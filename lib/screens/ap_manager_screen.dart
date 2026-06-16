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
    
    // Add listeners to keep UI in sync with manual input
    _nameController.addListener(_onInputChanged);
    _latitudeController.addListener(_onInputChanged);
    _longitudeController.addListener(_onInputChanged);
    _altitudeController.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _nameController.removeListener(_onInputChanged);
    _latitudeController.removeListener(_onInputChanged);
    _longitudeController.removeListener(_onInputChanged);
    _altitudeController.removeListener(_onInputChanged);
    _nameController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _altitudeController.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    // We still call setState to update the UI (like clear buttons or field styles)
    // but we won't disable the "Add" button anymore.
    if (mounted) setState(() {});
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  Future<void> _saveAccessPoint() async {
    final name = _nameController.text.trim();
    final latitude = double.tryParse(_latitudeController.text);
    final longitude = double.tryParse(_longitudeController.text);
    final altitude = double.tryParse(_altitudeController.text) ?? 0.0;

    if (name.isEmpty) {
      _showError('Please enter an Access Point name.');
      return;
    }

    if (latitude == null || latitude < -90 || latitude > 90) {
      _showError('Please enter a valid Latitude (-90 to 90).');
      return;
    }

    if (longitude == null || longitude < -180 || longitude > 180) {
      _showError('Please enter a valid Longitude (-180 to 180).');
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

    _refreshAccessPoints();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Access Point saved successfully.')),
      );
    }
  }

  bool _isSaveButtonEnabled() {
    // Now we only disable the button if we are currently capturing.
    // This makes manual input feel more responsive.
    return !_isCapturingLocation;
  }

  void _refreshAccessPoints() {
    setState(() {
      _accessPointsFuture = DatabaseService.instance.getAccessPoints();
    });
  }

  Future<void> _captureCurrentLocation() async {
    setState(() {
      _isCapturingLocation = true;
    });

    try {
      // Use a 5-second window of readings for a reliable location average
      final position = await GeolocatorService.instance.getAveragedPosition(
        duration: const Duration(seconds: 5)
      );
      _latitudeController.text = position.latitude.toString();
      _longitudeController.text = position.longitude.toString();
      _altitudeController.text = position.altitude.toString();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location captured and averaged over 5 seconds.')),
        );
      }
    } catch (e) {
      _showError("Failed to capture location: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isCapturingLocation = false;
        });
      }
    }
  }

  void _deleteAccessPoint(int id) {
    // We call the async deletion without awaiting to match the 'void Function(int)' signature
    _performDeletion(id);
  }

  Future<void> _performDeletion(int id) async {
    await DatabaseService.instance.removeAccessPoint(id);
    _refreshAccessPoints();
    
    // If the deleted AP was the selected one, clear selection
    if (SettingsService.instance.selectedAccessPoint?.id == id) {
      SettingsService.instance.selectedAccessPoint = null;
    }
  }

  void _selectAccessPoint(AccessPoint ap) {
    setState(() {
      SettingsService.instance.selectedAccessPoint = ap;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Selected: ${ap.name}')),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Access Point Name',
                        hintText: 'e.g. Sector 1 Tower',
                      ),
                    ),
                    const SizedBox(height: 16),
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
                    const SizedBox(height: 24),
                    const Text(
                      'Target Coordinates (Manual or Captured)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _latitudeController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(
                        labelText: 'Latitude',
                        hintText: 'e.g. 45.123456',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _longitudeController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(
                        labelText: 'Longitude',
                        hintText: 'e.g. -75.654321',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _altitudeController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Altitude (m)',
                        hintText: 'e.g. 15.0',
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isSaveButtonEnabled() ? _saveAccessPoint : null,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
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
