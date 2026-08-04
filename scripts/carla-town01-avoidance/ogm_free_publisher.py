#!/usr/bin/env python3
"""Publish a free occupancy grid only (does NOT publish empty PredictedObjects)."""
from __future__ import annotations

import rclpy
from nav_msgs.msg import MapMetaData, OccupancyGrid
from rclpy.node import Node
from std_msgs.msg import Header


class FreeOgm(Node):
    def __init__(self) -> None:
        super().__init__(
            "ogm_free_publisher",
            parameter_overrides=[
                rclpy.parameter.Parameter(
                    "use_sim_time", rclpy.parameter.Parameter.Type.BOOL, True
                )
            ],
        )
        self.pub = self.create_publisher(
            OccupancyGrid, "/perception/occupancy_grid_map/map", 1
        )
        self.w = 100
        self.h = 100
        self.res = 0.5
        self.data = [0] * (self.w * self.h)
        self.create_timer(0.1, self.tick)
        self.get_logger().info("free occupancy grid @ 10Hz (base_link)")

    def tick(self) -> None:
        stamp = self.get_clock().now().to_msg()
        ogm = OccupancyGrid()
        ogm.header = Header(stamp=stamp, frame_id="base_link")
        info = MapMetaData()
        info.map_load_time = stamp
        info.resolution = self.res
        info.width = self.w
        info.height = self.h
        half = self.w * self.res / 2.0
        info.origin.position.x = -half
        info.origin.position.y = -half
        info.origin.orientation.w = 1.0
        ogm.info = info
        ogm.data = self.data
        self.pub.publish(ogm)


def main() -> None:
    rclpy.init(args=["--ros-args", "-p", "use_sim_time:=true"])
    node = FreeOgm()
    try:
        rclpy.spin(node)
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
