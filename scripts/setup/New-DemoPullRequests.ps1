<#
.SYNOPSIS
    Creates (or resets) the three demo pull requests used in the workshop.

.DESCRIPTION
    A  feature/bonus-marks              - unit test fails  -> blocked by required check "build-and-test"
    B  feature/supplementary-eligibility - CI passes, waits for "external/security-scan" (Status API demo)
    C  docs/runbook-app-review          - all checks pass  -> code owner review required

    Re-running rebuilds each branch from the current main and force-pushes it. Existing pull requests are
    reused (reopened if they were closed), so their numbers and links stay the same. Scenario C receives a
    successful "external/security-scan" status so that only the code owner review is outstanding.
    A pull request that was merged cannot be reused; the script then creates a new one and prints its number.

.EXAMPLE
    ./New-DemoPullRequests.ps1 -Repo WernerRall147/ghec-admin-workshop-demo
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[^/\s]+/[^/\s]+$')]
    [string]$Repo = 'WernerRall147/ghec-admin-workshop-demo'
)

$ErrorActionPreference = 'Stop'

$scenarios = @(
    @{
        Branch = 'feature/bonus-marks'
        Title  = 'Add bonus marks for tutorial participation'
        Body   = "Adds ``applyBonus(mark, bonus)`` so tutors can award up to 5 bonus marks.`n`n_Workshop scenario A - a required check fails._"
        Apply  = {
            $js = Get-Content src/marks.js -Raw
            $fn = "/**`n * Adds bonus marks, never exceeding 100.`n * @param {number} mark`n * @param {number} bonus`n */`nfunction applyBonus(mark, bonus) {`n  return mark + bonus;`n}`n`n"
            $js = $js.Replace('module.exports = { finalMark, result };', "$($fn)module.exports = { finalMark, result, applyBonus };")
            Set-Content src/marks.js $js -NoNewline
            Set-Content test/bonus.test.js "'use strict';`n`nconst test = require('node:test');`nconst assert = require('node:assert/strict');`nconst { applyBonus } = require('../src/marks');`n`ntest('adds bonus marks', () => {`n  assert.equal(applyBonus(60, 5), 65);`n});`n`ntest('caps the mark at 100', () => {`n  assert.equal(applyBonus(98, 5), 100);`n});`n" -NoNewline
        }
    },
    @{
        Branch = 'feature/supplementary-eligibility'
        Title  = 'Add supplementary exam eligibility check'
        Body   = "Adds ``isSupplementaryEligible(mark)`` - students with 40-49% may write a supplementary exam.`n`n_Workshop scenario B - CI passes; waiting for the third-party ``external/security-scan`` status._"
        Apply  = {
            $js = Get-Content src/marks.js -Raw
            $fn = "/**`n * Students with a final mark from 40 up to (but excluding) 50 may write a supplementary exam.`n * @param {number} mark`n */`nfunction isSupplementaryEligible(mark) {`n  return mark >= 40 && mark < 50;`n}`n`n"
            $js = $js.Replace('module.exports = { finalMark, result };', "$($fn)module.exports = { finalMark, result, isSupplementaryEligible };")
            Set-Content src/marks.js $js -NoNewline
            Set-Content test/supplementary.test.js "'use strict';`n`nconst test = require('node:test');`nconst assert = require('node:assert/strict');`nconst { isSupplementaryEligible } = require('../src/marks');`n`ntest('40-49 is eligible', () => {`n  assert.equal(isSupplementaryEligible(40), true);`n  assert.equal(isSupplementaryEligible(49.9), true);`n});`n`ntest('below 40 or 50+ is not eligible', () => {`n  assert.equal(isSupplementaryEligible(39.9), false);`n  assert.equal(isSupplementaryEligible(50), false);`n});`n" -NoNewline
        }
    },
    @{
        Branch = 'docs/runbook-app-review'
        Title  = 'Runbook: add the quarterly GitHub App permission review'
        Body   = "Documents how to review installed GitHub Apps and their requested permissions.`n`n_Workshop scenario C - code owner review required._"
        ExternalStatus = 'success'
        Apply  = {
            [IO.File]::AppendAllText((Join-Path $PWD 'docs/admin-runbook.md'), "`n## Quarterly: GitHub App permission review`n`n1. Organization -> Settings -> GitHub Apps: list every installed app.`n2. For each app, compare *requested* permissions with what it actually needs.`n3. Remove apps nobody owns; record the owner of every remaining app.`n")
        }
    }
)

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("demo-prs-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
git clone --quiet "https://github.com/$Repo.git" $tmp
if ($LASTEXITCODE -ne 0) { throw 'Clone failed' }
Push-Location $tmp
try {
    git config core.autocrlf false
    foreach ($s in $scenarios) {
        # Reuse the newest unmerged pull request for this branch so its number stays stable.
        $existing = gh pr list --repo $Repo --head $s.Branch --state all --limit 20 --json number,state |
            ConvertFrom-Json | Where-Object state -ne 'MERGED' | Sort-Object number -Descending | Select-Object -First 1

        if ($existing -and $existing.state -eq 'CLOSED') {
            # GitHub only reopens a pull request while its branch still points at the PR's last commit.
            git fetch --quiet origin "refs/pull/$($existing.number)/head"
            git push --quiet --force origin "FETCH_HEAD:refs/heads/$($s.Branch)"
            gh pr reopen $existing.number --repo $Repo 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Could not reopen pull request #$($existing.number)" }
        }

        git checkout --quiet -B $s.Branch origin/main
        & $s.Apply
        git add -A
        git commit --quiet -m $s.Title
        git push --quiet --force origin $s.Branch
        if ($LASTEXITCODE -ne 0) { throw "Push of $($s.Branch) failed" }

        if ($existing) {
            $number = $existing.number
            gh pr edit $number --repo $Repo --title $s.Title --body $s.Body | Out-Null
            $action = if ($existing.state -eq 'CLOSED') { 'reopened and reset' } else { 'reset' }
        } else {
            $url = gh pr create --repo $Repo --base main --head $s.Branch --title $s.Title --body $s.Body
            if ($LASTEXITCODE -ne 0) { throw "Could not create a pull request for $($s.Branch)" }
            $number = [int]($url -split '/')[-1]
            $action = 'created (new number - update your notes)'
        }

        if ($s.ExternalStatus) {
            $sha = git rev-parse HEAD
            gh api "repos/$Repo/statuses/$sha" -f state=$($s.ExternalStatus) -f context=external/security-scan `
                -f description='No critical findings' | Out-Null
        }
        Write-Host ("#{0,-4} {1,-36} {2}" -f $number, $s.Branch, $action) -ForegroundColor Green
    }
} finally {
    Pop-Location
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
