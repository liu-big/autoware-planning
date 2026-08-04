# scripts/carla-town01-avoidance

Town01 + Autoware light e2e 静态绕障实验脚本与规划参数覆盖。

完整说明见仓库根目录 [README.md](../../README.md)。

## 推荐入口

```bash
# 已挂载到本机 /mnt/aw_res/docker 并启动 aw_carla_sim 后：
docker exec aw_carla_sim bash /home/aw/aw_docker/rerun_bypass_block.sh
```

## 同步到本机运行目录

```bash
REPO_SCRIPTS=/home/lj/autoware-planning/scripts/carla-town01-avoidance
cp -a "$REPO_SCRIPTS"/*.sh "$REPO_SCRIPTS"/*.py "$REPO_SCRIPTS"/*.md \
  /mnt/aw_res/docker/
cp -a "$REPO_SCRIPTS"/planning_overrides/. /mnt/aw_res/docker/planning_overrides/
# compose 如有更新再复制
cp -a "$REPO_SCRIPTS"/dev-humble-carla.compose.yaml /mnt/aw_res/docker/
```

路径硬编码针对当前实验机；换环境请自行替换 `/mnt/aw_res` 与 compose volumes。
