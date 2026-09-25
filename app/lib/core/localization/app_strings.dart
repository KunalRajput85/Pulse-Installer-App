import '../models/survey.dart';

/// Resolves UI strings from the JSON config's `strings` block for the active
/// language. Because the strings live in the config, adding a language or
/// changing wording is a server-side JSON edit — no app rebuild.
class AppStrings {
  final Map<String, Map<String, String>> _all;
  String _lang;
  final String _fallback;

  // NOTE: the active language is kept as requested even if the `strings` block
  // has no entry for it. This is deliberate: form labels/titles are localized
  // per-control (Control.labelFor), so the active language must reflect the
  // JSON's languageConfig regardless of whether the UI-chrome `strings` block
  // ships that language. Chrome strings fall back per-key in [t].
  AppStrings(RadarBundle bundle, {required String lang, String fallback = 'en'})
      : _all = bundle.strings,
        _lang = lang.isNotEmpty ? lang : fallback,
        _fallback = fallback;

  String get lang => _lang;

  void setLanguage(String lang) {
    if (lang.isNotEmpty) _lang = lang;
  }

  /// Returns the string for [key] in the active language, falling back to the
  /// default language, then to the key itself.
  String t(String key) {
    return _all[_lang]?[key] ?? _all[_fallback]?[key] ?? key;
  }
}
