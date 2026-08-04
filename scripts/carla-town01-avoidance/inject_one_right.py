#!/usr/bin/env python3
"""Single right-side static pedestrian for left-bypass demo."""
from __future__ import annotations

import os
import uuid

import rclpy
from autoware_perception_msgs.msg import (
    ObjectClassification,
    PredictedObject,
    PredictedObjectKinematics,
    PredictedObjects,
    PredictedPath,
    Shape,
)
from builtin_interfaces.msg import Duration
from geometry_msgs.msg import (
    Accel,
    AccelWithCovariance,
    Point,
    Pose,
    PoseWithCovariance,
    Quaternion,
    Twist,
    TwistWithCovariance,
    Vector3,
)
from rclpy.node import Node
from rclpy.parameter import Parameter
from sensor_msgs.msg import PointCloud2, PointField
from std_msgs.msg import Header
from unique_identifier_msgs.msg import UUID


class OneRight(Node):
    def __init__(self) -> None:
        super().__init__(
            "inject_one_right",
            parameter_overrides=[Parameter("use_sim_time", Parameter.Type.BOOL, True)],
        )
        self.ped_x = float(os.environ.get("PED_X", "36.0"))
        self.ped_y = float(os.environ.get("PED_Y", "-3.15"))
        self.pub = self.create_publisher(
            PredictedObjects, "/perception/object_recognition/objects", 1
        )
        self.pc = self.create_publisher(
            PointCloud2, "/perception/obstacle_segmentation/pointcloud", 1
        )
        self.create_timer(0.1, self.tick)
        self.get_logger().info(f"one right ped @ ({self.ped_x:.2f},{self.ped_y:.2f})")

    def tick(self) -> None:
        now = self.get_clock().now().to_msg()
        out = PredictedObjects()
        out.header = Header(stamp=now, frame_id="map")
        o = PredictedObject()
        u = uuid.uuid5(uuid.NAMESPACE_OID, "one-r")
        o.object_id = UUID(uuid=list(u.bytes))
        o.existence_probability = 1.0
        c = ObjectClassification()
        c.label = ObjectClassification.PEDESTRIAN
        c.probability = 1.0
        o.classification = [c]
        kin = PredictedObjectKinematics()
        pose = Pose(
            position=Point(x=self.ped_x, y=self.ped_y, z=0.0),
            orientation=Quaternion(w=1.0),
        )
        kin.initial_pose_with_covariance = PoseWithCovariance(
            pose=pose, covariance=[0.01] * 36
        )
        kin.initial_twist_with_covariance = TwistWithCovariance(
            twist=Twist(), covariance=[0.0] * 36
        )
        kin.initial_acceleration_with_covariance = AccelWithCovariance(
            accel=Accel(), covariance=[0.0] * 36
        )
        path = PredictedPath()
        path.confidence = 1.0
        path.time_step = Duration(sec=0, nanosec=200_000_000)
        path.path = [pose] * 5
        kin.predicted_paths = [path]
        o.kinematics = kin
        sh = Shape()
        sh.type = Shape.BOUNDING_BOX
        sh.dimensions = Vector3(x=0.5, y=0.5, z=1.7)
        o.shape = sh
        out.objects.append(o)
        self.pub.publish(out)
        pc = PointCloud2()
        pc.header = Header(stamp=now, frame_id="base_link")
        pc.height = 1
        pc.width = 0
        pc.fields = [
            PointField(name="x", offset=0, datatype=7, count=1),
            PointField(name="y", offset=4, datatype=7, count=1),
            PointField(name="z", offset=8, datatype=7, count=1),
        ]
        pc.point_step = 12
        pc.data = []
        self.pc.publish(pc)


def main() -> None:
    rclpy.init(args=["--ros-args", "-p", "use_sim_time:=true"])
    node = OneRight()
    try:
        rclpy.spin(node)
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
