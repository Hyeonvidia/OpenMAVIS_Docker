#!/usr/bin/env python3
"""ROS1 bag -> EuRoC (ASL) folder, without a ROS install.

Re-implements https://github.com/1fwang/euroc_dataset_tools rosbag2euroc.py,
the converter the OpenMAVIS README points to, on top of the pure-Python
`rosbags` reader so it runs on an OS that ROS 1 no longer supports.

Layout is the same as the original:
  * image topics sorted by name -> mav0/cam0, cam1, ...  (/alphasense/camN -> camN)
  * PNG file name = header stamp in integer nanoseconds
  * imu topics -> mav0/imu0/data.csv  (ts, w_x, w_y, w_z, a_x, a_y, a_z)
Differences: the original glues the first IMU sample onto the CSV header line
(no newline after the header), losing that sample; this one does not.

Also writes <seq>/timestamps.txt = first column of cam0/data.csv, as the
OpenMAVIS README asks, and reports frames missing from the other cameras.

  rosbag2euroc.py BAG -o OUT_DIR [--cams 0,1,3,4] [--workers 8]
"""
import argparse
import os
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import cv2
import numpy as np
from rosbags.highlevel import AnyReader

IMAGE_TYPES = {"sensor_msgs/msg/Image"}
IMU_TYPES = {"sensor_msgs/msg/Imu"}


def stamp_ns(header):
    return int(header.stamp.sec) * 1_000_000_000 + int(header.stamp.nanosec)


def to_cv(msg):
    enc = msg.encoding.lower()
    buf = np.asarray(msg.data, dtype=np.uint8)
    if enc in ("mono8", "8uc1"):
        return buf.reshape(msg.height, msg.step)[:, : msg.width]
    if enc in ("mono16", "16uc1"):
        img = buf.reshape(msg.height, msg.step).view(np.uint16)[:, : msg.width]
        return img.byteswap() if msg.is_bigendian else img
    if enc in ("bgr8", "rgb8", "8uc3"):
        img = buf.reshape(msg.height, msg.step)[:, : msg.width * 3].reshape(msg.height, msg.width, 3)
        return cv2.cvtColor(img, cv2.COLOR_RGB2BGR) if enc == "rgb8" else img
    raise ValueError(f"unsupported image encoding: {msg.encoding}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("rosbag_path")
    ap.add_argument("-o", "--output_path", default="./")
    ap.add_argument("--cams", default=None,
                    help="comma-separated camN indices to export (default: all image topics)")
    ap.add_argument("--workers", type=int, default=os.cpu_count() or 4)
    args = ap.parse_args()

    bag = Path(args.rosbag_path)
    seq = bag.name.split(".", 1)[0]
    base = Path(args.output_path) / seq / "mav0"

    with AnyReader([bag]) as reader:
        img_conns = sorted({c.topic: c for c in reader.connections if c.msgtype in IMAGE_TYPES}.values(),
                           key=lambda c: c.topic)
        imu_conns = sorted({c.topic: c for c in reader.connections if c.msgtype in IMU_TYPES}.values(),
                           key=lambda c: c.topic)
        print(f"bag: {bag}  duration {reader.duration / 1e9:.1f} s")
        for i, c in enumerate(img_conns):
            print(f"  cam{i} <- {c.topic} ({c.msgcount} msgs)")
        for i, c in enumerate(imu_conns):
            print(f"  imu{i} <- {c.topic} ({c.msgcount} msgs)")
        if len(imu_conns) != 1:
            print(f"WARNING: expected one IMU topic, got {len(imu_conns)}")

        wanted = set(range(len(img_conns))) if args.cams is None else {int(x) for x in args.cams.split(",")}
        cam_dir = {}
        csv = {}
        for i, c in enumerate(img_conns):
            if i not in wanted:
                continue
            d = base / f"cam{i}"
            (d / "data").mkdir(parents=True, exist_ok=True)
            cam_dir[c.topic] = d
            csv[c.topic] = open(d / "data.csv", "w")
            csv[c.topic].write("#timestamp [ns],filename\n")
        imu_csv = {}
        for i, c in enumerate(imu_conns):
            d = base / f"imu{i}"
            d.mkdir(parents=True, exist_ok=True)
            imu_csv[c.topic] = open(d / "data.csv", "w")
            imu_csv[c.topic].write("#timestamp [ns],w_RS_S_x [rad s^-1],w_RS_S_y [rad s^-1],w_RS_S_z [rad s^-1],"
                                   "a_RS_S_x [m s^-2],a_RS_S_y [m s^-2],a_RS_S_z [m s^-2]\n")

        stamps = {t: [] for t in cam_dir}
        conns = [c for c in img_conns if c.topic in cam_dir] + imu_conns
        pending = []
        n = 0
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            for conn, _, raw in reader.messages(connections=conns):
                msg = reader.deserialize(raw, conn.msgtype)
                ts = stamp_ns(msg.header)
                if conn.topic in imu_csv:
                    w, a = msg.angular_velocity, msg.linear_acceleration
                    imu_csv[conn.topic].write(f"{ts},{w.x!r},{w.y!r},{w.z!r},{a.x!r},{a.y!r},{a.z!r}\n")
                    continue
                name = f"{ts}.png"
                csv[conn.topic].write(f"{ts},{name}\n")
                stamps[conn.topic].append(ts)
                pending.append(pool.submit(cv2.imwrite, str(cam_dir[conn.topic] / "data" / name), to_cv(msg)))
                n += 1
                if len(pending) > 4 * args.workers:
                    for f in pending:
                        if not f.result():
                            sys.exit("cv2.imwrite failed")
                    pending.clear()
                if n % 5000 == 0:
                    print(f"  {n} images", flush=True)
            for f in pending:
                if not f.result():
                    sys.exit("cv2.imwrite failed")

    for f in list(csv.values()) + list(imu_csv.values()):
        f.close()

    topics = list(cam_dir)
    ref = stamps[topics[0]]
    ref_set = set(ref)
    common = ref_set.intersection(*(set(stamps[t]) for t in topics[1:]))
    for t in topics[1:]:
        s = set(stamps[t])
        print(f"  {cam_dir[t].name}: {len(s)} frames, missing vs {cam_dir[topics[0]].name}: "
              f"{len(ref_set - s)}, extra: {len(s - ref_set)}")
    # The README builds timestamps.txt from cam0 alone, but multi_inertial_euroc
    # returns 1 without saving a trajectory on the first image it cannot load,
    # so a frame missing from any exported camera is left out.
    kept = [t for t in ref if t in common]
    (base.parent / "timestamps.txt").write_text("".join(f"{t}\n" for t in kept))
    print(f"wrote {n} images; timestamps.txt: {len(kept)} of {len(ref)} {cam_dir[topics[0]].name} frames "
          f"(dropped {len(ref) - len(kept)} not present in every exported camera)")


if __name__ == "__main__":
    main()
