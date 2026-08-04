#!/usr/bin/env bash
# One-shot: inject pedestrian ahead + pose/route + Engage autonomous
# Usage (host): docker exec -e OBJECT_SOURCE=inject aw_carla_sim bash /home/aw/aw_docker/go_auto.sh
set -euo pipefail
set +u; source /opt/ros/humble/setup.bash; source /opt/autoware/setup.bash; set -u
export PYTHONPATH="/opt/py310_site:${PYTHONPATH:-}"
export OBJECT_SOURCE="${OBJECT_SOURCE:-inject}"
export AW_X="${AW_X:-25.0}"
export AW_Y="${AW_Y:--1.98}"
export GOAL_X="${GOAL_X:-70.0}"
export GOAL_Y="${GOAL_Y:--1.96}"

pkill -f automatic_pose_initializer || true
bash /home/aw/aw_docker/start_dummy_objects.sh

# CARLA teleport + /initialpose (same as drive_light core)
python3 - <<'PY'
import math, time
import carla
import rclpy
from geometry_msgs.msg import PoseWithCovarianceStamped
from rclpy.node import Node
import os
aw_x, aw_y, aw_yaw = float(os.environ["AW_X"]), float(os.environ["AW_Y"]), 0.0
ue_x, ue_y, ue_yaw = aw_x, -aw_y, -math.degrees(aw_yaw)
client = carla.Client("127.0.0.1", 2000); client.set_timeout(10.0)
world = client.get_world()
ego = None
for _ in range(40):
    cands = [a for a in world.get_actors() if a.type_id.startswith("vehicle.")]
    for a in cands:
        if a.attributes.get("role_name") in ("ego_vehicle", "hero", "ego"):
            ego = a; break
    if ego is None and cands: ego = cands[0]
    if ego: break
    try: world.tick()
    except Exception: time.sleep(0.1)
if ego is None: raise SystemExit("no ego")
ego.set_transform(carla.Transform(carla.Location(x=ue_x,y=ue_y,z=0.5), carla.Rotation(yaw=ue_yaw)))
ego.set_target_velocity(carla.Vector3D(0,0,0)); ego.set_target_angular_velocity(carla.Vector3D(0,0,0))
c=ego.get_control(); c.throttle=0; c.brake=1; c.hand_brake=True; ego.apply_control(c)
print(f"[go] teleported id={ego.id} AW=({aw_x},{aw_y})")
time.sleep(0.5)
class P(Node):
    def __init__(self):
        super().__init__("go_pose", parameter_overrides=[
            rclpy.parameter.Parameter("use_sim_time", rclpy.parameter.Parameter.Type.BOOL, True)])
        self.pub=self.create_publisher(PoseWithCovarianceStamped,"/initialpose",10)
        self.n=0; self.create_timer(0.35, self.tick)
    def tick(self):
        m=PoseWithCovarianceStamped(); m.header.stamp=self.get_clock().now().to_msg(); m.header.frame_id="map"
        m.pose.pose.position.x=aw_x; m.pose.pose.position.y=aw_y
        m.pose.pose.orientation.z=math.sin(aw_yaw/2); m.pose.pose.orientation.w=math.cos(aw_yaw/2)
        cov=[0.0]*36; cov[0]=cov[7]=0.25; cov[35]=0.07; m.pose.covariance=cov
        self.pub.publish(m); self.n+=1
        if self.n>=10: raise SystemExit
rclpy.init(args=["--ros-args","-p","use_sim_time:=true"]); n=P()
try: rclpy.spin(n)
except SystemExit: pass
n.destroy_node(); rclpy.shutdown(); print("[go] pose OK")
PY

sleep 2
ros2 service call /control/vehicle_cmd_gate/clear_external_emergency_stop std_srvs/srv/Trigger "{}" >/dev/null || true
ros2 service call /api/routing/clear_route autoware_adapi_v1_msgs/srv/ClearRoute "{}" >/dev/null || true
sleep 1
ros2 service call /api/routing/set_route_points autoware_adapi_v1_msgs/srv/SetRoutePoints "{
  header: {frame_id: map},
  option: {allow_goal_modification: true},
  goal: {position: {x: ${GOAL_X}, y: ${GOAL_Y}, z: 0.0}, orientation: {x: 0.0, y: 0.0, z: 0.0, w: 1.0}},
  waypoints: []
}"

echo "[go] wait trajectory..."
traj_ok=0
for i in $(seq 1 40); do
  if timeout 2 ros2 topic hz /planning/trajectory 2>&1 | grep -q average; then
    echo "[go] trajectory OK"; traj_ok=1; break
  fi
  sleep 1
done
if [[ "$traj_ok" -ne 1 ]]; then
  echo "[go] WARN still no /planning/trajectory — check Localization=Initialized in RViz"
fi

ros2 service call /api/autoware/set/engage tier4_external_api_msgs/srv/Engage "{engage: true}" || true
ros2 service call /api/operation_mode/change_to_stop autoware_adapi_v1_msgs/srv/ChangeOperationMode "{}" || true
sleep 1
for i in 1 2 3 4 5; do
  out=$(ros2 service call /api/operation_mode/change_to_autonomous autoware_adapi_v1_msgs/srv/ChangeOperationMode "{}" 2>&1 || true)
  echo "$out" | tail -3
  echo "$out" | grep -q 'success=True' && break
  sleep 2
done

timeout 3 ros2 topic echo /system/operation_mode/state --once 2>&1 | head -12
timeout 3 ros2 topic echo /perception/object_recognition/objects --once 2>&1 | head -20
echo "[go] done. RViz: Fixed Frame=map. Pedestrian is injected 12m ahead (no RViz tool needed)."
echo "  Do NOT press Emergency."
