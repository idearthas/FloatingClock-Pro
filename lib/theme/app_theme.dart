import 'package:flutter/material.dart';

/// FloatingClock 设计系统（冷淡风 / 极简版）
///
/// 视觉基调：低饱和的冷调中性灰 + 一抹克制的钢蓝点缀，
/// 大留白、近乎无阴影、去掉所有鲜艳与渐变，整体安静、克制、冷淡。
class AppColors {
  AppColors._();

  // 品牌色（去饱和的钢蓝，仅作极少量点缀）
  static const Color brand = Color(0xFF5B7C99);
  static const Color brandDeep = Color(0xFF486480);
  static const Color brandSoft = Color(0xFFEDF1F5);
  static const Color brandSoftStrong = Color(0xFFDCE3EB);
  static const Color accent = Color(0xFF7C8AA0);

  // 中性冷调底色
  static const Color background = Color(0xFFF6F7F9);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFFBFCFD);
  static const Color border = Color(0xFFE9ECF0);
  static const Color borderStrong = Color(0xFFDCE0E6);

  // 文字（冷深灰，非纯黑）
  static const Color textPrimary = Color(0xFF2B313B);
  static const Color textSecondary = Color(0xFF5E6675);
  static const Color textTertiary = Color(0xFF9AA1AD);

  // 状态色（全部去饱和，避免跳色）
  static const Color success = Color(0xFF5E8C75);
  static const Color successSoft = Color(0xFFEAF1ED);
  static const Color warning = Color(0xFFB08A4E);
  static const Color warningSoft = Color(0xFFF6F0E6);
  static const Color danger = Color(0xFFB26A6E);
  static const Color dangerSoft = Color(0xFFF5ECEC);

  // 浅色 Hero（主卡 / 画中画）：极浅冷白 → 白
  static const Color heroTop = Color(0xFFF1F4F7);
  static const Color heroBottom = Color(0xFFFFFFFF);
  static const Color onLight = Color(0xFF2B313B);
  static const Color onLightMuted = Color(0xFF6B7280);
  // 小数位高亮（与钢蓝一致，克制不跳）
  static const Color heroFraction = Color(0xFF5B7C99);
}

class AppGradients {
  AppGradients._();

  // 按钮点缀用的钢蓝渐变（去饱和、低对比）
  static const LinearGradient brand = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF6B8AA6), Color(0xFF5B7C99)],
  );

  // 主卡 / 画中画：极浅冷白到白（几乎不可察觉的渐变）
  static const LinearGradient hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.heroTop, AppColors.heroBottom],
  );

  static const LinearGradient danger = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFFC28A8D), Color(0xFFB26A6E)],
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

  // 几乎不可见的卡片阴影，靠边框区隔
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x06000000),
      blurRadius: 12,
      offset: Offset(0, 2),
    ),
  ];

  // 主卡阴影同样极弱
  static const List<BoxShadow> hero = [
    BoxShadow(
      color: Color(0x08000000),
      blurRadius: 14,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> floating = [
    BoxShadow(
      color: Color(0x07000000),
      blurRadius: 12,
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
