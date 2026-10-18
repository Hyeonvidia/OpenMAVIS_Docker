#!/usr/bin/env python3
"""ATE per run, multi vs stereo, per Hilti sequence -> docs/media/hilti_ate.png"""
import re
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

root = Path(sys.argv[1] if len(sys.argv) > 1 else "results/hilti")
out = Path(sys.argv[2] if len(sys.argv) > 2 else "docs/media/hilti_ate.png")

SEQS = [("exp14_basement_2", "exp14\nbasement 2"),
        ("exp18_corridor_lower_gallery_2", "exp18\ncorridor lower gallery 2"),
        ("exp16_attic_to_upper_gallery_2", "exp16\nattic to upper gallery 2")]
MODES = [("multi", "OpenMAVIS 4-camera + IMU", "#2a78d6", -0.17),
         ("stereo", "stereo-inertial (front pair) + IMU", "#eb6834", 0.17)]
SURFACE, INK, INK2, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e4e3df"


def ate(run):
    f = run / "ate.txt"
    m = re.search(r"rmse\s+([\d.]+)", f.read_text()) if f.exists() else None
    return float(m.group(1)) if m else None


fig, ax = plt.subplots(figsize=(8, 4.2), dpi=150)
fig.patch.set_facecolor(SURFACE)
ax.set_facecolor(SURFACE)
for i, (seq, _) in enumerate(SEQS):
    for mode, label, color, dx in MODES:
        vals = [ate(r) for r in sorted((root / seq / mode).glob("r*"))]
        ok = [v for v in vals if v is not None]
        x = i + dx
        if ok:
            ax.scatter([x] * len(ok), ok, s=64, color=color, edgecolors=SURFACE, linewidths=2,
                       zorder=3, label=label if i == 0 else None)
            mean = sum(ok) / len(ok)
            ax.hlines(mean, x - 0.11, x + 0.11, color=color, linewidth=2, zorder=2)
            ax.text(x + 0.13, mean, f"{mean:.3f}", va="center", ha="left", fontsize=8, color=INK2)
        failed = len(vals) - len(ok)
        if failed:
            ax.text(x, 0.012, f"{failed}/{len(vals)} runs\naborted,\nno trajectory",
                    ha="center", va="bottom", fontsize=8, color=INK2)

ax.set_xticks(range(len(SEQS)), [s[1] for s in SEQS], fontsize=9, color=INK)
ax.set_xlim(-0.6, len(SEQS) - 0.4)
ax.set_ylim(0, 0.25)
ax.set_ylabel("ATE RMSE, m  (SE(3)-aligned)", fontsize=9, color=INK2)
ax.tick_params(axis="y", labelsize=8, colors=INK2, length=0)
ax.tick_params(axis="x", length=0)
ax.grid(axis="y", color=GRID, linewidth=0.8)
ax.set_axisbelow(True)
for s in ax.spines.values():
    s.set_visible(False)
ax.set_title("Hilti 2022, 3 runs each: dots = runs, bar = mean", fontsize=10, color=INK, loc="left")
leg = ax.legend(loc="upper left", fontsize=8, frameon=False, labelcolor=INK2)
fig.tight_layout()
out.parent.mkdir(parents=True, exist_ok=True)
fig.savefig(out, facecolor=SURFACE)
print(out)
