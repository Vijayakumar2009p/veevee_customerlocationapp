import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_scope.dart';
import '../config.dart';
import '../screens/settings_screen.dart';
import '../theme.dart';
import '../utils/format.dart';

/// The ☰ menu on the Contacts tab: Settings, Check for updates,
/// Help & support, About, Log out.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.hostContext});

  /// The screen behind the menu: used for messages and dialogs after the
  /// menu has closed.
  final BuildContext hostContext;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final nav = Navigator.of(context);

    void close() => nav.pop();

    final (statusText, statusColor) = app.needsLogin
        ? ('Log in again', VV.danger)
        : app.online
        ? ('Connected${app.lastSyncAt != null ? ' · synced ${formatTime(app.lastSyncAt!)}' : ''}', VV.success)
        : ('Offline', VV.goldText);

    return Drawer(
      backgroundColor: Colors.white,
      width: 310,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(topRight: Radius.circular(20), bottomRight: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset('assets/images/logo_lockup.png', width: 170),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: WaColors.background, borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: VV.blue,
                          child: Text(
                            WaColors.initials(app.userName.isEmpty ? 'Field staff' : app.userName),
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                app.userName.isEmpty ? 'Field staff' : app.userName,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: VV.ink),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(Icons.circle, size: 8, color: statusColor),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      statusText,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 13, color: statusColor, fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _item(
              Icons.settings_outlined,
              'Settings',
              VV.blue,
              VV.blueSoft,
              onTap: () {
                close();
                nav.push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
              },
            ),
            _item(
              Icons.system_update_outlined,
              'Check for updates',
              VV.success,
              VV.successSoft,
              trailing: AppConfig.appVersion,
              onTap: () {
                close();
                checkForUpdatesInteractive(hostContext, app);
              },
            ),
            _item(
              Icons.support_agent_outlined,
              'Help & support',
              VV.goldText,
              VV.goldSoft,
              onTap: () {
                close();
                showHelpSheet(hostContext);
              },
            ),
            _item(
              Icons.info_outline,
              'About',
              VV.skyText,
              VV.skySoft,
              onTap: () {
                close();
                showAboutApp(hostContext);
              },
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: VV.danger,
                    side: const BorderSide(color: Color(0xFFF2C6C2)),
                    minimumSize: const Size(0, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    close();
                    confirmLogOut(hostContext, app);
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Log out', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Center(
                child: Text(
                  '${AppConfig.appName} · version ${AppConfig.appVersion}',
                  style: TextStyle(fontSize: 12, color: WaColors.grey),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(IconData icon, String label, Color fg, Color bg, {required VoidCallback onTap, String? trailing}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 22),
      minTileHeight: 56,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: fg, size: 20),
      ),
      title: Text(label, style: const TextStyle(fontSize: 16, color: VV.ink)),
      trailing: trailing == null ? null : Text(trailing, style: const TextStyle(fontSize: 12, color: WaColors.grey)),
      onTap: onTap,
    );
  }
}

/// Help & support: call, WhatsApp or email VeeVee.
void showHelpSheet(BuildContext context) {
  final phone = AppConfig.supportPhone.replaceAll(' ', '');
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text('Help & support', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text('VeeVee Infotech, Tirupur', style: TextStyle(color: WaColors.grey)),
          ),
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: VV.successSoft,
              child: Icon(Icons.phone, color: VV.success),
            ),
            title: const Text('Call'),
            subtitle: const Text(AppConfig.supportPhone),
            onTap: () => launchUrl(Uri(scheme: 'tel', path: phone)),
          ),
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: VV.successSoft,
              child: Icon(Icons.chat_outlined, color: VV.success),
            ),
            title: const Text('WhatsApp'),
            subtitle: const Text('Send us a message'),
            onTap: () => launchUrl(
              Uri.parse('https://wa.me/${phone.replaceAll('+', '')}'),
              mode: LaunchMode.externalApplication,
            ),
          ),
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: VV.blueSoft,
              child: Icon(Icons.mail_outline, color: VV.blue),
            ),
            title: const Text('Email'),
            subtitle: const Text(AppConfig.supportEmail),
            onTap: () => launchUrl(
              Uri(
                scheme: 'mailto',
                path: AppConfig.supportEmail,
                queryParameters: {'subject': 'VeeVee Field Locator help'},
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

void showAboutApp(BuildContext context) {
  showAboutDialog(
    context: context,
    applicationName: AppConfig.appName,
    applicationVersion: 'Version ${AppConfig.appVersion}',
    applicationIcon: Image.asset('assets/images/logo_mark.png', width: 40),
    children: const [
      Text(
        'Customer locations, new customers and your Odoo activities, '
        'from the field, with or without internet.',
      ),
      SizedBox(height: 12),
      Text('VeeVee Infotech, Tirupur'),
      Text('${AppConfig.supportEmail} | ${AppConfig.supportPhone}'),
    ],
  );
}
