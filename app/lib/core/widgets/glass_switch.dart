import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../haptics.dart';

/// 玻璃开关：圆钮 + 主色轨道 + Q弹回弹。
class GlassSwitch extends StatelessWidget {
  const GlassSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.width = 56,
    this.height = 30,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? activeColor;
  final double width;
  final double height;

  /// 置灰并不可交互。用于设备或功能不可用的场景。
  final bool enabled;

  void _toggle() {
    if (!enabled) return;
    Haptics.select();
    onChanged(!value);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accent = activeColor ?? Theme.of(context).colorScheme.primary;
    final double thumbSize = height - 6;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? _toggle : null,
      child: AnimatedContainer(
        duration: AppTokens.durMed,
        curve: Curves.easeOutCubic,
        width: width,
        height: height,
        padding: const EdgeInsets.all(AppTokens.padChipV),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height / 2),
          color: !enabled
              ? AppTokens.glassBorder(isDark).withValues(alpha: 0.25)
              : value
                  ? accent
                  : AppTokens.glassBorder(isDark).withValues(alpha: 0.6),
          border: Border.all(
            color: !enabled
                ? AppTokens.glassBorder(isDark).withValues(alpha: 0.5)
                : value
                    ? accent.withValues(alpha: 0.55)
                    : AppTokens.glassBorder(isDark),
          ),
        ),
        child: AnimatedAlign(
          duration: AppTokens.durMed,
          curve: Curves.easeOutBack,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: thumbSize,
            height: thumbSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  enabled ? Colors.white : Colors.white.withValues(alpha: 0.55),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 4,
                  offset: const Offset(0, 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
