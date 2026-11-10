'use strict';

// CPU stress for the Grafana demo. Runs in a worker thread so the main event loop
// keeps answering /health while the CPU is pegged — otherwise a /stress call during
// a deploy would make health checks fail.

const { Worker } = require('worker_threads');

const WORKER_CODE = `
const { parentPort, workerData } = require('worker_threads');
function fib(n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
const deadline = Date.now() + workerData.ms;
let rounds = 0;
while (Date.now() < deadline) { fib(25); rounds++; }
parentPort.postMessage(rounds);
`;

function runStress(ms) {
  return new Promise((resolve, reject) => {
    const worker = new Worker(WORKER_CODE, { eval: true, workerData: { ms } });
    worker.once('message', resolve);
    worker.once('error', reject);
  });
}

module.exports = { runStress };
