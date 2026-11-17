import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_scope.dart';
import '../models/activity.dart';
import '../services/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/photo_strip.dart';
import 'activities_screen.dart';
import 'customer_screen.dart';
import 'plan_activity_screen.dart';
import 'visit_done_screen.dart';

/// The main button of an activity: Call / Email opens the phone or mail app
/// and then asks "Mark done?"; Field Visit opens the GPS screen; others mark done.
/// Returns true when the activity was marked done.
Future<bool> runMainAction(BuildContext context, OdooActivity a) async {
  final app = AppScope.read(context);
  switch (a.kind) {
    case ActivityKind.fieldVisit:
      final customer = customerOfActivity(app.customers, a);
      final done = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => VisitDoneScreen(visit: a, customer: customer),
        ),
      );
      return done == true;
    case ActivityKind.call:
      if (a.phone.isNotEmpty) {
        await launchUrl(Uri(scheme: 'tel', path: a.phone.replaceAll(' ', '')));
      }
    case ActivityKind.email:
      if (a.email.isNotEmpty) {
        await launchUrl(Uri(scheme: 'mailto', path: a.email, queryParameters: {'subject': a.title}));
      }
    case ActivityKind.meeting || ActivityKind.upload || ActivityKind.todo:
      break;
  }
  if (!context.mounted) return false;
  return showMarkDoneSheet(context, a);
}

/// Bottom sheet: quick result (calls), note, photos, "Plan next activity".
Future<bool> showMarkDoneSheet(BuildContext context, OdooActivity a) async {
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _MarkDoneSheet(activity: a),
  );
  return done == true;
}

class _MarkDoneSheet extends StatefulWidget {
  const _MarkDoneSheet({required this.activity});
  final OdooActivity activity;

  @override
  State<_MarkDoneSheet> createState() => _MarkDoneSheetState();
}

class _MarkDoneSheetState extends State<_MarkDoneSheet> {
  final _note = TextEditingController();
  final _photos = PhotoSelection();
  String _result = '';
  bool _planNext = false;
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  List<String> get _results => switch (widget.activity.kind) {
    ActivityKind.call => const ['Spoke to customer', 'No answer', 'Call back later', 'Wrong number'],
    ActivityKind.email => const ['Email sent', 'Replied to customer'],
    ActivityKind.meeting => const ['Meeting held', 'Customer did not come'],
    _ => const [],
  };

  String get _title => switch (widget.activity.kind) {
    ActivityKind.call => 'Call finished?',
    ActivityKind.email => 'Email sent?',
    ActivityKind.meeting => 'Meeting over?',
    ActivityKind.upload => 'Upload document',
    _ => 'Mark as done',
  };

  Future<void> _save() async {
    final a = widget.activity;
    if (a.kind == ActivityKind.upload && _photos.isEmpty) {
      showMessage(context, 'Add a photo of the document first.', error: true);
      return;
    }
    setState(() => _busy = true);
    final app = AppScope.read(context);
    final navigator = Navigator.of(context);
    final customer = customerOfActivity(app.customers, a);
    try {
      final ref = await app.markActivityDone(
        ActivityDoneInput(activity: a, result: _result, remark: _note.text, photoPaths: List.of(_photos.paths)),
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showActivityResult(context, 'Marked done.', ref);
      navigator.pop(true);
      if (_planNext && customer != null) {
        await navigator.push(MaterialPageRoute(builder: (_) => PlanActivityScreen(customer: customer)));
      }
    } catch (e) {
      if (mounted) {
        showMessage(context, 'Could not save: $e', error: true);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.activity;
    final canPlanNext = a.partnerId != null || a.partnerRef != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              [a.title, a.relatedLine].where((s) => s.isNotEmpty).join(' · '),
              style: const TextStyle(fontSize: 14, color: VV.inkMuted),
            ),
            if (_results.isNotEmpty) ...[
              const SizedBox(height: 20),
              const FieldLabel('Result', optional: true),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in _results)
                    ChoiceChip(
                      label: Text(r),
                      selected: _result == r,
                      showCheckmark: false,
                      selectedColor: VV.blue,
                      labelStyle: TextStyle(fontWeight: FontWeight.w600, color: _result == r ? Colors.white : VV.ink),
                      onSelected: _busy ? null : (s) => setState(() => _result = s ? r : ''),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            const FieldLabel('Note', optional: true),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: a.kind == ActivityKind.call
                    ? 'e.g. Agreed to renew. Will pay by 25-11-2026.'
                    : 'What was done',
              ),
            ),
            const SizedBox(height: 20),
            FieldLabel(
              a.kind == ActivityKind.upload ? 'Document photo' : 'Photos',
              optional: a.kind != ActivityKind.upload,
              required: a.kind == ActivityKind.upload,
            ),
            PhotoStrip(selection: _photos, enabled: !_busy, chooseProfile: false, onChanged: () => setState(() {})),
            if (canPlanNext) ...[
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _planNext,
                onChanged: _busy ? null : (v) => setState(() => _planNext = v ?? false),
                title: const Text('Plan next activity', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('e.g. a field visit to collect payment'),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                    onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: VV.success, minimumSize: const Size(0, 52)),
                    onPressed: _busy ? null : _save,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Icon(Icons.check),
                    label: const Text('Mark done', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Saved in Odoo as "Done" with your note, by ${AppScope.read(context).userName}.',
                style: const TextStyle(fontSize: 12, color: VV.inkMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reschedule: Tomorrow / Next week / pick a date.
Future<void> rescheduleActivityDialog(BuildContext context, OdooActivity a) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final picked = await showModalBottomSheet<DateTime>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Move to', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          ListTile(
            leading: const Icon(Icons.today_outlined, color: VV.blue),
            title: const Text('Tomorrow'),
            subtitle: Text(formatDate(today.add(const Duration(days: 1)))),
            onTap: () => Navigator.pop(c, today.add(const Duration(days: 1))),
          ),
          ListTile(
            leading: const Icon(Icons.date_range_outlined, color: VV.blue),
            title: const Text('Next week'),
            subtitle: Text(formatDate(today.add(const Duration(days: 7)))),
            onTap: () => Navigator.pop(c, today.add(const Duration(days: 7))),
          ),
          ListTile(
            leading: const Icon(Icons.edit_calendar_outlined, color: VV.blue),
            title: const Text('Pick a date'),
            onTap: () async {
              final d = await showDatePicker(
                context: c,
                initialDate: a.deadline.isBefore(today) ? today : a.deadline,
                firstDate: today,
                lastDate: today.add(const Duration(days: 365)),
              );
              if (c.mounted) Navigator.pop(c, d);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  final ref = await AppScope.read(context).rescheduleActivity(a, picked);
  if (context.mounted) showActivityResult(context, 'Moved to ${formatDate(picked)}.', ref);
}

/// Activity details: task, due date, office note, customer shortcuts and actions.
class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key, required this.activity});
  final OdooActivity activity;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final a = activity;
    final look = ActivityLook.of(a);
    final customer = customerOfActivity(app.customers, a);
    final hasMap = customer != null && customer.hasLocation;

    Future<void> main() async {
      final done = await runMainAction(context, a);
      if (done && context.mounted) Navigator.of(context).pop();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: look.soft, borderRadius: BorderRadius.circular(VV.radiusSm)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(look.icon, size: 15, color: look.color),
                          const SizedBox(width: 6),
                          Text(
                            ActivityLook.typeLabel(a),
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: look.color),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(a.title, style: const TextStyle(fontSize: 24, height: 1.3, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 16, color: dueColor(a)),
                      const SizedBox(width: 6),
                      Text(
                        a.daysLeft < 0
                            ? 'Due ${formatDate(a.deadline)} · ${dueText(a).split(' · ').first}'
                            : 'Due ${dueText(a)}${a.daysLeft > 1 ? '' : ' · ${formatDate(a.deadline)}'}',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: dueColor(a)),
                      ),
                    ],
                  ),
                  if (a.note.isNotEmpty || a.assignedBy.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: VV.surfaceRaised,
                        border: Border.all(color: VV.line),
                        borderRadius: BorderRadius.circular(VV.radiusMd),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'NOTE',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: VV.inkMuted),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            a.note.isEmpty ? 'No note.' : a.note,
                            style: const TextStyle(fontSize: 15, height: 1.45),
                          ),
                          if (a.assignedBy.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Assigned by ${a.assignedBy}',
                              style: const TextStyle(fontSize: 12, color: VV.inkMuted),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  if (a.relatedLine.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      a.resModel == 'res.partner' ? 'CUSTOMER' : 'RELATED TO',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: VV.inkMuted),
                    ),
                    const SizedBox(height: 8),
                    Text(a.relatedLine, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    if (a.phone.isNotEmpty || a.email.isNotEmpty)
                      Text(
                        [a.phone, a.email].where((s) => s.isNotEmpty).join(' · '),
                        style: const TextStyle(fontSize: 13, color: VV.inkMuted),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (a.phone.isNotEmpty)
                          _Shortcut(
                            icon: Icons.phone_outlined,
                            color: VV.success,
                            label: 'Call',
                            onTap: () => launchUrl(Uri(scheme: 'tel', path: a.phone.replaceAll(' ', ''))),
                          ),
                        if (a.email.isNotEmpty)
                          _Shortcut(
                            icon: Icons.mail_outline,
                            color: VV.skyText,
                            label: 'Email',
                            onTap: () => launchUrl(Uri(scheme: 'mailto', path: a.email)),
                          ),
                        if (hasMap)
                          _Shortcut(
                            icon: Icons.directions_outlined,
                            color: VV.blue,
                            label: 'Directions',
                            onTap: () => launchUrl(
                              Uri.parse(
                                'https://www.google.com/maps/dir/?api=1&destination=${customer.latitude},${customer.longitude}',
                              ),
                              mode: LaunchMode.externalApplication,
                            ),
                          ),
                        if (customer != null)
                          _Shortcut(
                            icon: Icons.person_outline,
                            color: VV.blue,
                            label: 'Customer',
                            onTap: () => Navigator.of(
                              context,
                            ).push(MaterialPageRoute(builder: (_) => CustomerScreen(customer: customer))),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  if (a.kind == ActivityKind.call && a.phone.isNotEmpty ||
                      a.kind == ActivityKind.email && a.email.isNotEmpty ||
                      a.kind == ActivityKind.fieldVisit ||
                      a.kind == ActivityKind.upload) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: a.kind == ActivityKind.call ? VV.success : VV.blue,
                          minimumSize: const Size(0, 54),
                        ),
                        onPressed: main,
                        icon: Icon(look.actionIcon),
                        label: Text(
                          switch (a.kind) {
                            ActivityKind.call => 'Call ${a.customerName.isNotEmpty ? a.customerName : 'customer'}',
                            ActivityKind.email => 'Write email',
                            ActivityKind.fieldVisit => 'Mark visit done',
                            ActivityKind.upload => 'Upload document',
                            _ => look.action,
                          },
                          style: const TextStyle(fontSize: 17),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: a.kind == ActivityKind.fieldVisit || a.kind == ActivityKind.upload
                            ? const SizedBox.shrink()
                            : OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50)),
                                onPressed: () async {
                                  final done = await showMarkDoneSheet(context, a);
                                  if (done && context.mounted) Navigator.of(context).pop();
                                },
                                icon: const Icon(Icons.check),
                                label: const Text('Mark done', style: TextStyle(fontSize: 15)),
                              ),
                      ),
                      if (a.kind != ActivityKind.fieldVisit && a.kind != ActivityKind.upload) const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 50),
                            foregroundColor: VV.ink,
                            side: const BorderSide(color: VV.line),
                          ),
                          onPressed: () => rescheduleActivityDialog(context, a),
                          icon: const Icon(Icons.event_outlined),
                          label: const Text('Reschedule', style: TextStyle(fontSize: 15)),
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
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({required this.icon, required this.color, required this.label, required this.onTap});
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.only(right: 8),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 64),
          padding: EdgeInsets.zero,
          foregroundColor: VV.ink,
          side: const BorderSide(color: VV.line),
        ),
        onPressed: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    ),
  );
}
