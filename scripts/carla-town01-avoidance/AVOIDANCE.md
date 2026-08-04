# Pedestrian avoidance (light CARLA + Autoware)

## Quick start

```bash
export DISPLAY=:1 RVIZ=true CARLA_OFFSCREEN=1 OBJECT_SOURCE=dummy
/mnt/aw_res/docker/start_carla_e2e_light.sh
```

Do **not** press Emergency.

### Left-lane / opposite-lane bypass

Town01 centerlines were duplicate ways (same geometry, different IDs). After
`patch_town01_shared_bounds.py`, opposing parallel lanes **share** the center Linestring
and `lane_change=yes` — recreate `aw_carla_sim` to reload the map, then:

```bash
docker exec -e OBJECT_SOURCE=inject aw_carla_sim bash /home/aw/aw_docker/go_auto.sh
```

If the obstacle sits dead on centerline, planning may still prefer stop over a shift;
roadside offset (`inject` lateral 1.4 m) is the safer demo.

## Object sources (`OBJECT_SOURCE`)

| Value | Behavior |
|-------|----------|
| `dummy` | **RViz multi-scenario** — 2D Dummy Pedestrian/Car/Bus (recommended). |
| `inject` | Script ped ~14 m ahead + **1.4 m lateral** (auto demo only). |
| `static` | Several frozen map obstacles (script). Conflicts with RViz dummy. |
| `carla_walkers` | CARLA walkers → PredictedObjects. |
| `none` | Free occupancy grid only. |

### RViz publish “does nothing”

Usually because a script injector owns `/perception/object_recognition/objects`
and/or `dummy_perception_publisher` is not running. Fix:

```bash
docker exec aw_carla_sim bash /home/aw/aw_docker/enable_rviz_dummy.sh
```

Then in RViz: select **2D Dummy Pedestrian** (not Interact) → click beside the
lane center → Engage Auto. Works for any Town01 roadside placement (multi-scenario).

Also check: Fixed Frame=`map`, Localization=Initialized, Velocity Limit≈20,
no Emergency. Goal/Pose tools need the matching toolbar button selected first.

## Planning overrides

See `planning_overrides/README.md`. Bind-mounted via `dev-humble-carla.compose.yaml` (recreate container to apply).

## Bidirectional lanes (Town01)

Directional (one-way) road lanelets blocked opposite-direction goals/poses.

Applied change under `/mnt/aw_res/autoware/data/maps/Town01/lanelet2_map.osm`:

- every `road` lanelet tagged `one_way=no`
- a reverse lanelet (left/right swapped) added for each road lanelet

Backup: `lanelet2_map.osm.bak_oneway`

## Shared boundaries (for left-lane avoid / lane change)

CARLA Town01 had duplicate centerlines (same geometry, different way IDs), so Autoware
never saw adjacent lanes. Patch merges duplicate ways and tags shared bounds
`lane_change=yes`:

```bash
# already applied; re-run if restoring from backup then patching again
python3 /mnt/aw_res/docker/patch_town01_shared_bounds.py \
  /mnt/aw_res/autoware/data/maps/Town01/lanelet2_map.osm
```

Backup before patch: `lanelet2_map.osm.bak_pre_shared_*`

Restore pre-share map:

```bash
cp -a /mnt/aw_res/autoware/data/maps/Town01/lanelet2_map.osm.bak_pre_shared_* \
      /mnt/aw_res/autoware/data/maps/Town01/lanelet2_map.osm
# then recreate aw_carla_sim so map reloads
```

Restore original one-way Town01:

```bash
cp -a /mnt/aw_res/autoware/data/maps/Town01/lanelet2_map.osm.bak_oneway \
      /mnt/aw_res/autoware/data/maps/Town01/lanelet2_map.osm
# then recreate aw_carla_sim so map reloads
```


```bash
PERCEPTION=true /mnt/aw_res/docker/run_carla_e2e_with_perception.sh
```

Requires ≥8GB MemAvailable; often OOMs with CARLA + TRT.
