import 'package:flutter/material.dart';

/// VeeVee Infotech brand colours (from the VeeVee design system).
class VV {
  VV._();

  static const surface = Color(0xFFFFFFFF);
  static const surfaceRaised = Color(0xFFF4F8FB);
  static const line = Color(0xFFD6E2EC);
  static const ink = Color(0xFF0F2A3F);
  static const inkMuted = Color(0xFF4F6A7D);
  static const blue = Color(0xFF0261A8);
  static const blueSoft = Color(0xFFE3EFF8);
  static const sky = Color(0xFF349AC4);
  static const skyText = Color(0xFF1F7EA6);
  static const skySoft = Color(0xFFE2F2F9);
  static const gold = Color(0xFFFFB411);
  static const goldText = Color(0xFF8A5F05);
  static const goldSoft = Color(0xFFFFF3D6);
  static const success = Color(0xFF1A7A4A);
  static const successSoft = Color(0xFFE3F5EA);
  static const danger = Color(0xFFB3261E);
  static const dangerSoft = Color(0xFFFBE7E5);

  static const radiusSm = 4.0;
  static const radiusMd = 8.0;
  static const radiusLg = 16.0;
}

/// WhatsApp-like neutrals used by the tabbed screens.
class WaColors {
  WaColors._();
  static const grey = Color(0xFF54656F);
  static const background = Color(0xFFF0F2F5);
  static const divider = Color(0xFFE9EDEF);

  /// Avatar fills (brand colours) with the text colour that reads on each.
  static const avatars = [
    (Color(0xFF0261A8), Colors.white),
    (Color(0xFF349AC4), Color(0xFF0F2A3F)),
    (Color(0xFFFFB411), Color(0xFF0F2A3F)),
    (Color(0xFF1A7A4A), Colors.white),
    (Color(0xFF5B4FB5), Colors.white),
    (Color(0xFFB3261E), Colors.white),
  ];

  static (Color, Color) avatarFor(String name) {
    var h = 0;
    for (final c in name.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return avatars[h % avatars.length];
  }

  static String initials(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    final a = words.first.characters.first;
    final b = words.length > 1
        ? words[1].characters.first
        : (words.first.length > 1 ? words.first.characters.elementAt(1) : '');
    return (a + b).toUpperCase();
  }
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: VV.blue,
    primary: VV.blue,
    onPrimary: Colors.white,
    secondary: VV.sky,
    tertiary: VV.gold,
    error: VV.danger,
    surface: VV.surface,
    onSurface: VV.ink,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: VV.surface);
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(VV.radiusSm),
    borderSide: BorderSide(color: c, width: w),
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: VV.surface,
      foregroundColor: VV.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(color: VV.ink, fontSize: 18, fontWeight: FontWeight.w600),
      shape: Border(bottom: BorderSide(color: VV.line)),
    ),
    textTheme: base.textTheme.apply(bodyColor: VV.ink, displayColor: VV.ink),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VV.surface,
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: border(VV.line),
      enabledBorder: border(VV.line),
      focusedBorder: border(VV.blue, 2),
      errorBorder: border(VV.danger),
      focusedErrorBorder: border(VV.danger, 2),
      hintStyle: const TextStyle(color: VV.inkMuted),
      errorStyle: const TextStyle(color: VV.danger, fontSize: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: VV.blue,
        foregroundColor: Colors.white,
        disabledBackgroundColor: VV.line,
        disabledForegroundColor: VV.inkMuted,
        minimumSize: const Size(64, 48),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VV.radiusMd)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: VV.surfaceRaised,
        foregroundColor: VV.ink,
        minimumSize: const Size(64, 48),
        side: const BorderSide(color: VV.line),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VV.radiusMd)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: VV.blue,
        minimumSize: const Size(44, 44),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    dividerTheme: const DividerThemeData(color: VV.line, thickness: 1, space: 1),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
