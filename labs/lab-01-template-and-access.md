# Lab 1 – Create a repository from the template and grant team access

**Goal:** practise least-privilege access: base permission + team roles instead of individual grants.

1. Open this repository and click **Use this template → Create a new repository**.
   - Owner: *your organization* · Name: `admin-lab-<your-initials>` · Visibility: **Internal** (or Private)
2. Note what was copied (files, folders) and what was **not** (rulesets, environments, secrets, security settings).
3. Organization → **Settings → Member privileges → Base permissions**: note the current value.
   - Discuss: what can every member do in your new repository because of it? (`No permission` / `Read` are typical baselines.)
4. Create (or reuse) two teams: `lab-maintainers` and `lab-readers`.
5. In your repository: **Settings → Collaborators and teams → Add teams**
   - `lab-maintainers` → **Maintain**
   - `lab-readers` → **Read** (or **Triage** if they should manage issues)
6. Verify with a colleague (or with the API):

   ```powershell
   gh api repos/<org>/admin-lab-<initials>/teams --jq '.[] | "\(.slug): \(.permission)"'
   ```

**Discuss:** when would you use *Triage* or *Maintain* instead of *Write* or *Admin*?
