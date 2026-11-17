/// What the app offers as the main action for an activity.
enum ActivityKind { fieldVisit, call, email, meeting, upload, todo }

/// An open Odoo activity (mail.activity) assigned to the logged-in user:
/// To-Do, Email, Call, Meeting, Document, Field Visit or any custom type.
class OdooActivity {
  OdooActivity({
    this.id,
    this.localRef,
    this.partnerId,
    this.partnerRef,
    required this.customerName,
    this.resModel = 'res.partner',
    this.resId,
    this.resName = '',
    this.typeId,
    this.typeName = '',
    this.icon = '',
    this.category = 'default',
    this.isFieldVisit = false,
    required this.summary,
    this.note = '',
    required this.deadline,
    this.assignedBy = '',
    this.phone = '',
    this.email = '',
  });

  /// Odoo activity id; null while planned on the phone and not yet sent.
  int? id;

  /// Reference of the offline "plan activity" entry.
  String? localRef;

  /// The customer (res.partner) this activity is about: the record itself for
  /// contacts, else the record's partner_id (quotation, lead, invoice...).
  int? partnerId;
  String? partnerRef;
  String customerName;

  /// The record the activity is on in Odoo.
  String resModel;
  int? resId;
  String resName;

  int? typeId;
  String typeName;

  /// Odoo font-awesome icon name of the type (fa-phone, fa-envelope...).
  String icon;

  /// Odoo type category: default, phonecall, meeting, upload_file.
  String category;
  bool isFieldVisit;

  String summary;
  String note;

  /// Due date (date only).
  DateTime deadline;

  /// Name of the user who scheduled it.
  String assignedBy;
  String phone;
  String email;

  bool get isLocal => id == null;

  /// Negative: overdue; 0: today; positive: days ahead.
  int get daysLeft {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(deadline.year, deadline.month, deadline.day).difference(today).inDays;
  }

  String get title {
    if (summary.trim().isNotEmpty) return summary.trim();
    if (typeName.isNotEmpty) return typeName;
    return 'Activity';
  }

  ActivityKind get kind {
    if (isFieldVisit || icon == 'fa-map-marker') return ActivityKind.fieldVisit;
    if (category == 'phonecall' || icon == 'fa-phone') return ActivityKind.call;
    if (category == 'upload_file' || icon == 'fa-upload') return ActivityKind.upload;
    if (category == 'meeting' || icon == 'fa-users' || icon == 'fa-calendar') return ActivityKind.meeting;
    if (icon == 'fa-envelope' || icon == 'fa-envelope-o') return ActivityKind.email;
    return ActivityKind.todo;
  }

  /// "Quotation S00045 · Anand Knits" for records that are not contacts.
  String get relatedLine {
    if (resModel == 'res.partner' || resName.isEmpty) return customerName;
    final what = modelLabel(resModel);
    final head = what.isEmpty ? resName : '$what $resName';
    return customerName.isNotEmpty && customerName != resName ? '$head · $customerName' : head;
  }

  static String modelLabel(String model) => switch (model) {
    'res.partner' => '',
    'sale.order' => 'Quotation',
    'purchase.order' => 'Purchase',
    'crm.lead' => 'Lead',
    'account.move' => 'Invoice',
    'project.task' => 'Task',
    'project.project' => 'Project',
    'helpdesk.ticket' => 'Ticket',
    'stock.picking' => 'Transfer',
    'hr.employee' => 'Employee',
    _ => '',
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'localRef': localRef,
    'partnerId': partnerId,
    'partnerRef': partnerRef,
    'customerName': customerName,
    'resModel': resModel,
    'resId': resId,
    'resName': resName,
    'typeId': typeId,
    'typeName': typeName,
    'icon': icon,
    'category': category,
    'isFieldVisit': isFieldVisit,
    'summary': summary,
    'note': note,
    'deadline': deadline.toIso8601String(),
    'assignedBy': assignedBy,
    'phone': phone,
    'email': email,
  };

  factory OdooActivity.fromJson(Map<String, dynamic> j) => OdooActivity(
    id: j['id'] as int?,
    localRef: j['localRef'] as String?,
    partnerId: j['partnerId'] as int?,
    partnerRef: j['partnerRef'] as String?,
    customerName: (j['customerName'] ?? '') as String,
    resModel: (j['resModel'] ?? 'res.partner') as String,
    resId: j['resId'] as int?,
    resName: (j['resName'] ?? '') as String,
    typeId: j['typeId'] as int?,
    typeName: (j['typeName'] ?? '') as String,
    icon: (j['icon'] ?? '') as String,
    category: (j['category'] ?? 'default') as String,
    isFieldVisit: (j['isFieldVisit'] ?? false) as bool,
    summary: (j['summary'] ?? '') as String,
    note: (j['note'] ?? '') as String,
    deadline: DateTime.tryParse((j['deadline'] ?? '') as String) ?? DateTime.now(),
    assignedBy: (j['assignedBy'] ?? '') as String,
    phone: (j['phone'] ?? '') as String,
    email: (j['email'] ?? '') as String,
  );

  /// From an Odoo mail.activity search_read row.
  factory OdooActivity.fromOdoo(Map<String, dynamic> r, {int? fieldVisitTypeId}) {
    String str(Object? v) => v is String ? v : '';
    (int?, String) m2o(Object? v) => v is List && v.length >= 2 ? (v[0] as int?, v[1].toString()) : (null, '');
    final (typeId, typeName) = m2o(r['activity_type_id']);
    final (_, by) = m2o(r['create_uid']);
    final model = str(r['res_model']);
    final resId = r['res_id'] is int ? r['res_id'] as int : null;
    final resName = str(r['res_name']);
    return OdooActivity(
      id: r['id'] as int,
      partnerId: model == 'res.partner' ? resId : null,
      customerName: model == 'res.partner' ? resName : '',
      resModel: model,
      resId: resId,
      resName: resName,
      typeId: typeId,
      typeName: typeName,
      icon: str(r['icon']),
      category: str(r['activity_category']).isEmpty ? 'default' : str(r['activity_category']),
      isFieldVisit: fieldVisitTypeId != null && typeId == fieldVisitTypeId,
      summary: str(r['summary']),
      note: htmlToText(r['note']),
      deadline: DateTime.tryParse(str(r['date_deadline'])) ?? DateTime.now(),
      assignedBy: by,
    );
  }

  /// Odoo stores activity notes as HTML; the app shows plain text.
  static String htmlToText(Object? html) {
    if (html is! String) return '';
    return html
        .replaceAll(RegExp(r'<br\s*/?>|</p>|</div>|</li>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\n{2,}'), '\n')
        .trim();
  }
}

/// An activity type that can be planned from the app.
class ActivityType {
  const ActivityType({required this.id, required this.name, this.icon = '', this.category = 'default'});
  final int id;
  final String name;
  final String icon;
  final String category;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'icon': icon, 'category': category};

  factory ActivityType.fromJson(Map<String, dynamic> j) => ActivityType(
    id: j['id'] as int,
    name: (j['name'] ?? '') as String,
    icon: (j['icon'] ?? '') as String,
    category: (j['category'] ?? 'default') as String,
  );
}
