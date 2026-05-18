import 'dart:async';
import 'dart:convert';
import 'package:antenna_aligner/models/pointing_error.dart';
import 'package:antenna_aligner/services/settings_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

class BluetoothService {
  BluetoothService._internal();
  static final BluetoothService instance = BluetoothService._internal();

  fbp.BluetoothDevice? _connectedDevice;
  fbp.BluetoothCharacteristic? _writeCharacteristic;
  bool get isConnected => _connectedDevice != null && _writeCharacteristic != null;

  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);

  /// Scans for and connects to the Arduino Bluetooth module (typically HC-05/06 or ESP32)
  Future<void> connect() async {
    // 1. Check if Bluetooth is on
    if (await fbp.FlutterBluePlus.adapterState.first != fbp.BluetoothAdapterState.on) {
      return Future.error("Bluetooth is turned off");
    }

    // 2. Start scanning
    fbp.FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

    Completer<void> completer = Completer();

    var subscription = fbp.FlutterBluePlus.scanResults.listen((results) async {
      for (fbp.ScanResult r in results) {
        if (r.device.platformName.contains("Antenna") || r.device.platformName.contains("ESP32")) {
          fbp.FlutterBluePlus.stopScan();
          _connectedDevice = r.device;
          
          try {
            await _connectedDevice!.connect();
            // Prefixing with fbp. to avoid collision with this class name
            List<fbp.BluetoothService> services = await _connectedDevice!.discoverServices();
            
            // Look for a writable characteristic
            for (var service in services) {
              for (var characteristic in service.characteristics) {
                if (characteristic.properties.write) {
                  _writeCharacteristic = characteristic;
                  break;
                }
              }
              if (_writeCharacteristic != null) break;
            }
            if (!completer.isCompleted) completer.complete();
          } catch (e) {
            if (!completer.isCompleted) completer.completeError(e);
          }
          break;
        }
      }
    });

    try {
      await completer.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      fbp.FlutterBluePlus.stopScan();
      subscription.cancel();
      throw TimeoutException("Could not find Arduino device");
    } finally {
      subscription.cancel();
    }
  }

  Future<void> disconnect() async {
    await _connectedDevice?.disconnect();
    _connectedDevice = null;
    _writeCharacteristic = null;
  }

  /// Sends the pointing error to the Arduino in real-time.
  Future<void> sendPointingData(PointingError error) async {
    if (!isConnected) return;

    // Power Save Logic: Throttle data transmission if errors are small
    if (SettingsService.instance.powerSaveMode) {
      final totalError = error.deltaAzimuth.abs() + error.deltaElevation.abs();
      final timeSinceLast = DateTime.now().difference(_lastSent).inMilliseconds;
      
      if (totalError < 0.5 && timeSinceLast < 2000) {
        return;
      }
    }

    final packet = {
      "pan_error": error.deltaAzimuth.toStringAsFixed(2),
      "tilt_error": error.deltaElevation.toStringAsFixed(2),
      "timestamp": DateTime.now().millisecondsSinceEpoch,
    };

    final jsonString = jsonEncode(packet);
    
    try {
      await _writeCharacteristic!.write(utf8.encode("$jsonString\n"), withoutResponse: true);
      _lastSent = DateTime.now();
      // ignore: avoid_print
      print("BT_TX SUCCESS: $jsonString");
    } catch (e) {
      // ignore: avoid_print
      print("BT_TX FAILED: $e");
    }
  }
}
