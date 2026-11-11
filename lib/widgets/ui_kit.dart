import 'package:flutter/material.dart';
import 'package:floating_clock/theme/app_theme.dart';

/// 统一的可复用视觉组件。所有间距/圆角/配色均来自 AppTheme 设计系统。
class SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const SectionCard({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: child,
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Widget> actions;

  const SectionHeader({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.brandSoft,
            borderRadius: BorderRadius.circular(AppRadius.small),
          ),
          child: Icon(icon, size: 18, color: AppColors.brand),
        ),
        const SizedBox(width: AppSpacing.m),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        ...actions,
      ],
    );
  }
}

class CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final Color? color;
  final Color? background;
  final double size;

  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.background,
    this.size = 34,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: background ?? AppColors.brandSoft,
      borderRadius: BorderRadius.circular(AppRadius.small),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.small),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size * 0.52, color: color ?? AppColors.brand),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class Tag extends StatelessWidget {
  final String label;
  final Color color;
  final Color background;
  final IconData? icon;

  const Tag({
    super.key,
    required this.label,
    required this.color,
    required this.background,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  final bool running;
  const StatusPill({super.key, required this.running});

  @override
  Widget build(BuildContext context) {
    final dot = running ? const Color(0xFF4ADE80) : const Color(0xFF8D9AB5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: running ? const Color(0x1F4ADE80) : const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: running ? const Color(0x334ADE80) : const Color(0x22FFFFFF),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: dot,
              shape: BoxShape.circle,
              boxShadow: running
                  ? [
                      BoxShadow(
                        color: dot.withValues(alpha: 0.8),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            running ? '悬浮中' : '未启动',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class GradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool danger;
  final bool expand;

  const GradientButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.danger = false,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final button = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: danger ? AppGradients.danger : AppGradients.brand,
            borderRadius: BorderRadius.circular(AppRadius.medium),
            boxShadow: [
              BoxShadow(
                color: (danger ? AppColors.danger : AppColors.brand)
                    .withValues(alpha: 0.28),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(AppRadius.medium),
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: AppSpacing.s),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return expand ? Expanded(child: button) : button;
  }
}

class SoftButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool expand;

  const SoftButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final foreground = enabled ? AppColors.brand : AppColors.textTertiary;
    final button = Material(
      color: enabled ? AppColors.brandSoft : AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.medium),
            border: Border.all(
              color: enabled ? AppColors.brandSoftStrong : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: foreground, size: 20),
              const SizedBox(width: AppSpacing.s),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return expand ? Expanded(child: button) : button;
  }
}

class SegmentItem<T> {
  final T value;
  final String label;
  const SegmentItem({required this.value, required this.label});
}

class OptionSegment<T> extends StatelessWidget {
  final List<SegmentItem<T>> items;
  final T value;
  final ValueChanged<T> onChanged;

  const OptionSegment({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: items.map((item) {
          final selected = item.value == value;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(item.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: selected ? AppGradients.brand : null,
                  color: selected ? null : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: AppColors.brand.withValues(alpha: 0.22),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : AppColors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class ColorChoice {
  final String key;
  final String label;
  final Color color;
  const ColorChoice(this.key, this.label, this.color);
}

class ColorPickerRow extends StatelessWidget {
  final List<ColorChoice> options;
  final String selectedKey;
  final ValueChanged<String> onChanged;

  const ColorPickerRow({
    super.key,
    required this.options,
    required this.selectedKey,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: options.map((option) {
        final selected = option.key == selectedKey;
        return GestureDetector(
          onTap: () => onChanged(option.key),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: option.color,
                  border: Border.all(
                    color: selected ? option.color : Colors.transparent,
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: option.color.withValues(alpha: selected ? 0.4 : 0.18),
                      blurRadius: selected ? 10 : 5,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: selected
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
              const SizedBox(height: 6),
              Text(
                option.label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.textPrimary : AppColors.textTertiary,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class InfoBanner extends StatelessWidget {
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const InfoBanner({
    super.key,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: const Color(0xFFFFE0B2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: const Icon(Icons.bolt, size: 19, color: AppColors.warning),
          ),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: onAction,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.warning,
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                    child: Text(
                      actionLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
