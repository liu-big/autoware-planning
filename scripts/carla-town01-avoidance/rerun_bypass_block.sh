#!/usr/bin/env bash
# Place RIGHT ped ahead of current ego and force left bypass.
# No CARLA client. Goal far + allow_goal_modification=false.
set +e
set +u; source /opt/ros/humble/setup.bash; source /opt/autoware/setup.bash; set -u
export PYTHONPATH="/opt/py310_site:${PYTHONPATH:-}"

BPP=/planning/scenario_planning/lane_driving/behavior_planning/behavior_path_planner
MVP=/planning/scenario_planning/lane_driving/motion_planning/motion_velocity_planner

ego_x=$(timeout 2 ros2 topic echo /localization/kinematic_state --once 2>/dev/null | awk '/position:/{getline; print $2; exit}')
ego_y=$(timeout 2 ros2 topic echo /localization/kinematic_state --once 2>/dev/null | awk '/position:/{getline;getline; print $2; exit}')
echo "[ahead] ego=${ego_x},${ego_y}"

# ped ~14m ahead, ~1.6m to the RIGHT of lane center (~-2)
PED_X=$(python3 -c "print(f'{float(\"${ego_x:-47}\")+12.0:.2f}')")
PED_Y=-2.70
GOAL_X=$(python3 -c "print(f'{float(\"${ego_x:-47}\")+80.0:.2f}')")
echo "[ahead] ped=${PED_X},${PED_Y} goal=${GOAL_X}"

ros2 service call /api/autoware/set/engage tier4_external_api_msgs/srv/Engage "{engage: false}" >/dev/null 2>&1
ros2 service call /system/operation_mode/change_operation_mode \
  autoware_system_msgs/srv/ChangeOperationMode "{mode: 1}" >/dev/null 2>&1
sleep 0.5

pkill -f '/home/aw/aw_docker/inject_' || true
pkill -f dummy_perception_publisher || true
pkill -f detected_to_predicted_objects || true
pkill -f empty_objects_pc || true
sleep 1

bash /home/aw/aw_docker/apply_fast_avoidance.sh >/dev/null 2>&1
timeout 5 ros2 param set "$BPP" avoidance.target_filtering.object_check_goal_distance 5.0 >/dev/null 2>&1
timeout 5 ros2 param set "$BPP" avoidance.target_filtering.object_check_return_pose_distance 5.0 >/dev/null 2>&1
timeout 5 ros2 param set "$BPP" avoidance.target_filtering.parked_vehicle.th_offset_from_centerline 0.35 >/dev/null 2>&1
timeout 5 ros2 param set "$MVP" obstacle_stop.obstacle_filtering.check_outside.default false >/dev/null 2>&1
timeout 5 ros2 param set "$MVP" obstacle_stop.stop_planning.stop_margin 5.0 >/dev/null 2>&1

if ! pgrep -f ogm_free_publisher.py >/dev/null; then
  nohup python3 /home/aw/aw_docker/ogm_free_publisher.py >/home/aw/autoware_logs/ogm_free.log 2>&1 &
fi
if ! pgrep -f dummy_traffic_signals.py >/dev/null; then
  nohup python3 /home/aw/aw_docker/dummy_traffic_signals.py >/home/aw/autoware_logs/dummy_tl.log 2>&1 &
fi

nohup env PED_X="$PED_X" PED_Y="$PED_Y" python3 /home/aw/aw_docker/inject_one_right.py \
  >/home/aw/autoware_logs/inject_one_right.log 2>&1 &
sleep 2
echo "[ahead] objects:"
timeout 3 ros2 topic echo /perception/object_recognition/objects --once 2>/dev/null \
  | awk '/label:/{l=$2} /position:/{getline;x=$2;getline;y=$2; print l,x,y; exit}'

ros2 service call /api/routing/clear_route autoware_adapi_v1_msgs/srv/ClearRoute "{}" >/dev/null 2>&1
sleep 1
# CRITICAL: allow_goal_modification false — otherwise goal snaps near ego and ped becomes too_near_to_goal
ros2 service call /api/routing/set_route_points autoware_adapi_v1_msgs/srv/SetRoutePoints "{
  header: {frame_id: map},
  option: {allow_goal_modification: false},
  goal: {position: {x: ${GOAL_X}, y: -1.96, z: 0.0}, orientation: {w: 1.0}},
  waypoints: []
}" 2>&1 | tail -3

sleep 2
echo "[ahead] route goal:"
timeout 2 ros2 topic echo /planning/mission_planning/route --once 2>/dev/null \
  | awk '/goal_pose:/{getline;getline;print "gx",$2;getline;print "gy",$2; exit}'

echo "[ahead] debug ns:"
timeout 3 ros2 topic echo /planning/scenario_planning/lane_driving/behavior_planning/behavior_path_planner/debug/static_obstacle_avoidance --once 2>/dev/null \
  | grep "ns:" | sort | uniq -c | sort -rn | head -15

echo "[ahead] factors:"
timeout 3 ros2 topic echo /planning/planning_factors/static_obstacle_avoidance --once 2>/dev/null \
  | grep -E "shift_length:|detail:|distance:" | head -20

timeout 50 ros2 topic pub -r 10 /planning/scenario_planning/max_velocity tier4_planning_msgs/msg/VelocityLimit \
  "{max_velocity: 2.0, use_constraints: false, sender: ahead}" >/dev/null 2>&1 &

bash /home/aw/aw_docker/force_engage.sh

echo "[ahead] sample 30s — expect LEFT shift; ped closer to centerline y=-2.70"
for i in $(seq 1 30); do
  pose=$(timeout 2 ros2 topic echo /localization/kinematic_state --once 2>/dev/null | awk '/position:/{getline;x=$2;getline;y=$2; printf "%.1f,%.2f",x,y; exit}')
  ctrl=$(timeout 2 ros2 topic echo /control/command/control_cmd --once 2>/dev/null | awk '/steering_tire_angle:/{s=$2} /  velocity:/{v=$2} END{printf "%.2f,%.2f",s+0,v+0}')
  shift=$(timeout 2 ros2 topic echo /planning/planning_factors/static_obstacle_avoidance --once 2>/dev/null | awk '/shift_length:/{print $2; exit}')
  mot=$(timeout 2 ros2 topic echo /api/motion/state --once 2>/dev/null | awk '/^state:/{print $2; exit}')
  echo "[ahead] t=${i}s mot=$mot pose=$pose steer,v=$ctrl shift=$shift"
  sleep 1
done
echo AHEAD_BYPASS_DONE
