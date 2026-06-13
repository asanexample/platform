// Minimal Express service for app-${{ values.team }}-${{ values.product }}. Exposes the liveness/readiness
// endpoint the platform manifests probe (/healthz) and a JSON root. No cloud/AWS deps — an environment's AWS access
// (if any) is granted out-of-band via EKS Pod Identity to the named ServiceAccount.
'use strict';
const express = require('express');

const APP = 'app-${{ values.team }}-${{ values.product }}';

// createApp is exported so the unit test can exercise the routes without binding a fixed port.
function createApp() {
  const app = express();
  const version = process.env.VERSION || 'dev';
  const namespace = process.env.NAMESPACE || 'unknown';

  app.get('/healthz', (req, res) => res.json({ status: 'ok' }));

  app.get('/', (req, res) =>
    res.json({
      app: APP,
      version,
      namespace,
      hostname: req.headers.host || '',
      timestamp: new Date().toISOString(),
    }),
  );

  return app;
}

module.exports = { createApp };

// Started directly: listen on :8080 and shut down gracefully on SIGTERM (k8s sends it on pod termination).
if (require.main === module) {
  const server = createApp().listen(8080, () => console.log(`starting ${APP} on :8080`));
  const shutdown = () => {
    console.log('shutting down (draining in-flight requests)…');
    server.close(() => process.exit(0));
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}
