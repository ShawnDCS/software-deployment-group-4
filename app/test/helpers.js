'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { createApp } = require('../src/app');

const TEST_CONFIG = { NUMBER_RANGE_MIN: 1, NUMBER_RANGE_MAX: 100, MAX_ATTEMPTS: 10, VERSION: '1.0' };
const SECRET = 42;

function tempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'guessgame-test-'));
}

// App with a fixed secret number so every test is deterministic.
function makeApp(overrides = {}) {
  return createApp({
    dataDir: overrides.dataDir || tempDir(),
    config: TEST_CONFIG,
    randomInt: () => SECRET,
    buildInfo: { version: '1.0', buildNumber: '7', commit: 'abc1234', hostname: 'test-host', color: 'blue' },
    ...overrides,
  });
}

module.exports = { TEST_CONFIG, SECRET, tempDir, makeApp };
