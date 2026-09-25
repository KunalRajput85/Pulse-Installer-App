/// Runtime data models: GPS readings and survey responses (the data captured
/// by the installer that gets queued offline and uploaded).
library;

/// A GPS fix plus the outcome of the multi-layer authenticity verification
/// (RM Pulse Section 4 / Radar geo-tagging).
class GpsReading {
  final double latitude;
  final double longitude;
  final double accuracy; // metres (lower is better)
  final double? altitude;
  final double? speed;
  final DateTime capturedAt;
  final bool isMocked;
  final List<String> failedChecks;

  const GpsReading({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.capturedAt,
    this.altitude,
    this.speed,
    this.isMocked = false,
    this.failedChecks = const [],
  });

  bool get isAuthentic => failedChecks.isEmpty;

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'altitude': altitude,
        'speed': speed,
        'capturedAt': capturedAt.toIso8601String(),
        'isMocked': isMocked,
        'failedChecks': failedChecks,
      };

  factory GpsReading.fromJson(Map<String, dynamic> m) => GpsReading(
        latitude: (m['latitude'] as num).toDouble(),
        longitude: (m['longitude'] as num).toDouble(),
        accuracy: (m['accuracy'] as num).toDouble(),
        altitude: (m['altitude'] as num?)?.toDouble(),
        speed: (m['speed'] as num?)?.toDouble(),
        capturedAt: DateTime.parse(m['capturedAt']),
        isMocked: m['isMocked'] == true,
        failedChecks: (m['failedChecks'] as List?)?.cast<String>() ?? const [],
      );
}

/// One captured photo (answer to an optype=6 control).
class CapturedPhoto {
  final int controlId;
  final String localPath;
  final String sha256; // duplicate-image detection
  final String? caption;
  final DateTime capturedAt;

  /// Stable per-file identifier sent to the file-upload endpoint and referenced
  /// from the survey payload as `fileUniqueId`, so the server can tie a stored
  /// file back to the question it answers.
  final String fileUniqueId;

  const CapturedPhoto({
    required this.controlId,
    required this.localPath,
    required this.sha256,
    required this.capturedAt,
    required this.fileUniqueId,
    this.caption,
  });

  Map<String, dynamic> toJson() => {
        'controlId': controlId,
        'localPath': localPath,
        'sha256': sha256,
        'caption': caption,
        'capturedAt': capturedAt.toIso8601String(),
        'fileUniqueId': fileUniqueId,
      };

  factory CapturedPhoto.fromJson(Map<String, dynamic> m) => CapturedPhoto(
        controlId: (m['controlId'] as num).toInt(),
        localPath: m['localPath'],
        sha256: m['sha256'],
        caption: m['caption'],
        capturedAt: DateTime.parse(m['capturedAt']),
        // Fall back to a derived id for rows persisted before this field existed.
        fileUniqueId: (m['fileUniqueId'] ??
                m['capturedAt']?.toString().hashCode.toString() ??
                '')
            .toString(),
      );
}

enum SyncStatus { draft, queued, syncing, synced, failed }

/// A completed survey ready for offline storage + upload.
///
/// [answers] maps control id -> value. Values are primitives or lists so the
/// whole thing serialises to JSON directly. Photos are tracked separately so
/// their binaries can be uploaded to the media endpoint.
class SurveyResponse {
  final String localId; // client UUID
  final int surveyId;
  final int configVersion;
  final String installerId;
  final String deviceId;
  final GpsReading? gps;
  final double? distanceTravelledMeters; // Radar Phase 2 requirement
  final Map<int, dynamic> answers;
  final List<CapturedPhoto> photos;

  /// The structured submission payload: one entry per survey page,
  /// `{pageId, quesList:[{quesId, label?, ansMultiChoice|ansGrid|fileUniqueId|ans}]}`.
  /// Built at capture time (see [SurveyController.buildStructuredPages]) so it
  /// survives config changes between capture and upload.
  final List<Map<String, dynamic>> formPages;

  final DateTime createdAt;
  final SyncStatus status;
  final String? lastError;

  const SurveyResponse({
    required this.localId,
    required this.surveyId,
    required this.configVersion,
    required this.installerId,
    required this.deviceId,
    required this.answers,
    required this.photos,
    required this.createdAt,
    this.formPages = const [],
    this.gps,
    this.distanceTravelledMeters,
    this.status = SyncStatus.draft,
    this.lastError,
  });

  SurveyResponse copyWith({SyncStatus? status, String? lastError}) => SurveyResponse(
        localId: localId,
        surveyId: surveyId,
        configVersion: configVersion,
        installerId: installerId,
        deviceId: deviceId,
        gps: gps,
        distanceTravelledMeters: distanceTravelledMeters,
        answers: answers,
        photos: photos,
        formPages: formPages,
        createdAt: createdAt,
        status: status ?? this.status,
        lastError: lastError ?? this.lastError,
      );

  Map<String, dynamic> toJson() => {
        'localId': localId,
        'surveyId': surveyId,
        'configVersion': configVersion,
        'installerId': installerId,
        'deviceId': deviceId,
        'gps': gps?.toJson(),
        'distanceTravelledMeters': distanceTravelledMeters,
        'answers': answers.map((k, v) => MapEntry(k.toString(), v)),
        'photos': photos.map((p) => p.toJson()).toList(),
        'formPages': formPages,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
      };

  factory SurveyResponse.fromJson(Map<String, dynamic> m) => SurveyResponse(
        localId: m['localId'],
        surveyId: (m['surveyId'] as num).toInt(),
        configVersion: (m['configVersion'] as num?)?.toInt() ?? 0,
        installerId: m['installerId'] ?? '',
        deviceId: m['deviceId'] ?? '',
        gps: m['gps'] == null ? null : GpsReading.fromJson(Map<String, dynamic>.from(m['gps'])),
        distanceTravelledMeters: (m['distanceTravelledMeters'] as num?)?.toDouble(),
        answers: (m['answers'] as Map?)?.map(
              (k, v) => MapEntry(int.parse(k.toString()), v),
            ) ??
            {},
        photos: (m['photos'] as List? ?? [])
            .map((p) => CapturedPhoto.fromJson(Map<String, dynamic>.from(p)))
            .toList(),
        formPages: (m['formPages'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
        createdAt: DateTime.parse(m['createdAt']),
        status: SyncStatus.values.firstWhere(
          (e) => e.name == m['status'],
          orElse: () => SyncStatus.queued,
        ),
        lastError: m['lastError'],
      );
}
