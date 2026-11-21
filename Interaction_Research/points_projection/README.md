# Points projections: post-draft + mixed versions, and rookie values on points (2026-11-21)

Kyle asked: show projected 3-year points next to the grade, build post-draft and mixed versions (model parity), and backtest
rookie values using projected rookie-year points instead of the tier-hit odds. **Research only: nothing live changed.**
Scripts were run from the project files folder (`research/points_projection/`) and use absolute paths; `exp_rookie_env.R` runs
from a copy of Football2_Dynasty (it evaluates dv_13 up to the scoring loop plus dv_11, default scoring, NO_WRITE).

| Script | What |
| --- | --- |
| `pp_01_oof_table.R` | out-of-class projections per player from `../ix_*` runs (3-yr and rookie-year, hit and log-points) |
| `pp_02_mixed.R` | mixed points: post-draft log points + faller bump / + points-faller bump / post+pre stack, second-stage LOCO |
| `pp_03_value_backtest.R` | rookie value backtest 2016-2022 drafted players: live dv_13 tier method vs points projections |
| `pp_04_final_projections.R` | final models (trained 2010-2023) for 2024-2027 rows + calibrated expected points for the boards |
| `pp_05_site_preview.py` | injects the "Proj. pts" column into the site boards (prospect-actuary preview branch) |

## Results

**Mixed points** (`mixed_points_metrics.csv`, charts 01-02): the faller bump fixes fallers' projected level (e.g. WR fallers
typical 3-yr points 82 -> 149 vs 152 actual) but overall ranking doesn't improve (Spearman -0.006 to -0.031; TE worst).
The live mixed hit grade doesn't improve overall ranking either (.685 vs .686 QB, .633 vs .636 WR).

**Rookie values** (`value_backtest_cross.csv`, `value_backtest_by_pos.csv`, charts 03-06). Realized value = dv_13's players'
definition (discounted points over the draft season's replacement line, seasons to 2025). Mapped methods turn a projection into
season-by-season points over replacement with the same quasi-Poisson spline mapping (+ age), fit out of class.

| Method | Spearman vs realized value (all positions, within class) | 12-pick rookie draft, realized per class |
| --- | --- | --- |
| Live tier method (dv_13) | **0.540** | 1,300 |
| Tier method, research hit model | 0.522 | 1,309 |
| Hit model 3-yr (mapped) | 0.505 | 1,324 |
| Points 3-yr, mixed | 0.502 | 1,261 |
| Points, rookie year | 0.501 | 1,183 |
| Points 3-yr | 0.495 (gap CI below 0) | 1,195 |
| Pre-draft points 3-yr | 0.319 | 977 |

The live tier method is best at every position. Value counts only points above replacement, so it's driven by the chance of a
big season, which the tier odds measure directly. **Recommendation: keep the tier method for values; points only as a display column.**

**Board numbers** (`proj_points_*.csv`, `proj_points_calibration.csv`): expected 3-year PPR points, a quasi-Poisson spline of
actual points on the log projection (out of class). Post-draft mean projected vs actual: QB 224/212, RB 220/215, WR 206/200,
TE 137/137. Pre-draft includes the chance of going undrafted, so it runs low among drafted players.

## Follow-up: PPG model for rookie values (`pp_06_ppg_value.R`, charts 07-10)

Kyle's actual idea: project each rookie's PPG, then value = games x PPG over replacement. Stage 1: elastic net on the post-draft
inputs, target (A) rookie-year PPG or (B) seasons 1-3 PPG, weighted by games, out of class. Stage 2 (other classes): per season k,
PPG_k = a + b x projected PPG + c x age (residual sd = stop-loss spread), games_k from a spline of projected PPG. Value = sum v^k x
len x games x stoploss(PPG_k - replacement, sd_k), the same pieces dv_13 uses per tier.

| Method | Spearman vs realized value | 12-pick draft realized | Classes beating live (rank / draft) |
| --- | --- | --- | --- |
| Live tier method (dv_13, ordinal mixed model) | 0.540 | 1,300 | - |
| Tier method, research hit model | 0.522 | 1,309 | 2 / 2 of 7 |
| PPG model, rookie-year PPG | 0.519 (gap -0.021, CI -0.057 to 0.018) | 1,231 | 1 / 1 |
| PPG model, seasons 1-3 PPG | 0.516 (gap -0.024, CI -0.062 to 0.013) | 1,236 | 3 / 2 |

With the same underlying model family the PPG method and the tier method rank about equally (.519 vs .522); the live method's edge
comes mostly from the live (ordinal, mixed) model. PPG model accuracy (`ppg_model_accuracy.csv`): rookie PPG Spearman .42-.55,
seasons 1-3 PPG .54-.63.

## Follow-up: top-24 boards per class, three post-draft methods (`pp_07_top24_boards.R`, `rookie_top24.html`)

Kyle asked: top 24 rookies of every class under the current tier method (post-draft draft-only odds, not mixed), rookie-year PPG
and 3-year PPG, default scoring. Classes 2010-2022, out-of-class (2010-2015 use the 2016 replacement lines).
Board page: https://claude.ai/artifact/6UXRNYjU8YddKV9ajiXGej (`top24_boards.csv` has every player).

| Method | Top-24 realized value per class | Share of best 24 | Real top-24 caught | Classes beating current |
| --- | --- | --- | --- | --- |
| Current (tier odds) | 1,546 | 76% | 14.9 | - |
| Rookie-year PPG | 1,453 | 72% | 14.6 | 3 of 13 |
| 3-year PPG | 1,501 | 74% | 14.8 | 6 of 13 |

The three boards share about 21-22 of their 24 players in every class.
