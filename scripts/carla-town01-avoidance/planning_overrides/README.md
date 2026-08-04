# Planning parameter overrides for light CARLA e2e (pedestrian avoid-first)

Mounted by `dev-humble-carla.compose.yaml` over Autoware launch configs:

- `behavior_path_planner/.../static_obstacle_avoidance.param.yaml`
  - Fast realtime bypass: short prepare time, higher lateral jerk/accel, max lane deviation 4 m
- `behavior_path_planner/drivable_area_expansion.param.yaml`
  - Left bound offset 3.5 m so path can enter adjacent/opposite visual lane
- `motion_velocity_planner/obstacle_stop.param.yaml`
  - Faster stop on/off so avoid path updates are not held back
- `behavior_path_planner/scene_module_manager.param.yaml`
  - `avoidance_by_lane_change` allowed simultaneous with static avoidance
- `planning_validator/trajectory_checker.param.yaml`
  - Relaxed lateral shift threshold (avoid MRM on bypass)

Hot-apply without recreate (most BPP/MVP params):

```bash
docker exec aw_carla_sim bash /home/aw/aw_docker/apply_fast_avoidance.sh
```

Single-obstacle retest:

```bash
docker exec aw_carla_sim bash /home/aw/aw_docker/retest_fast_avoid.sh
```

Edit on host under `/mnt/aw_res/docker/planning_overrides/`, then recreate the container
(`start_carla_e2e_light.sh`) so bind mounts / scene_module flags fully apply.
