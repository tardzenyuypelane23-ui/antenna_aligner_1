import 'dart:math';
import 'package:antenna_aligner/models/access_point.dart';
import 'package:antenna_aligner/models/ekf_state.dart';
import 'package:antenna_aligner/models/pointing_error.dart';
import 'package:antenna_aligner/services/geolocator_service.dart';
import 'package:vector_math/vector_math_64.dart';

import '../utils/transform.dart';

class PointingService {
  PointingService._internal();
  static final PointingService instance = PointingService._internal();

  /// Computes target Azimuth/Elevation from local metric coordinates (ENU)
  double computeAzimuthENU(Vector3 currentEnu, Vector3 targetEnu) {
    final delta = targetEnu - currentEnu;
    // atan2(East, North) gives bearing from North
    return wrap360(radToDeg(atan2(delta.x, delta.y)));
  }

  double computeElevationENU(Vector3 currentEnu, Vector3 targetEnu) {
    final delta = targetEnu - currentEnu;
    final horizontalDistance = sqrt(delta.x * delta.x + delta.y * delta.y);
    return radToDeg(atan2(delta.z, horizontalDistance));
  }

  /// q must already be remapped to ENU (use a single helper arcoreToEnuQuaternion before calling).
  /// headingOffset is in degrees and is applied only here (single source of truth).
  Map<String, double> getHeadingFromARCore(Quaternion q, double headingOffset) {
    // 0. Defensive: ensure quaternion is normalized
    final enuQuat = Quaternion(q.x, q.y, q.z, q.w)..normalize();

    // 1. Camera forward vector in device local frame (camera looks along -Z)
    final localForward = Vector3(0, 0, -1);

    // 2. Rotate the local forward vector into ENU world frame
    final worldForward = enuQuat.rotated(localForward);

    // 3. Azimuth: atan2(East, North) -> degrees in [-180,180], then wrap to [0,360)
    double azimuth = radToDeg(atan2(worldForward.x, worldForward.y));
    azimuth = wrap360(azimuth + headingOffset);

    // 4. Elevation: angle above horizontal plane (degrees). Normalize to [-180,180] for safety.
    final horizontalDist = sqrt(worldForward.x * worldForward.x + worldForward.y * worldForward.y);
    double elevation = normalizeSigned(radToDeg(atan2(worldForward.z, horizontalDist)));

    return {
      'azimuth': azimuth,
      'elevation': elevation,
    };
  }



  /// Calculates the correction required to move from source to target.
  /// Returns values in range [-180, 180].
  /// Positive Azimuth error: Target is CLOCKWISE (Right) of current orientation.
  /// Positive Elevation error: Target is ABOVE (Up) current orientation.
  PointingError computePointingError({
    required GeoPosition currentLocation,
    required AccessPoint targetAccessPoint,
    required double sourceAzimuth,
    required double sourceElevation,
    required double targetAzimuth,
    required double targetElevation,
    required EKFState pose,
  }) {
    // 1. Calculate clean angular deltas using a [-180, 180] wrapping mechanism.
    // This stops your tracking needle from wrapping all the way around when crossing 0°/360°.
    final deltaAz = normalizeSigned(targetAzimuth - sourceAzimuth);
    final deltaEl = targetElevation - sourceElevation;

    // 2. Initialize the error payload container.
    // Note: The distance property is initialized here at 0.0 for safety,
    // and is immediately overwritten with the true EKF Euclidean metric distance
    // inside the calling FusionService._processAndEmit() pipeline.
    return PointingError(
      currentLocation: currentLocation,
      targetAccessPoint: targetAccessPoint,
      sourceAzimuth: sourceAzimuth,
      sourceElevation: sourceElevation,
      targetAzimuth: targetAzimuth,
      targetElevation: targetElevation,
      deltaAzimuth: deltaAz,
      deltaElevation: deltaEl,
      pose: pose,
      distance: 0.0,
      timestamp: DateTime.now(),
    );
  }


  // Legacy LLA methods kept for compatibility or rough distance
  double computeTargetAzimuth(GeoPosition source, AccessPoint target) {
    final lat1 = degToRad(source.latitude);
    final lat2 = degToRad(target.latitude);
    final dLon = degToRad(target.longitude - source.longitude);

    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    return wrap360(radToDeg(atan2(y, x)));
  }

  double computeTargetElevation(GeoPosition source, AccessPoint target) {
    final lat1 = degToRad(source.latitude);
    final deltaLat = (target.latitude - source.latitude) * 111000.0;
    final deltaLon = (target.longitude - source.longitude) * 111000.0 * cos(lat1);
    final horizontalDistance = sqrt(deltaLat * deltaLat + deltaLon * deltaLon);
    final verticalDistance = target.altitude - source.altitude;
    return radToDeg(atan2(verticalDistance, horizontalDistance));
  }

}
