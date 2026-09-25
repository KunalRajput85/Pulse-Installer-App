import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/offline_dropdown.dart';
import '../../core/models/survey.dart';
import '../branding/brand.dart';
import 'camera_capture_screen.dart';
import 'survey_controller.dart';

/// Renders a single Radar control based on its [OpType]. Everything the widget
/// shows — label, options, validation error, keypad type — comes from the JSON
/// config via the [Control] model.
class ControlWidget extends StatelessWidget {
  final Control control;
  final SurveyController controller;
  final bool liveCameraOnly;

  /// Active language code (from the JSON `languageConfig`). Labels are shown
  /// in this language when the control provides a translation for it.
  final String lang;

  const ControlWidget({
    super.key,
    required this.control,
    required this.controller,
    required this.liveCameraOnly,
    this.lang = 'en',
  });

  @override
  Widget build(BuildContext context) {
    final error = controller.errors[control.id];
    final body = _buildBody(context);
    if (control.opType == OpType.label) return body;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AuroraIconChip(_iconFor(control.opType), size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Text(control.labelFor(lang),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Brand.inkNavy)),
              ),
              if (control.validations.isMandatory)
                const Text(' *', style: TextStyle(color: Colors.red, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 12),
          body,
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(error,
                  style: const TextStyle(color: Colors.red, fontSize: 12.5)),
            ),
        ],
      ),
    );
  }

  /// A representative icon for each control type (shown in the card's chip).
  static IconData _iconFor(OpType t) {
    switch (t) {
      case OpType.dependentDropdown:
        return Icons.location_on;
      case OpType.dropdown:
        return Icons.arrow_drop_down_circle_outlined;
      case OpType.radio:
        return Icons.radio_button_checked;
      case OpType.checkbox:
        return Icons.check_box_outlined;
      case OpType.chipSingle:
      case OpType.chipMulti:
        return Icons.style_outlined;
      case OpType.rating:
        return Icons.star_border;
      case OpType.input:
        return Icons.edit_outlined;
      case OpType.imageUpload:
      case OpType.singleImage:
      case OpType.multiImage:
        return Icons.photo_camera_outlined;
      case OpType.datePicker:
        return Icons.calendar_today;
      case OpType.timePicker:
        return Icons.access_time;
      case OpType.toggle:
        return Icons.toggle_on_outlined;
      case OpType.grid:
        return Icons.grid_on;
      default:
        return Icons.tune;
    }
  }

  Widget _buildBody(BuildContext context) {
    switch (control.opType) {
      case OpType.label:
        return _label();
      case OpType.radio:
        return _radio();
      case OpType.checkbox:
        return _checkbox();
      case OpType.rating:
        return _rating();
      case OpType.input:
        return _input();
      case OpType.dropdown:
        return _dropdown(context);
      case OpType.dependentDropdown:
        return DependentDropdownField(
          control: control,
          controller: controller,
          lang: lang,
        );
      case OpType.imageUpload:
        return _imageUpload(context);
      case OpType.datePicker:
        return _dateTime(context, isDate: true);
      case OpType.timePicker:
        return _dateTime(context, isDate: false);
      case OpType.toggle:
        return _toggle();
      case OpType.chipSingle:
        return _chips(multi: false);
      case OpType.chipMulti:
        return _chips(multi: true);
      case OpType.grid:
        return _grid();
      default:
        return _comingSoon();
    }
  }

  Widget _label() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF1F8),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(control.labelFor(lang),
            style: const TextStyle(fontSize: 14, color: Color(0xFF0D3D6B))),
      );

  Widget _radio() {
    final selected = controller.answers[control.id] as String?;
    return Column(
      children: control.options
          .map((o) => RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(o),
                value: o,
                groupValue: selected,
                onChanged: (v) => controller.setAnswer(control.id, v),
              ))
          .toList(),
    );
  }

  Widget _checkbox() {
    final selected =
        (controller.answers[control.id] as List?)?.cast<String>() ?? <String>[];
    return Column(
      children: control.options.map((o) {
        final checked = selected.contains(o);
        return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(o),
          value: checked,
          onChanged: (v) {
            final next = [...selected];
            v == true ? next.add(o) : next.remove(o);
            controller.setAnswer(control.id, next);
          },
        );
      }).toList(),
    );
  }

  Widget _rating() {
    final value = (controller.answers[control.id] as num?)?.toInt() ?? 0;
    final max = (control.max ?? control.validations.maxValue ?? 5).toInt();
    return Row(
      children: List.generate(max, (i) {
        final star = i + 1;
        return IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40),
          icon: Icon(star <= value ? Icons.star : Icons.star_border,
              color: Colors.amber, size: 32),
          onPressed: () => controller.setAnswer(control.id, star),
        );
      }),
    );
  }

  Widget _input() {
    final v = control.validations;
    final isNumeric = v.keypadType == 1;
    return TextFormField(
      initialValue: controller.answers[control.id]?.toString(),
      keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
      inputFormatters:
          isNumeric ? [FilteringTextInputFormatter.digitsOnly] : null,
      maxLength: v.maxLen < 1000 ? v.maxLen : null,
      decoration: const InputDecoration(isDense: true),
      onChanged: (val) => controller.setAnswer(control.id, val),
    );
  }

  Widget _dropdown(BuildContext context) {
    final value = controller.answers[control.id] as String?;
    final options = control.options;
    // Guard: the stored value must be one of the current options, otherwise
    // DropdownButtonFormField asserts.
    final safeValue = options.contains(value) ? value : null;
    return DropdownButtonFormField<String>(
      value: safeValue,
      isExpanded: true,
      icon: const Icon(Icons.expand_more, color: Brand.royalBlue, size: 20),
      style: const TextStyle(
          fontSize: 14, color: Brand.inkNavy, fontWeight: FontWeight.w600),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        hintText: 'Select…',
      ),
      items: options
          .map((o) => DropdownMenuItem(value: o, child: Text(o)))
          .toList(),
      onChanged: (v) => controller.setAnswer(control.id, v),
    );
  }

  Widget _imageUpload(BuildContext context) {
    final captured = controller.photos[control.id] ?? [];
    Future<void> capture() async {
      final photo = await Navigator.of(context).push<dynamic>(
        MaterialPageRoute(
          builder: (_) => CameraCaptureScreen(
            control: control,
            liveCameraOnly: liveCameraOnly,
          ),
        ),
      );
      if (photo != null) {
        controller.addPhoto(control.id, photo,
            allowMultiple: control.allowMultiple);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (captured.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SizedBox(
              height: 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: captured.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final ph = captured[i];
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(File(ph.localPath),
                            width: 104, height: 104, fit: BoxFit.cover),
                      ),
                      // subtle gradient scrim for the delete button
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => controller.removePhoto(control.id, ph),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                      const Positioned(
                        left: 6,
                        bottom: 6,
                        child: Icon(Icons.verified,
                            size: 16, color: Color(0xFF7FE0A6)),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        // Modern capture tile.
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: capture,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                colors: [Color(0xFFEFF5FE), Color(0xFFE7F0FC)],
              ),
              border: Border.all(color: const Color(0xFFCFE0F5)),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    gradient: Brand.accentGradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_camera,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        captured.isEmpty
                            ? 'Capture with live camera'
                            : (control.allowMultiple
                                ? 'Add another photo'
                                : 'Retake photo'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            color: Brand.royalBlue),
                      ),
                      if (liveCameraOnly)
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              Icon(Icons.lock_outline,
                                  size: 12, color: Brand.mutedInk),
                              SizedBox(width: 4),
                              Text('Live camera only — gallery disabled',
                                  style: TextStyle(
                                      fontSize: 11.5, color: Brand.mutedInk)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Brand.mutedInk),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _dateTime(BuildContext context, {required bool isDate}) {
    final value = controller.answers[control.id] as String?;
    return OutlinedButton.icon(
      icon: Icon(isDate ? Icons.calendar_today : Icons.access_time),
      label: Text(value ?? (isDate ? 'Pick a date' : 'Pick a time')),
      onPressed: () async {
        if (isDate) {
          final d = await showDatePicker(
            context: context,
            initialDate: DateTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
          );
          if (d != null) {
            controller.setAnswer(
                control.id, '${d.year}-${d.month.toString().padLeft(2, '0')}-'
                    '${d.day.toString().padLeft(2, '0')}');
          }
        } else {
          final t = await showTimePicker(
              context: context, initialTime: TimeOfDay.now());
          if (t != null) controller.setAnswer(control.id, t.format(context));
        }
      },
    );
  }

  Widget _toggle() {
    final value = controller.answers[control.id] == true;
    return Row(
      children: [
        Switch(
          value: value,
          onChanged: (v) => controller.setAnswer(control.id, v),
        ),
        Text(value ? 'Yes' : 'No'),
      ],
    );
  }

  Widget _chips({required bool multi}) {
    final selected = multi
        ? ((controller.answers[control.id] as List?)?.cast<String>() ?? <String>[])
        : <String>[if (controller.answers[control.id] != null) controller.answers[control.id]];
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: control.options.map((o) {
        final on = selected.contains(o);
        return ChoiceChip(
          label: Text(o),
          selected: on,
          onSelected: (_) {
            if (multi) {
              final next = [...selected];
              on ? next.remove(o) : next.add(o);
              controller.setAnswer(control.id, next);
            } else {
              controller.setAnswer(control.id, o);
            }
          },
        );
      }).toList(),
    );
  }

  Widget _grid() {
    // Compact text grid (optype 13): rows x cols of small inputs. Respects the
    // control's length limit (len "min-max") and numeric keypad (dtype 1).
    final map = (controller.answers[control.id] as Map?)?.cast<String, String>() ??
        <String, String>{};
    final v = control.validations;
    final isNum = v.keypadType == 1;
    final maxLen = v.maxLen;
    final formatters = <TextInputFormatter>[
      if (isNum) FilteringTextInputFormatter.digitsOnly,
      if (maxLen > 0 && maxLen < 1000) LengthLimitingTextInputFormatter(maxLen),
    ];

    const line = Color(0xFFE2E8F0);
    const headBg = Color(0xFFF1F5F9);

    Widget headCell(String text) => Container(
          color: headBg,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          alignment: Alignment.center,
          child: Text(text,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13, color: Brand.inkNavy)),
        );

    Widget rowLabel(String text) => Container(
          color: const Color(0xFFFAFBFC),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          alignment: Alignment.centerLeft,
          child: Text(text,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
        );

    Widget inputCell(String r, String col) {
      final key = '$r|$col';
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: SizedBox(
          height: 40,
          child: TextFormField(
            initialValue: map[key],
            keyboardType: isNum ? TextInputType.number : TextInputType.text,
            inputFormatters: formatters,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              hintText: '0',
              hintStyle: const TextStyle(color: Color(0xFFB8C2CE)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              filled: true,
              fillColor: Colors.white,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Brand.royalBlue, width: 1.4),
              ),
            ),
            onChanged: (val) {
              map[key] = val;
              controller.setAnswer(control.id, Map<String, String>.from(map));
            },
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        border: const TableBorder(
          horizontalInside: BorderSide(color: line),
          verticalInside: BorderSide(color: line),
        ),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: {
          0: const IntrinsicColumnWidth(),
          for (var i = 0; i < control.cols.length; i++)
            i + 1: const FlexColumnWidth(),
        },
        children: [
          TableRow(children: [
            headCell(''),
            ...control.cols.map(headCell),
          ]),
          ...control.rows.map((r) => TableRow(children: [
                rowLabel(r),
                ...control.cols.map((col) => inputCell(r, col)),
              ])),
        ],
      ),
    );
  }

  Widget _comingSoon() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF4E5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE8A33D)),
        ),
        child: Row(
          children: [
            const Icon(Icons.hourglass_empty, size: 18, color: Color(0xFFB4791F)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Control type "${control.opType.name}" (optype ${control.opType.code}) '
                'is planned for a later phase.',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFFB4791F)),
              ),
            ),
          ],
        ),
      );
}

/// A compact, numbered photo-capture card for the 2-column photo grid — used
/// when a page has several image controls (e.g. capturing 7 photos on one
/// page). Shows a number badge, title, a "Tap capture" preview, and a Capture
/// button; both the preview and the button open the live camera.
class PhotoGridCard extends StatelessWidget {
  final Control control;
  final SurveyController controller;
  final bool liveCameraOnly;
  final String lang;
  final int number;

  const PhotoGridCard({
    super.key,
    required this.control,
    required this.controller,
    required this.liveCameraOnly,
    required this.number,
    this.lang = 'en',
  });

  Future<void> _capture(BuildContext context) async {
    final photo = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (_) => CameraCaptureScreen(
          control: control,
          liveCameraOnly: liveCameraOnly,
        ),
      ),
    );
    if (photo != null) {
      controller.addPhoto(control.id, photo,
          allowMultiple: control.allowMultiple);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = controller.photos[control.id] ?? const [];
    final hasPhoto = photos.isNotEmpty;
    final error = controller.errors[control.id];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: Brand.cardDecoration(radius: 16).copyWith(
        border: Border.all(
            color: error != null ? const Color(0xFFE7A0A0) : const Color(0xFFE4EDF7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE7F0FC),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(number.toString().padLeft(2, '0'),
                    style: const TextStyle(
                        color: Brand.indigo,
                        fontWeight: FontWeight.w800,
                        fontSize: 12)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  control.labelFor(lang),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                      height: 1.15,
                      color: Brand.inkNavy),
                ),
              ),
              if (control.validations.isMandatory)
                const Text(' *',
                    style: TextStyle(color: Colors.red, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => _capture(context),
            child: AspectRatio(
              aspectRatio: 1.15,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF3F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE0E8F2)),
                ),
                clipBehavior: Clip.antiAlias,
                child: hasPhoto
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(File(photos.last.localPath),
                              fit: BoxFit.cover),
                          if (photos.length > 1)
                            Positioned(
                              right: 6,
                              bottom: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text('${photos.length}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ),
                          const Positioned(
                            right: 6,
                            top: 6,
                            child: Icon(Icons.verified,
                                size: 18, color: Color(0xFF16C2A8)),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.photo_camera_outlined,
                              size: 30, color: Brand.mutedInk),
                          SizedBox(height: 6),
                          Text('Tap capture',
                              style: TextStyle(
                                  color: Brand.mutedInk,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          GradientButton(
            label: hasPhoto
                ? (control.allowMultiple ? 'Add' : 'Retake')
                : 'Capture',
            icon: null,
            height: 42,
            onPressed: () => _capture(context),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline,
                      size: 15, color: Color(0xFFD64545)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(error,
                        style: const TextStyle(
                            color: Color(0xFFD64545),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Cascading (N-level) dependent dropdown (optype 23).
///
/// The options come from the offline-dropdown tree, looked up by the control's
/// USER-DEFINED [Control.dependentKey] (e.g. "adgramList") — never hard-coded.
/// Selecting a value at one level reveals the next level (that node's
/// `options`) until a leaf is reached. The selected chain of labels is stored
/// as the control's answer (a `List<String>`), which the submission payload
/// emits as `ansMultiChoice`.
class DependentDropdownField extends StatefulWidget {
  final Control control;
  final SurveyController controller;
  final String lang;

  const DependentDropdownField({
    super.key,
    required this.control,
    required this.controller,
    this.lang = 'en',
  });

  @override
  State<DependentDropdownField> createState() => _DependentDropdownFieldState();
}

class _DependentDropdownFieldState extends State<DependentDropdownField> {
  OfflineDropdownTree? _tree;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tree = await widget.controller.app.offlineDropdown.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _tree = tree;
      _loading = false;
    });
  }

  List<String> get _chain {
    final a = widget.controller.answers[widget.control.id];
    if (a is List) return a.map((e) => e.toString()).toList();
    return const [];
  }

  static DropdownNode? _find(List<DropdownNode> nodes, String label) {
    for (final n in nodes) {
      if (n.label == label) return n;
    }
    return null;
  }

  /// Resolves the option list for each visible cascade level from the current
  /// selection chain.
  List<List<DropdownNode>> _levels(List<DropdownNode> roots) {
    final levels = <List<DropdownNode>>[roots];
    var current = roots;
    for (final label in _chain) {
      final node = _find(current, label);
      if (node == null) break;
      final children = node.selectableOptions;
      if (children.isEmpty) break; // leaf reached — no further level
      levels.add(children);
      current = children;
    }
    return levels;
  }

  void _onSelect(int level, String? label) {
    final chain = [..._chain];
    if (label == null) {
      // Cleared: drop this level and everything below it.
      if (level < chain.length) chain.removeRange(level, chain.length);
    } else {
      if (level < chain.length) {
        chain[level] = label;
        // Changing a parent invalidates every deeper selection.
        if (level + 1 < chain.length) {
          chain.removeRange(level + 1, chain.length);
        }
      } else {
        chain.add(label);
      }
    }
    widget.controller.setAnswer(widget.control.id, chain);
  }

  /// Resolves which node's `otherDetails` to render, honouring `showLevel`.
  /// `showLevel` gates WHEN the details appear (only once that many levels are
  /// selected). The details themselves come from the deepest selected node that
  /// actually carries `otherDetails`, so it works no matter which cascade level
  /// the backend attached them to.
  NodeDetails? _detailsToShow(List<DropdownNode> roots) {
    final level = widget.control.showLevel;
    if (level != null && _chain.length < level) return null; // not reached yet
    // Prefer the node at exactly `showLevel` if it carries details; otherwise
    // fall back to the deepest selected node that has details — so it works
    // whether the backend attached otherDetails at that level or at the leaf.
    NodeDetails? atLevel;
    NodeDetails? deepest;
    var current = roots;
    var depth = 0;
    for (final label in _chain) {
      final n = _find(current, label);
      if (n == null) break;
      depth++;
      if (n.details != null) {
        deepest = n.details;
        if (level != null && depth == level) atLevel = n.details;
      }
      current = n.selectableOptions;
    }
    return atLevel ?? deepest;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Loading options…', style: TextStyle(fontSize: 13)),
          ],
        ),
      );
    }

    final roots = _tree?.rootsFor(widget.control.dependentKey) ?? const [];
    if (roots.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF4E5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE8A33D)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 18, color: Color(0xFFB4791F)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.control.dependentKey == null
                    ? 'No dependentDropdownKey set for this control.'
                    : 'No options available for "${widget.control.dependentKey}" yet. '
                        'Reconnect to load the dropdown list.',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFFB4791F)),
              ),
            ),
          ],
        ),
      );
    }

    final chain = _chain;
    final levels = _levels(roots);
    final details = _detailsToShow(roots);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var li = 0; li < levels.length; li++)
          Padding(
            padding: EdgeInsets.only(top: li == 0 ? 0 : 8),
            child: _levelDropdown(li, levels[li], chain),
          ),
        if (details != null) ...[
          const SizedBox(height: 12),
          DropdownDetailsCard(details: details),
        ],
      ],
    );
  }

  /// A compact cascade row: tiny caption label + a dense dropdown so six levels
  /// no longer fill the whole page.
  Widget _levelDropdown(int level, List<DropdownNode> options, List<String> chain) {
    final selected = level < chain.length ? chain[level] : null;
    final labels = options.map((n) => n.label).toList();
    final safeValue = labels.contains(selected) ? selected : null;
    final hint = widget.control.dependentErrAt(level, widget.lang);
    final levelLabel = widget.control.dependentLabelAt(level, widget.lang);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (levelLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 3, left: 2),
            child: Text(levelLabel.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 0.4,
                  fontWeight: FontWeight.w700,
                  color: Brand.mutedInk,
                )),
          ),
        DropdownButtonFormField<String>(
          value: safeValue,
          isExpanded: true,
          icon: const Icon(Icons.expand_more, color: Brand.royalBlue, size: 20),
          style: const TextStyle(
              fontSize: 14, color: Brand.inkNavy, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            hintText: hint.isNotEmpty ? hint : 'Select…',
            hintStyle:
                const TextStyle(color: Color(0xFF9AA6B8), fontSize: 13.5),
          ),
          items: options
              .map((n) => DropdownMenuItem(
                  value: n.label,
                  child: Text(n.label, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (v) => _onSelect(level, v),
        ),
      ],
    );
  }
}

/// The info / table card shown beneath a selected cascading-dropdown value,
/// built from the node's `otherDetails` (info lines, HTML text and/or a table).
class DropdownDetailsCard extends StatelessWidget {
  final NodeDetails details;
  const DropdownDetailsCard({super.key, required this.details});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF3F8FF), Color(0xFFEAF2FF)],
        ),
        border: Border.all(color: const Color(0xFFD5E4F7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(
                    gradient: Brand.accentGradient, shape: BoxShape.circle),
                child: const Icon(Icons.store_mall_directory,
                    size: 14, color: Colors.white),
              ),
              const SizedBox(width: 8),
              const Text('Details',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: Brand.royalBlue)),
            ],
          ),
          if (details.info.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...details.info.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                          fontSize: 13.5, color: Brand.inkNavy, height: 1.35),
                      children: [
                        TextSpan(
                            text: r.label,
                            style: TextStyle(
                                fontWeight: r.bold
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                color: Brand.labelInk)),
                        TextSpan(text: r.value),
                      ],
                    ),
                  ),
                )),
          ],
          if (details.htmlText != null &&
              details.htmlText!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            HtmlLite(details.htmlText!),
          ],
          if (details.table != null && !details.table!.isEmpty) ...[
            const SizedBox(height: 12),
            MiniTable(table: details.table!),
          ],
        ],
      ),
    );
  }
}

/// A compact, modern table rendered from [NodeTable].
class MiniTable extends StatelessWidget {
  final NodeTable table;
  const MiniTable({super.key, required this.table});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD5E0EF)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Table(
          border: TableBorder.symmetric(
            inside: const BorderSide(color: Color(0xFFE4EBF5)),
          ),
          defaultColumnWidth: const FlexColumnWidth(),
          children: [
            if (table.headers.isNotEmpty)
              TableRow(
                decoration: const BoxDecoration(gradient: Brand.headerGradient),
                children: table.headers
                    .map((h) => _cell(h,
                        bold: true, color: Colors.white))
                    .toList(),
              ),
            for (var i = 0; i < table.rows.length; i++)
              TableRow(
                decoration: BoxDecoration(
                    color: i.isEven ? Colors.white : const Color(0xFFF4F8FE)),
                children: _padRow(table.rows[i], table.headers.length)
                    .map((c) => _cell(c))
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  static List<String> _padRow(List<String> row, int n) {
    if (n <= 0) return row;
    if (row.length >= n) return row.sublist(0, n);
    return [...row, ...List.filled(n - row.length, '')];
  }

  Widget _cell(String text, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(text,
            style: TextStyle(
              fontSize: 12.5,
              color: color ?? Brand.inkNavy,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            )),
      );
}
