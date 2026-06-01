import 'dart:async';
import 'package:antenna_aligner/models/access_point.dart';
import 'package:antenna_aligner/models/ekf_state.dart';
import 'package:antenna_aligner/models/pointing_error.dart';
import 'package:antenna_aligner/services/arcore_service.dart';
import 'package:antenna_aligner/services/compass_service.dart';
import 'package:antenna_aligner/services/coordinate_service.dart';
import 'package:antenna_aligner/services/ekf_service.dart';
import 'package:antenna_aligner/services/geolocator_service.dart';
import 'package:antenna_aligner/services/pointing_service.dart';
import 'package:vector_math/vector_math_64.dart';

import '../utils/transform.dart';

class FusionService {
  FusionService._internal();
  static final FusionService instance = FusionService._internal();

  EKFState _currentState = EKFState.initial();
  AccessPoint? _targetAP;
  double _headingOffset = 0.0; 
  bool _isCalibrated = false;

  final List<double> _magSamples = [];
  final int _magSampleWindow = 20;
  final double _magResultantThreshold = 0.75;
  
  Vector3? _refLla;
  Vector3? _refEcef;
  Vector3? _targetEnu;

  PointingError? _lastError;
  final StreamController<PointingError> _errorController = StreamController<PointingError>.broadcast();
  
  Stream<PointingError> get pointingStream async* {
    if (_lastError != null) yield _lastError!;
    yield* _errorController.stream;
  }

  final StreamController<String> _statusController = StreamController<String>.broadcast();
  String _lastStatus = "Waiting for sensors...";
  
  Stream<String> get statusStream async* {
    yield _lastStatus;
    yield* _statusController.stream;
  }

  void _setStatus(String status) {
    _lastStatus = status;
    _statusController.add(status);
  }

  StreamSubscription? _poseSub;
  StreamSubscription? _gpsSub;
  StreamSubscription? _compassSub;

  ArCorePose? _lastArPose;

  void start(AccessPoint target) {
    print("FusionService: Starting for ${target.name}");
    stop(); 
    _targetAP = target;
    _currentState = EKFState.initial();
    _isCalibrated = false;
    _lastArPose = null;
    _setStatus("Initializing Sensors...");
    
    if (_refLla != null && _refEcef != null) {
      _updateTargetEnu();
    }
    
    _poseSub = ArCoreService.instance.poseUpdates.listen((pose) {
      _predict(pose);
      // If we have AR but no GPS yet, update status to reassure the user
      if (_refLla == null) {
        _setStatus("AR Active. Waiting for GPS lock...");
      }
    });
    
    _gpsSub = GeolocatorService.instance.positionUpdates.listen((gpsPos) {
      _update(gpsPos);
      if (_lastStatus.contains("Waiting for GPS")) {
        _setStatus("Alignment Active");
      }
    });

    // Get mean magnetic heading for calibration
    _compassSub = CompassService.instance.magneticHeadingStream.listen((magHeading) {
      if (magHeading == null) return;

      // Only collect samples if we have a reference LLA (needed for declination)
      if (_refLla == null) return;

      // Collect sample into circular buffer
      _magSamples.add(magHeading);
      if (_magSamples.length > _magSampleWindow) {
        _magSamples.removeAt(0);
      }

      // When buffer full, compute resultant length and circular mean
      if (_magSamples.length >= _magSampleWindow) {
        final r = circularResultantLength(_magSamples);
        if (r >= _magResultantThreshold) {
          final mean = circularMeanDeg(_magSamples);
          // Call robust calibrator with the circular mean
          _autoCalibrate(mean);
          _magSamples.clear();
        }
      }
    });
    
    _processAndEmit();
  }

  /// Robust calibration using a provided mean magnetic heading (degrees).
  /// This method expects callers to supply a circular mean of recent magnetometer samples.
  /// It fetches declination from native code, computes true heading, reads ARCore azimuth
  /// (from the EKF orientation already remapped to ENU), and sets a signed heading offset.
  Future<void> _autoCalibrate(double meanMagHeading) async {
    if (_refLla == null) return;

    final lat = _refLla!.x;
    final lon = _refLla!.y;
    final alt = _refLla!.z;

    // 1. Fetch declination (degrees) from native Android GeomagneticField (or fallback).
    final declination = await CompassService.instance.getReliableDeclination(lat, lon, alt);

    // 2. Compute True Heading (0..360)
    final trueHeading = wrap360(meanMagHeading + declination);

    // 3. Compute ARCore azimuth from current EKF orientation (orientation is stored in ENU frame)
    final enuQuat = _currentState.orientation;
    final heading = PointingService.instance.getHeadingFromARCore(enuQuat, 0.0);
    final arAzimuth = heading['azimuth']!; // degrees [0,360)

    // 4. Compute signed offset (range [-180,180]) and store as degrees
    _headingOffset = normalizeSigned(trueHeading - arAzimuth);
    _isCalibrated = true;

    // ignore: avoid_print
    print("AUTO_CALIBRATE: [MeanMag: ${meanMagHeading.toStringAsFixed(2)}°] [Dec: ${declination.toStringAsFixed(2)}°] [True: ${trueHeading.toStringAsFixed(2)}°] [Offset: ${_headingOffset.toStringAsFixed(2)}°]");
    _setStatus("Calibrated to True North");
  }




  void _updateTargetEnu() {
    if (_targetAP == null || _refLla == null || _refEcef == null) return;
    final targetEcef = CoordinateService.instance.llaToEcef(
      _targetAP!.latitude, 
      _targetAP!.longitude, 
      _targetAP!.altitude
    );
    _targetEnu = CoordinateService.instance.ecefToEnu(targetEcef, _refLla!, _refEcef!);
  }

  void stop() {
    _poseSub?.cancel();
    _gpsSub?.cancel();
    _compassSub?.cancel();
    _poseSub = null;
    _gpsSub = null;
    _compassSub = null;
    _targetAP = null;
    _lastArPose = null;
    _lastError = null; // Clear stale data
    _refLla = null;
    _refEcef = null;
    _targetEnu = null;
    _isCalibrated = false;
    _setStatus("Stopped");
  }

  void _predict(ArCorePose pose) {
    if (_targetAP == null) return;

    if (_lastArPose == null) {
      _lastArPose = pose;
      // Initialize EKF orientation in ENU frame
      _currentState = EKFState(
        position: _currentState.position,
        velocity: _currentState.velocity,
        orientation: arcoreToEnuQuaternion(pose.rotation),
        covariance: _currentState.covariance,
        timestamp: DateTime.now(),
      );
      _processAndEmit(); // Process immediately to clear the initial loading state
      return;
    }

    // 1. Calculate raw, uncalibrated deltas directly within the ARCore frame
    final deltaPosAR = pose.translation - _lastArPose!.translation;

    // Calculate relative rotation delta: q_delta = q_prev^-1 * q_curr
    final deltaRot = _lastArPose!.rotation.conjugated() * pose.rotation;

    // 2. Map ARCore's local coordinate space directly to standard geographic ENU axes
    // ARCore Right (+X) maps to East (X)
    // ARCore Forward (-Z) maps to North (Y)
    // ARCore Up (+Y) maps to Up (Z)
    final localEnuDelta = Vector3(deltaPosAR.x, -deltaPosAR.z, deltaPosAR.y);

    // 3 & 4 . Keep EKF state in the canonical ENU remapped frame.
    //      Do NOT apply headingOffset here — apply headingOffset only when extracting heading for display/output.
    //      This avoids double application of the same correction.
    final deltaPosENU = localEnuDelta;


    // 5. Update the EKF state (orientation is maintained in ENU frame)
    _currentState = EKFService.instance.predict(
      _currentState,
      deltaPosENU,
      deltaRot,
      0.02,
    );

    _lastArPose = pose;
    _processAndEmit();
  }



  void _update(GeoPosition gpsPos) {
    if (_targetAP == null) return;

    final currentLla = Vector3(gpsPos.latitude, gpsPos.longitude, gpsPos.altitude);
    final currentEcef = CoordinateService.instance.llaToEcef(gpsPos.latitude, gpsPos.longitude, gpsPos.altitude);

    if (_refLla == null) {
      _refLla = currentLla;
      _refEcef = currentEcef;
      _updateTargetEnu();
    }

    final currentEnu = CoordinateService.instance.ecefToEnu(currentEcef, _refLla!, _refEcef!);
    _currentState = EKFService.instance.updateWithGNSS(_currentState, currentEnu);
    
    _processAndEmit();
  }

  void setHeadingOffset(double offset) {
    _headingOffset = offset;
    _processAndEmit();
  }

  void calibrateNorth() {
    // Current EKF orientation is already in ENU frame
    final enuRotation = _currentState.orientation;
    final heading = PointingService.instance.getHeadingFromARCore(enuRotation, 0.0);
    final rawAzimuth = heading['azimuth']!;
    // Offset makes current azimuth 0 (North)
    _headingOffset = wrap360(360 - rawAzimuth);
    _processAndEmit();
  }

  void _processAndEmit() {
    // 1. Structural guards
    if (_targetAP == null) return;

    if (_refLla == null) {
      _setStatus("Waiting for GPS lock...");
      return;
    }

    if (_targetEnu == null) {
      _updateTargetEnu();
      if (_targetEnu == null) return;
    }

    if (_lastArPose == null ) {
      _setStatus("Waiting for AR tracking...");
      return;
    }

    // 2. Ensure EKF orientation is ENU. If EKF was initialized with raw ARCore quaternion,
    //    initialize it with arcoreToEnuQuaternion at that point. Here we assume orientation is ENU.
    final enuRotation = _currentState.orientation;

    // 3. Extract heading using single-source offset application
    final heading = PointingService.instance.getHeadingFromARCore(enuRotation, _headingOffset);
    final sourceAzimuth = heading['azimuth']!;
    final sourceElevation = heading['elevation']!;

    // 4. Compute target azimuth/elevation using ENU positions
    final targetAzimuth = PointingService.instance.computeAzimuthENU(_currentState.position, _targetEnu!);
    final targetElevation = PointingService.instance.computeElevationENU(_currentState.position, _targetEnu!);

    // 5. Build GeoPosition metadata from reference LLA
    final activeLocation = GeoPosition(
      latitude: _refLla!.x,
      longitude: _refLla!.y,
      altitude: _refLla!.z,
    );

    // 6. Compute pointing error payload (delta angles normalized in PointingService)
    final pointingErrorPayload = PointingService.instance.computePointingError(
      currentLocation: activeLocation,
      targetAccessPoint: _targetAP!,
      sourceAzimuth: sourceAzimuth,
      sourceElevation: sourceElevation,
      targetAzimuth: targetAzimuth,
      targetElevation: targetElevation,
      pose: _currentState,
    );

    // 7. Compute Euclidean distance (meters) between EKF position and target ENU
    final currentMetricDistance = _currentState.position.distanceTo(_targetEnu!);

    // 8. Populate last error and emit
    _lastError = PointingError(
      currentLocation: pointingErrorPayload.currentLocation,
      targetAccessPoint: pointingErrorPayload.targetAccessPoint,
      sourceAzimuth: pointingErrorPayload.sourceAzimuth,
      sourceElevation: pointingErrorPayload.sourceElevation,
      targetAzimuth: pointingErrorPayload.targetAzimuth,
      targetElevation: pointingErrorPayload.targetElevation,
      deltaAzimuth: pointingErrorPayload.deltaAzimuth,
      deltaElevation: pointingErrorPayload.deltaElevation,
      pose: pointingErrorPayload.pose,
      distance: currentMetricDistance,
      timestamp: DateTime.now(),
    );

    _errorController.add(_lastError!);
  }


}
