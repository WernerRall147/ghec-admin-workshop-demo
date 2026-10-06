<#
.SYNOPSIS
    Simulates a third-party CI / security tool that reports its result to GitHub with the Commit Status API.

.DESCRIPTION
    Many external tools (SonarQube, Jenkins, security scanners, ...) report results back to GitHub by
    posting a commit status (POST /repos/{owner}/{repo}/statuses/{sha}). If the status "context" is
    configured as a required status check in a ruleset, the pull request cannot be merged until the
    tool reports "success".

    The script posts "pending", waits while the "scan" runs, then posts the final result.

.EXAMPLE
    ./Set-ExternalStatus.ps1 -Repo WernerRall147/ghec-admin-workshop-demo -PullRequest 2

.EXAMPLE
    ./Set-ExternalStatus.ps1 -Repo WernerRall147/ghec-admin-workshop-demo -PullRequest 2 -Result failure

.NOTES
    Requires the GitHub CLI (gh) authenticated with write access to commit statuses.
#>
[CmdletBinding(DefaultParameterSetName = 'PullRequest')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[^/\s]+/[^/\s]+$')]
    [string]$Repo,

    [Parameter(Mandatory, ParameterSetName = 'PullRequest')]
    [int]$PullRequest,

    [Parameter(Mandatory, ParameterSetName = 'Sha')]
    [ValidatePattern('^[0-9a-f]{7,40}$')]
    [string]$Sha,

    [ValidateSet('success', 'failure', 'error')]
    [string]$Result = 'success',

    [string]$Context = 'external/security-scan',

    [ValidateRange(0, 120)]
    [int]$ScanSeconds = 8,

    [string]$TargetUrl
)

$ErrorActionPreference = 'Stop'

# Retries transient network/API failures so a live demo survives a flaky connection.
function Invoke-GhWithRetry([string[]]$GhArgs, [int]$Attempts = 3) {
    for ($a = 1; $a -le $Attempts; $a++) {
        $out = & gh @GhArgs 2>&1
        if ($LASTEXITCODE -eq 0) { return $out }
        if ($a -lt $Attempts) {
            Write-Host "  (GitHub API call failed - retrying in $($a * 2)s)" -ForegroundColor DarkYellow
            Start-Sleep -Seconds ($a * 2)
        }
    }
    throw "gh $($GhArgs[0..1] -join ' ') failed after $Attempts attempts: $($out -join ' ')"
}

if ($PSCmdlet.ParameterSetName -eq 'PullRequest') {
    $commitSha = "$(Invoke-GhWithRetry @('pr', 'view', "$PullRequest", '--repo', $Repo, '--json', 'headRefOid', '--jq', '.headRefOid'))".Trim()
    if ($commitSha -notmatch '^[0-9a-f]{40}$') { throw "Could not find pull request #$PullRequest in $Repo" }
} else {
    $commitSha = $Sha
}

if (-not $TargetUrl) {
    $owner, $name = $Repo -split '/'
    $TargetUrl = "https://$($owner.ToLower()).github.io/$name/reports/security-scan.html"
}

function Set-CommitStatus([string]$State, [string]$Description) {
    $line = Invoke-GhWithRetry @('api', "repos/$Repo/statuses/$commitSha",
        '-f', "state=$State", '-f', "context=$Context", '-f', "description=$Description", '-f', "target_url=$TargetUrl",
        '--jq', '"  -> " + .state + "  [" + .context + "]  " + .description')
    Write-Host $line
}

Write-Host "External scanner picked up commit $($commitSha.Substring(0, 7)) in $Repo" -ForegroundColor Cyan
Set-CommitStatus -State 'pending' -Description 'Security scan in progress...'

for ($i = 1; $i -le $ScanSeconds; $i++) {
    Write-Progress -Activity 'Simulated third-party security scan' -Status "Scanning... $i/$ScanSeconds s" -PercentComplete ($i / [Math]::Max($ScanSeconds, 1) * 100)
    Start-Sleep -Seconds 1
}
Write-Progress -Activity 'Simulated third-party security scan' -Completed

$description = switch ($Result) {
    'success' { 'No critical findings' }
    'failure' { '2 critical findings - see report' }
    'error'   { 'Scanner could not complete' }
}
$colour = if ($Result -eq 'success') { 'Green' } else { 'Red' }
Set-CommitStatus -State $Result -Description $description

$combined = Invoke-GhWithRetry @('api', "repos/$Repo/commits/$commitSha/status", '--jq', '.state')
Write-Host "Combined commit status (all contexts) is now: $combined" -ForegroundColor $colour
