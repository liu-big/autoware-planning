#!/usr/bin/env bash
# Hot-apply fast realtime avoidance tuning (no container recreate).
# Scene-module slot flags still need recreate to fully take effect.
set +e
set +u; source /opt/ros/humble/setup.bash; source /opt/autoware/setup.bash; set -u

BPP=/planning/scenario_planning/lane_driving/behavior_planning/behavior_path_planner
MVP=/planning/scenario_planning/lane_driving/motion_planning/motion_velocity_planner

setp() {
  local node="$1" name="$2" val="$3"
  out=$(timeout 5 ros2 param set "$node" "$name" "$val" 2>&1 || true)
  echo "[fast_avoid] $name -> $(echo "$out" | tr '\n' ' ' | grep -oE 'success|Setting parameter failed|not settable|Unknown' | head -1)"
}

echo "[fast_avoid] applying realtime bypass params..."

# Expand drivable area into adjacent / opposite visual lane
setp "$BPP" drivable_area_left_bound_offset 3.5
setp "$BPP" drivable_area_right_bound_offset 1.0
setp "$BPP" dynamic_expansion.enabled true
setp "$BPP" dynamic_expansion.path_preprocessing.reuse_max_deviation 0.2
setp "$BPP" dynamic_expansion.path_preprocessing.resample_interval 1.0

# Faster avoidance path generation / update
setp "$BPP" avoidance.resample_interval_for_planning 0.2
setp "$BPP" avoidance.resample_interval_for_output 2.0
setp "$BPP" avoidance.avoidance.lateral.max_deviation_from_lane 4.0
setp "$BPP" avoidance.avoidance.lateral.th_avoid_execution 0.05
setp "$BPP" avoidance.avoidance.lateral.soft_drivable_bound_margin 0.05
setp "$BPP" avoidance.avoidance.lateral.hard_drivable_bound_margin 0.05
setp "$BPP" avoidance.avoidance.lateral.ratio_for_return_shift_approval 0.0
setp "$BPP" avoidance.avoidance.longitudinal.min_prepare_time 0.3
setp "$BPP" avoidance.avoidance.longitudinal.max_prepare_time 0.8
setp "$BPP" avoidance.avoidance.longitudinal.min_prepare_distance 0.5
setp "$BPP" avoidance.avoidance.longitudinal.nominal_avoidance_speed 5.56
setp "$BPP" avoidance.safety_check.hysteresis_factor_safe_count 1
setp "$BPP" avoidance.safety_check.hysteresis_factor_expand_rate 1.2
setp "$BPP" avoidance.cancel.force.duration_time 0.5
setp "$BPP" avoidance.stop.max_distance 12.0
setp "$BPP" avoidance.stop.stop_buffer 0.5
setp "$BPP" avoidance.shift_line_pipeline.trim.quantize_size 0.05
setp "$BPP" avoidance.target_filtering.avoidance_for_ambiguous_vehicle.policy auto
setp "$BPP" avoidance.constraints.lateral.max_accel_values "[1.0, 1.2, 1.5]"
setp "$BPP" avoidance.constraints.lateral.max_jerk_values "[5.0, 5.0, 5.0]"

# Release obstacle_stop faster when avoid path appears
setp "$MVP" obstacle_stop.stop_planning.stop_margin 2.5
setp "$MVP" obstacle_stop.stop_planning.min_behavior_stop_margin 1.5
setp "$MVP" obstacle_stop.stop_planning.behavior_stop_margin_hold_time 0.5
setp "$MVP" obstacle_stop.stop_planning.min_on_duration 0.1
setp "$MVP" obstacle_stop.stop_planning.min_off_duration 0.2
setp "$MVP" obstacle_stop.stop_planning.update_distance_th 0.2
setp "$MVP" obstacle_stop.obstacle_filtering.stop_obstacle_hold_time_threshold 0.3

echo "[fast_avoid] verify:"
timeout 3 ros2 param get "$BPP" avoidance.avoidance.longitudinal.min_prepare_time
timeout 3 ros2 param get "$BPP" avoidance.avoidance.lateral.max_deviation_from_lane
timeout 3 ros2 param get "$BPP" drivable_area_left_bound_offset
echo "[fast_avoid] done (recreate container later for scene_module_manager + yaml mount persistence)"
