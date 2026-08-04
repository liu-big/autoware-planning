#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export HOST_UID=$(id -u) HOST_GID=$(id -g)
export RVIZ="${RVIZ:-false}"
export CARLA_OFFSCREEN="${CARLA_OFFSCREEN:-0}"
if [[ -z "${DISPLAY:-}" ]] || ! xdpyinfo -display "${DISPLAY}" >/dev/null 2>&1; then
  for d in :1 :0 :2; do xdpyinfo -display "$d" >/dev/null 2>&1 && export DISPLAY="$d" && break; done
fi
xhost +local:root >/dev/null 2>&1 || true
sync; printf "1\n" | sudo -S bash -c "echo 3 > /proc/sys/vm/drop_caches" 2>/dev/null || true

if ! ss -lntp 2>/dev/null | grep -q ":2000 "; then
  echo "[host] start CARLA Low offscreen=$CARLA_OFFSCREEN DISPLAY=$DISPLAY"
  nohup env CARLA_OFFSCREEN="$CARLA_OFFSCREEN" /mnt/aw_res/carla/start_carla.sh \
    >/mnt/aw_res/autoware/logs/carla_server.log 2>&1 &
  for i in $(seq 1 60); do ss -lntp 2>/dev/null | grep -q ":2000 " && break; sleep 2; done
fi
ss -lntp 2>/dev/null | grep -q ":2000 " || { echo "CARLA fail"; exit 1; }

docker rm -f aw_carla_sim 2>/dev/null || true
export MAP_PATH="${MAP_PATH:-/home/aw/autoware_data/maps/Town01}"
export DRIVE_SCRIPT="${DRIVE_SCRIPT:-drive_light.sh}"
echo "[host] light e2e RVIZ=$RVIZ MAP_PATH=$MAP_PATH drive=$DRIVE_SCRIPT (no container memory cap)"
RVIZ="$RVIZ" docker compose -f dev-humble-carla.compose.yaml run -d --name aw_carla_sim \
  -e RVIZ="$RVIZ" \
  -e MAP_PATH="$MAP_PATH" \
  -e DRIVE_SCRIPT="$DRIVE_SCRIPT" \
  -e CARLA_SPAWN_POINT="${CARLA_SPAWN_POINT:-None}" \
  autoware_carla bash /home/aw/aw_docker/run_carla_e2e_light.sh

echo "[host] wait ego vehicle (do not open second CARLA client in sync mode)..."
for i in $(seq 1 90); do
  # Prefer interface log / ROS topic — a second carla.Client breaks sync-mode snapshots
  if docker logs aw_carla_sim 2>&1 | grep -q 'Registered sensor:'; then
    echo "[host] ego/sensors registered"; break
  fi
  if docker exec aw_carla_sim bash -lc '
    set +u; source /opt/ros/humble/setup.bash; set -u
    timeout 2 ros2 topic list 2>/dev/null | grep -q "/sensing/lidar/top/pointcloud"
  ' 2>/dev/null; then
    echo "[host] lidar topic up"; break
  fi
  avail_kb=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
  if [[ "${avail_kb}" -lt 1500000 ]]; then
    echo "[host] MemAvailable=${avail_kb}kB < 1.5G, abort"
    docker rm -f aw_carla_sim >/dev/null 2>&1 || true
    killall -9 CarlaUE4-Linux-Shipping >/dev/null 2>&1 || true
    exit 2
  fi
  sleep 2
done

echo "[host] disable automatic pose initializer (conflicts with manual pose)"
# Bracket trick so pgrep pattern does not match this docker-exec argv.
docker exec aw_carla_sim bash -lc '
  pgrep -f "[a]utoware_automatic_pose_initializer" | xargs -r kill 2>/dev/null || true
  sleep 1
  pgrep -f "[a]utoware_automatic_pose_initializer" | xargs -r kill 2>/dev/null || true
' || true

echo "[host] objects+OGM + lane pose + route + engage (OBJECT_SOURCE=${OBJECT_SOURCE:-dummy})"
DRIVE_SCRIPT="${DRIVE_SCRIPT:-drive_light.sh}"
OBJECT_SOURCE="${OBJECT_SOURCE:-dummy}" docker exec -e OBJECT_SOURCE="${OBJECT_SOURCE:-dummy}" \
  aw_carla_sim bash "/home/aw/aw_docker/${DRIVE_SCRIPT}" \
  | tee /mnt/aw_res/autoware/logs/drive_light.log
free -h | head -2
echo "[host] OK. Watch RViz; do NOT press Emergency."
echo "  re-drive: OBJECT_SOURCE=dummy docker exec -e OBJECT_SOURCE=dummy aw_carla_sim bash /home/aw/aw_docker/drive_light.sh"
echo "  walkers:  OBJECT_SOURCE=carla_walkers docker exec -e OBJECT_SOURCE=carla_walkers aw_carla_sim bash /home/aw/aw_docker/start_dummy_objects.sh"
echo "  enable RViz: RVIZ=true $0"
echo "  full perception (risky): PERCEPTION=true /mnt/aw_res/docker/run_carla_e2e_with_perception.sh"
echo "  stop: docker rm -f aw_carla_sim; killall -9 CarlaUE4-Linux-Shipping"
