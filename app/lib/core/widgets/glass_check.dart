import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../haptics.dart';
import '../motion.dart';

/// 勾的路径（在 [size]×[size] 的方框里）。
Path checkMarkPath(double size) => Path()
  ..moveTo(size * 0.26, size * 0.52)
  ..lineTo(size * 0.44, size * 0.69)
  ..lineTo(size * 0.75, size * 0.33);

/// 勾「描到一半」的那一段。[progress] 0 = 空路径，1 = 整笔。
Path checkMarkPathAt(double size, double progress) {
  final Path full = checkMarkPath(size);
  final double p = progress.clamp(0.0, 1.0);
  if (p <= 0) return Path();
  final ui.PathMetric metric = full.computeMetrics().first;
  return metric.extractPath(0, metric.length * p);
}

/// 待办勾选：空心环 → 主色实心 + 白勾。
class GlassCheck extends StatefulWidget {
  const GlassCheck({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.size = 28,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? activeColor;
  final double size;
  final bool enabled;

  @override
  State<GlassCheck> createState() => _GlassCheckState();
}

class _GlassCheckState extends State<GlassCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController.unbounded(
    vsync: this,
    value: widget.value ? 1.0 : 0.0,
  );
  bool _pressed = false;

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(GlassCheck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      springTo(_progress, widget.value ? 1.0 : 0.0);
    }
  }

  void _setPressed(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  void _toggle() {
    if (!widget.enabled) return;
    Haptics.select();
    widget.onChanged(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accent =
        widget.activeColor ?? Theme.of(context).colorScheme.primary;

    return AnimatedBuilder(
      animation: _progress,
      builder: (BuildContext context, Widget? _) {
        final double progress = _progress.value.clamp(0.0, 1.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: widget.enabled ? (_) => _setPressed(true) : null,
          onTapUp: widget.enabled
              ? (_) {
                  _setPressed(false);
                  _toggle();
                }
              : null,
          onTapCancel: () => _setPressed(false),
          child: QScale(
            pressed: _pressed,
            scale: AppTokens.pillGrow,
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: CustomPaint(
                painter: _CheckPainter(
                  progress: progress,
                  ringColor: Color.lerp(
                    AppTokens.navBorder(isDark).withValues(alpha: 0.45),
                    accent.withValues(alpha: 0.55),
                    progress,
                  )!,
                  fillColor: Color.lerp(
                    AppTokens.glassTint(isDark, true).first,
                    accent,
                    progress,
                  )!,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 画圆：淡底色 + 环 + 按进度描出的勾。
class _CheckPainter extends CustomPainter {
  const _CheckPainter({
    required this.progress,
    required this.ringColor,
    required this.fillColor,
  });

  final double progress;
  final Color ringColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final double side = math.min(size.width, size.height);
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = side / 2 - 0.75;

    canvas.drawCircle(center, radius, Paint()..color = fillColor);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = ringColor,
    );

    if (progress > 0.01) {
      canvas.drawPath(
        checkMarkPathAt(side, progress),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = side * 0.115
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color =
              Colors.white.withValues(alpha: (progress * 1.6).clamp(0.0, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.progress != progress ||
      old.ringColor != ringColor ||
      old.fillColor != fillColor;
}
