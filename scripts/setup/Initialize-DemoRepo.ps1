<#
.SYNOPSIS
    Configures the demo repository on GitHub for the workshop. Idempotent - re-run it at any time
    to restore the expected state (it does not touch existing pull requests; see New-DemoPullRequests.ps1).

.DESCRIPTION
    * Repository settings, topics, template flag, labels, variable
    * Environments: staging, production (required reviewer, main only, environment secret)
    * GitHub Pages (built by GitHub Actions)
    * Baseline: merge settings, security features, "main-protection" ruleset with required checks
    * "release-tags" tag ruleset and a classic branch protection rule for release/* (for comparison)
    * Release v1.0.0, demo issues and a project board

.EXAMPLE
    ./Initialize-DemoRepo.ps1 -Repo WernerRall147/ghec-admin-workshop-demo
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[^/\s]+/[^/\s]+$')]
    [string]$Repo = 'WernerRall147/ghec-admin-workshop-demo'
)

$ErrorActionPreference = 'Stop'
$owner, $name = $Repo -split '/'
$me = gh api user | ConvertFrom-Json
$pagesUrl = "https://$($owner.ToLower()).github.io/$name/"

function Invoke-GhJson([string]$Method, [string]$Path, $Body) {
    if ($null -ne $Body) {
        $out = $Body | ConvertTo-Json -Depth 10 | gh api --method $Method $Path --input - 2>&1
    } else {
        $out = gh api --method $Method $Path 2>&1
    }
    [pscustomobject]@{ Ok = ($LASTEXITCODE -eq 0); Output = ($out -join "`n") }
}
function Step([string]$Text) { Write-Host "`n== $Text" -ForegroundColor Cyan }

Step 'Repository settings'
gh repo edit $Repo --description 'Demo & template repository for a GitHub Enterprise Cloud admin workshop: rulesets, required checks, Status API, CODEOWNERS, environments, webhooks, API scripts.' `
    --homepage $pagesUrl --template --enable-issues --enable-projects --enable-discussions --enable-wiki=false `
    --add-topic 'github-enterprise,github-administration,workshop,rulesets,github-actions,github-api'

Step 'Labels'
$labels = @(
    @('type/bug', 'd73a4a', 'Something is not working'),
    @('type/feature', 'a2eeef', 'New feature or request'),
    @('triage', 'fbca04', 'Needs triage'),
    @('dependencies', '0366d6', 'Dependency updates'),
    @('area/ci', '1d76db', 'CI/CD and workflows'),
    @('area/security', 'b60205', 'Security related'),
    @('area/docs', '0e8a16', 'Documentation'),
    @('area/governance', '5319e7', 'Administration and governance')
)
foreach ($l in $labels) { gh label create $l[0] --color $l[1] --description $l[2] --repo $Repo --force | Out-Null }
Write-Host "  $($labels.Count) labels"

Step 'Variables and environments'
gh variable set APP_NAME --body 'marks-service' --repo $Repo
Invoke-GhJson PUT "repos/$Repo/environments/staging" @{} | Out-Null
$prod = Invoke-GhJson PUT "repos/$Repo/environments/production" @{
    wait_timer               = 0
    prevent_self_review      = $false
    reviewers                = @(@{ type = 'User'; id = $me.id })
    deployment_branch_policy = @{ protected_branches = $false; custom_branch_policies = $true }
}
if (-not $prod.Ok) { Write-Warning $prod.Output }
$policies = gh api "repos/$Repo/environments/production/deployment-branch-policies" --jq '.branch_policies[].name'
if ('main' -notin $policies) { Invoke-GhJson POST "repos/$Repo/environments/production/deployment-branch-policies" @{ name = 'main'; type = 'branch' } | Out-Null }
'demo-not-a-real-secret' | gh secret set DEPLOY_API_KEY --env production --repo $Repo
Write-Host '  staging, production (reviewer + main only + secret DEPLOY_API_KEY)'

Step 'GitHub Pages (workflow)'
$pages = Invoke-GhJson GET "repos/$Repo/pages"
if ($pages.Ok) {
    Invoke-GhJson PUT "repos/$Repo/pages" @{ build_type = 'workflow' } | Out-Null
} else {
    $r = Invoke-GhJson POST "repos/$Repo/pages" @{ build_type = 'workflow' }
    if (-not $r.Ok) { Write-Warning $r.Output }
}
Write-Host "  $pagesUrl"

Step 'Baseline: merge settings, security, main-protection ruleset'
& (Join-Path $PSScriptRoot '..\admin\Set-RepoBaseline.ps1') -Repo $Repo -RulesetName 'main-protection' `
    -RequiredChecks 'build-and-test', 'external/security-scan' -RequireCodeOwnerReview -AdminBypass pull_request

Step 'Tag ruleset release-tags'
$tagRuleset = @{
    name          = 'release-tags'
    target        = 'tag'
    enforcement   = 'active'
    conditions    = @{ ref_name = @{ include = @('refs/tags/v*'); exclude = @() } }
    bypass_actors = @(@{ actor_id = 5; actor_type = 'RepositoryRole'; bypass_mode = 'always' })
    rules         = @(@{ type = 'deletion' }, @{ type = 'non_fast_forward' }, @{ type = 'update' })
}
$existing = gh api "repos/$Repo/rulesets" --jq '.[] | select(.name == "release-tags") | .id'
if ($existing) { Invoke-GhJson PUT "repos/$Repo/rulesets/$existing" $tagRuleset | Out-Null } else { Invoke-GhJson POST "repos/$Repo/rulesets" $tagRuleset | Out-Null }
Write-Host '  v* tags cannot be moved or deleted (admins may bypass)'

Step 'Classic branch protection on release/* (for comparison with rulesets)'
$mainSha = gh api "repos/$Repo/git/ref/heads/main" --jq '.object.sha'
gh api "repos/$Repo/git/ref/heads/release/1.x" *> $null
if ($LASTEXITCODE -ne 0) { gh api "repos/$Repo/git/refs" -f ref='refs/heads/release/1.x' -f sha=$mainSha | Out-Null }
$repoId = gh api "repos/$Repo" --jq '.node_id'
$patterns = gh api graphql -f query='query($o:String!,$n:String!){repository(owner:$o,name:$n){branchProtectionRules(first:20){nodes{pattern}}}}' -F o=$owner -F n=$name --jq '.data.repository.branchProtectionRules.nodes[].pattern'
if ('release/*' -notin $patterns) {
    $mutation = 'mutation($id:ID!){createBranchProtectionRule(input:{repositoryId:$id,pattern:"release/*",requiresApprovingReviews:true,requiredApprovingReviewCount:1,requiresStatusChecks:true,requiredStatusCheckContexts:["build-and-test"],allowsForcePushes:false,allowsDeletions:false}){branchProtectionRule{pattern}}}'
    gh api graphql -f query=$mutation -F id=$repoId | Out-Null
}
Write-Host '  release/* protected with a classic rule; branch release/1.x exists'

Step 'Release v1.0.0'
gh release view v1.0.0 --repo $Repo *> $null
if ($LASTEXITCODE -ne 0) { gh release create v1.0.0 --repo $Repo --target main --title 'v1.0.0' --generate-notes | Out-Null }
Write-Host '  v1.0.0'

Step 'Demo issues'
$issues = @(
    @{ title = 'Map existing groups to GitHub teams'; label = 'area/governance'; body = "Design the team structure (parent/child teams) and decide which teams get which repository roles.`n`n- [ ] Inventory current groups`n- [ ] Decide on team sync with the identity provider`n- [ ] Grant repository access to teams, not individuals" },
    @{ title = 'Enable secret scanning push protection for all repositories'; label = 'area/security'; body = 'Turn on push protection at organization level via a security configuration, and decide who may bypass it.' },
    @{ title = 'Final mark is not rounded correctly for three components'; label = 'type/bug'; body = "Weights 33.3 / 33.3 / 33.4 give an unexpected result.`n`n**Steps**: call finalMark() with three components." },
    @{ title = 'Document the release process'; label = 'area/docs'; body = 'Describe how tags v* are protected by the release-tags ruleset and who can create releases.' }
)
$existingTitles = gh issue list --repo $Repo --state all --limit 100 --json title --jq '.[].title'
$created = @()
foreach ($i in $issues) {
    if ($i.title -notin $existingTitles) {
        $created += gh issue create --repo $Repo --title $i.title --body $i.body --label $i.label
    }
}
Write-Host "  $($created.Count) new issue(s)"

Step 'Project board'
$projTitle = 'GHEC Admin Workshop - demo board'
$proj = gh project list --owner $owner --format json --limit 100 | ConvertFrom-Json
$number = ($proj.projects | Where-Object title -eq $projTitle | Select-Object -First 1).number
if (-not $number) {
    $number = (gh project create --owner $owner --title $projTitle --format json | ConvertFrom-Json).number
    gh project link $number --owner $owner --repo $name | Out-Null
}
foreach ($url in (gh issue list --repo $Repo --state open --limit 50 --json url --jq '.[].url')) {
    gh project item-add $number --owner $owner --url $url *> $null
}
Write-Host "  project #$number"

Write-Host "`nDone. Repository: https://github.com/$Repo  |  Pages: $pagesUrl" -ForegroundColor Green
