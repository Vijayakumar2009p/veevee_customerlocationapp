import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../config.dart';
import '../models/customer.dart';
import '../services/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/photo_strip.dart';
import 'customer_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

/// Profile tab: who I am, my work, history, sync, app version, log out.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.onOpenTab});
  final void Function(int tab)? onOpenTab;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<(WorkStats, WorkStats)>? _stats;
  Future<int>? _myCount;
  Future<List<HistoryItem>>? _history;
  bool _photoBusy = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_reload);
  }

  void _reload() {
    if (!mounted) return;
    final app = AppScope.read(context);
    setState(() {
      _stats = app.loadWorkStats();
      _myCount = app.loadMyCustomersCount();
      _history = app.loadHistory(limit: 8);
    });
  }

  Future<void> _changePhoto() async {
    final path = await pickPhoto(context);
    if (path == null || !mounted) return;
    setState(() => _photoBusy = true);
    try {
      await AppScope.read(context).setProfilePhoto(path);
      if (mounted) showMessage(context, 'Profile photo updated in Odoo.');
    } catch (e) {
      if (mounted) showMessage(context, 'Could not change the photo. Check the internet and try again.', error: true);
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final db = app.database;
    return Scaffold(
      backgroundColor: WaColors.background,
      body: RefreshIndicator(
        color: VV.blue,
        onRefresh: () async {
          await app.loadProfile();
          _reload();
        },
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _header(app, db),
            Transform.translate(
              offset: const Offset(0, -34),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _workCard(),
                    const SizedBox(height: 14),
                    _myCustomersCard(app),
                    const SizedBox(height: 14),
                    _historyCard(),
                    const SizedBox(height: 14),
                    _syncCard(app),
                    const SizedBox(height: 14),
                    _moreCard(app),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- header
  Widget _header(AppState app, String db) {
    final img = app.userImage;
    final status = app.needsLogin
        ? ('Log in again', VV.danger)
        : app.online
        ? ('Online', VV.success)
        : ('Offline', VV.gold);
    return Container(
      padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 12, 16, 52),
      decoration: const BoxDecoration(
        color: VV.blue,
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                child: Image.asset('assets/images/logo_mark.png', height: 22),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Profile',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: status.$2, borderRadius: BorderRadius.circular(20)),
                child: Text(
                  '● ${status.$1}',
                  style: TextStyle(
                    color: status.$2 == VV.gold ? VV.ink : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: VV.blueSoft,
                  border: Border.all(color: Colors.white, width: 3),
                ),
                clipBehavior: Clip.antiAlias,
                alignment: Alignment.center,
                child: img.isNotEmpty
                    ? Image.memory(base64Decode(img), fit: BoxFit.cover, width: 96, height: 96, gaplessPlayback: true)
                    : Text(
                        WaColors.initials(app.userName.isEmpty ? '?' : app.userName),
                        style: const TextStyle(color: VV.blue, fontSize: 34, fontWeight: FontWeight.w700),
                      ),
              ),
              Positioned(
                right: -4,
                bottom: -4,
                child: Material(
                  color: VV.gold,
                  shape: const CircleBorder(side: BorderSide(color: Colors.white, width: 2)),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _photoBusy ? null : _changePhoto,
                    child: SizedBox(
                      width: 38,
                      height: 38,
                      child: _photoBusy
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: CircularProgressIndicator(strokeWidth: 2, color: VV.ink),
                            )
                          : const Icon(Icons.photo_camera, size: 19, color: VV.ink, semanticLabel: 'Change photo'),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            app.userName.isEmpty ? 'Field staff' : app.userName,
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
          ),
          Text(app.login, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              if (app.companyName.isNotEmpty) _chip(Icons.apartment, app.companyName),
              if (db.isNotEmpty) _chip(Icons.storage_outlined, 'Database: $db'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    ),
  );

  // -------------------------------------------------------------- my work
  Widget _workCard() {
    final now = DateTime.now();
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final thisName = months[now.month - 1];
    final lastName = months[(now.month + 10) % 12].substring(0, 3);
    return _Card(
      title: 'My work · $thisName',
      trailing: Text('vs $lastName', style: const TextStyle(fontSize: 12, color: WaColors.grey)),
      child: FutureBuilder<(WorkStats, WorkStats)>(
        future: _stats,
        builder: (context, snap) {
          if (snap.hasError) {
            return _retry('Could not load your numbers. Check the internet.', _reload);
          }
          final data = snap.data;
          Widget tile(String label, int? v, int? last, Color fg, Color bg) => Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v == null ? '–' : formatIndian(v),
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: fg, height: 1.15),
                ),
                Text(
                  label,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: VV.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  v == null || last == null
                      ? ' '
                      : v > last
                      ? '▲ ${v - last} more than $lastName'
                      : v < last
                      ? '▼ ${last - v} fewer'
                      : 'Same as $lastName',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: v == null || last == null || v == last ? WaColors.grey : (v > last ? VV.success : VV.danger),
                  ),
                ),
              ],
            ),
          );
          final (c, l) = data ?? (null, null);
          return GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.45,
            children: [
              tile('Customers added', c?.customers, l?.customers, VV.blue, VV.blueSoft),
              tile('Locations set', c?.locations, l?.locations, VV.skyText, VV.skySoft),
              tile('Activities done', c?.activities, l?.activities, VV.success, VV.successSoft),
              tile('Field visits', c?.visits, l?.visits, VV.goldText, VV.goldSoft),
            ],
          );
        },
      ),
    );
  }

  Widget _myCustomersCard(AppState app) => _Card(
    padding: EdgeInsets.zero,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const CircleAvatar(
        backgroundColor: VV.blueSoft,
        child: Icon(Icons.people_alt, color: VV.blue),
      ),
      title: const Text('My customers', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      subtitle: FutureBuilder<int>(
        future: _myCount,
        builder: (context, s) => Text(
          s.hasData ? '${formatIndian(s.data!)} customers you created' : 'Customers you created',
          style: const TextStyle(color: WaColors.grey),
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: WaColors.grey),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyCustomersScreen())),
    ),
  );

  // -------------------------------------------------------------- history
  Widget _historyCard() => _Card(
    title: 'My history',
    trailing: TextButton(
      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistoryScreen())),
      child: const Text('See all'),
    ),
    child: FutureBuilder<List<HistoryItem>>(
      future: _history,
      builder: (context, snap) {
        if (snap.hasError) return _retry('Could not load your history.', _reload);
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final items = snap.data!;
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Nothing yet. Your work in the app shows here.', style: TextStyle(color: WaColors.grey)),
          );
        }
        return HistoryList(items: items);
      },
    ),
  );

  // ----------------------------------------------------------------- sync
  Widget _syncCard(AppState app) {
    final waiting = app.waitingCount;
    final ok = waiting == 0 && app.blockedCount == 0;
    return _Card(
      title: 'Sync',
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: ok ? VV.successSoft : VV.goldSoft,
                child: Icon(ok ? Icons.check : Icons.cloud_upload_outlined, color: ok ? VV.success : VV.goldText),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ok ? 'All sent to Odoo' : '$waiting waiting to send',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      app.lastSyncAt == null
                          ? 'Not synced yet'
                          : 'Last sync ${formatTime(app.lastSyncAt!)}'
                                '${_isToday(app.lastSyncAt!) ? ' today' : ', ${formatDate(app.lastSyncAt!)}'}',
                      style: const TextStyle(fontSize: 13, color: WaColors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: app.syncing
                  ? null
                  : () async {
                      await app.refreshAll();
                      _reload();
                      if (!mounted) return;
                      showMessage(
                        context,
                        !app.online
                            ? 'Still offline. Entries are safe on this phone.'
                            : app.waitingCount == 0
                            ? 'All synced.'
                            : '${app.waitingCount} entries still waiting.',
                      );
                    },
              icon: app.syncing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync),
              label: const Text('Sync now'),
            ),
          ),
        ],
      ),
    );
  }

  static bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  // ----------------------------------------------------------------- more
  Widget _moreCard(AppState app) => _Card(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        ListTile(
          leading: const Icon(Icons.info_outline, color: VV.blue),
          title: Text('App version ${AppConfig.appVersion}', style: const TextStyle(fontWeight: FontWeight.w500)),
          subtitle: Text(
            app.update != null && app.update!.isNewer
                ? 'New version ${app.update!.latestVersion} available'
                : 'Up to date',
            style: TextStyle(color: app.update != null && app.update!.isNewer ? VV.goldText : VV.success),
          ),
          trailing: TextButton(
            onPressed: () => checkForUpdatesInteractive(context, app),
            child: const Text('Check for updates'),
          ),
        ),
        const Divider(height: 1, color: WaColors.divider),
        ListTile(
          leading: const Icon(Icons.logout, color: VV.danger),
          title: const Text(
            'Log out',
            style: TextStyle(fontWeight: FontWeight.w700, color: VV.danger),
          ),
          onTap: () => confirmLogOut(context, app),
        ),
      ],
    ),
  );

  Widget _retry(String text, VoidCallback onRetry) => Row(
    children: [
      Expanded(
        child: Text(text, style: const TextStyle(color: WaColors.grey)),
      ),
      TextButton(onPressed: onRetry, child: const Text('Try again')),
    ],
  );
}

class _Card extends StatelessWidget {
  const _Card({this.title, this.trailing, required this.child, this.padding = const EdgeInsets.all(16)});
  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [BoxShadow(color: Color(0x140F2A3F), blurRadius: 2, offset: Offset(0, 1))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(title!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                ?trailing,
              ],
            ),
          ),
        child,
      ],
    ),
  );
}

/// Timeline of history items, grouped by day.
class HistoryList extends StatelessWidget {
  const HistoryList({super.key, required this.items});
  final List<HistoryItem> items;

  static String _day(DateTime d) {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'TODAY';
    if (diff == 1) return 'YESTERDAY';
    return formatDate(d);
  }

  static Color _color(String kind) => switch (kind) {
    'activity' => VV.success,
    'location' => VV.blue,
    'customer' => VV.gold,
    'photo' => VV.sky,
    _ => WaColors.grey,
  };

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    String? last;
    for (final h in items) {
      final d = _day(h.at);
      if (d != last) {
        rows.add(
          Padding(
            padding: EdgeInsets.only(top: last == null ? 0 : 10, bottom: 4),
            child: Text(
              d,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: WaColors.grey,
                letterSpacing: 0.5,
              ),
            ),
          ),
        );
        last = d;
      }
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 50,
                child: Text(
                  formatTime(h.at),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: WaColors.grey),
                ),
              ),
              Container(
                margin: const EdgeInsets.only(top: 5, right: 12),
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: _color(h.kind), shape: BoxShape.circle),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(h.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    if (h.detail.isNotEmpty) Text(h.detail, style: const TextStyle(fontSize: 13, color: WaColors.grey)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}

/// Full "My history" page.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<HistoryItem>> _items;

  @override
  void initState() {
    super.initState();
    _items = AppScope.read(context).loadHistory(limit: 100);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: WaColors.background,
    appBar: AppBar(title: const Text('My history')),
    body: FutureBuilder<List<HistoryItem>>(
      future: _items,
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(child: Text('Could not load your history. Check the internet.'));
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
              child: snap.data!.isEmpty
                  ? const Text('Nothing yet.', style: TextStyle(color: WaColors.grey))
                  : HistoryList(items: snap.data!),
            ),
          ],
        );
      },
    ),
  );
}

/// Customers this user created (Profile → My customers).
class MyCustomersScreen extends StatelessWidget {
  const MyCustomersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = app.customers.where((c) => c.isLocal || (app.uid != 0 && c.createdBy == app.uid)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Scaffold(
      appBar: AppBar(title: Text('My customers (${list.length})')),
      body: list.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Customers you add with "New customer" show here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: WaColors.grey),
                ),
              ),
            )
          : ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 76, color: WaColors.divider),
              itemBuilder: (context, i) {
                final Customer c = list[i];
                final d = c.createdLocal;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: InitialsAvatar(c.name, size: 46),
                  title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    [if (d != null) 'Added ${formatDate(d)}', if (!c.hasLocation) 'No location'].join(' · '),
                    style: TextStyle(color: c.hasLocation ? WaColors.grey : VV.danger),
                  ),
                  trailing: Icon(
                    c.hasLocation ? Icons.location_on : Icons.location_off_outlined,
                    color: c.hasLocation ? VV.success : VV.danger,
                  ),
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => CustomerScreen(customer: c))),
                );
              },
            ),
    );
  }
}
