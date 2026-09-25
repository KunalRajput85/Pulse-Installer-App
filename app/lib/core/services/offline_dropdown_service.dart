import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/offline_dropdown.dart';
import 'api_service.dart';

/// Loads and caches the cascading (dependent) dropdown tree from
/// `get_offline_dropdown_options.php`.
///
/// Offline-first: the tree is cached to disk after each successful download so
/// installers can keep filling cascading dropdowns without connectivity. The
/// keys are user-defined (they come from the API response), so nothing here is
/// tied to a specific dropdown name.
class OfflineDropdownService {
  final ApiService _api;
  OfflineDropdownService(this._api);

  static const String _cacheFileName = 'offline_dropdown.json';

  OfflineDropdownTree? _tree;
  OfflineDropdownTree? get tree => _tree;
  bool get isLoaded => _tree != null;

  Future<File> _cacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _cacheFileName));
  }

  /// Returns the tree, loading it from the in-memory copy, then the disk cache,
  /// then the network — whichever is available first. Never throws.
  Future<OfflineDropdownTree> ensureLoaded() async {
    if (_tree != null) return _tree!;
    // Try the disk cache so cascading dropdowns render instantly / offline.
    try {
      final f = await _cacheFile();
      if (await f.exists()) {
        final decoded = jsonDecode(await f.readAsString());
        _tree = OfflineDropdownTree.fromResponse(decoded);
      }
    } catch (_) {/* fall through to network */}

    // Refresh from the server in the background (updates the cache for next time).
    if (_tree == null) {
      await refresh();
    } else {
      // Best-effort refresh without blocking the first render.
      refresh();
    }
    return _tree ?? const OfflineDropdownTree({});
  }

  /// Clears the in-memory tree and the on-disk cache. Call on logout or when
  /// switching team/config so a new installer never sees the previous team's
  /// cached dropdown options.
  Future<void> clear() async {
    _tree = null;
    try {
      final f = await _cacheFile();
      if (await f.exists()) { await f.delete(); }
    } catch (_) {/* best-effort */}
  }

  /// Downloads the latest tree from `offlineDropdownUrl` and caches it.
  /// Returns true on success.
  Future<bool> refresh() async {
    try {
      final data = await _api.getDynamic(_api.offlineDropdownUrl);
      final tree = OfflineDropdownTree.fromResponse(data);
      if (tree.isEmpty) {
        // The current team's offline API returned no options — drop any stale
        // cache from a previous team so we don't keep showing old data. (A
        // network/parse error throws instead and is caught below, preserving
        // the cache for genuine offline use.)
        await clear();
        return false;
      }
      _tree = tree;
      try {
        final f = await _cacheFile();
        await f.writeAsString(jsonEncode(data));
      } catch (_) {/* cache write is best-effort */}
      return true;
    } catch (_) {
      return false;
    }
  }
}
