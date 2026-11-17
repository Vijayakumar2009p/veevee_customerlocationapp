import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_scope.dart';
import '../config.dart';
import '../screens/new_customer_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/activities_screen.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'common.dart';

/// The ☰ side menu on the customer list.
class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.onShowAll,
    required this.onShowNoLocation,
    required this.onShowWaiting,
    required this.hostContext,
  });

  /// The screen behind the menu: used for messages and dialogs after the
  /// menu has closed.
  final BuildContext hostContext;

  final VoidCallback onShowAll;
  final VoidCallback onShowNoLocation;
  final VoidCallback onShowWaiting;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final nav = Navigator.of(context);

    void close() => nav.pop();
    void open(Widget page) {
      close();
      nav.push(MaterialPageRoute(builder: (_) => page));
    }

    final status = app.needsLogin
        ? ('Log in again', VV.gold)
        : app.online
        ? ('Online', const Color(0xFF7EE2A8))
        : ('Offline', VV.gold);

    return Drawer(
      backgroundColor: VV.surface,
      child: Column(
        children: [
          // ---- header: who and where ----
          Container(
            width: double.infinity,
            color: VV.blue,
            padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(VV.radiusMd)),
                      child: Image.asset('assets/images/logo_mark.png', width: 32, height: 29),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        AppConfig.appName,
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  app.userName.isEmpty ? 'Field staff' : app.userName,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.circle, size: 10, color: status.$2),
                    const SizedBox(width: 6),
                    Text(status.$1, style: const TextStyle(color: Colors.white, fontSize: 13)),
                    if (app.lastRefresh != null)
                      Text(
                        '  ·  Updated ${formatTime(app.lastRefresh!)}',
                        style: const TextStyle(color: Color(0xFFDCEBF7), fontSize: 13),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // ---- menu ----
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _item(
                  Icons.people_alt_outlined,
                  'All customers',
                  trailing: formatIndian(app.customers.length),
                  onTap: () {
                    close();
                    onShowAll();
                  },
                ),
                _item(
                  Icons.location_off_outlined,
                  'Without location',
                  trailing: formatIndian(app.withoutLocationCount),
                  onTap: () {
                    close();
                    onShowNoLocation();
                  },
                ),
                _item(
                  Icons.cloud_upload_outlined,
                  'Waiting to sync',
                  trailing: app.waitingCount > 0 ? '${app.waitingCount}' : null,
                  highlight: app.waitingCount > 0,
                  onTap: () {
                    close();
                    onShowWaiting();
                  },
                ),
                if (app.activitiesEnabled)
                  _item(
                    Icons.event_available_outlined,
                    'My Activities',
                    trailing: app.activities.isEmpty ? null : '${app.activities.length}',
                    highlight: app.activitiesDueCount > 0,
                    onTap: () => open(const ActivitiesScreen()),
                  ),
                _item(Icons.person_add_alt_1_outlined, 'New customer', onTap: () => open(const NewCustomerScreen())),
                _item(
                  Icons.sync,
                  'Sync now',
                  onTap: () async {
                    close();
                    await app.refreshAll();
                    if (hostContext.mounted) {
                      showMessage(
                        hostContext,
                        !app.online
                            ? 'Still offline. Entries are safe on this phone.'
                            : app.queue.isEmpty
                            ? 'All synced. Customer list updated.'
                            : '${app.queue.length} entries still waiting.',
                      );
                    }
                  },
                ),
                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider()),
                _item(Icons.settings_outlined, 'Settings', onTap: () => open(const SettingsScreen())),
                _item(
                  Icons.system_update_outlined,
                  'Check for updates',
                  onTap: () {
                    close();
                    checkForUpdatesInteractive(hostContext, app);
                  },
                ),
                _item(
                  Icons.support_agent_outlined,
                  'Help & support',
                  subtitle: 'Call ${AppConfig.supportPhone}',
                  onTap: () => launchUrl(Uri(scheme: 'tel', path: AppConfig.supportPhone.replaceAll(' ', ''))),
                ),
                _item(
                  Icons.info_outline,
                  'About',
                  onTap: () {
                    close();
                    showAboutDialog(
                      context: hostContext,
                      applicationName: AppConfig.appName,
                      applicationVersion: 'Version ${AppConfig.appVersion}',
                      applicationIcon: Image.asset('assets/images/logo_mark.png', width: 40, height: 36),
                      children: const [
                        Text(
                          'Saves the GPS location of customer sites into Odoo '
                          '(Contacts › Partner Assignment › Geolocation).',
                        ),
                        SizedBox(height: 12),
                        Text('VeeVee Infotech, Tirupur'),
                        Text('${AppConfig.supportEmail} | ${AppConfig.supportPhone}'),
                      ],
                    );
                  },
                ),
                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider()),
                _item(
                  Icons.logout,
                  'Log out',
                  color: VV.danger,
                  onTap: () {
                    close();
                    confirmLogOut(hostContext, app);
                  },
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                'Version ${AppConfig.appVersion} · VeeVee Infotech',
                style: const TextStyle(fontSize: 12, color: VV.inkMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _item(
    IconData icon,
    String label, {
    required VoidCallback onTap,
    String? subtitle,
    String? trailing,
    bool highlight = false,
    Color? color,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? VV.ink),
      title: Text(
        label,
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: color ?? VV.ink),
      ),
      subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(color: VV.inkMuted)),
      trailing: trailing == null
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: highlight ? VV.gold : VV.surfaceRaised,
                borderRadius: BorderRadius.circular(VV.radiusSm),
              ),
              child: Text(
                trailing,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: VV.ink),
              ),
            ),
      onTap: onTap,
    );
  }
}
