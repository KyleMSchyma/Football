#!/usr/bin/env bash
# =============================================================================
# Weekly refresh, 2026 NFL regular season (runs every Tuesday morning through Week 18)
#
#   1. pull fresh nflverse data: 2026 weekly player stats, injury report, weekly rosters
#   2. re-run the redraft (rest-of-season) and dynasty trade values for every scoring preset, plus rookie picks (dv_13 -> dv_10 + dv_11)
#   3. rebuild the Prospect Actuary "Trade values" page                 (dv_12)
#      and the Dynasty Daddy snapshot for the "Value research" page     (dv_14, called by dv_12)
#   4. while the college regular season is on: re-pull CFBD 2026 stats and re-grade the 2027 pre-draft
#      prospects (pd_01 pro-rated + as-is, pd_06), then refresh the pre-draft page data
#   5. push: ProspectActuary main (the live site) and the Football repo (branch or main, see FOOTBALL_BRANCH)
#
# Post-draft grades are not re-run: they use draft capital and college data only, so new NFL weeks
# do not change them. The old /dynasty/ page is never published by this script.
#
# usage:  bash refresh.sh            full run with pushes
#         NO_PUSH=1 bash refresh.sh  everything except git push
# =============================================================================
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
DYN="$ROOT/Football2_Dynasty"; PRE="$ROOT/Football2_PreDraft"
SITE="$ROOT/ProspectActuary"; REPO="$ROOT/Football_repo"
FOOTBALL_BRANCH="${FOOTBALL_BRANCH:-main}"   # Kyle 2026-11-11: push straight to main ("weekly-refresh" = branch + one PR instead)
PREDRAFT_UNTIL="2026-12-16"                             # CFBD regular season is over by then; grades stop changing
STAMP="$(date +%Y-%m-%d_%H%M)"; LOGDIR="$HERE/logs/$STAMP"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/refresh.txt"
say()  { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }
fail() { say "FAILED: $*"; echo "FAILED $STAMP: $*" > "$HERE/logs/last_status.txt"; exit 1; }
rr()   { local dir="$1" script="$2" log="$3"; shift 3; say "R: $script $*"
         "$HERE/run_r.sh" "$dir" "$script" "$LOGDIR/$log" "$@" || fail "$script (see $LOGDIR/$log)"; }

say "weekly refresh start ($STAMP), Football repo target: $FOOTBALL_BRANCH"

# ---------- 0. site repo must be clean, on main, and current ----------
cd "$SITE" || fail "no ProspectActuary folder"
[ "$(git branch --show-current)" = "main" ] || fail "ProspectActuary is not on main"
[ -z "$(git status --porcelain)" ] || fail "ProspectActuary has uncommitted changes; commit or discard them first"
git pull -q --ff-only origin main >> "$LOG" 2>&1 || fail "git pull ProspectActuary"

# ---------- 1. data ----------
rr "$HERE" rf_01_pull_nfl.R 01_pull_nfl.txt
cat "$LOGDIR/01_pull_nfl.txt" >> "$LOG"

# ---------- 4. pre-draft grades (college season only) ----------
PRE_DONE=0
if [[ "$(date +%Y-%m-%d)" < "$PREDRAFT_UNTIL" || "$(date +%Y-%m-%d)" == "$PREDRAFT_UNTIL" ]]; then
  mkdir -p "$LOGDIR/cfbd_prev"
  for f in cfbd_stats_2026.rds cfbd_team_stats_2026.rds; do [ -f "$PRE/cache/$f" ] && mv "$PRE/cache/$f" "$LOGDIR/cfbd_prev/"; done
  restore() { for f in cfbd_stats_2026.rds cfbd_team_stats_2026.rds; do [ -f "$LOGDIR/cfbd_prev/$f" ] && cp "$LOGDIR/cfbd_prev/$f" "$PRE/cache/"; done; }
  "$HERE/run_r.sh" "$PRE" pd_01_pool_build.R "$LOGDIR/04_pd01.txt" || { restore; fail "pd_01 (see 04_pd01.txt)"; }
  PD_NO_SCALE=1 "$HERE/run_r.sh" "$PRE" pd_01_pool_build.R "$LOGDIR/04_pd01_asis.txt" || { restore; fail "pd_01 as-is"; }
  rr "$PRE" pd_06_player_grades.R 05_pd06.txt
  rr "$HERE" rf_02_predraft_page.R 06_predraft_page.txt "$SITE/pre-draft/index.html"
  cp "$PRE"/pd_player_grades.csv "$PRE"/pd_grade_validation.csv "$PRE"/pd_grade_vs_pick.csv \
     "$PRE"/pd_grade_by_round.csv "$PRE"/pd_grade_scale.csv "$SITE/pre-draft/data/"
  PRE_DONE=1; say "pre-draft 2027 board refreshed"
else
  say "pre-draft skipped (college regular season over)"
fi

# ---------- 2-3. trade values (after the pre-draft grades: 2027 rookie picks come from them) ----------
rr "$DYN" dv_13_league_presets.R 02_values.txt       # runs dv_11 (and dv_10) once per scoring preset group; default run writes the usual boards
rr "$DYN" dv_12_trade_values_page.R 03_page.txt
cat "$LOGDIR/03_page.txt" >> "$LOG"


# ---------- 5a. publish the site ----------
cd "$SITE"
[ -e dynasty ] && fail "a dynasty/ folder is on the site; it must stay unpublished. Nothing pushed."
git add trade-values pre-draft value-research   # value-research/data/dd.js: Dynasty Daddy snapshot (dv_14, run by dv_12)
WK="$(grep -o 'through week [0-9]*' "$SITE/trade-values/index.html" | head -1)"
WHAT=""; [ "$PRE_DONE" = 1 ] && WHAT=" and 2027 pre-draft grades"
if git diff --cached --quiet; then say "site: no changes"
else git commit -q -m "Weekly refresh: trade values$WHAT, 2026 stats $WK" >> "$LOG" 2>&1 || fail "site commit"; fi
if [ -n "$(git rev-list origin/main..HEAD)" ]; then
  if [ -z "${NO_PUSH:-}" ]; then git push -q origin main >> "$LOG" 2>&1 || fail "site push"; say "site pushed: $(git log -1 --format=%h)"
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
mkdir -p "$WT/Trade_Values/weekly_refresh"
cp "$DYN"/dv_common.R "$DYN"/dv_10_ros_value.R "$DYN"/dv_11_dynasty_v4.R "$DYN"/dv_12_trade_values_page.R "$DYN"/dv_14_value_research_data.R "$DYN"/tv_page_template.html \
   "$DYN"/dv_ros_2026_board.csv "$DYN"/dv_v4_board.csv "$DYN"/dv_v4_backtest.csv "$DYN"/dv_ros_backtest_parts.csv \
   "$DYN"/dv_ros_backtest_value.csv "$DYN"/dv_ros_credibility_k.csv "$DYN"/dv_13_league_presets.R "$DYN"/dv_league_backtest.csv \
   "$DYN"/dv_scoring_backtest.csv "$DYN"/dv_anchor_check.csv "$WT/Trade_Values/"
cp "$HERE"/refresh.sh "$HERE"/run_r.sh "$HERE"/rf_01_pull_nfl.R "$HERE"/rf_02_predraft_page.R "$HERE"/run_weekly.cmd \
   "$HERE"/README.md "$WT/Trade_Values/weekly_refresh/" 2>/dev/null
if [ "$PRE_DONE" = 1 ]; then
  cp "$PRE"/pd_player_grades.csv "$PRE"/pd_grade_validation.csv "$PRE"/pd_grade_vs_pick.csv "$PRE"/pd_grade_by_round.csv \
     "$PRE"/pd_grade_scale.csv "$WT/PreDraft_Model/"
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
