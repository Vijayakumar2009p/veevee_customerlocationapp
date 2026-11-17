/// A contact (res.partner) as kept on the phone.
class Customer {
  Customer({
    required this.id,
    required this.name,
    this.localRef,
    this.isCompany = false,
    this.parentId,
    this.parentName = '',
    this.phone = '',
    this.email = '',
    this.vat = '',
    this.street = '',
    this.street2 = '',
    this.city = '',
    this.zip = '',
    this.stateName = '',
    this.countryName = '',
    this.latitude = 0,
    this.longitude = 0,
    this.locationDate = '',
    this.pending = false,
    this.createdAt = '',
    this.createdBy,
  });

  /// Odoo id. Negative while the customer exists only on the phone.
  int id;

  /// Reference of the offline "create" entry, for customers not yet in Odoo.
  String? localRef;

  String name;
  bool isCompany;
  int? parentId;
  String parentName;
  String phone;
  String email;
  String vat;
  String street;
  String street2;
  String city;
  String zip;
  String stateName;
  String countryName;
  double latitude;
  double longitude;
  String locationDate;

  /// True while a change for this customer waits to be synced.
  bool pending;

  /// When and by which Odoo user the contact was created (UTC 'YYYY-MM-DD HH:MM:SS').
  String createdAt;
  int? createdBy;

  DateTime? get createdLocal {
    final d = DateTime.tryParse(createdAt.contains('T') ? createdAt : '${createdAt.replaceFirst(' ', 'T')}Z');
    return d?.toLocal();
  }

  bool get isLocal => id < 0;
  bool get hasLocation => latitude != 0 || longitude != 0;

  String get addressLine => [
    street,
    street2,
    city,
    [stateName, zip].where((s) => s.isNotEmpty).join(' '),
  ].where((s) => s.trim().isNotEmpty).join(', ');

  /// Second line in the customer list.
  String get subtitle {
    final parts = <String>[];
    if (!isCompany && parentName.isNotEmpty) parts.add(parentName);
    if (city.isNotEmpty) parts.add(city);
    if (isCompany) parts.add(vat.isNotEmpty ? vat : 'No GSTIN');
    if (parts.isEmpty && phone.isNotEmpty) parts.add(phone);
    return parts.join(' · ');
  }

  String get _searchText =>
      [name, parentName, city, vat, phone.replaceAll(RegExp(r'\D'), ''), email].join(' ').toLowerCase();

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final digits = q.replaceAll(RegExp(r'[\s\-+]'), '');
    return q.split(RegExp(r'\s+')).every(_searchText.contains) ||
        (digits.length >= 4 && RegExp(r'^\d+$').hasMatch(digits) && _searchText.contains(digits));
  }

  static String _str(dynamic v) => (v == null || v == false) ? '' : v.toString();
  static double _num(dynamic v) => v is num ? v.toDouble() : 0;
  static String _m2oName(dynamic v) => (v is List && v.length > 1) ? v[1].toString() : '';
  static int? _m2oId(dynamic v) => (v is List && v.isNotEmpty && v[0] is int) ? v[0] as int : null;

  /// From an Odoo `search_read` row.
  factory Customer.fromOdoo(Map<String, dynamic> r, {String phoneField = 'phone'}) {
    var phone = _str(r[phoneField]);
    if (phone.isEmpty && phoneField != 'phone') phone = _str(r['phone']);
    return Customer(
      id: r['id'] as int,
      name: _str(r['name']).isNotEmpty ? _str(r['name']) : _str(r['display_name']),
      isCompany: r['is_company'] == true,
      parentId: _m2oId(r['parent_id']),
      parentName: _m2oName(r['parent_id']),
      phone: phone,
      email: _str(r['email']),
      vat: _str(r['vat']),
      street: _str(r['street']),
      street2: _str(r['street2']),
      city: _str(r['city']),
      zip: _str(r['zip']),
      stateName: _m2oName(r['state_id']).replaceAll(RegExp(r'\s*\([A-Z]{2}\)$'), ''),
      countryName: _m2oName(r['country_id']),
      latitude: _num(r['partner_latitude']),
      longitude: _num(r['partner_longitude']),
      locationDate: _str(r['date_localization']),
      createdAt: _str(r['create_date']),
      createdBy: _m2oId(r['create_uid']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'localRef': localRef,
    'name': name,
    'isCompany': isCompany,
    'parentId': parentId,
    'parentName': parentName,
    'phone': phone,
    'email': email,
    'vat': vat,
    'street': street,
    'street2': street2,
    'city': city,
    'zip': zip,
    'stateName': stateName,
    'countryName': countryName,
    'latitude': latitude,
    'longitude': longitude,
    'locationDate': locationDate,
    'pending': pending,
    'createdAt': createdAt,
    'createdBy': createdBy,
  };

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
    id: j['id'] as int,
    localRef: j['localRef'] as String?,
    name: (j['name'] ?? '') as String,
    isCompany: j['isCompany'] == true,
    parentId: j['parentId'] as int?,
    parentName: (j['parentName'] ?? '') as String,
    phone: (j['phone'] ?? '') as String,
    email: (j['email'] ?? '') as String,
    vat: (j['vat'] ?? '') as String,
    street: (j['street'] ?? '') as String,
    street2: (j['street2'] ?? '') as String,
    city: (j['city'] ?? '') as String,
    zip: (j['zip'] ?? '') as String,
    stateName: (j['stateName'] ?? '') as String,
    countryName: (j['countryName'] ?? '') as String,
    latitude: _num(j['latitude']),
    longitude: _num(j['longitude']),
    locationDate: (j['locationDate'] ?? '') as String,
    pending: j['pending'] == true,
    createdAt: (j['createdAt'] ?? '') as String,
    createdBy: j['createdBy'] as int?,
  );
}
