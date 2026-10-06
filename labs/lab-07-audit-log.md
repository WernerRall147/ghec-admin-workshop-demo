# Lab 7 – Audit log and dormant users

**Goal:** answer "who did what, when?" and find licences to reclaim.

1. Organization → **Settings → Audit log**. Try these searches:
   - `action:repo.create` – who created repositories this month?
   - `action:repo.access` – did anyone change a repository's visibility?
   - `action:org.update_member` – who was promoted to owner?
   - `action:repository_ruleset` – who changed a ruleset?
   - `actor:<username>` – everything one person did
2. Export the results (**Export → CSV / JSON**).
3. Do the same through the API (needs GitHub Enterprise Cloud and the `read:audit_log` scope):

   ```powershell
   gh auth refresh -h github.com -s read:audit_log
   ./scripts/admin/Search-AuditLog.ps1 -ListExamples
   ./scripts/admin/Search-AuditLog.ps1 -Org <org> -Phrase 'action:repo.create'
   ```

4. Enterprise → **Compliance → Reports → Dormant users → New report**, then download it.
   A user is dormant after **30 days** without qualifying activity (e.g. SSO sign-in, creating a PR, commenting on a PR).
5. Compare the report with `./scripts/admin/Find-InactiveMembers.ps1 -Org <org> -Days 30`.

**Discuss:** the audit log keeps 180 days (Git events 7 days) – what is your retention requirement? Consider **audit log streaming** to your SIEM.
