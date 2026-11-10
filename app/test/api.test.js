'use strict';

const request = require('supertest');
const { SECRET, tempDir, makeApp } = require('./helpers');

async function newGame(app) {
  const res = await request(app).post('/api/new');
  return res.body.gameId;
}

function guess(app, gameId, value) {
  return request(app).post('/api/guess').send({ gameId, guess: value });
}

describe('Brief Table III test cases', () => {
  test('T1: POST /api/new initializes a new game', async () => {
    const res = await request(makeApp()).post('/api/new');
    expect(res.status).toBe(200);
    expect(typeof res.body.gameId).toBe('string');
    expect(res.body).toMatchObject({ min: 1, max: 100, maxAttempts: 10, attempts: 0 });
  });

  test('T2: guess equal to secret returns "correct"', async () => {
    const app = makeApp();
    const id = await newGame(app);
    const res = await guess(app, id, SECRET);
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ result: 'correct', attempts: 1, status: 'won' });
  });

  test('T3: guess higher than secret returns "too high" and increments attempts', async () => {
    const app = makeApp();
    const id = await newGame(app);
    const first = await guess(app, id, SECRET + 10);
    expect(first.body).toMatchObject({ result: 'too high', attempts: 1 });
    const second = await guess(app, id, SECRET + 1);
    expect(second.body).toMatchObject({ result: 'too high', attempts: 2 });
  });

  test('T4: guess lower than secret returns "too low" and increments attempts', async () => {
    const app = makeApp();
    const id = await newGame(app);
    const res = await guess(app, id, SECRET - 1);
    expect(res.body).toMatchObject({ result: 'too low', attempts: 1 });
  });

  test('T5: out-of-range guess is rejected with 400 and attempts unchanged', async () => {
    const app = makeApp();
    const id = await newGame(app);
    await guess(app, id, 10); // one valid attempt first

    for (const bad of [101, 0, -5, 50.5, 'abc', null]) {
      const res = await guess(app, id, bad);
      expect(res.status).toBe(400);
      expect(res.body.error).toMatch(/between 1 and 100/);
      expect(res.body.attempts).toBe(1);
    }
    const next = await guess(app, id, 11);
    expect(next.body.attempts).toBe(2);
  });

  test('T6: 10 incorrect guesses end the game; 11th returns "game over"', async () => {
    const app = makeApp();
    const id = await newGame(app);
    for (let i = 1; i <= 10; i += 1) {
      const res = await guess(app, id, 1);
      expect(res.body).toMatchObject({ result: 'too low', attempts: i });
    }
    const eleventh = await guess(app, id, SECRET); // even the right answer is too late
    expect(eleventh.body).toMatchObject({ result: 'game over', attempts: 10, status: 'lost' });
  });

  test('T7: GET /health returns 200 "OK"', async () => {
    const res = await request(makeApp()).get('/health');
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/text\/plain/);
    expect(res.text).toBe('OK');
  });

  test('T8: best score persists across application restarts', async () => {
    const dataDir = tempDir();
    const first = makeApp({ dataDir });
    const id = await newGame(first);
    await guess(first, id, 50);
    await guess(first, id, 30);
    const win = await guess(first, id, SECRET);
    expect(win.body).toMatchObject({ result: 'correct', attempts: 3, bestScore: 3, isNewBest: true });

    // "Restart": a brand-new app instance (fresh memory) pointing at the same data dir.
    const restarted = makeApp({ dataDir });
    const res = await request(restarted).get('/api/score');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ bestScore: 3 });
  });
});

describe('Game flow details', () => {
  test('GET /api/score is null before any win', async () => {
    const res = await request(makeApp()).get('/api/score');
    expect(res.body).toEqual({ bestScore: null });
  });

  test('a worse win does not overwrite the best score; a better one does', async () => {
    const app = makeApp();
    let id = await newGame(app);
    await guess(app, id, 1);
    await guess(app, id, SECRET); // 2 attempts
    id = await newGame(app);
    await guess(app, id, 1);
    await guess(app, id, 2);
    const worse = await guess(app, id, SECRET); // 3 attempts
    expect(worse.body).toMatchObject({ bestScore: 2, isNewBest: false });
    id = await newGame(app);
    const better = await guess(app, id, SECRET); // 1 attempt
    expect(better.body).toMatchObject({ bestScore: 1, isNewBest: true });
  });

  test('guesses after a win return "game over" and do not count', async () => {
    const app = makeApp();
    const id = await newGame(app);
    await guess(app, id, SECRET);
    const res = await guess(app, id, 10);
    expect(res.body).toMatchObject({ result: 'game over', attempts: 1 });
  });

  test('losing guess reveals the secret', async () => {
    const app = makeApp({ config: { NUMBER_RANGE_MIN: 1, NUMBER_RANGE_MAX: 100, MAX_ATTEMPTS: 1, VERSION: '1.0' } });
    const id = await newGame(app);
    const res = await guess(app, id, 1);
    expect(res.body).toMatchObject({ result: 'too low', status: 'lost', secret: SECRET, remaining: 0 });
  });

  test('guess without gameId uses the latest game (brief payload is just {guess})', async () => {
    const app = makeApp();
    await newGame(app);
    const res = await request(app).post('/api/guess').send({ guess: SECRET });
    expect(res.body.result).toBe('correct');
  });

  test('guess with no game, or unknown gameId, returns 404', async () => {
    const app = makeApp();
    expect((await request(app).post('/api/guess').send({ guess: 5 })).status).toBe(404);
    await newGame(app);
    expect((await guess(app, 'nope', 5)).status).toBe(404);
  });

  test('numeric strings are accepted as guesses', async () => {
    const app = makeApp();
    const id = await newGame(app);
    const res = await guess(app, id, String(SECRET));
    expect(res.body.result).toBe('correct');
  });

  test('malformed JSON returns 400', async () => {
    const res = await request(makeApp())
      .post('/api/guess')
      .set('Content-Type', 'application/json')
      .send('{"guess":');
    expect(res.status).toBe(400);
  });

  test('old games are evicted after 1000 to bound memory', async () => {
    const app = makeApp();
    const first = await newGame(app);
    for (let i = 0; i < 1000; i += 1) await request(app).post('/api/new');
    expect((await guess(app, first, 5)).status).toBe(404);
  });

  test('range follows config (Level 4 demo: max 50)', async () => {
    const app = makeApp({ config: { NUMBER_RANGE_MIN: 1, NUMBER_RANGE_MAX: 50, MAX_ATTEMPTS: 10, VERSION: '2.0' } });
    const id = await newGame(app);
    const res = await guess(app, id, 51);
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/between 1 and 50/);
  });
});

describe('Page, metrics, stress', () => {
  test('GET / renders the range and the deployment footer', async () => {
    const res = await request(makeApp()).get('/');
    expect(res.status).toBe(200);
    expect(res.text).toContain('Guess a number between 1 and 100');
    expect(res.text).toContain('v1.0');
    expect(res.text).toContain('Build #7');
    expect(res.text).toContain('Commit: abc1234');
    expect(res.text).toContain('Host: test-host (blue)');
  });

  test('footer values are HTML-escaped', async () => {
    const app = makeApp({ buildInfo: { version: '<b>', buildNumber: '1', commit: 'x', hostname: 'h', color: 'c' } });
    const res = await request(app).get('/');
    expect(res.text).toContain('v&lt;b&gt;');
  });

  test('GET /metrics exposes default and HTTP metrics', async () => {
    const app = makeApp();
    await request(app).get('/health');
    await request(app).get('/does-not-exist');
    const res = await request(app).get('/metrics');
    expect(res.status).toBe(200);
    expect(res.text).toContain('nodejs_heap_size_used_bytes');
    expect(res.text).toMatch(/http_requests_total\{method="GET",route="\/health",status="200"\} 1/);
    expect(res.text).toMatch(/http_requests_total\{method="GET",route="unmatched",status="404"\} 1/);
    expect(res.text).toContain('http_request_duration_seconds_bucket');
    expect(res.text).toContain('app_info{version="1.0",build="7",commit="abc1234",color="blue"} 1');
  });

  test('GET /stress burns CPU in a worker and /health stays responsive', async () => {
    const app = makeApp();
    const stress = request(app).get('/stress?seconds=0.5');
    const healthStart = Date.now();
    const [stressRes, healthRes] = await Promise.all([stress, request(app).get('/health')]);
    expect(healthRes.text).toBe('OK');
    expect(Date.now() - healthStart).toBeGreaterThanOrEqual(400); // stress really ran
    expect(stressRes.status).toBe(200);
    expect(stressRes.text).toMatch(/^OK: CPU stress ran for/);
  });

  test('GET /stress rejects bad input, caps duration, and limits concurrency', async () => {
    const app = makeApp({ stressMaxSeconds: 0.3, stressMaxConcurrent: 1 });
    expect((await request(app).get('/stress?seconds=abc')).status).toBe(400);
    expect((await request(app).get('/stress?seconds=-1')).status).toBe(400);
    const [a, b] = await Promise.all([request(app).get('/stress?seconds=999'), request(app).get('/stress?seconds=0.1')]);
    expect([a.status, b.status].sort()).toEqual([200, 429]);
  });
});
