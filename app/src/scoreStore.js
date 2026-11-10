'use strict';

// Best score persistence: ${dataDir}/scores.json  ->  { "bestScore": <int|null> }
// In the container dataDir is /app/data, bind-mounted from /var/lib/app-data on the host,
// so the score survives container replacement (and is shared by blue and green).

const fs = require('fs');
const path = require('path');

function createScoreStore(dataDir) {
  const file = path.join(dataDir, 'scores.json');

  function getBest() {
    try {
      const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
      return Number.isInteger(parsed.bestScore) && parsed.bestScore > 0 ? parsed.bestScore : null;
    } catch (err) {
      if (err.code !== 'ENOENT') {
        // Corrupt or unreadable file: treat as "no score yet" rather than crash the game.
        console.warn(`scoreStore: could not read ${file}: ${err.message}`);
      }
      return null;
    }
  }

  // Records a win; returns { bestScore, isNewBest }.
  function recordWin(attempts) {
    const current = getBest();
    if (current !== null && current <= attempts) {
      return { bestScore: current, isNewBest: false };
    }
    fs.mkdirSync(dataDir, { recursive: true });
    // Write to a temp file then rename, so a crash mid-write never leaves a half-written file.
    const tmp = `${file}.${process.pid}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify({ bestScore: attempts, updatedAt: new Date().toISOString() }));
    fs.renameSync(tmp, file);
    return { bestScore: attempts, isNewBest: true };
  }

  return { file, getBest, recordWin };
}

module.exports = { createScoreStore };
