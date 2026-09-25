import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models/models.dart';

/// Manual upload / outbox view (Radar "Upload" header button). Lists pending
/// responses and lets the installer retry sync on demand.
class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  bool _syncing = false;

  Future<void> _sync() async {
    setState(() => _syncing = true);
    await context.read<AppState>().sync.syncNow();
    if (mounted) setState(() => _syncing = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Upload / Outbox')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _syncing ? null : _sync,
        icon: _syncing
            ? const SizedBox(
                height: 18, width: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.sync),
        label: const Text('Sync now'),
      ),
      body: FutureBuilder<List<SurveyResponse>>(
        future: app.store.pending(),
        builder: (_, snap) {
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_done, size: 56, color: Colors.green),
                  SizedBox(height: 12),
                  Text('Everything is synced'),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final r = items[i];
              final failed = r.status == SyncStatus.failed;
              return Card(
                child: ListTile(
                  leading: Icon(
                    failed ? Icons.error : Icons.schedule,
                    color: failed ? Colors.red : Colors.orange,
                  ),
                  title: Text('Site ${r.localId.substring(0, 8)}'),
                  subtitle: Text(
                    '${r.photos.length} photos · '
                    '${r.gps != null ? "GPS ✓" : "no GPS"} · '
                    '${r.status.name}${failed && r.lastError != null ? "\n${r.lastError}" : ""}',
                  ),
                  isThreeLine: failed,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
