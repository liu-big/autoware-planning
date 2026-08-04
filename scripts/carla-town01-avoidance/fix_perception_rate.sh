#!/usr/bin/env bash
# Keep perception topics at ~10Hz so Autoware CSM does not raise Emergency.
set +e
set +u
source /opt/ros/humble/setup.bash
source /opt/autoware/setup.bash
set -u
export PYTHONPATH="/opt/py310_site:${PYTHONPATH:-}"
mkdir -p /home/aw/autoware_logs

pkill -f '/home/aw/aw_docker/empty_objects_pc.py' || true
sleep 0.3
nohup python3 /home/aw/aw_docker/empty_objects_pc.py \
  >/home/aw/autoware_logs/empty_objects_pc.log 2>&1 &
echo "empty_pid=$!"
sleep 1
pgrep -af empty_objects_pc.py | grep -v pgrep || echo "WARN: empty_objects_pc not running"
ls -l /home/aw/autoware_logs/empty_objects_pc.log || true
