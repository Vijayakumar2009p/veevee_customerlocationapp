/// App-wide settings. Change these before building the APK.
class AppConfig {
  AppConfig._();

  static const String appName = 'VeeVee Field Locator';

  /// Must match `version:` in pubspec.yaml (the part before `+`).
  static const String appVersion = '1.2.0';

  /// Pre-filled on login page 1. Customer builds set it with
  /// `--dart-define=DEFAULT_SERVER=http://...`.
  static const String defaultServerUrl = String.fromEnvironment(
    'DEFAULT_SERVER',
    defaultValue: 'https://www.veeveeinfotech.com',
  );

  /// Pre-filled database name. Used when the server hides its database list.
  /// Replace with your real database name before building.
  static const String defaultDatabase = String.fromEnvironment('DEFAULT_DATABASE');

  /// A location is "good" when GPS accuracy is this many metres or better.
  static const double goodAccuracyMeters = 20;

  /// Network timeout for each Odoo request.
  static const Duration requestTimeout = Duration(seconds: 30);

  /// Retry pending entries this often while the app is open.
  static const Duration autoSyncInterval = Duration(minutes: 1);

  static const String userAgent =
      'VeeVeeFieldLocator/$appVersion (com.veeveeinfotech.fieldlocator; info@veeveeinfotech.com)';

  /// Contacts shown in the app: companies and individual contacts.
  /// Left out: invoice/delivery child addresses and your own staff (Odoo users).
  static const List<dynamic> customerDomain = [
    '&',
    '!',
    ['user_ids.share', '=', false],
    '|',
    ['is_company', '=', true],
    ['type', '=', 'contact'],
  ];

  /// Customer (trial) builds: show only contacts created by the logged-in
  /// Odoo user, so the list starts empty. Switched on at build time with
  /// `--dart-define=OWN_CONTACTS_ONLY=true`; VeeVee's own build shows all.
  static const bool ownContactsOnly = bool.fromEnvironment('OWN_CONTACTS_ONLY');

  /// Customer TRIAL build: allow plain http:// servers in an optimised build
  /// (`--dart-define=ALLOW_HTTP=true`). Test builds always allow http.
  static const bool allowHttp = bool.fromEnvironment('ALLOW_HTTP');

  /// Customer builds where all staff share one Odoo login: ask each
  /// person's name for the notes (`--dart-define=SHARED_LOGIN=true`).
  /// VeeVee's own build: each staff member has their own login, and the
  /// Odoo user's name is used.
  static const bool sharedLogin = bool.fromEnvironment('SHARED_LOGIN');

  /// Field visit "Mark done": warn when farther than this from the
  /// customer's saved location (warning only, never blocks).
  static const double visitFarMeters = 300;

  static const String supportPhone = '+91 99657 82269';
  static const String supportEmail = 'info@veeveeinfotech.com';
}
