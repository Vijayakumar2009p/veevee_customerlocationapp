import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'activities_screen.dart';

enum _Filter { all, noLocation, waiting }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  final _scaffold = GlobalKey<ScaffoldState>();
  _Filter _filter = _Filter.all;
  bool _updateShown = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    final update = app.update;
    if (!_updateShown && update != null && update.isNewer && !app.updateDismissed) {
      _updateShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showUpdateDialog(context);
      });
    }
  }

  List<Customer> _visible(List<Customer> all) {
    final q = _search.text;
    return all.where((c) {
      if (_filter == _Filter.noLocation && c.hasLocation) return false;
      if (_filter == _Filter.waiting && !c.pending) return false;
      return c.matches(q);
    }).toList();
  }

  /// Back button on the main screen: close the menu, or ask before leaving.
  Future<void> _onBack() async {
    final scaffold = _scaffold.currentState;
    if (scaffold != null && scaffold.isDrawerOpen) {
      scaffold.closeDrawer();
      return;
    }
    final waiting = AppScope.read(context).waitingCount;
    final exit = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Exit the app?'),
        content: Text(
          waiting == 0
              ? 'Do you want to close VeeVee Field Locator?'
              : '$waiting ${waiting == 1 ? 'entry is' : 'entries are'} waiting to sync. '
                    'They are safe on this phone and will be sent next time you open the app.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Exit')),
        ],
      ),
    );
    if (exit == true) await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = _visible(app.customers);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        key: _scaffold,
        drawer: AppDrawer(
          hostContext: context,
          onShowAll: () => setState(() => _filter = _Filter.all),
          onShowNoLocation: () => setState(() => _filter = _Filter.noLocation),
          onShowWaiting: () => setState(() => _filter = _Filter.waiting),
        ),
        appBar: AppBar(
          titleSpacing: 0,
          leading: IconButton(
            tooltip: 'Menu',
            icon: const Icon(Icons.menu),
            onPressed: () => _scaffold.currentState?.openDrawer(),
          ),
          title: Row(
            children: [
              Image.asset('assets/images/logo_mark.png', width: 30, height: 27),
              const SizedBox(width: 8),
              const Text(
                'Contacts',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: VV.ink),
              ),
            ],
          ),
          actions: [
            _SyncButton(
              count: app.waitingCount,
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
            const SizedBox(width: 8),
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
            const ActivitiesBanner(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Name, mobile, GSTIN or city',
                      filled: true,
                      fillColor: VV.surfaceRaised,
                      prefixIcon: const Icon(Icons.search, color: VV.inkMuted),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(_search.clear),
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(VV.radiusMd),
                        borderSide: const BorderSide(color: VV.line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(VV.radiusMd),
                        borderSide: const BorderSide(color: VV.line),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _chip('All', _Filter.all),
                        const SizedBox(width: 8),
                        _chip('Without location', _Filter.noLocation),
                        const SizedBox(width: 8),
                        _chip('Waiting to sync', _Filter.waiting),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${formatIndian(app.customers.length)} customers · '
                    '${formatIndian(app.withoutLocationCount)} without location'
                    '${app.lastRefresh != null ? ' · updated ${formatTime(app.lastRefresh!)}' : ''}',
                    style: const TextStyle(fontSize: 12, color: VV.inkMuted, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: RefreshIndicator(
                color: VV.blue,
                onRefresh: app.refreshAll,
                child: list.isEmpty
                    ? _empty(app.customers.isEmpty, app.refreshing)
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const Divider(),
                        itemBuilder: (context, i) => _CustomerRow(customer: list[i]),
                      ),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: VV.blue,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: const Text('New customer', style: TextStyle(fontWeight: FontWeight.w600)),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewCustomerScreen())),
        ),
      ),
    );
  }

  Widget _chip(String label, _Filter f) {
    final selected = _filter == f;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => setState(() => _filter = f),
      labelStyle: TextStyle(fontWeight: FontWeight.w600, color: selected ? Colors.white : VV.ink),
      selectedColor: VV.blue,
      backgroundColor: VV.surface,
      side: BorderSide(color: selected ? VV.blue : VV.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VV.radiusMd)),
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
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
          child: Column(
            children: [
              if (noCustomers && loading)
                const CircularProgressIndicator(color: VV.blue)
              else
                const Icon(Icons.search_off, size: 40, color: VV.inkMuted),
              const SizedBox(height: 16),
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: VV.inkMuted, height: 1.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.customer});
  final Customer customer;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CustomerScreen(customer: customer))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CustomerAvatar(customer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    customer.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: VV.inkMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            LocationBadge(customer),
          ],
        ),
      ),
    );
  }
}

class _SyncButton extends StatelessWidget {
  const _SyncButton({required this.count, required this.busy, required this.onTap});
  final int count;
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
