/// Radar survey form models: pages -> controls, with validations and skip
/// logic. Mirrors "Part 2: Survey forms" of the Radar documentation.
library;

/// Control types (`optype`) from the Radar spec. Values that are planned for a
/// later phase are still enumerated so JSON referencing them parses cleanly;
/// the renderer decides which are interactive vs. shown as "coming soon".
enum OpType {
  label(0),
  radio(1),
  checkbox(2),
  rating(3),
  input(4),
  dropdown(5),
  imageUpload(6),
  datePicker(7),
  timePicker(8),
  videoUpload(9),
  signature(10),
  barcode(11),
  qrCode(12),
  grid(13),
  descriptionBox(14),
  reserved15(15),
  reserved16(16),
  singleImage(17),
  videoPlayback(18),
  audioPlayback(19),
  audioUpload(20),
  multiImage(21),
  voiceRecording(22),
  dependentDropdown(23),
  webview(24),
  toggle(25),
  chipSingle(26),
  chipMulti(27);

  final int code;
  const OpType(this.code);

  static OpType fromCode(int c) =>
      OpType.values.firstWhere((e) => e.code == c, orElse: () => OpType.label);
}

/// Validation rules attached to a control (see the Radar validations table).
class Validations {
  /// 0 = optional, 1 = mandatory, 2 = all-mandatory (grid).
  final int mandatory;

  /// Min/max character length, parsed from a "min-max" string.
  final int minLen;
  final int maxLen;

  /// Validation type (regex family), 1..20. 0 = none.
  final int vtype;

  /// Keypad type: 1 numeric, 2 alphanumeric.
  final int keypadType;

  /// Numeric min/max value (for rating/number controls).
  final num? minValue;
  final num? maxValue;

  /// Grid only (optional): when 1, EVERY cell of the grid must be filled to
  /// pass. Omit the key (or set 0) to keep the grid lenient. Add it as
  /// `"gridRequireAll": 1` inside the control's `validations`.
  final int gridRequireAll;

  const Validations({
    this.mandatory = 0,
    this.minLen = 0,
    this.maxLen = 1000,
    this.vtype = 0,
    this.keypadType = 2,
    this.minValue,
    this.maxValue,
    this.gridRequireAll = 0,
  });

  bool get isMandatory => mandatory >= 1;

  /// True when a grid requires every cell filled (see [gridRequireAll]).
  bool get requireAllGridCells => gridRequireAll == 1;

  factory Validations.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const Validations();
    int minLen = 0, maxLen = 1000;
    final lenRaw = j['len'];
    if (lenRaw is String && lenRaw.contains('-')) {
      final parts = lenRaw.split('-');
      minLen = int.tryParse(parts[0].trim()) ?? 0;
      maxLen = int.tryParse(parts[1].trim()) ?? 1000;
    }
    return Validations(
      mandatory: (j['mn'] as num?)?.toInt() ?? 0,
      minLen: minLen,
      maxLen: maxLen,
      vtype: (j['vtype'] as num?)?.toInt() ?? 0,
      keypadType: (j['dtype'] as num?)?.toInt() ?? 2,
      minValue: j['min'] as num?,
      maxValue: j['max'] as num?,
      gridRequireAll: (j['gridRequireAll'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A single form control on a survey page.
class Control {
  /// Globally-unique INTERNAL key, namespaced by the page id (see [fromJson]).
  /// Used to key the controller's answers/photos/errors maps. Control ids are
  /// only unique WITHIN a page, so this prevents a control on page 2 from
  /// clobbering a same-id control on page 1.
  final int id;

  /// The control's own id EXACTLY as written in the JSON. This is what the
  /// submission sends as `quesId`, so the backend sees the ids from the config,
  /// grouped per page — never the namespaced internal key.
  final int wireId;

  final OpType opType;

  /// Label text per language code. A JSON `label` may be a plain string
  /// (`"Site name"`) or a map (`{"en":"Site name","hi":"साइट का नाम"}`).
  /// A plain string is stored under the `'*'` key and shown for every language.
  final Map<String, String> labels;
  final Validations validations;
  final Map<String, String> validationMsgs;

  /// Options for radio/checkbox/dropdown, split from a ";"-separated string.
  final List<String> options;

  // Grid
  final List<String> rows;
  final List<String> cols;

  // Skip logic
  final bool skip;
  final List<String> skipLogic; // page ids per option index

  // Media
  final String? file;
  final int camType; // 1 front, 2 back
  final bool allowMultiple;
  final int subtype; // caption capture mode on photos

  // Dependent dropdown
  final int? dependsOn; // control id this depends on
  final String? dataUrl; // per-dropdown API url (Radar Phase 2)

  /// The offline-dropdown tree key this cascading dropdown reads from. This is
  /// USER-DEFINED in the JSON (`dependentDropdownKey`, e.g. "adgramList") and is
  /// matched against the `key` field of the offline-dropdown API response — it
  /// is never hard-coded in the app.
  final String? dependentKey;

  /// One label per cascade level (`dependentDropdownLabel`). Each entry may be a
  /// plain string or a `{lang: text}` map, resolved via [dependentLabelAt].
  final List<Map<String, String>> dependentLabels;

  /// One "please select" error/hint per cascade level (`dependentDropdownErrMsg`).
  final List<Map<String, String>> dependentErrMsgs;

  /// The cascade level (1-based) at which the `otherDetails` card/table is shown
  /// AND up to which the cascade is required. From `showOtherDetailsLevel`
  /// (`[{ "showlevel": 1 }]`) or a plain `showlevel`/`showLevel`. When null the
  /// dropdown behaves as before (require to the leaf; show the deepest node's
  /// details).
  final int? showLevel;

  // Numeric
  final num? min;
  final num? max;

  const Control({
    required this.id,
    required this.wireId,
    required this.opType,
    required this.labels,
    required this.validations,
    this.validationMsgs = const {},
    this.options = const [],
    this.rows = const [],
    this.cols = const [],
    this.skip = false,
    this.skipLogic = const [],
    this.file,
    this.camType = 1,
    this.allowMultiple = false,
    this.subtype = 0,
    this.dependsOn,
    this.dataUrl,
    this.dependentKey,
    this.dependentLabels = const [],
    this.dependentErrMsgs = const [],
    this.showLevel,
    this.min,
    this.max,
  });

  /// Builds the validations map for [Validations.fromJson], folding in the
  /// control-level `dtype` (numeric/alphanumeric keypad) which the JSON places
  /// as a sibling of `validations`, not inside it.
  static Map<String, dynamic>? _valMap(Map<String, dynamic> j) {
    final raw = j['validations'];
    final dtype = j['dtype'];
    if (raw == null && dtype == null) return null;
    final m = raw == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(raw as Map);
    if (dtype != null && m['dtype'] == null) m['dtype'] = dtype;
    return m;
  }

  static List<String> _split(dynamic v) {
    // Accept BOTH a JSON array (["Height","Width"]) and a legacy ';'-joined
    // string ("Height;Width"). optRow/optCol/optList/skipLogic may arrive in
    // either shape; treating an array as "not a string" silently emptied grids.
    if (v is List) {
      return v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }
    if (v is String && v.trim().isNotEmpty) {
      return v.split(';').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }
    return const [];
  }

  /// Parses a `label` node that may be a plain string or a `{lang: text}` map.
  static Map<String, String> _labels(dynamic v) {
    if (v is Map) {
      final m = <String, String>{};
      v.forEach((k, val) => m[k.toString()] = val.toString());
      return m;
    }
    if (v is String) return {'*': v};
    return const {'*': ''};
  }

  /// Returns the label for [lang], falling back to the language-agnostic
  /// `'*'` entry, then English, then the first available translation.
  String labelFor(String lang) {
    return labels[lang] ??
        labels['*'] ??
        labels['en'] ??
        (labels.isNotEmpty ? labels.values.first : '');
  }

  /// Language-agnostic default (used where no active language is available).
  String get label => labelFor('*');

  /// Parses a list node (`dependentDropdownLabel`/`dependentDropdownErrMsg`)
  /// where each item is a plain string or a `{lang: text}` map.
  static List<Map<String, String>> _labelList(dynamic v) {
    if (v is List) return v.map((e) => _labels(e)).toList();
    return const [];
  }

  /// Resolves the cascade label for [level] in [lang], falling back to the
  /// language-agnostic entry, then English, then any available translation.
  String dependentLabelAt(int level, String lang) {
    if (level < 0 || level >= dependentLabels.length) return '';
    final m = dependentLabels[level];
    return m[lang] ??
        m['*'] ??
        m['en'] ??
        (m.isNotEmpty ? m.values.first : '');
  }

  /// Parses `showOtherDetailsLevel` (a `[{showlevel: N}]` list, a `{showlevel:N}`
  /// map, or a plain number) into a 1-based level, or null.
  static int? _showLevel(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    if (v is List && v.isNotEmpty) return _showLevel(v.first);
    if (v is Map) return _showLevel(v['showlevel'] ?? v['showLevel'] ?? v['level']);
    return null;
  }

  /// Resolves the "please select" message for [level] in [lang].
  String dependentErrAt(int level, String lang) {
    if (level < 0 || level >= dependentErrMsgs.length) return '';
    final m = dependentErrMsgs[level];
    return m[lang] ??
        m['*'] ??
        m['en'] ??
        (m.isNotEmpty ? m.values.first : '');
  }

  /// Namespace multiplier for building the unique internal [id] from
  /// (pageId, wireId). Larger than any realistic control id per page.
  static const int _pageKeyStride = 100000;

  factory Control.fromJson(Map<String, dynamic> j, {int pageId = 0}) {
    final msgs = <String, String>{};
    (j['validationsMsg'] as Map?)?.forEach((k, v) => msgs[k.toString()] = v.toString());
    final rawId = (j['id'] as num).toInt();
    return Control(
      // Namespaced by page so answers/photos/errors never collide across pages.
      id: pageId * _pageKeyStride + rawId,
      // The JSON's own control id, sent to the backend as `quesId`.
      wireId: rawId,
      opType: OpType.fromCode((j['optype'] as num?)?.toInt() ?? 0),
      labels: _labels(j['label']),
      validations: Validations.fromJson(_valMap(j)),
      validationMsgs: msgs,
      options: _split(j['optList']),
      rows: _split(j['optRow']),
      cols: _split(j['optCol']),
      skip: (j['skipFlag'] as num?)?.toInt() == 1,
      skipLogic: _split(j['skipLogic']),
      file: j['file'],
      camType: (j['cam_type'] as num?)?.toInt() ?? 1,
      allowMultiple: (j['mul'] as num?)?.toInt() == 1,
      subtype: (j['subtype'] as num?)?.toInt() ?? 0,
      dependsOn: (j['dependsOn'] as num?)?.toInt(),
      dataUrl: j['dataUrl'],
      dependentKey: (j['dependentDropdownKey'] ?? j['dependentKey'])?.toString(),
      dependentLabels: _labelList(j['dependentDropdownLabel']),
      dependentErrMsgs: _labelList(j['dependentDropdownErrMsg']),
      showLevel: _showLevel(
          j['showOtherDetailsLevel'] ?? j['showlevel'] ?? j['showLevel']),
      min: j['min'] as num?,
      max: j['max'] as num?,
    );
  }
}

/// A survey page holding one or more controls.
class SurveyPage {
  final int id;

  /// Page title per language code — same rules as [Control.labels].
  final Map<String, String> titles;
  final List<Control> controls;

  const SurveyPage({required this.id, required this.titles, required this.controls});

  String titleFor(String lang) {
    return titles[lang] ??
        titles['*'] ??
        titles['en'] ??
        (titles.isNotEmpty ? titles.values.first : '');
  }

  String get title => titleFor('*');

  factory SurveyPage.fromJson(Map<String, dynamic> j) {
    final pageId = (j['id'] as num).toInt();
    return SurveyPage(
      id: pageId,
      titles: Control._labels(j['title']),
      controls: (j['controls'] as List? ?? [])
          .map((c) =>
              Control.fromJson(Map<String, dynamic>.from(c), pageId: pageId))
          .toList(),
    );
  }
}

/// The complete configuration bundle the app runs on: appConfig + strings +
/// the survey pages.
class RadarBundle {
  final Map<String, dynamic> rawAppConfig;
  final Map<String, Map<String, String>> strings;
  final List<SurveyPage> forms;

  const RadarBundle({
    required this.rawAppConfig,
    required this.strings,
    required this.forms,
  });

  factory RadarBundle.fromJson(Map<String, dynamic> j) {
    final strings = <String, Map<String, String>>{};
    (j['strings'] as Map?)?.forEach((lang, kv) {
      final m = <String, String>{};
      (kv as Map).forEach((k, v) => m[k.toString()] = v.toString());
      strings[lang.toString()] = m;
    });
    return RadarBundle(
      rawAppConfig: Map<String, dynamic>.from(j['appConfig'] ?? {}),
      strings: strings,
      forms: (j['appForms'] as List? ?? [])
          .map((p) => SurveyPage.fromJson(Map<String, dynamic>.from(p)))
          .toList(),
    );
  }
}
