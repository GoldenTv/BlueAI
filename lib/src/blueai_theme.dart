import 'package:flutter/material.dart';

/// Neutral chat surfaces with blue reserved for primary actions and selections.
class BlueAIPalette {
  BlueAIPalette._();

  // ── สีแบรนด์ ──
  static const Color accent = Color(0xFF2563EB);
  static const Color accentDeep = Color(0xFF1D4ED8);
  static const Color accentBright = Color(0xFF38BDF8);
  static const Color accentSoft = Color(0xFF7EB3FF);

  /// ไล่เฉดหลักของแบรนด์ (ใช้กับโลโก้ ปุ่มส่ง ฟองข้อความ)
  static const List<Color> brandGradient = <Color>[accentDeep, accentBright];

  // ── Light theme ──
  static const Color lightBackground = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCodeBackground = Color(0xFFF4F4F5);
  static const Color lightBorder = Color(0xFFE4E4E7);
  static const Color lightText = Color(0xFF18181B);
  static const Color lightTextSecondary = Color(0xFF71717A);
  static const Color lightTint = Color(0xFFF4F4F5);

  // ── Dark theme ──
  static const Color darkBackground = Color(0xFF18181B);
  static const Color darkSurface = Color(0xFF202023);
  static const Color darkSurfaceHigh = Color(0xFF27272A);
  static const Color darkBorder = Color(0xFF3F3F46);
  static const Color darkText = Color(0xFFF4F4F5);
  static const Color darkTextSecondary = Color(0xFFA1A1AA);
  static const Color darkTint = Color(0xFF27272A);

  // ── Helper ตามโหมด ──
  static Color text(bool isDark) => isDark ? darkText : lightText;
  static Color textSecondary(bool isDark) =>
      isDark ? darkTextSecondary : lightTextSecondary;
  static Color surface(bool isDark) => isDark ? darkSurface : lightSurface;
  static Color surfaceHigh(bool isDark) => isDark ? darkSurfaceHigh : lightTint;
  static Color border(bool isDark) => isDark ? darkBorder : lightBorder;
  static Color background(bool isDark) =>
      isDark ? darkBackground : lightBackground;
  static Color tint(bool isDark) => isDark ? darkTint : lightTint;
  static Color codeBackground(bool isDark) =>
      isDark ? const Color(0xFF202023) : lightCodeBackground;

  /// สีข้อความบนพื้น tint — ใช้กับชิป/ปุ่มรอง
  static Color accentText(bool isDark) => isDark ? accentSoft : accentDeep;
}
