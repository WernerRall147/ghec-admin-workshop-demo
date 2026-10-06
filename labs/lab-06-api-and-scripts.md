# Lab 6 – REST vs GraphQL and admin scripts

**Goal:** choose the right API, respect rate limits and automate recurring admin work.

1. Compare the two APIs for the same question ("my most recently pushed repositories with open PR and issue counts"):

   ```powershell
   ./scripts/api/Compare-RestGraphQL.ps1 -Owner <org> -Top 15
   ```

   Note the number of calls and the rate-limit cost of each approach.
2. Check your remaining rate limit:

   ```powershell
   gh api rate_limit --jq '.resources | {core: .core.remaining, graphql: .graphql.remaining, search: .search.remaining}'
   ```

3. Take an organization snapshot (run as an owner):

   ```powershell
   ./scripts/admin/Get-OrgSnapshot.ps1 -Org <org> -OutFile snapshot.md
   ```

4. Produce a repository health report and export it:

   ```powershell
   ./scripts/admin/Get-RepoHealthReport.ps1 -Owner <org> -Top 100 -Format Csv | Out-File health.csv
   ```

5. Find members without contributions in the last 90 days (GraphQL, batched):

   ```powershell
   ./scripts/admin/Find-InactiveMembers.ps1 -Org <org> -Days 90
   ```

**Discuss:** which identity should run these scripts on a schedule? (A GitHub App, not a personal token – see `.github/workflows/governance-report.yml`.)
