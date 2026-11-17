/// A change made on the phone that still has to reach Odoo.
///
/// Kinds:
///  * [PendingAction.create]      - a new customer (payload = Odoo values, photos)
///  * [PendingAction.location]    - a GPS location (+ optional address, photo, remark)
///  * [PendingAction.photos]      - photos added to an existing customer
///  * [PendingAction.visitCreate]  - an activity planned on the phone (any type)
///  * [PendingAction.visitDone]    - an activity marked done (Field Visit: with GPS)
///  * [PendingAction.activityDate] - an activity moved to another date
class PendingAction {
  PendingAction({
    required this.ref,
    required this.kind,
    required this.createdAt,
    required this.customerName,
    required this.payload,
    this.partnerId,
    this.partnerRef,
    this.attempts = 0,
    this.lastError = '',
    this.blocked = false,
  });

  static const String create = 'create';
  static const String location = 'location';
  static const String photos = 'photos';
  static const String visitCreate = 'visitCreate';
  static const String visitDone = 'visitDone';
  static const String activityDate = 'activityDate';

  /// Unique reference on this phone.
  final String ref;
  final String kind;
  final DateTime createdAt;
  final String customerName;

  /// Odoo id of the customer (null while the customer itself is pending).
  int? partnerId;

  /// For a location on a customer created offline: the `ref` of its create entry.
  String? partnerRef;

  final Map<String, dynamic> payload;
  int attempts;
  String lastError;

  /// Odoo refused this entry (not a network problem). Needs attention.
  bool blocked;

  String get label {
    if (kind == create) {
      return payload['withLocation'] == true ? 'New customer + location' : 'New customer';
    }
    if (kind == photos) return 'Photos';
    if (kind == visitCreate) return 'Activity planned';
    if (kind == visitDone) return 'Activity done';
    if (kind == activityDate) return 'Activity moved';
    return 'Location';
  }

  Map<String, dynamic> toJson() => {
    'ref': ref,
    'kind': kind,
    'createdAt': createdAt.toIso8601String(),
    'customerName': customerName,
    'partnerId': partnerId,
    'partnerRef': partnerRef,
    'payload': payload,
    'attempts': attempts,
    'lastError': lastError,
    'blocked': blocked,
  };

  factory PendingAction.fromJson(Map<String, dynamic> j) => PendingAction(
    ref: j['ref'] as String,
    kind: j['kind'] as String,
    createdAt: DateTime.tryParse((j['createdAt'] ?? '') as String) ?? DateTime.now(),
    customerName: (j['customerName'] ?? '') as String,
    partnerId: j['partnerId'] as int?,
    partnerRef: j['partnerRef'] as String?,
    payload: Map<String, dynamic>.from((j['payload'] ?? const {}) as Map),
    attempts: (j['attempts'] ?? 0) as int,
    lastError: (j['lastError'] ?? '') as String,
    blocked: j['blocked'] == true,
  );
}
