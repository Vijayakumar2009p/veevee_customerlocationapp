import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../app_scope.dart';
import '../config.dart';
import '../models/customer.dart';
import '../models/activity.dart';
import '../services/app_state.dart';
import '../services/location_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/photo_strip.dart';
import 'activities_screen.dart';

/// Marks a Field Visit done on site: GPS position and distance from the
/// customer's saved location (warning only), remark, optional photos.
class VisitDoneScreen extends StatefulWidget {
  const VisitDoneScreen({super.key, required this.visit, this.customer});
  final OdooActivity visit;
  final Customer? customer;

  @override
  State<VisitDoneScreen> createState() => _VisitDoneScreenState();
}

class _VisitDoneScreenState extends State<VisitDoneScreen> {
  final _remark = TextEditingController();
  final _photos = PhotoSelection();
  StreamSubscription<Position>? _sub;
  Timer? _timer;
  Position? _best;
  String? _gpsProblem;
  bool _withoutGps = false;
  bool _saveAsLocation = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_capture);
  }

  @override
  void dispose() {
    _stop();
    _remark.dispose();
    super.dispose();
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _capture() async {
    _stop();
    setState(() {
      _gpsProblem = null;
      _withoutGps = false;
      _best = null;
    });
    try {
      await LocationService.ensureReady();
    } on LocationProblemException catch (e) {
      if (mounted) setState(() => _gpsProblem = e.message);
      return;
    }
    if (!mounted) return;
    _timer = Timer(const Duration(seconds: 60), () {
      if (mounted) setState(_stop);
    });
    _sub = LocationService.positions().listen(
      (p) {
        if (!mounted) return;
        if (p.isMocked) {
          _stop();
          setState(() => _gpsProblem = 'Fake GPS detected. Turn off the fake location app.');
          return;
        }
        if (_best == null || p.accuracy < _best!.accuracy) setState(() => _best = p);
        if (p.accuracy <= 8) setState(_stop);
      },
      onError: (Object e) {
        if (!mounted) return;
        _stop();
        if (_best == null) setState(() => _gpsProblem = 'Could not get the GPS location.');
      },
    );
  }

  Customer? get _customer {
    final c = widget.customer;
    return c == null ? null : AppScope.read(context).resolve(c);
  }

  double? get _distance {
    final c = _customer;
    final p = _best;
    if (c == null || p == null || !c.hasLocation) return null;
    return distanceMeters(c.latitude, c.longitude, p.latitude, p.longitude);
  }

  Future<String?> _askFarReason(double distance) {
    final reason = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: VV.goldText, size: 36),
        title: const Text('Far from the customer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are ${formatMeters(distance)} from the customer\'s saved location. '
              'Write why, then tap Mark done.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'e.g. Met at their new shop'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(d, reason.text.trim().isEmpty ? 'No reason given' : reason.text.trim()),
            child: const Text('Mark done'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final fix = _withoutGps ? null : _best;
    if (fix == null && !_withoutGps) return;
    setState(_stop);
    final distance = _distance;
    var farReason = '';
    if (fix == null) {
      farReason = 'GPS not available: ${_gpsProblem ?? 'no reading'}';
    } else if (distance != null && distance > AppConfig.visitFarMeters) {
      final r = await _askFarReason(distance);
      if (r == null || !mounted) return;
      farReason = r;
    }
    setState(() => _saving = true);
    final app = AppScope.read(context);
    try {
      final customer = _customer;
      // A customer without a saved location: save this place as its location too.
      if (fix != null &&
          customer != null &&
          !customer.hasLocation &&
          _saveAsLocation &&
          fix.accuracy <= AppConfig.goodAccuracyMeters * 2) {
        await app.saveLocation(
          LocationInput(
            customer: customer,
            latitude: double.parse(fix.latitude.toStringAsFixed(7)),
            longitude: double.parse(fix.longitude.toStringAsFixed(7)),
            accuracy: fix.accuracy,
            pinMovedMeters: 0,
            capturedAt: DateTime.now(),
            remark: 'Saved while marking a field visit done',
          ),
          sendNow: false, // sent together with the visit below (one wait)
        );
      }
      final ref = await app.markActivityDone(
        ActivityDoneInput(
          activity: widget.visit,
          latitude: fix?.latitude,
          longitude: fix?.longitude,
          accuracy: fix?.accuracy,
          distanceMeters: fix == null ? null : distance,
          farReason: farReason,
          remark: _remark.text,
          photoPaths: List.of(_photos.paths),
        ),
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showActivityResult(context, 'Field visit marked done.', ref);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showMessage(context, 'Could not save: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.visit;
    final customer = _customer;
    final distance = _distance;
    final far = distance != null && distance > AppConfig.visitFarMeters;
    final ready = _withoutGps || _best != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Mark visit done')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                children: [
                  Text(v.relatedLine, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(v.title, style: const TextStyle(fontSize: 16, color: VV.ink)),
                  if (v.note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(v.note, style: const TextStyle(fontSize: 14, color: VV.inkMuted)),
                  ],
                  const SizedBox(height: 20),
                  _gpsCard(customer, distance, far),
                  if (_best != null && customer != null && !customer.hasLocation) ...[
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _saveAsLocation,
                      onChanged: (x) => setState(() => _saveAsLocation = x ?? false),
                      title: const Text('Also save this place as the customer\'s location'),
                      subtitle: const Text('This customer has no location yet.'),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const FieldLabel('Remark', optional: true),
                  TextField(
                    controller: _remark,
                    minLines: 2,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'e.g. Gave 2 calendars to Mr. Kumar'),
                  ),
                  const SizedBox(height: 20),
                  const FieldLabel('Photos', optional: true),
                  PhotoStrip(
                    selection: _photos,
                    enabled: !_saving,
                    chooseProfile: false,
                    onChanged: () => setState(() {}),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: VV.success, minimumSize: const Size(64, 54)),
                  onPressed: !ready || _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(ready ? 'Mark done' : 'Getting location…', style: const TextStyle(fontSize: 17)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gpsCard(Customer? customer, double? distance, bool far) {
    late final IconData icon;
    late final Color color;
    late final Color bg;
    late final String title;
    String? detail;
    Widget? action;
    if (_withoutGps) {
      icon = Icons.location_disabled_outlined;
      color = VV.goldText;
      bg = VV.goldSoft;
      title = 'Without GPS';
      detail = 'The visit is saved without a location. Odoo will show this.';
      action = TextButton(onPressed: _capture, child: const Text('Try GPS again'));
    } else if (_gpsProblem != null) {
      icon = Icons.location_off_outlined;
      color = VV.danger;
      bg = VV.dangerSoft;
      title = _gpsProblem!;
      action = Wrap(
        spacing: 8,
        children: [
          TextButton(onPressed: _capture, child: const Text('Try again')),
          TextButton(onPressed: () => setState(() => _withoutGps = true), child: const Text('Continue without GPS')),
        ],
      );
    } else if (_best == null) {
      icon = Icons.my_location;
      color = VV.blue;
      bg = VV.blueSoft;
      title = 'Getting your location…';
      detail = 'Stay outside or near a window for a better reading.';
    } else if (distance == null) {
      icon = Icons.my_location;
      color = VV.blue;
      bg = VV.blueSoft;
      title = 'Location found (±${_best!.accuracy.round()} m)';
      detail = 'This customer has no saved location to compare with.';
    } else if (far) {
      icon = Icons.warning_amber_rounded;
      color = VV.goldText;
      bg = VV.goldSoft;
      title = '${formatMeters(distance)} from the customer';
      detail = 'You can still mark it done; the app will ask why.';
    } else {
      icon = Icons.where_to_vote;
      color = VV.success;
      bg = VV.successSoft;
      title = 'At the customer · ${formatMeters(distance)} away';
      detail = 'GPS ±${_best!.accuracy.round()} m';
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(VV.radiusLg)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(detail, style: const TextStyle(fontSize: 13, color: VV.ink)),
                ],
                ?action,
              ],
            ),
          ),
          if (_sub != null && _best != null)
            const Padding(
              padding: EdgeInsets.only(left: 8, top: 4),
              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
    );
  }
}
