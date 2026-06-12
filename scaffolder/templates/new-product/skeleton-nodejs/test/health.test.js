'use strict';
const { test } = require('node:test');
const assert = require('node:assert');
const { createApp } = require('../src/server');

// Asserts the liveness/readiness endpoint the platform probes returns 200 {"status":"ok"}.
test('GET /healthz returns 200 ok', async () => {
  const server = createApp().listen(0);
  const { port } = server.address();
  try {
    const res = await fetch(`http://127.0.0.1:${port}/healthz`);
    assert.strictEqual(res.status, 200);
    const body = await res.json();
    assert.strictEqual(body.status, 'ok');
  } finally {
    server.close();
  }
});
