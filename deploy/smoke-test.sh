#!/bin/sh
# smoke-test.sh BASE_URL EXPECTED_BUILD [full|readonly]
set -eu
BASE=${1:?usage: smoke-test.sh BASE_URL EXPECTED_BUILD [full|readonly]}
BUILD=${2:?expected build number}
MODE=${3:-full}
fails=0

pass() { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }
json_field() { sed -n "s/.*\"$1\":\"\{0,1\}\([^,\"}]*\).*/\1/p"; }
post() { curl -fs -m 10 -X POST -H 'Content-Type: application/json' -d "$2" "$BASE$1"; }

echo "Smoke test: $BASE (expect build #$BUILD, mode=$MODE)"

body=$(curl -fs -m 10 "$BASE/health" || true)
if [ "$body" = "OK" ]; then pass "GET /health = OK"; else fail "GET /health returned '$body'"; fi

page=$(curl -fs -m 10 "$BASE/" || true)
if printf '%s' "$page" | grep -q "Build #$BUILD<"; then pass "footer shows Build #$BUILD"; else fail "footer does not show Build #$BUILD"; fi
range=$(printf '%s' "$page" | grep -o 'Guess a number between [0-9]* and [0-9]*' | head -1)
if [ -n "$range" ]; then pass "page says '$range'"; else fail "game prompt missing"; fi

new=$(post /api/new '{}' || true)
game=$(printf '%s' "$new" | json_field gameId)
min=$(printf '%s' "$new" | json_field min); max=$(printf '%s' "$new" | json_field max)
if [ -n "$game" ]; then pass "POST /api/new -> gameId $game (range $min-$max)"; else fail "POST /api/new failed: $new"; fi

code=$(curl -s -m 10 -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
  -d "{\"gameId\":\"$game\",\"guess\":$((max + 1))}" "$BASE/api/guess")
if [ "$code" = 400 ]; then pass "out-of-range guess -> 400"; else fail "out-of-range guess -> $code (expected 400)"; fi

if [ "$MODE" = full ] && [ -n "$game" ]; then
  lo=$min; hi=$max; result=""; n=0
  while [ "$n" -lt 10 ]; do
    g=$(( (lo + hi) / 2 )); n=$((n + 1))
    result=$(post /api/guess "{\"gameId\":\"$game\",\"guess\":$g}" | json_field result)
    case $result in
      "too high") hi=$((g - 1)) ;;
      "too low")  lo=$((g + 1)) ;;
      *) break ;;
    esac
  done
  if [ "$result" = correct ]; then pass "won a game in $n guesses (binary search)"; else fail "could not win: last result '$result'"; fi
fi

score=$(curl -fs -m 10 "$BASE/api/score" || true)
if printf '%s' "$score" | grep -q '"bestScore"'; then pass "GET /api/score -> $score"; else fail "GET /api/score returned '$score'"; fi

if [ "$fails" -gt 0 ]; then echo "SMOKE TEST FAILED ($fails check(s))"; exit 1; fi
echo "SMOKE TEST PASSED"
