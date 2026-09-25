/// Boot/environment constants — the SINGLE place to define every backend URL.
///
/// Named [AppEnv] (not AppConfig) to avoid clashing with the JSON-driven
/// `AppConfig` model in core/models/app_config.dart.
///
/// ── How to set the URLs (three ways, in priority order) ────────────────────
/// 1. Per-installer JSON (`apiUrls` block) — overrides the upload/summary/
///    dropdown/jsonUpdate endpoints at runtime, per user. See ApiUrls in
///    core/models/app_config.dart. (login/OTP can't come from here — they run
///    BEFORE the JSON is fetched.)
/// 2. Build-time --dart-define — override any single endpoint without editing
///    code, e.g.:
///       flutter build apk \
///         --dart-define=API_BASE_URL=https://your.server/mobile_services/api \
///         --dart-define=SUMMARY_PATH=/summary.php \
///         --dart-define=SEND_OTP_PATH=/promoter_verification.php?type=1
/// 3. The defaults below — edit these to match your server once and rebuild.
///
/// A "path" (starts with `/`) is resolved against [apiBaseUrl]. A full URL
/// (starts with `http`) is used as-is, so you can point one endpoint at a
/// different host if you ever need to.
class AppEnv {
  AppEnv._();

  /// Base URL of the backend API (your own mobile_services system).
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.rmartsindia.com/mobile_services/api',
  );

  // ── Endpoint paths (relative to [apiBaseUrl], or a full http URL) ──────────
  // Each is overridable at build time via the named --dart-define key.

  /// Login (username + password + device profile). POST.
  static const String loginPath =
      String.fromEnvironment('LOGIN_PATH', defaultValue: '/auth.php');

  /// Send OTP (first device registration / device-change approval). POST.
  static const String sendOtpPath = String.fromEnvironment('SEND_OTP_PATH',
      defaultValue: '/promoter_verification.php?type=1');

  /// Validate OTP. POST.
  static const String validateOtpPath = String.fromEnvironment(
      'VALIDATE_OTP_PATH',
      defaultValue: '/promoter_verification.php?type=2');

  /// Upload captured survey/site data (JSON array). POST.
  static const String dataUploadPath =
      String.fromEnvironment('DATA_UPLOAD_PATH', defaultValue: '/data.php');

  /// Upload captured photos (multipart, one call per image). POST.
  static const String fileUploadPath =
      String.fromEnvironment('FILE_UPLOAD_PATH', defaultValue: '/file.php');

  /// Home/dashboard bootstrap data (team, assignment, counters). GET/POST.
  static const String homeScreenPath = String.fromEnvironment(
      'HOME_SCREEN_PATH',
      defaultValue: '/home_screen_data.php');

  /// Summary dashboard (approved/pending/rejected KPIs, recent sites). GET/POST.
  static const String summaryPath =
      String.fromEnvironment('SUMMARY_PATH', defaultValue: '/summary.php');

  /// Offline dropdown master data (states/districts/villages, etc.). GET/POST.
  static const String offlineDropdownPath = String.fromEnvironment(
      'OFFLINE_DROPDOWN_PATH',
      defaultValue: '/get_offline_dropdown_options.php');

  /// Report/refresh the survey-config (json_link) version the device is on. POST.
  static const String jsonUpdatePath = String.fromEnvironment(
      'JSON_UPDATE_PATH',
      defaultValue: '/jsonUpdate.php');

  /// Rework sites assigned back to the installer (Tasks tab). GET.
  static const String reworkPath =
      String.fromEnvironment('REWORK_PATH', defaultValue: '/rework_assign.php');

  /// Canonical endpoint keys used by [ApiService] and the JSON `apiUrls` block.
  static const List<String> endpointKeys = [
    'login',
    'sendOtp',
    'validateOtp',
    'dataUpload',
    'fileUpload',
    'homeScreen',
    'summary',
    'offlineDropdown',
    'jsonUpdate',
    'rework',
  ];

  /// The default path for each canonical endpoint key (before any JSON override).
  static const Map<String, String> defaultEndpoints = {
    'login': loginPath,
    'sendOtp': sendOtpPath,
    'validateOtp': validateOtpPath,
    'dataUpload': dataUploadPath,
    'fileUpload': fileUploadPath,
    'homeScreen': homeScreenPath,
    'summary': summaryPath,
    'offlineDropdown': offlineDropdownPath,
    'jsonUpdate': jsonUpdatePath,
    'rework': reworkPath,
  };

  /// Turns a path or full URL into an absolute URL against [apiBaseUrl].
  static String resolve(String pathOrUrl) {
    if (pathOrUrl.startsWith('http')) return pathOrUrl;
    final base = apiBaseUrl.endsWith('/')
        ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
        : apiBaseUrl;
    final path = pathOrUrl.startsWith('/') ? pathOrUrl : '/$pathOrUrl';
    return '$base$path';
  }

  /// Maximum acceptable GPS horizontal accuracy in metres (fallback; the loaded
  /// config can override via featureConfig.gpsAuthenticity.maxAccuracyMeters).
  static const double maxGpsAccuracyMeters = 30.0;

  /// How often the background sync worker flushes the offline outbox.
  static const Duration syncInterval = Duration(seconds: 30);

  /// JPEG quality (0-100) used when compressing captured photos before queueing.
  static const int photoJpegQuality = 70;
}
