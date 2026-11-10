'use strict';

// Entrypoint: reads env, starts listening, shuts down cleanly on SIGTERM
// (docker stop sends SIGTERM — without a handler Node as PID 1 would ignore it
// and Docker would SIGKILL after 10 s, cutting off in-flight requests).

const path = require('path');
const { createApp } = require('./app');

const port = Number(process.env.PORT) || 3000;
const dataDir = process.env.DATA_DIR || path.join(__dirname, '..', 'data');

const app = createApp({ dataDir });
const server = app.listen(port, () => {
  console.log(`guessgame listening on :${port} (dataDir=${dataDir})`);
});

function shutdown(signal) {
  console.log(`${signal} received, closing server`);
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 10000).unref();
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
