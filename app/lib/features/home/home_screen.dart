import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models/rework_site.dart';
import '../auth/login_screen.dart';
import '../branding/brand.dart';
import '../site/survey_screen.dart';
import 'upload_screen.dart';

/// Home / dashboard. Matches the client mockup: a branded blue header with the
/// team name, a summary dashboard fed ONLY by the server's `summaryUrl`, an
/// "Installation guidelines" popup, the primary START INSTALLATION action, and
/// a bottom navigation bar. Language + refresh + logout live in the header menu.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<dynamic>> _summary;
  Future<List<ReworkSite>>? _rework;
  String _team = '';
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _summary = app.fetchSummary();
    app.teamName().then((n) {
      if (mounted && n != null && n.isNotEmpty) setState(() => _team = n);
    });
  }

  void _reloadSummary() => setState(() => _summary = context.read<AppState>().fetchSummary());

  Future<void> _refreshAll() async {
    await context.read<AppState>().refreshConfig();
    _reloadSummary();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Scaffold(
      backgroundColor: Brand.surface,
      body: Column(
        children: [
          _header(app),
          Expanded(
            child: _tab == 3 ? _tasksBody(app) : _dashboardBody(app),
          ),
        ],
      ),
      bottomNavigationBar: _bottomNav(context, Brand.indigo),
    );
  }

  Widget _dashboardBody(AppState app) {
    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _SummaryView(future: _summary, onRetry: _reloadSummary),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              foregroundColor: Brand.indigo,
              side: const BorderSide(color: Brand.fieldBorder),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.list_alt),
            label: const Text('Installation guidelines'),
            onPressed: () => _showGuidelines(context, app, Brand.indigo),
          ),
          const SizedBox(height: 12),
          GradientButton(
            label: app.t('start'),
            icon: Icons.play_arrow,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SurveyScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tasksBody(AppState app) {
    return RefreshIndicator(
      onRefresh: () async => setState(() => _rework = app.fetchReworkSites()),
      child: FutureBuilder<List<ReworkSite>>(
        future: _rework ??= app.fetchReworkSites(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final sites = snap.data ?? const <ReworkSite>[];
          if (sites.isEmpty) {
            return ListView(
              children: [
                const SizedBox(height: 90),
                Icon(Icons.task_alt, size: 60, color: Brand.indigo.withOpacity(0.4)),
                const SizedBox(height: 12),
                const Center(
                  child: Text('No rework sites assigned',
                      style: TextStyle(color: Brand.mutedInk, fontSize: 15)),
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text('Rework sites (${sites.length})',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Brand.inkNavy)),
              ),
              for (final s in sites) _ReworkCard(site: s),
            ],
          );
        },
      ),
    );
  }

  // ── Branded header ─────────────────────────────────────────────────────────
  Widget _header(AppState app) {
    const fg = Colors.white;
    return Container(
      decoration: const BoxDecoration(
        gradient: Brand.meshGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 8, 18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Team',
                        style: TextStyle(color: fg.withOpacity(0.85), fontSize: 11.5)),
                    const SizedBox(height: 2),
                    Text(_team.isEmpty ? app.t('app_title') : _team,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: fg, fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              // Language switch
              PopupMenuButton<String>(
                icon: Icon(Icons.translate, color: fg),
                tooltip: 'Language',
                onSelected: app.setLanguage,
                itemBuilder: (_) => app.appConfig.language.supported
                    .map((l) => PopupMenuItem(value: l, child: Text(l.toUpperCase())))
                    .toList(),
              ),
              // Settings menu: refresh + logout
              PopupMenuButton<String>(
                icon: Icon(Icons.settings, color: fg),
                tooltip: 'Menu',
                onSelected: (v) {
                  if (v == 'refresh') _refreshAll();
                  if (v == 'logout') _confirmLogout();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'refresh',
                    child: Row(children: [
                      Icon(Icons.refresh, size: 20),
                      SizedBox(width: 10),
                      Text('Refresh'),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'logout',
                    child: Row(children: [
                      Icon(Icons.logout, size: 20, color: Colors.red),
                      SizedBox(width: 10),
                      Text('Logout', style: TextStyle(color: Colors.red)),
                    ]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Bottom navigation ──────────────────────────────────────────────────────
  Widget _bottomNav(BuildContext context, Color active) {
    final items = const [
      (Icons.home_outlined, Icons.home, 'Home'),
      (Icons.cloud_upload_outlined, Icons.cloud_upload, 'Upload'),
      (Icons.bar_chart_outlined, Icons.bar_chart, 'Report'),
      (Icons.build_outlined, Icons.build, 'Rework'),
    ];
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE6EBF1))),
        ),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: List.generate(items.length, (i) {
            final (off, on, label) = items[i];
            final selected = i == _tab;
            return Expanded(
              child: InkWell(
                onTap: () => _onTab(i),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(selected ? on : off,
                        size: 22, color: selected ? active : Colors.grey),
                    const SizedBox(height: 2),
                    Text(label,
                        style: TextStyle(
                            fontSize: 11,
                            color: selected ? active : Colors.grey,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  void _onTab(int i) {
    if (i == 1) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const UploadScreen()));
      return;
    }
    if (i == 2) {
      // Report = the summary dashboard; just refresh it.
      _reloadSummary();
    }
    if (i == 3) {
      // Tasks = rework sites; load them the first time the tab is opened.
      _rework ??= context.read<AppState>().fetchReworkSites();
    }
    setState(() => _tab = i == 1 ? 0 : i);
  }

  // ── Logout ─────────────────────────────────────────────────────────────────
  Future<void> _confirmLogout() async {
    final app = context.read<AppState>();
    // Block logout while there is unsynced data in the Upload queue — logging
    // out clears the session/token and would strand that data.
    final pending = await app.store.unsyncedCount();
    if (!mounted) return;
    if (pending > 0) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Upload pending data first'),
          content: Text(
              'You have $pending unsynced ${pending == 1 ? "entry" : "entries"} in the Upload queue. '
              'Please upload all pending data before logging out — logging out now would lose it.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const UploadScreen()));
              },
              child: const Text('Go to Upload'),
            ),
          ],
        ),
      );
      return; // do NOT log out while data is pending
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need your username and password to sign in again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await context.read<AppState>().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  // ── Guidelines popup ───────────────────────────────────────────────────────
  /// Guidelines come from the JSON config (`guidelines`, multilingual) in the
  /// active language. The static list is only a fallback for when the server
  /// JSON doesn't provide any.
  void _showGuidelines(BuildContext context, AppState app, Color accent) {
    const fallback = [
      'Reach the assigned site and stay inside the geofence zone.',
      'Wait for good GPS accuracy before adding the site.',
      'Capture all required photos in order using the live camera.',
      'Match the creative & dimension to your allocation.',
      'Gallery uploads are not allowed — live camera only.',
      'Review the summary, then submit (saved & auto-synced offline).',
    ];
    final fromJson = app.appConfig.guidelines.forLang(app.strings.lang);
    final guidelines = fromJson.isNotEmpty ? fromJson : fallback;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: const Color(0xFFD8DFE8),
                    borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Icon(Icons.list_alt, color: accent, size: 20),
              const SizedBox(width: 8),
              const Text('Installation guidelines',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 12),
            ...List.generate(guidelines.length, (i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 22, height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: accent.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6)),
                        child: Text('${i + 1}',
                            style: TextStyle(
                                color: accent, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(guidelines[i], style: const TextStyle(fontSize: 13.5))),
                    ],
                  ),
                )),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.check),
              label: const Text('Got it'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders the summary sections exactly as the server's `summaryUrl` returns
/// them. Supports both the `{title, summaryList:[{label,value}]}` shape and the
/// `{summaryTitle, summaryData:{labelList,cardList}}` shape.
class _SummaryView extends StatelessWidget {
  final Future<List<dynamic>> future;
  final VoidCallback onRetry;
  const _SummaryView({required this.future, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return _message(
            icon: Icons.cloud_off,
            title: 'Could not load dashboard',
            subtitle: snap.error.toString(),
            onRetry: onRetry,
          );
        }
        final sections = snap.data ?? const [];
        if (sections.isEmpty) {
          return _message(
            icon: Icons.dashboard_customize_outlined,
            title: 'No summary yet',
            subtitle: 'Your dashboard will appear here once the server returns summary data.',
            onRetry: onRetry,
          );
        }
        return Column(
          children: sections
              .whereType<Map>()
              .map((s) => _section(Map<String, dynamic>.from(s)))
              .toList(),
        );
      },
    );
  }

  Widget _section(Map<String, dynamic> s) {
    final title = (s['title'] ?? s['summaryTitle'] ?? '').toString();
    final rows = <Map<String, dynamic>>[];
    void addAll(dynamic list) {
      if (list is List) {
        for (final e in list) {
          if (e is Map) rows.add(Map<String, dynamic>.from(e));
        }
      }
    }

    addAll(s['summaryList']);
    if (s['summaryData'] is Map) {
      final d = Map<String, dynamic>.from(s['summaryData']);
      addAll(d['labelList']);
      addAll(d['cardList']);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            if (rows.isEmpty)
              const Text('—', style: TextStyle(color: Colors.grey))
            else
              ...rows.map((r) {
                final label = (r['label'] ?? r['key'] ?? '').toString();
                final value = (r['value'] ?? '').toString();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(label, style: const TextStyle(color: Color(0xFF5A6B7B))),
                      ),
                      const SizedBox(width: 12),
                      Text(value,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _message({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onRetry,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 40, color: Colors.grey),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: Colors.grey)),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single rework-site card shown in the Tasks tab.
class _ReworkCard extends StatelessWidget {
  final ReworkSite site;
  const _ReworkCard({required this.site});

  @override
  Widget build(BuildContext context) {
    final high = site.priority.toLowerCase().contains('high') ||
        site.priority.toLowerCase().contains('urgent');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: Brand.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _chip('Rework', const Color(0xFFEAF2FF), Brand.indigo),
              if (site.priority.isNotEmpty) ...[
                const SizedBox(width: 8),
                _chip(site.priority,
                    high ? const Color(0xFFFDECEC) : const Color(0xFFEDF6EE),
                    high ? const Color(0xFFD64545) : const Color(0xFF2E9E5B)),
              ],
              const Spacer(),
              if (site.assignedOn.isNotEmpty)
                Text(site.assignedOn,
                    style: const TextStyle(fontSize: 11.5, color: Brand.mutedInk)),
            ],
          ),
          const SizedBox(height: 10),
          Text(site.siteName.isEmpty ? 'Site #${site.id}' : site.siteName,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: Brand.inkNavy)),
          if (site.brand.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(site.brand,
                  style: const TextStyle(fontSize: 12.5, color: Brand.mutedInk)),
            ),
          if (site.address.isNotEmpty) ...[
            const SizedBox(height: 8),
            _iconRow(Icons.location_on_outlined, site.address),
          ],
          if (site.contactNo.isNotEmpty) ...[
            const SizedBox(height: 4),
            _iconRow(Icons.call_outlined, site.contactNo),
          ],
          if (site.reason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF6E9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF3E0C0)),
              ),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 13, color: Color(0xFF8A5A12), height: 1.35),
                  children: [
                    const TextSpan(
                        text: 'Reason: ',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    TextSpan(text: site.reason),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          GradientButton(
            label: 'Start rework',
            icon: Icons.play_arrow,
            height: 46,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SurveyScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w700)),
      );

  Widget _iconRow(IconData icon, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Brand.mutedInk),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 13, color: Color(0xFF3A4A63))),
          ),
        ],
      );
}
