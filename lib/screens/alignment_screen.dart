import 'package:antenna_aligner/services/geolocator_service.dart';
import 'package:antenna_aligner/services/settings_service.dart';
import 'package:ar_flutter_plugin_2/ar_flutter_plugin.dart';
import 'package:antenna_aligner/services/arcore_service.dart';
import 'package:flutter/material.dart';
import 'package:antenna_aligner/models/pointing_error.dart';
import 'package:antenna_aligner/services/database_service.dart';
import 'package:antenna_aligner/services/fusion_service.dart';
import 'package:antenna_aligner/widgets/alignment_display.dart';

class AlignmentScreen extends StatefulWidget {
  const AlignmentScreen({super.key});

  @override
  State<AlignmentScreen> createState() => _AlignmentScreenState();
}

class _AlignmentScreenState extends State<AlignmentScreen> {
  bool _isInitializing = true;
  bool _hasAccessPoints = false;

  @override
  void initState() {
    super.initState();
    _initializeAlignment();
  }

  @override
  void dispose() {
    FusionService.instance.stop();
    ArCoreService.instance.dispose();
    super.dispose();
  }

  Future<void> _initializeAlignment() async {
    // 1. Request Camera Permission (Critical for AR)
    final hasCamera = await ArCoreService.instance.requestPermissions();
    if (!hasCamera && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera permission is required for AR tracking.')),
      );
    }

    // 2. Request Location Permission (Critical for GPS)
    try {
      await GeolocatorService.instance.requestPermissions();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Location error: $e')),
        );
      }
    }

    final accessPoints = await DatabaseService.instance.getAccessPoints();
    final selectedAp = SettingsService.instance.selectedAccessPoint ?? 
                      (accessPoints.isNotEmpty ? accessPoints.first : null);

    if (mounted) {
      setState(() {
        _isInitializing = false;
        _hasAccessPoints = accessPoints.isNotEmpty;
      });
    }

    if (selectedAp != null) {
      SettingsService.instance.selectedAccessPoint = selectedAp;
      FusionService.instance.start(selectedAp);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Scaffold(
        appBar: AppBar(title: const Text('Real-time Alignment')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasAccessPoints) {
      return Scaffold(
        appBar: AppBar(title: const Text('Real-time Alignment')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('No Access Points found.'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, '/ap_manager'),
                child: const Text('Add Access Point'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(SettingsService.instance.selectedAccessPoint?.name ?? 'Real-time Alignment'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: () => Navigator.pushNamed(context, '/ap_manager').then((_) => _initializeAlignment()),
            tooltip: 'Change Access Point',
          ),
          IconButton(
            icon: const Icon(Icons.settings_bluetooth),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: Stack(
        children: [
          // AR View - Must have a size and be in the widget tree to initialize
          Positioned.fill(
            child: ARView(
              onARViewCreated: (sessionManager, objectManager, anchorManager, locationManager) {
                print("WIDGET: ARView.onARViewCreated fired!");
                ArCoreService.instance.onARViewCreated(sessionManager, objectManager, anchorManager, locationManager);
              },
            ),
          ),
          
          Positioned.fill(
            child: StreamBuilder<PointingError>(
              stream: FusionService.instance.pointingStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Container(
                    color: Colors.black.withAlpha(100), // Semi-transparent overlay while loading
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(color: Colors.white),
                            const SizedBox(height: 32),
                            StreamBuilder<String>(
                              stream: FusionService.instance.statusStream,
                              initialData: "Initializing...",
                              builder: (context, statusSnapshot) {
                                final status = statusSnapshot.data ?? "Initializing...";
                                String hint = "Starting sensors...";
                                
                                if (status.contains("GPS")) {
                                  hint = "Waiting for satellite lock. Ensure you have a clear view of the sky.";
                                } else if (status.contains("AR") || status.contains("Tracking")) {
                                  hint = "Please move your device slowly to initialize AR tracking";
                                } else if (status.contains("Initializing")) {
                                  hint = "Calibrating inertial sensors...";
                                }

                                return Column(
                                  children: [
                                    Text(
                                      status,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 18, 
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      hint,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
                }

                return AlignmentDisplay(pointingError: snapshot.data!);
              },
            ),
          ),

          // Sensor Status Indicators
          Positioned(
            top: 10,
            right: 10,
            child: Row(
              children: [
                _StatusIcon(
                  stream: ArCoreService.instance.poseUpdates,
                  label: "AR",
                  icon: Icons.camera,
                ),
                const SizedBox(width: 8),
                _StatusIcon(
                  stream: GeolocatorService.instance.positionUpdates,
                  label: "GPS",
                  icon: Icons.location_on,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusIcon<T> extends StatelessWidget {
  final Stream<T> stream;
  final String label;
  final IconData icon;

  const _StatusIcon({
    required this.stream,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T>(
      stream: stream,
      builder: (context, snapshot) {
        final isActive = snapshot.hasData && !snapshot.hasError;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: (isActive ? Colors.green : Colors.red).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isActive ? Colors.green : Colors.red),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: isActive ? Colors.green : Colors.red),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isActive ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
