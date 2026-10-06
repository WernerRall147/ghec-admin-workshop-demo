# Scripts

All scripts use the GitHub CLI (`gh`) for authentication – no tokens are stored in files.
Run `Get-Help ./<script>.ps1 -Detailed` for parameters and examples.

## `api/` – GitHub API demos

| Script | What it shows |
|---|---|
| `Compare-RestGraphQL.ps1` | Same data via REST (1 + N calls) and GraphQL (1 call); rate-limit cost |
| `Set-ExternalStatus.ps1` | A third-party tool reporting `pending` → `success`/`failure` with the Commit Status API |
| `New-DemoDeployment.ps1` | An external CD tool using the Deployments API (queued → in_progress → success) |
| `webhook-receiver.js` | Minimal receiver that verifies `X-Hub-Signature-256`; use with `gh webhook forward` |

## `admin/` – administration automation

| Script | What it does |
|---|---|
| `Get-OrgSnapshot.ps1` | Organization settings, people, teams, repos, Actions policy, rulesets, apps, webhooks + recommendations |
| `Get-RepoHealthReport.ps1` | Per-repository health: protection, CODEOWNERS, README, staleness, size, branches, Dependabot alerts |
| `Find-InactiveMembers.ps1` | Members without contributions in N days (batched GraphQL) – complements the Dormant users report |
| `Search-AuditLog.ps1` | Organization / enterprise audit log via the API, with a list of useful queries (`-ListExamples`) |
| `Compare-MigratedRepo.ps1` | Validates a migration: every branch and tag SHA in source (e.g. GitLab) vs target (GitHub) |
| `Set-RepoBaseline.ps1` | Applies merge settings, security features and a default-branch ruleset (idempotent, supports `-WhatIf`) |

## `unhealthy/` – repository health and rewriting history

| Script | What it does |
|---|---|
| `New-UnhealthyRepo.ps1` | Builds a repo with a large binary and a fake secret in history plus stale branches; optional publish/reset |
| `Measure-RepoHealth.ps1` | Finds large blobs in history, secret-like content, stale branches, missing hygiene files |
| `Repair-UnhealthyRepo.ps1` | `git filter-repo` on a fresh mirror clone; before/after comparison; optional force-push |

## `setup/` – workshop presenter tooling

| Script | What it does |
|---|---|
| `Initialize-DemoRepo.ps1` | Configures this repository (rulesets, environments, Pages, labels, issues, project). Idempotent |
| `New-DemoPullRequests.ps1` | Creates or resets the three demo pull requests (failing check / waiting for status / code owner) |
