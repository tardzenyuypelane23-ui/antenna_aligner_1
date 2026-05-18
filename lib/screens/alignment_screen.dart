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
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.1, // Keep it nearly invisible if preferred
                child: ARView(
                  onARViewCreated: (sessionManager, objectManager, anchorManager, locationManager) {
                    ArCoreService.instance.onARViewCreated(sessionManager, objectManager, anchorManager, locationManager);
                  },
                ),
              ),
            ),
          ),
          
          StreamBuilder<PointingError>(
            stream: FusionService.instance.pointingStream,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 24),
                      StreamBuilder<String>(
                        stream: FusionService.instance.statusStream,
                        initialData: "Initializing...",
                        builder: (context, statusSnapshot) {
                          return Text(
                            statusSnapshot.data ?? "Initializing...",
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Please move your device slowly to initialize AR tracking",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }
              
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              return AlignmentDisplay(pointingError: snapshot.data!);
            },
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
