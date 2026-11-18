import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/activity.dart';
import '../models/customer.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'activity_screen.dart';
import 'home_screen.dart';
import 'plan_activity_screen.dart';
import 'set_location_screen.dart';

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

/// "My Activities" tab: every open activity assigned to this user in Odoo.
class ActivitiesScreen extends StatefulWidget {
  const ActivitiesScreen({super.key, this.onOpenTab});
  final void Function(int tab)? onOpenTab;

  @override
  State<ActivitiesScreen> createState() => _ActivitiesScreenState();
}

enum _View { today, upcoming, done }

class _ActivitiesScreenState extends State<ActivitiesScreen> {
  _View _view = _View.today;
  String _type = 'all';

  /// A day picked in the week strip (null: use the tabs).
  DateTime? _day;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final today = _dateOnly(DateTime.now());
    final all = app.openActivities;
    final typed = _type == 'all' ? all : all.where((a) => ActivityLook.typeLabel(a) == _type).toList();
    final dueNow = typed.where((a) => a.daysLeft <= 0).toList();
    final upcoming = typed.where((a) => a.daysLeft > 0).toList();
    final done = app.doneToday;
    final doneCount = done.length;
    final totalToday = doneCount + all.where((a) => a.daysLeft <= 0).length;
    final left = totalToday - doneCount;

    // Type filter: types present, in a fixed order.
    final counts = <String, int>{};
    for (final a in all) {
      counts.update(ActivityLook.typeLabel(a), (n) => n + 1, ifAbsent: () => 1);
    }
    const order = ['Field visit', 'Call', 'To-Do', 'Email', 'Meeting', 'Document'];
    final types = [...order.where(counts.containsKey), ...counts.keys.where((k) => !order.contains(k))];
    if (_type != 'all' && !counts.containsKey(_type)) _type = 'all';

    final firstDay = today.subtract(Duration(days: today.weekday - 1));
    final week = [for (var i = 0; i < 7; i++) firstDay.add(Duration(days: i))];
    final day = _day;

    Widget body;
    if (day != null) {
      final list = typed.where((a) => _dateOnly(a.deadline) == day).toList();
      body = _list([
        if (list.isEmpty) _emptyBox('Nothing planned on ${_dayName(day)} ${day.day}.'),
        for (final a in list) _SwipeActivity(activity: a),
      ]);
    } else if (_view == _View.today) {
      final overdue = dueNow.where((a) => a.daysLeft < 0).toList();
      final todays = dueNow.where((a) => a.daysLeft == 0).toList();
      body = _list([
        if (dueNow.isEmpty)
          _emptyBox(doneCount > 0 ? 'All done for today. Well done!' : 'Nothing due today.', icon: Icons.task_alt),
        if (overdue.isNotEmpty) _section('OVERDUE', VV.danger),
        for (final a in overdue) _SwipeActivity(activity: a, withButtons: true),
        if (todays.isNotEmpty) _section('TODAY', VV.goldText),
        for (final a in todays) _SwipeActivity(activity: a),
        if (dueNow.isNotEmpty) _hint(),
      ]);
    } else if (_view == _View.upcoming) {
      final byDay = <DateTime, List<OdooActivity>>{};
      for (final a in upcoming) {
        byDay.putIfAbsent(_dateOnly(a.deadline), () => []).add(a);
      }
      body = _list([
        if (upcoming.isEmpty) _emptyBox('Nothing planned yet.'),
        for (final e in byDay.entries) ...[
          _section(_dayHeader(e.key), WaColors.grey),
          for (final a in e.value) _SwipeActivity(activity: a),
        ],
      ]);
    } else {
      body = _list([
        if (done.isEmpty) _emptyBox('Nothing marked done today yet.'),
        for (final (a, at) in done) _DoneTile(activity: a, at: at),
      ]);
    }

    return Scaffold(
      backgroundColor: WaColors.background,
      body: RefreshIndicator(
        color: VV.blue,
        onRefresh: () async {
          await app.syncNow();
          await app.refreshActivities();
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _Header(
                greeting: '$_greeting, ${app.userName.isEmpty ? 'there' : app.userName.split(' ').first}',
                done: doneCount,
                total: totalToday,
                left: left,
                week: week,
                today: today,
                selected: day ?? today,
                hasItems: (d) => all.any((a) => _dateOnly(a.deadline) == d),
                onDay: (d) => setState(() => _day = d == today ? null : d),
              ),
            ),
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Row(
                  children: [
                    if (day != null)
                      _pill(
                        '${_dayName(day)} ${day.day} · ${typed.where((a) => _dateOnly(a.deadline) == day).length}',
                        true,
                        () => setState(() => _day = null),
                        trailing: Icons.close,
                      ),
                    _pill('Today · ${dueNow.length}', day == null && _view == _View.today, () {
                      setState(() {
                        _day = null;
                        _view = _View.today;
                      });
                    }),
                    _pill('Upcoming · ${upcoming.length}', day == null && _view == _View.upcoming, () {
                      setState(() {
                        _day = null;
                        _view = _View.upcoming;
                      });
                    }),
                    _pill('Done · $doneCount', day == null && _view == _View.done, () {
                      setState(() {
                        _day = null;
                        _view = _View.done;
                      });
                    }),
                  ],
                ),
              ),
            ),
            if (types.isNotEmpty)
              SliverToBoxAdapter(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: Row(
                    children: [_typeChip('all', 'All', null), for (final t in types) _typeChip(t, t, _dotColor(t))],
                  ),
                ),
              ),
            body,
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'plan',
        backgroundColor: VV.gold,
        foregroundColor: VV.ink,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.add),
        label: const Text('Plan', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        onPressed: () => pickCustomerAndPlan(context),
      ),
    );
  }

  static String _dayName(DateTime d) => const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];

  String _dayHeader(DateTime d) {
    final diff = d.difference(_dateOnly(DateTime.now())).inDays;
    if (diff == 1) return 'TOMORROW';
    return '${_dayName(d).toUpperCase()} · ${formatDate(d)}';
  }

  Color _dotColor(String t) => switch (t) {
    'Field visit' => VV.blue,
    'Call' => VV.success,
    'Email' => VV.sky,
    'Meeting' => VV.gold,
    'Document' => VV.ink,
    _ => WaColors.grey,
  };

  Widget _list(List<Widget> children) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
    sliver: SliverList.list(children: children),
  );

  Widget _section(String text, Color color) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
    child: Text(
      text,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.5),
    ),
  );

  Widget _hint() => const Padding(
    padding: EdgeInsets.only(top: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.swipe, size: 16, color: WaColors.grey),
        SizedBox(width: 6),
        Text('Swipe right: done · Swipe left: later', style: TextStyle(fontSize: 12, color: WaColors.grey)),
      ],
    ),
  );

  Widget _emptyBox(String text, {IconData icon = Icons.event_available_outlined}) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
    child: Column(
      children: [
        Icon(icon, size: 48, color: icon == Icons.task_alt ? VV.success : WaColors.grey),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: VV.ink),
        ),
        const SizedBox(height: 4),
        const Text(
          'Activities assigned to you in Odoo show here. Pull down to check again.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: WaColors.grey),
        ),
      ],
    ),
  );

  Widget _pill(String text, bool selected, VoidCallback onTap, {IconData? trailing}) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Material(
      color: selected ? VV.ink : Colors.white,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: selected ? Colors.white : WaColors.grey,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 6),
                Icon(trailing, size: 16, color: selected ? Colors.white : WaColors.grey),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  Widget _typeChip(String key, String label, Color? dot) {
    final selected = _type == key;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: selected ? VV.blueSoft : Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _type = key),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dot != null) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: selected ? VV.blue : WaColors.grey,
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

/// Blue header: greeting, progress ring for today, week strip.
class _Header extends StatelessWidget {
  const _Header({
    required this.greeting,
    required this.done,
    required this.total,
    required this.left,
    required this.week,
    required this.today,
    required this.selected,
    required this.hasItems,
    required this.onDay,
  });

  final String greeting;
  final int done;
  final int total;
  final int left;
  final List<DateTime> week;
  final DateTime today;
  final DateTime selected;
  final bool Function(DateTime) hasItems;
  final void Function(DateTime) onDay;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : done / total;
    return Container(
      padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 16, 16, 14),
      decoration: const BoxDecoration(
        color: VV.blue,
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 60,
                      height: 60,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 7,
                        strokeCap: StrokeCap.round,
                        color: VV.gold,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                    Text(
                      '$done/$total',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(greeting, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    const Text(
                      'My Activities',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      total == 0
                          ? 'Nothing due today'
                          : left == 0
                          ? 'All done for today'
                          : '$left left today · keep going',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final d in week)
                Expanded(
                  child: GestureDetector(
                    onTap: () => onDay(d),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: d == selected ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(
                            const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1],
                            style: TextStyle(
                              fontSize: 12,
                              color: d == selected ? VV.blue : Colors.white70,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '${d.day}',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: d == selected ? VV.blue : Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: hasItems(d)
                                  ? (d.isBefore(today) ? VV.gold : (d == selected ? VV.blue : Colors.white))
                                  : Colors.transparent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A card that can be swiped: right = main action (done), left = later.
class _SwipeActivity extends StatelessWidget {
  const _SwipeActivity({required this.activity, this.withButtons = false});
  final OdooActivity activity;
  final bool withButtons;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey('act-${activity.id ?? activity.localRef}'),
        background: _swipeBg(Alignment.centerLeft, VV.success, Icons.check, 'Done'),
        secondaryBackground: _swipeBg(Alignment.centerRight, VV.gold, Icons.schedule, 'Later', dark: true),
        confirmDismiss: (dir) async {
          if (dir == DismissDirection.startToEnd) {
            // Field visits need the GPS screen; everything else goes straight to "Mark done".
            return activity.kind == ActivityKind.fieldVisit
                ? runMainAction(context, activity)
                : showMarkDoneSheet(context, activity);
          }
          await rescheduleActivityDialog(context, activity);
          return false;
        },
        child: ActivityCard(activity: activity, withButtons: withButtons),
      ),
    );
  }

  Widget _swipeBg(Alignment align, Color color, IconData icon, String label, {bool dark = false}) => Container(
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
    alignment: align,
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: dark ? VV.ink : Colors.white, size: 26),
        Text(
          label,
          style: TextStyle(color: dark ? VV.ink : Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
        ),
      ],
    ),
  );
}

/// One activity: customer avatar with a type badge, task, customer, due tag.
class ActivityCard extends StatelessWidget {
  const ActivityCard({super.key, required this.activity, this.showCustomer = true, this.withButtons = false});
  final OdooActivity activity;
  final bool showCustomer;
  final bool withButtons;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final look = ActivityLook.of(a);
    final who = a.customerName.isNotEmpty ? a.customerName : (a.resName.isNotEmpty ? a.resName : a.title);
    final late = a.daysLeft < 0;
    final tag = late
        ? (a.daysLeft == -1 ? '1 day late' : '${-a.daysLeft} days late')
        : (a.daysLeft == 0 ? 'Today' : (a.daysLeft == 1 ? 'Tomorrow' : formatDate(a.deadline)));
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 0.5,
      shadowColor: const Color(0x220F2A3F),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ActivityScreen(activity: a))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  InitialsAvatar(
                    who,
                    size: 48,
                    badge: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: look.color == VV.inkMuted ? WaColors.grey : look.color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Icon(look.icon, size: 11, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: VV.ink),
                        ),
                        if (showCustomer && a.relatedLine.isNotEmpty)
                          Text(
                            a.relatedLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, color: WaColors.grey),
                          ),
                        Row(
                          children: [
                            Text(
                              ActivityLook.typeLabel(a),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: look.color == VV.inkMuted ? WaColors.grey : look.color,
                              ),
                            ),
                            if (a.isLocal) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.cloud_upload_outlined, size: 14, color: VV.goldText),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: late ? VV.dangerSoft : (a.daysLeft == 0 ? VV.goldSoft : WaColors.background),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: late ? VV.danger : (a.daysLeft == 0 ? VV.goldText : WaColors.grey),
                      ),
                    ),
                  ),
                ],
              ),
              if (showCustomer && a.kind == ActivityKind.fieldVisit) ...[
                const SizedBox(height: 10),
                FieldVisitLocationButton(activity: a, compact: true),
              ],
              if (withButtons) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: a.kind == ActivityKind.call ? VV.success : VV.blue,
                          minimumSize: const Size(0, 44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => runMainAction(context, a),
                        icon: Icon(look.actionIcon, size: 18),
                        label: Text(look.action == 'Call' ? 'Call now' : look.action),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: WaColors.background,
                          foregroundColor: VV.ink,
                          minimumSize: const Size(0, 44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => rescheduleActivityDialog(context, a),
                        child: const Text('Later'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A finished activity in the Done tab.
class _DoneTile extends StatelessWidget {
  const _DoneTile({required this.activity, required this.at});
  final OdooActivity activity;
  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(color: VV.successSoft, shape: BoxShape.circle),
            child: const Icon(Icons.check, color: VV.success),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: WaColors.grey,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                Text(
                  [ActivityLook.typeLabel(a), a.relatedLine].where((s) => s.isNotEmpty).join(' · '),
                  style: const TextStyle(fontSize: 13, color: WaColors.grey),
                ),
              ],
            ),
          ),
          Text(
            formatTime(at),
            style: const TextStyle(fontSize: 12, color: VV.success, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

/// Plan button: pick a customer, then plan an activity for them.
Future<void> pickCustomerAndPlan(BuildContext context) async {
  final customer = await showModalBottomSheet<Customer>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => const _CustomerPicker(),
  );
  if (customer == null || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlanActivityScreen(customer: customer)));
}

class _CustomerPicker extends StatefulWidget {
  const _CustomerPicker();

  @override
  State<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends State<_CustomerPicker> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = app.customers.where((c) => c.matches(_q.text)).take(80).toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Plan for which customer?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _q,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search customer',
                filled: true,
                fillColor: WaColors.background,
                prefixIcon: const Icon(Icons.search, color: WaColors.grey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom + 16),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final c = list[i];
                return ListTile(
                  leading: InitialsAvatar(c.name, size: 42),
                  title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text(c.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.of(context).pop(c),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Field visit: "Set location" (or "Update location" when the customer already
/// has one) opens the Set location screen for the visit's customer.
/// Hidden when the activity is not linked to a contact.
class FieldVisitLocationButton extends StatelessWidget {
  const FieldVisitLocationButton({super.key, required this.activity, this.compact = false});
  final OdooActivity activity;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final customer = customerOfActivity(AppScope.of(context).customers, activity);
    if (customer == null) return const SizedBox.shrink();
    final has = customer.hasLocation;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: Size(0, compact ? 40 : 50),
          foregroundColor: VV.blue,
          side: const BorderSide(color: VV.line),
          shape: compact ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)) : null,
        ),
        onPressed: () =>
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => SetLocationScreen(customer: customer))),
        icon: Icon(has ? Icons.edit_location_alt_outlined : Icons.add_location_alt_outlined, size: compact ? 18 : 20),
        label: Text(has ? 'Update location' : 'Set location', style: TextStyle(fontSize: compact ? 14 : 15)),
      ),
    );
  }
}

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
