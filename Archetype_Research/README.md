# Archetype_Research

Research only (2026-11-28). Formal, data-based player archetypes for QB, RB, WR and TE, and a check of whether they are
well separated and stable. **Write-ups with all charts: [ARCHETYPES.md](ARCHETYPES.md) (definitions, approved 11-28) and [DOUBLE_COUNT.md](DOUBLE_COUNT.md) (step 2: double counting test).** No model, value or site change.

Run (Python 3 with pandas, pyarrow, scikit-learn, matplotlib, pyreadr), from this folder:

```
# download nflverse parquet files (play_by_play_YYYY, pbp_participation_YYYY, snap_counts_YYYY,
# stats_player_reg_YYYY for 2016-2026; players, ngs_passing) into <dir>, then:
python3 ar_01_build.py <dir>        # -> ar_player_seasons.csv (not committed, ~2.4 MB; rebuildable)
python3 ar_02_features.py <dir>     # -> ar_features_{POS}.csv (not committed; rebuildable)
python3 ar_03_rules.py              # -> ar_labels_{POS}.csv  (qualifying seasons, features, labels, role/style layers)
python3 ar_04_separation.py         # -> tables/, plots/, ar_separation_summary.csv
python3 ar_05_college_proxies.py    # -> tables/college_proxy_auc.csv, plots/college_proxies.png
python3 ar_06_two_layer.py          # -> tables/two_layer_*.csv, plots/two_layer_persistence.png
python3 ar_07_double_count.py      # step 2 -> tables/dc_*.csv, plots/dc_*.png (needs scipy)
```

All thresholds live in `ar_03_rules.py`. Data: nflverse (CC BY 4.0) and the repo's cfbfastR college tables.
