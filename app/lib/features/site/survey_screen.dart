import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models/models.dart';
import '../../core/models/survey.dart';
import '../../core/services/geofence_service.dart';
import '../../core/services/location_service.dart';
import '../branding/brand.dart';
import 'control_widgets.dart';
import 'summary_screen.dart';
import 'survey_controller.dart';

/// Runs one installation capture. Before any form is shown it captures GPS and
/// applies the geofence hard-block (RM Pulse Section 4 + geofencing). If the
/// installer is outside every active zone the capture cannot proceed.
class SurveyScreen extends StatefulWidget {
  const SurveyScreen({super.key});

  @override
  State<SurveyScreen> createState() => _SurveyScreenState();
}

enum _Gate { checking, blocked, ready, error }

class _SurveyScreenState extends State<SurveyScreen> {
  late final SurveyController _controller;
  _Gate _gate = _Gate.checking;
  String _message = '';
  bool _checking = false; // verifying location on Continue

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _controller = SurveyController(app: app, pages: app.forms);
    _runGate();
  }

  Future<void> _runGate() async {
    setState(() => _gate = _Gate.checking);
    final app = context.read<AppState>();

    final permErr = await app.location.ensureReady();
    if (!mounted) return;
    if (permErr != null) {
      setState(() { _gate = _Gate.error; _message = permErr; });
      return;
    }

    GpsReading reading;
    try {
      reading = await app.location.capture(app.appConfig.features);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _gate = _Gate.error;
        _message = app.t('gps_poor');
      });
      return;
    }
    if (!mounted) return;

    // GPS authenticity hard-block.
    if (app.appConfig.features.gpsAuthenticity && !reading.isAuthentic) {
      final mock = reading.failedChecks.contains('mock_location_flag');
      setState(() {
        _gate = _Gate.blocked;
        _message = mock ? app.t('mock_detected') : app.t('gps_poor');
      });
      return;
    }

    // Geofence hard-block.
    final geo = GeofenceService.evaluate(app.appConfig.geo, reading);
    if (!geo.allowed) {
      setState(() {
        _gate = _Gate.blocked;
        _message = geo.blockReason ?? app.t('geofence_blocked');
      });
      return;
    }

    _controller.gps = reading;
    setState(() => _gate = _Gate.ready);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Scaffold(
        backgroundColor: Brand.surface,
        body: switch (_gate) {
          _Gate.checking => _gateScaffold(
              app,
              _centered(const CircularProgressIndicator(),
                  'Verifying GPS & work area…'),
            ),
          _Gate.error =>
            _gateScaffold(app, _blockView(Icons.gps_off, _message, Colors.orange)),
          _Gate.blocked => _gateScaffold(
              app, _blockView(Icons.block, _message, app.appConfig.theme.danger)),
          _Gate.ready => _form(app),
        },
      ),
    );
  }

  /// Header + centered body for the non-form gate states.
  Widget _gateScaffold(AppState app, Widget body) => Column(
        children: [
          AuroraStepHeader(
            kicker: app.t('start'),
            title: 'Preparing…',
            showStepper: false,
          ),
          Expanded(child: body),
        ],
      );

  Widget _centered(Widget top, String text) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [top, const SizedBox(height: 16), Text(text)],
        ),
      );

  Widget _blockView(IconData icon, String message, Color color) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64, color: color),
              const SizedBox(height: 16),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 24),
              GradientButton(
                label: 'Retry',
                icon: Icons.refresh,
                onPressed: _runGate,
                height: 48,
              ),
            ],
          ),
        ),
      );

  Widget _form(AppState app) {
    final page = _controller.current;
    return Column(
      children: [
        AuroraStepHeader(
          kicker: app.t('start'),
          title: page.titleFor(app.strings.lang),
          currentStep: _controller.index + 1,
          totalSteps: _controller.pages.length,
        ),
        Expanded(
          child: ListView(
            // Unique per page so field State (TextEditingControllers) is NOT
            // reused across pages — otherwise a value typed in one page's grid
            // bleeds into the next page's same-shaped grid.
            key: ValueKey('page_${page.id}'),
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
            children: _pageChildren(app, page),
          ),
        ),
        AuroraActionBar(
          primaryLabel: _controller.isLast ? app.t('submit') : app.t('next'),
          primaryIcon: _controller.isLast
              ? Icons.check_circle_outline
              : Icons.arrow_forward,
          busy: _checking,
          onBack: (_controller.index > 0 && !_checking) ? _controller.back : null,
          backLabel: app.t('back'),
          onPrimary: _checking ? null : () => _onContinue(app),
        ),
      ],
    );
  }

  /// Single, deterministic Continue flow:
  ///   1. validate the page (blocks + shows errors on any failure);
  ///   2. if the page has a cascading dropdown, guarantee its tree is loaded so
  ///      geo resolution is reliable, then ALWAYS capture GPS and run the
  ///      mock/authenticity check and (when the selected site has coordinates)
  ///      the geofence radius check — the next page never opens until this
  ///      completes successfully;
  ///   3. only then navigate.
  /// A single `_checking` flag guards the whole async section so the button is
  /// disabled and Continue can't be double-fired (no race conditions).
  Future<void> _onContinue(AppState app) async {
    if (_checking) return;
    if (!_controller.validateCurrent()) return; // errors now visible on the page

    final page = _controller.current;
    final hasDependentDropdown =
        page.controls.any((c) => c.opType == OpType.dependentDropdown);

    // Pages without a location dropdown have nothing async to verify.
    if (!hasDependentDropdown) {
      _advance();
      return;
    }

    setState(() => _checking = true);
    try {
      // Guarantee the dropdown tree is present so the selected node (and its
      // lt/lg) resolves deterministically — removes the "sometimes no geo" race.
      await app.offlineDropdown.ensureLoaded();

      final geo = _controller.currentPageGeoDetails();
      final needGeo = app.appConfig.geo.active && geo != null && geo.hasGeo;
      final gpsAuth = app.appConfig.features.gpsAuthenticity;

      // Take a fix only when it's actually needed — a geofence target exists,
      // or GPS-authenticity is enabled — but when needed it is NEVER skipped.
      if (needGeo || gpsAuth) {
        final permErr = await app.location.ensureReady();
        if (permErr != null) {
          _snack(permErr);
          return;
        }
        final reading = await app.location.capture(app.appConfig.features);
        _controller.gps = reading;

        // Mock / fake-GPS + authenticity guard.
        if (gpsAuth && !reading.isAuthentic) {
          final mock = reading.failedChecks.contains('mock_location_flag') ||
              reading.failedChecks.contains('developer_mode');
          _showAuthBlock(
            mock ? app.t('mock_detected') : app.t('gps_poor'),
            reading.failedChecks,
          );
          return; // spoofed / untrusted fix — cannot proceed
        }

        // Geofence radius check against the selected site's coordinates.
        if (needGeo) {
          final cfgRadius = app.appConfig.geo.defaultRadiusMeters;
          final radius = (geo!.radiusMeters != null && geo.radiusMeters! > 0)
              ? geo.radiusMeters!
              : (cfgRadius > 0 ? cfgRadius.toDouble() : 200.0);
          final dist = LocationService.distanceBetween(
              reading.latitude, reading.longitude, geo.lat!, geo.lng!);
          if (dist > radius) {
            _showGeoBlock(dist, radius);
            return; // outside the site — cannot proceed
          }
        }
      }
    } on Object catch (_) {
      _snack('Could not verify your location. Move to open sky and try again.');
      return;
    } finally {
      if (mounted) setState(() => _checking = false);
    }

    _advance();
  }

  void _advance() {
    if (_controller.isLast) {
      if (_controller.validateCurrent()) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SummaryScreen(controller: _controller),
        ));
      }
    } else {
      _controller.next();
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showAuthBlock(String message, List<String> failed) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFDECEC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.gpp_bad, color: Color(0xFFD64545)),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Fake location detected')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: const TextStyle(height: 1.4)),
            const SizedBox(height: 10),
            const Text(
              'Turn off any fake-GPS / mock-location app and developer mock '
              'location, then try again.',
              style: TextStyle(fontSize: 12.5, color: Brand.mutedInk, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showGeoBlock(double dist, double radius) {
    final over = (dist - radius).round();
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFDECEC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.wrong_location, color: Color(0xFFD64545)),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Outside the location')),
          ],
        ),
        content: Text(
          'You are about ${over}m outside the selected site '
          '(allowed radius ${radius.round()}m). Move to the correct location '
          'to continue.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static bool _isPhoto(OpType t) =>
      t == OpType.imageUpload ||
      t == OpType.singleImage ||
      t == OpType.multiImage;

  /// Builds the page body, laying consecutive photo controls out in a 2-column
  /// grid (numbered capture cards) so many photos fit on one page, while
  /// non-photo controls stay as full-width cards.
  List<Widget> _pageChildren(AppState app, SurveyPage page) {
    final out = <Widget>[];
    final buffer = <Control>[];
    var photoNo = 0;

    void flush() {
      if (buffer.isEmpty) return;
      final imgs = List<Control>.from(buffer);
      buffer.clear();
      out.add(_photoGrid(app, imgs, photoNo - imgs.length + 1));
    }

    for (final c in page.controls) {
      if (_isPhoto(c.opType)) {
        buffer.add(c);
        photoNo++;
      } else {
        flush();
        out.add(_controlCard(app, c));
      }
    }
    flush();
    return out;
  }

  Widget _photoGrid(AppState app, List<Control> imgs, int startNumber) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (ctx, cns) {
          final w = (cns.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var i = 0; i < imgs.length; i++)
                SizedBox(
                  width: w,
                  child: PhotoGridCard(
                    control: imgs[i],
                    controller: _controller,
                    liveCameraOnly: app.appConfig.features.liveCameraOnly,
                    lang: app.strings.lang,
                    number: startNumber + i,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Wraps each control in a soft card (labels/description controls stay flat).
  Widget _controlCard(AppState app, Control c) {
    final widget = ControlWidget(
      control: c,
      controller: _controller,
      liveCameraOnly: app.appConfig.features.liveCameraOnly,
      lang: app.strings.lang,
    );
    if (c.opType == OpType.label) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: widget,
      );
    }
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: Brand.cardDecoration(),
      child: widget,
    );
  }
}
