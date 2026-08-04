#!/usr/bin/env python3
"""Inject a stationary PEDESTRIAN + empty obstacle pointcloud (no RViz tool needed).

Place the pedestrian ahead AND laterally offset from the lane centerline.
Autoware static_obstacle_avoidance ignores objects marked
`others_too_near_to_centerline` (on-centerline → stop only, no bypass).
"""
from __future__ import annotations

import math
import os
import uuid

import rclpy
from autoware_perception_msgs.msg import (
    ObjectClassification,
    PredictedObject,
    PredictedObjectKinematics,
    PredictedObjects,
    Shape,
)
from geometry_msgs.msg import Point, Pose, PoseWithCovariance, Quaternion, Vector3
from nav_msgs.msg import Odometry
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy
from sensor_msgs.msg import PointCloud2, PointField
from std_msgs.msg import Header
from unique_identifier_msgs.msg import UUID

BE_QOS = QoSProfile(
    reliability=ReliabilityPolicy.BEST_EFFORT,
    history=HistoryPolicy.KEEP_LAST,
    depth=1,
    durability=DurabilityPolicy.VOLATILE,
)


class Inject(Node):
    def __init__(self) -> None:
        super().__init__(
            "inject_dummy_pedestrian",
            parameter_overrides=[
                rclpy.parameter.Parameter(
                    "use_sim_time", rclpy.parameter.Parameter.Type.BOOL, True
                )
            ],
        )
        # Ahead along ego yaw; lateral offset (vehicle right = negative y in AW for +x lane)
        self.ahead_m = float(os.environ.get("PED_AHEAD_M", "14.0"))
        # + = left of heading, - = right. Need |offset| > th_offset_from_centerline (~1.0)
        self.lateral_m = float(os.environ.get("PED_LATERAL_M", "1.4"))
        self.obj_pub = self.create_publisher(
            PredictedObjects, "/perception/object_recognition/objects", 1
        )
        self.pc_pub = self.create_publisher(
            PointCloud2, "/perception/obstacle_segmentation/pointcloud", BE_QOS
        )
        self.pose = None
        self.create_subscription(
            Odometry, "/localization/kinematic_state", self.on_odom, 1
        )
        self.create_timer(0.1, self.tick)
        self.get_logger().info(
            f"inject PEDESTRIAN ahead={self.ahead_m}m lateral={self.lateral_m}m @ 10Hz"
        )

    def on_odom(self, msg: Odometry) -> None:
        self.pose = msg.pose.pose

    def _empty_pc(self, stamp) -> PointCloud2:
        pc = PointCloud2()
        pc.header = Header(stamp=stamp, frame_id="base_link")
        pc.height = 1
        pc.width = 0
        pc.fields = [
            PointField(name="x", offset=0, datatype=PointField.FLOAT32, count=1),
            PointField(name="y", offset=4, datatype=PointField.FLOAT32, count=1),
            PointField(name="z", offset=8, datatype=PointField.FLOAT32, count=1),
        ]
        pc.is_bigendian = False
        pc.point_step = 12
        pc.row_step = 0
        pc.data = []
        pc.is_dense = True
        return pc

    def tick(self) -> None:
        stamp = self.get_clock().now().to_msg()
        self.pc_pub.publish(self._empty_pc(stamp))
        if self.pose is None:
            return
        q = self.pose.orientation
        yaw = math.atan2(
            2.0 * (q.w * q.z + q.x * q.y), 1.0 - 2.0 * (q.y * q.y + q.z * q.z)
        )
        # forward + left-of-heading lateral (ROS/Autoware ENU yaw)
        c, s = math.cos(yaw), math.sin(yaw)
        px = self.pose.position.x + self.ahead_m * c - self.lateral_m * s
        py = self.pose.position.y + self.ahead_m * s + self.lateral_m * c

        out = PredictedObjects()
        out.header.stamp = stamp
        out.header.frame_id = "map"
        obj = PredictedObject()
        u = uuid.uuid5(uuid.NAMESPACE_OID, "inject-pedestrian-1")
        obj.object_id = UUID(uuid=list(u.bytes))
        obj.existence_probability = 1.0
        cls = ObjectClassification()
        cls.label = ObjectClassification.PEDESTRIAN
        cls.probability = 1.0
        obj.classification = [cls]
        kin = PredictedObjectKinematics()
        pose = Pose()
        pose.position = Point(x=px, y=py, z=0.0)
        pose.orientation = Quaternion(
            x=0.0, y=0.0, z=math.sin(yaw / 2.0), w=math.cos(yaw / 2.0)
        )
        pwc = PoseWithCovariance()
        pwc.pose = pose
        cov = [0.0] * 36
        cov[0] = cov[7] = 0.25
        cov[35] = 0.1
        pwc.covariance = cov
        kin.initial_pose_with_covariance = pwc
        obj.kinematics = kin
        shape = Shape()
        shape.type = Shape.BOUNDING_BOX
        shape.dimensions = Vector3(x=0.5, y=0.5, z=1.7)
        obj.shape = shape
        out.objects.append(obj)
        self.obj_pub.publish(out)


def main() -> None:
    rclpy.init(args=["--ros-args", "-p", "use_sim_time:=true"])
    node = Inject()
    try:
        rclpy.spin(node)
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
