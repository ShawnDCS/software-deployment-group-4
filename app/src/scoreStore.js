'use strict';

// Best score persistence

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
        // Corrupt or unreadable file: treat as no score
        console.warn(`scoreStore: could not read ${file}: ${err.message}`);
      }
      return null;
    }
  }

  // Records a win
  function recordWin(attempts) {
    const current = getBest();
    if (current !== null && current <= attempts) {
      return { bestScore: current, isNewBest: false };
    }
    fs.mkdirSync(dataDir, { recursive: true });
    // Write to a temp file then rename, so a crash mid-write never leaves a half-written file
    const tmp = `${file}.${process.pid}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify({ bestScore: attempts, updatedAt: new Date().toISOString() }));
    fs.renameSync(tmp, file);
    return { bestScore: attempts, isNewBest: true };
  }

  return { file, getBest, recordWin };
}

module.exports = { createScoreStore };
