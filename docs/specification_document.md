# Specification Document: Antenna Aligner

## 1. Project Overview
The **Antenna Aligner** is a mobile application designed to assist technicians in precisely aligning microwave and cellular antennas. By leveraging Augmented Reality (AR), GNSS (GPS), and Magnetometer sensors, the app provides real-time guidance to hit specific geographic targets with high angular accuracy.

## 2. Problem Statement
Manual antenna alignment is often prone to human error, especially in remote or high-altitude environments. Traditional compasses are susceptible to local magnetic interference, and GPS alone lacks the orientation precision required for narrow-beam alignment.

## 3. Goals and Objectives
*   **Precision Alignment**: Achieve sub-degree angular accuracy for Azimuth and Elevation.
*   **Sensor Fusion**: Combine ARCore's Visual-Inertial Odometry (VIO) with absolute GNSS and Magnetometer data.
*   **Real-time Feedback**: Provide a visual "needle" or HUD to guide the user toward the target.
*   **Drift Mitigation**: Use an Extended Kalman Filter (EKF) to maintain pose stability even when sensors are noisy.

## 4. Functional Requirements
*   **AP Management**: Create, edit, and delete target Access Points (AP) with Lat/Lon/Alt coordinates.
*   **Live Tracking**: Real-time display of current device Azimuth and Elevation.
*   **Pointing Guidance**: Calculation of "Error" (Delta Azimuth and Delta Elevation) relative to a target.
*   **Calibration**: Automated calibration procedure to align the AR coordinate system with True North.
*   **Distance Tracking**: Real-time Euclidean distance calculation between the device and the target AP.

## 5. Non-Functional Requirements
*   **Performance**: High-frequency updates (>30Hz) for the AR guidance overlay.
*   **Reliability**: Robust handling of GPS signal loss or AR tracking interruptions.
*   **Usability**: Intuitive HUD design suitable for outdoor use in bright sunlight.
*   **Portability**: Built with Flutter for cross-platform potential (currently optimized for Android via ARCore).

## 6. Target Audience
Telecom field engineers, WISP (Wireless ISP) installers, and satellite dish technicians.
