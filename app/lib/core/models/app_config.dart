import 'dart:ui';

/// Parsed representation of the Radar JSON `appConfig` block plus the RM Pulse
/// additions (`geoConfig`, `featureConfig`). Everything the app's appearance
/// and rules depend on is derived from here, so changing the server JSON
/// changes the app without a rebuild.
class AppConfig {
  final int id;
  final int version;
  final String relDate;
  final ThemeConfig theme;
  final LogoConfig logo;
  final FontsConfig fonts;
  final Map<String, HeaderButton> buttons;
  final ApiUrls apiUrls;
  final FeatureConfig features;
  final GeoConfig geo;
  final LanguageConfig language;
  final Guidelines guidelines;

  const AppConfig({
    required this.id,
    required this.version,
    required this.relDate,
    required this.theme,
    required this.logo,
    required this.fonts,
    required this.buttons,
    required this.apiUrls,
    required this.features,
    required this.geo,
    required this.language,
    required this.guidelines,
  });

  factory AppConfig.fromJson(Map<String, dynamic> j) {
    final buttons = <String, HeaderButton>{};
    (j['buttons'] as Map?)?.forEach((k, v) {
      buttons[k] = HeaderButton.fromJson(Map<String, dynamic>.from(v));
    });
    return AppConfig(
      id: (j['id'] as num?)?.toInt() ?? 0,
      version: (j['version'] as num?)?.toInt() ?? 1,
      relDate: j['relDate'] ?? '',
      theme: ThemeConfig.fromJson(Map<String, dynamic>.from(j['themeConfig'] ?? {})),
      logo: LogoConfig.fromJson(Map<String, dynamic>.from(j['logoConfig'] ?? {})),
      fonts: FontsConfig.fromJson(Map<String, dynamic>.from(j['fontsConfig'] ?? {})),
      buttons: buttons,
      apiUrls: ApiUrls.fromJson(Map<String, dynamic>.from(j['apiUrls'] ?? {})),
      features: FeatureConfig.fromJson(Map<String, dynamic>.from(j['featureConfig'] ?? {})),
      geo: GeoConfig.fromJson(Map<String, dynamic>.from(j['geoConfig'] ?? {})),
      language: LanguageConfig.fromJson(Map<String, dynamic>.from(j['languageConfig'] ?? {})),
      guidelines: Guidelines.fromJson(j['guidelines']),
    );
  }
}

Color _hex(String? s, Color fallback) {
  if (s == null || s.isEmpty) return fallback;
  var h = s.replaceAll('#', '').trim();
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(v);
}

class ThemeConfig {
  final Color formBackground;
  final Color formText;
  final Color formSubtext;
  final Color headerBackground;
  final Color headerText;
  final Color accent;
  final Color danger;

  const ThemeConfig({
    required this.formBackground,
    required this.formText,
    required this.formSubtext,
    required this.headerBackground,
    required this.headerText,
    required this.accent,
    required this.danger,
  });

  factory ThemeConfig.fromJson(Map<String, dynamic> j) => ThemeConfig(
        formBackground: _hex(j['formBackgroundColor'], const Color(0xFFF5F7FA)),
        formText: _hex(j['formTextColor'], const Color(0xFF0D3D6B)),
        formSubtext: _hex(j['formSubtextColor'], const Color(0xFF5A6B7B)),
        headerBackground: _hex(j['headerBackgroundColor'], const Color(0xFF1B5E9B)),
        headerText: _hex(j['headerTextColor'], const Color(0xFFFFFFFF)),
        accent: _hex(j['accentColor'], const Color(0xFF00A878)),
        danger: _hex(j['dangerColor'], const Color(0xFFD64545)),
      );
}

class LogoConfig {
  final String splashScreenUrl;
  final String clientLogoUrl;
  final String companyLogoUrl;

  const LogoConfig({
    required this.splashScreenUrl,
    required this.clientLogoUrl,
    required this.companyLogoUrl,
  });

  factory LogoConfig.fromJson(Map<String, dynamic> j) => LogoConfig(
        splashScreenUrl: j['splashScreenUrl'] ?? '',
        clientLogoUrl: j['clientLogoUrl'] ?? '',
        companyLogoUrl: j['companyLogoUrl'] ?? '',
      );
}

class FontsConfig {
  final double fontSize;
  final String fontStyle;
  final double formTextFontSize;
  final String formTextFontStyle;
  final double formSubtextFontSize;
  final String formSubtextFontStyle;

  const FontsConfig({
    required this.fontSize,
    required this.fontStyle,
    required this.formTextFontSize,
    required this.formTextFontStyle,
    required this.formSubtextFontSize,
    required this.formSubtextFontStyle,
  });

  static double _px(String? s, double fallback) {
    if (s == null) return fallback;
    final v = double.tryParse(s.replaceAll('px', '').trim());
    return v ?? fallback;
  }

  factory FontsConfig.fromJson(Map<String, dynamic> j) => FontsConfig(
        fontSize: _px(j['fontSize'], 16),
        fontStyle: j['fontStyle'] ?? 'Roboto',
        formTextFontSize: _px(j['formTextFontSize'], 18),
        formTextFontStyle: j['formTextFontStyle'] ?? 'Roboto',
        formSubtextFontSize: _px(j['formSubtextFontSize'], 14),
        formSubtextFontStyle: j['formSubtextFontStyle'] ?? 'Roboto',
      );
}

class HeaderButton {
  final String label;
  final bool hidden;

  const HeaderButton({required this.label, required this.hidden});

  factory HeaderButton.fromJson(Map<String, dynamic> j) => HeaderButton(
        label: j['label'] ?? '',
        hidden: (j['hide'] as num?)?.toInt() == 1,
      );
}

/// Per-installer endpoint overrides supplied by the JSON `apiUrls` block. Each
/// canonical endpoint key (see [AppEnv.endpointKeys]) may be given as a path or
/// a full URL; anything omitted falls back to the [AppEnv] default. Both the RM
/// Pulse names (`dataUploadUrl`, `fileUploadUrl`, `summaryUrl`, …) and the legacy
/// Radar names (`surveyUploadUrl`, `imageUploadUrl`, `statsUrl`) are accepted.
class ApiUrls {
  /// Canonical endpoint key -> path/URL, only for keys the JSON actually set.
  final Map<String, String> overrides;

  const ApiUrls(this.overrides);

  /// Returns the override for [key] (canonical name) or null if not set.
  String? operator [](String key) {
    final v = overrides[key];
    return (v != null && v.trim().isNotEmpty) ? v.trim() : null;
  }

  factory ApiUrls.fromJson(Map<String, dynamic> j) {
    final m = <String, String>{};
    void take(String canonical, List<String> aliases) {
      for (final a in aliases) {
        final v = j[a];
        if (v is String && v.trim().isNotEmpty) {
          m[canonical] = v.trim();
          return;
        }
      }
    }

    take('login', ['loginUrl', 'login']);
    take('sendOtp', ['sendOtpUrl', 'sendOtp']);
    take('validateOtp', ['validateOtpUrl', 'validateOtp']);
    take('dataUpload', ['dataUploadUrl', 'surveyUploadUrl', 'dataUpload']);
    take('fileUpload', ['fileUploadUrl', 'imageUploadUrl', 'fileUpload']);
    take('homeScreen', ['homeScreenUrl', 'homeScreen']);
    take('summary', ['summaryUrl', 'statsUrl', 'summary']);
    take('offlineDropdown', ['offlineDropdownUrl', 'offlineDropdown']);
    take('jsonUpdate', ['jsonUpdateUrl', 'jsonUpdate']);
    take('rework', ['reworkUrl', 'reworkAssignUrl', 'rework']);
    return ApiUrls(m);
  }
}

/// Feature flags — each is a simple on/off with optional parameters.
class FeatureConfig {
  final bool liveCameraOnly;
  final bool offlineSync;
  final bool deviceBinding;
  final bool gpsAuthenticity;
  final double maxAccuracyMeters;
  final bool blockMockLocation;
  final bool blockRootedDevice;

  const FeatureConfig({
    required this.liveCameraOnly,
    required this.offlineSync,
    required this.deviceBinding,
    required this.gpsAuthenticity,
    required this.maxAccuracyMeters,
    required this.blockMockLocation,
    required this.blockRootedDevice,
  });

  static bool _on(dynamic node) {
    if (node is Map) return (node['active'] as num?)?.toInt() == 1;
    return false;
  }

  factory FeatureConfig.fromJson(Map<String, dynamic> j) {
    final gps = Map<String, dynamic>.from(j['gpsAuthenticity'] ?? {});
    return FeatureConfig(
      liveCameraOnly: _on(j['liveCameraOnly']),
      offlineSync: _on(j['offlineSync']),
      deviceBinding: _on(j['deviceBinding']),
      gpsAuthenticity: _on(j['gpsAuthenticity']),
      maxAccuracyMeters: (gps['maxAccuracyMeters'] as num?)?.toDouble() ?? 30,
      blockMockLocation: (gps['blockMockLocation'] as num?)?.toInt() == 1,
      blockRootedDevice: (gps['blockRootedDevice'] as num?)?.toInt() == 1,
    );
  }
}

/// Geofencing configuration (RM Pulse). Everything here is JSON-controllable:
/// the global on/off, the enforcement mode, the default radius/limit, the
/// periodic tagging interval and the list of zones (each individually
/// active/inactive with its own radius limit).
class GeoConfig {
  final bool active;
  final String enforcement; // "block" | "warn" | "off"
  final double defaultRadiusMeters;
  final int periodicTaggingSeconds;
  final bool trackDistance;
  final List<GeoZone> zones;

  const GeoConfig({
    required this.active,
    required this.enforcement,
    required this.defaultRadiusMeters,
    required this.periodicTaggingSeconds,
    required this.trackDistance,
    required this.zones,
  });

  bool get isBlocking => active && enforcement == 'block';

  List<GeoZone> get activeZones => zones.where((z) => z.active).toList();

  factory GeoConfig.fromJson(Map<String, dynamic> j) => GeoConfig(
        active: (j['active'] as num?)?.toInt() == 1,
        enforcement: j['enforcement'] ?? 'block',
        defaultRadiusMeters: (j['defaultRadiusMeters'] as num?)?.toDouble() ?? 250,
        periodicTaggingSeconds: (j['periodicTaggingSeconds'] as num?)?.toInt() ?? 60,
        trackDistance: (j['trackDistance'] as num?)?.toInt() == 1,
        zones: (j['zones'] as List? ?? [])
            .map((z) => GeoZone.fromJson(Map<String, dynamic>.from(z)))
            .toList(),
      );
}

class GeoZone {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final double radiusMeters;
  final bool active;

  const GeoZone({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.radiusMeters,
    required this.active,
  });

  factory GeoZone.fromJson(Map<String, dynamic> j) => GeoZone(
        id: j['id'].toString(),
        name: j['name'] ?? '',
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        radiusMeters: (j['radiusMeters'] as num?)?.toDouble() ?? 250,
        active: (j['active'] as num?)?.toInt() == 1,
      );
}

class LanguageConfig {
  final String defaultLang;
  final List<String> supported;

  const LanguageConfig({required this.defaultLang, required this.supported});

  factory LanguageConfig.fromJson(Map<String, dynamic> j) => LanguageConfig(
        defaultLang: j['default'] ?? 'en',
        supported: (j['supported'] as List?)?.cast<String>() ?? const ['en'],
      );
}

/// Installation guidelines shown in the home popup — fully JSON-driven and
/// multilingual. Accepts three shapes in the JSON `guidelines` key:
///   A) a plain list:            ["step 1", "step 2", ...]
///   B) per-item translations:   [{"en":"...","hi":"..."}, {...}, ...]
///   C) per-language lists:       {"en":["..."], "hi":["..."]}
/// A plain list is stored under '*' and shown for every language.
class Guidelines {
  /// language code -> ordered list of guideline lines.
  final Map<String, List<String>> byLang;

  const Guidelines(this.byLang);

  bool get isEmpty => byLang.isEmpty || byLang.values.every((l) => l.isEmpty);

  /// Best list for [lang]: exact language -> language-agnostic '*' -> English
  /// -> first non-empty list available.
  List<String> forLang(String lang) {
    final exact = byLang[lang];
    if (exact != null && exact.isNotEmpty) return exact;
    final star = byLang['*'];
    if (star != null && star.isNotEmpty) return star;
    final en = byLang['en'];
    if (en != null && en.isNotEmpty) return en;
    for (final l in byLang.values) {
      if (l.isNotEmpty) return l;
    }
    return const [];
  }

  factory Guidelines.fromJson(dynamic node) {
    final out = <String, List<String>>{};

    // Shape C: { "en": [...], "hi": [...] }
    if (node is Map) {
      node.forEach((lang, list) {
        if (list is List) {
          out[lang.toString()] =
              list.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
        }
      });
      return Guidelines(out);
    }

    // Shapes A/B: a list of strings and/or {lang: text} maps.
    if (node is List) {
      for (final item in node) {
        if (item is String) {
          (out['*'] ??= <String>[]).add(item);
        } else if (item is Map) {
          item.forEach((lang, text) {
            (out[lang.toString()] ??= <String>[]).add(text.toString());
          });
        }
      }
    }
    return Guidelines(out);
  }
}
