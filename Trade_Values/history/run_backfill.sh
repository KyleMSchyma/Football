#!/usr/bin/env bash
# Point-in-time value history: every snapshot, then the track record and the site files.
#   bash run_backfill.sh DYN_DIR OUT_DIR [SITE_DIR] [JOBS]
# DYN_DIR = the dynasty model folder (Football2_Dynasty); OUT_DIR gets snapshots/, scored/, values/.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; DYN="$1"; OUT="$2"; SITE="${3:-}"; JOBS="${4:-4}"
mkdir -p "$OUT/snapshots" "$OUT/scored" "$OUT/values" "$OUT/logs"
LAST_WK=$(cd "$DYN" && Rscript -e 'x <- readRDS("nfl_weekly_2026.rds"); cat(max(x$week[x$season_type == "REG"]))')
{ for s in $(seq 2016 2025); do n=$([ "$s" -ge 2021 ] && echo 18 || echo 17); for w in $(seq 1 "$n"); do echo "$s $w"; done; done
  for w in $(seq 1 "$LAST_WK"); do echo "2026 $w"; done; } > "$OUT/jobs.txt"
cd "$DYN"
xargs -P "$JOBS" -L1 sh -c 'f=$(printf "%s/snapshots/hv_%d_w%02d.rds" "'"$OUT"'" $0 $1); [ -f "$f" ] && exit 0;
  Rscript "'"$HERE"'/hv_01_snapshot.R" $0 $1 "'"$OUT"'/snapshots" 2>"'"$OUT"'/logs/err_$0_$1.txt" || echo "FAILED $0 $1"' < "$OUT/jobs.txt"
Rscript "$HERE/hv_02_track_record.R" "$OUT/snapshots" "$OUT/scored"
Rscript "$HERE/hv_04_export_csv.R" "$OUT/snapshots" "$OUT/values"
[ -n "$SITE" ] && Rscript "$HERE/hv_03_site_data.R" "$OUT/snapshots" "$OUT/scored" "$SITE"
echo "done"
