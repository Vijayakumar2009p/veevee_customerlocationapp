import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../services/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'customer_screen.dart';

class LocationSavedScreen extends StatelessWidget {
  const LocationSavedScreen({super.key, required this.input, required this.entryRef});

  final LocationInput input;

  /// The saved entry; it leaves the waiting list once Odoo has it.
  final String entryRef;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context); // rebuilds when the entry syncs later
    final c = app.resolve(input.customer);
    final entry = app.pendingByRef(entryRef);
    final synced = entry == null;
    final refused = entry != null && entry.blocked;
    final String title;
    final String message;
    if (synced) {
      title = 'Location saved';
      message = '${c.name} is now pinned in Odoo.';
    } else if (refused) {
      title = 'Not accepted by Odoo';
      message = 'Odoo refused this location: ${entry.lastError}\nIt is kept on this phone; see Settings.';
    } else if (!app.online) {
      title = 'Saved on this phone';
      message = "No connection right now. It will be sent to Odoo automatically when you're online.";
    } else {
      title = 'Saved on this phone';
      message = app.syncing
          ? 'Signal is weak. It is safe on this phone and will be sent to Odoo automatically.'
          : 'Sending to Odoo…';
    }
    void goHome() => Navigator.of(context).popUntil((r) => r.isFirst);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 4,
        title: TextButton.icon(
          onPressed: goHome,
          style: TextButton.styleFrom(
            foregroundColor: VV.ink,
            textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          icon: const Icon(Icons.home_outlined, size: 26),
          label: const Text('Home'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
          children: [
            Center(
              child: synced
                  ? const BigIcon(Icons.check, tone: Tone.success)
                  : refused
                  ? const BigIcon(Icons.error_outline, tone: Tone.danger)
                  : const BigIcon(Icons.cloud_upload_outlined, tone: Tone.gold),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, height: 1.5, color: VV.inkMuted),
            ),
            const SizedBox(height: 24),
            InfoTable([
              ('Latitude', formatCoord(input.latitude)),
              ('Longitude', formatCoord(input.longitude)),
              ('GPS accuracy', '${input.accuracy.round()} m'),
              ('Set by', app.userName),
              ('Date and time', formatDateTime(input.capturedAt)),
              ('Address', input.address == null ? '' : 'Updated'),
              ('Photo', input.photoPath == null ? '' : 'Attached'),
            ]),
            const SizedBox(height: 16),
            Callout(
              synced
                  ? "A note with these details${input.photoPath != null ? ' and the photo' : ''} "
                        "was added to the customer's chatter in Odoo."
                  : 'You can keep working. Check "Waiting to sync" in Settings any time.',
              tone: synced ? Tone.blue : Tone.gold,
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
              child: const Text('Next customer'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                final nav = Navigator.of(context);
                nav.popUntil((r) => r.isFirst);
                nav.push(MaterialPageRoute(builder: (_) => CustomerScreen(customer: c)));
              },
              child: Text('Back to ${c.name}', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}
