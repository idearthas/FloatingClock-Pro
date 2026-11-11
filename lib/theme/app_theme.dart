import 'package:flutter/material.dart';

/// FloatingClock 设计系统
///
/// 统一收敛配色、圆角、间距与阴影，避免各页面各写一套硬编码样式。
/// 视觉基调：冷灰蓝底 + 纯白卡片 + 科技蓝主色 + 深色渐变时钟卡。
class AppColors {
  AppColors._();

  static const Color brand = Color(0xFF3D6BFF);
  static const Color brandDeep = Color(0xFF2B4FD8);
  static const Color brandSoft = Color(0xFFEEF3FF);
  static const Color brandSoftStrong = Color(0xFFE1EAFF);
  static const Color accent = Color(0xFF7C5CFF);

  static const Color background = Color(0xFFF5F7FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFF9FBFF);
  static const Color border = Color(0xFFE7ECF5);
  static const Color borderStrong = Color(0xFFD8E0EF);

  static const Color textPrimary = Color(0xFF1A2138);
  static const Color textSecondary = Color(0xFF66728C);
  static const Color textTertiary = Color(0xFF9BA6BA);

  static const Color success = Color(0xFF12B76A);
  static const Color successSoft = Color(0xFFE7F8EF);
  static const Color warning = Color(0xFFF79009);
  static const Color warningSoft = Color(0xFFFFF4E4);
  static const Color danger = Color(0xFFF04438);
  static const Color dangerSoft = Color(0xFFFFECEA);

  static const Color heroTop = Color(0xFF24325E);
  static const Color heroBottom = Color(0xFF0A0F20);
  static const Color onDark = Color(0xFFFFFFFF);
  static const Color onDarkMuted = Color(0xB3FFFFFF);
  static const Color heroFraction = Color(0xFFFFC46B);
}

class AppGradients {
  AppGradients._();

  static const LinearGradient brand = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF4C7DFF), Color(0xFF6C5CE7)],
  );

  static const LinearGradient brandVertical = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4C7DFF), Color(0xFF5C63E8)],
  );

  static const LinearGradient hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.heroTop, Color(0xFF141C38), AppColors.heroBottom],
  );

  static const LinearGradient danger = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFFFF6B6B), Color(0xFFE8443A)],
  );
}

class AppRadius {
  AppRadius._();

  static const double small = 10.0;
  static const double medium = 14.0;
  static const double card = 20.0;
  static const double large = 26.0;
  static const double pill = 999.0;
}

class AppSpacing {
  AppSpacing._();

  static const double xs = 4.0;
  static const double s = 8.0;
  static const double m = 12.0;
  static const double l = 16.0;
  static const double xl = 20.0;
  static const double xxl = 28.0;
}

class AppShadows {
  AppShadows._();

  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x0A1A2B4D),
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
  ];

  static const List<BoxShadow> hero = [
    BoxShadow(
      color: Color(0x33223A7A),
      blurRadius: 26,
      offset: Offset(0, 12),
    ),
  ];

  static const List<BoxShadow> floating = [
    BoxShadow(
      color: Color(0x1A1A2B4D),
      blurRadius: 22,
      offset: Offset(0, -4),
    ),
  ];
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.brand,
        brightness: Brightness.light,
      ).copyWith(
        primary: AppColors.brand,
        surface: AppColors.surface,
      ),
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary, size: 22),
      ),
      dividerColor: AppColors.border,
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.brand,
        selectionColor: AppColors.brandSoftStrong,
        selectionHandleColor: AppColors.brand,
      ),
    );
  }
}
