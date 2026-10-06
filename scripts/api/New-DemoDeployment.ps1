<#
.SYNOPSIS
    Demonstrates the Deployments API the way an external CD tool (Octopus, Azure Pipelines, Argo CD, ...)
    would use it: create a deployment for a ref, then report deployment statuses.

.DESCRIPTION
    GitHub Actions creates deployments automatically when a job targets an environment.
    External tools use the same API so that deployments, environments and their URLs show up on
    the repository home page and in pull requests.

.EXAMPLE
    ./New-DemoDeployment.ps1 -Repo WernerRall147/ghec-admin-workshop-demo

.EXAMPLE
    ./New-DemoDeployment.ps1 -Repo WernerRall147/ghec-admin-workshop-demo -Environment qa -Ref main -Fail
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[^/\s]+/[^/\s]+$')]
    [string]$Repo,

    [string]$Environment = 'qa',

    [string]$Ref = 'main',

    [switch]$Fail
)

$ErrorActionPreference = 'Stop'
$owner, $name = $Repo -split '/'
$envUrl = "https://$($owner.ToLower()).github.io/$name/?env=$Environment"

$body = @{
    ref               = $Ref
    environment       = $Environment
    description       = 'Deployment created by an external CD tool (demo)'
    auto_merge        = $false
    required_contexts = @()   # do not wait for commit statuses in this demo
    payload           = @{ tool = 'demo-cd'; triggeredBy = $env:USERNAME }
} | ConvertTo-Json -Depth 5

$deployment = $body | gh api "repos/$Repo/deployments" --method POST --input - | ConvertFrom-Json
if (-not $deployment.id) { throw "Deployment was not created: $($deployment | ConvertTo-Json -Compress)" }
Write-Host "Created deployment $($deployment.id) of '$Ref' ($($deployment.sha.Substring(0,7))) to '$Environment'" -ForegroundColor Cyan

function Set-DeploymentStatus([string]$State, [string]$Description) {
    $status = @{ state = $State; description = $Description; environment_url = $envUrl; log_url = "https://github.com/$Repo/deployments" } |
        ConvertTo-Json | gh api "repos/$Repo/deployments/$($deployment.id)/statuses" --method POST --input - | ConvertFrom-Json
    Write-Host "  -> $($status.state): $Description"
}

Set-DeploymentStatus 'queued' 'Waiting for a deployment agent'
Start-Sleep -Seconds 2
Set-DeploymentStatus 'in_progress' 'Rolling out...'
Start-Sleep -Seconds 4
if ($Fail) {
    Set-DeploymentStatus 'failure' 'Health check failed - rolled back'
} else {
    Set-DeploymentStatus 'success' "Live at $envUrl"
}

Write-Host "`nRecent deployments for '$Environment':" -ForegroundColor Cyan
gh api "repos/$Repo/deployments?environment=$Environment&per_page=5" --jq '.[] | "  #\(.id)  \(.ref)  \(.sha[0:7])  \(.created_at)"'
Write-Host "View them at https://github.com/$Repo/deployments"
