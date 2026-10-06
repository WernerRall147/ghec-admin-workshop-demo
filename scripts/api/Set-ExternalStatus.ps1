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

if ($PSCmdlet.ParameterSetName -eq 'PullRequest') {
    $Sha = gh pr view $PullRequest --repo $Repo --json headRefOid --jq .headRefOid
    if ($LASTEXITCODE -ne 0 -or -not $Sha) { throw "Could not find pull request #$PullRequest in $Repo" }
}

if (-not $TargetUrl) {
    $owner, $name = $Repo -split '/'
    $TargetUrl = "https://$($owner.ToLower()).github.io/$name/reports/security-scan.html"
}

function Set-CommitStatus([string]$State, [string]$Description) {
    $line = gh api "repos/$Repo/statuses/$Sha" `
        -f state=$State -f context=$Context -f description=$Description -f target_url=$TargetUrl `
        --jq '"  -> " + .state + "  [" + .context + "]  " + .description'
    if ($LASTEXITCODE -ne 0) { throw "Failed to post status '$State'" }
    Write-Host $line
}

Write-Host "External scanner picked up commit $($Sha.Substring(0, 7)) in $Repo" -ForegroundColor Cyan
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

$combined = gh api "repos/$Repo/commits/$Sha/status" --jq '.state'
Write-Host "Combined commit status (all contexts) is now: $combined" -ForegroundColor $colour
