import 'package:geolocator/geolocator.dart';

import '../models/app_config.dart';
import '../models/models.dart';
import 'device_service.dart';

/// Captures a GPS fix and runs the multi-layer authenticity verification
/// (RM Pulse Section 4). Each failed layer is recorded by name so the reason
/// can be shown to the installer and stored in the audit trail.
class LocationService {
  final DeviceService _deviceService;
  LocationService(this._deviceService);

  /// Ensures location services + permission are available.
  Future<String?> ensureReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Location services are turned off. Please enable GPS.';
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return 'Location permission is required to capture sites.';
    }
    return null;
  }

  DeviceIdentity? _device; // cached — device profile is constant during a session

  /// Warm up the GPS (fire-and-forget) when the site screen opens, so the first
  /// [capture] can reuse a ready fix instead of waiting on a cold sensor.
  Future<void> warmUp() async {
    try {
      await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (_) {/* best-effort */}
  }

  /// Captures a reading and evaluates the authenticity layers against the
  /// current [features] configuration.
  Future<GpsReading> capture(FeatureConfig features) async {
    // Acquire the BEST fix over a short window instead of accepting the first
    // (usually poor) reading — GPS accuracy tightens as more satellites lock.
    final Position pos = await _acquireBestFix(features.maxAccuracyMeters);

    _device ??= await _deviceService.read();
    final device = _device!;
    final failed = <String>[];

    // Layer 1: OS mock-location flag on the fix itself.
    final mocked = pos.isMocked;
    if (features.blockMockLocation && mocked) failed.add('mock_location_flag');

    // Layer 2: horizontal accuracy within configured limit.
    if (features.gpsAuthenticity && pos.accuracy > features.maxAccuracyMeters) {
      failed.add('poor_accuracy');
    }
    // Layer 3: rooted / jailbroken device.
    if (features.blockRootedDevice && device.isRooted) {
      failed.add('rooted_device');
    }
    // Layer 4: emulator / non-physical device.
    if (device.isRealDevice == false) failed.add('emulator');
    // Layer 5: developer mode with mock-app risk.
    if (device.isDevelopmentModeEnabled && mocked) failed.add('developer_mode');
    // Layer 6: implausible coordinates (null island / out of range).
    if ((pos.latitude == 0 && pos.longitude == 0) ||
        pos.latitude.abs() > 90 ||
        pos.longitude.abs() > 180) {
      failed.add('implausible_coordinates');
    }
    // Layer 7: impossible speed (teleport) — a jump faster than ~360 km/h.
    if (pos.speed.isFinite && pos.speed > 100) failed.add('impossible_speed');
    // Layer 8: zero/again-mocked accuracy sentinel (some fake apps report 0).
    if (pos.accuracy <= 0) failed.add('invalid_accuracy');
    // Layer 9: stale timestamp (fix older than 30s => possibly replayed).
    final age = DateTime.now().difference(pos.timestamp).inSeconds;
    if (age.abs() > 30) failed.add('stale_fix');

    return GpsReading(
      latitude: pos.latitude,
      longitude: pos.longitude,
      accuracy: pos.accuracy,
      altitude: pos.altitude,
      speed: pos.speed,
      capturedAt: DateTime.now(),
      isMocked: mocked,
      failedChecks: failed,
    );
  }

  /// Returns the best GPS fix available within a short time budget. A recent,
  /// accurate last-known fix is used instantly; otherwise it samples live fixes
  /// for up to ~18s, returning the moment accuracy meets [targetAccuracy] and
  /// otherwise the most accurate fix seen (so a slightly-loose fix is used
  /// rather than false-blocking). Only if nothing is obtained does it fall back
  /// to a single reading.
  Future<Position> _acquireBestFix(double targetAccuracy) async {
    final last = await Geolocator.getLastKnownPosition();
    if (last != null &&
        last.accuracy > 0 &&
        last.accuracy <= targetAccuracy &&
        DateTime.now().difference(last.timestamp).inSeconds.abs() <= 12) {
      return last;
    }

    Position? best;
    final deadline = DateTime.now().add(const Duration(seconds: 18));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final p = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 8),
        );
        if (p.accuracy > 0 && (best == null || p.accuracy < best!.accuracy)) {
          best = p;
        }
        if (p.accuracy > 0 && p.accuracy <= targetAccuracy) return p;
      } catch (_) {/* keep trying until the deadline */}
      await Future.delayed(const Duration(milliseconds: 800));
    }
    if (best != null) return best!;
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 10),
    );
  }

  /// Straight-line distance in metres between two coordinates.
  static double distanceBetween(
          double lat1, double lng1, double lat2, double lng2) =>
      Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
}
