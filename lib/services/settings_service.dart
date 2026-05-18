import 'package:antenna_aligner/models/access_point.dart';

class SettingsService {
  SettingsService._internal();
  static final SettingsService instance = SettingsService._internal();

  bool powerSaveMode = false;
  bool useArVisuals = false;
  bool enableBluetooth = false;
  
  AccessPoint? selectedAccessPoint;
}
