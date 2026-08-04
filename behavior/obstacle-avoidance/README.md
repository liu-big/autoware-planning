# 静态障碍绕行（behavior）

日期：2026-08-04  
场景：CARLA Town01 + Autoware light e2e（`aw_carla_sim`）

## 结论

1. **能绕**：`static_obstacle_avoidance` 对右侧偏置行人生成 **left shift**（约 0.5–1.0 m），自车横向离开车道中心（例如 y: `-2.0 → -0.63`）。
2. **常见「只停不绕」**：`allow_goal_modification: true` 把终点吸近 → debug 出现 `others_too_near_to_goal` → 绕障忽略目标，只剩 `obstacle_stop`。
3. **联仿注意**：sync 模式下不要再开第二个 `carla.Client` 乱 `tick`/销毁车辆。

## 脚本位置

仓库内：[`scripts/carla-town01-avoidance/`](../../scripts/carla-town01-avoidance/)

推荐：

```bash
docker exec aw_carla_sim bash /home/aw/aw_docker/rerun_bypass_block.sh
```

完整步骤、参数表、排障见根目录 [README.md](../../README.md)。

## 关键检查

```bash
# avoidable_target_* （不是 too_near_to_goal）
timeout 3 ros2 topic echo \
  /planning/scenario_planning/lane_driving/behavior_planning/behavior_path_planner/debug/static_obstacle_avoidance \
  --once | grep ns:

# left shift
timeout 3 ros2 topic echo /planning/planning_factors/static_obstacle_avoidance --once \
  | grep -E "shift_length:|detail:"
```
