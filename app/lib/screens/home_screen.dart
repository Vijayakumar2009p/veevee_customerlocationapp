import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_scope.dart';
import '../config.dart';
import '../models/customer.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/app_drawer.dart';
import '../widgets/common.dart';
import 'customer_screen.dart';
import 'login_screen.dart';
import 'new_customer_screen.dart';
import 'settings_screen.dart';

enum _Filter { all, companies, noLocation, mine, waiting }

/// Contacts tab: customer list, search, filters and New customer.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.scaffoldKey, required this.onOpenTab});

  /// Lets the tab bar close the ☰ menu with the back button.
  final GlobalKey<ScaffoldState> scaffoldKey;
  final void Function(int tab) onOpenTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _mine(Customer c, int uid) => c.isLocal || (uid != 0 && c.createdBy == uid);

  List<Customer> _visible(List<Customer> all, int uid) {
    final q = _search.text;
    return all.where((c) {
      switch (_filter) {
        case _Filter.all:
          break;
        case _Filter.companies:
          if (!c.isCompany) return false;
        case _Filter.noLocation:
          if (c.hasLocation) return false;
        case _Filter.mine:
          if (!_mine(c, uid)) return false;
        case _Filter.waiting:
          if (!c.pending) return false;
      }
      return c.matches(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (_filter == _Filter.waiting && app.waitingCount == 0) _filter = _Filter.all;
    final list = _visible(app.customers, app.uid);
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final addedThisWeek = app.customers.where((c) {
      final d = c.createdLocal;
      return _mine(c, app.uid) && d != null && d.isAfter(weekAgo);
    }).length;

    return Scaffold(
      key: widget.scaffoldKey,
      backgroundColor: Colors.white,
      drawer: AppDrawer(hostContext: context),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        leading: IconButton(
          tooltip: 'Menu',
          icon: const Icon(Icons.menu, color: VV.ink),
          onPressed: () => widget.scaffoldKey.currentState?.openDrawer(),
        ),
        title: Row(
          children: [
            Image.asset('assets/images/logo_mark.png', height: 28),
            const SizedBox(width: 10),
            const Text(
              'Contacts',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700, color: VV.ink, letterSpacing: -0.2),
            ),
          ],
        ),
        actions: [
          _SyncButton(
            count: app.waitingCount,
            online: app.online && !app.needsLogin,
            busy: app.syncing || app.refreshing,
            onTap: () async {
              await app.refreshAll();
              if (!context.mounted) return;
              if (!app.online) {
                showMessage(context, 'Still offline. Entries are safe on this phone.');
              } else if (app.refreshError != null) {
                showMessage(context, app.refreshError!, error: true);
              }
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          if (app.needsLogin)
            InfoStrip(
              text: 'Your Odoo session ended. Tap to log in again.',
              icon: Icons.lock_outline,
              tone: Tone.danger,
              onTap: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen(relogin: true))),
            )
          else if (!app.online)
            InfoStrip(
              text: app.waitingCount == 0
                  ? "You're offline. You can still save locations."
                  : "You're offline. ${app.waitingCount} "
                        "${app.waitingCount == 1 ? 'entry' : 'entries'} will sync automatically.",
              icon: Icons.wifi_off,
            )
          else if (app.blockedCount > 0)
            InfoStrip(
              text:
                  '${app.blockedCount} ${app.blockedCount == 1 ? 'entry was' : 'entries were'} '
                  'refused by Odoo. Tap to check.',
              icon: Icons.error_outline,
              tone: Tone.danger,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
          Expanded(
            child: RefreshIndicator(
              color: VV.blue,
              onRefresh: app.refreshAll,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                      child: Row(
                        children: [
                          _Tile(
                            value: formatIndian(app.customers.length),
                            label: 'Customers',
                            bg: VV.blue,
                            fg: Colors.white,
                            onTap: () => setState(() => _filter = _Filter.all),
                          ),
                          const SizedBox(width: 10),
                          _Tile(
                            value: formatIndian(app.withoutLocationCount),
                            label: 'No location',
                            bg: VV.goldSoft,
                            fg: VV.goldText,
                            onTap: () => setState(() => _filter = _Filter.noLocation),
                          ),
                          const SizedBox(width: 10),
                          _Tile(
                            value: formatIndian(addedThisWeek),
                            label: 'Added this week',
                            bg: VV.successSoft,
                            fg: VV.success,
                            onTap: () => setState(() => _filter = _Filter.mine),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search name, mobile, GSTIN, city',
                          hintStyle: const TextStyle(color: WaColors.grey),
                          filled: true,
                          fillColor: WaColors.background,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 13),
                          prefixIcon: const Icon(Icons.search, color: WaColors.grey),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  icon: const Icon(Icons.close, color: WaColors.grey),
                                  onPressed: () => setState(_search.clear),
                                ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: const BorderSide(color: VV.blue, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                      child: Row(
                        children: [
                          _chip('All', _Filter.all),
                          _chip('Companies', _Filter.companies),
                          _chip('No location', _Filter.noLocation),
                          if (!AppConfig.ownContactsOnly) _chip('Mine', _Filter.mine),
                          if (app.waitingCount > 0) _chip('Waiting ${app.waitingCount}', _Filter.waiting),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Text(
                        '${formatIndian(list.length)} ${list.length == 1 ? 'contact' : 'contacts'}'
                        '${app.lastRefresh != null ? ' · updated ${formatTime(app.lastRefresh!)}' : ''}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: WaColors.grey),
                      ),
                    ),
                  ),
                  if (list.isEmpty)
                    SliverFillRemaining(hasScrollBody: false, child: _empty(app.customers.isEmpty, app.refreshing))
                  else
                    SliverPadding(
                      padding: const EdgeInsets.only(bottom: 96),
                      sliver: SliverList.builder(
                        itemCount: list.length,
                        itemBuilder: (context, i) => _CustomerRow(customer: list[i]),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: VV.blue,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('New customer', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewCustomerScreen())),
      ),
    );
  }

  Widget _chip(String label, _Filter f) {
    final selected = _filter == f;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => setState(() => _filter = f),
        labelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: selected ? VV.blue : WaColors.grey),
        selectedColor: VV.blueSoft,
        backgroundColor: WaColors.background,
        side: BorderSide.none,
        shape: const StadiumBorder(),
      ),
    );
  }

  Widget _empty(bool noCustomers, bool loading) {
    final String text;
    if (noCustomers && loading) {
      text = 'Loading customers from Odoo…';
    } else if (noCustomers) {
      text = AppConfig.ownContactsOnly
          ? 'No contacts yet. Tap New customer to add your first one.'
          : 'No customers on this phone yet. Pull down to load them from Odoo.';
    } else if (_search.text.isNotEmpty) {
      text = 'No customer matches "${_search.text}".\nTap "New customer" to add one.';
    } else {
      text = 'Nothing here.';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
      child: Column(
        children: [
          if (noCustomers && loading)
            const CircularProgressIndicator(color: VV.blue)
          else
            const Icon(Icons.person_search_outlined, size: 44, color: WaColors.grey),
          const SizedBox(height: 16),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: WaColors.grey, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.value, required this.label, required this.bg, required this.fg, required this.onTap});
  final String value;
  final String label;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: fg, height: 1.2),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: fg),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Round avatar with initials in a brand colour (same colour for the same name).
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.name, {super.key, this.size = 50, this.badge});
  final String name;
  final double size;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = WaColors.avatarFor(name);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(
              WaColors.initials(name),
              style: TextStyle(color: fg, fontSize: size * 0.36, fontWeight: FontWeight.w500),
            ),
          ),
          if (badge != null) Positioned(right: -3, bottom: -3, child: badge!),
        ],
      ),
    );
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.customer});
  final Customer customer;

  String _when(DateTime? d) {
    if (d == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];
    return formatDate(d);
  }

  @override
  Widget build(BuildContext context) {
    final c = customer;
    final when = c.pending ? 'Waiting to sync' : _when(c.createdLocal);
    final noLoc = !c.hasLocation;
    final sub = [
      if (noLoc) 'No location',
      if (c.subtitle.isNotEmpty) c.subtitle else if (c.phone.isNotEmpty) c.phone,
    ].join(' · ');
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CustomerScreen(customer: c))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InitialsAvatar(
              c.name,
              badge: c.pending
                  ? Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: VV.gold,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.arrow_upward, size: 11, color: VV.ink),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Container(
                padding: const EdgeInsets.only(bottom: 12, top: 2),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: WaColors.divider)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: VV.ink),
                          ),
                        ),
                        if (when.isNotEmpty)
                          Text(
                            when,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: c.pending ? VV.goldText : (when == 'Today' ? VV.success : WaColors.grey),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: noLoc ? VV.danger : WaColors.grey,
                              fontWeight: noLoc ? FontWeight.w500 : FontWeight.w400,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (noLoc)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: VV.dangerSoft, borderRadius: BorderRadius.circular(20)),
                            child: const Text(
                              'Set',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: VV.danger),
                            ),
                          )
                        else
                          const Icon(Icons.location_on, size: 18, color: VV.success, semanticLabel: 'Location saved'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncButton extends StatelessWidget {
  const _SyncButton({required this.count, required this.online, required this.busy, required this.onTap});
  final int count;
  final bool online;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: count > 0 ? 'Sync now, $count waiting' : 'Sync now',
      onPressed: busy ? null : onTap,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: Padding(
                    padding: EdgeInsets.all(2),
                    child: CircularProgressIndicator(strokeWidth: 2, color: VV.blue),
                  ),
                )
              : const Icon(Icons.sync, color: VV.ink),
          if (count > 0)
            Positioned(
              right: -8,
              top: -6,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(color: VV.gold, borderRadius: BorderRadius.circular(9)),
                alignment: Alignment.center,
                child: Text(
                  '$count',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: VV.ink),
                ),
              ),
            )
          else
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: online ? VV.success : VV.gold,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "New version available" dialog.
Future<void> showUpdateDialog(BuildContext context) {
  final app = AppScope.read(context);
  final update = app.update!;
  return showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.system_update_outlined, color: VV.blue, size: 32),
      title: const Text('New version available'),
      content: Text(
        'Version ${update.latestVersion} is ready. This phone has version ${AppConfig.appVersion}. '
        'Install it so syncing keeps working correctly.'
        '${update.notes.isNotEmpty ? '\n\n${update.notes}' : ''}',
      ),
      actions: [
        TextButton(
          onPressed: () {
            app.dismissUpdate();
            Navigator.pop(c);
          },
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: update.apkUrl.isEmpty
              ? null
              : () async {
                  Navigator.pop(c);
                  await launchUrl(Uri.parse(update.apkUrl), mode: LaunchMode.externalApplication);
                },
          child: const Text('Download update'),
        ),
      ],
    ),
  );
}
