# /// script
# requires-python = ">=3.9"
# dependencies = [
#     "open3d>=0.18",
#     "numpy>=1.24",
#     "scipy>=1.10",
#     "opencv-python>=4.8",
# ]
# ///
"""Visualize a StrayScanner dataset: coordinate frames, point clouds, or a
TSDF-integrated mesh. Run with `uv run scripts/integrate.py <path> --integrate`
(uv reads the inline dependency metadata above) or install the dependencies
manually and run with plain `python`.
"""
import os
from argparse import ArgumentParser

import numpy as np
import open3d as o3d
import cv2
from scipy.spatial.transform import Rotation

DEPTH_WIDTH = 256
DEPTH_HEIGHT = 192

def read_args():
    parser = ArgumentParser()
    parser.add_argument('path', type=str, help="Path to StrayScanner folder to process.")
    parser.add_argument('--frames', action='store_true', help="Visualize coordinate frames.")
    parser.add_argument('--point-clouds', action='store_true', help="Visualize point clouds one-by-one.")
    parser.add_argument('--integrate', action='store_true', help="Integrate frames into a TSDF mesh.")
    parser.add_argument('--every', type=int, default=50)
    return parser.parse_args()

def _resize_camera_matrix(camera_matrix, scale_x, scale_y):
    fx = camera_matrix[0, 0]
    fy = camera_matrix[1, 1]
    cx = camera_matrix[0, 2]
    cy = camera_matrix[1, 2]
    return np.array([[fx * scale_x, 0.0, cx * scale_x],
        [0., fy * scale_y, cy * scale_y],
        [0., 0., 1.0]])

def read_data(flags):
    intrinsics = np.loadtxt(os.path.join(flags.path, 'camera_matrix.csv'), delimiter=',')
    odometry = np.loadtxt(os.path.join(flags.path, 'odometry.csv'), delimiter=',', skiprows=1)
    poses = []

    for line in odometry:
        # timestamp, frame, x, y, z, qx, qy, qz, qw, ...
        position = line[2:5]
        quaternion = line[5:9]
        T_WC = np.eye(4)
        T_WC[:3, :3] = Rotation.from_quat(quaternion).as_matrix()
        T_WC[:3, 3] = position
        poses.append(T_WC)
    return { 'poses': poses, 'intrinsics': intrinsics }

def load_depth(path):
    # Depth is stored as a 16-bit grayscale PNG in millimeters (see docs/format.md).
    depth_mm = cv2.imread(path, cv2.IMREAD_UNCHANGED)
    depth_m = depth_mm.astype(np.float32) / 1000.0
    return o3d.geometry.Image(depth_m)

def get_intrinsics(intrinsics):
    # camera_matrix.csv / odometry intrinsics are at the RGB capture resolution
    # (1920x1440, 4:3 — matching the 4:3 depth aspect). Scale them down to the
    # 256x192 depth resolution.
    intrinsics_scaled = _resize_camera_matrix(intrinsics, DEPTH_WIDTH / 1920, DEPTH_HEIGHT / 1440)
    return o3d.camera.PinholeCameraIntrinsic(width=DEPTH_WIDTH, height=DEPTH_HEIGHT, fx=intrinsics_scaled[0, 0],
        fy=intrinsics_scaled[1, 1], cx=intrinsics_scaled[0, 2], cy=intrinsics_scaled[1, 2])

def show_frames(flags, data):
    frames = [o3d.geometry.TriangleMesh.create_coordinate_frame().scale(0.25, np.zeros(3))]
    for i, T_WC in enumerate(data['poses']):
        if not i % flags.every == 0:
            continue
        print(f"Frame {i}", end="\r")
        mesh = o3d.geometry.TriangleMesh.create_coordinate_frame().scale(0.1, np.zeros(3))
        frames.append(mesh.transform(T_WC))
    return frames

def point_clouds(flags, data):
    intrinsics = get_intrinsics(data['intrinsics'])
    pc = o3d.geometry.PointCloud()
    for i, T_WC in enumerate(data['poses']):
        if i % flags.every != 0:
            continue
        print(f"Point cloud {i}", end="\r")
        T_CW = np.linalg.inv(T_WC)
        depth = load_depth(os.path.join(flags.path, 'depth', f'{i:06}.png'))
        X = o3d.geometry.PointCloud.create_from_depth_image(depth, intrinsics, extrinsic=T_CW, depth_scale=1.0)
        pc += X.uniform_down_sample(every_k_points=10)
    return [pc]

def _rgb_frames(rgb_path):
    """Yields RGB frames from rgb.mp4 as HxWx3 uint8 arrays (RGB order)."""
    capture = cv2.VideoCapture(rgb_path)
    try:
        while True:
            ok, frame_bgr = capture.read()
            if not ok:
                break
            yield cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
    finally:
        capture.release()

def integrate(flags, data):
    volume = o3d.pipelines.integration.ScalableTSDFVolume(
            voxel_length=4.0 / 1024.0,
            sdf_trunc=0.05,
            color_type=o3d.pipelines.integration.TSDFVolumeColorType.RGB8)

    intrinsics = get_intrinsics(data['intrinsics'])

    rgb_path = os.path.join(flags.path, 'rgb.mp4')
    for i, (T_WC, rgb) in enumerate(zip(data['poses'], _rgb_frames(rgb_path))):
        print(f"Integrating frame {i:06}", end='\r')
        depth_path = os.path.join(flags.path, 'depth', f'{i:06}.png')
        depth = load_depth(depth_path)
        rgb = cv2.resize(rgb, (DEPTH_WIDTH, DEPTH_HEIGHT))
        rgbd = o3d.geometry.RGBDImage.create_from_color_and_depth(
            o3d.geometry.Image(np.ascontiguousarray(rgb)), depth,
            depth_scale=1.0, depth_trunc=4.0, convert_rgb_to_intensity=False)

        volume.integrate(rgbd, intrinsics, np.linalg.inv(T_WC))
    mesh = volume.extract_triangle_mesh()
    mesh.compute_vertex_normals()
    return [mesh]

def main():
    flags = read_args()

    data = read_data(flags)
    geometries = []
    if flags.frames:
        geometries += show_frames(flags, data)
    if flags.point_clouds:
        geometries += point_clouds(flags, data)
    if flags.integrate:
        geometries += integrate(flags, data)
    o3d.visualization.draw_geometries(geometries)

if __name__ == "__main__":
    main()
