import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

class DeviceService {
  static final DeviceService instance = DeviceService._internal();
  factory DeviceService() => instance;
  DeviceService._internal();

  String? _deviceModel;
  String? get cachedModel => _deviceModel;

  Future<String> getDeviceModel() async {
    if (_deviceModel != null) return _deviceModel!;

    final deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        _deviceModel = '${androidInfo.manufacturer} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _deviceModel = iosInfo.name;
      } else {
        _deviceModel = 'Unknown Device';
      }
    } catch (e) {
      _deviceModel = 'Unknown Device';
    }

    return _deviceModel!;
  }
}
