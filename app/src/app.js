'use strict';

// createApp() builds the Express app but never calls listen() — server.js does that.
// This lets the tests spin up as many isolated apps as they like with supertest.

const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const express = require('express');

const defaultConfig = require('./config');
const { RESULT, createGame, validateGuess, applyGuess } = require('./game');
const { createScoreStore } = require('./scoreStore');
const { createMetrics } = require('./metrics');
const { runStress } = require('./stress');

const MAX_GAMES_IN_MEMORY = 1000;
const TEMPLATE = fs.readFileSync(path.join(__dirname, 'views', 'index.html'), 'utf8');

function defaultRandomInt(min, max) {
  return crypto.randomInt(min, max + 1); // crypto.randomInt's upper bound is exclusive
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[c]));
}

// Footer info. Build number / commit are baked into the image as env vars by the
// Dockerfile; DEPLOY_COLOR is set by the deploy script at `docker run` time.
function buildInfoFromEnv(config, env = process.env) {
  return {
    version: env.APP_VERSION || config.VERSION,
    buildNumber: env.BUILD_NUMBER || 'dev',
    commit: (env.GIT_COMMIT || 'local').slice(0, 7),
    hostname: os.hostname(),
    color: env.DEPLOY_COLOR || 'none',
  };
}

function createApp({
  dataDir,
  config = defaultConfig,
  randomInt = defaultRandomInt,
  buildInfo = buildInfoFromEnv(config),
  stressMaxSeconds = 30,
  stressMaxConcurrent = 2,
} = {}) {
  if (!dataDir) throw new Error('createApp: dataDir is required');

  const min = config.NUMBER_RANGE_MIN;
  const max = config.NUMBER_RANGE_MAX;
  const scores = createScoreStore(dataDir);
  const metrics = createMetrics(buildInfo);
  const games = new Map(); // gameId -> game state (in memory, per brief §2.4.4)
  let latestGameId = null;
  let stressRunning = 0;

  const page = TEMPLATE
    .replaceAll('{{MIN}}', escapeHtml(min))
    .replaceAll('{{MAX}}', escapeHtml(max))
    .replaceAll('{{MAX_ATTEMPTS}}', escapeHtml(config.MAX_ATTEMPTS))
    .replaceAll('{{VERSION}}', escapeHtml(buildInfo.version))
    .replaceAll('{{BUILD_NUMBER}}', escapeHtml(buildInfo.buildNumber))
    .replaceAll('{{COMMIT}}', escapeHtml(buildInfo.commit))
    .replaceAll('{{HOSTNAME}}', escapeHtml(buildInfo.hostname))
    .replaceAll('{{COLOR}}', escapeHtml(buildInfo.color));

  const app = express();
  app.disable('x-powered-by');
  app.use(metrics.middleware);
  app.use(express.json({ limit: '1kb' }));

  app.get('/', (req, res) => {
    res.type('html').send(page);
  });

  app.post('/api/new', (req, res) => {
    const gameId = crypto.randomUUID();
    games.set(gameId, createGame({
      secret: randomInt(min, max),
      min,
      max,
      maxAttempts: config.MAX_ATTEMPTS,
    }));
    latestGameId = gameId;
    // Keep memory bounded: drop the oldest game (Map keeps insertion order).
    if (games.size > MAX_GAMES_IN_MEMORY) games.delete(games.keys().next().value);
    res.json({ gameId, min, max, maxAttempts: config.MAX_ATTEMPTS, attempts: 0 });
  });

  app.post('/api/guess', (req, res) => {
    const body = req.body || {};
    // gameId is optional: the brief's payload is just {"guess": n}, so fall back to the latest game.
    const gameId = body.gameId || latestGameId;
    const game = gameId && games.get(gameId);
    if (!game) {
      return res.status(404).json({ error: 'No active game. Start one with POST /api/new.' });
    }

    const check = validateGuess(body.guess, min, max);
    if (!check.ok) {
      return res.status(400).json({ error: check.error, attempts: game.attempts });
    }

    const { game: next, result } = applyGuess(game, check.value);
    games.set(gameId, next);

    const response = {
      result,
      attempts: next.attempts,
      remaining: next.maxAttempts - next.attempts,
      status: next.status,
    };
    if (result === RESULT.CORRECT) {
      Object.assign(response, scores.recordWin(next.attempts));
    } else if (next.status === 'lost' && result !== RESULT.GAME_OVER) {
      response.secret = next.secret; // reveal the number on the losing guess
    }
    return res.json(response);
  });

  app.get('/api/score', (req, res) => {
    res.json({ bestScore: scores.getBest() });
  });

  app.get('/health', (req, res) => {
    res.type('text/plain').send('OK');
  });

  app.get('/metrics', async (req, res, next) => {
    try {
      res.set('Content-Type', metrics.register.contentType);
      res.send(await metrics.register.metrics());
    } catch (err) {
      next(err);
    }
  });

  // GET /stress?seconds=N  (default 10, capped) — burns CPU so Grafana shows a spike.
  app.get('/stress', async (req, res, next) => {
    const requested = req.query.seconds === undefined ? 10 : Number(req.query.seconds);
    if (!Number.isFinite(requested) || requested <= 0) {
      return res.status(400).type('text/plain').send('seconds must be a positive number');
    }
    if (stressRunning >= stressMaxConcurrent) {
      return res.status(429).type('text/plain').send('Stress test already running, try again shortly');
    }
    const seconds = Math.min(requested, stressMaxSeconds);
    stressRunning += 1;
    try {
      const started = Date.now();
      const rounds = await runStress(seconds * 1000);
      const took = ((Date.now() - started) / 1000).toFixed(1);
      return res.type('text/plain').send(`OK: CPU stress ran for ${took}s (${rounds} fib(25) rounds)`);
    } catch (err) {
      return next(err);
    } finally {
      stressRunning -= 1;
    }
  });

  app.use((req, res) => {
    res.status(404).json({ error: 'Not found' });
  });

  // Error handler (4 args). Malformed JSON bodies arrive here as 400s.
  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, next) => {
    const status = err.status || err.statusCode || 500;
    if (status >= 500) console.error(err);
    res.status(status).json({ error: status >= 500 ? 'Internal server error' : err.message });
  });

  return app;
}

module.exports = { createApp, buildInfoFromEnv };
