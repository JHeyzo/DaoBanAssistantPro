import 'package:flutter/material.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';

/// 日历日期格的圆角方章（v0.11.3 视觉重做）。
///
/// 扁平布局：无卡片容器，日期数字收进章内，班次简称在数字下方。
/// 原版浅色系：
/// - 白班：底 `#EEF4FF`，描边 `#9EC1F5`，字 `#2F7CF6`
/// - 值班（纯值班）：红底 `#E5484D` 系
/// - 休：灰章
/// - 今天：蓝色实心章
///
/// 白+值：蓝章右上斜切 + 实心红三角悬浮。两片是**分开的模型**，斜边处留缝，
/// 顶边/右边与蓝章外沿共线，三角外直角倒圆角，整体仍是一整根圆角矩形。
/// 休息日值班 = 灰底 + 红角（红角是值班语义标记的视觉表达，与底色无关）。
class DayChipPainter extends CustomPainter {
  DayChipPainter({
    required this.day,
    required this.label,
    required this.baseColor,
    required this.borderColor,
    required this.textColor,
    required this.hasDutyCorner,
    required this.isToday,
    this.cornerColor = AppTokens.chipDutyBase,
  });

  /// 日期数字。
  final int day;

  /// 班次简称（如 白/值/休），空串则不画。
  final String label;

  /// 章底色。
  final Color baseColor;

  /// 章描边色。
  final Color borderColor;

  /// 字色。
  final Color textColor;

  /// 是否画右上红折角（值班语义标记）。
  final bool hasDutyCorner;

  /// 是否为今天（蓝色实心章）。
  final bool isToday;

  /// 折角颜色。
  final Color cornerColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // 圆角半径：章宽的约 1/4（38~44dp 章上约 9~10）。
    final radius = w * 0.24;
    const strokeWidth = 2.0;

    // 蓝章右上斜切的几何（viewBox 60x72 换算到实际尺寸）：
    // 蓝章路径 x 2→58，斜切从 (30,2) 到 (58,30)。
    // 红三角路径 M33,1 H49 Q59,1 59,11 V27 Z。
    final scaleX = w / 60;
    final scaleY = h / 72;

    // --- 蓝章主体（含斜切） ---
    final chipPath = Path();
    if (hasDutyCorner) {
      // 右上斜切：从顶边 (30,2) 到右边 (58,30)。
      final cutStartX = 30 * scaleX;
      final cutStartY = 2 * scaleY;
      final cutEndX = 58 * scaleX;
      final cutEndY = 30 * scaleY;
      chipPath.moveTo(2 * scaleX + radius, 2 * scaleY);
      chipPath.lineTo(cutStartX, cutStartY);
      chipPath.lineTo(cutEndX, cutEndY);
      // 切角后直接沿右边下来（切口处不需要圆角）
      // 右边 → 右下圆角 → 底边 → 左下圆角 → 左边 → 左上圆角 → 回到起点
      chipPath.lineTo(58 * scaleX, 70 * scaleY - radius);
      chipPath.quadraticBezierTo(58 * scaleX, 70 * scaleY,
          58 * scaleX - radius, 70 * scaleY);
      chipPath.lineTo(2 * scaleX + radius, 70 * scaleY);
      chipPath.quadraticBezierTo(
          2 * scaleX, 70 * scaleY, 2 * scaleX, 70 * scaleY - radius);
      chipPath.lineTo(2 * scaleX, 2 * scaleY + radius);
      chipPath.quadraticBezierTo(
          2 * scaleX, 2 * scaleY, 2 * scaleX + radius, 2 * scaleY);
      chipPath.close();
    } else {
      // 完整圆角矩形。
      chipPath.addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(
            2 * scaleX, 2 * scaleY, 56 * scaleX, 68 * scaleY),
        Radius.circular(radius),
      ));
    }

    // 底
    canvas.drawPath(
      chipPath,
      Paint()..color = isToday ? AppTokens.chipWorkText : baseColor,
    );
    // 描边（今天不描边）
    if (!isToday) {
      canvas.drawPath(
        chipPath,
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth,
      );
    }

    // --- 红折角（实心三角，与蓝章分开，斜边处留缝） ---
    if (hasDutyCorner) {
      // 路径 M33,1 H49 Q59,1 59,11 V27 Z，顶边/右边与蓝章外沿共线。
      final cornerPath = Path();
      cornerPath.moveTo(33 * scaleX, 1 * scaleY);
      cornerPath.lineTo(49 * scaleX, 1 * scaleY);
      // 外直角倒圆角（半径与章同）
      cornerPath.quadraticBezierTo(
          59 * scaleX, 1 * scaleY, 59 * scaleX, 11 * scaleY);
      cornerPath.lineTo(59 * scaleX, 27 * scaleY);
      cornerPath.close();
      canvas.drawPath(
        cornerPath,
        Paint()..color = cornerColor,
      );
    }

    // --- 文字：日期数字 + 班次简称 ---
    final dayTextColor = isToday ? Colors.white : textColor;
    final labelTextColor =
        isToday ? Colors.white.withValues(alpha: 0.85) : textColor.withValues(alpha: 0.75);

    // 日期数字（居中偏上）
    final dayPainter = TextPainter(
      text: TextSpan(
        text: '$day',
        style: TextStyle(
          color: dayTextColor,
          fontSize: h * 0.32,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    dayPainter.paint(
      canvas,
      Offset(
        (w - dayPainter.width) / 2,
        h * 0.18,
      ),
    );

    // 班次简称（数字下方）
    if (label.isNotEmpty) {
      final labelPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: labelTextColor,
            fontSize: h * 0.20,
              height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelPainter.paint(
        canvas,
        Offset(
          (w - labelPainter.width) / 2,
          h * 0.18 + dayPainter.height + h * 0.04,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant DayChipPainter oldDelegate) {
    return oldDelegate.day != day ||
        oldDelegate.label != label ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.textColor != textColor ||
        oldDelegate.hasDutyCorner != hasDutyCorner ||
        oldDelegate.isToday != isToday ||
        oldDelegate.cornerColor != cornerColor;
  }
}
