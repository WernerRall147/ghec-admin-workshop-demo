<#
.SYNOPSIS
    Analyses a local Git repository (normal or mirror clone) for common health problems.

.DESCRIPTION
    Reports: packed size, largest blobs anywhere in history (and whether they still exist at HEAD),
    sensitive-looking files and secret-like lines in history, stale branches, vendored/build folders
    and missing hygiene files (README, .gitignore, CODEOWNERS).

    For a deeper analysis, GitHub's open-source "git-sizer" tool is recommended:
    https://github.com/github/git-sizer

.EXAMPLE
    ./Measure-RepoHealth.ps1 -Path C:\Git\ghec-admin-workshop-unhealthy
#>
[CmdletBinding()]
param(
    [string]$Path = '.',

    [ValidateRange(1, 100)]
    [int]$Top = 5,

    [int]$StaleDays = 90
)

$ErrorActionPreference = 'Stop'
Push-Location $Path
# Bare/mirror clones must be named explicitly when Git's safe.bareRepository=explicit is set.
$isBare = (Test-Path (Join-Path $Path 'HEAD')) -and (Test-Path (Join-Path $Path 'objects')) -and -not (Test-Path (Join-Path $Path '.git'))
if ($isBare) { $env:GIT_DIR = (Resolve-Path $Path).Path }
try {
    git rev-parse --git-dir *> $null
    if ($LASTEXITCODE -ne 0) { throw "$Path is not a Git repository" }

    function Write-Check([bool]$Ok, [string]$Text) {
        if ($Ok) { Write-Host "  [ok]   $Text" -ForegroundColor Green } else { Write-Host "  [warn] $Text" -ForegroundColor Yellow }
    }

    $counts = @{}
    git count-objects -v | ForEach-Object { $k, $v = "$_" -split ':\s*'; $counts[$k] = $v }
    $sizeMb = [math]::Round(([double]$counts['size-pack'] + [double]$counts['size']) / 1024, 1)
    $commits = git rev-list --all --count
    Write-Host "`nRepository: $((Resolve-Path .).Path)" -ForegroundColor Cyan
    Write-Host "  Packed size: $sizeMb MB | Commits (all refs): $commits"

    Write-Host "`nLargest blobs in history" -ForegroundColor Cyan
    $blobs = git rev-list --objects --all |
        git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' |
        Where-Object { $_ -like 'blob *' } |
        ForEach-Object {
            $type, $sha, $size, $file = "$_" -split ' ', 4
            [pscustomobject]@{ SizeMB = [math]::Round([long]$size / 1MB, 2); Path = $file; Sha = $sha.Substring(0, 8) }
        } |
        Sort-Object SizeMB -Descending | Select-Object -First $Top
    foreach ($b in $blobs) {
        git cat-file -e "HEAD:$($b.Path)" 2>$null
        $b | Add-Member -NotePropertyName AtHEAD -NotePropertyValue ($LASTEXITCODE -eq 0)
    }
    $blobs | Format-Table -AutoSize
    $hidden = @($blobs | Where-Object { -not $_.AtHEAD -and $_.SizeMB -ge 1 })
    Write-Check ($hidden.Count -eq 0) "$($hidden.Count) large file(s) deleted from HEAD but still in history (every clone downloads them)"

    Write-Host "`nSensitive files and secret-like lines in history" -ForegroundColor Cyan
    $sensitive = git log --all --name-only --format= |
        Where-Object { $_ -match '(^|/)(\.env(\..+)?|id_rsa|.*\.pem|.*\.pfx|.*\.p12|.*\.key|secrets?\.(json|ya?ml|txt))$' } |
        Sort-Object -Unique
    Write-Check (-not $sensitive) "Sensitive-looking files ever committed: $(if ($sensitive) { $sensitive -join ', ' } else { 'none' })"
    $pattern = '([Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Aa][Pp][Ii]_?[Kk][Ee][Yy]|[Ss][Ee][Cc][Rr][Ee][Tt])[[:space:]]*[:=]'
    $secretCommits = @(git log --all -G $pattern --format='%h %ad %s' --date=short)
    Write-Check ($secretCommits.Count -eq 0) "Commits adding/removing secret-like lines: $($secretCommits.Count)"
    $secretCommits | Select-Object -First 5 | ForEach-Object { Write-Host "         $_" }

    Write-Host "`nBranches" -ForegroundColor Cyan
    $cutoff = (Get-Date).AddDays(-$StaleDays)
    $branches = git for-each-ref --format='%(refname:short)|%(committerdate:iso-strict)' refs/heads refs/remotes/origin |
        Where-Object { $_ -notmatch '/HEAD\|' } |
        ForEach-Object { $n, $d = "$_" -split '\|'; [pscustomobject]@{ Branch = $n; LastCommit = [datetime]$d } }
    $stale = @($branches | Where-Object LastCommit -lt $cutoff)
    Write-Check ($stale.Count -eq 0) "$($stale.Count) of $(@($branches).Count) branches have no commits in the last $StaleDays days"

    Write-Host "`nContent at HEAD" -ForegroundColor Cyan
    $tree = git ls-tree -r --name-only HEAD
    $dirs = $tree | ForEach-Object { ($_ -split '/')[0] } | Sort-Object -Unique
    $bad = @($dirs | Where-Object { $_ -in 'node_modules', 'vendor', 'packages', 'bin', 'obj', 'build', 'dist', 'logs' })
    Write-Check ($bad.Count -eq 0) "Build / dependency / log folders committed: $(if ($bad) { $bad -join ', ' } else { 'none' })"
    $hasReadme = [bool]($tree | Where-Object { $_ -match '^README' })
    $hasIgnore = [bool]($tree | Where-Object { $_ -eq '.gitignore' })
    $hasOwners = [bool]($tree | Where-Object { $_ -in 'CODEOWNERS', '.github/CODEOWNERS', 'docs/CODEOWNERS' })
    Write-Check $hasReadme $(if ($hasReadme) { 'README present' } else { 'README missing' })
    Write-Check $hasIgnore $(if ($hasIgnore) { '.gitignore present' } else { '.gitignore missing' })
    Write-Check $hasOwners $(if ($hasOwners) { 'CODEOWNERS present' } else { 'CODEOWNERS missing' })
} finally {
    if ($isBare) { Remove-Item Env:GIT_DIR -ErrorAction SilentlyContinue }
    Pop-Location
}
