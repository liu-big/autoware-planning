# 领域仓库划分（约定）

每个领域一个仓库，目录不加序号：

| 仓库名（建议） | 内容 |
|----------------|------|
| `autoware-perception` | 感知 |
| `autoware-localization` | 定位 |
| `autoware-prediction` | 预测 |
| `autoware-planning` | 决策规划（本仓库） |
| `autoware-control` | 控制 |
| `autoware-platform` | 硬件平台与计算单元 |
| `autoware-map-v2x` | 高精地图与 V2X |
| `autoware-simulation` | 可选：CARLA/联仿运维（与 planning 交叉引用） |

本仓库只写 **规划三层** + 用仿真验证规划的实验记录。
