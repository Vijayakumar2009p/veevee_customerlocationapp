import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_scope.dart';
import '../models/customer.dart';
import '../models/pending_action.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'add_photos_screen.dart';
import 'activities_screen.dart';
import 'plan_activity_screen.dart';
import 'set_location_screen.dart';

/// Customer details. The app only sets the location here; other details
/// are changed by the office in Odoo.
class CustomerScreen extends StatelessWidget {
  const CustomerScreen({super.key, required this.customer});
  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = app.resolve(customer);
    final pending = app.pendingFor(c);
    final waitingLocation = pending.any((a) => a.kind == PendingAction.location);
    final blocked = pending.where((a) => a.blocked).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Customer')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CustomerAvatar(c, size: 52),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                            if (!c.isCompany && c.parentName.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(c.parentName, style: const TextStyle(color: VV.inkMuted)),
                              ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                StatusBadge(
                                  c.isCompany ? 'Company' : 'Individual',
                                  tone: c.isCompany ? Tone.blue : Tone.sky,
                                ),
                                LocationBadge(c),
                                if (c.isLocal) const StatusBadge('Not in Odoo yet', tone: Tone.gold),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (blocked.isNotEmpty) ...[
                    Callout(
                      'Odoo refused this change: ${blocked.first.lastError}',
                      tone: Tone.danger,
                      title: 'Not saved in Odoo',
                      icon: Icons.error_outline,
                    ),
                    const SizedBox(height: 16),
                  ],
                  InfoTable(
                    [('Mobile', c.phone), ('GSTIN', c.vat), ('Email', c.email), ('Address', c.addressLine)],
                    stacked: true,
                    actions: {
                      'Mobile': FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: VV.success,
                          minimumSize: const Size(96, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        onPressed: () => launchUrl(Uri(scheme: 'tel', path: c.phone.replaceAll(' ', ''))),
                        icon: const Icon(Icons.call, size: 20),
                        label: const Text('Call'),
                      ),
                    },
                  ),
                  const SizedBox(height: 16),
                  if (c.hasLocation) _LocationCard(c, waiting: waitingLocation) else const _NoLocationCard(),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => AddPhotosScreen(customer: c))),
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Add photos', style: TextStyle(fontSize: 16)),
                  ),
                  if (app.activitiesEnabled) ...[
                    const SizedBox(height: 24),
                    const SectionLabel('Activities'),
                    for (final v in app.activitiesFor(c)) ActivityCard(activity: v, showCustomer: false),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                      onPressed: () => Navigator.of(
                        context,
                      ).push(MaterialPageRoute(builder: (_) => PlanActivityScreen(customer: c))),
                      icon: const Icon(Icons.event_available_outlined),
                      label: const Text('Plan activity', style: TextStyle(fontSize: 16)),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(64, 52)),
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => SetLocationScreen(customer: c))),
                  icon: const Icon(Icons.my_location),
                  label: Text(c.hasLocation ? 'Update location' : 'Set location', style: const TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoLocationCard extends StatelessWidget {
  const _NoLocationCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      decoration: BoxDecoration(
        color: VV.surfaceRaised,
        border: Border.all(color: VV.line, width: 1.5),
        borderRadius: BorderRadius.circular(VV.radiusMd),
      ),
      child: const Column(
        children: [
          Icon(Icons.location_on_outlined, size: 32, color: VV.inkMuted),
          SizedBox(height: 8),
          Text('No location saved yet', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          SizedBox(height: 4),
          Text(
            "Stand at the customer's entrance, then tap Set location.",
            textAlign: TextAlign.center,
            style: TextStyle(color: VV.inkMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard(this.c, {required this.waiting});
  final Customer c;
  final bool waiting;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Location'),
        InfoTable([
          ('Latitude', formatCoord(c.latitude)),
          ('Longitude', formatCoord(c.longitude)),
          ('Saved on', c.locationDate.isEmpty ? '' : formatOdooDate(c.locationDate)),
          ('Status', waiting ? 'Waiting to sync' : 'In Odoo'),
        ]),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => launchUrl(
              Uri.parse('https://www.google.com/maps/search/?api=1&query=${c.latitude},${c.longitude}'),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.directions_outlined, size: 18),
            label: const Text('Open in Maps'),
          ),
        ),
      ],
    );
  }
}
