import 'dart:math';
import 'package:vector_math/vector_math_64.dart';

/// Transformation and angle helpers used across the antenna_aligner services.
/// Keep axis remapping, angle wrapping, and circular statistics in one place
/// to avoid subtle frame/angle bugs.

/// Wrap angle to [0, 360)
double wrap360(double degrees) => (degrees % 360 + 360) % 360;

/// Normalize angle to signed range [-180, 180)
double normalizeSigned(double degrees) {
  var v = wrap360(degrees);
  if (v >= 180.0) v -= 360.0;
  return v;
}

/// Convert degrees to radians
double degToRad(double deg) => deg * pi / 180.0;

/// Convert radians to degrees
double radToDeg(double rad) => rad * 180.0 / pi;

/// Circular mean for headings in degrees. Returns value in [0, 360).
/// Use this for averaging magnetometer headings to avoid wrap issues.
double circularMeanDeg(List<double> anglesDeg) {
  if (anglesDeg.isEmpty) return 0.0;
  double sumX = 0.0;
  double sumY = 0.0;
  for (final a in anglesDeg) {
    final r = degToRad(a);
    sumX += cos(r);
    sumY += sin(r);
  }
  final meanRad = atan2(sumY, sumX);
  return wrap360(radToDeg(meanRad));
}

/// Resultant vector length R in [0,1] for circular data; indicates concentration.
/// R = sqrt(sumX^2 + sumY^2) / N. Higher R means samples are tightly clustered.
double circularResultantLength(List<double> anglesDeg) {
  if (anglesDeg.isEmpty) return 0.0;
  double sumX = 0.0;
  double sumY = 0.0;
  for (final a in anglesDeg) {
    final r = degToRad(a);
    sumX += cos(r);
    sumY += sin(r);
  }
  final rLen = sqrt(sumX * sumX + sumY * sumY) / anglesDeg.length;
  return rLen;
}

/// Convert an ARCore device quaternion (X right, Y up, Z back) to ENU quaternion
/// (X east, Y north, Z up). This is the canonical remap used across the app.
/// - Input q: ARCore quaternion (x,y,z,w)
/// - Output: quaternion that rotates vectors into ENU coordinates
Quaternion arcoreToEnuQuaternion(Quaternion q) {
  // Rotate about device X by +90° to map ARCore forward/back to ENU north axis.
  // This matches the remap used elsewhere: Quaternion.axisAngle(Vector3(1,0,0), pi/2)
  final remap = Quaternion.axisAngle(Vector3(1, 0, 0), pi / 2);
  final out = (remap * q);
  out.normalize();
  return out;
}

/// Rotate a vector by a quaternion and return the rotated vector.
/// Convenience wrapper to make intent explicit in code that uses it.
Vector3 rotateVectorByQuaternion(Quaternion q, Vector3 v) {
  final qv = Quaternion(v.x, v.y, v.z, 0.0);
  final res = q * qv * q.conjugated();
  return Vector3(res.x, res.y, res.z);
}
