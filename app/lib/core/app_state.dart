import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'localization/app_strings.dart';
import 'models/app_config.dart';
import 'models/rework_site.dart';
import 'models/survey.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/device_service.dart';
import 'services/local_store.dart';
import 'services/location_service.dart';
import 'services/offline_dropdown_service.dart';
import 'services/remote_config_service.dart';
import 'services/sync_service.dart';

/// Root application state + service locator.
class AppState extends ChangeNotifier {
  late final ApiService api;
  late final DeviceService device;
  late final AuthService auth;
  late final RemoteConfigService config;
  late final LocationService location;
  late final LocalStore store;
  late final SyncService sync;
  late final OfflineDropdownService offlineDropdown;

  AppStrings? _strings;
  bool _ready = false;

  bool get ready => _ready;
  AppStrings get strings => _strings!;
  RadarBundle get bundle => config.bundle;
  AppConfig get appConfig => config.appConfig;
  List<SurveyPage> get forms => config.bundle.forms;

  AppState() {
    api = ApiService();
    device = DeviceService();
    auth = AuthService(api, device);
    config = RemoteConfigService(api);
    location = LocationService(device);
    store = LocalStore();
    sync = SyncService(api, store);
    offlineDropdown = OfflineDropdownService(api);
    // Retry uploading the outbox whenever the app comes back to the foreground.
    WidgetsBinding.instance.addObserver(_ResumeObserver(() => sync.syncNow()));
  }

  /// Loads local config so the login screen can render, then (if already logged
  /// in) pulls the latest survey JSON from the saved json_link.
  Future<void> bootstrap() async {
    // Keep the branded splash on screen for a beat. loadLocal() only reads a
    // bundled asset, so without this the splash would flash by in milliseconds.
    final minSplash = Future<void>.delayed(const Duration(milliseconds: 2200));
    await config.loadLocal();
    _rebuildStrings();
    await minSplash;
    _ready = true;
    notifyListeners();

    if (await auth.isLoggedIn()) {
      await refreshConfig();
      sync.start(); // always run — guarantees queued data uploads
    }
  }

  /// Downloads the survey JSON from the saved json_link and refreshes strings.
  /// Call this right after a successful login, and from pull-to-refresh.
  Future<void> refreshConfig() async {
    final link = await auth.jsonLink();
    if (link != null && link.isNotEmpty) {
      final changed = await config.fetchSurveyJson(link);
      if (changed) {
        // A new team/config was loaded — drop the previous team's cached
        // dropdown tree so stale options are never shown.
        await offlineDropdown.clear();
        // Endpoint URLs the JSON overrides (upload/summary/dropdown/jsonUpdate).
        api.applyJsonUrls(config.appConfig.apiUrls);
        // The freshly-fetched user JSON dictates the language, so adopt its
        // configured default rather than keeping the bundled 'en'.
        _rebuildStrings(forceLang: config.appConfig.language.defaultLang);
        notifyListeners();
      }
    }
    // Pre-warm the cascading-dropdown tree (cached to disk for offline use).
    offlineDropdown.ensureLoaded();
    sync.start(); // always run — guarantees queued data uploads
  }

  void _rebuildStrings({String? forceLang}) {
    final current =
        forceLang ?? _strings?.lang ?? config.appConfig.language.defaultLang;
    _strings = AppStrings(config.bundle, lang: current);
  }

  void setLanguage(String lang) {
    _strings?.setLanguage(lang);
    notifyListeners();
  }

  String t(String key) => _strings?.t(key) ?? key;

  /// Fetches the dashboard summary from the JSON-configured `summaryUrl`
  /// (falls back to the AppEnv default). Returns the raw list of summary
  /// sections the server sends — the dashboard renders exactly this, nothing
  /// else. Throws [ApiException] on a non-200 envelope.
  Future<List<dynamic>> fetchSummary() async {
    final envelope = await api.getJson(api.summaryUrl);
    final resp = ApiService.unwrap(envelope);
    if (resp is List) return resp;
    if (resp is Map && resp['summary'] is List) return resp['summary'] as List;
    return const [];
  }

  /// Fetches rework sites for the Tasks tab from the JSON-configured
  /// `reworkUrl` (rework_assign.php). Accepts the standard envelope or a raw
  /// array. Returns an empty list on any error.
  Future<List<ReworkSite>> fetchReworkSites() async {
    final data = await api.getDynamic(api.reworkUrl);
    dynamic list = data;
    if (data is Map) {
      list = data['response'] ??
          data['data'] ??
          data['reworkList'] ??
          data['sites'] ??
          data['reworkSites'];
    }
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => ReworkSite.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// The signed-in team/installer name saved at login (shown in the header).
  Future<String?> teamName() => auth.clientName();

  /// Clears the session and token.
  Future<void> logout() async {
    await offlineDropdown.clear();
    await auth.logout();
  }
}

/// Fires [onResume] each time the app returns to the foreground, so the offline
/// outbox is drained promptly whenever the installer reopens the app.
class _ResumeObserver extends WidgetsBindingObserver {
  final VoidCallback onResume;
  _ResumeObserver(this.onResume);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}
