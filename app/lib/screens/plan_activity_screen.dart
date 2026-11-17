import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/activity.dart';
import '../models/customer.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'activities_screen.dart';

/// Plans an activity for yourself on a customer: any Odoo activity type.
class PlanActivityScreen extends StatefulWidget {
  const PlanActivityScreen({super.key, required this.customer});
  final Customer customer;

  @override
  State<PlanActivityScreen> createState() => _PlanActivityScreenState();
}

class _PlanActivityScreenState extends State<PlanActivityScreen> {
  static const _quick = {
    'Field Visit': ['Calendar distribution', 'Support visit', 'Payment collection', 'Demo', 'Training'],
    'Call': ['Follow up', 'Payment reminder', 'Renewal reminder'],
    'Email': ['Send quotation', 'Send demo link', 'Send invoice copy'],
    'Meeting': ['Requirement discussion', 'Demo', 'Review meeting'],
    'To-Do': ['Prepare quotation', 'Check payment', 'Update details in Odoo'],
    'Document': ['Collect GST certificate', 'Collect signed order'],
  };

  final _form = GlobalKey<FormState>();
  final _summary = TextEditingController();
  final _note = TextEditingController();
  late DateTime _date;
  ActivityType? _type;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day + 1);
    Future.microtask(() {
      if (!mounted) return;
      final app = AppScope.read(context);
      if (app.activityTypes.isEmpty) {
        app.refreshActivities().then((_) {
          if (mounted) setState(() => _type ??= _defaultType());
        });
      }
      setState(() => _type ??= _defaultType());
    });
  }

  ActivityType? _defaultType() {
    final types = AppScope.read(context).plannableTypes;
    return types.isEmpty ? null : types.first;
  }

  @override
  void dispose() {
    _summary.dispose();
    _note.dispose();
    super.dispose();
  }

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: _today,
      lastDate: _today.add(const Duration(days: 365)),
      helpText: 'Activity date',
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    final type = _type;
    if (type == null) {
      showMessage(context, 'Activity types are not loaded yet. Check the internet and try again.', error: true);
      return;
    }
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final ref = await AppScope.read(
        context,
      ).scheduleActivity(widget.customer, type: type, summary: _summary.text, date: _date, note: _note.text);
      if (!mounted) return;
      showActivityResult(context, '${type.name} planned for ${formatDate(_date)}.', ref);
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showMessage(context, 'Could not save: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  IconData _iconOf(ActivityType t) => switch (t.icon) {
    'fa-map-marker' => Icons.location_on_outlined,
    'fa-phone' => Icons.phone_outlined,
    'fa-envelope' || 'fa-envelope-o' => Icons.mail_outline,
    'fa-users' || 'fa-calendar' => Icons.groups_outlined,
    'fa-upload' => Icons.upload_file_outlined,
    _ => Icons.check_box_outlined,
  };

  Widget _dayChip(String label, DateTime d) =>
      ChoiceChip(label: Text(label), selected: _date == d, onSelected: _busy ? null : (_) => setState(() => _date = d));

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = app.resolve(widget.customer);
    final types = app.plannableTypes;
    final tomorrow = _today.add(const Duration(days: 1));
    final isOther = _date != _today && _date != tomorrow;
    final quick = _quick[_type?.name] ?? const <String>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Plan activity')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                  children: [
                    Text(c.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    const Text(
                      'Added to this customer in Odoo, assigned to you.',
                      style: TextStyle(color: VV.inkMuted),
                    ),
                    const SizedBox(height: 20),
                    const FieldLabel('Type', required: true),
                    if (types.isEmpty)
                      const Text('Loading types…', style: TextStyle(color: VV.inkMuted))
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final t in types)
                            ChoiceChip(
                              avatar: Icon(_iconOf(t), size: 17, color: _type?.id == t.id ? Colors.white : VV.blue),
                              label: Text(t.name),
                              selected: _type?.id == t.id,
                              showCheckmark: false,
                              selectedColor: VV.blue,
                              labelStyle: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _type?.id == t.id ? Colors.white : VV.ink,
                              ),
                              onSelected: _busy ? null : (_) => setState(() => _type = t),
                            ),
                        ],
                      ),
                    const SizedBox(height: 20),
                    const FieldLabel('What is it for?', required: true),
                    TextFormField(
                      controller: _summary,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(hintText: quick.isEmpty ? 'e.g. Follow up' : 'e.g. ${quick.first}'),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Write what it is for.' : null,
                    ),
                    if (quick.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final q in quick)
                            ActionChip(
                              label: Text(q),
                              onPressed: _busy ? null : () => setState(() => _summary.text = q),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    const FieldLabel('When?', required: true),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _dayChip('Today', _today),
                        _dayChip('Tomorrow', tomorrow),
                        ChoiceChip(
                          avatar: const Icon(Icons.event, size: 18),
                          label: Text(isOther ? formatDate(_date) : 'Pick a date'),
                          selected: isOther,
                          onSelected: _busy ? null : (_) => _pickDate(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const FieldLabel('Note', optional: true),
                    TextField(
                      controller: _note,
                      minLines: 2,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(hintText: 'e.g. Ask for Mr. Kumar, after 4 pm'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(64, 52)),
                    onPressed: _busy ? null : _save,
                    icon: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Icon(Icons.event_available),
                    label: const Text('Save activity', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
