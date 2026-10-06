#!/usr/bin/env node
'use strict';

// Minimal webhook receiver for the workshop.
// - Verifies the X-Hub-Signature-256 HMAC when WEBHOOK_SECRET is set
// - Prints a one-line summary of every event it receives
//
// Usage (two terminals):
//   1) $env:WEBHOOK_SECRET = 'workshop-demo'; node scripts/api/webhook-receiver.js
//   2) gh webhook forward --repo=OWNER/REPO --events=issues,issue_comment,pull_request,push,status `
//        --url=http://localhost:3000/webhook --secret=workshop-demo
//
// Then open an issue, comment on a PR or push a commit and watch the events arrive.

const http = require('http');
const crypto = require('crypto');

const PORT = Number(process.env.PORT || 3000);
const SECRET = process.env.WEBHOOK_SECRET || '';

function verifySignature(signature, body) {
  if (!SECRET) return null; // verification disabled
  if (!signature) return false;
  const expected = 'sha256=' + crypto.createHmac('sha256', SECRET).update(body).digest('hex');
  const a = Buffer.from(signature);
  const b = Buffer.from(expected);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function describe(event, p) {
  const who = p.sender ? `by ${p.sender.login}` : '';
  switch (event) {
    case 'ping':
      return `hook ${p.hook_id} is alive: "${p.zen}"`;
    case 'issues':
      return `${p.action} issue #${p.issue.number} "${p.issue.title}" ${who}`;
    case 'issue_comment':
      return `${p.action} comment on #${p.issue.number}: "${(p.comment.body || '').slice(0, 60)}" ${who}`;
    case 'pull_request': {
      const merged = p.action === 'closed' && p.pull_request.merged ? ' (merged)' : '';
      return `${p.action}${merged} PR #${p.number} "${p.pull_request.title}" ${who}`;
    }
    case 'pull_request_review':
      return `${p.action} review (${p.review.state}) on PR #${p.pull_request.number} ${who}`;
    case 'push':
      return `${(p.commits || []).length} commit(s) to ${p.ref} ${who}`;
    case 'status':
      return `${p.context} = ${p.state} on ${p.sha.slice(0, 7)} ("${p.description || ''}")`;
    case 'workflow_run':
      return `workflow "${p.workflow_run.name}" ${p.action} -> ${p.workflow_run.conclusion || p.workflow_run.status}`;
    case 'deployment_status':
      return `deployment to ${p.deployment.environment} -> ${p.deployment_status.state}`;
    default:
      return `${p.action || ''} ${who}`.trim();
  }
}

const server = http.createServer((req, res) => {
  if (req.method !== 'POST' || !req.url.startsWith('/webhook')) {
    res.writeHead(404).end();
    return;
  }

  const chunks = [];
  req.on('data', (chunk) => chunks.push(chunk));
  req.on('end', () => {
    const body = Buffer.concat(chunks);
    const event = String(req.headers['x-github-event'] || 'unknown');
    const delivery = String(req.headers['x-github-delivery'] || '-');
    const verified = verifySignature(req.headers['x-hub-signature-256'], body);

    if (verified === false) {
      console.log(`REJECTED ${event} delivery ${delivery}: invalid signature`);
      res.writeHead(401).end('invalid signature');
      return;
    }

    let payload = {};
    try {
      payload = JSON.parse(body.toString('utf8'));
    } catch {
      // Non-JSON payloads are ignored in this demo.
    }

    const time = new Date().toISOString().slice(11, 19);
    const lock = verified ? '[signed]' : '[unsigned]';
    console.log(`${time} ${lock} ${event.padEnd(18)} ${describe(event, payload)}`);
    res.writeHead(202).end('accepted');
  });
});

server.listen(PORT, () => {
  console.log(`Webhook receiver listening on http://localhost:${PORT}/webhook`);
  console.log(`Signature verification: ${SECRET ? 'ON' : 'OFF (set WEBHOOK_SECRET to enable)'}`);
});
