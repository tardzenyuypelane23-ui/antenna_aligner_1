import 'package:antenna_aligner/models/ekf_state.dart';
import 'package:vector_math/vector_math_64.dart';

class EKFService {
  EKFService._internal();
  static final EKFService instance = EKFService._internal();

  // Process Noise (Q) and Measurement Noise (R) constants
  final double _processNoisePos = 0.01;
  final double _processNoiseVel = 0.1;
  final double _gpsNoise = 2.0; // GNSS is usually accurate to ~2-5m

  /// Prediction Step: Project the state forward using VIO delta
  /// [deltaPosition] and [deltaRotation] come from ARCore's Pose changes
  EKFState predict(EKFState prevState, Vector3 deltaPosition, Quaternion deltaRotation, double dt) {
    // 1. Predict Position: x_k = x_{k-1} + v_{k-1}*dt + 0.5*a*dt^2
    // For simplicity, we use the VIO delta directly as a displacement
    final predictedPos = prevState.position + deltaPosition;

    // 2. Predict Velocity: v_k = deltaPos / dt (Smoothing VIO velocity)
    final predictedVel = deltaPosition / (dt > 0 ? dt : 1.0);

    // 3. Predict Orientation: q_k = q_{k-1} * deltaQ
    final predictedOri = prevState.orientation * deltaRotation;
    predictedOri.normalize();

    // 4. Update Covariance (P_k = F*P_{k-1}*F' + Q)
    // Simplified: increase uncertainty over time during prediction
    // Matrix4 is 4x4, so we track position in 0,1,2 and general motion in 3.
    final newCovariance = prevState.covariance.clone();
    for (int i = 0; i < 3; i++) {
      newCovariance.setEntry(i, i, newCovariance.entry(i, i) + _processNoisePos);
    }
    newCovariance.setEntry(3, 3, newCovariance.entry(3, 3) + _processNoiseVel);

    return EKFState(
      position: predictedPos,
      velocity: predictedVel,
      orientation: predictedOri,
      covariance: newCovariance,
      timestamp: DateTime.now(),
    );
  }

  EKFState updateWithGNSS(EKFState state, Vector3 measuredGpsPos) {
    // 1. Innovation (GPS - predicted)
    final innovation = measuredGpsPos - state.position;

    // 2. Per-axis Kalman gains using diagonal covariance entries
    //    K_i = P_ii / (P_ii + R_i)
    //    Here we use _gpsNoise as R for each axis but you can make R a Vector3 if needed.
    final newCovariance = state.covariance.clone();

    final double pX = newCovariance.entry(0, 0);
    final double pY = newCovariance.entry(1, 1);
    final double pZ = newCovariance.entry(2, 2);

    final double kx = pX / (pX + _gpsNoise);
    final double ky = pY / (pY + _gpsNoise);
    final double kz = pZ / (pZ + _gpsNoise);

    // 3. Correct state per axis using the innovation and per-axis gains
    final correctedPx = state.position.x + innovation.x * kx;
    final correctedPy = state.position.y + innovation.y * ky;
    final correctedPz = state.position.z + innovation.z * kz;

    // 4. Update covariance diagonals: P = (I - K) * P
    newCovariance.setEntry(0, 0, (1.0 - kx) * pX);
    newCovariance.setEntry(1, 1, (1.0 - ky) * pY);
    newCovariance.setEntry(2, 2, (1.0 - kz) * pZ);

    return EKFState(
      position: Vector3(correctedPx, correctedPy, correctedPz),
      velocity: state.velocity,
      orientation: state.orientation,
      covariance: newCovariance,
      timestamp: DateTime.now(),
    );
  }


}
