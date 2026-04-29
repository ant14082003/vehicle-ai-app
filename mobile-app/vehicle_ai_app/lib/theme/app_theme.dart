import 'package:flutter/material.dart';

/// Shared design tokens for the premium dark automotive theme.
/// Import this in every screen — never hardcode colours elsewhere.
class AppTheme {
  // ── Core palette ────────────────────────────────────────────────────────────
  static const Color bg = Color(0xFF080B14); // near-black base
  static const Color surface = Color(0xFF0E1420); // card backgrounds
  static const Color surface2 = Color(0xFF141C2E); // slightly lighter card
  static const Color border = Color(0xFF1E2A40); // subtle borders
  static const Color borderHigh = Color(0xFF2A3A58); // highlighted borders

  // ── Accent ──────────────────────────────────────────────────────────────────
  static const Color accent = Color(0xFFE8B84B); // gold — premium feel
  static const Color accentLight = Color(0xFFF5D07A); // lighter gold for text
  static const Color accentDark = Color(0xFFA07820); // dark gold for shadows

  // ── Status colours ──────────────────────────────────────────────────────────
  static const Color success = Color(0xFF00C48C);
  static const Color warning = Color(0xFFFFB300);
  static const Color danger = Color(0xFFFF4757);
  static const Color info = Color(0xFF4FC3F7);

  // ── Text ────────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF0F4FF);
  static const Color textSecondary = Color(0xFF8895B0);
  static const Color textMuted = Color(0xFF4A5568);

  // ── Gradients ───────────────────────────────────────────────────────────────
  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFFE8B84B), Color(0xFFF5D07A), Color(0xFFE8B84B)],
    stops: [0.0, 0.5, 1.0],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF141C2E), Color(0xFF0E1420)],
  );

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.transparent, Color(0xCC080B14), Color(0xFF080B14)],
    stops: [0.3, 0.75, 1.0],
  );

  // ── Typography ───────────────────────────────────────────────────────────────
  static TextStyle get displayLarge => const TextStyle(
    color: textPrimary,
    fontSize: 28,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    height: 1.1,
  );

  static TextStyle get displayMedium => const TextStyle(
    color: textPrimary,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  static TextStyle get titleLarge => const TextStyle(
    color: textPrimary,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );

  static TextStyle get titleMedium => const TextStyle(
    color: textPrimary,
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  static TextStyle get bodyMedium => const TextStyle(
    color: textSecondary,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static TextStyle get labelSmall => const TextStyle(
    color: textMuted,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.8,
  );

  static TextStyle get accentLabel => const TextStyle(
    color: accent,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.5,
  );

  static TextStyle get plateNumber => const TextStyle(
    color: accentLight,
    fontSize: 13,
    fontWeight: FontWeight.w800,
    letterSpacing: 2.0,
  );

  // ── Decorations ──────────────────────────────────────────────────────────────
  static BoxDecoration get cardDecoration => BoxDecoration(
    gradient: cardGradient,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: border),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.4),
        blurRadius: 16,
        offset: const Offset(0, 6),
      ),
    ],
  );

  static BoxDecoration get accentCardDecoration => BoxDecoration(
    gradient: cardGradient,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: accent.withOpacity(0.4), width: 1.5),
    boxShadow: [
      BoxShadow(
        color: accent.withOpacity(0.1),
        blurRadius: 20,
        offset: const Offset(0, 4),
      ),
    ],
  );

  // ── Button styles ─────────────────────────────────────────────────────────
  static ButtonStyle get primaryButton => ElevatedButton.styleFrom(
    backgroundColor: accent,
    foregroundColor: bg,
    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    elevation: 0,
    textStyle: const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
    ),
  );

  static ButtonStyle get outlineButton => OutlinedButton.styleFrom(
    foregroundColor: accent,
    side: const BorderSide(color: accent, width: 1.5),
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
  );

  static ButtonStyle get ghostButton => TextButton.styleFrom(
    foregroundColor: accent,
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
    textStyle: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
    ),
  );

  // ── ThemeData ─────────────────────────────────────────────────────────────
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.dark(
      primary: accent,
      secondary: accent,
      surface: surface,
      background: bg,
      onPrimary: bg,
      onSecondary: bg,
      onSurface: textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: bg,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
      iconTheme: IconThemeData(color: textPrimary),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: border),
      ),
    ),
    dividerTheme: const DividerThemeData(color: border, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: surface2,
      contentTextStyle: const TextStyle(color: textPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: accent, width: 1.5),
      ),
      labelStyle: const TextStyle(color: textSecondary, fontSize: 14),
      hintStyle: const TextStyle(color: textMuted, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
  );
}

/// Reusable gold accent line divider
class AccentDivider extends StatelessWidget {
  final double width;
  const AccentDivider({super.key, this.width = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 2,
      decoration: BoxDecoration(
        gradient: AppTheme.accentGradient,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}

/// Glowing container used for section headers
class SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    required this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppTheme.accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
          ),
          child: Icon(icon, color: AppTheme.accent, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: AppTheme.titleMedium)),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Status badge pill
class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 11),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
