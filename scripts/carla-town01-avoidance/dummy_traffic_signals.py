#!/usr/bin/env python3
"""Publish empty traffic signals so component_state_monitor allows Autonomous
when perception:=false (light CARLA e2e)."""
from __future__ import annotations

import rclpy
from rclpy.node import Node
from autoware_perception_msgs.msg import TrafficLightGroupArray
from std_msgs.msg import Header


class Pub(Node):
    def __init__(self) -> None:
        super().__init__(
            "dummy_traffic_signals",
            parameter_overrides=[
                rclpy.parameter.Parameter(
                    "use_sim_time", rclpy.parameter.Parameter.Type.BOOL, True
                )
            ],
        )
        self.pub = self.create_publisher(
            TrafficLightGroupArray,
            "/perception/traffic_light_recognition/traffic_signals",
            1,
        )
        self.create_timer(0.1, self.tick)
        self.get_logger().info("dummy traffic_signals @ 10Hz")

    def tick(self) -> None:
        msg = TrafficLightGroupArray()
        msg.stamp = self.get_clock().now().to_msg()
        msg.traffic_light_groups = []
        self.pub.publish(msg)


def main() -> None:
    rclpy.init(args=["--ros-args", "-p", "use_sim_time:=true"])
    node = Pub()
    try:
        rclpy.spin(node)
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
