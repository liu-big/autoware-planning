# autoware-planning

Autoware **决策规划**领域笔记与实验记录。

按三层拆分：

| 目录 | 对应能力 |
|------|----------|
| `global-route/` | 全局路径规划（mission / route） |
| `behavior/` | 行为决策（lane change、绕障、交叉口等） |
| `motion/` | 运动规划（轨迹速度、obstacle stop/cruise） |

> 感知 / 定位 / 控制 / 地图·V2X / 平台 各自独立仓库，不放在这里。

## 本机实验环境（摘要）

- Autoware Humble + CARLA Town01 light e2e
- 容器：`aw_carla_sim`
- 脚本根：`/mnt/aw_res/docker/`

## 今天记录

见 [`behavior/obstacle-avoidance/`](behavior/obstacle-avoidance/)：Town01 静态障碍绕行（CARLA 联仿）。
