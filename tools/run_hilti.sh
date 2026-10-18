#!/usr/bin/env bash
# In-container: one OpenMAVIS run on a Hilti 2022 sequence that
# tools/rosbag2euroc.py converted, then ATE against the 6DoF ground truth.
#   tools/run_hilti.sh <seq> <multi|stereo> [run_tag]
#
#   multi  : Examples/Multi-Inertial/multi_inertial_euroc  (4 cameras + IMU)
#   stereo : Examples/Stereo-Inertial/stereo_inertial_euroc (front pair + IMU)
# Both use the upstream HiltiChallenge2022.yaml unchanged: in IMU_STEREO mode
# Settings reads only Camera1/2, Stereo.T_c1_c2 and IMU.T_b_c1 from it.
set -euo pipefail
SEQ="${1:?sequence name, e.g. exp14_basement_2}"
MODE="${2:?multi or stereo}"
TAG="${3:-$(date +%Y%m%d_%H%M%S)}"
SRC=/opt/OpenMAVIS
YAML=$SRC/Examples/Multi-Inertial/HiltiChallenge2022.yaml
DATA=/datasets/Hilti2022/euroc/${SEQ}
OUT=/workspace/results/hilti/${SEQ}/${MODE}/${TAG}
mkdir -p "$OUT"; cd "$OUT"
cp /opt/OpenMAVIS.commit upstream.commit

case "$MODE" in
  multi)
    BIN=$SRC/Examples/Multi-Inertial/multi_inertial_euroc
    SEQDIR=$DATA ;;
  stereo)
    BIN=$SRC/Examples/Stereo-Inertial/stereo_inertial_euroc
    # stereo_inertial_euroc reads mav0/cam0 as left, mav0/cam1 as right;
    # the Hilti config's Camera1 (left) is Alphasense cam1, Camera2 is cam0
    # (multi_inertial_euroc maps them the same way). Swap via symlinks.
    SEQDIR=/tmp/stereo_view/${SEQ}
    mkdir -p "$SEQDIR/mav0"
    ln -sfn "$DATA/mav0/cam1" "$SEQDIR/mav0/cam0"
    ln -sfn "$DATA/mav0/cam0" "$SEQDIR/mav0/cam1"
    ln -sfn "$DATA/mav0/imu0" "$SEQDIR/mav0/imu0" ;;
  *) echo "mode must be multi or stereo" >&2; exit 2 ;;
esac

start=$(date +%s.%N)
set +e
"$BIN" "$SRC/Vocabulary/ORBvoc.txt" "$YAML" "$SEQDIR" "$DATA/timestamps.txt" > run.log 2>&1
rc=$?
set -e
end=$(date +%s.%N)
echo "exit=$rc wall_s=$(python3 -c "print(f'{$end-$start:.1f}')")" | tee status.txt

GT=/datasets/Hilti2022/ground_truth/${SEQ}_imu.txt
if [ -s CameraTrajectory.txt ] && [ -f "$GT" ]; then
  /workspace/tools/eval_ate.sh "$GT" CameraTrajectory.txt tum > ate.txt 2>&1 || true
  grep -E 'rmse' ate.txt || true
fi
exit 0
