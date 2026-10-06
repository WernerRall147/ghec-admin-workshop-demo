<#
.SYNOPSIS
    Rewrites a repository's history with git filter-repo to remove a leaked secret file and large
    binaries, optionally deletes stale branches, and (optionally) force-pushes the result.

.DESCRIPTION
    ORDER MATTERS when a secret has leaked:
      1. ROTATE / REVOKE the credential first. Rewriting history does NOT "un-leak" it - assume it is compromised.
      2. Announce a short freeze; merge or close open pull requests.
      3. Rewrite on a FRESH MIRROR CLONE (this script does that for you).
      4. Force-push. Protected branches/rulesets will block this unless you are allowed to bypass.
      5. Everyone re-clones (an old clone pushed again would re-introduce the history).
      6. On GitHub, pull request refs and cached views can keep old objects reachable - contact
         GitHub Support to purge them if the data is sensitive.

    Requires git-filter-repo:  pip install git-filter-repo   (https://github.com/newren/git-filter-repo)

.EXAMPLE
    ./Repair-UnhealthyRepo.ps1 -SourceUrl https://github.com/my-user/ghec-admin-workshop-unhealthy.git

.EXAMPLE
    ./Repair-UnhealthyRepo.ps1 -SourceUrl https://github.com/my-user/ghec-admin-workshop-unhealthy.git -DeleteStaleBranches -Push
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SourceUrl,

    [string]$WorkDir = (Join-Path ([IO.Path]::GetTempPath()) 'ghec-unhealthy-rewrite.git'),

    [string[]]$RemovePaths = @('config/.env'),

    [string]$StripBlobsBiggerThan = '10M',

    [switch]$DeleteStaleBranches,

    [string]$StaleBranchPattern = 'feature/old-*',

    [switch]$Push
)

$ErrorActionPreference = 'Stop'

# Locate git-filter-repo (on PATH as "git filter-repo", or as a Python module)
git filter-repo --version *> $null
if ($LASTEXITCODE -eq 0) {
    $filterRepo = { param([string[]]$FrArgs) git filter-repo @FrArgs }
} else {
    python -m git_filter_repo --version *> $null
    if ($LASTEXITCODE -ne 0) { throw 'git-filter-repo not found. Install it with:  pip install git-filter-repo' }
    $filterRepo = { param([string[]]$FrArgs) python -m git_filter_repo @FrArgs }
}

function Get-Stats {
    $counts = @{}
    git count-objects -v | ForEach-Object { $k, $v = "$_" -split ':\s*'; $counts[$k] = $v }
    [pscustomobject]@{
        SizeMB  = [math]::Round(([double]$counts['size-pack'] + [double]$counts['size']) / 1024, 1)
        Commits = [int](git rev-list --all --count)
        Branches = @(git for-each-ref refs/heads --format='%(refname)').Count
        MainSha = (git rev-parse --short main)
    }
}

if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
Write-Host "1/5 Fresh mirror clone of $SourceUrl" -ForegroundColor Cyan
git clone --quiet --mirror --no-local $SourceUrl $WorkDir
if ($LASTEXITCODE -ne 0) { throw 'Clone failed' }

Push-Location $WorkDir
# Git's safe.bareRepository=explicit setting requires bare repositories to be named explicitly;
# git-filter-repo's fresh-clone check expects that name to be ".".
$env:GIT_DIR = '.'
try {
    $before = Get-Stats
    Write-Host "    before: $($before.SizeMB) MB, $($before.Commits) commits, $($before.Branches) branches, main = $($before.MainSha)"
    Write-Host "    secret file history before: $(@(git log --all --oneline -- $RemovePaths).Count) commit(s) touch $($RemovePaths -join ', ')"

    Write-Host "2/5 Rewriting history: removing $($RemovePaths -join ', ') and blobs > $StripBlobsBiggerThan" -ForegroundColor Cyan
    $frArgs = @('--quiet', '--invert-paths')
    foreach ($p in $RemovePaths) { $frArgs += @('--path', $p) }
    $frArgs += @('--strip-blobs-bigger-than', $StripBlobsBiggerThan)
    # "git remote rm origin" (run by filter-repo) prints a harmless note for mirror clones - hide it.
    & $filterRepo $frArgs 2>&1 | ForEach-Object { "$_" } |
        Where-Object { $_ -notmatch '^(Note: Some branches outside the refs/remotes|to delete them, use:|\s+git branch -d )' }
    if ($LASTEXITCODE -ne 0) { throw 'git filter-repo failed' }

    if ($DeleteStaleBranches) {
        Write-Host "3/5 Deleting stale branches matching '$StaleBranchPattern'" -ForegroundColor Cyan
        $stale = @(git for-each-ref "refs/heads/$StaleBranchPattern" --format='%(refname:short)')
        foreach ($b in $stale) { git branch -D $b *> $null }
        Write-Host "    deleted $($stale.Count) branches"
    } else {
        Write-Host '3/5 Skipping stale branch clean-up (use -DeleteStaleBranches)' -ForegroundColor DarkGray
    }

    git reflog expire --expire=now --all
    git gc --quiet --prune=now --aggressive
    $after = Get-Stats

    Write-Host '4/5 Result' -ForegroundColor Cyan
    [pscustomobject]@{ Metric = 'Packed size (MB)'; Before = $before.SizeMB; After = $after.SizeMB },
    [pscustomobject]@{ Metric = 'Commits'; Before = $before.Commits; After = $after.Commits },
    [pscustomobject]@{ Metric = 'Branches'; Before = $before.Branches; After = $after.Branches },
    [pscustomobject]@{ Metric = 'main commit SHA'; Before = $before.MainSha; After = $after.MainSha } | Format-Table -AutoSize | Out-Host
    Write-Host "    secret file history after: $(@(git log --all --oneline -- $RemovePaths).Count) commit(s)"
    Write-Host '    Every rewritten commit has a NEW SHA - old clones, forks and open PRs no longer match.' -ForegroundColor Yellow
    $map = Join-Path $WorkDir 'filter-repo/commit-map'
    if (Test-Path $map) { Write-Host '    Old -> new commit map (first 3):'; Get-Content $map | Select-Object -Skip 1 -First 3 | ForEach-Object { "      $_" } }

    if ($Push) {
        Write-Host "5/5 Force-pushing rewritten history to $SourceUrl" -ForegroundColor Cyan
        git remote add origin $SourceUrl 2>$null
        git push --force --prune origin 'refs/heads/*:refs/heads/*' 'refs/tags/*:refs/tags/*'
        if ($LASTEXITCODE -ne 0) { throw 'Push rejected - is the branch protected by a ruleset without a bypass for you?' }
        Write-Host '    Done. Ask every contributor to re-clone. Consider a GitHub Support request to purge cached data.' -ForegroundColor Green
    } else {
        Write-Host "5/5 Not pushed (dry run). Rewritten mirror is in $WorkDir - re-run with -Push to publish." -ForegroundColor DarkGray
    }
} finally {
    Remove-Item Env:GIT_DIR -ErrorAction SilentlyContinue
    Pop-Location
}
