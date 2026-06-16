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
  String? get connectedDeviceName => _connectedDevice?.platformName ?? _connectedDevice?.remoteId.str;

  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isConnecting = false;

  final StreamController<List<fbp.ScanResult>> _scanResultsController = StreamController<List<fbp.ScanResult>>.broadcast();
  Stream<List<fbp.ScanResult>> get scanResults => _scanResultsController.stream;

  final StreamController<bool> _connectionStateController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  Future<void> startScan() async {
    if (await fbp.FlutterBluePlus.adapterState.first != fbp.BluetoothAdapterState.on) {
      return Future.error("Bluetooth is turned off");
    }
    
    fbp.FlutterBluePlus.scanResults.listen((results) {
      _scanResultsController.add(results);
    });

    await fbp.FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
  }

  Future<void> stopScan() async {
    await fbp.FlutterBluePlus.stopScan();
  }

  /// Connects to a specific device selected by the user
  Future<void> connectToDevice(fbp.BluetoothDevice device) async {
    if (_isConnecting) return;
    _isConnecting = true;

    try {
      await stopScan();
      
      // Disconnect existing if any
      await disconnect();

      print("BT: Connecting to ${device.platformName}...");
      await device.connect(timeout: const Duration(seconds: 10));
      
      await _setupDevice(device);
      _connectionStateController.add(true);
    } catch (e) {
      print("BT: Connection failed: $e");
      _connectionStateController.add(false);
      rethrow;
    } finally {
      _isConnecting = false;
    }
  }

  /// Original connect method modified to auto-reconnect to last known if possible, 
  /// or just do nothing if no device is specified.
  Future<void> connect() async {
    // For now, if called without arguments, we don't know which device to pick 
    // unless we implement persistence.
    print("BT: connect() called without device. Use connectToDevice() for manual selection.");
  }

  Future<void> _setupDevice(fbp.BluetoothDevice device) async {
    print("BT: Discovering services for ${device.platformName}...");
    List<fbp.BluetoothService> services = await device.discoverServices();
    
    for (var service in services) {
      for (var characteristic in service.characteristics) {
        if (characteristic.properties.write || characteristic.properties.writeWithoutResponse) {
          _writeCharacteristic = characteristic;
          _connectedDevice = device;
          print("BT: Found writable characteristic: ${characteristic.uuid}");
          return;
        }
      }
    }
    throw Exception("No writable characteristic found on device");
  }

  Future<void> disconnect() async {
    await _connectedDevice?.disconnect();
    _connectedDevice = null;
    _writeCharacteristic = null;
    _connectionStateController.add(false);
  }

  Future<void> sendPointingData(PointingError error) async {
    if (!isConnected) return;

    if (SettingsService.instance.powerSaveMode) {
      final totalError = error.deltaAzimuth.abs() + error.deltaElevation.abs();
      final timeSinceLast = DateTime.now().difference(_lastSent).inMilliseconds;
      
      if (totalError < 0.5 && timeSinceLast < 2000) {
        return;
      }
    }

    final packet = {
      "pan_error": error.deltaAzimuth,
      "tilt_error": error.deltaElevation,
    };

    final jsonString = jsonEncode(packet);
    
    try {
      await _writeCharacteristic!.write(
        utf8.encode("$jsonString\n"), 
        withoutResponse: _writeCharacteristic!.properties.writeWithoutResponse
      );
      _lastSent = DateTime.now();
      print("BT_TX SUCCESS: $jsonString");
    } catch (e) {
      print("BT_TX FAILED: $e");
      if (e.toString().contains("disconnected")) {
        _connectedDevice = null;
        _writeCharacteristic = null;
        _connectionStateController.add(false);
      }
    }
  }
}
