import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';

/// Offline outbox. Captured [SurveyResponse]s are persisted here immediately so
/// nothing is lost if the app is closed or the device is offline; the sync
/// worker drains the queue when connectivity returns (RM Pulse Section 2).
class LocalStore {
  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'rm_pulse.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE responses (
            localId TEXT PRIMARY KEY,
            surveyId INTEGER,
            status TEXT,
            createdAt TEXT,
            payload TEXT
          )
        ''');
        await db.execute('CREATE INDEX idx_status ON responses(status)');
        // Rolling log of the last-seen photo hashes for duplicate detection.
        await db.execute('''
          CREATE TABLE photo_hashes (
            sha256 TEXT PRIMARY KEY,
            seenAt TEXT
          )
        ''');
      },
    );
    return _db!;
  }

  Future<void> saveResponse(SurveyResponse r) async {
    final db = await _database;
    await db.insert(
      'responses',
      {
        'localId': r.localId,
        'surveyId': r.surveyId,
        'status': r.status.name,
        'createdAt': r.createdAt.toIso8601String(),
        'payload': jsonEncode(r.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateStatus(String localId, SyncStatus status,
      {String? error}) async {
    final db = await _database;
    final rows = await db.query('responses',
        where: 'localId = ?', whereArgs: [localId], limit: 1);
    if (rows.isEmpty) return;
    final payload = jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>;
    payload['status'] = status.name;
    if (error != null) payload['lastError'] = error;
    await db.update(
      'responses',
      {'status': status.name, 'payload': jsonEncode(payload)},
      where: 'localId = ?',
      whereArgs: [localId],
    );
  }

  Future<List<SurveyResponse>> pending() async {
    final db = await _database;
    // Includes `syncing` so a response interrupted mid-upload (e.g. the app was
    // killed) is retried rather than stranded. Re-upload is safe: the server
    // dedupes on the response's uniqueId and each file's fileUniqueId.
    final rows = await db.query(
      'responses',
      where: 'status IN (?, ?, ?)',
      whereArgs: [
        SyncStatus.queued.name,
        SyncStatus.failed.name,
        SyncStatus.syncing.name,
      ],
      orderBy: 'createdAt ASC',
    );
    return rows
        .map((r) => SurveyResponse.fromJson(
            jsonDecode(r['payload'] as String) as Map<String, dynamic>))
        .toList();
  }

  /// Count of responses not yet confirmed uploaded (anything but `synced`).
  Future<int> unsyncedCount() async {
    final db = await _database;
    final rows = await db.rawQuery(
      "SELECT COUNT(*) c FROM responses WHERE status != ?",
      [SyncStatus.synced.name],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<Map<String, int>> counts() async {
    final db = await _database;
    final rows = await db.rawQuery(
        'SELECT status, COUNT(*) c FROM responses GROUP BY status');
    return {for (final r in rows) r['status'] as String: r['c'] as int};
  }

  /// Returns true if this photo hash was already seen (possible duplicate).
  Future<bool> isDuplicatePhoto(String sha256) async {
    final db = await _database;
    final rows = await db.query('photo_hashes',
        where: 'sha256 = ?', whereArgs: [sha256], limit: 1);
    if (rows.isNotEmpty) return true;
    await db.insert('photo_hashes',
        {'sha256': sha256, 'seenAt': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    return false;
  }
}
