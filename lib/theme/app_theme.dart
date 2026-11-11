import 'package:flutter/material.dart';

/// FloatingClock 设计系统（轻量 / 简约版）
///
/// 视觉基调：大面积留白 + 纯白卡片 + 单一克制品牌蓝作为点缀，
/// 去除深色渐变与重阴影，整体更清爽、更轻。
class AppColors {
  AppColors._();

  // 品牌色（克制，仅作点缀）
  static const Color brand = Color(0xFF4A6CF7);
  static const Color brandDeep = Color(0xFF3A57D7);
  static const Color brandSoft = Color(0xFFEEF2FF);
  static const Color brandSoftStrong = Color(0xFFE0E7FF);
  static const Color accent = Color(0xFF7C5CFF);

  // 中性底色
  static const Color background = Color(0xFFF6F7F9);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFFAFBFC);
  static const Color border = Color(0xFFECEDF1);
  static const Color borderStrong = Color(0xFFE1E3EA);

  // 文字
  static const Color textPrimary = Color(0xFF1C2230);
  static const Color textSecondary = Color(0xFF5B6478);
  static const Color textTertiary = Color(0xFF9AA1B1);

  // 状态色（柔和）
  static const Color success = Color(0xFF16A34A);
  static const Color successSoft = Color(0xFFE9F7EE);
  static const Color warning = Color(0xFFE08A00);
  static const Color warningSoft = Color(0xFFFFF4E2);
  static const Color danger = Color(0xFFE5484D);
  static const Color dangerSoft = Color(0xFFFDECEC);

  // 浅色 Hero（主卡 / 画中画）：极浅蓝 → 白
  static const Color heroTop = Color(0xFFEDF2FF);
  static const Color heroBottom = Color(0xFFFFFFFF);
  static const Color onLight = Color(0xFF1C2230);
  static const Color onLightMuted = Color(0xFF6B7384);
  // 小数位高亮（与品牌蓝一致，保持克制）
  static const Color heroFraction = Color(0xFF4A6CF7);
}

class AppGradients {
  AppGradients._();

  // 按钮等少量点缀用的品牌渐变
  static const LinearGradient brand = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF5B82FF), Color(0xFF6C5CE7)],
  );

  // 浅色主卡 / 画中画：极浅蓝到白
  static const LinearGradient hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.heroTop, AppColors.heroBottom],
  );

  static const LinearGradient danger = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFFFF7B7B), Color(0xFFE5484D)],
  );
}

class AppRadius {
  AppRadius._();

  static const double small = 10.0;
  static const double medium = 14.0;
  static const double card = 18.0;
  static const double large = 24.0;
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

  // 极淡卡片阴影，几乎不可见，靠边框区隔
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x08000000),
      blurRadius: 14,
      offset: Offset(0, 3),
    ),
  ];

  // 主卡阴影同样收敛
  static const List<BoxShadow> hero = [
    BoxShadow(
      color: Color(0x0C1B3A66),
      blurRadius: 16,
      offset: Offset(0, 5),
    ),
  ];

  static const List<BoxShadow> floating = [
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 14,
      offset: Offset(0, -2),
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
