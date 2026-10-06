# Lab 2 – Protect the default branch with a ruleset

**Goal:** require pull requests and block force-pushes/deletions on the default branch — first in *Evaluate* mode, then *Active*.

1. Repository → **Settings → Rules → Rulesets → New ruleset → New branch ruleset**
   - Name: `default-branch` · Enforcement: **Evaluate** (GitHub Enterprise) · Target: **Include default branch**
   - Rules: ✅ Restrict deletions · ✅ Block force pushes · ✅ Require a pull request before merging (1 approval, dismiss stale approvals, require conversation resolution)
   - Bypass list: **Repository admin → For pull requests only**
2. Push a commit directly to the default branch. In *Evaluate* mode it succeeds, but **Rules → Insights** records that it *would* have been blocked.
3. Switch Enforcement to **Active** and try again:

   ```powershell
   git commit --allow-empty -m "direct push test"
   git push origin main   # expected: GH013 Repository rule violations found
   ```

4. Create a branch and a pull request instead. Observe the merge box: what is required? Can an admin bypass?
5. Optional – automate it for many repositories:

   ```powershell
   ./scripts/admin/Set-RepoBaseline.ps1 -Repo <org>/<repo> -Enforcement evaluate -WhatIf
   ```

**Discuss:** rulesets vs classic branch protection — layering, organization-wide targeting, evaluate mode, bypass lists, insights.
At organization level (GitHub Enterprise) one ruleset can protect the default branch of *every* repository.
