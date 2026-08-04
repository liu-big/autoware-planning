#!/usr/bin/env bash
# Force clear blockers and enter Autonomous (system mode=2).
set +e
set +u; source /opt/ros/humble/setup.bash; source /opt/autoware/setup.bash; set -u
export PYTHONPATH="/opt/py310_site:${PYTHONPATH:-}"
exec > >(stdbuf -oL tee /home/aw/autoware_logs/force_engage.log) 2>&1

echo "[engage] helpers"
pkill -f automatic_pose_initializer || true
if ! pgrep -f dummy_traffic_signals.py >/dev/null; then
  nohup python3 /home/aw/aw_docker/dummy_traffic_signals.py >/home/aw/autoware_logs/dummy_tl.log 2>&1 &
fi
if ! pgrep -f ogm_free_publisher.py >/dev/null; then
  nohup python3 /home/aw/aw_docker/ogm_free_publisher.py >/home/aw/autoware_logs/ogm_free.log 2>&1 &
fi
# CSM watches objects/pointcloud rate; sparse dummy → Emergency → Auto grayed
# Do NOT start empty keepalive while inject_* owns the topics (would wipe obstacles)
if ! pgrep -f 'inject_complex_dynamic|inject_static_obstacles|inject_dummy_pedestrian|inject_one_right' >/dev/null 2>&1; then
  bash /home/aw/aw_docker/fix_perception_rate.sh >/dev/null 2>&1 || true
else
  echo "[engage] skip empty keepalive (injector active)"
fi
# Keep RViz dummy pipeline if present; do not start injectors

echo "[engage] clear emergency / MRM"
ros2 service call /system/mrm/emergency_stop/operate tier4_system_msgs/srv/OperateMrm "{operate: false}" >/dev/null 2>&1
ros2 service call /control/vehicle_cmd_gate/clear_external_emergency_stop std_srvs/srv/Trigger "{}" >/dev/null 2>&1

echo "[engage] publish velocity limit 20km/h for 3s"
# external velocity limit selector listens on max_velocity
timeout 3 ros2 topic pub -r 10 /planning/scenario_planning/max_velocity tier4_planning_msgs/msg/VelocityLimit \
  "{max_velocity: 5.56, use_constraints: false, sender: force_engage}" >/dev/null 2>&1 &
VPID=$!

echo "[engage] engage + system Autonomous"
ros2 service call /api/autoware/set/engage tier4_external_api_msgs/srv/Engage "{engage: true}" >/dev/null 2>&1
sleep 0.5
# Prefer system API (ADAPI often reports unavailable while already in mode 2)
for i in 1 2 3 4 5 6; do
  out=$(timeout 8 ros2 service call /system/operation_mode/change_operation_mode \
    autoware_system_msgs/srv/ChangeOperationMode "{mode: 2}" 2>&1 || true)
  echo "[engage] sys_auto$i: $(echo "$out" | tr '\n' ' ' | grep -oE 'success=[A-Za-z]+|message=[^,]+|code=[0-9]+' | head -c 100)"
  echo "$out" | grep -qE 'success=True|same as the current' && break
  sleep 1
done

# Also try ADAPI for RViz panel sync
out=$(timeout 8 ros2 service call /api/operation_mode/change_to_autonomous \
  autoware_adapi_v1_msgs/srv/ChangeOperationMode "{}" 2>&1 || true)
echo "[engage] adapi_auto: $(echo "$out" | tr '\n' ' ' | grep -oE 'success=[A-Za-z]+|message=[^,]+' | head -c 120)"

sleep 1
kill $VPID 2>/dev/null || true

echo "[engage] status"
mode=$(timeout 2 ros2 topic echo /system/operation_mode/state --once 2>/dev/null | awk '/^mode:/{print $2; exit}')
eng=$(timeout 2 ros2 topic echo /api/autoware/get/engage --once 2>/dev/null | awk '/^engage:/{print $2; exit}')
emg=$(timeout 2 ros2 topic echo /api/autoware/get/emergency --once 2>/dev/null | awk '/^emergency:/{print $2; exit}')
aw=$(timeout 2 ros2 topic echo /autoware/state --once 2>/dev/null | awk '/^state:/{print $2; exit}')
mot=$(timeout 2 ros2 topic echo /api/motion/state --once 2>/dev/null | awk '/^state:/{print $2; exit}')
pose=$(timeout 2 ros2 topic echo /localization/kinematic_state --once 2>/dev/null | awk '/position:/{getline; x=$2; getline; y=$2; printf "%.1f,%.2f",x,y; exit}')
ctrl=$(timeout 2 ros2 topic echo /control/command/control_cmd --once 2>/dev/null | awk '/steering_tire_angle:/{s=$2} /  velocity:/{v=$2} END{print s","v}')
vmax=$(timeout 2 ros2 topic echo /planning/trajectory --once 2>/dev/null | awk '/longitudinal_velocity_mps:/{print $2; exit}')
echo "[engage] mode=$mode engage=$eng emergency=$emg autoware_state=$aw motion=$mot"
echo "[engage] pose=$pose steer,v=$ctrl traj_v0=$vmax"
echo "[engage] RViz: if Auto grayed, ignore — system mode=2 is already Autonomous."
echo "[engage] If car not moving: drag Velocity Limit to ~20; clear Dummy obstacles on path; check Motion not Stopped by obstacle_stop."
echo "[engage] DONE"
