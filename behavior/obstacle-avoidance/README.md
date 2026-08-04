# 静态障碍绕行（behavior）

日期：2026-08-04  
场景：CARLA Town01 + Autoware light e2e（`aw_carla_sim`）

## 结论（先看这个）

1. **能绕**：`static_obstacle_avoidance` 会对右侧偏置行人生成 **left shift**（约 0.5–1.0 m），自车横向会离开车道中心（例如 y: `-2.0 → -0.63`）。
2. **常见“只停不绕”根因**：`allow_goal_modification: true` 把终点吸到自车附近 → 障碍落入 goal 附近 → debug 出现 `others_too_near_to_goal` → 绕障模块忽略目标，只剩 `obstacle_stop` / `obstacle_slow_down`。
3. **联仿注意**：同步模式下不要再开第二个 `carla.Client` 乱 `tick`/销毁车辆，容易飞车或丢 ego。

## 推荐复现步骤

```bash
# 1) 启动联仿（保留 CARLA 时只重启 Autoware 亦可）
export DISPLAY=:1 RVIZ=true CARLA_OFFSCREEN=1 OBJECT_SOURCE=dummy
/mnt/aw_res/docker/start_carla_e2e_light.sh

# 2) 自车稳定后：前方右侧偏置行人 + 远端终点（禁止改 goal）
docker exec aw_carla_sim bash /home/aw/aw_docker/rerun_bypass_block.sh
```

关键检查：

```bash
# 应看到 avoidable_target_* ，而不是 others_too_near_to_goal
docker exec aw_carla_sim bash -lc '
  source /opt/ros/humble/setup.bash
  source /opt/autoware/setup.bash
  timeout 3 ros2 topic echo \
    /planning/scenario_planning/lane_driving/behavior_planning/behavior_path_planner/debug/static_obstacle_avoidance \
    --once | grep ns: | sort | uniq -c | sort -rn | head
'

# 应看到 left shift
docker exec aw_carla_sim bash -lc '
  source /opt/ros/humble/setup.bash
  source /opt/autoware/setup.bash
  timeout 3 ros2 topic echo /planning/planning_factors/static_obstacle_avoidance --once \
    | grep -E "shift_length:|detail:" | head
'
```

## 参数要点

| 项 | 建议 |
|----|------|
| 设终点 | `allow_goal_modification: false`，终点远离障碍（例如前方 +80 m） |
| `object_check_goal_distance` | 降到约 `5.0`（override 已改） |
| 行人横向 | 相对车道中心约 **0.7–1.4 m**（太贴中心易只停；太靠边可能直行擦过） |
| 障碍注入 | 用**地图固定坐标**（`inject_one_right.py` + `PED_X`/`PED_Y`），不要用跟车移动的 inject |
| `obstacle_stop.check_outside.default` | demo 时可 `false`，避免路边目标被 MVP 先死锁停车 |

本机 override：

- `/mnt/aw_res/docker/planning_overrides/behavior_path_planner/.../static_obstacle_avoidance.param.yaml`
- `/mnt/aw_res/docker/apply_fast_avoidance.sh`（热更新部分参数）

## 相关脚本（本机）

| 脚本 | 作用 |
|------|------|
| `start_carla_e2e_light.sh` | 启动 light e2e |
| `inject_one_right.py` | 固定右侧行人（`PED_X`/`PED_Y`） |
| `rerun_bypass_block.sh` | 前方近中心线行人 + 远终点绕行 |
| `bypass_no_carla_touch.sh` | 只动 ROS，不碰 CARLA API |
| `force_engage.sh` | 清急停并进 Autonomous |
| `AVOIDANCE.md` | 更早的绕行说明 |

## 地图前置（Town01）

- `one_way=no` + reverse lanelets  
- shared bounds：`lane_change=yes`（`patch_town01_shared_bounds.py`）  
细节归 **地图仓库**（`map-hdmap`），这里只引用。

## 待办

- [ ] 把成功一次的 RViz 截图与 shift 日志归档进 `assets/`
- [ ] 整理 `motion/` 下 obstacle_stop 与 behavior 绕障的职责边界笔记
- [ ] 与 simulation 仓库交叉链接（CARLA 启动/排障）
