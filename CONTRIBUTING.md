# Contributing

1. Create a branch from `main` (direct pushes to `main` are blocked by the `main-protection` ruleset).
2. Make your change and run `npm test`.
3. Open a pull request using the template. It needs:
   - a passing `build-and-test` check,
   - a passing `external/security-scan` status,
   - an approval from a code owner (see `.github/CODEOWNERS`).
4. Pull requests are merged with **squash** or **rebase**; the branch is deleted automatically.
