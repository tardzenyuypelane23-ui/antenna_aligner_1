import 'package:vector_math/vector_math_64.dart';

class EKFState {
  final Vector3 position;    // x, y, z in meters (Relative or Global)
  final Vector3 velocity;    // vx, vy, vz
  final Quaternion orientation; // Orientation from fused sensors
  final Matrix4 covariance;  // Uncertainty matrix
  final DateTime timestamp;

  EKFState({
    required this.position,
    required this.velocity,
    required this.orientation,
    required this.covariance,
    required this.timestamp,
  });

  // Factory for initial state
  factory EKFState.initial() {
    return EKFState(
      position: Vector3.zero(),
      velocity: Vector3.zero(),
      orientation: Quaternion.identity(),
      covariance: Matrix4.identity() * 0.1,
      timestamp: DateTime.now(),
    );
  }
}
