# Lab 3 – CODEOWNERS with teams

**Goal:** route reviews automatically to the team that owns a path, and make their approval mandatory.

1. Create `.github/CODEOWNERS` in your lab repository:

   ```text
   # last matching pattern wins
   *                    @<org>/lab-maintainers
   /docs/               @<org>/lab-readers
   /.github/workflows/  @<org>/platform-admins
   ```

   > Teams must have at least **Write** access to the repository to be valid code owners.
2. Open the file on GitHub – the editor highlights invalid owners. You can also check with:

   ```powershell
   gh api repos/<org>/<repo>/codeowners/errors
   ```

3. In your ruleset's *Require a pull request* rule, enable **Require review from Code Owners**.
4. Open a pull request that changes `docs/` and one that changes a workflow – see who is requested automatically.

**Discuss:** why teams instead of individuals? How do nested teams and team sync with your identity provider help here?
