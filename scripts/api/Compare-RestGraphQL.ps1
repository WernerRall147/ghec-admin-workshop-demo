<#
.SYNOPSIS
    Retrieves the same repository information with the REST API and with GraphQL, and compares
    the number of API calls, the rate-limit cost and the elapsed time.

.DESCRIPTION
    REST:    1 call to list repositories + 1 call per repository to count open PRs  =>  1 + N calls
             (and every response returns ~100 fields we do not need)
    GraphQL: 1 query that asks for exactly the fields we need, nested           =>  1 call

.EXAMPLE
    ./Compare-RestGraphQL.ps1 -Owner WernerRall147 -Top 8 -PublicOnly

.EXAMPLE
    ./Compare-RestGraphQL.ps1 -Owner my-org -Top 25
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Owner,

    [ValidateRange(1, 50)]
    [int]$Top = 10,

    # Only include public repositories (handy when presenting on a shared screen)
    [switch]$PublicOnly
)

$ErrorActionPreference = 'Stop'

function Get-RateLimit {
    gh api rate_limit --jq '{core: .resources.core.remaining, graphql: .resources.graphql.remaining}' | ConvertFrom-Json
}

$me = gh api user --jq '.login'
$ownerType = gh api "users/$Owner" --jq '.type'
if ($ownerType -eq 'Organization') {
    $type = if ($PublicOnly) { 'public' } else { 'all' }
    $restPath = "orgs/$Owner/repos?type=$type&sort=pushed&direction=desc&per_page=$Top"
} elseif ($Owner -eq $me -and -not $PublicOnly) {
    $restPath = "user/repos?affiliation=owner&sort=pushed&direction=desc&per_page=$Top"
} else {
    # Other users' repositories: REST only returns public ones, so compare like with like.
    $restPath = "users/$Owner/repos?type=owner&sort=pushed&direction=desc&per_page=$Top"
    $PublicOnly = $true
}
$privacy = if ($PublicOnly) { 'PUBLIC' } else { 'null' }

# ---------------------------------------------------------------- REST
Write-Host "`n=== REST API ===" -ForegroundColor Cyan
$before = Get-RateLimit
$sw = [Diagnostics.Stopwatch]::StartNew()
$calls = 0

$repos = gh api $restPath | ConvertFrom-Json
$calls++
$restRows = foreach ($r in $repos) {
    # REST's open_issues_count includes pull requests, so PRs need one extra call per repository.
    $prs = @(gh api "repos/$($r.full_name)/pulls?state=open&per_page=100" | ConvertFrom-Json).Count
    $calls++
    [pscustomobject]@{
        Repository    = $r.name
        Visibility    = $r.visibility
        DefaultBranch = $r.default_branch
        OpenPRs       = $prs
        OpenIssues    = [int]$r.open_issues_count - $prs
        LastPush      = ([datetime]$r.pushed_at).ToString('yyyy-MM-dd')
    }
}
$sw.Stop()
$after = Get-RateLimit
$restResult = [pscustomobject]@{ Api = 'REST'; Calls = $calls; Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1); RateLimitUsed = $before.core - $after.core }
$restRows | Format-Table -AutoSize | Out-Host

# ---------------------------------------------------------------- GraphQL
Write-Host "=== GraphQL API ===" -ForegroundColor Cyan
$query = @'
query($login: String!, $top: Int!, $privacy: RepositoryPrivacy) {
  repositoryOwner(login: $login) {
    repositories(first: $top, privacy: $privacy, ownerAffiliations: [OWNER], orderBy: {field: PUSHED_AT, direction: DESC}) {
      nodes {
        name
        visibility
        defaultBranchRef { name }
        pullRequests(states: OPEN) { totalCount }
        issues(states: OPEN) { totalCount }
        pushedAt
      }
    }
  }
  rateLimit { cost remaining }
}
'@
$before = Get-RateLimit
$sw = [Diagnostics.Stopwatch]::StartNew()
$data = gh api graphql -f query=$query -F login=$Owner -F top=$Top -F privacy=$privacy | ConvertFrom-Json
$sw.Stop()
$gqlRows = foreach ($n in $data.data.repositoryOwner.repositories.nodes) {
    [pscustomobject]@{
        Repository    = $n.name
        Visibility    = $n.visibility.ToLower()
        DefaultBranch = $n.defaultBranchRef.name
        OpenPRs       = $n.pullRequests.totalCount
        OpenIssues    = $n.issues.totalCount
        LastPush      = ([datetime]$n.pushedAt).ToString('yyyy-MM-dd')
    }
}
$gqlRows | Format-Table -AutoSize | Out-Host
$gqlResult = [pscustomobject]@{ Api = 'GraphQL'; Calls = 1; Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1); RateLimitUsed = $data.data.rateLimit.cost }

Write-Host "=== Comparison ===" -ForegroundColor Cyan
@($restResult, $gqlResult) | Format-Table -AutoSize | Out-Host
Write-Host 'REST rate limit is counted in requests (5,000/hour for a user token); GraphQL is counted in query cost points (5,000 points/hour).' -ForegroundColor DarkGray
