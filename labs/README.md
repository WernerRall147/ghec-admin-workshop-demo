# Hands-on labs

Short, self-contained exercises to repeat the workshop demos **in your own organization**.
Do them in a sandbox organization or in a clearly named test repository.

| # | Lab | Time | Topics |
|---|---|---|---|
| 1 | [Create a repository from the template and grant team access](lab-01-template-and-access.md) | 10 min | templates, base permissions, roles, teams |
| 2 | [Protect the default branch with a ruleset](lab-02-rulesets.md) | 15 min | rulesets, evaluate mode, bypass list, rule insights |
| 3 | [CODEOWNERS with teams](lab-03-codeowners.md) | 10 min | CODEOWNERS, required code-owner review |
| 4 | [Required status checks: GitHub Actions + a third-party tool](lab-04-status-checks.md) | 15 min | required checks, Commit Status API |
| 5 | [Receive webhooks on your laptop](lab-05-webhooks.md) | 10 min | webhooks, signatures, `gh webhook forward` |
| 6 | [REST vs GraphQL and admin scripts](lab-06-api-and-scripts.md) | 15 min | APIs, rate limits, automation |
| 7 | [Audit log and dormant users](lab-07-audit-log.md) | 10 min | audit log search/API, dormant users report |
| 8 | [Fix an unhealthy repository by rewriting history](lab-08-unhealthy-repo.md) | 15 min | large files, leaked secrets, `git filter-repo` |

## Prerequisites

- An organization where you are an **owner** (or a repository you administer)
- [GitHub CLI](https://cli.github.com) signed in: `gh auth login`
- PowerShell 7+ (`pwsh`), Git, Node.js 20+
- For lab 5: `gh extension install cli/gh-webhook`
- For lab 8: `pip install git-filter-repo`
