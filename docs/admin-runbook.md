# GitHub Enterprise Cloud – admin runbook (sample)

A starting point for the recurring tasks of enterprise and organization owners.
Adapt the frequency and owners to your organization.

## Daily

| Task | Where | Why |
|---|---|---|
| Triage new **critical/high** security alerts | Organization → Security → Overview / Alerts | Fix exposure quickly; route to code owners |
| Check **secret scanning push-protection bypasses** | Security → Secret scanning → filter `bypassed:true` | A bypass means someone pushed a secret deliberately |

## Weekly

| Task | Where | Why |
|---|---|---|
| Review **new repositories** and visibility changes | Audit log: `action:repo.create`, `action:repo.access` | Catch accidental public repositories |
| Review **outside collaborators** added | Organization → People → Outside collaborators | They consume licences and bypass team governance |
| Approve / deny **fine-grained PAT requests** | Organization → Settings → Personal access tokens → Pending requests | Least privilege for automation |
| Check **Actions usage and spend** | Enterprise → Billing & licensing → Usage | Avoid surprises from runner minutes and storage |

## Monthly

| Task | Where | Why |
|---|---|---|
| Download the **Dormant users** report and reclaim licences | Enterprise → Compliance → Reports | Users inactive for 30+ days |
| Review **installed GitHub Apps** and **OAuth app approvals** | Organization → Settings → GitHub Apps / Third-party access | Remove unused integrations with broad permissions |
| Review the **owners** list (enterprise and organization) | People → filter by role | Keep owners to the minimum (but at least two) |
| Review **rule insights** for bypasses | Organization or repository → Settings → Rules → Insights | Bypasses should be rare and justified |
| Archive **stale repositories** | `scripts/admin/Get-RepoHealthReport.ps1` | Less noise, smaller attack surface |

## Quarterly

- Review enterprise **policies** (repository, Actions, Copilot, code security, personal access tokens).
- Reconcile **teams** with identity-provider groups (team sync / SCIM).
- Test the **audit log streaming** destination and alert rules.
- Re-run `scripts/admin/Get-OrgSnapshot.ps1` and compare with the previous snapshot.

## Incident: a secret was committed

1. **Revoke / rotate the credential immediately** – treat it as compromised.
2. Check the audit log and the provider's logs for misuse.
3. Remove it from history only if needed (`scripts/unhealthy/Repair-UnhealthyRepo.ps1`) and coordinate a re-clone.
4. Enable or verify **push protection** so it cannot happen again.
