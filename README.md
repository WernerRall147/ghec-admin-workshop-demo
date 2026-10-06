# GHEC Admin Workshop – demo & template repository

Demo repository for a **GitHub Enterprise Cloud (GHEC) administrator workshop**.
It is deliberately small so that every administration feature it showcases is easy to find and explain.

| Feature | Where to look |
|---|---|
| **Rulesets** (protected branches) | Settings → Rules → Rulesets: `main-protection`, `release-tags` |
| Classic branch protection (for comparison) | Settings → Branches: `release/*` |
| **Required status checks** – GitHub Actions | [`ci.yml`](.github/workflows/ci.yml) → check `build-and-test` |
| **Required status checks** – third-party tool via the Status API | [`Set-ExternalStatus.ps1`](scripts/api/Set-ExternalStatus.ps1) → context `external/security-scan` |
| **CODEOWNERS** | [`.github/CODEOWNERS`](.github/CODEOWNERS) |
| Pull request template & issue forms | [`.github/`](.github) |
| **Environments**, approvals, secrets & deployments | [`deploy.yml`](.github/workflows/deploy.yml) (staging → production) |
| **Deployments API** (external CD tool) | [`New-DemoDeployment.ps1`](scripts/api/New-DemoDeployment.ps1) |
| **GitHub Pages** (built by Actions) | [`pages.yml`](.github/workflows/pages.yml) → [`site/`](site) |
| **Dependabot** alerts & updates | `package.json` pins a vulnerable `lodash`; [`dependabot.yml`](.github/dependabot.yml) |
| **Code scanning** (CodeQL) + Copilot Autofix | [`src/legacy/report-server.js`](src/legacy/report-server.js) – **intentionally vulnerable** |
| **Webhooks** | [`webhook-receiver.js`](scripts/api/webhook-receiver.js) + `gh webhook forward` |
| **REST vs GraphQL** | [`Compare-RestGraphQL.ps1`](scripts/api/Compare-RestGraphQL.ps1) |
| **Admin automation** | [`scripts/admin/`](scripts/admin) – org snapshot, repo health, inactive members, audit log, migration check, baseline |
| **Unhealthy repositories** & changing history | [`scripts/unhealthy/`](scripts/unhealthy) |
| Hands-on labs | [`labs/`](labs) |

> ⚠️ `src/legacy/report-server.js` and the pinned `lodash` version are **deliberately insecure** so that security alerts appear.
> Never copy them into real code.

## Use it as a template

**Use this template → Create a new repository** and pick your organization.
Templates copy **files only** – rulesets, environments, secrets and security settings are not copied.
Configuring them is part of the [labs](labs), or run [`Set-RepoBaseline.ps1`](scripts/admin/Set-RepoBaseline.ps1).

## Prerequisites for the scripts

- PowerShell 7+ (`pwsh`) and the [GitHub CLI](https://cli.github.com) (`gh auth login`)
- Node.js 20+ (sample app and webhook receiver)
- Optional: `gh extension install cli/gh-webhook` (webhook forwarding)
- Optional: `pip install git-filter-repo` (history rewrite demo)

## Sample app

```powershell
npm ci
npm test
```

See [`scripts/README.md`](scripts/README.md) for every script and [`docs/admin-runbook.md`](docs/admin-runbook.md) for a sample admin runbook.
