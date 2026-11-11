'use strict';

// Prometheus metrics

const client = require('prom-client');

function createMetrics(buildInfo = {}) {
  const register = new client.Registry();
  // Default Node.js metrics
  client.collectDefaultMetrics({ register });

  const httpRequestsTotal = new client.Counter({
    name: 'http_requests_total',
    help: 'Total HTTP requests',
    labelNames: ['method', 'route', 'status'],
    registers: [register],
  });

  const httpRequestDuration = new client.Histogram({
    name: 'http_request_duration_seconds',
    help: 'HTTP request duration in seconds',
    labelNames: ['method', 'route', 'status'],
    buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30],
    registers: [register],
  });

  // Constant gauge = 1 whose labels say which build is live (Grafana "Live build" panel)
  const appInfo = new client.Gauge({
    name: 'app_info',
    help: 'Build information of the running game',
    labelNames: ['version', 'build', 'commit', 'color'],
    registers: [register],
  });
  appInfo.set({
    version: String(buildInfo.version || 'unknown'),
    build: String(buildInfo.buildNumber || 'unknown'),
    commit: String(buildInfo.commit || 'unknown'),
    color: String(buildInfo.color || 'unknown'),
  }, 1);

  // Express middleware
  function middleware(req, res, next) {
    const end = httpRequestDuration.startTimer();
    res.on('finish', () => {
      const route = req.route ? req.baseUrl + req.route.path : 'unmatched';
      const labels = { method: req.method, route, status: String(res.statusCode) };
      httpRequestsTotal.inc(labels);
      end(labels);
    });
    next();
  }

  return { register, middleware };
}

module.exports = { createMetrics };
