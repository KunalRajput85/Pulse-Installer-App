import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models/models.dart';
import '../branding/brand.dart';
import 'survey_controller.dart';

/// Final Review screen shown before submission. Lists every answered question
/// and its answer(s) — including each dependent-dropdown level — so the
/// installer can check everything. Images are intentionally NOT shown here;
/// they are still captured and uploaded through the normal flow.
class SummaryScreen extends StatefulWidget {
  final SurveyController controller;
  const SummaryScreen({super.key, required this.controller});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  bool _submitting = false;

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final app = context.read<AppState>();
    final response = await widget.controller.buildResponse();

    // Duplicate-image guard (RM Pulse Section 7) — images still submitted.
    for (final photo in response.photos) {
      await app.store.isDuplicatePhoto(photo.sha256);
    }

    await app.store.saveResponse(response.copyWith(status: SyncStatus.queued));
    app.sync.syncNow(); // fire-and-forget; stays queued offline

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF16C2A8), size: 56),
            const SizedBox(height: 12),
            Text(app.t('site_submitted'), textAlign: TextAlign.center),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context)
                ..pop() // dialog
                ..pop() // review
                ..pop(); // survey
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final items = widget.controller.buildReview();
    final gps = widget.controller.gps;

    return Scaffold(
      backgroundColor: Brand.surface,
      body: Column(
        children: [
          AuroraStepHeader(
            kicker: app.t('start'),
            title: app.t('summary_title'),
            showStepper: false,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
              children: [
                if (gps != null) _gpsCard(gps),
                for (final item in items) _reviewCard(item),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('Nothing to review yet.',
                          style: TextStyle(color: Brand.mutedInk)),
                    ),
                  ),
              ],
            ),
          ),
          AuroraActionBar(
            primaryLabel: app.t('submit'),
            primaryIcon: Icons.check_circle_outline,
            busy: _submitting,
            onBack: _submitting ? null : () => Navigator.of(context).maybePop(),
            backLabel: app.t('back'),
            onPrimary: _submitting ? null : _submit,
          ),
        ],
      ),
    );
  }

  Widget _gpsCard(GpsReading gps) {
    final ok = gps.isAuthentic;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: Brand.cardDecoration(),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: ok ? const Color(0xFFE6F7F1) : const Color(0xFFFDECEC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.location_on,
                color: ok ? const Color(0xFF16A97F) : const Color(0xFFD64545)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${gps.latitude.toStringAsFixed(6)}, ${gps.longitude.toStringAsFixed(6)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: Brand.inkNavy)),
                const SizedBox(height: 2),
                Text(
                  'Accuracy ${gps.accuracy.round()} m · ${ok ? "Authentic ✓" : "Flagged"}',
                  style: const TextStyle(fontSize: 12.5, color: Brand.mutedInk),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewCard(ReviewItem item) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: Brand.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.question,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Brand.mutedInk)),
          const SizedBox(height: 8),
          for (final row in item.rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: row.key.isEmpty
                  ? Text(row.value,
                      style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: Brand.inkNavy))
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 110,
                          child: Text('${row.key}:',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Brand.labelInk)),
                        ),
                        Expanded(
                          child: Text(row.value,
                              style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: Brand.inkNavy)),
                        ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}
