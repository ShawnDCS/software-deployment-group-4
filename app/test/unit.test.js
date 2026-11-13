'use strict';

const fs = require('fs');
const request = require('supertest');
const path = require('path');
const { RESULT, createGame, validateGuess, applyGuess } = require('../src/game');
const { createScoreStore } = require('../src/scoreStore');
const { createApp, buildInfoFromEnv } = require('../src/app');
const config = require('../src/config');
const { tempDir } = require('./helpers');

describe('game.js', () => {
  const base = { secret: 5, min: 1, max: 10, maxAttempts: 3 };

  test('createGame rejects a secret outside the range', () => {
    expect(() => createGame({ ...base, secret: 11 })).toThrow(RangeError);
    expect(() => createGame({ ...base, secret: 2.5 })).toThrow(RangeError);
  });

  test('validateGuess', () => {
    expect(validateGuess(3, 1, 10)).toEqual({ ok: true, value: 4 });
    expect(validateGuess(' 7 ', 1, 10)).toEqual({ ok: true, value: 7 });
    expect(validateGuess(11, 1, 10).ok).toBe(false);
    expect(validateGuess('7a', 1, 10).ok).toBe(false);
    expect(validateGuess(undefined, 1, 10).ok).toBe(false);
  });

  test('applyGuess does not mutate its input', () => {
    const g = createGame(base);
    const { game } = applyGuess(g, 1);
    expect(g.attempts).toBe(0);
    expect(game.attempts).toBe(1);
  });

  test('applyGuess loses on the last attempt and ignores later guesses', () => {
    let g = createGame(base);
    ({ game: g } = applyGuess(g, 9));
    ({ game: g } = applyGuess(g, 9));
    const last = applyGuess(g, 1);
    expect(last.result).toBe(RESULT.TOO_LOW);
    expect(last.game.status).toBe('lost');
    expect(applyGuess(last.game, 5).result).toBe(RESULT.GAME_OVER);
  });

  test('a correct guess on the final attempt still wins', () => {
    let g = createGame(base);
    ({ game: g } = applyGuess(g, 9));
    ({ game: g } = applyGuess(g, 9));
    const { game, result } = applyGuess(g, 5);
    expect(result).toBe(RESULT.CORRECT);
    expect(game.status).toBe('won');
  });
});

describe('scoreStore.js', () => {
  test('creates the data dir and writes scores.json', () => {
    const dir = path.join(tempDir(), 'nested', 'data');
    const store = createScoreStore(dir);
    expect(store.getBest()).toBeNull();
    expect(store.recordWin(4)).toEqual({ bestScore: 4, isNewBest: true });
    expect(JSON.parse(fs.readFileSync(store.file, 'utf8')).bestScore).toBe(4);
  });

  test('a corrupt file is treated as no score and then overwritten', () => {
    const dir = tempDir();
    fs.writeFileSync(path.join(dir, 'scores.json'), '{not json');
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});
    const store = createScoreStore(dir);
    expect(store.getBest()).toBeNull();
    expect(warn).toHaveBeenCalled();
    expect(store.recordWin(6).bestScore).toBe(6);
    warn.mockRestore();
  });

  test('an invalid stored value is ignored', () => {
    const dir = tempDir();
    fs.writeFileSync(path.join(dir, 'scores.json'), JSON.stringify({ bestScore: -3 }));
    expect(createScoreStore(dir).getBest()).toBeNull();
  });
});

describe('metrics.js', () => {
  test('app_info falls back to "unknown" labels', async () => {
    const { createMetrics } = require('../src/metrics');
    const text = await createMetrics().register.metrics();
    expect(text).toContain('app_info{version="unknown",build="unknown",commit="unknown",color="unknown"} 1');
  });
});

describe('app.js', () => {
  test('createApp requires dataDir', () => {
    expect(() => createApp()).toThrow(/dataDir/);
  });

  test('default random secret is within range', async () => {
    // Uses the real crypto-based randomInt (no injection). createGame throws if out of range.
    const app = createApp({ dataDir: tempDir(), config: { ...config, NUMBER_RANGE_MIN: 1, NUMBER_RANGE_MAX: 2 } });
    for (let i = 0; i < 20; i += 1) {
      const res = await request(app).post('/api/new');
      expect(res.status).toBe(200);
    }
  });

  test('buildInfoFromEnv reads env vars with sensible fallbacks', () => {
    expect(buildInfoFromEnv(config, {})).toMatchObject({
      version: config.VERSION, buildNumber: 'dev', commit: 'local', color: 'none',
    });
    expect(buildInfoFromEnv(config, {
      APP_VERSION: '9.9', BUILD_NUMBER: '47', GIT_COMMIT: 'a3f9c2d1234567', DEPLOY_COLOR: 'green',
    })).toMatchObject({ version: '9.9', buildNumber: '47', commit: 'a3f9c2d', color: 'green' });
  });

  // NOTE: deliberately no test pinning config values — the Level 4 demo changes
  // NUMBER_RANGE_MAX to 50 and that commit must pass the pipeline.
});
