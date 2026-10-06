<#
.SYNOPSIS
    Builds a deliberately UNHEALTHY Git repository for the "unhealthy repositories / changing history" demo.

.DESCRIPTION
    Creates a local repository with problems commonly found in (manually) migrated repositories:
      * a large binary build artefact, committed and later deleted (it is still in history)
      * a .env file with a FAKE password, committed and later deleted (still in history)
      * vendored dependencies and a large log file
      * stale feature branches (back-dated by months)
      * no README, no .gitignore, no CODEOWNERS
    Optionally publishes (or re-publishes, to reset the demo) the repository as a PRIVATE GitHub repo.

.EXAMPLE
    ./New-UnhealthyRepo.ps1 -Path C:\Git\ghec-admin-workshop-unhealthy

.EXAMPLE
    # Create + publish. Re-run with -Force to reset the demo after a history rewrite.
    ./New-UnhealthyRepo.ps1 -Path C:\Git\ghec-admin-workshop-unhealthy -Publish -Repo my-user/ghec-admin-workshop-unhealthy -Force

.EXAMPLE
    # Also publish a "manual migration" copy (main + one tag only) for Compare-MigratedRepo.ps1
    ./New-UnhealthyRepo.ps1 -Path C:\Git\ghec-admin-workshop-unhealthy -Publish -Repo my-user/ghec-admin-workshop-unhealthy `
        -MigratedRepo my-user/ghec-admin-workshop-migrated -Force
#>
[CmdletBinding()]
param(
    [string]$Path = (Join-Path ([IO.Path]::GetTempPath()) 'ghec-admin-workshop-unhealthy'),

    [ValidateRange(1, 90)]
    [int]$BinaryMB = 15,

    [ValidateRange(0, 200)]
    [int]$StaleBranches = 25,

    [switch]$Publish,

    [ValidatePattern('^[^/\s]+/[^/\s]+$')]
    [string]$Repo,

    # Optional: simulate an incomplete manual migration (only main and tag v0.2 are pushed)
    [ValidatePattern('^[^/\s]+/[^/\s]+$')]
    [string]$MigratedRepo,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if ($Publish -and -not $Repo) { throw '-Repo owner/name is required with -Publish' }

if (Test-Path $Path) {
    if (-not $Force) { throw "$Path already exists. Use -Force to recreate it." }
    Remove-Item $Path -Recurse -Force
}
New-Item -ItemType Directory -Path $Path | Out-Null
Push-Location $Path
try {
    git init --quiet --initial-branch=main
    git config core.autocrlf false

    $start = (Get-Date).Date.AddDays(-420).AddHours(9)
    function Save-Commit([string]$Message, [int]$DayOffset) {
        $date = $start.AddDays($DayOffset).ToString('yyyy-MM-ddTHH:mm:ss')
        $env:GIT_AUTHOR_DATE = $date; $env:GIT_COMMITTER_DATE = $date
        git add -A
        git commit --quiet -m $Message
        Remove-Item Env:GIT_AUTHOR_DATE, Env:GIT_COMMITTER_DATE
    }
    function Write-TextFile([string]$RelativePath, [string]$Content) {
        $full = Join-Path $Path $RelativePath
        New-Item -ItemType Directory -Force -Path (Split-Path $full) | Out-Null
        [IO.File]::WriteAllText($full, $Content)
    }

    # 1. Initial import
    Write-TextFile 'app/main.py' "def final_mark(parts):`n    return round(sum(m * w for m, w in parts) / 100, 1)`n`nif __name__ == '__main__':`n    print(final_mark([(80, 30), (60, 70)]))`n"
    Write-TextFile 'app/requirements.txt' "flask==2.0.1`nrequests==2.25.0`n"
    Save-Commit 'Initial import' 0

    # 2. Configuration with a FAKE secret
    Write-TextFile 'config/.env' "# Local settings`nDB_HOST=db.internal.example`nDB_USER=report_svc`nDB_PASSWORD=Winter2025!NotReal`nREPORTING_API_KEY=not-a-real-key-7f3a9c2e5b1d8f4a`n"
    Save-Commit 'Add configuration' 10
    git tag v0.1

    # 3. Build output and logs
    $bytes = [byte[]]::new($BinaryMB * 1MB)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    New-Item -ItemType Directory -Force -Path (Join-Path $Path 'build') | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $Path 'build/installer.bin'), $bytes)
    $log = (1..40000 | ForEach-Object { "2025-03-01T10:00:$('{0:D2}' -f ($_ % 60)) INFO request $_ served in $($_ % 97) ms" }) -join "`n"
    Write-TextFile 'logs/app.log' $log
    Save-Commit 'Add build output' 20

    # 4. Vendored dependencies
    1..150 | ForEach-Object { Write-TextFile ("vendor/lib$($_)/module.py") "# vendored third-party code $_`nVALUE = $_`n" }
    Save-Commit 'Vendor dependencies' 30

    # 5. "Remove" the secret and the binary - they stay in history
    Remove-Item (Join-Path $Path 'config/.env')
    Save-Commit 'Remove secrets' 100
    Remove-Item (Join-Path $Path 'build/installer.bin')
    Save-Commit 'Remove build output' 110

    # 6. Later work
    Write-TextFile 'app/main.py' "def final_mark(parts):`n    total = sum(m * w for m, w in parts)`n    return round(total / 100, 1)`n`nif __name__ == '__main__':`n    print(final_mark([(80, 30), (60, 70)]))`n"
    Save-Commit 'Fix rounding' 220
    git tag v0.2

    # 7. Stale branches (back-dated commits, created without checkout)
    $tree = git rev-parse 'HEAD^{tree}'
    for ($i = 1; $i -le $StaleBranches; $i++) {
        $date = $start.AddDays(120 + $i * 3).ToString('yyyy-MM-ddTHH:mm:ss')
        $env:GIT_AUTHOR_DATE = $date; $env:GIT_COMMITTER_DATE = $date
        $commit = git commit-tree $tree -p HEAD -m "WIP experiment $i"
        Remove-Item Env:GIT_AUTHOR_DATE, Env:GIT_COMMITTER_DATE
        git branch "feature/old-experiment-$i" $commit
    }

    git gc --quiet
    $counts = @{}
    git count-objects -v | ForEach-Object { $k, $v = "$_" -split ':\s*'; $counts[$k] = $v }
    $sizeMb = [math]::Round(([double]$counts['size-pack'] + [double]$counts['size']) / 1024, 1)
    Write-Host "Unhealthy repository created at $Path ($sizeMb MB packed, $(git rev-list --all --count) commits, $(@(git branch --format='%(refname)').Count) branches)" -ForegroundColor Green

    if ($Publish) {
        gh repo view $Repo --json name 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            gh repo create $Repo --private --description 'Deliberately unhealthy repository for the GHEC admin workshop (large binaries, fake secret in history, stale branches).' | Out-Null
            Write-Host "Created private repository $Repo" -ForegroundColor Green
        } elseif (-not $Force) {
            throw "$Repo already exists. Use -Force to overwrite its branches and tags."
        }
        git remote add origin "https://github.com/$Repo.git"
        # --prune removes remote branches/tags that no longer exist locally, so this also resets the demo.
        git push --quiet --force --prune origin 'refs/heads/*:refs/heads/*' 'refs/tags/*:refs/tags/*'
        if ($LASTEXITCODE -ne 0) { throw 'Push failed' }
        git branch --set-upstream-to=origin/main main | Out-Null
        Write-Host "Published to https://github.com/$Repo" -ForegroundColor Green

        if ($MigratedRepo) {
            gh repo view $MigratedRepo --json name 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) {
                gh repo create $MigratedRepo --private --description 'Simulated manual migration (only main + one tag were pushed) for the migration validation demo.' | Out-Null
            }
            # A typical manual migration: only the default branch and one tag were pushed.
            git push --quiet --force --prune "https://github.com/$MigratedRepo.git" 'refs/heads/main:refs/heads/main' 'refs/tags/v0.2:refs/tags/v0.2'
            if ($LASTEXITCODE -ne 0) { throw 'Push to the migrated repository failed' }
            Write-Host "Published partial 'manual migration' to https://github.com/$MigratedRepo" -ForegroundColor Green
        }
    }
} finally {
    Pop-Location
}
