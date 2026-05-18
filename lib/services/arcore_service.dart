import 'dart:async';
import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
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
  Timer? _pollingTimer;

  void onARViewCreated(
      ARSessionManager arSessionManager,
      ARObjectManager arObjectManager,
      ARAnchorManager arAnchorManager,
      ARLocationManager arLocationManager) {
    _arSessionManager = arSessionManager;
    _arSessionManager!.onInitialize(
      showFeaturePoints: false,
      showPlanes: false,
      showWorldOrigin: true,
      handleTaps: false,
    );
    
    _startPolling();
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    // Poll for camera pose at ~30Hz
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) async {
      if (_arSessionManager != null) {
        final pose = await _arSessionManager!.getCameraPose();
        if (pose != null) {
          updatePose(pose);
        }
      }
    });
  }

  Future<void> initialize() async {
    // AR availability is typically handled by the ARView and session manager internally
    // in newer versions of the plugin.
    _isArAvailable = true;
  }

  void updatePose(Matrix4 transform) {
    final translation = transform.getTranslation();
    final rotation = Quaternion.fromRotation(transform.getRotation());

    _poseController.add(ArCorePose(
      translation: translation,
      rotation: rotation,
      timestamp: DateTime.now(),
    ));
  }

  void dispose() {
    _pollingTimer?.cancel();
    _arSessionManager = null;
  }
}
