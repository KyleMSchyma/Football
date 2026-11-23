#!/usr/bin/env bash
# =============================================================================
# tm_weekly.sh: weekly update of the Market Check "Trade market" source (Kyle 2026-11-23: "I want the trade data
# updated weekly"). Runs on Kyle's PC before the Tuesday refresh (Task Scheduler: Tuesday 5:00 AM, tm_weekly.cmd).
#   1. tm_01: pull the newest week(s) of dynasty trades from the Dynasty Daddy Trade Database (finished weeks skipped)
#   2. tm_04: refit dynasty on 1-for-1, 1-for-2, 2-for-2, 2-for-3 trades (about 1.5 h, one core)
#   3. tm_07 (R; the PC has no Python): write out/tm.js (the page data). refresh.sh copies it to the site and the aggregates to the Football repo.
# Raw trades (with league ids) stay in dd_trades/raw and are never copied anywhere.
# Folder: R Studio/Football2/research/dd_trades (scripts copied there). Log: logs/tm_<date>.txt; status: logs/tm_last_status.txt
# =============================================================================
set -u
export PATH="/c/Program Files/R/R-4.6.1/bin:$PATH"   # Rscript is not on Git Bash's PATH on Kyle's PC
DDT="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DDT/../../.." && pwd)"            # R Studio
SITE="${SITE_DIR:-$ROOT/ProspectActuary}"
mkdir -p "$DDT/logs"; LOG="$DDT/logs/tm_$(date +%Y-%m-%d_%H%M).txt"
say() { echo "$(date +%H:%M:%S) $*" | tee -a "$LOG"; }
fail() { say "FAILED: $*"; echo "FAILED $(date +%F) $*" > "$DDT/logs/tm_last_status.txt"; exit 1; }
cd "$DDT"
say "pull"; TM_TYPES=Dynasty Rscript tm_01_pull_dd_trades.R >> "$LOG" 2>&1 || fail "tm_01 pull"
say "fit";  TM_SHAPES=1-1,1-2,2-2,2-3 TM_TAG=add4 Rscript tm_04_additive_calibrated.R dynasty >> "$LOG" 2>&1 || fail "tm_04 fit"
say "site data"
Rscript tm_07_site_data.R "$DDT/out" "$SITE/data/sleeper_ids.json" "$DDT/out/tm.js" >> "$LOG" 2>&1 || fail "tm_07 site data"
echo "OK $(date +%F)" > "$DDT/logs/tm_last_status.txt"; say "done"
