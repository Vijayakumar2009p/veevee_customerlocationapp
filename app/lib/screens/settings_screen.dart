import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../config.dart';
import '../models/pending_action.dart';
import '../services/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'home_screen.dart';
import 'your_name_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      backgroundColor: VV.surfaceRaised,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionLabel('Waiting to sync'),
          _card(
            Column(
              children: [
                if (app.queue.isEmpty)
                  const ListTile(
                    leading: Icon(Icons.check_circle_outline, color: VV.success),
                    title: Text('Everything is in Odoo'),
                  )
                else
                  for (final a in app.queue) ...[_PendingRow(action: a), const Divider()],
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: app.syncing || app.refreshing
                          ? null
                          : () async {
                              await app.refreshAll();
                              if (!context.mounted) return;
                              showMessage(
                                context,
                                !app.online
                                    ? 'Still offline. Entries are safe on this phone.'
                                    : app.queue.isEmpty
                                    ? 'All synced. Customer list updated.'
                                    : '${app.queue.length} entries still waiting.',
                              );
                            },
                      icon: app.syncing || app.refreshing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.sync),
                      label: const Text('Sync now'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            app.lastRefresh == null
                ? 'Customer list not loaded yet.'
                : 'Customer list updated ${formatDateTime(app.lastRefresh!)}. '
                      'Entries sync by themselves when you are online.',
            style: const TextStyle(fontSize: 12, color: VV.inkMuted),
          ),
          const SizedBox(height: 24),
          const SectionLabel('You'),
          _card(
            ListTile(
              title: Text(
                AppConfig.sharedLogin ? 'Your name' : 'Your name (from your Odoo login)',
                style: const TextStyle(fontSize: 13, color: VV.inkMuted),
              ),
              subtitle: Text(
                app.userName,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: VV.ink),
              ),
              // Own Odoo login per person: the name comes from Odoo.
              trailing: !AppConfig.sharedLogin
                  ? null
                  : TextButton(
                      onPressed: () async {
                        final yes = await showDialog<bool>(
                          context: context,
                          builder: (d) => AlertDialog(
                            title: const Text('Change your name?'),
                            content: Text(
                              'Your name "${app.userName}" is written in every note sent to Odoo. '
                              'Do you really want to change it?',
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('No')),
                              FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Yes, change')),
                            ],
                          ),
                        );
                        if (yes == true && context.mounted) {
                          Navigator.of(
                            context,
                          ).push(MaterialPageRoute(builder: (_) => const YourNameScreen(editing: true)));
                        }
                      },
                      child: const Text('Change'),
                    ),
            ),
          ),
          const SizedBox(height: 24),
          const SectionLabel('Connection'),
          InfoTable([
            ('Server', Uri.tryParse(app.serverUrl)?.host ?? app.serverUrl),
            ('Database', app.database),
            ('Odoo login', app.odooUserName.isNotEmpty ? '${app.odooUserName} (${app.login})' : app.login),
            ('Status', app.needsLogin ? 'Log in again' : (app.online ? 'Online' : 'Offline')),
            ('Odoo module', app.hasAddon ? 'Installed' : 'Not installed'),
            ('App version', AppConfig.appVersion),
          ]),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _checkUpdate(context, app),
            icon: const Icon(Icons.system_update_outlined),
            label: const Text('Check for updates'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: VV.danger),
            onPressed: () => _logOut(context, app),
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
          ),
        ],
      ),
    );
  }

  Widget _card(Widget child) => Container(
    decoration: BoxDecoration(
      color: VV.surface,
      border: Border.all(color: VV.line),
      borderRadius: BorderRadius.circular(VV.radiusMd),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

/// "Check for updates" (Settings and the side menu).
Future<void> checkForUpdatesInteractive(BuildContext context, AppState app) => _checkUpdate(context, app);

/// "Log out" with confirmation (Settings and the side menu).
Future<void> confirmLogOut(BuildContext context, AppState app) => _logOut(context, app);

Future<void> _checkUpdate(BuildContext context, AppState app) async {
  if (!app.hasAddon) {
    showMessage(context, 'Update check needs the VeeVee Field Locator module in Odoo.');
    return;
  }
  final info = await app.checkForUpdate();
  if (!context.mounted) return;
  if (info == null) {
    showMessage(context, 'Could not check for updates. Are you online?', error: true);
  } else if (info.isNewer) {
    await showUpdateDialog(context);
  } else {
    showMessage(context, "You're on the latest version (${AppConfig.appVersion}).");
  }
}

Future<void> _logOut(BuildContext context, AppState app) async {
  final waiting = app.queue.length;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Log out?'),
      content: Text(
        waiting == 0
            ? 'You will need the login and password to use the app again.'
            : '$waiting ${waiting == 1 ? 'entry has' : 'entries have'} not reached Odoo yet '
                  'and will be lost. Sync first if you can.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: VV.danger),
          onPressed: () => Navigator.pop(c, true),
          child: Text(waiting == 0 ? 'Log out' : 'Log out anyway'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  Navigator.of(context).popUntil((r) => r.isFirst);
  await app.logOut();
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({required this.action});
  final PendingAction action;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    final waitingForCustomer =
        action.kind != PendingAction.create && action.partnerId == null && !app.refToId.containsKey(action.partnerRef);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(action.customerName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    Text(
                      '${action.label} · ${formatDateTime(action.createdAt)}',
                      style: const TextStyle(fontSize: 13, color: VV.inkMuted),
                    ),
                  ],
                ),
              ),
              StatusBadge(
                action.blocked ? 'Refused' : (waitingForCustomer ? 'After customer' : 'Waiting'),
                tone: action.blocked ? Tone.danger : Tone.gold,
              ),
            ],
          ),
          if (action.blocked) ...[
            const SizedBox(height: 8),
            Text(action.lastError, style: const TextStyle(fontSize: 13, color: VV.danger)),
            Row(
              children: [
                TextButton(onPressed: () => app.retry(action), child: const Text('Try again')),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: VV.danger),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Delete this entry?'),
                        content: Text(
                          action.kind == PendingAction.create
                              ? 'The new customer and its location will be removed from this phone.'
                              : action.kind == PendingAction.photos
                              ? 'These photos will be removed from this phone.'
                              : action.kind == PendingAction.visitCreate
                              ? 'This planned activity will be removed from this phone.'
                              : action.kind == PendingAction.visitDone
                              ? 'The activity will not be marked done; it shows again in My Activities.'
                              : action.kind == PendingAction.activityDate
                              ? 'The new date will not be sent to Odoo.'
                              : 'This location will be removed from this phone.',
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                        ],
                      ),
                    );
                    if (ok == true) await app.discard(action);
                  },
                  child: const Text('Delete'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
