# motion

运动规划笔记（轨迹速度、obstacle stop / slow down / cruise 等）。

与 behavior 绕障的关系：

- Behavior（`static_obstacle_avoidance`）负责 **横向 shift**。
- Motion（`obstacle_stop` 等）负责 **纵向停车/减速**。
- 若 behavior 因 `too_near_to_goal` 不产出 shift，RViz 上往往只看到 `obstacle_stop` / `obstacle_slow_down`，路径仍是直线。

本机相关：`/mnt/aw_res/docker/planning_overrides/motion_velocity_planner/obstacle_stop.param.yaml`
