import 'package:antenna_aligner/services/fusion_service.dart';
import 'package:flutter/material.dart';
import 'package:antenna_aligner/models/pointing_error.dart';

class AlignmentDisplay extends StatelessWidget {
  const AlignmentDisplay({
    super.key,
    required this.pointingError,
  });

  final PointingError pointingError;

  @override
  Widget build(BuildContext context) {
    final totalError = (pointingError.deltaAzimuth.abs() + pointingError.deltaElevation.abs());
    final color = _getErrorColor(totalError);

    return SingleChildScrollView(
      child: Column(
        children: [
          _buildReticle(context, color),
          _buildCalibrationTools(context),
          _buildErrorSummary(context, color),
          _buildDetailedStats(context),
        ],
      ),
    );
  }

  Widget _buildCalibrationTools(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton.icon(
            onPressed: () {
              FusionService.instance.calibrateNorth();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Heading Calibrated to North')),
              );
            },
            icon: const Icon(Icons.compass_calibration),
            label: const Text('Calibrate North'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey.shade800,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReticle(BuildContext context, Color color) {
    return Container(
      height: 300,
      margin: const EdgeInsets.symmetric(vertical: 24),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background Rings
          ...List.generate(3, (index) => Container(
            width: (index + 1) * 80.0,
            height: (index + 1) * 80.0,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.withAlpha(77), width: 1),
            ),
          )),
          // Crosshairs
          Container(width: 2, height: 240, color: Colors.grey.withAlpha(51)),
          Container(width: 240, height: 2, color: Colors.grey.withAlpha(51)),
          
          // The Target Dot (Moving based on error)
          // We map -10 to +10 degrees error to -100 to +100 pixels
          AnimatedAlign(
            duration: const Duration(milliseconds: 100),
            alignment: Alignment(
              (pointingError.deltaAzimuth / 10.0).clamp(-1.0, 1.0),
              (pointingError.deltaElevation / 10.0).clamp(-1.0, 1.0),
            ),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withAlpha(179),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 3),
                boxShadow: [BoxShadow(color: color.withAlpha(128), blurRadius: 10)],
              ),
              child: const Icon(Icons.gps_fixed, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorSummary(BuildContext context, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _statCard('Azimuth Error', '${pointingError.deltaAzimuth.toStringAsFixed(1)}°', color),
          _statCard('Elevation Error', '${pointingError.deltaElevation.toStringAsFixed(1)}°', color),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Expanded(
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailedStats(BuildContext context) {
    final pos = pointingError.pose.position;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ExpansionTile(
          title: const Text('Diagnostics & Sensor Fusion', style: TextStyle(fontSize: 14)),
          children: [
            ListTile(
              title: const Text('Filtered Position (Local ENU)'),
              subtitle: Text('E: ${pos.x.toStringAsFixed(2)}m, N: ${pos.y.toStringAsFixed(2)}m, U: ${pos.z.toStringAsFixed(2)}m'),
            ),
            ListTile(
              title: const Text('Target Location'),
              subtitle: Text(pointingError.targetAccessPoint.name),
            ),
            ListTile(
              title: const Text('Last Packet Sent'),
              trailing: const Icon(Icons.bluetooth_connected, color: Colors.blue),
              subtitle: Text('ID: ${pointingError.timestamp.millisecondsSinceEpoch}'),
            ),
          ],
        ),
      ),
    );
  }

  Color _getErrorColor(double totalError) {
    if (totalError < 1.0) return Colors.green;
    if (totalError < 5.0) return Colors.orange;
    return Colors.red;
  }
}
