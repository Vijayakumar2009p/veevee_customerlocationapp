import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../config.dart';
import '../models/customer.dart';
import '../models/activity.dart';
import '../models/pending_action.dart';
import '../utils/format.dart';
import '../utils/validators.dart';
import 'local_store.dart';
import 'odoo_client.dart';

/// Values typed on the "New customer" screen.
class NewCustomerInput {
  NewCustomerInput({
    required this.name,
    required this.isCompany,
    required this.phone,
    this.email = '',
    this.vat = '',
    this.street = '',
    this.city = '',
    this.zip = '',
    this.parent,
    this.photoPaths = const [],
    this.profilePhoto,
    this.contacts = const [],
  });

  final String name;
  final bool isCompany;
  final String phone;
  final String email;
  final String vat;
  final String street;
  final String city;
  final String zip;
  final Customer? parent;

  /// Optional photos (camera or gallery), attached to the "created" log note.
  final List<String> photoPaths;

  /// Index in [photoPaths] of the photo to use as the Odoo profile picture.
  final int? profilePhoto;

  /// Contact persons of a new company ("Add contact"); created under it.
  final List<ContactInput> contacts;
}

/// A contact person added on the "New customer" screen.
class ContactInput {
  const ContactInput({required this.name, this.phone = ''});
  final String name;
  final String phone;
}

/// A location captured on the "Set location" screen.
class LocationInput {
  LocationInput({
    required this.customer,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.pinMovedMeters,
    required this.capturedAt,
    this.address,
    this.remark = '',
    this.photoPath,
  });

  final Customer customer;
  final double latitude;
  final double longitude;
  final double accuracy;
  final double pinMovedMeters;
  final DateTime capturedAt;

  /// Only when the user changed the address: street, street2, city, zip,
  /// state (name) and countryCode.
  final Map<String, String>? address;
  final String remark;
  final String? photoPath;
}

/// Values from the "Mark done" screens.
class ActivityDoneInput {
  ActivityDoneInput({
    required this.activity,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.distanceMeters,
    this.farReason = '',
    this.result = '',
    this.remark = '',
    this.photoPaths = const [],
  });

  final OdooActivity activity;

  /// GPS (Field Visit only); null for other types.
  final double? latitude;
  final double? longitude;
  final double? accuracy;

  /// Distance from the customer's saved location; null when it has none.
  final double? distanceMeters;
  final String farReason;

  /// Quick result, e.g. "Spoke to customer" (calls).
  final String result;
  final String remark;
  final List<String> photoPaths;
}

/// Counts for the Profile tab.
class WorkStats {
  const WorkStats({this.customers = 0, this.locations = 0, this.activities = 0, this.visits = 0});
  final int customers;
  final int locations;
  final int activities;
  final int visits;
}

/// One line of "My history".
class HistoryItem {
  const HistoryItem({required this.at, required this.title, required this.detail, required this.kind});
  final DateTime at;
  final String title;
  final String detail;
  final String kind;
}

class UpdateInfo {
  UpdateInfo({required this.latestVersion, required this.apkUrl, this.notes = ''});
  final String latestVersion;
  final String apkUrl;
  final String notes;
  bool get isNewer => compareVersions(latestVersion, AppConfig.appVersion) > 0;
}

/// Odoo has not created the customer yet; the location waits for it.
class _WaitForCreate implements Exception {}

/// Everything the screens need: login, customers, pending entries and sync.
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState._(this.store);

  final LocalStore store;

  // ---- saved settings ----
  String serverUrl = AppConfig.defaultServerUrl;
  String database = AppConfig.defaultDatabase;
  String login = '';
  String userName = '';
  bool rememberMe = true;
  bool loggedIn = false;
  String odooUserName = '';
  int uid = 0;

  /// Odoo id of the "Field Visit" activity type (module 19.0.1.1.0+); null = feature off.
  int? visitTypeId;
  List<OdooActivity> activities = [];
  List<ActivityType> activityTypes = [];
  bool refreshingActivities = false;
  Map<String, dynamic> userContext = {};
  Set<String> partnerFields = {};
  bool hasAddon = false;
  DateTime? lastRefresh;
  DateTime? lastSyncAt;
  bool largeText = false;

  // Profile (from Odoo res.users)
  int? myPartnerId;
  String companyName = '';
  String userImage = '';

  /// Activities marked done on this phone (last 7 days), for the Done tab.
  List<Map<String, dynamic>> doneLog = [];
  Map<String, int> refToId = {};
  int _nextLocalId = -1;

  // ---- data ----
  List<Customer> customers = [];
  List<PendingAction> queue = [];

  // ---- live status ----
  bool online = true;
  bool syncing = false;
  bool refreshing = false;
  bool needsLogin = false;
  String? refreshError;
  UpdateInfo? update;
  bool updateDismissed = false;

  OdooClient? _client;
  String? _password;
  Timer? _timer;
  final Map<String, int?> _countryIds = {};
  final Map<String, int?> _stateIds = {};

  static Future<AppState> load() async {
    final state = AppState._(await LocalStore.open());
    await state._restore();
    WidgetsBinding.instance.addObserver(state);
    return state;
  }

  // ======================================================================
  // Derived values
  // ======================================================================

  String get phoneField => partnerFields.contains('mobile') ? 'mobile' : 'phone';
  int get withoutLocationCount => customers.where((c) => !c.hasLocation).length;
  int get waitingCount => queue.length;
  int get blockedCount => queue.where((a) => a.blocked).length;

  /// The current copy of [c] (customers are replaced after each refresh,
  /// and a phone-only customer gets its Odoo id after syncing).
  Customer resolve(Customer c) {
    if (c.localRef != null) {
      final byRef = customers.where((x) => x.localRef == c.localRef);
      if (byRef.isNotEmpty) return byRef.first;
      final newId = refToId[c.localRef];
      if (newId != null) {
        final byId = customers.where((x) => x.id == newId);
        if (byId.isNotEmpty) return byId.first;
      }
    }
    final byId = customers.where((x) => x.id == c.id);
    return byId.isNotEmpty ? byId.first : c;
  }

  List<PendingAction> pendingFor(Customer c) => queue
      .where(
        (a) =>
            (a.partnerId != null && a.partnerId == c.id) ||
            (c.localRef != null && (a.ref == c.localRef || a.partnerRef == c.localRef)),
      )
      .toList();

  // ======================================================================
  // Saving and restoring
  // ======================================================================

  Future<void> _restore() async {
    final s = await store.readJson('settings');
    if (s is Map) {
      serverUrl = (s['serverUrl'] ?? serverUrl) as String;
      database = (s['database'] ?? database) as String;
      login = (s['login'] ?? '') as String;
      userName = (s['userName'] ?? '') as String;
      rememberMe = s['rememberMe'] != false;
      loggedIn = s['loggedIn'] == true;
      odooUserName = (s['odooUserName'] ?? '') as String;
      uid = (s['uid'] ?? 0) as int;
      visitTypeId = s['visitTypeId'] as int?;
      final types = s['activityTypes'];
      if (types is List) {
        activityTypes = types.map((e) => ActivityType.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      }
      if (!AppConfig.sharedLogin && odooUserName.isNotEmpty) userName = odooUserName;
      userContext = Map<String, dynamic>.from((s['userContext'] ?? const {}) as Map);
      partnerFields = Set<String>.from((s['partnerFields'] ?? const []) as List);
      hasAddon = s['hasAddon'] == true;
      lastRefresh = DateTime.tryParse((s['lastRefresh'] ?? '') as String);
      lastSyncAt = DateTime.tryParse((s['lastSyncAt'] ?? '') as String);
      largeText = s['largeText'] == true;
      myPartnerId = s['myPartnerId'] as int?;
      companyName = (s['companyName'] ?? '') as String;
      userImage = (s['userImage'] ?? '') as String;
      refToId = Map<String, int>.from((s['refToId'] ?? const {}) as Map);
      _nextLocalId = (s['nextLocalId'] ?? -1) as int;
    }
    final c = await store.readJson('customers');
    if (c is List) {
      customers = c.map((e) => Customer.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    }
    final dl = await store.readJson('doneLog');
    if (dl is List) doneLog = dl.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final v = await store.readJson('activities');
    if (v is List) {
      activities = v.map((e) => OdooActivity.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    }
    final q = await store.readJson('queue');
    if (q is List) {
      queue = q.map((e) => PendingAction.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    }
    if (loggedIn) {
      _password = await store.readSecret('password');
      _client = OdooClient(serverUrl)..sessionId = await store.readSecret('session');
      if (_password == null && _client!.sessionId == null) {
        loggedIn = false;
      } else {
        _startTimer();
      }
    }
  }

  Future<void> _saveSettings() => store.writeJson('settings', {
    'serverUrl': serverUrl,
    'database': database,
    'login': login,
    'userName': userName,
    'rememberMe': rememberMe,
    'loggedIn': loggedIn,
    'odooUserName': odooUserName,
    'uid': uid,
    'visitTypeId': visitTypeId,
    'activityTypes': activityTypes.map((t) => t.toJson()).toList(),
    'userContext': userContext,
    'partnerFields': partnerFields.toList(),
    'hasAddon': hasAddon,
    'lastRefresh': lastRefresh?.toIso8601String(),
    'lastSyncAt': lastSyncAt?.toIso8601String(),
    'largeText': largeText,
    'myPartnerId': myPartnerId,
    'companyName': companyName,
    'userImage': userImage,
    'refToId': refToId,
    'nextLocalId': _nextLocalId,
  });

  Future<void> _saveCustomers() => store.writeJson('customers', customers.map((c) => c.toJson()).toList());

  Future<void> _saveQueue() => store.writeJson('queue', queue.map((a) => a.toJson()).toList());

  Future<void> _saveActivities() => store.writeJson('activities', activities.map((v) => v.toJson()).toList());

  Future<void> setUserName(String name) async {
    userName = name.trim();
    await _saveSettings();
    notifyListeners();
  }

  // ======================================================================
  // Login
  // ======================================================================

  /// Database names on [url]; throws when the server hides them.
  Future<List<String>> listDatabases(String url) async {
    final client = OdooClient(url);
    try {
      return await client.listDatabases();
    } finally {
      client.close();
    }
  }

  Future<void> logIn({
    required String url,
    required String db,
    required String user,
    required String password,
    required bool remember,
  }) async {
    final client = OdooClient(url);
    final info = await client.authenticate(db, user, password);
    if (info == null) {
      client.close();
      throw OdooException(
        'This Odoo user has two-factor authentication switched on. '
        'Use a login without two-factor authentication for the app.',
      );
    }
    final changedServer = client.baseUrl != serverUrl || db != database || user != login;
    _client?.close();
    _client = client;
    _password = password;
    serverUrl = client.baseUrl;
    database = db;
    login = user;
    rememberMe = remember;
    odooUserName = (info['name'] ?? info['username'] ?? user).toString();
    uid = info['uid'] is int ? info['uid'] as int : 0;
    // Each staff member has their own Odoo login: notes use the Odoo user's name.
    // (Customer builds with one shared login still ask each person's name.)
    if (!AppConfig.sharedLogin) userName = odooUserName;
    final ctx = info['user_context'];
    userContext = ctx is Map ? Map<String, dynamic>.from(ctx) : {};
    needsLogin = false;
    online = true;

    if (changedServer) {
      customers = [];
      activities = [];
      visitTypeId = null;
      await _saveActivities();
      queue = [];
      refToId = {};
      lastRefresh = null;
      _countryIds.clear();
      _stateIds.clear();
      await _saveQueue();
      await _saveCustomers();
    }

    await _loadServerFeatures();
    loggedIn = true;
    await store.writeSecret('password', remember ? password : null);
    await store.writeSecret('session', remember ? client.sessionId : null);
    await _saveSettings();
    _startTimer();
    notifyListeners();

    // In the background: pending entries first, then the customer list.
    unawaited(() async {
      await syncNow();
      await refreshCustomers();
      await checkForUpdate();
    }());
  }

  Future<void> logOut() async {
    _timer?.cancel();
    final client = _client;
    _client = null;
    if (client != null) {
      // Tell Odoo in the background; do not wait (the phone may be offline).
      unawaited(client.logout().whenComplete(client.close));
    }
    final photos = [for (final a in queue) ...photosOf(a.payload)];
    _password = null;
    loggedIn = false;
    needsLogin = false;
    customers = [];
    activities = [];
    doneLog = [];
    myPartnerId = null;
    companyName = '';
    userImage = '';
    unawaited(store.writeJson('doneLog', []));
    visitTypeId = null;
    uid = 0;
    queue = [];
    refToId = {};
    lastRefresh = null;
    update = null;
    notifyListeners();
    await store.writeSecret('password', null);
    await store.writeSecret('session', null);
    await _saveQueue();
    await _saveCustomers();
    await _saveSettings();
    for (final p in photos) {
      await store.deletePhoto(p);
    }
  }

  Future<void> _loadServerFeatures() async {
    final fields = await _call(
      'res.partner',
      'fields_get',
      [],
      kwargs: {
        'attributes': ['type'],
      },
    );
    if (fields is Map) partnerFields = fields.keys.map((k) => k.toString()).toSet();
    hasAddon = partnerFields.contains('vv_gps_captured');
  }

  /// Calls Odoo; logs in again by itself when the session has ended.
  Future<dynamic> _call(String model, String method, List<dynamic> args, {Map<String, dynamic>? kwargs}) async {
    final client = _client ??= OdooClient(serverUrl);
    final kw = <String, dynamic>{...?kwargs};
    kw['context'] = {...userContext, ...?(kwargs?['context'] as Map<String, dynamic>?)};
    try {
      final result = await client.callKw(model, method, args, kwargs: kw);
      _setOnline(true);
      return result;
    } on OdooNetworkException {
      _setOnline(false);
      rethrow;
    } on OdooException catch (e) {
      if (!e.isSessionExpired) {
        _setOnline(true);
        rethrow;
      }
      await _renewSession();
      final result = await client.callKw(model, method, args, kwargs: kw);
      _setOnline(true);
      return result;
    }
  }

  Future<void> _renewSession() async {
    final client = _client!;
    if (_password == null || login.isEmpty) {
      _markNeedsLogin();
      throw OdooException('Your session has ended. Please log in again.', name: 'SessionExpired');
    }
    Map<String, dynamic>? info;
    try {
      info = await client.authenticate(database, login, _password!);
    } on OdooException catch (e) {
      if (e.isAccessDenied) {
        _markNeedsLogin();
        throw OdooException('The saved password no longer works. Please log in again.', name: 'SessionExpired');
      }
      rethrow;
    }
    if (info == null) {
      _markNeedsLogin();
      throw OdooException('Please log in again.', name: 'SessionExpired');
    }
    if (rememberMe) await store.writeSecret('session', client.sessionId);
  }

  void _markNeedsLogin() {
    needsLogin = true;
    notifyListeners();
  }

  void _setOnline(bool value) {
    if (online != value) {
      online = value;
      notifyListeners();
    }
  }

  // ======================================================================
  // Customers
  // ======================================================================

  List<String> get _readFields {
    final wanted = [
      'name',
      'is_company',
      'parent_id',
      'phone',
      'mobile',
      'email',
      'vat',
      'street',
      'street2',
      'city',
      'zip',
      'state_id',
      'country_id',
      'partner_latitude',
      'partner_longitude',
      'date_localization',
      'create_date',
      'create_uid',
    ];
    if (partnerFields.isEmpty) {
      return wanted.where((f) => f != 'mobile' && f != 'date_localization').toList();
    }
    return wanted.where(partnerFields.contains).toList();
  }

  /// Contacts shown in the app. Customer builds: only those created by this login.
  List<dynamic> get _listDomain => AppConfig.ownContactsOnly
      ? [
          '&',
          ['create_uid.login', '=ilike', login],
          ...AppConfig.customerDomain,
        ]
      : AppConfig.customerDomain;

  /// Downloads all contacts so search works offline.
  Future<void> refreshCustomers() async {
    if (refreshing || !loggedIn) return;
    refreshing = true;
    refreshError = null;
    notifyListeners();
    final started = DateTime.now();
    try {
      const batch = 500;
      final rows = <Map<String, dynamic>>[];
      var offset = 0;
      while (true) {
        final result = await _call(
          'res.partner',
          'search_read',
          [],
          kwargs: {
            'domain': _listDomain,
            'fields': _readFields,
            'offset': offset,
            'limit': batch,
            'order': 'name asc, id asc',
          },
        );
        final page = (result as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        rows.addAll(page);
        if (page.length < batch) break;
        offset += batch;
      }
      final fresh = rows.map((r) => Customer.fromOdoo(r, phoneField: phoneField)).toList();
      // Keep phone-only customers, and customers created while this download
      // was running (the downloaded pages may not include them yet).
      final freshIds = fresh.map((c) => c.id).toSet();
      fresh.addAll(
        customers.where((c) => c.isLocal || (!freshIds.contains(c.id) && (_linkedAt[c.id]?.isAfter(started) ?? false))),
      );
      customers = fresh;
      _applyPendingToCustomers();
      lastRefresh = DateTime.now();
      await _saveCustomers();
      await _saveSettings();
    } on OdooNetworkException catch (e) {
      refreshError = e.message;
    } on OdooException catch (e) {
      refreshError = e.message;
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }

  /// Puts locations that are still waiting onto the customer list.
  void _applyPendingToCustomers() {
    for (final c in customers) {
      c.pending = false;
    }
    for (final a in queue) {
      final matches = customers.where(
        (c) =>
            (a.partnerId != null && c.id == a.partnerId) ||
            (a.partnerRef != null && c.localRef == a.partnerRef) ||
            (a.kind == PendingAction.create && c.localRef == a.ref),
      );
      for (final c in matches) {
        c.pending = true;
        if (a.kind == PendingAction.location) _applyLocation(c, a.payload);
      }
    }
  }

  void _applyLocation(Customer c, Map<String, dynamic> p) {
    c.latitude = (p['lat'] as num).toDouble();
    c.longitude = (p['lng'] as num).toDouble();
    final captured = DateTime.tryParse((p['capturedAt'] ?? '') as String) ?? DateTime.now();
    c.locationDate = odooDate(captured);
    final addr = p['address'];
    if (addr is Map) {
      c.street = (addr['street'] ?? '') as String;
      c.street2 = (addr['street2'] ?? '') as String;
      c.city = (addr['city'] ?? '') as String;
      c.zip = (addr['zip'] ?? '') as String;
      if ((addr['state'] ?? '').toString().isNotEmpty) c.stateName = addr['state'] as String;
    }
  }

  /// Customers already in Odoo (or on this phone) with the same mobile or GSTIN.
  Future<List<Customer>> findDuplicates(String phone, String gstin) async {
    final mobile = Validators.mobileDigits(phone);
    final gst = Validators.cleanGstin(gstin);
    final found = <int, Customer>{};
    bool same(Customer c) =>
        (mobile.length == 10 && Validators.mobileDigits(c.phone) == mobile) ||
        (gst.isNotEmpty && Validators.cleanGstin(c.vat) == gst);
    for (final c in customers.where(same)) {
      found[c.id] = c;
    }
    try {
      final domain = <dynamic>[];
      if (mobile.length == 10 && gst.isNotEmpty) domain.add('|');
      if (mobile.length == 10) domain.add([phoneField, 'ilike', mobile.substring(5)]);
      if (gst.isNotEmpty) domain.add(['vat', '=ilike', gst]);
      if (domain.isNotEmpty) {
        final rows = await _call(
          'res.partner',
          'search_read',
          [],
          kwargs: {'domain': domain, 'fields': _readFields, 'limit': 20},
        );
        for (final r in (rows as List)) {
          final c = Customer.fromOdoo(Map<String, dynamic>.from(r as Map), phoneField: phoneField);
          if (same(c)) found.putIfAbsent(c.id, () => c);
        }
      }
    } catch (_) {
      // Offline: the phone's own list was checked above.
    }
    return found.values.toList();
  }

  /// Companies for the "works at" field of a new individual.
  List<Customer> companies(String query) =>
      customers.where((c) => c.isCompany && !c.isLocal && c.matches(query)).take(20).toList();

  // ======================================================================
  // Changes made in the field
  // ======================================================================

  String _newRef() => '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}';

  Future<Customer> addCustomer(NewCustomerInput input) async {
    final ref = _newRef();
    final photos = await _keepPhotos(input.photoPaths, ref);
    final vals = <String, dynamic>{
      'name': input.name.trim(),
      'is_company': input.isCompany,
      phoneField: Validators.formatMobile(input.phone),
      if (input.email.trim().isNotEmpty) 'email': input.email.trim(),
      if (input.vat.trim().isNotEmpty) 'vat': Validators.cleanGstin(input.vat),
      if (input.street.trim().isNotEmpty) 'street': input.street.trim(),
      if (input.city.trim().isNotEmpty) 'city': input.city.trim(),
      if (input.zip.trim().isNotEmpty) 'zip': input.zip.trim(),
      if (!input.isCompany && input.parent != null && !input.parent!.isLocal) 'parent_id': input.parent!.id,
      if (partnerFields.contains('customer_rank')) 'customer_rank': 1,
    };
    final gstState = input.vat.trim().isEmpty ? null : Validators.gstinState(input.vat);
    final parent = input.isCompany ? null : input.parent;
    queue.add(
      PendingAction(
        ref: ref,
        kind: PendingAction.create,
        createdAt: DateTime.now(),
        customerName: input.name.trim(),
        payload: {
          'vals': vals,
          'countryCode': 'IN',
          if (gstState != null) 'state': gstState,
          if (parent != null && parent.isLocal) 'parentRef': parent.localRef,
          if (photos.isNotEmpty) 'photos': photos,
          if (photos.isNotEmpty) 'profile': (input.profilePhoto ?? 0).clamp(0, photos.length - 1),
          'userName': userName,
        },
      ),
    );
    final customer = Customer(
      id: _nextLocalId--,
      localRef: ref,
      name: input.name.trim(),
      isCompany: input.isCompany,
      parentId: input.parent?.id,
      parentName: input.parent?.name ?? '',
      phone: Validators.formatMobile(input.phone),
      email: input.email.trim(),
      vat: Validators.cleanGstin(input.vat),
      street: input.street.trim(),
      city: input.city.trim(),
      zip: input.zip.trim(),
      stateName: gstState ?? '',
      pending: true,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      createdBy: uid == 0 ? null : uid,
    );
    customers.insert(0, customer);
    // Extra contact persons (company or individual): each one is created
    // under the new customer once it is in Odoo.
    for (final person in input.contacts.where((p) => p.name.trim().isNotEmpty)) {
      final personRef = _newRef();
      final personPhone = person.phone.trim().isEmpty ? '' : Validators.formatMobile(person.phone);
      queue.add(
        PendingAction(
          ref: personRef,
          kind: PendingAction.create,
          createdAt: DateTime.now(),
          customerName: '${person.name.trim()} (${input.name.trim()})',
          payload: {
            'vals': <String, dynamic>{
              'name': person.name.trim(),
              'is_company': false,
              'type': 'contact',
              if (personPhone.isNotEmpty) phoneField: personPhone,
              if (partnerFields.contains('customer_rank')) 'customer_rank': 1,
            },
            'parentRef': ref,
            'userName': userName,
          },
        ),
      );
      customers.insert(
        1,
        Customer(
          id: _nextLocalId--,
          localRef: personRef,
          name: person.name.trim(),
          parentName: input.name.trim(),
          phone: personPhone,
          city: input.city.trim(),
          pending: true,
          createdAt: DateTime.now().toUtc().toIso8601String(),
          createdBy: uid == 0 ? null : uid,
        ),
      );
    }
    await _saveQueue();
    await _saveCustomers();
    await _saveSettings();
    notifyListeners();
    try {
      await syncNow();
    } catch (_) {
      // Saved on the phone; it will be sent later.
    }
    return resolve(customer);
  }

  /// Saves the location on the phone, then tries to send it to Odoo.
  /// Returns the entry's reference: use [pendingByRef] to see whether it
  /// reached Odoo (no entry), still waits, or was refused.
  Future<String> saveLocation(LocationInput input) async {
    final ref = _newRef();
    String? photo;
    if (input.photoPath != null) photo = await store.keepPhoto(input.photoPath!, ref);
    final c = resolve(input.customer);
    final action = PendingAction(
      ref: ref,
      kind: PendingAction.location,
      createdAt: DateTime.now(),
      customerName: c.name,
      partnerId: c.isLocal ? null : c.id,
      partnerRef: c.isLocal ? c.localRef : null,
      payload: {
        'lat': input.latitude,
        'lng': input.longitude,
        'accuracy': input.accuracy,
        'pinMoved': input.pinMovedMeters,
        'capturedAt': input.capturedAt.toIso8601String(),
        if (input.address != null) 'address': input.address,
        'remark': input.remark.trim(),
        if (photo != null) 'photo': photo,
        'userName': userName,
      },
    );
    // A newer location replaces one still waiting for the same customer.
    bool sameCustomer(PendingAction a) => c.isLocal
        ? a.partnerRef == c.localRef
        : (a.partnerId == c.id || (a.partnerRef != null && refToId[a.partnerRef] == c.id));
    final older = queue.where((a) => a.kind == PendingAction.location && sameCustomer(a)).toList();
    for (final a in older) {
      queue.remove(a);
      await _deletePhotos(a.payload);
    }
    queue.add(action);
    _applyLocation(c, action.payload);
    c.pending = true;
    await _saveQueue();
    await _saveCustomers();
    notifyListeners();
    try {
      await syncNow();
    } catch (_) {
      // Saved on the phone; it will be sent later.
    }
    return ref;
  }

  PendingAction? pendingByRef(String ref) {
    for (final a in queue) {
      if (a.ref == ref) return a;
    }
    return null;
  }

  // ======================================================================
  // Sync
  // ======================================================================

  void _startTimer() {
    _timer?.cancel();
    var ticks = 0;
    _timer = Timer.periodic(AppConfig.autoSyncInterval, (_) {
      if (queue.any((a) => !a.blocked)) syncNow();
      // New activities from the office show up within about 5 minutes.
      if (++ticks % 5 == 0 && loggedIn && !needsLogin) refreshActivities();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && loggedIn && !needsLogin) {
      refreshAll(onlyIfOld: true);
    }
  }

  /// Sends waiting entries, then reloads the customer list.
  Future<void> refreshAll({bool onlyIfOld = false}) async {
    await syncNow();
    final old = lastRefresh == null || DateTime.now().difference(lastRefresh!) > const Duration(minutes: 10);
    if (!onlyIfOld || old) await refreshCustomers();
    await refreshActivities();
    if (myPartnerId == null || !onlyIfOld) unawaited(loadProfile());
  }

  Future<void>? _syncRun;
  bool _syncAgain = false;

  /// Sends waiting entries. If a sync is already running, the caller waits
  /// for it, and anything added meanwhile is sent in the same run.
  Future<void> syncNow() {
    if (!loggedIn || needsLogin || queue.isEmpty) return Future<void>.value();
    final running = _syncRun;
    if (running != null) {
      _syncAgain = true;
      return running;
    }
    final run = _syncLoop();
    _syncRun = run;
    return run.whenComplete(() => _syncRun = null);
  }

  Future<void> _syncLoop() async {
    syncing = true;
    notifyListeners();
    try {
      var reachedServer = true;
      do {
        _syncAgain = false;
        reachedServer = await _syncPass();
      } while (_syncAgain && reachedServer && !needsLogin);
      if (reachedServer) lastSyncAt = DateTime.now();
    } finally {
      syncing = false;
      _applyPendingToCustomers();
      await _saveQueue();
      await _saveCustomers();
      await _saveSettings();
      notifyListeners();
    }
  }

  /// One pass over the queue. Returns false when it stopped because the
  /// server could not be reached.
  Future<bool> _syncPass() async {
    for (final action in List<PendingAction>.of(queue)) {
      if (action.blocked || !queue.contains(action)) continue;
      try {
        if (action.kind == PendingAction.create) {
          await _sendCreate(action);
        } else if (action.kind == PendingAction.photos) {
          await _sendPhotos(action);
        } else if (action.kind == PendingAction.visitCreate) {
          await _sendActivityCreate(action);
        } else if (action.kind == PendingAction.visitDone) {
          await _sendActivityDone(action);
        } else if (action.kind == PendingAction.activityDate) {
          await _sendActivityDate(action);
        } else {
          await _sendLocation(action);
        }
        queue.remove(action);
        await _deletePhotos(action.payload);
      } on _WaitForCreate {
        continue;
      } on OdooNetworkException catch (e) {
        action.lastError = e.message;
        await _saveQueue();
        return false; // offline: try again later
      } on OdooException catch (e) {
        if (needsLogin) return false;
        action.attempts++;
        action.lastError = e.message;
        action.blocked = true; // Odoo refused it; needs a person to look
      } on FileSystemException {
        action.payload.remove('photo'); // photo file lost: send without it
        action.payload['photos'] = [
          for (final p in photosOf(action.payload))
            if (File(p).existsSync()) p,
        ];
      } catch (e) {
        // Anything unexpected: keep the entry and try again later.
        action.attempts++;
        action.lastError = e.toString();
        await _saveQueue();
        return false;
      }
      await _saveQueue();
    }
    return true;
  }

  Future<void> retry(PendingAction action) async {
    action.blocked = false;
    action.lastError = '';
    await _saveQueue();
    notifyListeners();
    await syncNow();
  }

  Future<void> discard(PendingAction action) async {
    final removed = [action];
    if (action.kind == PendingAction.create) {
      customers.removeWhere((c) => c.localRef == action.ref);
      removed.addAll(queue.where((a) => a.partnerRef == action.ref && a.partnerId == null));
      activities.removeWhere((v) => v.partnerRef == action.ref && v.partnerId == null);
    }
    if (action.kind == PendingAction.visitCreate) {
      activities.removeWhere((v) => v.localRef == action.ref);
      removed.addAll(queue.where((a) => a.payload['activityRef'] == action.ref && a.payload['activityId'] == null));
    }
    if (action.kind == PendingAction.visitDone) {
      unawaited(refreshActivities()); // the activity shows again in the list
    }
    for (final a in removed) {
      queue.remove(a);
      await _deletePhotos(a.payload);
    }
    _applyPendingToCustomers();
    await _saveQueue();
    await _saveCustomers();
    await _saveActivities();
    notifyListeners();
  }

  /// Customers created in Odoo during this app session, with the time.
  final Map<int, DateTime> _linkedAt = {};

  void _linkCreated(PendingAction a, int newId) {
    refToId[a.ref] = newId;
    for (final v in activities.where((v) => v.partnerRef == a.ref)) {
      v.partnerId = newId;
    }
    _linkedAt[newId] = DateTime.now();
    for (final c in customers.where((c) => c.localRef == a.ref)) {
      c.id = newId;
      c.localRef = null;
    }
    for (final other in queue.where((x) => x.partnerRef == a.ref)) {
      other.partnerId = newId;
    }
  }

  /// After a timeout the customer may already be in Odoo: look for it.
  Future<int?> _findCreated(Map<String, dynamic> vals, DateTime createdAt) async {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = createdAt.toUtc().subtract(const Duration(hours: 1));
    final since = '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
    final rows = await _call(
      'res.partner',
      'search_read',
      [],
      kwargs: {
        'domain': [
          ['name', '=', vals['name']],
          [phoneField, '=', vals[phoneField]],
          ['create_date', '>=', since],
        ],
        'fields': ['id'],
        'limit': 1,
        'order': 'id desc',
      },
    );
    final list = rows as List;
    return list.isEmpty ? null : (list.first as Map)['id'] as int;
  }

  Future<void> _sendCreate(PendingAction a) async {
    // Already created (the app stopped right after): link it again, then
    // finish the log note below if it was not posted yet.
    final known = refToId[a.ref];
    if (known != null) {
      _linkCreated(a, known);
      await _postCreatedNote(a, known);
      return;
    }
    final vals = Map<String, dynamic>.from(a.payload['vals'] as Map);
    final ids = await _stateAndCountry(
      (a.payload['state'] ?? '') as String,
      (a.payload['countryCode'] ?? '') as String,
    );
    vals.addAll(ids);
    // The company may itself have been created offline: wait for it.
    final parentRef = a.payload['parentRef'] as String?;
    if (parentRef != null) {
      final parentId = refToId[parentRef];
      if (parentId == null) throw _WaitForCreate();
      vals['parent_id'] = parentId;
    }

    // An earlier try may have reached Odoo even though no answer came back.
    int? newId;
    if (a.payload['sent'] == true) newId = await _findCreated(vals, a.createdAt);
    if (newId == null) {
      a.payload['sent'] = true;
      await _saveQueue();
      final result = await _call('res.partner', 'create', [vals]);
      newId = result is int ? result : (result as List).first as int;
    }
    _linkCreated(a, newId);
    await _saveSettings();
    await _postCreatedNote(a, newId);
  }

  /// "Customer created…" log note, with the customer photos attached, and
  /// the chosen photo set as profile picture. If the network drops, the entry
  /// stays waiting and only these steps are sent again (the customer is not
  /// created twice).
  Future<void> _postCreatedNote(PendingAction a, int partnerId) async {
    final profileSet = await _setProfilePicture(a, partnerId);
    if (a.payload['notePosted'] == true) return;
    try {
      final attachments = await _uploadPhotos(a, 'Customer photo', skipProfile: profileSet);
      final extra = StringBuffer();
      if (attachments.isNotEmpty) {
        extra.write(attachments.length == 1 ? ' Photo attached.' : ' ${attachments.length} photos attached.');
      }
      if (profileSet) extra.write(' Profile picture set.');
      await _postNote(
        partnerId,
        'Customer created with VeeVee Field Locator by '
        '${_by(a)} on ${formatDateTime(a.createdAt)}.$extra',
        attachmentIds: attachments,
      );
    } on OdooNetworkException {
      rethrow; // try the note again later
    } on OdooException {
      // The customer exists; Odoo refused only the note. Do not block on it.
    }
    a.payload['notePosted'] = true;
    await _saveQueue();
  }

  /// Photos added later to an existing customer (customer page → Add photos).
  Future<void> _sendPhotos(PendingAction a) async {
    final partnerId = a.partnerId ?? (a.partnerRef != null ? refToId[a.partnerRef] : null);
    if (partnerId == null) throw _WaitForCreate();
    a.partnerId = partnerId;
    final profileSet = await _setProfilePicture(a, partnerId);
    if (a.payload['notePosted'] == true) return;
    final attachments = await _uploadPhotos(a, 'Site photo', skipProfile: profileSet);
    if (attachments.isEmpty && !profileSet) return; // photo files gone: nothing to send
    final n = attachments.length;
    final parts = [
      if (n > 0) n == 1 ? '1 photo attached.' : '$n photos attached.',
      if (profileSet) 'Profile picture updated.',
    ];
    await _postNote(
      partnerId,
      '${n > 0 ? 'Photos added' : 'Profile picture changed'} with VeeVee Field Locator by '
      '${_by(a)} on ${formatDateTime(a.createdAt)}. ${parts.join(' ')}',
      attachmentIds: attachments,
    );
    a.payload['notePosted'] = true;
    await _saveQueue();
  }

  /// Sets the chosen photo as the contact's profile picture (once).
  /// Returns true when it is (or already was) set.
  Future<bool> _setProfilePicture(PendingAction a, int partnerId) async {
    if (a.payload['profileDone'] == true) return a.payload['profileSet'] == true;
    final photos = photosOf(a.payload);
    final index = (a.payload['profile'] as int?) ?? 0;
    var ok = false;
    if (photos.isNotEmpty && index >= 0 && index < photos.length) {
      final file = File(photos[index]);
      if (await file.exists()) {
        try {
          await _call('res.partner', 'write', [
            [partnerId],
            {'image_1920': base64Encode(await file.readAsBytes())},
          ]);
          ok = true;
        } on OdooNetworkException {
          rethrow;
        } on OdooException {
          // Refused (e.g. the Odoo module is older): keep the photos in the note.
        }
      }
    }
    a.payload['profileDone'] = true;
    a.payload['profileSet'] = ok;
    await _saveQueue();
    return ok;
  }

  /// Uploads every photo file still on the phone; returns attachment ids.
  /// The profile picture is left out when it was set (it is already the
  /// contact's picture, so it is not repeated in the log note).
  Future<List<int>> _uploadPhotos(PendingAction a, String title, {bool skipProfile = false}) async {
    final all = photosOf(a.payload);
    final profile = skipProfile ? (a.payload['profile'] as int?) ?? 0 : -1;
    final photos = [
      for (var i = 0; i < all.length; i++)
        if (i != profile && await File(all[i]).exists()) all[i],
    ];
    final ids = <int>[];
    for (var i = 0; i < photos.length; i++) {
      final n = photos.length > 1 ? ' ${i + 1}' : '';
      ids.add(await _uploadPhoto(photos[i], '$title$n ${formatDate(a.createdAt)}.jpg'));
    }
    return ids;
  }

  /// All photo files of an entry (new list, plus the older single `photo`).
  static List<String> photosOf(Map<String, dynamic> payload) => [
    ...((payload['photos'] as List?) ?? const []).cast<String>(),
    if (payload['photo'] is String && (payload['photo'] as String).isNotEmpty) payload['photo'] as String,
  ];

  Future<void> _deletePhotos(Map<String, dynamic> payload) async {
    for (final p in photosOf(payload)) {
      await store.deletePhoto(p);
    }
  }

  /// Copies picked photos into the app's own folder (the picker's copies are temporary).
  Future<List<String>> _keepPhotos(List<String> paths, String ref) async => [
    for (var i = 0; i < paths.length; i++) await store.keepPhoto(paths[i], '$ref-$i'),
  ];

  /// Queues photos for an existing customer (and optionally a new profile picture).
  Future<String> addPhotos(Customer customer, List<String> paths, int? profile) async {
    final ref = _newRef();
    final c = resolve(customer);
    final photos = await _keepPhotos(paths, ref);
    queue.add(
      PendingAction(
        ref: ref,
        kind: PendingAction.photos,
        createdAt: DateTime.now(),
        customerName: c.name,
        partnerId: c.isLocal ? null : c.id,
        partnerRef: c.isLocal ? c.localRef : null,
        payload: {'photos': photos, if (profile != null) 'profile': profile, 'userName': userName},
      ),
    );
    c.pending = true;
    await _saveQueue();
    await _saveCustomers();
    notifyListeners();
    try {
      await syncNow();
    } catch (_) {
      // Saved on the phone; it will be sent later.
    }
    return ref;
  }

  /// Uploads a photo for the next log note and returns its attachment id.
  Future<int> _uploadPhoto(String path, String name) async {
    final bytes = await File(path).readAsBytes();
    final id = await _call('ir.attachment', 'create', [
      {
        'name': name,
        'datas': base64Encode(bytes),
        'mimetype': 'image/jpeg',
        'res_model': 'mail.compose.message',
        'res_id': 0,
      },
    ]);
    return id is int ? id : (id as List).first as int;
  }

  Future<void> _sendLocation(PendingAction a) async {
    final partnerId = a.partnerId ?? (a.partnerRef != null ? refToId[a.partnerRef] : null);
    if (partnerId == null) throw _WaitForCreate();
    a.partnerId = partnerId;

    final p = a.payload;
    final lat = (p['lat'] as num).toDouble();
    final lng = (p['lng'] as num).toDouble();
    final accuracy = (p['accuracy'] as num).toDouble();
    final captured = DateTime.tryParse((p['capturedAt'] ?? '') as String) ?? a.createdAt;

    // Latitude/longitude must be in the same write as any address change,
    // otherwise Odoo resets them to 0.
    final vals = <String, dynamic>{
      'partner_latitude': lat,
      'partner_longitude': lng,
      if (partnerFields.contains('date_localization')) 'date_localization': odooDate(captured),
      if (hasAddon) 'vv_gps_captured': true,
      if (hasAddon) 'vv_gps_accuracy': accuracy,
      if (hasAddon) 'vv_gps_by': _by(a),
    };
    final addr = p['address'];
    if (addr is Map) {
      for (final f in ['street', 'street2', 'city', 'zip']) {
        vals[f] = (addr[f] ?? '').toString();
      }
      vals.addAll(await _stateAndCountry((addr['state'] ?? '').toString(), (addr['countryCode'] ?? '').toString()));
    }
    await _call('res.partner', 'write', [
      [partnerId],
      vals,
    ]);

    final photo = p['photo'] as String?;
    final attachments = <int>[
      if (photo != null && photo.isNotEmpty) await _uploadPhoto(photo, 'Site photo ${formatDate(captured)}.jpg'),
    ];

    final moved = (p['pinMoved'] as num? ?? 0).toDouble();
    final remark = (p['remark'] ?? '').toString();
    final late = DateTime.now().difference(captured) > const Duration(minutes: 5);
    final note = StringBuffer()
      ..write(
        'Location set on site with VeeVee Field Locator by ${_by(a)} '
        'on ${formatDateTime(captured)}. ',
      )
      ..write('Lat ${formatCoord(lat)}, Long ${formatCoord(lng)}. ')
      ..write('GPS accuracy ${accuracy.round()} m.');
    if (moved >= 5) note.write(' Pin moved ${formatMeters(moved)} from the GPS point.');
    if (addr is Map) note.write(' Address updated from site.');
    if (remark.isNotEmpty) note.write(' Remark: $remark');
    if (late) note.write(' (Saved offline, sent ${formatDateTime(DateTime.now())}.)');
    await _postNote(partnerId, note.toString(), attachmentIds: attachments);
  }

  String _by(PendingAction a) {
    final n = (a.payload['userName'] ?? '').toString();
    return n.isNotEmpty ? n : (userName.isNotEmpty ? userName : odooUserName);
  }

  Future<void> _postNote(int partnerId, String text, {List<int> attachmentIds = const []}) {
    return _call(
      'res.partner',
      'message_post',
      [
        [partnerId],
      ],
      kwargs: {
        'body': text,
        'message_type': 'comment',
        'subtype_xmlid': 'mail.mt_note',
        if (attachmentIds.isNotEmpty) 'attachment_ids': attachmentIds,
      },
    );
  }

  /// Odoo ids for a state name (e.g. "Tamil Nadu") and country code ("IN").
  Future<Map<String, dynamic>> _stateAndCountry(String state, String countryCode) async {
    final result = <String, dynamic>{};
    if (countryCode.isEmpty) return result;
    if (!_countryIds.containsKey(countryCode)) {
      final rows = await _call(
        'res.country',
        'search_read',
        [],
        kwargs: {
          'domain': [
            ['code', '=', countryCode],
          ],
          'fields': ['id'],
          'limit': 1,
        },
      );
      _countryIds[countryCode] = (rows as List).isEmpty ? null : (rows.first as Map)['id'] as int;
    }
    final countryId = _countryIds[countryCode];
    if (countryId == null) return result;
    result['country_id'] = countryId;
    if (state.isEmpty) return result;
    final key = '$countryCode/${state.toLowerCase()}';
    if (!_stateIds.containsKey(key)) {
      final rows = await _call(
        'res.country.state',
        'search_read',
        [],
        kwargs: {
          'domain': [
            ['country_id', '=', countryId],
            '|',
            ['name', '=ilike', state],
            ['code', '=ilike', state],
          ],
          'fields': ['id'],
          'limit': 1,
        },
      );
      _stateIds[key] = (rows as List).isEmpty ? null : (rows.first as Map)['id'] as int;
    }
    final stateId = _stateIds[key];
    if (stateId != null) result['state_id'] = stateId;
    return result;
  }

  // ======================================================================
  // My Activities: every mail.activity assigned to this user (To-Do, Email,
  // Call, Meeting, Document, Field Visit...), on contacts or other records.
  // ======================================================================

  /// Field visits need the Odoo module; all other activity types work on any Odoo.
  bool get activitiesEnabled => loggedIn;
  bool get fieldVisitsEnabled => visitTypeId != null;

  /// Open activities, earliest first.
  List<OdooActivity> get openActivities => List.of(activities)..sort((a, b) => a.deadline.compareTo(b.deadline));

  int get activitiesDueCount => activities.where((v) => v.daysLeft <= 0).length;
  int get activitiesOverdueCount => activities.where((v) => v.daysLeft < 0).length;

  List<OdooActivity> activitiesFor(Customer c) {
    final x = resolve(c);
    return openActivities
        .where((v) => (!x.isLocal && v.partnerId == x.id) || (x.localRef != null && v.partnerRef == x.localRef))
        .toList();
  }

  /// Activity types staff can plan (contacts), Field Visit first when present.
  List<ActivityType> get plannableTypes {
    final list = List.of(activityTypes);
    list.sort((a, b) => (b.id == visitTypeId ? 1 : 0) - (a.id == visitTypeId ? 1 : 0));
    return list;
  }

  /// Downloads this user's open activities; ones changed on the phone (planned,
  /// done or moved, not yet sent) are kept as they are on the phone.
  Future<void> refreshActivities() async {
    if (!loggedIn || needsLogin || refreshingActivities) return;
    refreshingActivities = true;
    notifyListeners();
    try {
      if (uid == 0) await _loadUid();
      if (uid == 0) return;
      await _loadActivityTypes();
      final rows = await _call(
        'mail.activity',
        'search_read',
        [
          [
            ['user_id', '=', uid],
          ],
        ],
        kwargs: {
          'fields': [
            'res_model',
            'res_id',
            'res_name',
            'activity_type_id',
            'activity_category',
            'icon',
            'summary',
            'note',
            'date_deadline',
            'create_uid',
          ],
          'order': 'date_deadline asc, id asc',
          'limit': 500,
        },
      );
      final doneIds = {
        for (final a in queue.where((a) => a.kind == PendingAction.visitDone)) a.payload['activityId'] as int?,
      };
      final fresh = [
        for (final r in (rows as List).cast<Map>())
          if (!doneIds.contains(r['id']))
            OdooActivity.fromOdoo(Map<String, dynamic>.from(r), fieldVisitTypeId: visitTypeId),
      ];
      await _fillPartners(fresh);
      // Dates moved on the phone and not yet sent:
      for (final a in queue.where((a) => a.kind == PendingAction.activityDate)) {
        final d = DateTime.tryParse((a.payload['date'] ?? '').toString());
        for (final v in fresh.where((v) => v.id != null && v.id == a.payload['activityId'])) {
          if (d != null) v.deadline = d;
        }
      }
      // Planned on the phone and not yet sent:
      final local = activities.where((v) => v.isLocal && queue.any((a) => a.ref == v.localRef)).toList();
      activities = [...fresh, ...local];
      await _saveActivities();
    } on OdooException {
      // Offline or refused: keep the list we have.
    } finally {
      refreshingActivities = false;
      notifyListeners();
    }
  }

  Future<void> _loadActivityTypes() async {
    try {
      final rows = await _call(
        'mail.activity.type',
        'search_read',
        [
          [
            '|',
            ['res_model', '=', false],
            ['res_model', '=', 'res.partner'],
          ],
        ],
        kwargs: {
          'fields': ['name', 'icon', 'category'],
          'order': 'sequence asc, id asc',
        },
      );
      activityTypes = [
        for (final r in (rows as List).cast<Map>())
          ActivityType(
            id: r['id'] as int,
            name: (r['name'] ?? '').toString(),
            icon: r['icon'] is String ? r['icon'] as String : '',
            category: r['category'] is String ? r['category'] as String : 'default',
          ),
      ];
      await _saveSettings();
    } on OdooNetworkException {
      rethrow;
    } on OdooException {
      // Keep the types we have.
    }
  }

  /// Customer name, phone and email for each activity: the contact itself, or
  /// the partner of the record (quotation, lead, invoice...).
  Future<void> _fillPartners(List<OdooActivity> list) async {
    final byModel = <String, Set<int>>{};
    for (final v in list) {
      if (v.resModel != 'res.partner' && v.resId != null) {
        byModel.putIfAbsent(v.resModel, () => {}).add(v.resId!);
      }
    }
    for (final entry in byModel.entries) {
      try {
        final rows = await _call(
          entry.key,
          'read',
          [entry.value.toList()],
          kwargs: {
            'fields': ['partner_id'],
          },
        );
        final partnerOf = <int, (int, String)>{};
        for (final r in (rows as List).cast<Map>()) {
          final p = r['partner_id'];
          if (p is List && p.length >= 2) partnerOf[r['id'] as int] = (p[0] as int, p[1].toString());
        }
        for (final v in list.where((v) => v.resModel == entry.key)) {
          final p = partnerOf[v.resId];
          if (p != null) {
            v.partnerId = p.$1;
            v.customerName = p.$2;
          }
        }
      } on OdooNetworkException {
        rethrow;
      } on OdooException {
        // No partner field or no access: show the record name only.
      }
    }
    // Phone and email: from the customers on the phone, else from Odoo.
    final missing = <int>{};
    for (final v in list) {
      final id = v.partnerId;
      if (id == null) continue;
      final c = customers.where((c) => c.id == id).firstOrNull;
      if (c != null) {
        v.phone = c.phone;
        v.email = c.email;
        if (v.customerName.isEmpty) v.customerName = c.name;
      } else {
        missing.add(id);
      }
    }
    if (missing.isEmpty) return;
    try {
      final rows = await _call(
        'res.partner',
        'read',
        [missing.toList()],
        kwargs: {
          'fields': ['name', phoneField, 'phone', 'email'],
        },
      );
      final info = {for (final r in (rows as List).cast<Map>()) r['id'] as int: r};
      for (final v in list) {
        final r = info[v.partnerId];
        if (r == null) continue;
        String s(Object? x) => x is String ? x : '';
        v.phone = s(r[phoneField]).isNotEmpty ? s(r[phoneField]) : s(r['phone']);
        v.email = s(r['email']);
        if (v.customerName.isEmpty) v.customerName = s(r['name']);
      }
    } on OdooNetworkException {
      rethrow;
    } on OdooException {
      // Not allowed to read those contacts: no Call/Email shortcut.
    }
  }

  Future<void> _loadUid() async {
    final ids = await _call(
      'res.users',
      'search',
      [
        [
          ['login', '=', login],
        ],
      ],
      kwargs: {'limit': 1},
    );
    if (ids is List && ids.isNotEmpty) {
      uid = ids.first as int;
      await _saveSettings();
    }
  }

  /// Plans an activity for this user on a customer (any type).
  Future<String> scheduleActivity(
    Customer customer, {
    required ActivityType type,
    required String summary,
    required DateTime date,
    String note = '',
  }) async {
    final ref = _newRef();
    final c = resolve(customer);
    final day = DateTime(date.year, date.month, date.day);
    queue.add(
      PendingAction(
        ref: ref,
        kind: PendingAction.visitCreate,
        createdAt: DateTime.now(),
        customerName: c.name,
        partnerId: c.isLocal ? null : c.id,
        partnerRef: c.isLocal ? c.localRef : null,
        payload: {
          'typeId': type.id,
          'typeName': type.name,
          'summary': summary.trim(),
          'note': note.trim(),
          'date': odooDate(day),
          'userName': userName,
        },
      ),
    );
    activities.add(
      OdooActivity(
        localRef: ref,
        partnerId: c.isLocal ? null : c.id,
        partnerRef: c.isLocal ? c.localRef : null,
        customerName: c.name,
        resId: c.isLocal ? null : c.id,
        resName: c.name,
        typeId: type.id,
        typeName: type.name,
        icon: type.icon,
        category: type.category,
        isFieldVisit: type.id == visitTypeId,
        summary: summary.trim(),
        note: note.trim(),
        deadline: day,
        assignedBy: odooUserName,
        phone: c.phone,
        email: c.email,
      ),
    );
    await _saveQueue();
    await _saveActivities();
    notifyListeners();
    try {
      await syncNow();
    } catch (_) {
      // Saved on the phone; it will be sent later.
    }
    return ref;
  }

  /// Marks an activity done. Returns the queue reference.
  Future<String> markActivityDone(ActivityDoneInput input) async {
    final ref = _newRef();
    final v = input.activity;
    final photos = await _keepPhotos(input.photoPaths, ref);
    queue.add(
      PendingAction(
        ref: ref,
        kind: PendingAction.visitDone,
        createdAt: DateTime.now(),
        customerName: v.customerName.isNotEmpty ? v.customerName : v.resName,
        partnerId: v.partnerId,
        partnerRef: v.partnerId == null ? v.partnerRef : null,
        payload: {
          'activityId': v.id,
          if (v.id == null) 'activityRef': v.localRef,
          'summary': v.title,
          'typeName': v.typeName,
          'resModel': v.resModel,
          'resId': v.resId,
          if (input.latitude != null) 'lat': input.latitude,
          if (input.longitude != null) 'lng': input.longitude,
          if (input.accuracy != null) 'accuracy': input.accuracy,
          if (v.isFieldVisit) 'gps': true,
          'distance': input.distanceMeters,
          'farReason': input.farReason.trim(),
          'result': input.result.trim(),
          'remark': input.remark.trim(),
          if (photos.isNotEmpty) 'photos': photos,
          'userName': userName,
        },
      ),
    );
    activities.remove(v);
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    doneLog
      ..removeWhere((e) => (DateTime.tryParse((e['doneAt'] ?? '') as String) ?? cutoff).isBefore(cutoff))
      ..insert(0, {
        ...v.toJson(),
        'doneAt': DateTime.now().toIso8601String(),
        'result': input.result.trim(),
        'remark': input.remark.trim(),
      });
    await store.writeJson('doneLog', doneLog);
    await _saveQueue();
    await _saveActivities();
    notifyListeners();
    try {
      await syncNow();
    } catch (_) {
      // Saved on the phone; it will be sent later.
    }
    return ref;
  }

  /// Activities marked done today on this phone, newest first.
  List<(OdooActivity, DateTime)> get doneToday {
    final now = DateTime.now();
    final out = <(OdooActivity, DateTime)>[];
    for (final e in doneLog) {
      final at = DateTime.tryParse((e['doneAt'] ?? '') as String);
      if (at == null || at.year != now.year || at.month != now.month || at.day != now.day) continue;
      out.add((OdooActivity.fromJson(e), at));
    }
    return out;
  }

  /// Moves an activity to another date.
  Future<String> rescheduleActivity(OdooActivity v, DateTime date) async {
    final day = DateTime(date.year, date.month, date.day);
    // Planned on the phone and not sent yet: just change the plan.
    if (v.isLocal) {
      final plan = queue.where((a) => a.ref == v.localRef).firstOrNull;
      if (plan != null) {
        plan.payload['date'] = odooDate(day);
        v.deadline = day;
        await _saveQueue();
        await _saveActivities();
        notifyListeners();
        return plan.ref;
      }
    }
    final ref = _newRef();
    queue.removeWhere((a) => a.kind == PendingAction.activityDate && a.payload['activityId'] == v.id && v.id != null);
    queue.add(
      PendingAction(
        ref: ref,
        kind: PendingAction.activityDate,
        createdAt: DateTime.now(),
        customerName: v.customerName.isNotEmpty ? v.customerName : v.resName,
        partnerId: v.partnerId,
        payload: {
          'activityId': v.id,
          if (v.id == null) 'activityRef': v.localRef,
          'date': odooDate(day),
          'summary': v.title,
          'userName': userName,
        },
      ),
    );
    v.deadline = day;
    await _saveQueue();
    await _saveActivities();
    notifyListeners();
    try {
      await syncNow();
    } catch (_) {
      // Saved on the phone; it will be sent later.
    }
    return ref;
  }

  Future<void> _sendActivityCreate(PendingAction a) async {
    final partnerId = a.partnerId ?? (a.partnerRef != null ? refToId[a.partnerRef] : null);
    if (partnerId == null) throw _WaitForCreate();
    a.partnerId = partnerId;
    if (uid == 0) await _loadUid();
    final typeId = (a.payload['typeId'] as int?) ?? visitTypeId;
    if (typeId == null) {
      throw OdooException('This activity type is not available in Odoo any more. Delete this entry and plan it again.');
    }
    final summary = (a.payload['summary'] ?? '').toString();
    final date = (a.payload['date'] ?? '').toString();
    int? id;
    if (a.payload['sent'] == true) {
      // An earlier try may have reached Odoo before the network dropped.
      final found = await _call(
        'mail.activity',
        'search',
        [
          [
            ['res_model', '=', 'res.partner'],
            ['res_id', '=', partnerId],
            ['user_id', '=', uid],
            ['activity_type_id', '=', typeId],
            ['summary', '=', summary],
            ['date_deadline', '=', date],
          ],
        ],
        kwargs: {
          'limit': 1,
          'context': {'active_test': false},
        },
      );
      if (found is List && found.isNotEmpty) id = found.first as int;
    }
    if (id == null) {
      a.payload['sent'] = true;
      await _saveQueue();
      final note = (a.payload['note'] ?? '').toString();
      final created = await _call(
        'res.partner',
        'activity_schedule',
        [
          [partnerId],
        ],
        kwargs: {
          'activity_type_id': typeId,
          'user_id': uid,
          'summary': summary,
          'date_deadline': date,
          if (note.isNotEmpty) 'note': note,
        },
      );
      id = created is List ? created.first as int : created as int;
    }
    refToId[a.ref] = id;
    for (final v in activities.where((v) => v.localRef == a.ref)) {
      v.id = id;
      v.localRef = null;
      v.partnerId = partnerId;
      v.resId = partnerId;
    }
    for (final other in queue.where((x) => x.payload['activityRef'] == a.ref)) {
      other.payload['activityId'] = id;
      other.partnerId ??= partnerId;
    }
    await _saveActivities();
    await _saveSettings();
  }

  int? _activityIdOf(PendingAction a) {
    var activityId = a.payload['activityId'] as int?;
    if (activityId == null) {
      final r = a.payload['activityRef'] as String?;
      activityId = r != null ? refToId[r] : null;
      if (activityId == null) throw _WaitForCreate();
      a.payload['activityId'] = activityId;
    }
    return activityId;
  }

  static bool _isGone(OdooException e) =>
      e.message.contains('does not exist') || e.message.contains('has been deleted') || e.message.contains('Missing');

  Future<void> _sendActivityDate(PendingAction a) async {
    final activityId = _activityIdOf(a);
    try {
      await _call('mail.activity', 'write', [
        [activityId],
        {'date_deadline': (a.payload['date'] ?? '').toString()},
      ]);
    } on OdooNetworkException {
      rethrow;
    } on OdooException catch (e) {
      if (!_isGone(e)) rethrow; // done or deleted in Odoo meanwhile: nothing to move
    }
  }

  Future<void> _sendActivityDone(PendingAction a) async {
    final activityId = _activityIdOf(a);
    final partnerId = a.partnerId ?? (a.partnerRef != null ? refToId[a.partnerRef] : null);
    if (a.payload['sent'] == true) {
      // Done already if the activity is archived (Odoo keeps done activities archived).
      final done = await _call(
        'mail.activity',
        'search_count',
        [
          [
            ['id', '=', activityId],
            ['active', '=', false],
          ],
        ],
        kwargs: {
          'context': {'active_test': false},
        },
      );
      if (done is int && done > 0) return;
    }
    final attachments = await _uploadPhotos(a, a.payload['gps'] == true ? 'Field visit photo' : 'Activity photo');
    final feedback = _doneFeedback(a);
    a.payload['sent'] = true;
    await _saveQueue();
    try {
      await _call(
        'mail.activity',
        'action_feedback',
        [
          [activityId],
        ],
        kwargs: {'feedback': feedback, 'attachment_ids': attachments},
      );
    } on OdooNetworkException {
      rethrow;
    } on OdooException catch (e) {
      // The office deleted the activity meanwhile: keep the work as a note.
      if (!_isGone(e) || partnerId == null) rethrow;
      final summary = (a.payload['summary'] ?? '').toString();
      await _postNote(
        partnerId,
        '${(a.payload['typeName'] ?? 'Activity').toString()} done${summary.isNotEmpty ? ': $summary' : ''}. $feedback',
        attachmentIds: attachments,
      );
    }
  }

  String _doneFeedback(PendingAction a) {
    final p = a.payload;
    final parts = <String>[];
    if (p['gps'] == true) {
      final lat = (p['lat'] as num?)?.toDouble();
      final lng = (p['lng'] as num?)?.toDouble();
      final distance = (p['distance'] as num?)?.toDouble();
      parts.add('Done on site by ${_by(a)} on ${formatDateTime(a.createdAt)}.');
      if (lat == null || lng == null) {
        parts.add('No GPS location.');
      } else {
        parts.add(
          distance != null
              ? '${formatMeters(distance)} from the customer\'s saved location.'
              : 'Customer has no saved location.',
        );
        parts.add(
          'Lat ${lat.toStringAsFixed(6)}, Long ${lng.toStringAsFixed(6)} (GPS ±${(p['accuracy'] as num? ?? 0).round()} m).',
        );
      }
      final reason = (p['farReason'] ?? '').toString();
      if (reason.isNotEmpty) parts.add('Far from the customer: $reason.');
    } else {
      parts.add('Done by ${_by(a)} on ${formatDateTime(a.createdAt)} (VeeVee Field Locator).');
    }
    final result = (p['result'] ?? '').toString();
    if (result.isNotEmpty) parts.add('Result: $result.');
    final remark = (p['remark'] ?? '').toString();
    if (remark.isNotEmpty) parts.add('Note: $remark');
    return parts.join(' ');
  }

  // ======================================================================
  // Profile tab: who I am, my work this month, history, phone check
  // ======================================================================

  Future<void> setLargeText(bool value) async {
    largeText = value;
    await _saveSettings();
    notifyListeners();
  }

  /// Name, photo and company of the logged-in Odoo user.
  Future<void> loadProfile() async {
    if (!loggedIn || needsLogin) return;
    try {
      if (uid == 0) await _loadUid();
      if (uid == 0) return;
      final rows = await _call(
        'res.users',
        'read',
        [
          [uid],
        ],
        kwargs: {
          'fields': ['name', 'partner_id', 'company_id', 'image_128'],
        },
      );
      final r = Map<String, dynamic>.from((rows as List).first as Map);
      final p = r['partner_id'];
      if (p is List && p.isNotEmpty) myPartnerId = p[0] as int;
      final c = r['company_id'];
      companyName = c is List && c.length > 1 ? c[1].toString() : '';
      userImage = _pictureOrEmpty(r['image_128']);
      final name = r['name'] is String ? r['name'] as String : '';
      if (name.isNotEmpty) {
        odooUserName = name;
        if (!AppConfig.sharedLogin) userName = name;
      }
      await _saveSettings();
      notifyListeners();
    } on OdooNetworkException {
      // Offline: keep what we have.
    } on OdooException {
      // Not allowed: keep what we have.
    }
  }

  /// Odoo gives users without a photo a generated SVG avatar; the app shows
  /// its own initial instead.
  static String _pictureOrEmpty(Object? b64) {
    if (b64 is! String || b64.isEmpty) return '';
    try {
      final head = utf8.decode(
        base64Decode(b64.substring(0, b64.length.clamp(0, 64))).take(20).toList(),
        allowMalformed: true,
      );
      if (head.contains('<svg') || head.contains('<?xml')) return '';
    } catch (_) {
      return '';
    }
    return b64;
  }

  /// Sets the Odoo user's photo (Profile → camera button). Needs internet.
  Future<void> setProfilePhoto(String path) async {
    final bytes = await File(path).readAsBytes();
    await _call('res.users', 'write', [
      [uid],
      {'image_1920': base64Encode(bytes)},
    ]);
    await loadProfile();
  }

  static String _odooDateTime(DateTime local) {
    final u = local.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year}-${two(u.month)}-${two(u.day)} ${two(u.hour)}:${two(u.minute)}:${two(u.second)}';
  }

  Future<int> _count(String model, List<dynamic> domain) async {
    final n = await _call(model, 'search_count', [domain]);
    return n is int ? n : 0;
  }

  Future<WorkStats> _statsBetween(DateTime from, DateTime to) async {
    final a = _odooDateTime(from);
    final b = _odooDateTime(to);
    final pid = myPartnerId ?? 0;
    final customers = await _count('res.partner', [
      ...AppConfig.customerDomain,
      ['create_uid', '=', uid],
      ['create_date', '>=', a],
      ['create_date', '<', b],
    ]);
    final locations = await _count('mail.message', [
      ['model', '=', 'res.partner'],
      ['author_id', '=', pid],
      ['body', 'ilike', 'Location set on site with VeeVee Field Locator'],
      ['date', '>=', a],
      ['date', '<', b],
    ]);
    final activitiesDone = await _count('mail.message', [
      ['author_id', '=', pid],
      ['mail_activity_type_id', '!=', false],
      ['date', '>=', a],
      ['date', '<', b],
    ]);
    final visits = visitTypeId == null
        ? 0
        : await _count('mail.message', [
            ['author_id', '=', pid],
            ['mail_activity_type_id', '=', visitTypeId],
            ['date', '>=', a],
            ['date', '<', b],
          ]);
    return WorkStats(customers: customers, locations: locations, activities: activitiesDone, visits: visits);
  }

  /// This month and last month, counted in Odoo (so reinstalling loses nothing).
  Future<(WorkStats, WorkStats)> loadWorkStats() async {
    if (myPartnerId == null) await loadProfile();
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month);
    final nextMonth = DateTime(now.year, now.month + 1);
    final lastMonth = DateTime(now.year, now.month - 1);
    final current = await _statsBetween(thisMonth, nextMonth);
    final previous = await _statsBetween(lastMonth, thisMonth);
    return (current, previous);
  }

  /// All contacts this user ever created.
  Future<int> loadMyCustomersCount() => _count('res.partner', [
    ...AppConfig.customerDomain,
    ['create_uid', '=', uid],
  ]);

  /// My latest notes and done activities in Odoo, newest first.
  Future<List<HistoryItem>> loadHistory({int limit = 30}) async {
    if (myPartnerId == null) await loadProfile();
    final rows = await _call(
      'mail.message',
      'search_read',
      [
        [
          ['author_id', '=', myPartnerId ?? 0],
          ['model', '!=', false],
          [
            'message_type',
            'in',
            ['comment', 'notification'],
          ],
        ],
      ],
      kwargs: {
        'fields': ['date', 'body', 'record_name', 'model', 'mail_activity_type_id'],
        'order': 'date desc, id desc',
        'limit': limit,
      },
    );
    final out = <HistoryItem>[];
    for (final m in (rows as List).cast<Map>()) {
      final text = OdooActivity.htmlToText(m['body']);
      final type = m['mail_activity_type_id'];
      final record = m['record_name'] is String ? m['record_name'] as String : '';
      final at = DateTime.tryParse('${(m['date'] ?? '').toString().replaceFirst(' ', 'T')}Z')?.toLocal();
      if (at == null) continue;
      String title;
      var kind = 'note';
      if (type is List && type.length > 1) {
        title = '${type[1]} done';
        kind = 'activity';
      } else if (text.startsWith('Location set')) {
        title = 'Location set';
        kind = 'location';
      } else if (text.startsWith('Customer created')) {
        title = 'Customer added';
        kind = 'customer';
      } else if (text.startsWith('Photos added') || text.startsWith('Profile picture')) {
        title = 'Photos added';
        kind = 'photo';
      } else if (text.isEmpty) {
        continue; // field-change tracking, nothing to show
      } else {
        title = 'Note';
      }
      final result = RegExp(r'Result: ([^.]+)\.').firstMatch(text)?.group(1);
      out.add(
        HistoryItem(at: at, title: title, detail: [record, ?result].where((s) => s.isNotEmpty).join(' · '), kind: kind),
      );
    }
    return out;
  }

  /// True when Odoo answers with this login.
  Future<bool> checkServer() async {
    try {
      await _call('res.users', 'search_count', [
        [
          ['id', '=', uid],
        ],
      ]);
      return true;
    } on OdooNetworkException {
      return false;
    } on OdooException {
      return false;
    }
  }

  /// "Report a problem": a note with the text (and screenshot) on your own
  /// contact in Odoo, plus a To-Do for the administrator so it is seen.
  Future<void> reportProblem(String text, {String? screenshotPath}) async {
    if (myPartnerId == null) await loadProfile();
    final pid = myPartnerId;
    if (pid == null) throw OdooException('Could not find your contact in Odoo. Check the internet and try again.');
    final attachments = <int>[];
    if (screenshotPath != null) {
      attachments.add(await _uploadPhoto(screenshotPath, 'Problem screenshot ${formatDate(DateTime.now())}.jpg'));
    }
    final body =
        'Problem reported from VeeVee Field Locator ${AppConfig.appVersion} by $userName '
        'on ${formatDateTime(DateTime.now())}: ${text.trim()}';
    await _postNote(pid, body, attachmentIds: attachments);
    // Tell the administrator (user 2 is the first admin in every Odoo).
    final todo = activityTypes.where((t) => t.icon == 'fa-check' || t.name == 'To-Do').firstOrNull;
    try {
      await _call(
        'res.partner',
        'activity_schedule',
        [
          [pid],
        ],
        kwargs: {
          'activity_type_id': ?todo?.id,
          'user_id': 2,
          'summary': 'Problem reported in the app by $userName',
          'note': text.trim(),
        },
      );
    } on OdooException {
      // The note is posted; the reminder for the admin is a bonus.
    }
  }

  // ======================================================================
  // App updates (needs the VeeVee Field Locator Odoo module)
  // ======================================================================

  Future<UpdateInfo?> checkForUpdate() async {
    if (!hasAddon || !loggedIn) return null;
    try {
      final r = await _call('veevee.field.locator', 'get_app_info', []);
      if (r is! Map) return null;
      final info = UpdateInfo(
        latestVersion: (r['latest_version'] ?? '').toString(),
        apkUrl: (r['apk_url'] ?? '').toString(),
        notes: (r['release_notes'] ?? '').toString(),
      );
      update = info;
      final typeId = r['field_visit_type_id'];
      final newType = typeId is int ? typeId : null;
      if (newType != visitTypeId) {
        visitTypeId = newType;
        await _saveSettings();
      }
      notifyListeners();
      return info;
    } catch (_) {
      return null;
    }
  }

  void dismissUpdate() {
    updateDismissed = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _client?.close();
    super.dispose();
  }
}
