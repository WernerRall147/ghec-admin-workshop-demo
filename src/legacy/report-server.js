'use strict';

// ⚠️  INTENTIONALLY VULNERABLE CODE ⚠️
// This file exists ONLY to demonstrate code scanning (CodeQL) alerts and Copilot Autofix
// during the GHEC admin workshop. Never deploy it and never copy it into real code.

const http = require('http');
const url = require('url');
const { exec } = require('child_process');

const server = http.createServer((req, res) => {
  const query = url.parse(req.url, true).query;

  if (req.url.startsWith('/ping')) {
    // Command injection: untrusted input is concatenated into a shell command.
    exec('ping -c 1 ' + query.host, (err, stdout) => {
      res.end(err ? 'error' : stdout);
    });
    return;
  }

  // Reflected cross-site scripting: untrusted input is written into HTML without encoding.
  res.writeHead(200, { 'Content-Type': 'text/html' });
  res.end('<h1>Report for ' + query.student + '</h1>');
});

if (require.main === module) {
  server.listen(process.env.PORT || 8080);
}

module.exports = server;
