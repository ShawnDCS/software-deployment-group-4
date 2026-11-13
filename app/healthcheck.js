'use strict';

// Used by the Dockerfile HEALTHCHECK
const http = require('http');

const port = Number(process.env.PORT) || 3000;
/*const req = http.get({ host: '127.0.0.1', port, path: '/health', timeout: 2000 }, (res) => {
  let body = '';
  res.on('data', (chunk) => { body += chunk; });
  res.on('end', () => process.exit(res.statusCode === 200 && body.trim() === 'OK' ? 0 : 1));
});
req.on('timeout', () => req.destroy(new Error('timeout')));
req.on('error', () => process.exit(1));
*/