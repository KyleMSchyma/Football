#!/usr/bin/env bash
# =============================================================================
# Weekly refresh, 2026 NFL regular season (runs every Tuesday morning through Week 18)
#
#   1. pull fresh nflverse data: 2026 weekly player stats, injury report, weekly rosters            (rf_01)
#   1b. role data for the trade values: depth charts, injuries, weekly rosters, snap counts, schedule (rl_00, rl_01
#       in the dynasty folder). A failed pull reuses last week's file and says so in the log; the run goes on.
#   2. re-run the redraft (rest-of-season) and dynasty trade values for every scoring preset, plus rookie picks (dv_13 -> dv_10 + dv_11)
#   3. rebuild the Prospect Actuary "Trade values" page                 (dv_12)
#      and the Dynasty Daddy snapshot for the "Value research" page     (dv_14, called by dv_12)
#   3c. browser vs R reconciliation data (dv_15)
#   4. while the college regular season is on: re-pull CFBD 2026 stats and re-grade the 2027 pre-draft
#      prospects (pd_01 pro-rated + as-is, pd_06, pd_11 drafted recalibration)
#   4b. after dv_13, every week: swap the data lines of the pre-draft and post-draft grade pages (rf_02, pd_10),
#      which carry the cross-position Value column (dv_rookie_board_values.csv from dv_13)
#   G. OUTPUT GATES (rf_03): every team in the latest week, no missing values, replacement lines and pick multiplier in
#      range, top-50 turnover vs last week, R and browser reconciliation. A failed gate stops the run: nothing is
#      committed or pushed.
#   A. dated archive of the week's redraft, dynasty and pick values + biggest movers (rf_04), into Trade_Values/archive/
#   5. push: the site (SITE_BRANCH, main for the live site) and the Football repo (FOOTBALL_BRANCH)
#   On any failure: a FAILED text file on the Desktop and a Windows popup, plus logs/last_status.txt.
#
# Post-draft grades are not re-run: they use draft capital and college data only, so new NFL weeks
# do not change them. The old /dynasty/ page is never published by this script.
#
# usage:  bash refresh.sh                    full run with pushes (live folders, site main, Football main)
#         NO_PUSH=1 bash refresh.sh          everything except git push
#         settings (environment): DYN_DIR, SITE_DIR, SITE_BRANCH, FOOTBALL_BRANCH, SKIP_PREDRAFT=1, ARCHIVE_DIR,
#         FORCE_GATE_FAIL=1 (test the failure path), NO_NOTIFY=1 (no popup). run_dev.sh sets the dev folders.
# =============================================================================
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
DYN="${DYN_DIR:-$ROOT/Football2_Dynasty}"; PRE="$ROOT/Football2_PreDraft"
SITE="${SITE_DIR:-$ROOT/ProspectActuary}"; REPO="$ROOT/Football_repo"
SITE_BRANCH="${SITE_BRANCH:-main}"
FOOTBALL_BRANCH="${FOOTBALL_BRANCH:-main}"   # Kyle 2026-11-11: push straight to main ("weekly-refresh" = branch + one PR instead)
ARCH="${ARCHIVE_DIR:-$HERE/archive}"; mkdir -p "$ARCH"
PREDRAFT_UNTIL="2026-12-16"                             # CFBD regular season is over by then; grades stop changing
STAMP="$(date +%Y-%m-%d_%H%M)"; LOGDIR="$HERE/logs/$STAMP"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/refresh.txt"
export DYN_DIR="$DYN" SITE_DIR="$SITE" ARCHIVE_DIR="$ARCH"
say()  { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }
notify() {                                   # visible notice on the PC: Desktop file + popup (popup runs in the background)
  local msg="$1" desk; desk="$(powershell.exe -NoProfile -Command "[Environment]::GetFolderPath('Desktop')" 2>/dev/null | tr -d '\r')"
  [ -n "$desk" ] && printf 'Prospect Actuary weekly refresh FAILED (%s)\r\n%s\r\nLog: %s\r\nNothing was pushed after the failed step.\r\n' "$STAMP" "$msg" "$(cygpath -w "$LOG" 2>/dev/null || echo "$LOG")" \
    > "$(cygpath -u "$desk" 2>/dev/null || echo "$desk")/PROSPECT_ACTUARY_REFRESH_FAILED.txt"
  if [ -z "${NO_NOTIFY:-}" ]; then
    local m="${msg//\'/}"; m="${m:0:300}"
    powershell.exe -NoProfile -WindowStyle Hidden -Command "Add-Type -AssemblyName PresentationFramework; [void][System.Windows.MessageBox]::Show('Weekly refresh FAILED: $m. See PROSPECT_ACTUARY_REFRESH_FAILED.txt on the Desktop.', 'Prospect Actuary refresh')" >/dev/null 2>&1 &
  fi
}
fail() { say "FAILED: $*"; echo "FAILED $STAMP: $*" > "$HERE/logs/last_status.txt"; notify "$*"; exit 1; }
rr()   { local dir="$1" script="$2" log="$3"; shift 3; say "R: $script $*"
         "$HERE/run_r.sh" "$dir" "$script" "$LOGDIR/$log" "$@" || fail "$script (see $LOGDIR/$log)"; }

say "weekly refresh start ($STAMP): dynasty folder $DYN, site $SITE ($SITE_BRANCH), Football repo target: $FOOTBALL_BRANCH"

# ---------- 0. site repo must be clean, on its branch, and current ----------
cd "$SITE" || fail "no site folder $SITE"
[ "$(git branch --show-current)" = "$SITE_BRANCH" ] || fail "site checkout is not on $SITE_BRANCH"
[ -z "$(git status --porcelain)" ] || fail "site checkout has uncommitted changes; commit or discard them first"
git pull -q --ff-only origin "$SITE_BRANCH" >> "$LOG" 2>&1 || fail "git pull site ($SITE_BRANCH)"

# ---------- 1. data ----------
rr "$HERE" rf_01_pull_nfl.R 01_pull_nfl.txt
cat "$LOGDIR/01_pull_nfl.txt" >> "$LOG"
# 1b. role data (depth charts, injuries, rosters): guarded, a failure keeps last week's files
if "$HERE/run_r.sh" "$DYN" rl_00_pull_role_data.R "$LOGDIR/01b_role_pull.txt"; then
  grep -h "REUSED\|failed" "$LOGDIR/01b_role_pull.txt" | sed 's/^/  role data: /' | tee -a "$LOG"
  say "role data pulled"
else say "WARNING: role data pull failed, reusing last week's cached files (see 01b_role_pull.txt)"; fi
if "$HERE/run_r.sh" "$DYN" rl_01_role_build.R "$LOGDIR/01c_role_build.txt"; then say "role tables rebuilt"
else say "WARNING: role table build failed, reusing last week's tables (see 01c_role_build.txt)"; fi

# ---------- 4. pre-draft grades (college season only) ----------
PRE_DONE=0
if [ -z "${SKIP_PREDRAFT:-}" ] && [[ "$(date +%Y-%m-%d)" < "$PREDRAFT_UNTIL" || "$(date +%Y-%m-%d)" == "$PREDRAFT_UNTIL" ]]; then
  mkdir -p "$LOGDIR/cfbd_prev"
  for f in cfbd_stats_2026.rds cfbd_team_stats_2026.rds; do [ -f "$PRE/cache/$f" ] && mv "$PRE/cache/$f" "$LOGDIR/cfbd_prev/"; done
  restore() { for f in cfbd_stats_2026.rds cfbd_team_stats_2026.rds; do [ -f "$LOGDIR/cfbd_prev/$f" ] && cp "$LOGDIR/cfbd_prev/$f" "$PRE/cache/"; done; }
  "$HERE/run_r.sh" "$PRE" pd_01_pool_build.R "$LOGDIR/04_pd01.txt" || { restore; fail "pd_01 (see 04_pd01.txt)"; }
  PD_NO_SCALE=1 "$HERE/run_r.sh" "$PRE" pd_01_pool_build.R "$LOGDIR/04_pd01_asis.txt" || { restore; fail "pd_01 as-is"; }
  rr "$PRE" pd_06_player_grades.R 05_pd06.txt
  rr "$PRE" pd_11_drafted_calibration.R 05b_pd11.txt   # pre-draft probabilities conditional on being drafted (2027 picks + Value column)
  cp "$PRE"/pd_player_grades.csv "$PRE"/pd_grade_validation.csv "$PRE"/pd_grade_vs_pick.csv \
     "$PRE"/pd_grade_by_round.csv "$PRE"/pd_grade_scale.csv "$SITE/pre-draft/data/"
  PRE_DONE=1; say "pre-draft 2027 board refreshed"
else
  say "pre-draft skipped (college regular season over, or SKIP_PREDRAFT)"
fi

# ---------- 2-3. trade values (after the pre-draft grades: 2027 rookie picks come from them) ----------
rr "$DYN" dv_13_league_presets.R 02_values.txt       # runs dv_11 (and dv_10) once per scoring preset group; default run writes the usual boards
cp "$LOGDIR/02_values.txt" "$DYN/dv_13_log.txt"      # read by the reconciliation gate
rr "$DYN" dv_12_trade_values_page.R 03_page.txt
cat "$LOGDIR/03_page.txt" >> "$LOG"
rr "$DYN" dv_15_board_value_check.R 03c_dv15.txt     # board values + browser reconciliation data (dv_15_expected.js)

# ---------- 3b. grade pages: swap only their data lines (window.PD, window.MOCK27) ----------
# Runs every week, after dv_13: the boards' cross-position Value column (dv_rookie_board_values.csv) moves with the
# NFL replacement lines even after the college season. The post-draft grades themselves are not re-run.
rr "$HERE" rf_02_predraft_page.R 06_predraft_page.txt "$SITE/pre-draft/index.html"
"$HERE/run_r.sh" "$ROOT/Football2_PostDraft" pd_10_site_page.R "$LOGDIR/06b_postdraft_page.txt" "$SITE/post-draft/index.html" || fail "post-draft page (see 06b_postdraft_page.txt)"
cp "$DYN"/dv_rookie_board_values.csv "$SITE/pre-draft/data/rookie_board_values.csv"

# ---------- G. output gates: nothing is committed or pushed unless every gate passes ----------
"$HERE/run_r.sh" "$HERE" rf_03_gates.R "$LOGDIR/08_gates.txt" "$LOGDIR/gates_report.csv"; GST=$?
grep "^\[" "$LOGDIR/08_gates.txt" | tee -a "$LOG"
[ "$GST" = 0 ] || fail "output gates: $(grep '^\[FAIL\]' "$LOGDIR/08_gates.txt" | sed 's/^\[FAIL\] //' | tr '\n' ';')"

# ---------- A. dated archive + biggest movers ----------
rr "$HERE" rf_04_archive.R 09_archive.txt
grep -h "archived\|movers" "$LOGDIR/09_archive.txt" | tee -a "$LOG"

# ---------- 5a. publish the site ----------
cd "$SITE"
[ -e dynasty ] && fail "a dynasty/ folder is on the site; it must stay unpublished. Nothing pushed."
git add trade-values pre-draft post-draft value-research   # value-research/data/dd.js: Dynasty Daddy snapshot (dv_14, run by dv_12)
WK="$(grep -o 'through week [0-9]*' "$SITE/trade-values/index.html" | head -1)"
WHAT=""; [ "$PRE_DONE" = 1 ] && WHAT=" and 2027 pre-draft grades"
if git diff --cached --quiet; then say "site: no changes"
else git commit -q -m "Weekly refresh: trade values$WHAT, 2026 stats $WK" >> "$LOG" 2>&1 || fail "site commit"; fi
if [ -n "$(git rev-list "origin/$SITE_BRANCH"..HEAD)" ]; then
  if [ -z "${NO_PUSH:-}" ]; then git push -q origin "$SITE_BRANCH" >> "$LOG" 2>&1 || fail "site push"; say "site pushed: $(git log -1 --format=%h)"
  else say "site committed locally, not pushed (NO_PUSH)"; fi
fi

# ---------- 5b. Football repo, through a temporary worktree (other work may have the checkout on another branch) ----------
cd "$REPO" || fail "no Football_repo"
git fetch -q origin >> "$LOG" 2>&1 || fail "git fetch Football"
BASE="origin/main"
if [ "$FOOTBALL_BRANCH" != "main" ] && git rev-parse -q --verify "origin/$FOOTBALL_BRANCH" >/dev/null \
   && ! git merge-base --is-ancestor "origin/$FOOTBALL_BRANCH" origin/main; then BASE="origin/$FOOTBALL_BRANCH"; fi
WT="$(mktemp -d)/football_wt"
git worktree add -q --detach "$WT" "$BASE" >> "$LOG" 2>&1 || fail "worktree"
cleanup_wt() { cd "$REPO"; git worktree remove --force "$WT" >/dev/null 2>&1; }
mkdir -p "$WT/Trade_Values/weekly_refresh" "$WT/Trade_Values/archive"
cp "$DYN"/dv_common.R "$DYN"/dv_10_ros_value.R "$DYN"/dv_11_dynasty_v4.R "$DYN"/dv_12_trade_values_page.R "$DYN"/dv_14_value_research_data.R "$DYN"/tv_page_template.html \
   "$DYN"/dv_ros_2026_board.csv "$DYN"/dv_v4_board.csv "$DYN"/dv_v4_backtest.csv "$DYN"/dv_ros_backtest_parts.csv \
   "$DYN"/dv_ros_backtest_value.csv "$DYN"/dv_ros_credibility_k.csv "$DYN"/dv_13_league_presets.R "$DYN"/dv_league_backtest.csv \
   "$DYN"/dv_scoring_backtest.csv "$DYN"/dv_anchor_check.csv "$DYN"/dv_rookie_board_values.csv "$WT/Trade_Values/"
cp "$DYN"/rl_00_pull_role_data.R "$DYN"/rl_01_role_build.R "$DYN"/rl_common.R "$DYN"/rl_dv10.R "$DYN"/rl_dv11_ext.R "$DYN"/rl_dv11_qb.R \
   "$DYN"/dv_15_board_value_check.R "$DYN"/dv_15_check.js "$WT/Trade_Values/" 2>/dev/null
cp "$ARCH"/*.csv "$WT/Trade_Values/archive/" 2>/dev/null
cp "$HERE"/refresh.sh "$HERE"/run_r.sh "$HERE"/rf_01_pull_nfl.R "$HERE"/rf_02_predraft_page.R "$HERE"/rf_03_gates.R "$HERE"/rf_04_archive.R \
   "$HERE"/rf_gate_limits.csv "$HERE"/run_weekly.cmd "$HERE"/README.md "$WT/Trade_Values/weekly_refresh/" 2>/dev/null
if [ "$PRE_DONE" = 1 ]; then
  cp "$PRE"/pd_player_grades.csv "$PRE"/pd_grade_validation.csv "$PRE"/pd_grade_vs_pick.csv "$PRE"/pd_grade_by_round.csv \
     "$PRE"/pd_grade_scale.csv "$PRE"/pd_player_probs_drafted.csv "$PRE"/pd_drafted_calibration.csv "$PRE"/pd_drafted_calibration_check.csv \
     "$PRE"/pd_drafted_calibration_bins.csv "$WT/PreDraft_Model/"
  "$HERE/run_r.sh" "$HERE" rf_02_predraft_page.R "$LOGDIR/07_repo_page.txt" "$WT/PreDraft_Model/pd_player_grades.html" || { cleanup_wt; fail "repo pre-draft page"; }
fi
cd "$WT"
KEY="$(sed -n 's/^CFBD_API_KEY=//p' C:/Users/kylem/Documents/.Renviron | tr -d '\r\n"')"
if [ -n "$KEY" ] && git grep -q -I -F "$KEY" -- . ; then cleanup_wt; fail "CFBD key found in repo files; nothing pushed"; fi
git add -A Trade_Values PreDraft_Model
if git diff --cached --quiet; then say "Football repo: no changes"
else
  git -c user.name="Kyle" -c user.email="329119484+kylejoe05-ai@users.noreply.github.com" commit -q \
    -m "Weekly refresh: trade values$WHAT, 2026 stats $WK" >> "$LOG" 2>&1 || { cleanup_wt; fail "Football commit"; }
  if [ -z "${NO_PUSH:-}" ]; then
    git push -q origin "HEAD:refs/heads/$FOOTBALL_BRANCH" >> "$LOG" 2>&1 || { cleanup_wt; fail "Football push"; }
    say "Football pushed to $FOOTBALL_BRANCH: $(git log -1 --format=%h)"
    if [ "$FOOTBALL_BRANCH" != "main" ]; then     # one open PR for the branch; later weeks just add commits to it
      TOKEN="$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill 2>/dev/null | sed -n 's/^password=//p')"
      API="https://api.github.com/repos/KyleMSchyma/Football/pulls"
      if ! curl -s -H "Authorization: token $TOKEN" "$API?state=open&head=KyleMSchyma:$FOOTBALL_BRANCH" | grep -q '"number"'; then
        curl -s -H "Authorization: token $TOKEN" -X POST "$API" -d "{\"title\":\"Weekly refresh: 2026 trade values and pre-draft grades\",\"head\":\"$FOOTBALL_BRANCH\",\"base\":\"main\",\"body\":\"Automatic weekly refresh from Kyle's PC (Weekly_Refresh/refresh.sh). Each Tuesday through Week 18 adds a commit with updated trade values (Trade_Values/) and, during the college season, updated 2027 pre-draft grades (PreDraft_Model/). Merge whenever you like; the next run starts a new PR.\"}" \
          | grep -o '"html_url": *"[^"]*pull[^"]*"' | head -1 | tee -a "$LOG"
      fi
    fi
  else say "Football committed in worktree only (NO_PUSH)"; fi
fi
cleanup_wt

echo "OK $STAMP: $WK" > "$HERE/logs/last_status.txt"
say "done"
