import 'package:antenna_aligner/services/settings_service.dart';
import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;
    
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('Use AR Visuals'),
            subtitle: const Text('Render alignment markers using AR mode when available.'),
            value: settings.useArVisuals,
            onChanged: (value) => setState(() => settings.useArVisuals = value),
          ),
          SwitchListTile(
            title: const Text('Enable Bluetooth'),
            subtitle: const Text('Allow the app to connect to equipment over Bluetooth.'),
            value: settings.enableBluetooth,
            onChanged: (value) => setState(() => settings.enableBluetooth = value),
          ),
          SwitchListTile(
            title: const Text('Power Save Mode'),
            subtitle: const Text('Reduce update frequency when alignment is near perfect.'),
            value: settings.powerSaveMode,
            onChanged: (value) => setState(() => settings.powerSaveMode = value),
          ),
        ],
      ),
    );
  }
}
