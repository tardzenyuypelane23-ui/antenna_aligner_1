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

  /// Update Step: Correct the state using absolute GNSS coordinates
  EKFState updateWithGNSS(EKFState state, Vector3 measuredGpsPos) {
    // 1. Calculate Innovation (Difference between GPS and Predicted)
    final innovation = measuredGpsPos - state.position;

    // 2. Calculate Kalman Gain K = P / (P + R)
    // Simplified scalar-like update for each dimension
    final double pVal = state.covariance.entry(0, 0);
    final double kPos = pVal / (pVal + _gpsNoise);

    // 3. Update State
    final correctedPos = state.position + (innovation * kPos);

    // 4. Update Covariance P = (I - K) * P
    final newCovariance = state.covariance.clone();
    for (int i = 0; i < 3; i++) {
      double currentVal = newCovariance.entry(i, i);
      newCovariance.setEntry(i, i, (1.0 - kPos) * currentVal);
    }

    return EKFState(
      position: correctedPos,
      velocity: state.velocity,
      orientation: state.orientation,
      covariance: newCovariance,
      timestamp: DateTime.now(),
    );
  }
}
