import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_service.dart';
import 'device_service.dart';

/// Result of a successful login.
class LoginResult {
  final String token; // base64 credential used for Basic auth
  final String jsonLink; // URL of the survey JSON to download
  final String clientName;
  final String? splashImg;
  final String? logoImg;

  const LoginResult({
    required this.token,
    required this.jsonLink,
    required this.clientName,
    this.splashImg,
    this.logoImg,
  });

  factory LoginResult.fromResponse(Map<String, dynamic> r) => LoginResult(
        token: r['token']?.toString() ?? '',
        jsonLink: r['json_link']?.toString() ?? '',
        clientName: r['client_name']?.toString() ?? '',
        splashImg: r['splash_img']?.toString(),
        logoImg: r['logo_img']?.toString(),
      );
}

/// Handles username + password login against auth.php, sending the full device
/// profile so the backend can bind the device (one device per installer) and
/// save the hardware details. No OTP step — the device lock + admin device-change
/// approval are handled server-side.
class AuthService {
  final ApiService _api;
  final DeviceService _deviceService;
  // resetOnError: on some OEM keystores saved data becomes undecryptable
  // (BAD_DECRYPT). Reset the corrupt entry and return null instead of throwing.
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
  );

  static const _kToken = 'auth_token';
  static const _kJsonLink = 'json_link';
  static const _kClientName = 'client_name';

  AuthService(this._api, this._deviceService);

  /// Restores a saved token into the API client. Returns true if logged in.
  Future<bool> isLoggedIn() async {
    try {
      final t = await _storage
          .read(key: _kToken)
          .timeout(const Duration(seconds: 6));
      if (t != null && t.isNotEmpty) {
        _api.setToken(t);
        return true;
      }
    } catch (_) {
      // Secure storage can hang/throw on some OEM keystores (seen on certain
      // OnePlus builds). Never block startup — treat as logged out so the login
      // screen is reachable instead of an endless spinner.
    }
    return false;
  }

  Future<String?> jsonLink() => _storage.read(key: _kJsonLink);
  Future<String?> clientName() => _storage.read(key: _kClientName);

  /// The device profile that will be sent with login (for previewing/debug).
  Future<DeviceIdentity> deviceProfile() => _deviceService.read();

  /// Logs in with username + password. Sends the full device profile so the
  /// backend can enforce the one-device binding. Throws [ApiException] with the
  /// server message if credentials are wrong or the device is not authorised
  /// (e.g. the account is already bound to another phone).
  Future<LoginResult> login(String username, String password) async {
    final device = await _deviceService.read();
    final body = <String, dynamic>{
      'username': username,
      'password': password,
      ...device.toJson(), // imei(bindingId) + full device details
    };
    final envelope = await _api.postJson(_api.loginUrl, body);
    final response = ApiService.unwrap(envelope); // throws on non-200
    final result = LoginResult.fromResponse(Map<String, dynamic>.from(response));

    _api.setToken(result.token);
    await _storage.write(key: _kToken, value: result.token);
    await _storage.write(key: _kJsonLink, value: result.jsonLink);
    await _storage.write(key: _kClientName, value: result.clientName);
    return result;
  }

  Future<void> logout() async {
    _api.setToken(null);
    await _storage.deleteAll();
  }
}
