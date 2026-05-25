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
      // Initialize EKF orientation with first pose
      _currentState = EKFState(
        position: _currentState.position,
        velocity: _currentState.velocity,
        orientation: pose.rotation,
        covariance: _currentState.covariance,
        timestamp: DateTime.now(),
      );
      _processAndEmit(); // Process immediately to clear the "Loading" state
      return;
    }

    // 1. Calculate deltas in ARCore frame
    final deltaPosAR = pose.translation - _lastArPose!.translation;
    
    // 2. Rotate position delta into ENU frame using the current heading offset
    // ARCore uses Y-Up, X-Right, Z-Back. 
    // We map AR(X, Y, Z) to ENU(X, -Z, Y) roughly, but the _headingOffset handles the rotation around vertical.
    // The EKF position is in ENU (East-North-Up).
    
    // Convert AR delta to a local ENU-aligned delta (assuming initial AR Z is North)
    final localEnuDelta = Vector3(deltaPosAR.x, -deltaPosAR.z, deltaPosAR.y);
    
    final rotationOffset = Quaternion.axisAngle(Vector3(0, 0, 1), _headingOffset * pi / 180.0);
    final deltaPosENU = rotationOffset.rotated(localEnuDelta);

    // 3. Calculate rotation delta: q_delta = q_prev^-1 * q_curr
    final deltaRot = _lastArPose!.rotation.conjugated() * pose.rotation;

    // 4. Update EKF state with smoothed VIO deltas
    _currentState = EKFService.instance.predict(
      _currentState, 
      deltaPosENU, 
      deltaRot, 
      0.033, 
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
    // If we are missing critical data, we update the status but don't emit a pointing error yet.
    // This allows the UI to show specific "Waiting for..." messages instead of a generic spinner.
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

    // 1. Get robust heading from orientation quaternion
    final heading = PointingService.instance.getHeadingFromQuaternion(_currentState.orientation);
    final rawAzimuth = heading['azimuth']!;
    final sourceElevation = heading['elevation']!;
    
    // 2. Apply calibration offset
    final sourceAzimuth = (rawAzimuth + _headingOffset + 360) % 360;

    // 3. Compute target vectors in ENU
    final targetAz = PointingService.instance.computeAzimuthENU(_currentState.position, _targetEnu!);
    final targetEl = PointingService.instance.computeElevationENU(_currentState.position, _targetEnu!);

    // 4. Calculate final pointing errors
    final error = PointingService.instance.computePointingError(
      currentLocation: GeoPosition(latitude: _refLla!.x, longitude: _refLla!.y, altitude: _refLla!.z),
      targetAccessPoint: _targetAP!,
      sourceAzimuth: sourceAzimuth,
      sourceElevation: sourceElevation,
      targetAzimuth: targetAz,
      targetElevation: targetEl,
      pose: _currentState,
    );

    // ignore: avoid_print
    print("DATA_STREAM: [Src: ${sourceAzimuth.toStringAsFixed(1)}°, ${sourceElevation.toStringAsFixed(1)}°] "
          "[Tar: ${targetAz.toStringAsFixed(1)}°, ${targetEl.toStringAsFixed(1)}°] "
          "[Err: ${error.deltaAzimuth.toStringAsFixed(1)}°, ${error.deltaElevation.toStringAsFixed(1)}°]");

    _errorController.add(error);
    _lastError = error;
    BluetoothService.instance.sendPointingData(error);
  }
}
