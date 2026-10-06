<#
.SYNOPSIS
    Governance snapshot of a GitHub organization: key settings, people, teams, repositories,
    Actions policy, rulesets, installed apps and webhooks - with recommendations.

.EXAMPLE
    ./Get-OrgSnapshot.ps1 -Org my-org

.EXAMPLE
    ./Get-OrgSnapshot.ps1 -Org my-org -OutFile ./my-org-snapshot.md

.NOTES
    Run as an organization owner for complete results. Sections you cannot read show "n/a".
    Webhooks need an extra scope:  gh auth refresh -h github.com -s admin:org_hook
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Org,

    [string]$OutFile,

    [int]$StaleDays = 365
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
function Show([object]$Value) { if ($null -eq $Value) { 'n/a' } else { "$Value" } }
function Count([object]$Items) { if ($null -eq $Items) { 'n/a' } else { @($Items).Count } }

Write-Host "Collecting snapshot for organization '$Org'..." -ForegroundColor Cyan
$o = Invoke-Gh "orgs/$Org"
if (-not $o) { throw "Organization '$Org' not found or not accessible with the current token" }

$members  = Invoke-Gh "orgs/$Org/members?per_page=100" -Paginate
$owners   = Invoke-Gh "orgs/$Org/members?role=admin&per_page=100" -Paginate
$outside  = Invoke-Gh "orgs/$Org/outside_collaborators?per_page=100" -Paginate
$invites  = Invoke-Gh "orgs/$Org/invitations?per_page=100" -Paginate
$teams    = Invoke-Gh "orgs/$Org/teams?per_page=100" -Paginate
$repos    = Invoke-Gh "orgs/$Org/repos?type=all&per_page=100" -Paginate
$actions  = Invoke-Gh "orgs/$Org/actions/permissions"
$wfPerms  = Invoke-Gh "orgs/$Org/actions/permissions/workflow"
$rulesets = Invoke-Gh "orgs/$Org/rulesets?per_page=100" -Paginate
$apps     = Invoke-Gh "orgs/$Org/installations?per_page=100"
$hooks    = Invoke-Gh "orgs/$Org/hooks?per_page=100" -Paginate

$recs = [System.Collections.Generic.List[string]]::new()
$ownerCount = Count $owners
$memberCount = Count $members
if ($ownerCount -is [int]) {
    if ($ownerCount -lt 2) { $recs.Add('Only one owner - add a second owner to avoid a single point of failure.') }
    if ($memberCount -is [int] -and $memberCount -gt 20 -and $ownerCount -gt [Math]::Max(3, $memberCount * 0.1)) {
        $recs.Add("$ownerCount owners for $memberCount members - reduce owners (least privilege).")
    }
}
if ($o.default_repository_permission -in 'write', 'admin') {
    $recs.Add("Base permission is '$($o.default_repository_permission)' - use 'read' or 'none' and grant access through teams.")
}
if ($o.members_can_create_public_repositories) { $recs.Add('Members can create PUBLIC repositories - restrict to avoid accidental exposure.') }
if ($o.two_factor_requirement_enabled -eq $false) { $recs.Add('2FA is not required - require 2FA (or enforce SAML SSO with MFA at the IdP).') }
if ($o.members_can_fork_private_repositories) { $recs.Add('Forking of private repositories is allowed - confirm this is intended.') }
if ((Count $outside) -is [int] -and (Count $outside) -gt 0) { $recs.Add("$(Count $outside) outside collaborators - review regularly; they consume licences.") }
if ((Count $invites) -is [int] -and (Count $invites) -gt 0) { $recs.Add("$(Count $invites) pending invitations - cancel stale ones.") }
if ($actions -and $actions.allowed_actions -eq 'all') { $recs.Add('All Actions are allowed - restrict to GitHub-owned, verified creators and an allow-list.') }
if ($wfPerms -and $wfPerms.default_workflow_permissions -eq 'write') { $recs.Add('Default GITHUB_TOKEN permission is read/write - set it to read-only.') }
if ($wfPerms -and $wfPerms.can_approve_pull_request_reviews) { $recs.Add('Actions can approve pull requests - disable unless required.') }
if ($null -ne $rulesets -and @($rulesets).Count -eq 0) { $recs.Add('No organization rulesets - protect default branches of all repositories centrally.') }

$repoList = @($repos)
$staleRepos = @($repoList | Where-Object { -not $_.archived -and $_.pushed_at -and ((Get-Date) - [datetime]$_.pushed_at).TotalDays -gt $StaleDays })
if ($staleRepos.Count -gt 0) { $recs.Add("$($staleRepos.Count) repositories without a push for $StaleDays+ days - review and archive.") }

$md = [System.Collections.Generic.List[string]]::new()
$md.Add("# Organization snapshot: $Org")
$md.Add("_Generated $((Get-Date).ToString('yyyy-MM-dd HH:mm')) by $((gh api user --jq .login))_")
$md.Add('')
$md.Add('## Key settings')
$md.Add('| Setting | Value |')
$md.Add('|---|---|')
$md.Add("| Plan | $(Show $o.plan.name) |")
$md.Add("| Base (default) repository permission | $(Show $o.default_repository_permission) |")
$md.Add("| Members can create repositories | $(Show $o.members_can_create_repositories) |")
$md.Add("| ...public / private / internal | $(Show $o.members_can_create_public_repositories) / $(Show $o.members_can_create_private_repositories) / $(Show $o.members_can_create_internal_repositories) |")
$md.Add("| Members can fork private repositories | $(Show $o.members_can_fork_private_repositories) |")
$md.Add("| 2FA required | $(Show $o.two_factor_requirement_enabled) |")
$md.Add("| Web commit sign-off required | $(Show $o.web_commit_signoff_required) |")
$md.Add('')
$md.Add('## People')
$md.Add("| Members | Owners | Outside collaborators | Pending invitations |")
$md.Add('|---:|---:|---:|---:|')
$md.Add("| $memberCount | $ownerCount | $(Count $outside) | $(Count $invites) |")
if ($owners) { $md.Add(''); $md.Add("Owners: $((@($owners) | ForEach-Object login) -join ', ')") }
$md.Add('')
$md.Add("## Teams ($(Count $teams))")
if ($teams) {
    $md.Add('| Team | Parent | Privacy | Description |')
    $md.Add('|---|---|---|---|')
    foreach ($t in @($teams)) { $md.Add("| $($t.name) | $(if ($t.parent) { $t.parent.name } else { '-' }) | $($t.privacy) | $($t.description) |") }
}
$md.Add('')
$md.Add("## Repositories ($(Count $repos))")
if ($repos) {
    $byVis = $repoList | Group-Object visibility | ForEach-Object { "$($_.Name): $($_.Count)" }
    $md.Add("Visibility: $($byVis -join ', ') | Archived: $(@($repoList | Where-Object archived).Count) | Forks: $(@($repoList | Where-Object fork).Count) | Stale ($StaleDays+ days): $($staleRepos.Count)")
}
$md.Add('')
$md.Add('## GitHub Actions policy')
$md.Add("| Enabled repositories | Allowed actions | Default GITHUB_TOKEN | Actions can approve PRs |")
$md.Add('|---|---|---|---|')
$md.Add("| $(Show $actions.enabled_repositories) | $(Show $actions.allowed_actions) | $(Show $wfPerms.default_workflow_permissions) | $(Show $wfPerms.can_approve_pull_request_reviews) |")
$md.Add('')
$md.Add("## Organization rulesets ($(Count $rulesets))")
foreach ($rs in @($rulesets | Where-Object { $_ })) { $md.Add("- $($rs.name) - $($rs.target) - $($rs.enforcement)") }
$md.Add('')
$appList = if ($apps) { @($apps.installations) } else { $null }
$md.Add("## Installed GitHub Apps ($(Count $appList))")
foreach ($a in @($appList | Where-Object { $_ })) { $md.Add("- $($a.app_slug) - repositories: $($a.repository_selection) - created $(([datetime]$a.created_at).ToString('yyyy-MM-dd'))") }
$md.Add('')
$md.Add("## Organization webhooks ($(Count $hooks))")
foreach ($h in @($hooks | Where-Object { $_ })) { $md.Add("- $($h.config.url) - events: $($h.events -join ', ') - active: $($h.active)") }
$md.Add('')
$md.Add('## Recommendations')
if ($recs.Count -eq 0) { $md.Add('- No issues detected by the automated checks.') }
foreach ($rec in $recs) { $md.Add("- $rec") }

$text = $md -join [Environment]::NewLine
if ($OutFile) {
    $text | Out-File -FilePath $OutFile -Encoding utf8
    Write-Host "Snapshot written to $OutFile" -ForegroundColor Green
}
$text
