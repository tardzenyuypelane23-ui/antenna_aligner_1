import 'package:antenna_aligner/services/bluetooth_service.dart';
import 'package:antenna_aligner/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isScanning = false;

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;
    
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Visuals & Performance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          SwitchListTile(
            title: const Text('Use AR Visuals'),
            subtitle: const Text('Render alignment markers using AR mode when available.'),
            value: settings.useArVisuals,
            onChanged: (value) => setState(() => settings.useArVisuals = value),
          ),
          SwitchListTile(
            title: const Text('Power Save Mode'),
            subtitle: const Text('Reduce update frequency when alignment is near perfect.'),
            value: settings.powerSaveMode,
            onChanged: (value) => setState(() => settings.powerSaveMode = value),
          ),
          
          const Divider(height: 32),
          const Text('Bluetooth Configuration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          SwitchListTile(
            title: const Text('Enable Bluetooth'),
            subtitle: const Text('Allow the app to connect to hardware for real-time error output.'),
            value: settings.enableBluetooth,
            onChanged: (value) {
              setState(() {
                settings.enableBluetooth = value;
                if (!value) {
                  BluetoothService.instance.disconnect();
                }
              });
            },
          ),
          
          if (settings.enableBluetooth) ...[
            _buildBluetoothStatus(),
            const SizedBox(height: 16),
            _buildScannerSection(),
          ],
        ],
      ),
    );
  }

  Widget _buildBluetoothStatus() {
    return StreamBuilder<bool>(
      stream: BluetoothService.instance.connectionStateStream,
      initialData: BluetoothService.instance.isConnected,
      builder: (context, snapshot) {
        final isConnected = snapshot.data ?? false;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isConnected ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isConnected ? Colors.green : Colors.red),
          ),
          child: Row(
            children: [
              Icon(
                isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                color: isConnected ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isConnected ? 'Status: Connected' : 'Status: Disconnected',
                      style: TextStyle(fontWeight: FontWeight.bold, color: isConnected ? Colors.green : Colors.red),
                    ),
                    if (isConnected)
                      Text('Device: ${BluetoothService.instance.connectedDeviceName}', style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              if (isConnected)
                TextButton(
                  onPressed: () => BluetoothService.instance.disconnect(),
                  child: const Text('Disconnect', style: TextStyle(color: Colors.red)),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildScannerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Available Devices', style: TextStyle(fontWeight: FontWeight.w500)),
            if (_isScanning)
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            else
              TextButton.icon(
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Scan'),
                onPressed: _startScan,
              ),
          ],
        ),
        Container(
          height: 250,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: StreamBuilder<List<fbp.ScanResult>>(
            stream: BluetoothService.instance.scanResults,
            builder: (context, snapshot) {
              final results = snapshot.data ?? [];
              if (results.isEmpty) {
                return const Center(child: Text('No devices found', style: TextStyle(color: Colors.grey)));
              }
              return ListView.builder(
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final r = results[index];
                  final name = r.device.platformName.isNotEmpty ? r.device.platformName : (r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : 'Unknown Device');
                  return ListTile(
                    leading: const Icon(Icons.bluetooth),
                    title: Text(name),
                    subtitle: Text(r.device.remoteId.str),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _connectToDevice(r.device),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _startScan() async {
    setState(() => _isScanning = true);
    try {
      await BluetoothService.instance.startScan();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scan Error: $e')));
      }
    }
    // Scan times out after 15 seconds in BluetoothService
    await Future.delayed(const Duration(seconds: 15));
    if (mounted) setState(() => _isScanning = false);
  }

  Future<void> _connectToDevice(fbp.BluetoothDevice device) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await BluetoothService.instance.connectToDevice(device);
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connected Successfully!')));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Connection Failed: $e')));
      }
    }
  }
}
