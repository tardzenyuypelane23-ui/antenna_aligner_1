# Antenna Aligner (MAAAS)

An advanced Android application designed for high-precision antenna alignment using ARCore-assisted sensor fusion, GPS, and real-time geospatial calculations.

## Overview

The Antenna Aligner provides field engineers with a reliable tool to align microwave or cellular antennas to specific targets. It uses an Extended Kalman Filter (EKF) to fuse Visual-Inertial Odometry (VIO) from ARCore with GNSS data, ensuring accurate pointing even in environments with magnetic interference or GPS drift.

## Key Features

- **AR HUD Overlay**: Real-time display of Source vs. Target Azimuth and Elevation directly on the camera view.
- **Sensor Fusion (EKF)**: Combines ARCore tracking with GPS to provide stable positioning and sub-degree orientation accuracy.
- **True North Alignment**: Automatic calibration using hardware compass and geographic declination models.
- **Coordinate Reliability**: Built-in remapping between ARCore (Y-Up) and Geographic ENU (East-North-Up, Z-Up) frames to eliminate axis cross-talk (e.g., panning no longer affects elevation).
- **Dynamic Distance Tracking**: Real-time Euclidean distance calculation to the target Access Point.

## Technical Architecture

### Coordinate Systems
The app maintains a strict internal **ENU (East-North-Up)** coordinate system for all geospatial math:
- **X-axis**: East
- **Y-axis**: North
- **Z-axis**: Up (Zenith)

ARCore tracking data (Native Y-Up) is remapped to this frame using a 90-degree X-axis transformation. Orientation is extracted as a **Device-to-World** transformation to ensure that the phone's physical movement maps correctly to geographic bearings.

### Sensor Pipeline
1. **ArCoreService**: Provides high-frequency local pose updates (VIO).
2. **GeolocatorService**: Provides absolute LLA (Latitude, Longitude, Altitude) reference.
3. **CompassService**: Corrects magnetic heading to True North using WMM Declination.
4. **FusionService**: Acts as the central hub, integrating VIO deltas and GPS measurements into a consistent world-space pose.
5. **PointingService**: Calculates the angular error between the phone's camera LOS (Line of Sight) and the target ENU vector.

## Getting Started

### Prerequisites
- **Android Device**: Must support ARCore (Google Play Services for AR).
- **Sensors**: Requires GPS, Magnetometer, and Gyroscope.

### Permissions
The app requires the following permissions:
- `CAMERA`: For AR tracking and HUD overlay.
- `ACCESS_FINE_LOCATION`: For GPS baseline and target calculation.

### Installation
1. Ensure Flutter is installed.
2. Run `flutter pub get`.
3. Connect an ARCore-capable device and run `flutter run`.

## Usage
1. **Target Selection**: Select the target Access Point from the home screen.
2. **AR Initialization**: Hold the device steady in **Portrait Orientation** to initialize tracking.
3. **North Alignment**: The system will auto-calibrate to True North. For best results, calibrate 2 meters away from large metal structures.
4. **Alignment**: Rotate the phone until the Azimuth and Elevation errors in the HUD reach 0°.

## Development Notes
- **Simple VIO Mode**: The EKF is currently in a "Simple VIO" bypass mode to ensure maximum coordinate mapping stability during field validation.
- **Heading Extractor**: The azimuth is calculated using `atan2(East, North)` to provide a standard [0-360] compass bearing.

---
*Developed as part of the MAAAS Project.*
