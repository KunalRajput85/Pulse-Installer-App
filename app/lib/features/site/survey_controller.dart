import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_state.dart';
import '../../core/models/models.dart';
import '../../core/models/offline_dropdown.dart';
import '../../core/models/survey.dart';
import '../../core/services/validation_service.dart';

/// One reviewed control: a question plus one or more labelled value rows.
/// Simple controls have a single row with an empty sub-label; a dependent
/// dropdown has one row per selected level.
class ReviewItem {
  final String question;
  final List<MapEntry<String, String>> rows;
  const ReviewItem(this.question, this.rows);
}

/// Drives a single survey capture: holds answers, validates each page, applies
/// skip logic, and assembles the final [SurveyResponse].
class SurveyController extends ChangeNotifier {
  final AppState app;
  final List<SurveyPage> pages;

  final Map<int, dynamic> answers = {}; // controlId -> value
  final Map<int, List<CapturedPhoto>> photos = {}; // controlId -> photos
  final Map<int, String?> errors = {}; // controlId -> error text
  GpsReading? gps;

  int _index = 0;
  final List<int> _history = [0];

  SurveyController({required this.app, required this.pages});

  SurveyPage get current => pages[_index];
  int get index => _index;
  bool get isLast => _nextIndex() == null;
  double get progress => pages.isEmpty ? 1 : (_index + 1) / pages.length;

  void setAnswer(int controlId, dynamic value) {
    answers[controlId] = value;
    errors.remove(controlId);
    notifyListeners();
  }

  void addPhoto(int controlId, CapturedPhoto photo, {bool allowMultiple = false}) {
    final list = photos.putIfAbsent(controlId, () => []);
    if (!allowMultiple) list.clear();
    list.add(photo);
    // NOTE: photos live ONLY in the `photos` map — do NOT mirror them into
    // `answers`. control ids are unique per page but can repeat ACROSS pages
    // (e.g. page 1 dropdown id 1 and page 2 photo id 1). Writing the image path
    // into answers[controlId] here overwrote another page's real answer, which
    // leaked a /data/.../xxxx.jpg path into that question's ansMultiChoice.
    errors.remove(controlId);
    notifyListeners();
  }

  void removePhoto(int controlId, CapturedPhoto photo) {
    photos[controlId]?.remove(photo);
    // (see addPhoto) photos are tracked in `photos` only, never in `answers`.
    notifyListeners();
  }

  /// Validates every control on the current page. Returns true if all pass.
  bool validateCurrent() {
    var ok = true;
    for (final c in current.controls) {
      if (c.opType == OpType.label) continue;
      String? err;
      if (c.opType == OpType.dependentDropdown) {
        err = _validateDependent(c);
      } else if (_isPhotoType(c.opType)) {
        err = _validatePhotos(c);
      } else if (c.opType == OpType.grid) {
        err = _validateGrid(c);
      } else {
        err = ValidationService.validateAnswer(c, answers[c.id]);
      }
      errors[c.id] = err;
      if (err != null) ok = false;
    }
    notifyListeners();
    return ok;
  }

  static bool _isPhotoType(OpType t) =>
      t == OpType.imageUpload ||
      t == OpType.singleImage ||
      t == OpType.multiImage;

  String? _validatePhotos(Control c) {
    final count = photos[c.id]?.length ?? 0;
    if (c.validations.isMandatory && count == 0) {
      return c.validationMsgs['mn'] ?? 'Photo is required';
    }
    return null;
  }

  /// Validates a text grid (optype 13). With `gridRequireAll: 1` EVERY cell
  /// must be filled; otherwise a mandatory grid needs at least one cell and an
  /// optional grid is always valid.
  String? _validateGrid(Control c) {
    final map = (answers[c.id] as Map?)?.cast<String, String>() ?? const {};
    bool filled(String r, String col) =>
        (map['$r|$col'] ?? '').trim().isNotEmpty;

    if (c.validations.requireAllGridCells) {
      for (final r in c.rows) {
        for (final col in c.cols) {
          if (!filled(r, col)) {
            return c.validationMsgs['mn'] ?? 'Please fill all values';
          }
        }
      }
      return null;
    }
    if (c.validations.isMandatory) {
      final any = c.rows.any((r) => c.cols.any((col) => filled(r, col)));
      if (!any) return c.validationMsgs['mn'] ?? 'This field is required';
    }
    return null;
  }

  /// Validates a cascading dependent dropdown. Only the levels the flow actually
  /// requires are enforced:
  ///   • If `showLevel` is set → the user must reach that level (levels beyond it
  ///     are optional).
  ///   • Otherwise → the user must drill down to a leaf (a node with no more
  ///     children).
  /// The error shown is the configured message for the FIRST level still needed,
  /// so partial selections aren't blocked by later, not-yet-reachable levels.
  String? _validateDependent(Control c) {
    if (!c.validations.isMandatory) return null;
    final lang = app.strings.lang;
    final chain = (answers[c.id] as List?)?.map((e) => e.toString()).toList() ??
        const <String>[];
    final selected = chain.length;

    String needMsg(int level) {
      final m = c.dependentErrAt(level, lang);
      return m.isNotEmpty ? m : (c.validationMsgs['mn'] ?? 'This field is required');
    }

    // A mandatory cascade always needs at least the first level. (This also
    // fixes the old bug where an empty/unloaded tree let a blank selection pass.)
    if (selected == 0) return needMsg(0);

    // ALL levels are required. `showLevel` is a DISPLAY-only setting (when the
    // otherDetails card appears) and never reduces how many levels must be
    // selected. Require the user to drill to a LEAF: detect the leaf from the
    // loaded tree; if the tree can't be inspected, require every configured
    // level (dependentDropdownLabel).
    final tree = app.offlineDropdown.tree;
    if (tree != null && tree.hasKey(c.dependentKey)) {
      var options = tree.rootsFor(c.dependentKey);
      if (options.isNotEmpty) {
        for (final label in chain) {
          DropdownNode? found;
          for (final n in options) {
            if (n.label == label) {
              found = n;
              break;
            }
          }
          if (found == null) break;
          options = found.selectableOptions;
        }
        // Deepest selected node still has selectable children => not complete.
        return options.isEmpty ? null : needMsg(selected);
      }
    }
    // Tree unavailable → require all configured cascade levels.
    final need =
        c.dependentLabels.isNotEmpty ? c.dependentLabels.length : selected;
    return selected >= need ? null : needMsg(selected);
  }

  /// Computes the next page index honouring skip logic (optype 1/2) on the
  /// current page, or null if this is the terminal page.
  int? _nextIndex() {
    // Skip logic: if a radio/checkbox on this page sets skipFlag, jump to the
    // mapped page id for the selected option.
    for (final c in current.controls) {
      if (!c.skip || c.skipLogic.isEmpty) continue;
      final answer = answers[c.id];
      if (answer == null) continue;
      final selectedIdx = _selectedOptionIndex(c, answer);
      if (selectedIdx != null && selectedIdx < c.skipLogic.length) {
        final targetId = int.tryParse(c.skipLogic[selectedIdx]);
        final targetIdx = pages.indexWhere((p) => p.id == targetId);
        if (targetIdx >= 0) return targetIdx;
      }
    }
    return _index + 1 < pages.length ? _index + 1 : null;
  }

  int? _selectedOptionIndex(Control c, dynamic answer) {
    // Options are 1-based in the Radar spec; convert to 0-based index.
    if (answer is String) {
      final i = c.options.indexOf(answer);
      return i >= 0 ? i : null;
    }
    if (answer is List && answer.isNotEmpty) {
      final i = c.options.indexOf(answer.first.toString());
      return i >= 0 ? i : null;
    }
    return null;
  }

  /// Resolves the geo-tag (lt/lg + radius) of the location selected in a
  /// dependent dropdown on the CURRENT page, if any. Returns null when there is
  /// no cascading dropdown, nothing selected, or the selected leaf carries no
  /// coordinates. Used to geofence the installer against the chosen site.
  NodeDetails? currentPageGeoDetails() {
    final tree = app.offlineDropdown.tree;
    if (tree == null) return null;
    for (final c in current.controls) {
      if (c.opType != OpType.dependentDropdown) continue;
      final chain = (answers[c.id] as List?)?.map((e) => e.toString()).toList() ??
          const <String>[];
      if (chain.isEmpty) continue;
      var nodes = tree.rootsFor(c.dependentKey);
      DropdownNode? node;
      for (final label in chain) {
        DropdownNode? found;
        for (final n in nodes) {
          if (n.label == label) {
            found = n;
            break;
          }
        }
        if (found == null) break;
        node = found;
        nodes = found.selectableOptions;
      }
      if (node?.details != null && node!.details!.hasGeo) return node.details;
    }
    return null;
  }

  bool next() {
    if (!validateCurrent()) return false;
    final n = _nextIndex();
    if (n == null) return false;
    _index = n;
    _history.add(_index);
    notifyListeners();
    return true;
  }

  bool back() {
    if (_history.length <= 1) return false;
    _history.removeLast();
    _index = _history.last;
    notifyListeners();
    return true;
  }

  /// Human-readable summary shown before submission (Radar Phase 3).
  Map<String, String> buildSummary() {
    final out = <String, String>{};
    for (final page in pages) {
      for (final c in page.controls) {
        if (c.opType == OpType.label) continue;
        final a = answers[c.id];
        if (a == null) continue;
        if (c.opType == OpType.imageUpload) {
          out[c.label] = '${(photos[c.id]?.length ?? 0)} photo(s)';
        } else if (a is List) {
          out[c.label] = a.join(', ');
        } else {
          out[c.label] = a.toString();
        }
      }
    }
    return out;
  }

  /// Builds the review model shown before submission: one entry per answered
  /// control (questions + answers). Image controls are EXCLUDED from the review
  /// (they are still submitted normally). Dependent dropdowns are broken out
  /// into one labelled row per selected level (Village: …, Creative: …).
  List<ReviewItem> buildReview() {
    final lang = app.strings.lang;
    final items = <ReviewItem>[];
    for (final page in pages) {
      for (final c in page.controls) {
        if (c.opType == OpType.label) continue;
        if (_isPhotoType(c.opType)) continue; // never show images in the review

        final question = c.labelFor(lang);

        if (c.opType == OpType.dependentDropdown) {
          final chain =
              (answers[c.id] as List?)?.map((e) => e.toString()).toList() ??
                  const <String>[];
          if (chain.isEmpty) continue;
          final rows = <MapEntry<String, String>>[];
          for (var i = 0; i < chain.length; i++) {
            final levelLabel = c.dependentLabelAt(i, lang);
            rows.add(MapEntry(
                levelLabel.isNotEmpty ? levelLabel : 'Level ${i + 1}', chain[i]));
          }
          items.add(ReviewItem(question, rows));
          continue;
        }

        final a = answers[c.id];
        if (a == null || (a is String && a.trim().isEmpty)) continue;
        String value;
        if (a is List) {
          value = a.map((e) => e.toString()).where((s) => s.isNotEmpty).join(', ');
        } else if (a is bool) {
          value = a ? 'Yes' : 'No';
        } else if (a is Map) {
          value = a.entries.map((e) => '${e.key}: ${e.value}').join('  ·  ');
        } else {
          value = a.toString();
        }
        if (value.trim().isEmpty) continue;
        items.add(ReviewItem(question, [MapEntry('', value)]));
      }
    }
    return items;
  }

  Future<SurveyResponse> buildResponse() async {
    final installerId = await app.auth.clientName() ?? '';
    final device = await app.device.read();
    final allPhotos = photos.values.expand((e) => e).toList();
    return SurveyResponse(
      localId: const Uuid().v4(),
      surveyId: app.appConfig.id,
      configVersion: app.appConfig.version,
      installerId: installerId,
      deviceId: device.bindingId,
      gps: gps,
      answers: Map<int, dynamic>.from(answers),
      photos: allPhotos,
      formPages: buildStructuredPages(),
      createdAt: DateTime.now(),
      status: SyncStatus.queued,
    );
  }

  /// Builds the structured submission payload the backend expects:
  ///
  /// ```json
  /// [
  ///   { "pageId": 1, "quesList": [
  ///       {"quesId": 2, "label": "Area", "ansMultiChoice": ["Fena","Up",...]},
  ///       {"quesId": 4, "label": "Size", "ansGrid": [{"ans":"56","colNo":1,"rowNo":1}, ...]},
  ///       {"quesId": 5, "fileUniqueId": "1748243883236"}
  ///   ]},
  ///   ...
  /// ]
  /// ```
  ///
  /// Each control maps to a typed answer field: multi/single selects →
  /// `ansMultiChoice`, grids → `ansGrid`, photo/file controls → one entry per
  /// captured file with its `fileUniqueId`, and everything text-like → `ans`.
  /// Unanswered controls are omitted.
  List<Map<String, dynamic>> buildStructuredPages() {
    final lang = app.strings.lang;
    final out = <Map<String, dynamic>>[];
    for (final page in pages) {
      final quesList = <Map<String, dynamic>>[];
      for (final c in page.controls) {
        if (c.opType == OpType.label) continue;
        quesList.addAll(_questionEntries(c, lang));
      }
      if (quesList.isNotEmpty) {
        out.add({'pageId': page.id, 'quesList': quesList});
      }
    }
    return out;
  }

  List<Map<String, dynamic>> _questionEntries(Control c, String lang) {
    final label = c.labelFor(lang);
    switch (c.opType) {
      // File-bearing controls: one entry per captured file.
      case OpType.imageUpload:
      case OpType.singleImage:
      case OpType.multiImage:
      case OpType.videoUpload:
      case OpType.audioUpload:
      case OpType.voiceRecording:
      case OpType.signature:
        final files = photos[c.id] ?? const [];
        return files
            .map((p) => {'quesId': c.wireId, 'fileUniqueId': p.fileUniqueId})
            .toList();

      // Grid: row/column answers as {ans, colNo, rowNo} (1-based).
      case OpType.grid:
        final grid = _gridAnswer(c);
        if (grid.isEmpty) return const [];
        return [
          {'quesId': c.wireId, 'label': label, 'ansGrid': grid}
        ];

      // Cascading dependent dropdown: the answer is stored as the selected
      // LABELS (for display/geofencing), but the submission must send the
      // underlying VALUES from the offline-dropdown tree.
      case OpType.dependentDropdown:
        final values = _dependentValues(c);
        if (values.isEmpty) return const [];
        return [
          {'quesId': c.wireId, 'label': label, 'ansMultiChoice': values}
        ];

      // Other selections: an array of the chosen option strings.
      case OpType.checkbox:
      case OpType.chipMulti:
      case OpType.radio:
      case OpType.dropdown:
      case OpType.chipSingle:
        final choices = _multiChoiceAnswer(c);
        if (choices.isEmpty) return const [];
        return [
          {'quesId': c.wireId, 'label': label, 'ansMultiChoice': choices}
        ];

      // Everything text-like (input, description, rating, toggle, date/time…).
      default:
        final a = answers[c.id];
        if (a == null || (a is String && a.trim().isEmpty)) return const [];
        return [
          {'quesId': c.wireId, 'label': label, 'ans': a}
        ];
    }
  }

  List<String> _multiChoiceAnswer(Control c) {
    final a = answers[c.id];
    if (a == null) return const [];
    if (a is List) {
      return a.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    final s = a.toString().trim();
    return s.isEmpty ? const [] : [s];
  }

  /// Translates a dependent-dropdown's selected LABEL chain into the underlying
  /// VALUE chain from the offline-dropdown tree (each option carries both a
  /// label and a value). Walks the tree level by level along the selected
  /// labels. If the tree isn't loaded, the key is unknown, or a node has no
  /// value, it falls back to the label for that level so nothing is dropped.
  List<String> _dependentValues(Control c) {
    final labels = _multiChoiceAnswer(c); // the selected label chain
    if (labels.isEmpty) return const [];
    final tree = app.offlineDropdown.tree;
    if (tree == null || !tree.hasKey(c.dependentKey)) return labels;

    final out = <String>[];
    var nodes = tree.rootsFor(c.dependentKey);
    for (final label in labels) {
      DropdownNode? found;
      for (final n in nodes) {
        if (n.label == label) {
          found = n;
          break;
        }
      }
      if (found == null) {
        out.add(label); // couldn't resolve this level — keep the label
        continue;
      }
      out.add(found.value.trim().isNotEmpty ? found.value : label);
      nodes = found.selectableOptions;
    }
    return out;
  }

  List<Map<String, dynamic>> _gridAnswer(Control c) {
    final map = (answers[c.id] as Map?)?.cast<String, String>() ?? const {};
    final out = <Map<String, dynamic>>[];
    for (var ri = 0; ri < c.rows.length; ri++) {
      for (var ci = 0; ci < c.cols.length; ci++) {
        final v = map['${c.rows[ri]}|${c.cols[ci]}'];
        if (v != null && v.trim().isNotEmpty) {
          out.add({'ans': v, 'colNo': ci + 1, 'rowNo': ri + 1});
        }
      }
    }
    return out;
  }
}
