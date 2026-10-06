<#
.SYNOPSIS
    Repository health report for an organization or user: protection, ownership, staleness,
    size, branch sprawl and open Dependabot alerts.

.EXAMPLE
    ./Get-RepoHealthReport.ps1 -Owner my-org -Top 100

.EXAMPLE
    ./Get-RepoHealthReport.ps1 -Owner my-org -Format Csv | Out-File repo-health.csv

.EXAMPLE
    ./Get-RepoHealthReport.ps1 -Owner WernerRall147 -Repo ghec-admin-workshop-demo,ghec-admin-workshop-unhealthy
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Owner,

    # Optional subset of repository names (without owner)
    [string[]]$Repo,

    [ValidateRange(1, 1000)]
    [int]$Top = 50,

    [int]$StaleDays = 180,

    [int]$MaxBranches = 50,

    [ValidateSet('Table', 'Markdown', 'Csv', 'Object')]
    [string]$Format = 'Table'
)

$ErrorActionPreference = 'Stop'

function Invoke-Gh {
    param([Parameter(Mandatory)][string]$Path, [switch]$Paginate)
    $ghArgs = @('api', $Path)
    if ($Paginate) { $ghArgs += @('--paginate', '--slurp') }
    $out = & gh @ghArgs 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    $json = $out -join "`n"
    if ([string]::IsNullOrWhiteSpace($json)) { return $null }
    $obj = ConvertFrom-Json -InputObject $json -NoEnumerate
    if ($Paginate) { $obj = @($obj | ForEach-Object { $_ }) }
    # The leading comma stops PowerShell from unrolling arrays, so callers can tell
    # an empty result (@()) from a failed call ($null).
    return , $obj
}

if ($Repo) {
    $repos = foreach ($name in $Repo) { Invoke-Gh "repos/$Owner/$name" }
} else {
    $type = (Invoke-Gh "users/$Owner").type
    $listPath = if ($type -eq 'Organization') { "orgs/$Owner/repos" } else { "users/$Owner/repos" }
    if ($Top -le 100) {
        $repos = Invoke-Gh "$($listPath)?sort=pushed&direction=desc&per_page=$Top"
    } else {
        $repos = (Invoke-Gh "$($listPath)?sort=pushed&direction=desc&per_page=100" -Paginate) | Select-Object -First $Top
    }
}

$now = Get-Date
$report = foreach ($r in @($repos | Where-Object { $_ })) {
    $full = $r.full_name
    $branch = $r.default_branch
    $findings = [System.Collections.Generic.List[string]]::new()

    $branchInfo = Invoke-Gh "repos/$full/branches/$branch"
    $rules = Invoke-Gh "repos/$full/rules/branches/$branch"
    $ruleCount = if ($rules) { @($rules).Count } else { 0 }
    $protected = [bool]$branchInfo.protected -or $ruleCount -gt 0
    $requiresPr = @($rules | Where-Object { $_.type -eq 'pull_request' }).Count -gt 0 -or [bool]$branchInfo.protection.required_pull_request_reviews
    if (-not $protected) { $findings.Add('Default branch not protected') }
    elseif (-not $requiresPr) { $findings.Add('No PR required on default branch') }

    $hasReadme = $null -ne (Invoke-Gh "repos/$full/readme")
    if (-not $hasReadme) { $findings.Add('No README') }

    $hasCodeowners = $null -ne (Invoke-Gh "repos/$full/codeowners/errors")
    if (-not $hasCodeowners) { $findings.Add('No CODEOWNERS') }

    $branches = Invoke-Gh "repos/$full/branches?per_page=100" -Paginate
    $branchCount = if ($null -eq $branches) { 0 } else { $branches.Count }
    if ($branchCount -gt $MaxBranches) { $findings.Add("$branchCount branches (prune stale ones)") }

    $daysSincePush = [int]($now - [datetime]$r.pushed_at).TotalDays
    if (-not $r.archived -and $daysSincePush -gt $StaleDays) { $findings.Add("No push for $daysSincePush days (archive?)") }

    $sizeMb = [math]::Round($r.size / 1024, 1)
    if ($sizeMb -ge 10240) { $findings.Add("Very large ($sizeMb MB)") }
    elseif ($sizeMb -ge 1024) { $findings.Add("Large ($sizeMb MB) - review binaries / Git LFS") }

    $alerts = Invoke-Gh "repos/$full/dependabot/alerts?state=open&per_page=100" -Paginate
    $alertCount = if ($null -eq $alerts) { 'n/a' } else { $alerts.Count }
    if ($alertCount -is [int] -and $alertCount -gt 0) { $findings.Add("$alertCount open Dependabot alerts") }

    $health = switch ($findings.Count) {
        0 { 'Healthy' }
        { $_ -le 2 } { 'Attention' }
        default { 'Unhealthy' }
    }
    if ($r.archived) { $health = 'Archived' }

    [pscustomobject]@{
        Repository   = $r.name
        Visibility   = $r.visibility
        Health       = $health
        SizeMB       = $sizeMb
        Branches     = $branchCount
        DaysSincePush = $daysSincePush
        Protected    = $protected
        CODEOWNERS   = $hasCodeowners
        DependabotAlerts = $alertCount
        Findings     = ($findings -join '; ')
    }
}

switch ($Format) {
    'Object' { $report }
    'Csv'    { $report | ConvertTo-Csv -NoTypeInformation }
    'Table'  { $report | Format-Table Repository, Visibility, Health, SizeMB, Branches, DaysSincePush, Protected, CODEOWNERS, DependabotAlerts -AutoSize; $report | Where-Object Findings | Format-List Repository, Findings }
    'Markdown' {
        "## Repository health report - $Owner"
        ""
        "_Generated $($now.ToString('yyyy-MM-dd HH:mm')) - stale threshold $StaleDays days_"
        ""
        "| Repository | Visibility | Health | Size (MB) | Branches | Days since push | Protected | CODEOWNERS | Dependabot alerts | Findings |"
        "|---|---|---|---:|---:|---:|---|---|---:|---|"
        foreach ($row in $report) {
            "| $($row.Repository) | $($row.Visibility) | $($row.Health) | $($row.SizeMB) | $($row.Branches) | $($row.DaysSincePush) | $($row.Protected) | $($row.CODEOWNERS) | $($row.DependabotAlerts) | $($row.Findings) |"
        }
    }
}

# API failures above are handled (reported as n/a); don't leak the last native exit code to callers/CI.
$global:LASTEXITCODE = 0
