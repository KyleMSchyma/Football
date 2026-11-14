#!/usr/bin/env bash
# Dev run of the weekly refresh (FABLE build): dev dynasty folder, the site worktree on the review branch, the Football
# review branch, no pre-draft regrade (it would edit the live Football2_PreDraft folder). Always NO_PUSH unless DEV_PUSH=1.
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
export DYN_DIR="$ROOT/Football2_Dynasty_dev" SITE_DIR="$ROOT/ProspectActuary_wt" SITE_BRANCH="claude/project-thread-huep4j" \
       FOOTBALL_BRANCH="claude/project-thread-huep4j" SKIP_PREDRAFT=1 ARCHIVE_DIR="${ARCHIVE_DIR:-$HERE/archive}"
[ -z "${DEV_PUSH:-}" ] && export NO_PUSH=1
bash "$HERE/refresh.sh"
