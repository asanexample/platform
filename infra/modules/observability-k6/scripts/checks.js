// Platform synthetics — scripted health checks with thresholds (#102 P9b / k6).
// Runs as a k6 CronJob; metrics export to Mimir via Prometheus remote_write (K6_OUT in the CronJob env).
// Targets are in-cluster store/UI endpoints (reliable, no internal-NLB hairpin); blackbox covers the
// external Gateway/TLS path. k6 adds scripted multi-target checks + pass-rate / latency thresholds.
import http from 'k6/http';
import { check } from 'k6';

export const options = {
  // A single iteration per run; the CronJob schedule drives the cadence.
  vus: 1,
  iterations: 1,
  thresholds: {
    // The run FAILS (non-zero exit, visible in the Job) if these are breached.
    checks: ['rate>0.99'], // ~all checks must pass
    http_req_duration: ['p(95)<1500'], // 95th-percentile latency budget
  },
};

const targets = [
  { name: 'grafana', url: 'http://kube-prometheus-stack-grafana.observability.svc/api/health', ok: (r) => r.status === 200 && r.body.includes('database') },
  { name: 'mimir', url: 'http://mimir-gateway.observability.svc/ready', ok: (r) => r.status === 200 },
  { name: 'loki', url: 'http://loki.observability.svc:3100/ready', ok: (r) => r.status === 200 }, // the loki component; the nginx gateway doesn't proxy /ready
  { name: 'tempo', url: 'http://tempo-query-frontend.observability.svc:3200/ready', ok: (r) => r.status === 200 },
];

export default function () {
  for (const t of targets) {
    const res = http.get(t.url, { tags: { target: t.name }, timeout: '10s' });
    check(res, { 'healthy': t.ok }, { target: t.name });
  }
}
