import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/activity.dart';
import '../models/customer.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'activity_screen.dart';

/// Look of each activity type: icon, colour and the main button.
class ActivityLook {
  const ActivityLook(this.icon, this.color, this.soft, this.label, this.action, this.actionIcon);
  final IconData icon;
  final Color color;
  final Color soft;
  final String label;
  final String action;
  final IconData actionIcon;

  static ActivityLook of(OdooActivity a) => switch (a.kind) {
    ActivityKind.fieldVisit => const ActivityLook(
      Icons.location_on_outlined,
      VV.blue,
      VV.blueSoft,
      'Field visit',
      'Mark done',
      Icons.where_to_vote_outlined,
    ),
    ActivityKind.call => ActivityLook(
      Icons.phone_outlined,
      VV.success,
      VV.successSoft,
      'Call',
      a.phone.isNotEmpty ? 'Call' : 'Mark done',
      a.phone.isNotEmpty ? Icons.phone : Icons.check,
    ),
    ActivityKind.email => ActivityLook(
      Icons.mail_outline,
      VV.skyText,
      VV.skySoft,
      'Email',
      a.email.isNotEmpty ? 'Email' : 'Mark done',
      a.email.isNotEmpty ? Icons.send_outlined : Icons.check,
    ),
    ActivityKind.meeting => const ActivityLook(
      Icons.groups_outlined,
      VV.goldText,
      VV.goldSoft,
      'Meeting',
      'Mark done',
      Icons.check,
    ),
    ActivityKind.upload => const ActivityLook(
      Icons.upload_file_outlined,
      VV.ink,
      VV.surfaceRaised,
      'Document',
      'Upload',
      Icons.photo_camera_outlined,
    ),
    ActivityKind.todo => const ActivityLook(
      Icons.check_box_outlined,
      VV.inkMuted,
      VV.surfaceRaised,
      'To-Do',
      'Mark done',
      Icons.check,
    ),
  };

  /// Type name from Odoo when it is a custom type.
  static String typeLabel(OdooActivity a) {
    final l = of(a).label;
    if (a.kind == ActivityKind.todo && a.typeName.isNotEmpty) return a.typeName;
    return l;
  }
}

String dueText(OdooActivity a) {
  final d = a.daysLeft;
  if (d < -1) return '${-d} days late · ${formatDate(a.deadline)}';
  if (d == -1) return '1 day late · ${formatDate(a.deadline)}';
  if (d == 0) return 'Today';
  if (d == 1) return 'Tomorrow';
  return formatDate(a.deadline);
}

Color dueColor(OdooActivity a) => a.daysLeft < 0 ? VV.danger : (a.daysLeft == 0 ? VV.goldText : VV.inkMuted);

/// "My Activities": every open activity assigned to this user in Odoo.
class ActivitiesScreen extends StatefulWidget {
  const ActivitiesScreen({super.key});

  @override
  State<ActivitiesScreen> createState() => _ActivitiesScreenState();
}

class _ActivitiesScreenState extends State<ActivitiesScreen> {
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) AppScope.read(context).refreshActivities();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final all = app.openActivities;
    // Filter chips: one per type present, in a fixed order.
    final counts = <String, int>{};
    for (final a in all) {
      counts.update(ActivityLook.typeLabel(a), (n) => n + 1, ifAbsent: () => 1);
    }
    const order = ['Field visit', 'Call', 'To-Do', 'Email', 'Meeting', 'Document'];
    final chips = [...order.where(counts.containsKey), ...counts.keys.where((k) => !order.contains(k))];
    if (_filter != 'all' && !counts.containsKey(_filter)) _filter = 'all';
    final shown = _filter == 'all' ? all : all.where((a) => ActivityLook.typeLabel(a) == _filter).toList();
    final overdue = shown.where((v) => v.daysLeft < 0).toList();
    final today = shown.where((v) => v.daysLeft == 0).toList();
    final upcoming = shown.where((v) => v.daysLeft > 0).toList();

    return Scaffold(
      backgroundColor: VV.surfaceRaised,
      appBar: AppBar(
        title: const Text('My Activities'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text('${all.length} open', style: const TextStyle(fontSize: 13, color: VV.inkMuted)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (all.isNotEmpty)
            Container(
              color: Colors.white,
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                children: [
                  _chip('all', 'All ${all.length}', null),
                  for (final c in chips) _chip(c, '$c ${counts[c]}', _iconFor(c)),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              color: VV.blue,
              onRefresh: () async {
                await app.syncNow();
                await app.refreshActivities();
              },
              child: all.isEmpty
                  ? _empty(app.refreshingActivities)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                      children: [
                        if (overdue.isNotEmpty) ..._group('OVERDUE', overdue, VV.danger),
                        if (today.isNotEmpty) ..._group('TODAY', today, VV.goldText),
                        if (upcoming.isNotEmpty) ..._group('UPCOMING', upcoming, VV.inkMuted),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  IconData? _iconFor(String label) => switch (label) {
    'Field visit' => Icons.location_on_outlined,
    'Call' => Icons.phone_outlined,
    'To-Do' => Icons.check_box_outlined,
    'Email' => Icons.mail_outline,
    'Meeting' => Icons.groups_outlined,
    'Document' => Icons.upload_file_outlined,
    _ => null,
  };

  Widget _chip(String key, String text, IconData? icon) {
    final selected = _filter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: icon == null ? null : Icon(icon, size: 16, color: selected ? Colors.white : VV.blue),
        label: Text(text),
        selected: selected,
        showCheckmark: false,
        selectedColor: VV.blue,
        labelStyle: TextStyle(fontWeight: FontWeight.w600, color: selected ? Colors.white : VV.ink),
        onSelected: (_) => setState(() => _filter = key),
      ),
    );
  }

  Widget _empty(bool loading) => ListView(
    padding: const EdgeInsets.all(32),
    children: [
      const SizedBox(height: 40),
      const Icon(Icons.event_available_outlined, size: 56, color: VV.inkMuted),
      const SizedBox(height: 12),
      Text(
        loading ? 'Loading your activities…' : 'Nothing to do right now.',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      const Text(
        'Activities assigned to you in Odoo (To-Do, Call, Email, Meeting, Document, Field Visit) show here. '
        'Pull down to check again.',
        textAlign: TextAlign.center,
        style: TextStyle(color: VV.inkMuted),
      ),
    ],
  );

  List<Widget> _group(String title, List<OdooActivity> list, Color color) => [
    Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 6),
      child: Text(
        '$title · ${list.length}',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.3),
      ),
    ),
    for (final v in list) ActivityCard(activity: v),
  ];
}

/// One activity card: type, task, customer or record, due date, main button.
class ActivityCard extends StatelessWidget {
  const ActivityCard({super.key, required this.activity, this.showCustomer = true});
  final OdooActivity activity;
  final bool showCustomer;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final look = ActivityLook.of(a);
    final primary = a.kind == ActivityKind.fieldVisit || a.kind == ActivityKind.call;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VV.radiusMd),
          side: const BorderSide(color: VV.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(VV.radiusMd),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ActivityScreen(activity: a))),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: look.soft,
                    borderRadius: BorderRadius.circular(VV.radiusMd),
                    border: look.soft == VV.surfaceRaised ? Border.all(color: VV.line) : null,
                  ),
                  child: Icon(look.icon, color: look.color, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ActivityLook.typeLabel(a).toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: look.color,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        a.title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: VV.ink),
                      ),
                      if (showCustomer && a.relatedLine.isNotEmpty)
                        Text(a.relatedLine, style: const TextStyle(fontSize: 13, color: VV.inkMuted)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    dueText(a),
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: dueColor(a)),
                                  ),
                                ),
                                if (a.isLocal) ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.cloud_upload_outlined, size: 15, color: VV.goldText),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 38,
                            child: primary
                                ? FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: a.kind == ActivityKind.call ? VV.success : VV.blue,
                                      padding: const EdgeInsets.symmetric(horizontal: 14),
                                      minimumSize: const Size(0, 38),
                                    ),
                                    onPressed: () => runMainAction(context, a),
                                    icon: Icon(look.actionIcon, size: 18),
                                    label: Text(look.action),
                                  )
                                : OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 14),
                                      minimumSize: const Size(0, 38),
                                    ),
                                    onPressed: () => runMainAction(context, a),
                                    icon: Icon(look.actionIcon, size: 18),
                                    label: Text(look.action),
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
        ),
      ),
    );
  }
}

/// Gold bar on the home screen: "2 overdue · 3 today · 4 upcoming".
class ActivitiesBanner extends StatelessWidget {
  const ActivitiesBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.activitiesEnabled) return const SizedBox.shrink();
    final all = app.activities;
    final overdue = all.where((a) => a.daysLeft < 0).length;
    final today = all.where((a) => a.daysLeft == 0).length;
    final upcoming = all.where((a) => a.daysLeft > 0).length;
    final urgent = overdue + today > 0;
    final parts = [
      if (overdue > 0) '$overdue overdue',
      if (today > 0) '$today today',
      if (upcoming > 0) '$upcoming upcoming',
    ];
    final text = parts.isEmpty ? 'Nothing assigned to you' : parts.join(' · ');
    final fg = urgent ? VV.goldText : VV.blue;
    return Material(
      color: urgent ? VV.goldSoft : VV.blueSoft,
      child: InkWell(
        onTap: () => openActivities(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: urgent ? VV.gold : VV.blue,
                  borderRadius: BorderRadius.circular(VV.radiusMd),
                ),
                child: Icon(Icons.event_available_outlined, color: urgent ? VV.ink : Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'My Activities',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: VV.ink),
                    ),
                    Text(
                      text,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

void openActivities(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ActivitiesScreen()));

/// The customer an activity belongs to, from the phone's list or a minimal one.
Customer? customerOfActivity(List<Customer> customers, OdooActivity a) {
  for (final c in customers) {
    if ((a.partnerId != null && c.id == a.partnerId) || (a.partnerRef != null && c.localRef == a.partnerRef)) {
      return c;
    }
  }
  if (a.partnerId == null) return null;
  return Customer(id: a.partnerId!, name: a.customerName, phone: a.phone, email: a.email);
}

/// Shows a short result after saving an activity entry.
void showActivityResult(BuildContext context, String okText, String ref) {
  final waiting = AppScope.read(context).pendingByRef(ref);
  showMessage(
    context,
    waiting == null
        ? okText
        : waiting.blocked
        ? 'Odoo refused it: ${waiting.lastError}'
        : 'Saved on this phone. It will be sent to Odoo when online.',
    error: waiting?.blocked ?? false,
  );
}
