import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/app_config.dart';
import '../models/survey.dart';
import 'api_service.dart';

/// Source that produced the currently-loaded config.
enum ConfigSource { bundledDefault, cache, network }

/// Loads, caches and refreshes the survey JSON.
///
/// Flow with your backend:
///   1. On startup [loadLocal] loads the last cached JSON (or the bundled
///      default) so the login screen has theme + strings to render.
///   2. After login, [fetchSurveyJson] downloads the real form JSON from the
///      `json_link` the login returned, merges it over the bundled defaults
///      (so geofencing / feature flags / UI strings survive even if the server
///      JSON only provides appConfig + appForms), and caches it.
class RemoteConfigService {
  final ApiService _api;
  RemoteConfigService(this._api);

  static const String _cacheFileName = 'survey_config.json';

  Map<String, dynamic> _baseJson = const {}; // bundled defaults (merge base)
  RadarBundle? _bundle;
  AppConfig? _appConfig;
  ConfigSource _source = ConfigSource.bundledDefault;

  RadarBundle get bundle => _bundle!;
  AppConfig get appConfig => _appConfig!;
  ConfigSource get source => _source;
  bool get isLoaded => _bundle != null;

  Future<File> _cacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _cacheFileName));
  }

  /// Loads a config to run on immediately (cache or bundled).
  Future<void> loadLocal() async {
    // Bundled defaults are always the merge base (they carry strings + geo +
    // feature flags that the server form JSON may not include).
    final rawBundled =
        await rootBundle.loadString('assets/config/default_config.json');
    _baseJson = jsonDecode(rawBundled) as Map<String, dynamic>;

    Map<String, dynamic>? json;
    try {
      final f = await _cacheFile();
      if (await f.exists()) {
        json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        _source = ConfigSource.cache;
      }
    } catch (_) {/* fall through to bundled */}

    _apply(json ?? _baseJson);
    if (json == null) _source = ConfigSource.bundledDefault;
  }

  /// Downloads the survey JSON from [jsonLink] (from login), merges + caches it.
  /// Returns true on success.
  Future<bool> fetchSurveyJson(String jsonLink) async {
    if (jsonLink.isEmpty) return false;
    try {
      final fetched = await _api.getJson(jsonLink);
      // Some deployments may wrap the JSON in the standard envelope.
      final Map<String, dynamic> surveyJson =
          fetched.containsKey('appConfig') || fetched.containsKey('appForms')
              ? fetched
              : (fetched['response'] is Map
                  ? Map<String, dynamic>.from(fetched['response'])
                  : fetched);

      final merged = _merge(_baseJson, surveyJson);
      _apply(merged);
      _source = ConfigSource.network;
      final f = await _cacheFile();
      await f.writeAsString(jsonEncode(merged));
      return true;
    } catch (_) {
      // Offline / server error: keep running on the local config.
      return false;
    }
  }

  /// Shallow-merges the fetched survey JSON over the bundled defaults so
  /// server-provided keys win, but locally-defined extensions (strings,
  /// featureConfig) survive when the server omits them.
  ///
  /// Geofencing and language are treated specially: they are driven STRICTLY by
  /// the user's JSON. Geofencing is OFF unless the JSON turns it on (a full
  /// `geoConfig` object, or the shorthand key `"geofencing": true`), so an
  /// installer whose JSON doesn't mention geofencing is never blocked. The
  /// active language likewise comes from the JSON's `languageConfig`/`language`.
  Map<String, dynamic> _merge(
      Map<String, dynamic> base, Map<String, dynamic> fetched) {
    final out = Map<String, dynamic>.from(base);

    final baseAc = Map<String, dynamic>.from(base['appConfig'] ?? {});
    final fetchedAc = fetched['appConfig'] is Map
        ? Map<String, dynamic>.from(fetched['appConfig'])
        : <String, dynamic>{};
    final mergedAc = {...baseAc, ...fetchedAc}; // fetched keys override

    // Geofencing: user JSON is the ONLY source of truth. Default = off.
    mergedAc['geoConfig'] = _resolveGeo(fetched, fetchedAc);

    // Language: honour a `language` shorthand or a full `languageConfig`.
    final lang = _resolveLanguage(fetched, fetchedAc);
    if (lang != null) mergedAc['languageConfig'] = lang;

    // Guidelines may live at the top level of the JSON or inside appConfig.
    if (fetched['guidelines'] != null && fetchedAc['guidelines'] == null) {
      mergedAc['guidelines'] = fetched['guidelines'];
    }

    out['appConfig'] = mergedAc;

    if (fetched['appForms'] is List) out['appForms'] = fetched['appForms'];
    if (fetched['strings'] is Map) out['strings'] = fetched['strings'];
    return out;
  }

  /// Resolves the geofence config from the user JSON only.
  /// Priority: full `geoConfig` object > shorthand `"geofencing": true` > OFF.
  Map<String, dynamic> _resolveGeo(
      Map<String, dynamic> root, Map<String, dynamic> appConfig) {
    if (appConfig['geoConfig'] is Map) {
      return Map<String, dynamic>.from(appConfig['geoConfig']);
    }
    if (root['geoConfig'] is Map) {
      return Map<String, dynamic>.from(root['geoConfig']);
    }
    final on = _asBool(root['geofencing']) ??
        _asBool(appConfig['geofencing']) ??
        _asBool(root['geoFencing']) ??
        _asBool(appConfig['geoFencing']);
    if (on == true) {
      // Enabled via the shorthand. Zones may be supplied alongside it; if none
      // are given the app simply has nothing to enforce against (never blocks).
      final zones = root['zones'] ?? appConfig['zones'] ?? const [];
      return {'active': 1, 'enforcement': 'block', 'zones': zones};
    }
    return const {'active': 0, 'zones': []};
  }

  /// Resolves the language config from the user JSON. Accepts a full
  /// `languageConfig` object or a `"language": "hi"` shorthand.
  Map<String, dynamic>? _resolveLanguage(
      Map<String, dynamic> root, Map<String, dynamic> appConfig) {
    if (appConfig['languageConfig'] is Map) {
      return Map<String, dynamic>.from(appConfig['languageConfig']);
    }
    if (root['languageConfig'] is Map) {
      return Map<String, dynamic>.from(root['languageConfig']);
    }
    final code = (root['language'] ?? appConfig['language']);
    if (code is String && code.trim().isNotEmpty) {
      return {'default': code.trim(), 'supported': [code.trim()]};
    }
    return null;
  }

  /// Interprets `true`/`1`/`"true"`/`"1"` as true, `false`/`0`/`"false"`/`"0"`
  /// as false, and anything else as null (key absent / unrecognised).
  static bool? _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v == 1;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == 'true' || s == '1' || s == 'yes' || s == 'on') return true;
      if (s == 'false' || s == '0' || s == 'no' || s == 'off') return false;
    }
    return null;
  }

  void _apply(Map<String, dynamic> json) {
    _bundle = RadarBundle.fromJson(json);
    _appConfig = AppConfig.fromJson(_bundle!.rawAppConfig);
  }
}
