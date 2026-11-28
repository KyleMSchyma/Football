"""Archetype research, step 3: rule-based archetype labels (one primary label per player-season, priority order).
Thresholds are round numbers near data percentiles of 2016-2025 qualifying seasons (see ARCHETYPES.md).
Run after ar_02_features.py -> ar_labels_{POS}.csv"""
import numpy as np, pandas as pd

def qb_label(d):
    rush = np.select([d.rush_ypg >= 30, d.rush_ypg >= 20], ["rush_high", "rush_mid"], "rush_low")
    risky = (d.int_rate >= 0.025) | (d.aggressiveness >= 18)
    manager = (d.adot_pass < 7.5) & (d.epa_db < 0.05)
    style = np.select([(d.adot_pass >= 8.5) & risky, manager], ["Gunslinger", "Game manager"], "Pocket passer")
    lab = np.select([rush == "rush_high", rush == "rush_mid"], ["Dual-threat", "Hybrid"], style)
    return lab, style

def rb_label(d):
    work = (d.snap_share >= 0.60) & (d.touches_pg >= 16)
    recv = (d.targets_pg >= 3.5) & (d.tgt_mix >= 0.28)
    power = (d.gl_share >= 0.45) & (d.tgt_mix < 0.20) & ((d.weight >= 220) | (d.explosive_rate < 0.045))
    expl = (d.explosive_rate >= 0.06) & (d.carries >= 50)
    comm = d.opp_share < 0.50
    return np.select([work, recv, power, expl, comm], ["Workhorse", "Receiving back", "Power / goal-line", "Explosive", "Committee"], "Lead back (balanced)")

def wr_label(d):
    x = (d.target_share >= 0.20) & (d.air_share >= 0.25) & (d.adot >= 9)
    deep = (d.adot >= 14) & (d.deep_rate >= 0.25)
    yac = (d.adot < 8) & (d.yac_per_rec >= 5) & ((d.behind_rate >= 0.20) | (d.carries_pg >= 0.5))
    big = ((d.height >= 75) | (d.weight >= 215)) & (d.rz_mix >= 0.15)
    poss = d.adot < 10
    return np.select([x, deep, yac, big, poss], ["X / alpha", "Deep threat", "YAC / gadget", "Big-bodied red zone", "Slot / possession"], "Outside #2 (intermediate)")

def te_label(d):
    has_tilt = d.run_tilt.notna()
    rec = d.targets_per_snap >= 0.10
    hybrid = rec & (d.snap_share >= 0.75)
    block = (d.targets_per_snap < 0.08) & ((d.run_tilt >= 0.05) | (~has_tilt & (d.targets_per_snap < 0.06)))
    rz = (d.targets_per_snap < 0.10) & (d.targets >= 15) & (d.rz_mix >= 0.25) & (d.td_per_tgt >= 0.08)
    return np.select([hybrid, rec, rz, block], ["Hybrid", "Receiving / move", "Red-zone specialist", "Inline / blocking"], "Rotational (no clear role)")

def two_layer(pos, d):
    """Alternative tested: separate ROLE (how much he is used) from STYLE (how he is used)."""
    if pos == "RB":
        role = np.select([(d.snap_share >= 0.60) & (d.touches_pg >= 16), d.opp_share >= 0.50], ["Workhorse", "Lead"], "Committee")
        style = np.select([(d.targets_pg >= 3) & (d.tgt_mix >= 0.25), (d.gl_share >= 0.45) | (d.weight >= 225),
                           (d.explosive_rate >= 0.06) & (d.carries >= 50)], ["Receiving", "Power", "Explosive"], "Balanced")
    elif pos == "WR":
        role = np.select([d.target_share >= 0.22, d.target_share >= 0.15], ["Alpha", "Starter"], "Rotational")
        style = np.select([(d.adot >= 14) & (d.deep_rate >= 0.25), (d.adot < 8) & (d.yac_per_rec >= 5) & ((d.behind_rate >= 0.20) | (d.carries_pg >= 0.5)),
                           ((d.height >= 75) | (d.weight >= 215)) & (d.rz_mix >= 0.15), d.adot < 10],
                          ["Deep", "YAC / gadget", "Big red zone", "Short / slot"], "Intermediate outside")
    elif pos == "TE":
        role = np.where(d.snap_share >= 0.75, "Every-down", np.where(d.snap_share >= 0.50, "Regular", "Part-time"))
        style = np.select([d.targets_per_snap >= 0.10, (d.targets_per_snap < 0.10) & (d.targets >= 15) & (d.rz_mix >= 0.25) & (d.td_per_tgt >= 0.08),
                           (d.targets_per_snap < 0.08) & ((d.run_tilt >= 0.05) | (d.run_tilt.isna() & (d.targets_per_snap < 0.06)))],
                          ["Receiver", "Red zone", "Blocker"], "Balanced")
    else:  # QB: rushing layer x passing layer
        role = np.select([d.rush_ypg >= 30, d.rush_ypg >= 20], ["Runner", "Mobile"], "Pocket")
        style = qb_label(d)[1]
    return role, style

if __name__ == "__main__":
    for pos, f in [("QB", qb_label), ("RB", rb_label), ("WR", wr_label), ("TE", te_label)]:
        d = pd.read_csv(f"ar_features_{pos}.csv"); d = d[d.qual].copy()
        res = f(d)
        if pos == "QB": d["archetype"], d["pass_style"] = res
        else: d["archetype"] = res
        d["role_layer"], d["style_layer"] = two_layer(pos, d)
        d.to_csv(f"ar_labels_{pos}.csv", index=False)
        h = d[d.season < 2026]
        print(f"\n{pos}  n={len(h)} (2016-25)"); print(h.archetype.value_counts().to_string())
        print("2026 examples:"); 
        for a, gdf in d[d.season == 2026].sort_values("fantasy_points_ppr", ascending=False).groupby("archetype"):
            print("  ", a, ":", ", ".join(gdf.display_name.head(6)))
