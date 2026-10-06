<#
.SYNOPSIS
    Creates (or resets) the three demo pull requests used in the workshop.

.DESCRIPTION
    A  feature/bonus-marks              - unit test fails  -> blocked by required check "build-and-test"
    B  feature/supplementary-eligibility - CI passes, waits for "external/security-scan" (Status API demo)
    C  docs/runbook-app-review          - documentation change -> code owner review required

    Re-running closes the existing demo PRs, deletes their branches and recreates them from main.

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
        Apply  = {
            Add-Content docs/admin-runbook.md "`n## Quarterly: GitHub App permission review`n`n1. Organization -> Settings -> GitHub Apps: list every installed app.`n2. For each app, compare *requested* permissions with what it actually needs.`n3. Remove apps nobody owns; record the owner of every remaining app.`n"
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
        $open = gh pr list --repo $Repo --head $s.Branch --state open --json number --jq '.[].number'
        foreach ($n in $open) { gh pr close $n --repo $Repo --comment 'Resetting workshop demo.' | Out-Null }
        git push --quiet origin --delete $s.Branch 2>$null

        git checkout --quiet -B $s.Branch origin/main
        & $s.Apply
        git add -A
        git commit --quiet -m $s.Title
        git push --quiet --force origin $s.Branch
        if ($LASTEXITCODE -ne 0) { throw "Push of $($s.Branch) failed" }
        $url = gh pr create --repo $Repo --base main --head $s.Branch --title $s.Title --body $s.Body
        Write-Host "$($s.Branch.PadRight(36)) $url" -ForegroundColor Green
    }
} finally {
    Pop-Location
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
