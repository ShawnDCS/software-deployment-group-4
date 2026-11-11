'use strict';

// Pure game logic

const RESULT = Object.freeze({
  TOO_HIGH: 'too high',
  TOO_LOW: 'too low',
  CORRECT: 'correct',
  GAME_OVER: 'game over',
});

function createGame({ secret, min, max, maxAttempts }) {
  if (!Number.isInteger(secret) || secret < min || secret > max) {
    throw new RangeError(`secret ${secret} is outside ${min}-${max}`);
  }
  return { secret, min, max, maxAttempts, attempts: 0, status: 'playing' };
}

// Accepts an integer or an integer-looking string ("42")
function validateGuess(raw, min, max) {
  let value = raw;
  if (typeof raw === 'string' && /^\s*-?\d+\s*$/.test(raw)) {
    value = Number(raw);
  }
  if (typeof value !== 'number' || !Number.isInteger(value)) {
    return { ok: false, error: `Guess must be a whole number between ${min} and ${max}.` };
  }
  if (value < min || value > max) {
    return { ok: false, error: `Guess ${value} is out of range. Pick a number between ${min} and ${max}.` };
  }
  return { ok: true, value };
}

// Returns { game, result } where game is a NEW object (the input is not mutated)
function applyGuess(game, value) {
  if (game.status !== 'playing') {
    return { game, result: RESULT.GAME_OVER };
  }
  const attempts = game.attempts + 1;
  if (value === game.secret) {
    return { game: { ...game, attempts, status: 'won' }, result: RESULT.CORRECT };
  }
  const result = value > game.secret ? RESULT.TOO_HIGH : RESULT.TOO_LOW;
  const status = attempts >= game.maxAttempts ? 'lost' : 'playing';
  return { game: { ...game, attempts, status }, result };
}

module.exports = { RESULT, createGame, validateGuess, applyGuess };
