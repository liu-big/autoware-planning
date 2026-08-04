#!/usr/bin/env bash
# Switch object source to official RViz dummy tools (multi-scenario).
# Stops script injectors that overwrite /perception/object_recognition/objects.
set -euo pipefail
set +u; source /opt/ros/humble/setup.bash; source /opt/autoware/setup.bash; set -u
export PYTHONPATH="/opt/py310_site:${PYTHONPATH:-}"

echo "[rviz_dummy] stop injectors + start dummy_perception_publisher"
OBJECT_SOURCE=dummy bash /home/aw/aw_docker/start_dummy_objects.sh

# Hot-apply avoidance params that help any RViz-placed roadside obstacle
BPP=/planning/scenario_planning/lane_driving/behavior_planning/behavior_path_planner
timeout 5 ros2 param set "$BPP" drivable_area_left_bound_offset 3.5 >/dev/null 2>&1 || true
timeout 5 ros2 param set "$BPP" drivable_area_right_bound_offset 1.0 >/dev/null 2>&1 || true
timeout 5 ros2 param set "$BPP" avoidance.use_lane_type opposite_direction_lane >/dev/null 2>&1 || true
timeout 5 ros2 param set "$BPP" avoidance.avoidance.lateral.max_deviation_from_lane 4.0 >/dev/null 2>&1 || true
timeout 5 ros2 param set "$BPP" avoidance.target_object.pedestrian.lateral_margin.soft_margin 0.8 >/dev/null 2>&1 || true
timeout 5 ros2 param set "$BPP" avoidance.target_object.pedestrian.lateral_margin.hard_margin 0.5 >/dev/null 2>&1 || true
timeout 5 ros2 param set "$BPP" avoidance.target_filtering.detection_area.static true >/dev/null 2>&1 || true
timeout 5 ros2 param set "$BPP" avoidance.target_filtering.detection_area.min_forward_distance 10.0 >/dev/null 2>&1 || true

sleep 2
echo "[rviz_dummy] publishers on objects:"
timeout 3 ros2 topic info /perception/object_recognition/objects -v 2>/dev/null \
  | grep -E 'Publisher count|Node name:' | head -20 || true
echo "[rviz_dummy] dummy_perception topic:"
timeout 3 ros2 topic info /dummy_perception_publisher/object_info -v 2>/dev/null \
  | grep -E 'Publisher count|Subscription count|Node name:' | head -12 || true

echo
echo "[rviz_dummy] RViz usage (multi-scenario):"
echo "  1) Toolbar: click tool FIRST (not Interact)"
echo "     - 2D Pose Estimate  → set pose when Localization Uninitialized"
echo "     - 2D Goal Pose      → set route goal on lane"
echo "     - 2D Dummy Pedestrian / Car / Bus → place obstacle"
echo "  2) Place dummy BESIDE lane center (~1–1.5 m offset), not on centerline"
echo "  3) Same side only if you want continuous bypass (L+R zig-zag → stop)"
echo "  4) Engage Auto; Velocity Limit ~20; do NOT press Emergency"
echo "  5) If publish still dead: Fixed Frame=map, Localization=Initialized"
echo
echo "[rviz_dummy] OK"
