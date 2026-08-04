# global-route

全局路径 / mission planning 笔记。

今日实验相关：

- 设终点时务必 **`allow_goal_modification: false`**（绕障 demo），否则 goal 被改到自车附近，行为层会把障碍滤成 `too_near_to_goal`。
- ADAPI：`/api/routing/set_route_points`、`/api/routing/clear_route`
