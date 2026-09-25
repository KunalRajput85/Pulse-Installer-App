import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:safe_device/safe_device.dart';
import 'package:uuid/uuid.dart';

/// Full device profile captured at login for the one-device binding + audit.
///
/// NOTE ON IMEI: Android 10+ (API 29) blocks third-party apps from reading the
/// real IMEI/serial. So [bindingId] is a stable per-device/per-install key used
/// as the "one device" lock (sent to the backend as `imei` for compatibility).
/// [realImei] stays null on modern Android; everything else below is readable.
class DeviceIdentity {
  final String bindingId; // stable lock key (sent as `imei`)
  final String? realImei; // null on Android 10+ (OS restriction)
  final String manufacturer;
  final String brand;
  final String model;
  final String device;
  final String product;
  final String hardware;
  final String fingerprint;
  final String androidVersion;
  final int sdkInt;
  final String appVersion;
  final bool isRealDevice; // false => emulator
  final bool isRooted;
  final bool isDevelopmentModeEnabled;

  const DeviceIdentity({
    required this.bindingId,
    required this.realImei,
    required this.manufacturer,
    required this.brand,
    required this.model,
    required this.device,
    required this.product,
    required this.hardware,
    required this.fingerprint,
    required this.androidVersion,
    required this.sdkInt,
    required this.appVersion,
    required this.isRealDevice,
    required this.isRooted,
    required this.isDevelopmentModeEnabled,
  });

  bool get isCompromised => isRooted || !isRealDevice;

  /// Sent with the login request. `imei` carries the binding key for the
  /// existing device-lock logic; the rest are the full device details to save.
  Map<String, dynamic> toJson() => {
        // one-device binding key (server compares this to the bound device)
        'imei': bindingId,
        'device_uid': bindingId,
        'real_imei': realImei, // null on Android 10+
        // device identity / "which company phone"
        'manufacturer': manufacturer,
        'brand': brand,
        'model': model,
        'device': device,
        'product': product,
        'hardware': hardware,
        'fingerprint': fingerprint,
        'os': 'Android',
        'android_version': androidVersion,
        'sdk_int': sdkInt,
        'app_version': appVersion,
        // integrity signals
        'is_physical_device': isRealDevice,
        'is_rooted': isRooted,
        'dev_mode': isDevelopmentModeEnabled,
        // legacy keys kept for backend compatibility
        'deviceModel': model,
        'androidVersion': androidVersion,
        'appVersion': appVersion,
        'isRooted': isRooted,
      };
}

class DeviceService {
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
  );
  static const String _kBindingId = 'device_binding_id';

  /// Returns a stable device binding id, generating and persisting one on first
  /// launch. This is the "one device" lock key. It stays the same across app
  /// restarts on the same device; installing on a different phone (or a fresh
  /// reinstall) produces a new id — which is exactly when the admin must
  /// approve the device change.
  Future<String> _getOrCreateBindingId() async {
    String? id;
    try {
      id = await _storage.read(key: _kBindingId);
    } catch (_) {
      // Corrupt/undecryptable keystore entry (BAD_DECRYPT on some OnePlus/OEM
      // builds). Wipe and regenerate so login can proceed. A new binding id
      // means the admin must re-approve this device.
      try {
        await _storage.deleteAll();
      } catch (_) {/* ignore */}
      id = null;
    }
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      try {
        await _storage.write(key: _kBindingId, value: id);
      } catch (_) {/* still return a usable id for this session */}
    }
    return id;
  }

  Future<DeviceIdentity> read() async {
    final pkg = await PackageInfo.fromPlatform();

    String manufacturer = 'unknown',
        brand = 'unknown',
        model = 'unknown',
        device = 'unknown',
        product = 'unknown',
        hardware = 'unknown',
        fingerprint = 'unknown',
        release = 'unknown';
    int sdkInt = 0;
    bool physical = true;

    try {
      final a = await _deviceInfo.androidInfo;
      manufacturer = a.manufacturer;
      brand = a.brand;
      model = a.model;
      device = a.device;
      product = a.product;
      hardware = a.hardware;
      fingerprint = a.fingerprint;
      release = a.version.release;
      sdkInt = a.version.sdkInt;
      physical = a.isPhysicalDevice;
    } catch (_) {/* non-Android / test env */}

    bool rooted = false, devMode = false;
    try {
      rooted = await SafeDevice.isJailBroken;
      physical = physical && await SafeDevice.isRealDevice;
      devMode = await SafeDevice.isDevelopmentModeEnable;
    } catch (_) {/* plugin unavailable */}

    return DeviceIdentity(
      bindingId: await _getOrCreateBindingId(),
      realImei: null, // not readable on Android 10+ (OS restriction)
      manufacturer: manufacturer,
      brand: brand,
      model: model,
      device: device,
      product: product,
      hardware: hardware,
      fingerprint: fingerprint,
      androidVersion: 'Android $release',
      sdkInt: sdkInt,
      appVersion: '${pkg.version}+${pkg.buildNumber}',
      isRealDevice: physical,
      isRooted: rooted,
      isDevelopmentModeEnabled: devMode,
    );
  }
}
