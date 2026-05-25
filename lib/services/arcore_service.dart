import 'dart:async';
import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vector_math/vector_math_64.dart';

class ArCorePose {
  final Vector3 translation;
  final Quaternion rotation;
  final DateTime timestamp;

  ArCorePose({
    required this.translation,
    required this.rotation,
    required this.timestamp,
  });
}

class ArCoreService {
  ArCoreService._internal();
  static final ArCoreService instance = ArCoreService._internal();

  final StreamController<ArCorePose> _poseController = StreamController<ArCorePose>.broadcast();
  Stream<ArCorePose> get poseUpdates => _poseController.stream;

  bool _isArAvailable = false;
  bool get isArAvailable => _isArAvailable;

  ARSessionManager? _arSessionManager;
  MethodChannel? _directChannel;
  Timer? _pollingTimer;
  bool _isTracking = false;
  bool _isPollingBusy = false;
  int _consecutiveFailures = 0;

  Future<void> onARViewCreated(
      ARSessionManager arSessionManager,
      ARObjectManager arObjectManager,
      ARAnchorManager arAnchorManager,
      ARLocationManager arLocationManager) async {
    
    print("AR_SERVICE: onARViewCreated called.");
    
    // Check if permissions are actually granted at this point
    final cameraStatus = await Permission.camera.status;
    print("AR_SERVICE: Camera permission status: $cameraStatus");

    _pollingTimer?.cancel();
    _pollingTimer = null;
    _isTracking = false;
    _isPollingBusy = false;
    _directChannel = null;
    _consecutiveFailures = 0;
    _arSessionManager = arSessionManager;

    try {
      print("AR_SERVICE: Initializing AR Session with minimal features...");
      // We disable EVERYTHING that might trigger depth-based SphericalRectifier errors.
      // Note: We MUST NOT use depth on Pixel 4a 5G if we want to avoid the RET_CHECK failure
      await _arSessionManager!.onInitialize(
        showFeaturePoints: false, 
        showPlanes: false,
        showWorldOrigin: false, 
        handleTaps: false,
        showAnimatedGuide: false,
      );
      
      print("AR_SERVICE: Session initialized. 3s Warm-up start...");
      _setStatus("AR Core Warming up...");
      Future.delayed(const Duration(milliseconds: 3000), () {
        if (_arSessionManager == arSessionManager) {
          _startPolling();
        }
      });
    } catch (e) {
      print("AR_SERVICE_ERROR: Failed to initialize AR session: $e");
      _setStatus("AR Init Error: $e");
    }
  }

  void _setStatus(String status) {
    print("AR_STATUS: $status");
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _isTracking = false;
    print("AR_SERVICE: Starting polling loop.");
    
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) async {
      if (_arSessionManager == null || _isPollingBusy) return;
      
      // Slow down polling until tracking is established
      if (!_isTracking && timer.tick % 10 != 0) return;

      _isPollingBusy = true;
      try {
        dynamic poseData;
        
        // Use Direct Channel to avoid plugin's cast bug (Map -> List)
        if (_directChannel == null) {
          // Probe channels. The plugin usually uses arsession_0
          final candidates = ['arsession_0', 'arsession_1', 'arsession_2'];
          for (var name in candidates) {
            try {
              final result = await MethodChannel(name)
                  .invokeMethod<dynamic>('getCameraPose', {})
                  .timeout(const Duration(milliseconds: 100));
              
              if (result != null) {
                _directChannel = MethodChannel(name);
                print("AR_SERVICE: Bypassed plugin bug. Connected to: $name");
                poseData = result;
                break;
              }
            } catch (_) {}
          }
        } else {
          try {
            poseData = await _directChannel!
                .invokeMethod<dynamic>('getCameraPose', {})
                .timeout(const Duration(milliseconds: 150));
            _consecutiveFailures = 0;
          } catch (e) {
            _consecutiveFailures++;
            if (_consecutiveFailures > 10) _directChannel = null;
          }
        }
        
        if (poseData != null) {
          updatePose(poseData);
        }
      } finally {
        _isPollingBusy = false;
      }
    });
  }

  Future<bool> requestPermissions() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  void updatePose(dynamic poseData) {
    Matrix4? transform;

    // Handle various response types (Map from native, List from plugin)
    if (poseData is Map) {
      final dynamic pos = poseData['position'];
      final dynamic rot = poseData['rotation'];
      if (pos is Map && rot is Map) {
        final tx = (pos['x'] as num).toDouble();
        final ty = (pos['y'] as num).toDouble();
        final tz = (pos['z'] as num).toDouble();
        final rx = (rot['x'] as num).toDouble();
        final ry = (rot['y'] as num).toDouble();
        final rz = (rot['z'] as num).toDouble();
        final rw = (rot['w'] as num).toDouble();
        
        transform = Matrix4.compose(
          Vector3(tx, ty, tz),
          Quaternion(rx, ry, rz, rw),
          Vector3.all(1.0)
        );
      }
    } else if (poseData is List && poseData.length == 16) {
      transform = Matrix4.fromList(poseData.map((e) => (e as num).toDouble()).toList());
    }

    if (transform != null) {
      final storage = transform.storage;
      // Filter out invalid/identity-like initial ARCore matrices
      bool isZero = storage[0] == 0.0 && storage[5] == 0.0 && storage[10] == 0.0;
      bool isIdentity = storage[0] == 1.0 && storage[5] == 1.0 && storage[10] == 1.0 && storage[12] == 0.0 && storage[13] == 0.0 && storage[14] == 0.0;
      
      if (isZero) return;

      if (!_isTracking && !isIdentity) {
        print("AR_SERVICE: Tracking established!");
        _isTracking = true;
      }

      if (_isTracking) {
        _poseController.add(ArCorePose(
          translation: transform.getTranslation(),
          rotation: Quaternion.fromRotation(transform.getRotation()),
          timestamp: DateTime.now(),
        ));
      }
    }
  }

  void dispose() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _arSessionManager = null;
    _directChannel = null;
    _isTracking = false;
  }
}
