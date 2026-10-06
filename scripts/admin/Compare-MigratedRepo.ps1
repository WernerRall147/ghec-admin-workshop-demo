<#
.SYNOPSIS
    Validates a repository migration by comparing every branch and tag (and its commit SHA) between
    the source (e.g. GitLab) and the target (GitHub). No clone needed - uses git ls-remote.

.DESCRIPTION
    If every branch and tag points to the same commit SHA on both sides, the full Git history was
    migrated faithfully. Typical problems this catches in manual migrations:
      * only the default branch was pushed (other branches / tags missing)
      * history was rewritten or squashed (SHA mismatch)
      * the default branch differs (e.g. master vs main)

    Note: Git refs only. Merge requests, issues, CI variables, protected-branch settings and
    permissions are NOT migrated by a plain "git push --mirror" - use GitHub Enterprise Importer
    for metadata, and re-create settings with scripts/admin/Set-RepoBaseline.ps1.

.EXAMPLE
    ./Compare-MigratedRepo.ps1 -Source https://gitlab.example.com/group/app.git -Target https://github.com/my-org/app.git

.EXAMPLE
    # Validate many repositories from a CSV with columns Source,Target
    Import-Csv migrations.csv | ForEach-Object { ./Compare-MigratedRepo.ps1 -Source $_.Source -Target $_.Target -Quiet }
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Source,

    [Parameter(Mandatory)]
    [string]$Target,

    # Only print the summary line
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

function Get-RemoteRefs([string]$Url) {
    $lines = git ls-remote $Url 'refs/heads/*' 'refs/tags/*' 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git ls-remote failed for $($Url): $($lines -join ' ')" }
    $refs = @{}
    foreach ($line in $lines) {
        $sha, $ref = "$line" -split "`t"
        if ($ref) { $refs[$ref] = $sha }
    }
    $refs
}

function Get-DefaultBranch([string]$Url) {
    $line = git ls-remote --symref $Url HEAD 2>$null | Select-Object -First 1
    if ("$line" -match '^ref:\s+refs/heads/(\S+)') { $Matches[1] } else { '?' }
}

$src = Get-RemoteRefs $Source
$dst = Get-RemoteRefs $Target

$rows = foreach ($ref in ($src.Keys + $dst.Keys | Sort-Object -Unique)) {
    $s = $src[$ref]; $d = $dst[$ref]
    $status = if (-not $d) { 'MISSING IN TARGET' } elseif (-not $s) { 'EXTRA IN TARGET' } elseif ($s -ne $d) { 'DIFFERENT COMMIT' } else { 'OK' }
    [pscustomobject]@{
        Ref    = $ref -replace '^refs/(heads|tags)/', ''
        Type   = if ($ref -like 'refs/tags/*') { 'tag' } else { 'branch' }
        Source = if ($s) { $s.Substring(0, 7) } else { '-' }
        Target = if ($d) { $d.Substring(0, 7) } else { '-' }
        Status = $status
    }
}

$srcDefault = Get-DefaultBranch $Source
$dstDefault = Get-DefaultBranch $Target
$problems = @($rows | Where-Object Status -ne 'OK')
$count = { param($refs, $type) @($refs.Keys | Where-Object { $_ -like "refs/$type/*" -and $_ -notlike '*^{}' }).Count }

if (-not $Quiet) {
    Write-Host "`nSource: $Source" -ForegroundColor Cyan
    Write-Host "Target: $Target" -ForegroundColor Cyan
    [pscustomobject]@{
        'Branches (src/dst)'     = "$(& $count $src 'heads') / $(& $count $dst 'heads')"
        'Tags (src/dst)'         = "$(& $count $src 'tags') / $(& $count $dst 'tags')"
        'Default branch (src/dst)' = "$srcDefault / $dstDefault"
        'Refs with problems'     = $problems.Count
    } | Format-List | Out-Host
    if ($problems.Count -gt 0) {
        $problems | Format-Table -AutoSize | Out-Host
    }
    if ($srcDefault -ne $dstDefault) {
        Write-Host "Default branch differs ($srcDefault vs $dstDefault) - intended rename, or a migration mistake?" -ForegroundColor Yellow
    }
}

$ok = $problems.Count -eq 0
$colour = if ($ok) { 'Green' } else { 'Red' }
$verdict = if ($ok) { 'PASS - all branches and tags match' } else { "FAIL - $($problems.Count) ref(s) differ" }
Write-Host "$verdict  [$Target]" -ForegroundColor $colour
if (-not $ok) { $global:LASTEXITCODE = 1 }
