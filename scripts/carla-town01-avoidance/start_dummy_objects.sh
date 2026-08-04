#!/usr/bin/env bash
# Start official dummy_perception_publisher + Detected→Predicted converter + free OGM.
# OBJECT_SOURCE=dummy (default) | carla_walkers | none
set -euo pipefail
set +u; source /opt/ros/humble/setup.bash; source /opt/autoware/setup.bash; set -u
export PYTHONPATH="/opt/py310_site:${PYTHONPATH:-}"

OBJECT_SOURCE="${OBJECT_SOURCE:-dummy}"

pkill -f '/home/aw/aw_docker/dummy_perception.py' || true
pkill -f 'dummy_perception_publisher' || true
pkill -f 'detected_to_predicted_objects' || true
pkill -f 'carla_walker_to_objects.py' || true
pkill -f 'ogm_free_publisher.py' || true
pkill -f 'empty_objects_pc.py' || true
# Kill ALL injectors — they steal /perception/object_recognition/objects and
# make RViz 2D Dummy Pedestrian/Car/Bus appear to "do nothing".
pkill -f 'inject_dummy_pedestrian.py' || true
pkill -f 'inject_complex_dynamic.py' || true
pkill -f 'inject_static_obstacles.py' || true
pkill -f 'inject_one_right.py' || true
pkill -f 'inject_test' || true
pkill -f '/home/aw/aw_docker/inject_' || true
sleep 0.5

# Required for Autonomous when perception:=false (CSM watches this topic)
if ! pgrep -f 'dummy_traffic_signals.py' >/dev/null 2>&1; then
  nohup python3 /home/aw/aw_docker/dummy_traffic_signals.py \
    >/home/aw/autoware_logs/dummy_tl.log 2>&1 &
fi

nohup python3 /home/aw/aw_docker/ogm_free_publisher.py \
  >/home/aw/autoware_logs/ogm_free.log 2>&1 &

case "$OBJECT_SOURCE" in
  dummy)
    echo "[objects] dummy_perception_publisher + detected_to_predicted converter"
    nohup ros2 launch autoware_dummy_perception_publisher dummy_perception_publisher.launch.xml \
      >/home/aw/autoware_logs/dummy_objects.log 2>&1 &
    sleep 1
    nohup ros2 launch autoware_perception_objects_converter detected_to_predicted_objects.launch.xml \
      input_topic:=/perception/object_recognition/detection/objects \
      output_topic:=/perception/object_recognition/objects \
      >/home/aw/autoware_logs/detected_to_predicted.log 2>&1 &
    # Keep ~10Hz even with zero dummies (prevents CSM Emergency / Auto unavailable)
    bash /home/aw/aw_docker/fix_perception_rate.sh >/dev/null 2>&1 || true
    ;;
  inject)
    # Lateral offset required: on-centerline pedestrians are filtered as
    # others_too_near_to_centerline → stop only, no bypass.
    export PED_AHEAD_M="${PED_AHEAD_M:-14.0}"
    export PED_LATERAL_M="${PED_LATERAL_M:-1.4}"
    echo "[objects] inject_dummy_pedestrian ahead=${PED_AHEAD_M}m lateral=${PED_LATERAL_M}m"
    nohup env PED_AHEAD_M="$PED_AHEAD_M" PED_LATERAL_M="$PED_LATERAL_M" \
      python3 /home/aw/aw_docker/inject_dummy_pedestrian.py \
      >/home/aw/autoware_logs/inject_ped.log 2>&1 &
    ;;
  static)
    echo "[objects] inject_static_obstacles (3 frozen map obstacles)"
    nohup python3 /home/aw/aw_docker/inject_static_obstacles.py \
      >/home/aw/autoware_logs/static_obstacles.log 2>&1 &
    ;;
  carla_walkers)
    echo "[objects] CARLA walker bridge -> PredictedObjects"
    nohup python3 /home/aw/aw_docker/carla_walker_to_objects.py \
      >/home/aw/autoware_logs/carla_walkers.log 2>&1 &
    ;;
  none)
    echo "[objects] none (OGM only)"
    ;;
  *)
    echo "Unknown OBJECT_SOURCE=$OBJECT_SOURCE (dummy|inject|static|carla_walkers|none)"; exit 1
    ;;
esac

echo "[objects] OK source=$OBJECT_SOURCE"
echo "  RViz: toolbar -> 2D Dummy Pedestrian (when source=dummy)"
echo "  check: ros2 topic echo /perception/object_recognition/objects --once"
