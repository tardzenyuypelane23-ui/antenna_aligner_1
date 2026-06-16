# Technical Document: Antenna Aligner System Architecture

## 1. System Overview
The Antenna Aligner is a sensor-fusion system built on Flutter. It integrates high-frequency visual-inertial odometry (ARCore) with absolute positioning (GNSS) and orientation (Magnetometer) sensors to provide precision antenna alignment guidance.

## 2. Coordinate Systems & Transformations
The system manages transitions between four primary coordinate frames:

*   **Geodetic (LLA)**: WGS84 Latitude, Longitude, and Altitude.
*   **ECEF (Earth-Centered, Earth-Fixed)**: A global Cartesian frame (meters) used for computing vectors between points on the Earth's surface.
*   **ENU (East-North-Up)**: A local tangent plane (meters). This is the primary frame for the Extended Kalman Filter (EKF).
*   **ARCore Frame**: The local device-centric frame (Right, Up, Back).

### Transformation Logic
1.  **Translation**: ARCore deltas are remapped to ENU: `(dx, -dz, dy)`.
2.  **Rotation**: The `arcoreToEnuQuaternion` applies a $+90^\circ$ pitch to align the device's optical axis with the ENU horizontal plane.

## 3. Sensor Fusion (Extended Kalman Filter)
The `EKFService` implements a linear-model Extended Kalman Filter to estimate the device's pose $(x, y, z, v_x, v_y, v_z, q)$.

*   **Prediction Step (~50Hz)**: Projects the state forward using ARCore translation and rotation deltas.
*   **Correction Step (~1Hz)**: Updates the state using GNSS position measurements. Innovation is calculated in the ENU frame.
*   **Covariance Management**: Tracks uncertainty in position and velocity, ensuring smooth tracking even during GPS "jitter."

## 4. Services Architecture
*   **`ArCoreService`**: Manages the AR session and polls the camera pose via a dedicated `MethodChannel` for low latency.
*   **`GeolocatorService`**: Handles GPS permissions and provides a stream of absolute LLA coordinates.
*   **`CompassService`**: Interfaces with the magnetometer and fetches magnetic declination via native Android APIs.
*   **`FusionService`**: The central orchestrator. It manages the EKF, handles auto-calibration, and emits the final pointing error.
*   **`PointingService`**: Contains the trigonometry for calculating target azimuth/elevation and angular error deltas.

## 5. Dependency Stack
*   **Flutter SDK**: UI and platform abstraction.
*   **vector_math_64**: High-precision linear algebra for 3D transforms.
*   **ar_flutter_plugin_2**: ARCore/ARKit integration.
*   **geolocator**: GNSS data access.
