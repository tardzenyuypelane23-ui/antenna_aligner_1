import 'package:flutter/material.dart';

import 'package:antenna_aligner/models/access_point.dart';
import 'package:antenna_aligner/services/database_service.dart';
import 'package:antenna_aligner/services/geolocator_service.dart';
import 'package:antenna_aligner/services/settings_service.dart';
import 'package:antenna_aligner/services/fusion_service.dart';
import 'package:antenna_aligner/utils/validators.dart';
import 'package:antenna_aligner/widgets/ap_list_widget.dart';

class APManagerScreen extends StatefulWidget {
  const APManagerScreen({super.key});

  @override
  State<APManagerScreen> createState() => _APManagerScreenState();
}

class _APManagerScreenState extends State<APManagerScreen> {
  final _nameController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _altitudeController = TextEditingController();
  late Future<List<AccessPoint>> _accessPointsFuture;
  bool _isCapturingLocation = false;

  @override
  void initState() {
    super.initState();
    _refreshAccessPoints();
  }

  void _refreshAccessPoints() {
    _accessPointsFuture = DatabaseService.instance.getAccessPoints();
  }

  Future<void> _captureCurrentLocation() async {
    setState(() {
      _isCapturingLocation = true;
    });

    try {
      final position = await GeolocatorService.instance.getCurrentPosition();
      _latitudeController.text = position.latitude.toStringAsFixed(6);
      _longitudeController.text = position.longitude.toStringAsFixed(6);
      _altitudeController.text = position.altitude.toStringAsFixed(1);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to capture location: $error')),
      );
    } finally {
      setState(() {
        _isCapturingLocation = false;
      });
    }
  }

  Future<void> _saveAccessPoint() async {
    final name = _nameController.text;
    final latitude = double.tryParse(_latitudeController.text);
    final longitude = double.tryParse(_longitudeController.text);
    final altitude = double.tryParse(_altitudeController.text) ?? 0.0;

    if (!Validators.isNonEmptyString(name) || latitude == null || longitude == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid coordinates and a name.')),
      );
      return;
    }

    final newAp = AccessPoint(
      name: name,
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
    );

    await DatabaseService.instance.addAccessPoint(newAp);

    _nameController.clear();
    _latitudeController.clear();
    _longitudeController.clear();
    _altitudeController.clear();

    setState(() {
      _refreshAccessPoints();
    });
  }

  Future<void> _deleteAccessPoint(int id) async {
    if (SettingsService.instance.selectedAccessPoint?.id == id) {
      SettingsService.instance.selectedAccessPoint = null;
      FusionService.instance.stop();
    }
    await DatabaseService.instance.removeAccessPoint(id);
    setState(() {
      _refreshAccessPoints();
    });
  }

  void _selectAccessPoint(AccessPoint ap) {
    setState(() {
      SettingsService.instance.selectedAccessPoint = ap;
      FusionService.instance.stop();
      FusionService.instance.start(ap);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Selected ${ap.name} for alignment')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Access Point Manager')),
      body: Column(
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Access Point Name'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isCapturingLocation ? null : _captureCurrentLocation,
                            icon: _isCapturingLocation
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.location_on),
                            label: Text(_isCapturingLocation ? 'Capturing...' : 'Capture Current Location'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_latitudeController.text.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Captured Location:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _latitudeController,
                            readOnly: true,
                            decoration: const InputDecoration(labelText: 'Latitude'),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _longitudeController,
                            readOnly: true,
                            decoration: const InputDecoration(labelText: 'Longitude'),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _altitudeController,
                            readOnly: true,
                            decoration: const InputDecoration(labelText: 'Altitude (m)'),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _latitudeController.text.isNotEmpty && _nameController.text.isNotEmpty
                                ? _saveAccessPoint
                                : null,
                            child: const Text('Add Access Point'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<AccessPoint>>(
              future: _accessPointsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(child: Text('Failed to load access points.'));
                }
                return APListWidget(
                  accessPoints: snapshot.data ?? const [],
                  onDelete: _deleteAccessPoint,
                  onSelect: _selectAccessPoint,
                  selectedId: SettingsService.instance.selectedAccessPoint?.id,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
