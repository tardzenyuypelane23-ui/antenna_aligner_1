import 'dart:async';
import 'dart:math';
import 'package:antenna_aligner/models/access_point.dart';
import 'package:antenna_aligner/models/ekf_state.dart';
import 'package:antenna_aligner/models/pointing_error.dart';
import 'package:antenna_aligner/services/arcore_service.dart';
import 'package:antenna_aligner/services/bluetooth_service.dart';
import 'package:antenna_aligner/services/compass_service.dart';
import 'package:antenna_aligner/services/coordinate_service.dart';
import 'package:antenna_aligner/services/ekf_service.dart';
import 'package:antenna_aligner/services/geolocator_service.dart';
import 'package:antenna_aligner/services/pointing_service.dart';
import 'package:vector_math/vector_math_64.dart';

class FusionService {
  FusionService._internal();
  static final FusionService instance = FusionService._internal();

  EKFState _currentState = EKFState.initial();
  AccessPoint? _targetAP;
  double _headingOffset = 0.0; 
  bool _isCalibrated = false;
  
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

    _compassSub = CompassService.instance.magneticHeadingStream.listen((magHeading) {
      if (magHeading != null && !_isCalibrated && _refLla != null) {
        _autoCalibrate(magHeading);
      }
    });
    
    _processAndEmit();
  }

  Future<void> _autoCalibrate(double magHeading) async {
    if (_refLla == null) return;
    
    final lat = _refLla!.x;
    final lon = _refLla!.y;
    final alt = _refLla!.z;

    // 1. Fetch reliable declination from native hardware (Android GeomaticField)
    final declination = await CompassService.instance.getReliableDeclination(lat, lon, alt);
    
    // 2. True Heading (Bearing from True North) = Magnetic Heading + Declination
    final trueHeading = (magHeading + declination + 360) % 360;

    // 3. Align ARCore's internal coordinate system to True North
    final heading = PointingService.instance.getHeadingFromQuaternion(_currentState.orientation);
    final arAzimuth = heading['azimuth']!;

    // Offset = TrueNorth - ARCore_Azimuth
    _headingOffset = (trueHeading - arAzimuth + 360) % 360;
    _isCalibrated = true;
    
    // ignore: avoid_print
    print("AUTO_CALIBRATE: [Mag: ${magHeading.toStringAsFixed(1)}°] [Dec: ${declination.toStringAsFixed(1)}°] [True: ${trueHeading.toStringAsFixed(1)}°] [Offset: ${_headingOffset.toStringAsFixed(1)}°]");
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
      // Initialize EKF orientation with the first uncalibrated ARCore pose
      _currentState = EKFState(
        position: _currentState.position,
        velocity: _currentState.velocity,
        orientation: pose.rotation,
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

    // 2. Map ARCore's local coordinate space directly to standard right-handed ENU axes
    // ARCore Right (+X) maps to East (X)
    // ARCore Up (+Y) maps to North (Y)
    // ARCore Back (+Z) maps to Up (Z) -> Note: If your hardware verification trace
    // shows that forward movement increases Z instead of decreasing it, use -deltaPosAR.z
    final localEnuDelta = Vector3(deltaPosAR.x, deltaPosAR.y, deltaPosAR.z);

    // 3. Create the true geospatial transformation matrix based on your True North heading offset
    // We use a negative angle because vector_math quaternions rotate Counter-Clockwise (CCW),
    // while geographic compass bearings rotate Clockwise (CW).
    final rotationOffset = Quaternion.axisAngle(Vector3(0, 0, 1), -_headingOffset * pi / 180.0);

    // 4. Transform the local position delta into the absolute True-North geographic ENU frame
    final deltaPosENU = rotationOffset.rotated(localEnuDelta);

    // 5. Critical Fix: Conjugate-rotate the rotation quaternion delta into the exact same True-North reference frame.
    // This step ensures your EKF orientation tracking state spins on the true geographic horizon,
    // matching your position updates and resolving the "Civil War" inside the filter state matrix.
    final correctedDeltaRot = rotationOffset * deltaRot * rotationOffset.conjugated();

    // 6. Update your EKF state with perfectly synchronized and pre-aligned vectors
    // We pass a standard time delta slice of 20ms (0.02) to match your 50ms ARCore polling loop frequency.
    _currentState = EKFService.instance.predict(
      _currentState,
      deltaPosENU,
      correctedDeltaRot,
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
    final heading = PointingService.instance.getHeadingFromQuaternion(_currentState.orientation);
    final rawAzimuth = heading['azimuth']!;
    // Offset makes current azimuth 0 (North)
    _headingOffset = (360 - rawAzimuth) % 360;
    _processAndEmit();
  }

  void _processAndEmit() {
    // 1. Structural Guard: Ensure all critical sensor systems have warm data.
    // This allows the UI to display granular states instead of a generic loading spinner.
    if (_targetAP == null) return;

    if (_refLla == null) {
      _setStatus("Waiting for GPS lock...");
      return;
    }

    if (_targetEnu == null) {
      _updateTargetEnu();
      if (_targetEnu == null) return;
    }

    if (_lastArPose == null) {
      _setStatus("Waiting for AR tracking...");
      return;
    }

    // 2. Extract stable orientation metrics out of the EKF State Quaternion.
    // Because the rotation deltas are now pre-aligned to True North during the
    // prediction stage, the extracted azimuth is natively aligned to True North.
    final heading = PointingService.instance.getHeadingFromQuaternion(_currentState.orientation);
    final sourceAzimuth = heading['azimuth']!;
    final sourceElevation = heading['elevation']!;

    // 3. Compute the True Target vectors from the current EKF position to the Target AP ENU vector.
    // This uses your mathematically verified, high-precision ENU coordinate pipeline.
    final targetAzimuth = PointingService.instance.computeAzimuthENU(_currentState.position, _targetEnu!);
    final targetElevation = PointingService.instance.computeElevationENU(_currentState.position, _targetEnu!);

    // 4. Create a valid GeoPosition instance from your reference coordinates for metadata tracking.
    final activeLocation = GeoPosition(
      latitude: _refLla!.x,
      longitude: _refLla!.y,
      altitude: _refLla!.z,
    );

    // 5. Generate the absolute calculation delta matrix via PointingService.
    final pointingError = PointingService.instance.computePointingError(
      currentLocation: activeLocation,
      targetAccessPoint: _targetAP!,
      sourceAzimuth: sourceAzimuth,
      sourceElevation: sourceElevation,
      targetAzimuth: targetAzimuth,
      targetElevation: targetElevation,
      pose: _currentState,
    );

    // 6. Calculate real-time 3D Euclidean distance (in meters) between the phone's EKF state and the AP.
    final currentMetricDistance = _currentState.position.distanceTo(_targetEnu!);

    // Update the class-level storage and push the clean error payload out to your stream listeners.
    _lastError = PointingError(
      currentLocation: pointingError.currentLocation,
      targetAccessPoint: pointingError.targetAccessPoint,
      sourceAzimuth: pointingError.sourceAzimuth,
      sourceElevation: pointingError.sourceElevation,
      targetAzimuth: pointingError.targetAzimuth,
      targetElevation: pointingError.targetElevation,
      deltaAzimuth: pointingError.deltaAzimuth,
      deltaElevation: pointingError.deltaElevation,
      pose: pointingError.pose,
      distance: currentMetricDistance,
      timestamp: DateTime.now(),
    );

    _errorController.add(_lastError!);
  }

}
