import 'dart:async';
import 'dart:math';
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

  Future<void> onARViewCreated(
      ARSessionManager arSessionManager,
      ARObjectManager arObjectManager,
      ARAnchorManager arAnchorManager,
      ARLocationManager arLocationManager) async {
    _arSessionManager = arSessionManager;
    
    print("AR_SERVICE: AR View Created. Initializing session...");

    try {
      await _arSessionManager!.onInitialize(
        showFeaturePoints: true, 
        showPlanes: false,
        showWorldOrigin: false, 
        handleTaps: false,
      );
      print("AR_SERVICE: Session initialized successfully.");
    } catch (e) {
      print("AR_SERVICE_ERROR: Failed to initialize AR session: $e");
    }
    
    _startPolling();
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _isTracking = false;
    print("AR_SERVICE: Starting polling for camera poses...");
    
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) async {
      if (_arSessionManager == null || _isPollingBusy) return;
      
      _isPollingBusy = true;
      try {
        dynamic poseData;
        
        // Try known channel candidates immediately if the primary isn't set
        if (_directChannel == null) {
          final candidates = ['arsession_0', 'ar_flutter_plugin', 'ar_flutter_plugin_0'];
          for (var name in candidates) {
            try {
              final result = await MethodChannel(name)
                  .invokeMethod<dynamic>('getCameraPose', {})
                  .timeout(const Duration(milliseconds: 100));
              if (result != null) {
                _directChannel = MethodChannel(name);
                print("AR_SERVICE: Connected to channel: $name");
                poseData = result;
                break;
              }
            } catch (_) {}
          }
        } else {
          try {
            poseData = await _directChannel!
                .invokeMethod<dynamic>('getCameraPose', {})
                .timeout(const Duration(milliseconds: 200));
          } catch (e) {
            _directChannel = null; // Reset for re-discovery if it fails
          }
        }
        
        // Fallback to official manager if direct channel failed
        if (poseData == null && _arSessionManager != null) {
          poseData = await _arSessionManager!.getCameraPose();
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

    if (poseData is Matrix4) {
      transform = poseData;
    } else if (poseData is Map) {
      dynamic matrixValue = poseData['matrix'] ?? poseData['transform'] ?? poseData['pose'];
      if (matrixValue is List) {
        try {
          final List<double> matrix = matrixValue.map((e) => (e as num).toDouble()).toList();
          if (matrix.length == 16) {
            transform = Matrix4.fromList(matrix);
          }
        } catch (_) {}
      }
    } else if (poseData is List && poseData.length == 16) {
      try {
        final List<double> matrix = poseData.map((e) => (e as num).toDouble()).toList();
        transform = Matrix4.fromList(matrix);
      } catch (_) {}
    }

    if (transform != null) {
      final storage = transform.storage;
      
      // Check for zero-matrix which indicates ARCore is NOT yet tracking.
      // We no longer block identity matrices (1.0 on diagonal) because the 
      // first valid tracking pose at the origin IS an identity matrix.
      bool isZero = storage[0] == 0.0 && storage[5] == 0.0 && storage[10] == 0.0;
      
      if (isZero) {
        if (_isTracking) {
          print("AR_SERVICE: Tracking lost (zero matrix)");
          _isTracking = false;
        }
        return;
      }

      if (!_isTracking) {
        print("AR_SERVICE: Tracking established! Matrix: ${storage[0]}, ${storage[5]}, ${storage[10]}");
        _isTracking = true;
      }

      final translation = transform.getTranslation();
      final rotation = Quaternion.fromRotation(transform.getRotation());
      
      _poseController.add(ArCorePose(
        translation: translation,
        rotation: rotation,
        timestamp: DateTime.now(),
      ));
    }
  }

  void dispose() {
    _pollingTimer?.cancel();
    _arSessionManager = null;
    _directChannel = null;
  }
}
