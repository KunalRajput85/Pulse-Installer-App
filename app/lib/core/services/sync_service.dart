import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import 'api_service.dart';
import 'local_store.dart';

/// Drains the offline outbox to your backend:
///   1. each captured photo -> file.php (multipart)
///   2. the survey response  -> data.php (JSON array)
/// Runs on a timer and whenever connectivity is restored.
class SyncService {
  final ApiService _api;
  final LocalStore _store;

  Timer? _timer;
  bool _running = false;

  SyncService(this._api, this._store);

  void start() {
    _timer ??= Timer.periodic(AppEnv.syncInterval, (_) => syncNow());
    Connectivity().onConnectivityChanged.listen((result) {
      if (!result.contains(ConnectivityResult.none)) syncNow();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> syncNow() async {
    if (_running || !_api.hasToken) return;
    final conn = await Connectivity().checkConnectivity();
    if (conn.contains(ConnectivityResult.none)) return;

    _running = true;
    try {
      for (final r in await _store.pending()) {
        await _uploadOne(r);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _uploadOne(SurveyResponse r) async {
    await _store.updateStatus(r.localId, SyncStatus.syncing);
    try {
      final lt = r.gps?.latitude ?? 0;
      final lg = r.gps?.longitude ?? 0;
      final dt = (r.gps?.capturedAt ?? r.createdAt).millisecondsSinceEpoch;

      // 1. Upload each photo binary to file.php. Each file carries the same
      //    fileUniqueId that the survey payload references, so the server can
      //    link the stored file to its question.
      for (final photo in r.photos) {
        final file = File(photo.localPath);
        if (!await file.exists()) continue;
        final form = FormData.fromMap({
          'file': await MultipartFile.fromFile(file.path,
              filename: '${photo.fileUniqueId}.jpg'),
          'fileUniqueId': photo.fileUniqueId,
          // mob_img_id must be the PER-IMAGE id (fileUniqueId), not the survey id.
          // Otherwise every photo shares the same (uni_id, mob_img_id) and file.php's
          // dedup keeps only the first row. uni_id stays shared via surveyUniqId below.
          'uniqId': photo.fileUniqueId,
          'surveyId': r.surveyId,
          'pageId': 0, // page not tracked per photo in MVP
          'quesId': photo.controlId,
          'surveyUniqId': r.localId,
          'lt': lt,
          'lg': lg,
          'dt': dt,
        });
        final envelope = await _api.postMultipart(_api.fileUploadUrl, form);
        ApiService.unwrap(envelope); // throws on non-200
      }

      // 2. Upload the survey response to data.php as a one-item array. The
      //    answers are sent in the structured page/quesList format.
      final payload = [
        {
          'uniqueId': r.localId,
          'surveyId': r.surveyId,
          'surveyTime': 0,
          'lt': lt,
          'lg': lg,
          'dt': dt,
          'appFormList': r.formPages,
          'totalDistance': 0,
          'distanceInMeters': r.distanceTravelledMeters ?? 0,
        }
      ];
      final envelope = await _api.postJson(_api.dataUploadUrl, payload);
      ApiService.unwrap(envelope);

      await _store.updateStatus(r.localId, SyncStatus.synced);
    } catch (e) {
      await _store.updateStatus(r.localId, SyncStatus.failed, error: e.toString());
    }
  }
}
