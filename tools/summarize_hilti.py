#!/usr/bin/env python3
"""Collects results/hilti/<seq>/<mode>/<run>/ into results/hilti/summary.md."""
import re
import statistics as st
import sys
from pathlib import Path

root = Path(sys.argv[1] if len(sys.argv) > 1 else "results/hilti")
rows = []
for run in sorted(root.glob("*/*/r*")):
    seq, mode, tag = run.parts[-3:]
    status = (run / "status.txt").read_text() if (run / "status.txt").exists() else ""
    log = (run / "run.log").read_text(errors="replace") if (run / "run.log").exists() else ""
    ate = (run / "ate.txt").read_text() if (run / "ate.txt").exists() else ""
    rc = re.search(r"exit=(-?\d+)", status)
    wall = re.search(r"wall_s=([\d.]+)", status)
    rmse = re.search(r"rmse\s+([\d.]+)", ate)
    maps = re.search(r"There are (\d+) maps", log)
    kfs = re.findall(r"Map \d+ has (\d+) KFs", log)
    traj = run / "CameraTrajectory.txt"
    poses = sum(1 for l in traj.open() if not l.startswith("#")) if traj.exists() else 0
    ts = Path("/datasets/Hilti2022/euroc") / seq / "timestamps.txt"
    frames = sum(1 for _ in ts.open()) if ts.exists() else None
    rows.append(dict(seq=seq, mode=mode, tag=tag, rc=int(rc.group(1)) if rc else None,
                     wall=float(wall.group(1)) if wall else None,
                     rmse=float(rmse.group(1)) if rmse else None,
                     maps=int(maps.group(1)) if maps else None,
                     kfs=max(map(int, kfs)) if kfs else None,
                     poses=poses, frames=frames))

out = ["| sequence | mode | run | exit | ATE RMSE, m | maps | KFs (largest map) | poses / frames | wall, s |",
       "|---|---|---|---:|---:|---:|---:|---:|---:|"]
for r in rows:
    f = lambda v, fmt="{}": "—" if v is None else fmt.format(v)
    out.append(f"| {r['seq']} | {r['mode']} | {r['tag']} | {f(r['rc'])} | {f(r['rmse'], '{:.3f}')} | "
               f"{f(r['maps'])} | {f(r['kfs'])} | {r['poses']} / {f(r['frames'])} | {f(r['wall'], '{:.0f}')} |")

out += ["", "| sequence | mode | runs | ATE mean, m | ATE std, m | ATE min–max, m | no trajectory | crash after saving |",
        "|---|---|---:|---:|---:|---:|---:|---:|"]
for key in sorted({(r["seq"], r["mode"]) for r in rows}):
    g = [r for r in rows if (r["seq"], r["mode"]) == key]
    v = [r["rmse"] for r in g if r["rmse"] is not None]
    lost = sum(1 for r in g if r["rmse"] is None)
    late = sum(1 for r in g if r["rmse"] is not None and r["rc"] != 0)
    out.append(f"| {key[0]} | {key[1]} | {len(g)} | "
               + (f"{st.mean(v):.3f} | {st.stdev(v) if len(v) > 1 else 0:.3f} | {min(v):.3f}–{max(v):.3f}" if v else "— | — | —")
               + f" | {lost} | {late} |")
text = "\n".join(out) + "\n"
(root / "summary.md").write_text(text)
print(text)
