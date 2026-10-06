<#
.SYNOPSIS
    Applies a governance baseline to a repository: merge settings, security features and a
    default-branch ruleset. Safe to re-run (idempotent).

.DESCRIPTION
    Use it to bring migrated repositories up to standard in bulk, e.g.:

        gh repo list my-org --limit 500 --json nameWithOwner --jq '.[].nameWithOwner' |
            ForEach-Object { ./Set-RepoBaseline.ps1 -Repo $_ -RequiredChecks build -WhatIf }

    Baseline applied:
      * Squash/rebase merges only, delete head branches after merge, auto-merge allowed, wiki off
      * Dependabot alerts + security updates, secret scanning + push protection, CodeQL default setup
        (private/internal repos need GitHub Secret Protection / Code Security licences for the last two)
      * Ruleset on the default branch: no deletion, no force-push, PR + approvals required,
        optional code-owner review and required status checks

.EXAMPLE
    ./Set-RepoBaseline.ps1 -Repo my-org/my-repo -RequiredChecks build-and-test -RequireCodeOwnerReview

.EXAMPLE
    ./Set-RepoBaseline.ps1 -Repo my-org/my-repo -Enforcement evaluate   # dry-run the ruleset (GHEC)
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[^/\s]+/[^/\s]+$')]
    [string]$Repo,

    [string[]]$RequiredChecks = @(),

    [ValidateRange(0, 6)]
    [int]$RequiredApprovals = 1,

    [switch]$RequireCodeOwnerReview,

    [string]$RulesetName = 'baseline-default-branch',

    [ValidateSet('active', 'evaluate', 'disabled')]
    [string]$Enforcement = 'active',

    # Who may bypass the ruleset: repository admins only via pull requests (default), always, or nobody.
    [ValidateSet('pull_request', 'always', 'none')]
    [string]$AdminBypass = 'pull_request',

    [switch]$SkipSecurity,

    [switch]$SkipMergeSettings
)

$ErrorActionPreference = 'Stop'

function Invoke-GhJson {
    param([string]$Method, [string]$Path, $Body)
    $ghArgs = @('api', '--method', $Method, $Path)
    if ($null -ne $Body) {
        $out = $Body | ConvertTo-Json -Depth 10 | & gh @ghArgs --input - 2>&1
    } else {
        $out = & gh @ghArgs 2>&1
    }
    [pscustomobject]@{ Ok = ($LASTEXITCODE -eq 0); Output = ($out -join "`n") }
}

function Write-Result([string]$Step, $Result) {
    if ($Result.Ok) {
        Write-Host "  [ok]   $Step" -ForegroundColor Green
    } else {
        $msg = ($Result.Output -split "`n" | Select-Object -First 1)
        Write-Host "  [skip] $Step - $msg" -ForegroundColor Yellow
    }
}

$repoInfo = gh api "repos/$Repo" | ConvertFrom-Json
if (-not $repoInfo) { throw "Repository $Repo not found or not accessible" }
Write-Host "Applying baseline to $Repo ($($repoInfo.visibility), default branch '$($repoInfo.default_branch)')" -ForegroundColor Cyan

if (-not $SkipMergeSettings -and $PSCmdlet.ShouldProcess($Repo, 'Configure merge settings')) {
    $r = Invoke-GhJson PATCH "repos/$Repo" @{
        allow_merge_commit     = $false
        allow_squash_merge     = $true
        allow_rebase_merge     = $true
        delete_branch_on_merge = $true
        allow_auto_merge       = $true
        allow_update_branch    = $true
        has_wiki               = $false
    }
    Write-Result 'Merge settings (squash/rebase only, auto-delete branches, wiki off)' $r
}

if (-not $SkipSecurity -and $PSCmdlet.ShouldProcess($Repo, 'Enable security features')) {
    Write-Result 'Dependabot alerts' (Invoke-GhJson PUT "repos/$Repo/vulnerability-alerts")
    Write-Result 'Dependabot security updates' (Invoke-GhJson PUT "repos/$Repo/automated-security-fixes")
    Write-Result 'Secret scanning + push protection' (Invoke-GhJson PATCH "repos/$Repo" @{
        security_and_analysis = @{
            secret_scanning                 = @{ status = 'enabled' }
            secret_scanning_push_protection = @{ status = 'enabled' }
        }
    })
    Write-Result 'Code scanning (CodeQL default setup)' (Invoke-GhJson PATCH "repos/$Repo/code-scanning/default-setup" @{ state = 'configured' })
    if ($repoInfo.visibility -eq 'public') {
        Write-Result 'Private vulnerability reporting' (Invoke-GhJson PUT "repos/$Repo/private-vulnerability-reporting")
    }
}

$rules = @(
    @{ type = 'deletion' }
    @{ type = 'non_fast_forward' }
    @{
        type       = 'pull_request'
        parameters = @{
            required_approving_review_count   = $RequiredApprovals
            dismiss_stale_reviews_on_push     = $true
            require_code_owner_review         = [bool]$RequireCodeOwnerReview
            require_last_push_approval        = $false
            required_review_thread_resolution = $true
            allowed_merge_methods             = @('squash', 'rebase')
        }
    }
)
if ($RequiredChecks.Count -gt 0) {
    $rules += @{
        type       = 'required_status_checks'
        parameters = @{
            strict_required_status_checks_policy = $false
            do_not_enforce_on_create             = $false
            required_status_checks               = @($RequiredChecks | ForEach-Object { @{ context = $_ } })
        }
    }
}

$ruleset = @{
    name          = $RulesetName
    target        = 'branch'
    enforcement   = $Enforcement
    conditions    = @{ ref_name = @{ include = @('~DEFAULT_BRANCH'); exclude = @() } }
    bypass_actors = @()
    rules         = $rules
}
if ($AdminBypass -ne 'none') {
    # actor_id 5 = the built-in "Repository admin" role
    $ruleset.bypass_actors = @(@{ actor_id = 5; actor_type = 'RepositoryRole'; bypass_mode = $AdminBypass })
}

if ($PSCmdlet.ShouldProcess($Repo, "Create or update ruleset '$RulesetName' ($Enforcement)")) {
    $existing = gh api "repos/$Repo/rulesets?includes_parents=false" --jq ".[] | select(.name == `"$RulesetName`") | .id"
    if ($existing) {
        $r = Invoke-GhJson PUT "repos/$Repo/rulesets/$existing" $ruleset
        Write-Result "Ruleset '$RulesetName' updated ($Enforcement)" $r
    } else {
        $r = Invoke-GhJson POST "repos/$Repo/rulesets" $ruleset
        Write-Result "Ruleset '$RulesetName' created ($Enforcement)" $r
    }
    if (-not $r.Ok) { Write-Warning $r.Output }
}

Write-Host "Done. Review: https://github.com/$Repo/settings/rules" -ForegroundColor Cyan
