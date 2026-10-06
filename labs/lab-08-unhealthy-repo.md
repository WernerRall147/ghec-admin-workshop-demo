# Lab 8 – Fix an unhealthy repository by rewriting history

**Goal:** find what makes a repository slow or risky, and clean it up safely.

> ⚠️ Rewriting history changes every affected commit SHA. Only do this on a repository you own, after agreeing it with the team.

1. Build a deliberately unhealthy repository (15 MB binary and a **fake** secret in history, stale branches):

   ```powershell
   ./scripts/unhealthy/New-UnhealthyRepo.ps1 -Path $HOME/unhealthy-lab -Force
   ```

2. Analyse it:

   ```powershell
   ./scripts/unhealthy/Measure-RepoHealth.ps1 -Path $HOME/unhealthy-lab
   ```

   Why does deleting a file in a new commit **not** make the repository smaller or the secret safe?
3. Dry-run the rewrite on a fresh mirror clone:

   ```powershell
   ./scripts/unhealthy/Repair-UnhealthyRepo.ps1 -SourceUrl $HOME/unhealthy-lab -DeleteStaleBranches
   ```

   Compare size, commit count and the `main` SHA before and after.
4. Optional – publish the repository first (`New-UnhealthyRepo.ps1 ... -Publish -Repo <you>/unhealthy-lab`) and re-run step 3 with `-Push`.

**The order that matters when a real secret leaks:** rotate the secret → freeze → rewrite on a fresh mirror → force-push (needs a ruleset bypass) → everyone re-clones → ask GitHub Support to purge cached data → enable push protection.

**Prevention:** `.gitignore`, Git LFS for binaries, secret scanning **push protection**, and rulesets that block force pushes.
