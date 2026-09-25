/// Model for the cascading (dependent) dropdown tree returned by
/// `get_offline_dropdown_options.php`.
///
/// The API returns a top-level JSON array, one entry per named tree:
/// ```
/// [
///   { "key": "adgramList", "dropDownItemList": [ {label,value,options:[...]}, ... ] },
///   { "key": "adgramDirectList", "dropDownItemList": [ ... ] }
/// ]
/// ```
/// The `key` is user-defined (it matches a control's `dependentDropdownKey`),
/// so nothing here is hard-coded to a particular key. Each node may carry its
/// own `options` list (the next cascade level); a node with no non-empty
/// options is a leaf. A node may also carry `otherDetails` — extra info that
/// renders as a card (and/or table) beneath the dropdown once it is selected.
library;

/// One "label: value" line of extra info shown under a selected dropdown value
/// (maps to the backend's `htmlTextColumns` entries).
class InfoRow {
  final String label;
  final String value;
  final bool bold;
  const InfoRow({required this.label, required this.value, this.bold = true});

  factory InfoRow.fromJson(Map<String, dynamic> j) => InfoRow(
        label: (j['label'] ?? '').toString(),
        value: (j['value'] ?? j['text'] ?? '').toString(),
        bold: j['boldLabel'] == true || j['bold'] == true || j['boldLabel'] == null,
      );
}

/// A simple table to render under a selected dropdown value.
class NodeTable {
  final List<String> headers;
  final List<List<String>> rows;
  const NodeTable({required this.headers, required this.rows});

  bool get isEmpty => headers.isEmpty && rows.isEmpty;

  factory NodeTable.fromJson(Map<String, dynamic> j) {
    final headers = ((j['headers'] ?? j['columns'] ?? const []) as List)
        .map((e) => e.toString())
        .toList();
    final rawRows = (j['rows'] ?? j['data'] ?? const []) as List;
    final rows = <List<String>>[];
    for (final r in rawRows) {
      if (r is List) {
        rows.add(r.map((e) => e.toString()).toList());
      } else if (r is Map) {
        // Row given as a keyed object — project onto the header order.
        rows.add(headers.map((h) => (r[h] ?? '').toString()).toList());
      }
    }
    return NodeTable(headers: headers, rows: rows);
  }
}

/// Extra content attached to a dropdown node (`otherDetails`): info lines,
/// raw HTML text, an optional table, and an optional image.
class NodeDetails {
  final List<InfoRow> info;
  final String? htmlText;
  final NodeTable? table;
  final String? imageLink;

  /// Geo-tag for this option (from otherDetails `lt`/`lg`). Used to geofence the
  /// installer against the selected location when they tap Continue.
  final double? lat;
  final double? lng;

  /// Optional per-option allowed radius in metres (`radius` /
  /// `allowed_distance_in_mtr`). Falls back to the config default when null.
  final double? radiusMeters;

  const NodeDetails({
    this.info = const [],
    this.htmlText,
    this.table,
    this.imageLink,
    this.lat,
    this.lng,
    this.radiusMeters,
  });

  bool get hasGeo =>
      lat != null && lng != null && !(lat == 0 && lng == 0);

  bool get isEmpty =>
      info.isEmpty &&
      (htmlText == null || htmlText!.trim().isEmpty) &&
      (table == null || table!.isEmpty) &&
      (imageLink == null || imageLink!.trim().isEmpty) &&
      !hasGeo;

  static double? _toD(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  static NodeDetails? fromJson(dynamic v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);

    // Info rows: accept several key names the backend might emit.
    final rawInfo = j['htmlTextList'] ??
        j['htmlTextColumns'] ??
        j['info'] ??
        j['infoList'];
    final info = <InfoRow>[];
    if (rawInfo is List) {
      for (final e in rawInfo) {
        if (e is Map) info.add(InfoRow.fromJson(Map<String, dynamic>.from(e)));
      }
    }

    final table = j['table'] is Map
        ? NodeTable.fromJson(Map<String, dynamic>.from(j['table']))
        : null;

    final details = NodeDetails(
      info: info,
      htmlText: j['htmlText']?.toString(),
      table: table,
      imageLink: j['imageLink']?.toString(),
      lat: _toD(j['lt'] ?? j['lat'] ?? j['latitude']),
      lng: _toD(j['lg'] ?? j['lng'] ?? j['longitude']),
      radiusMeters:
          _toD(j['radius'] ?? j['allowed_distance_in_mtr'] ?? j['radiusMeters']),
    );
    return details.isEmpty ? null : details;
  }
}

/// A single selectable node at one level of a cascading dropdown.
class DropdownNode {
  final String label;
  final String value;
  final List<DropdownNode> options; // children = next cascade level
  final NodeDetails? details; // otherDetails (info / html / table)

  const DropdownNode({
    required this.label,
    required this.value,
    this.options = const [],
    this.details,
  });

  /// The children that are actually selectable (drops the "Please select"
  /// placeholder rows the API includes, which have an empty value).
  List<DropdownNode> get selectableOptions =>
      options.where((o) => o.value.trim().isNotEmpty).toList();

  bool get isLeaf => selectableOptions.isEmpty;

  factory DropdownNode.fromJson(Map<String, dynamic> j) => DropdownNode(
        label: (j['label'] ?? '').toString(),
        value: (j['value'] ?? '').toString(),
        options: (j['options'] as List?)
                ?.whereType<Map>()
                .map((e) => DropdownNode.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            const [],
        details: NodeDetails.fromJson(j['otherDetails']),
      );
}

/// The full set of cascading-dropdown trees, indexed by their user-defined key.
class OfflineDropdownTree {
  final Map<String, List<DropdownNode>> byKey;

  const OfflineDropdownTree(this.byKey);

  bool get isEmpty => byKey.isEmpty;

  /// The level-1 nodes for [key], dropping any empty-value placeholder rows.
  List<DropdownNode> rootsFor(String? key) {
    if (key == null) return const [];
    final roots = byKey[key];
    if (roots == null) return const [];
    return roots.where((n) => n.value.trim().isNotEmpty).toList();
  }

  bool hasKey(String? key) => key != null && byKey.containsKey(key);

  /// Parses either the raw API array or the standard `{response: [...]}`
  /// envelope into a keyed tree.
  factory OfflineDropdownTree.fromResponse(dynamic data) {
    dynamic list = data;
    if (data is Map) list = data['response'] ?? data['data'] ?? data['dropdowns'];
    final map = <String, List<DropdownNode>>{};
    if (list is List) {
      for (final entry in list) {
        if (entry is Map) {
          final key = (entry['key'] ?? '').toString();
          if (key.isEmpty) continue;
          final items = (entry['dropDownItemList'] as List?)
                  ?.whereType<Map>()
                  .map((e) =>
                      DropdownNode.fromJson(Map<String, dynamic>.from(e)))
                  .toList() ??
              <DropdownNode>[];
          map[key] = items;
        }
      }
    }
    return OfflineDropdownTree(map);
  }
}
