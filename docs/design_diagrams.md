# Design Diagrams: Antenna Aligner

This document provides visual representations of the system architecture, data flow, and mathematical transformations using Mermaid.js syntax.

## 1. High-Level System Architecture
This diagram illustrates how raw sensor data flows through the service layer and EKF to produce the final guidance HUD.

```mermaid
graph TD
    subgraph Sensors
        GPS[GNSS Receiver]
        CAM[ARCore VIO]
        MAG[Magnetometer]
    end

    subgraph Service Layer
        GS[GeolocatorService]
        AS[ArCoreService]
        CS[CompassService]
        PS[PointingService]
    end

    subgraph Fusion Engine
        FS[FusionService]
        EKF[EKFService]
    end

    GPS --> GS
    CAM --> AS
    MAG --> CS

    GS -->|LLA| FS
    AS -->|Pose| FS
    CS -->|Mag Heading| FS

    FS -->|Delta Position/Rotation| EKF
    EKF -->|State Update| FS
    
    FS -->|Current Pose| PS
    PS -->|Azimuth/Elevation Error| FS
    
    FS -->|PointingError DTO| UI[Alignment HUD]
```

## 2. Coordinate Transformation Flow
The "Rosetta Stone" of the project: mapping absolute Earth coordinates and local AR coordinates into a unified local metric ENU frame.

```mermaid
graph LR
    subgraph Global
        LLA[Geodetic LLA] -->|WGS84| ECEF[ECEF Meters]
        ECEF -->|Reference LLA| ENU[Local ENU]
    end

    subgraph Local AR
        AR[ARCore Coordinate] -->|Axis Swap| AR_ENU[AR-Aligned ENU]
        AR_ENU -->|Heading Offset| ENU
    end
    
    subgraph Final Output
        ENU -->|Trigonometry| AE[Azimuth & Elevation]
    end
```

## 3. EKF Lifecycle (Predict & Update)
The recursive loop that maintains a stable pose even when individual sensors fail or lag.

```mermaid
stateDiagram-v2
    [*] --> Predict
    Predict --> Wait: Next AR Frame
    Wait --> Predict: New ArCorePose
    
    state Predict {
        direction LR
        State_k_minus_1 --> Apply_VIO_Delta
        Apply_VIO_Delta --> State_k_est
        State_k_est --> Expand_Covariance
    }

    Wait --> Update: New GPS Fix
    state Update {
        direction LR
        Compute_Innovation --> Calculate_Gain
        Calculate_Gain --> Adjust_State
        Adjust_State --> Contract_Covariance
    }
    Update --> Wait
```

## 4. Calibration Sequence
The process of aligning the virtual "North" with the geographic "True North."

```mermaid
sequenceDiagram
    participant S as Sensors (Mag)
    participant C as CompassService
    participant F as FusionService
    participant N as Native Android (WMM)

    S->>C: Raw Mag Heading
    C->>F: Mean Mag Heading (Buffered)
    F->>N: Request Declination(lat, lon, alt)
    N-->>F: Declination (Degrees)
    Note over F: True North = Mag + Dec
    F->>F: Calculate Heading Offset
    F->>F: Set _isCalibrated = true
    F->>UI: Update Alignment Status
```

## 5. UI Data Consumption
How the Flutter UI layer reacts to the stream of pointing errors.

```mermaid
graph TD
    FS[FusionService] -->|Stream PointingError| UI[AlignmentScreen]
    UI -->|rebuild| Needle[Compass Needle Widget]
    UI -->|rebuild| HUD[Digital Az/El Readout]
    UI -->|rebuild| Dist[Distance Tracker]
```
