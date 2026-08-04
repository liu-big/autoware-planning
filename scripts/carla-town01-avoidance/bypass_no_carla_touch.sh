#!/usr/bin/env bash
# Bypass only: switch to fixed right ped. NO CARLA API calls (prevents ego loss).
set +e
set +u; source /opt/ros/humble/setup.bash; source /opt/autoware/setup.bash; set -u
export PYTHONPATH="/opt/py310_site:${PYTHONPATH:-}"

echo "[bypass] Autoware soft stop (no CARLA touch)"
ros2 service call /api/autoware/set/engage tier4_external_api_msgs/srv/Engage "{engage: false}" >/dev/null 2>&1
ros2 service call /system/operation_mode/change_operation_mode \
  autoware_system_msgs/srv/ChangeOperationMode "{mode: 1}" >/dev/null 2>&1
ros2 service call /system/mrm/emergency_stop/operate tier4_system_msgs/srv/OperateMrm "{operate: false}" >/dev/null 2>&1
ros2 service call /control/vehicle_cmd_gate/clear_external_emergency_stop std_srvs/srv/Trigger "{}" >/dev/null 2>&1
sleep 1

pkill -f automatic_pose_initializer || true
pkill -f dummy_perception_publisher || true
pkill -f detected_to_predicted_objects || true
pkill -f empty_objects_pc || true
pkill -f '/home/aw/aw_docker/inject_' || true
sleep 1

bash /home/aw/aw_docker/apply_fast_avoidance.sh
BPP=/planning/scenario_planning/lane_driving/behavior_planning/behavior_path_planner
MVP=/planning/scenario_planning/lane_driving/motion_planning/motion_velocity_planner
timeout 5 ros2 param set "$BPP" avoidance.target_filtering.parked_vehicle.th_offset_from_centerline 0.5 >/dev/null 2>&1
timeout 5 ros2 param set "$BPP" avoidance.target_object.pedestrian.lateral_margin.soft_margin 0.4 >/dev/null 2>&1
timeout 5 ros2 param set "$BPP" avoidance.target_object.pedestrian.lateral_margin.hard_margin 0.25 >/dev/null 2>&1
timeout 5 ros2 param set "$MVP" obstacle_stop.stop_planning.stop_margin 3.5 >/dev/null 2>&1

if ! pgrep -f dummy_traffic_signals.py >/dev/null; then
  nohup python3 /home/aw/aw_docker/dummy_traffic_signals.py >/home/aw/autoware_logs/dummy_tl.log 2>&1 &
fi
if ! pgrep -f ogm_free_publisher.py >/dev/null; then
  nohup python3 /home/aw/aw_docker/ogm_free_publisher.py >/home/aw/autoware_logs/ogm_free.log 2>&1 &
fi

nohup python3 /home/aw/aw_docker/inject_one_right.py \
  >/home/aw/autoware_logs/inject_one_right.log 2>&1 &
sleep 2
echo "[bypass] ped:"
timeout 3 ros2 topic echo /perception/object_recognition/objects --once 2>/dev/null \
  | awk '/label:/{l=$2} /position:/{getline;x=$2;getline;y=$2; print l,"at",x,y; exit}'
echo "[bypass] ego:"
timeout 2 ros2 topic echo /localization/kinematic_state --once 2>/dev/null \
  | awk '/position:/{getline;x=$2;getline;y=$2; printf "%.1f,%.2f\n",x,y; exit}'

ros2 service call /api/routing/clear_route autoware_adapi_v1_msgs/srv/ClearRoute "{}" >/dev/null 2>&1
sleep 1
ros2 service call /api/routing/set_route_points autoware_adapi_v1_msgs/srv/SetRoutePoints "{
  header: {frame_id: map},
  option: {allow_goal_modification: true},
  goal: {position: {x: 90.0, y: -1.96, z: 0.0}, orientation: {w: 1.0}},
  waypoints: []
}" 2>&1 | tail -3

for i in $(seq 1 20); do
  if timeout 2 ros2 topic echo /planning/trajectory --once 2>/dev/null | grep -q longitudinal_velocity_mps; then
    echo "[bypass] traj OK @$i"; break
  fi
  sleep 1
done

echo "[bypass] factors:"
timeout 3 ros2 topic echo /planning/planning_factors/static_obstacle_avoidance --once 2>/dev/null \
  | grep -E "shift_length:|detail:|distance:" | head -20

# velocity limit in background for whole sample window
timeout 40 ros2 topic pub -r 10 /planning/scenario_planning/max_velocity tier4_planning_msgs/msg/VelocityLimit \
  "{max_velocity: 5.56, use_constraints: false, sender: bypass}" >/dev/null 2>&1 &

bash /home/aw/aw_docker/force_engage.sh

echo "[bypass] sample 30s"
for i in $(seq 1 30); do
  mode=$(timeout 2 ros2 topic echo /system/operation_mode/state --once 2>/dev/null | awk '/^mode:/{print $2; exit}')
  pose=$(timeout 2 ros2 topic echo /localization/kinematic_state --once 2>/dev/null | awk '/position:/{getline;x=$2;getline;y=$2; printf "%.1f,%.2f",x,y; exit}')
  ctrl=$(timeout 2 ros2 topic echo /control/command/control_cmd --once 2>/dev/null | awk '/steering_tire_angle:/{s=$2} /  velocity:/{v=$2} END{printf "%.2f,%.2f",s+0,v+0}')
  shift=$(timeout 2 ros2 topic echo /planning/planning_factors/static_obstacle_avoidance --once 2>/dev/null | awk '/shift_length:/{s=$2} END{print s}')
  echo "[bypass] t=${i}s mode=$mode pose=$pose steer,v=$ctrl shift=$shift"
  sleep 1
done
echo BYPASS_DONE
