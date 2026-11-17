import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../theme.dart';
import 'activities_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';

/// The app after login: three tabs at the bottom, like WhatsApp.
/// Contacts · My Activities · Profile.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;
  final _contactsScaffold = GlobalKey<ScaffoldState>();
  bool _updateShown = false;

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

  void _go(int i) {
    setState(() => _tab = i);
    final app = AppScope.read(context);
    if (i == 1) app.refreshActivities();
  }

  /// Back: close the menu, go to Contacts, or ask before leaving.
  Future<void> _onBack() async {
    final menu = _contactsScaffold.currentState;
    if (_tab == 0 && menu != null && menu.isDrawerOpen) {
      menu.closeDrawer();
      return;
    }
    if (_tab != 0) {
      setState(() => _tab = 0);
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
    final due = app.activitiesDueCount;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            HomeScreen(scaffoldKey: _contactsScaffold, onOpenTab: _go),
            ActivitiesScreen(onOpenTab: _go),
            ProfileScreen(onOpenTab: _go),
          ],
        ),
        bottomNavigationBar: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: Colors.white,
            indicatorColor: VV.blueSoft,
            surfaceTintColor: Colors.transparent,
            labelTextStyle: WidgetStateProperty.resolveWith(
              (s) => TextStyle(
                fontSize: 12,
                fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
                color: s.contains(WidgetState.selected) ? VV.ink : WaColors.grey,
              ),
            ),
          ),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: WaColors.divider)),
            ),
            child: NavigationBar(
              height: 68,
              selectedIndex: _tab,
              onDestinationSelected: _go,
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.people_alt_outlined, color: WaColors.grey),
                  selectedIcon: Icon(Icons.people_alt, color: VV.blue),
                  label: 'Contacts',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: due > 0,
                    backgroundColor: VV.success,
                    label: Text('$due'),
                    child: const Icon(Icons.event_available_outlined, color: WaColors.grey),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: due > 0,
                    backgroundColor: VV.success,
                    label: Text('$due'),
                    child: const Icon(Icons.event_available, color: VV.blue),
                  ),
                  label: 'My Activities',
                ),
                NavigationDestination(
                  icon: Opacity(opacity: 0.75, child: Image.asset('assets/images/logo_mark.png', height: 22)),
                  selectedIcon: Image.asset('assets/images/logo_mark.png', height: 24),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
