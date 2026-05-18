import 'dart:math';
import 'package:antenna_aligner/models/access_point.dart';
import 'package:antenna_aligner/models/ekf_state.dart';
import 'package:antenna_aligner/models/pointing_error.dart';
import 'package:antenna_aligner/services/geolocator_service.dart';
import 'package:vector_math/vector_math_64.dart';

class PointingService {
  PointingService._internal();
  static final PointingService instance = PointingService._internal();

  /// Computes target Azimuth/Elevation from local metric coordinates (ENU)
  double computeAzimuthENU(Vector3 currentEnu, Vector3 targetEnu) {
    final delta = targetEnu - currentEnu;
    // atan2(East, North) gives bearing from North
    return (_radiansToDegrees(atan2(delta.x, delta.y)) + 360) % 360;
  }

  double computeElevationENU(Vector3 currentEnu, Vector3 targetEnu) {
    final delta = targetEnu - currentEnu;
    final horizontalDistance = sqrt(delta.x * delta.x + delta.y * delta.y);
    return _radiansToDegrees(atan2(delta.z, horizontalDistance));
  }

  /// Extracts Azimuth and Elevation from a device orientation quaternion.
  /// Azimuth: 0 = North, 90 = East, 180 = South, 270 = West.
  /// Elevation: +90 = Up, -90 = Down.
  Map<String, double> getHeadingFromQuaternion(Quaternion q) {
    // 1. Define the device's "pointing" direction in its local frame.
    // For most Android/ARCore devices, the camera looks along the negative Z-axis.
    final localForward = Vector3(0, 0, -1);
    
    // 2. Rotate the local forward vector into the global ARCore world frame.
    // In ARCore world frame: Y is Up, X is Right, Z is Back.
    final worldForward = q.rotated(localForward);

    // 3. Calculate Azimuth (bearing) in the horizontal (X-Z) plane.
    // We treat -Z as "AR North" and X as "AR East".
    // atan2(East, North) -> atan2(x, -z)
    double azimuth = _radiansToDegrees(atan2(worldForward.x, -worldForward.z));
    azimuth = (azimuth + 360) % 360;

    // 4. Calculate Elevation (angle from horizontal plane X-Z).
    final horizontalDist = sqrt(worldForward.x * worldForward.x + worldForward.z * worldForward.z);
    final elevation = _radiansToDegrees(atan2(worldForward.y, horizontalDist));

    return {
      'azimuth': azimuth,
      'elevation': elevation,
    };
  }

  /// Calculates the correction required to move from source to target.
  /// Returns values in range [-180, 180].
  /// Positive Azimuth error: Target is CLOCKWISE (Right) of current.
  /// Positive Elevation error: Target is ABOVE (Up) current.
  PointingError computePointingError({
    required GeoPosition currentLocation,
    required AccessPoint targetAccessPoint,
    required double sourceAzimuth,
    required double sourceElevation,
    required double targetAzimuth,
    required double targetElevation,
    required EKFState pose,
  }) {
    final deltaAz = _normalizeAngle(targetAzimuth - sourceAzimuth);
    final deltaEl = targetElevation - sourceElevation; // Elevation doesn't wrap 360

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
      timestamp: DateTime.now(),
    );
  }

  // Legacy LLA methods kept for compatibility or rough distance
  double computeTargetAzimuth(GeoPosition source, AccessPoint target) {
    final lat1 = _degreesToRadians(source.latitude);
    final lat2 = _degreesToRadians(target.latitude);
    final dLon = _degreesToRadians(target.longitude - source.longitude);

    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    return (_radiansToDegrees(atan2(y, x)) + 360) % 360;
  }

  double computeTargetElevation(GeoPosition source, AccessPoint target) {
    final lat1 = _degreesToRadians(source.latitude);
    final deltaLat = (target.latitude - source.latitude) * 111000.0;
    final deltaLon = (target.longitude - source.longitude) * 111000.0 * cos(lat1);
    final horizontalDistance = sqrt(deltaLat * deltaLat + deltaLon * deltaLon);
    final verticalDistance = target.altitude - source.altitude;
    return _radiansToDegrees(atan2(verticalDistance, horizontalDistance));
  }

  double _normalizeAngle(double angle) {
    var normalized = angle % 360;
    if (normalized > 180) normalized -= 360;
    if (normalized < -180) normalized += 360;
    return normalized;
  }

  double _degreesToRadians(double degrees) => degrees * pi / 180.0;
  double _radiansToDegrees(double radians) => radians * 180.0 / pi;
}
