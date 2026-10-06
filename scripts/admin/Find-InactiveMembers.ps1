<#
.SYNOPSIS
    Finds organization members with no recorded contributions to the organization in the last N days,
    using a batched GraphQL query.

.DESCRIPTION
    This is an APPROXIMATION to help start a licence clean-up conversation. The authoritative source
    for licensing decisions is:  Enterprise > Compliance > Reports > Dormant users  (30-day definition,
    based on activities such as SSO sign-in, pushes to internal repos, PR activity, etc.).

    Contributions counted: commits, pull requests, pull request reviews, issues
    (plus "restricted" private contributions the token cannot see in detail).

.EXAMPLE
    ./Find-InactiveMembers.ps1 -Org my-org -Days 90

.EXAMPLE
    ./Find-InactiveMembers.ps1 -Org my-org -Days 60 | Where-Object Status -eq 'Inactive' | Export-Csv inactive.csv
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Org,

    [ValidateRange(1, 365)]
    [int]$Days = 90,

    [ValidateRange(1, 50)]
    [int]$BatchSize = 20
)

$ErrorActionPreference = 'Stop'

$membersQuery = @'
query($org: String!, $endCursor: String) {
  organization(login: $org) {
    id
    membersWithRole(first: 100, after: $endCursor) {
      pageInfo { hasNextPage endCursor }
      nodes { login name }
    }
  }
}
'@

$pages = gh api graphql --paginate --slurp -f query=$membersQuery -F org=$Org | ConvertFrom-Json -NoEnumerate
if ($LASTEXITCODE -ne 0 -or -not $pages) { throw "Could not read members of '$Org'" }
$orgId = $pages[0].data.organization.id
$members = @($pages | ForEach-Object { $_.data.organization.membersWithRole.nodes } | Where-Object { $_ })
Write-Host "$($members.Count) members in '$Org'. Checking contributions in the last $Days days..." -ForegroundColor Cyan

$from = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString('yyyy-MM-ddTHH:mm:ssZ')
$results = [System.Collections.Generic.List[object]]::new()

for ($i = 0; $i -lt $members.Count; $i += $BatchSize) {
    $batch = $members[$i..([Math]::Min($i + $BatchSize, $members.Count) - 1)]

    # One GraphQL request for the whole batch, using aliases (u0, u1, ...).
    $fields = for ($j = 0; $j -lt $batch.Count; $j++) {
        $login = $batch[$j].login
        if ($login -notmatch '^[A-Za-z0-9_-]+$') { continue }  # logins are inserted into the query text
        "u$($j): user(login: `"$login`") { login contributionsCollection(organizationID: `$orgId, from: `$from) { totalCommitContributions totalPullRequestContributions totalPullRequestReviewContributions totalIssueContributions restrictedContributionsCount } }"
    }
    $query = "query(`$orgId: ID!, `$from: DateTime!) {`n$($fields -join "`n")`n}"
    $response = gh api graphql -f query=$query -F orgId=$orgId -F from=$from | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw 'GraphQL batch query failed' }

    for ($j = 0; $j -lt $batch.Count; $j++) {
        $u = $response.data."u$j"
        if (-not $u) { continue }
        $c = $u.contributionsCollection
        $total = $c.totalCommitContributions + $c.totalPullRequestContributions + $c.totalPullRequestReviewContributions + $c.totalIssueContributions + $c.restrictedContributionsCount
        $results.Add([pscustomobject]@{
            Login      = $u.login
            Name       = $batch[$j].name
            Commits    = $c.totalCommitContributions
            PRs        = $c.totalPullRequestContributions
            Reviews    = $c.totalPullRequestReviewContributions
            Issues     = $c.totalIssueContributions
            Restricted = $c.restrictedContributionsCount
            Total      = $total
            Status     = if ($total -eq 0) { 'Inactive' } else { 'Active' }
        })
    }
}

$inactive = @($results | Where-Object Status -eq 'Inactive').Count
Write-Host "$inactive of $($results.Count) members have no contributions to '$Org' in the last $Days days." -ForegroundColor Yellow
Write-Host 'Confirm with the enterprise Dormant users report before removing anyone.' -ForegroundColor DarkGray
$results | Sort-Object Total, Login
