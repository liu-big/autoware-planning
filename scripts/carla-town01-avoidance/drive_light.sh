#!/usr/bin/env bash
# Lane-align (CARLA teleport + /initialpose), route, engage for Town01 light e2e.
set -euo pipefail
set +u; source /opt/ros/humble/setup.bash; source /opt/autoware/setup.bash; set -u
export PYTHONPATH="/opt/py310_site:${PYTHONPATH:-}"

AW_X="${AW_X:-25.0}"
AW_Y="${AW_Y:--1.98}"
AW_YAW="${AW_YAW:-0.0}"
GOAL_X="${GOAL_X:-70.0}"
GOAL_Y="${GOAL_Y:--1.96}"
OBJECT_SOURCE="${OBJECT_SOURCE:-dummy}"

pkill -f automatic_pose_initializer || true

# Objects + free OGM (replaces empty dummy_perception.py)
bash /home/aw/aw_docker/start_dummy_objects.sh

python3 - <<PY
import math, time
import carla
import rclpy
from geometry_msgs.msg import PoseWithCovarianceStamped
from rclpy.node import Node

aw_x, aw_y, aw_yaw = float("$AW_X"), float("$AW_Y"), float("$AW_YAW")
ue_x, ue_y = aw_x, -aw_y
ue_yaw = -math.degrees(aw_yaw)

client = carla.Client("127.0.0.1", 2000)
client.set_timeout(10.0)
world = client.get_world()
ego = None
for _ in range(40):
    actors = list(world.get_actors())
    cands = [a for a in actors if a.type_id.startswith("vehicle.")]
    for a in cands:
        if a.attributes.get("role_name") in ("ego_vehicle", "hero", "ego"):
            ego = a
            break
    if ego is None and cands:
        ego = cands[0]
    if ego:
        break
    # Do NOT world.tick() — bridge owns sync ticks; ticking hangs/breaks CARLA.
    time.sleep(0.1)
if ego is None:
    raise SystemExit("[drive] no ego in CARLA")

tf = carla.Transform(
    carla.Location(x=ue_x, y=ue_y, z=0.5),
    carla.Rotation(pitch=0.0, yaw=ue_yaw, roll=0.0),
)
ego.set_transform(tf)
ego.set_target_velocity(carla.Vector3D(0, 0, 0))
ego.set_target_angular_velocity(carla.Vector3D(0, 0, 0))
ctrl = ego.get_control()
ctrl.throttle = 0.0
ctrl.brake = 1.0
ctrl.hand_brake = True
ego.apply_control(ctrl)
print(f"[drive] teleported ego id={ego.id} AW=({aw_x},{aw_y}) yaw={aw_yaw}")
time.sleep(0.5)

class P(Node):
    def __init__(self):
        super().__init__("lane_pose")
        self.pub = self.create_publisher(PoseWithCovarianceStamped, "/initialpose", 10)
        self.n = 0
        self.create_timer(0.35, self.tick)

    def tick(self):
        m = PoseWithCovarianceStamped()
        m.header.stamp = self.get_clock().now().to_msg()
        m.header.frame_id = "map"
        m.pose.pose.position.x = aw_x
        m.pose.pose.position.y = aw_y
        m.pose.pose.orientation.z = math.sin(aw_yaw / 2)
        m.pose.pose.orientation.w = math.cos(aw_yaw / 2)
        cov = [0.0] * 36
        cov[0] = cov[7] = 0.25
        cov[35] = 0.07
        m.pose.covariance = cov
        self.pub.publish(m)
        self.n += 1
        if self.n >= 8:
            raise SystemExit

rclpy.init()
n = P()
try:
    rclpy.spin(n)
except SystemExit:
    pass
n.destroy_node()
rclpy.shutdown()
print("[drive] pose OK")
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
}" || true

sleep 3
# wait briefly for trajectory
traj_ok=0
for i in $(seq 1 25); do
  if timeout 2 ros2 topic hz /planning/trajectory 2>&1 | grep -q average; then
    echo "[drive] trajectory up"
    traj_ok=1
    break
  fi
  sleep 1
done
if [[ "$traj_ok" -ne 1 ]]; then
  echo "[drive] WARN: no trajectory yet (localization/route may still be settling)"
fi

ros2 service call /api/autoware/set/engage tier4_external_api_msgs/srv/Engage "{engage: true}" || true
ros2 service call /api/operation_mode/change_to_stop autoware_adapi_v1_msgs/srv/ChangeOperationMode "{}" || true
sleep 1
ros2 service call /api/operation_mode/change_to_autonomous autoware_adapi_v1_msgs/srv/ChangeOperationMode "{}" || true
# retry autonomous once if needed
sleep 2
ros2 service call /api/operation_mode/change_to_autonomous autoware_adapi_v1_msgs/srv/ChangeOperationMode "{}" || true

echo "[drive] done OBJECT_SOURCE=$OBJECT_SOURCE"
echo "  Routing should be Set; Motion Moving after Engage."
echo "  Avoidance: RViz 2D Dummy Pedestrian ahead of ego (source=dummy)."
echo "  Do NOT press Emergency."

