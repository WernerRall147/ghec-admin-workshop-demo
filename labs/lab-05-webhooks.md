# Lab 5 – Receive webhooks on your laptop

**Goal:** see the events GitHub sends, and verify their signatures.

1. Terminal 1 – start the receiver:

   ```powershell
   $env:WEBHOOK_SECRET = 'lab-secret'
   node scripts/api/webhook-receiver.js
   ```

2. Terminal 2 – forward repository events to it (creates a temporary webhook while it runs):

   ```powershell
   gh extension install cli/gh-webhook   # once
   $env:GH_TOKEN = gh auth token         # the extension cannot read tokens from the OS keyring
   gh webhook forward --repo=<org>/<repo> --events=issues,issue_comment,pull_request,push,status `
     --url=http://localhost:3000/webhook --secret=lab-secret
   ```

   > A `HTTP 404 ... /hooks` error means the extension had no token – set `GH_TOKEN` as above.
   > Only one person can forward a given repository at a time ("Hook already exists").

3. Open an issue, comment on a pull request, push a commit, or run `Set-ExternalStatus.ps1` — each event appears in terminal 1 with `[signed]`.
4. Restart the receiver with a different `WEBHOOK_SECRET` and trigger an event: it is **rejected** – this is why you always verify `X-Hub-Signature-256`.
5. In the UI, look at **Settings → Webhooks** of a real webhook: *Recent deliveries*, request/response, **Redeliver**.

**Discuss:** repository vs organization vs enterprise webhooks; webhooks vs audit log streaming vs polling the API.
