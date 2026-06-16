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

    return Stack(
      children: [
        // Reticle (Always centered)
        Center(child: _buildReticle(context, color)),

        // HUD - Stats at the top
        Positioned(
          top: 60, // Below status icons
          left: 16,
          right: 16,
          child: _buildHUD(context, color),
        ),

        // Calibration Button at the bottom
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: _buildCalibrationTools(context),
        ),
      ],
    );
  }

  Widget _buildHUD(BuildContext context, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(180),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(150), width: 2),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(100), blurRadius: 10)
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _hudStat('AZ ERR', '${pointingError.deltaAzimuth.toStringAsFixed(1)}°', color),
              const SizedBox(width: 16),
              _hudStat('EL ERR', '${pointingError.deltaElevation.toStringAsFixed(1)}°', color),
            ],
          ),
          const Divider(color: Colors.white24, height: 20),
          _hudRow('CURRENT', '${pointingError.sourceAzimuth.toStringAsFixed(1)}° / ${pointingError.sourceElevation.toStringAsFixed(1)}°'),
          _hudRow('TARGET', '${pointingError.targetAzimuth.toStringAsFixed(1)}° / ${pointingError.targetElevation.toStringAsFixed(1)}°'),
          _hudRow('DISTANCE', '${pointingError.distance.toStringAsFixed(1)}m'),
        ],
      ),
    );
  }

  Widget _hudStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
          Text(value, style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _hudRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _buildCalibrationTools(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        StreamBuilder<bool>(
          stream: FusionService.instance.autoAlignStream,
          initialData: FusionService.instance.isAutoAligning,
          builder: (context, snapshot) {
            final isAutoAligning = snapshot.data ?? false;
            return ElevatedButton.icon(
              onPressed: () => FusionService.instance.toggleAutoAlign(),
              icon: Icon(isAutoAligning ? Icons.stop_circle : Icons.play_circle_filled),
              label: Text(isAutoAligning ? 'STOP AUTO-ALIGN' : 'START AUTO-ALIGN'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isAutoAligning ? Colors.red.withAlpha(200) : Colors.green.withAlpha(200),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () {
            FusionService.instance.calibrateNorth();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Heading Calibrated to North')),
            );
          },
          icon: const Icon(Icons.compass_calibration),
          label: const Text('CALIBRATE NORTH'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueGrey.shade900.withAlpha(200),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            side: const BorderSide(color: Colors.white24),
          ),
        ),
      ],
    );
  }

  Widget _buildReticle(BuildContext context, Color color) {
    return SizedBox(
      width: 300,
      height: 300,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background Rings
          ...List.generate(3, (index) => Container(
            width: (index + 1) * 80.0,
            height: (index + 1) * 80.0,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withAlpha(40), width: 1),
            ),
          )),
          // Crosshairs
          Container(width: 1, height: 260, color: Colors.white.withAlpha(30)),
          Container(width: 260, height: 1, color: Colors.white.withAlpha(30)),
          
          // The Target Dot
          AnimatedAlign(
            duration: const Duration(milliseconds: 100),
            alignment: Alignment(
              (pointingError.deltaAzimuth / 10.0).clamp(-1.0, 1.0),
              (-pointingError.deltaElevation / 10.0).clamp(-1.0, 1.0),
            ),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withAlpha(200),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [BoxShadow(color: color.withAlpha(150), blurRadius: 15)],
              ),
              child: const Icon(Icons.gps_fixed, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Color _getErrorColor(double totalError) {
    if (totalError < 1.0) return Colors.greenAccent;
    if (totalError < 5.0) return Colors.orangeAccent;
    return Colors.redAccent;
  }
}
