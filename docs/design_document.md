# Design Document: Antenna Aligner UI/UX & Data Flow

## 1. Design Philosophy
The UI is designed for high-stress, outdoor environments where visibility and simplicity are paramount. The "Heads-Up Display" (HUD) approach ensures that the most critical information—the alignment error—is always central.

## 2. Component Interaction
The system follows a reactive pattern using Flutter Streams:
*   **Services** (`FusionService`, `ArCoreService`, etc.) act as Data Sources.
*   **UI Components** (`AlignmentScreen`, `AlignmentDisplay`) act as Data Sinks, rebuilding only when new `PointingError` packets are emitted.

## 3. Screen Flow
1.  **Home Screen**: AP selection and status overview.
2.  **AP Manager**: Interface for adding/editing target geographic coordinates.
3.  **Alignment Screen**: The primary HUD. Displays:
    *   **Live AR View**: Background camera feed.
    *   **The Needle**: A 2D/3D graphical representation of the target direction.
    *   **Status Bar**: GPS accuracy, AR tracking state, and calibration status.
    *   **Metric Panel**: Real-time Azimuth, Elevation, and Distance to target.

## 4. Data Flow (The Guidance Loop)
1.  `ArCoreService` → `FusionService` (Predict State)
2.  `GeolocatorService` → `FusionService` (Correct State)
3.  `CompassService` → `FusionService` (Calibrate Frame)
4.  `FusionService` → `PointingService` (Calculate Error)
5.  `FusionService` → `AlignmentScreen` (Emit UI Update)

## 5. Visual Language
*   **Green**: Within alignment tolerance (< 1.0°).
*   **Yellow**: Approaching target (< 5.0°).
*   **Red**: Out of alignment.
*   **Pulsing Animation**: Used when GPS accuracy is low to warn the user.
