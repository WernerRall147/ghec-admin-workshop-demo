# Lab 4 – Required status checks: GitHub Actions + a third-party tool

**Goal:** block merges until CI passes **and** an external tool reports success through the Commit Status API.

1. Make sure `.github/workflows/ci.yml` exists in your repository and has run at least once (check names only appear after a first run).
2. Edit your default-branch ruleset → ✅ **Require status checks to pass** → add:
   - `build-and-test` (GitHub Actions job)
   - `external/security-scan` (a commit status posted by an external system)
3. Open a pull request. The merge box shows `external/security-scan` as **Expected — Waiting for status to be reported**.
4. Act as the external tool:

   ```powershell
   ./scripts/api/Set-ExternalStatus.ps1 -Repo <org>/<repo> -PullRequest <number> -Result failure
   ./scripts/api/Set-ExternalStatus.ps1 -Repo <org>/<repo> -PullRequest <number> -Result success
   ```

   Or with plain REST:

   ```powershell
   $sha = gh pr view <number> --repo <org>/<repo> --json headRefOid --jq .headRefOid
   gh api repos/<org>/<repo>/statuses/$sha -f state=success -f context=external/security-scan -f description="All good"
   ```

5. Watch the merge box update after each call.

**Discuss:** statuses vs checks (GitHub Apps can use the richer Checks API); who should be allowed to post a status? (Anyone with write access can – for stronger guarantees pin the required check to a specific GitHub App in the ruleset.)
