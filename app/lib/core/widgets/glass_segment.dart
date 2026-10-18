import 'dart:async';

import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../haptics.dart';
import '../motion.dart';

/// 胶囊分段选择器：按下预览目标段、拖动跟手、松手提交。
class GlassSegment extends StatefulWidget {
  const GlassSegment({
    super.key,
    required this.count,
    required this.selectedIndex,
    required this.onSelected,
    required this.itemBuilder,
    this.height = 44,
  });

  final int count;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget Function(int index, bool selected) itemBuilder;
  final double height;

  @override
  State<GlassSegment> createState() => _GlassSegmentState();
}

class _GlassSegmentState extends State<GlassSegment> {
  late int _committed;
  late double _page;
  double _grabOffset = 0;
  bool _pressed = false;
  bool _dragging = false;

  double _clampPage(double page) => page.clamp(0.0, widget.count - 1.0);

  @override
  void initState() {
    super.initState();
    _committed = widget.selectedIndex;
    _page = _committed.toDouble();
  }

  @override
  void didUpdateWidget(GlassSegment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex && !_dragging) {
      _committed = widget.selectedIndex;
      _page = _committed.toDouble();
    }
  }

  void _press(double dx, double itemW) {
    setState(() {
      _pressed = true;
      _dragging = false;
      _page = _clampPage(dx / itemW - 0.5);
    });
  }

  void _dragStart(double dx, double itemW) {
    setState(() {
      _pressed = true;
      _dragging = true;
      _grabOffset = dx / itemW - 0.5 - _page;
    });
  }

  void _dragUpdate(double dx, double itemW) {
    setState(() => _page = _clampPage(dx / itemW - 0.5 - _grabOffset));
  }

  void _release() {
    final int target = _page.round().clamp(0, widget.count - 1);
    setState(() {
      _committed = target;
      _page = target.toDouble();
      _pressed = false;
      _dragging = false;
    });
    if (target != widget.selectedIndex) {
      Haptics.select();
      widget.onSelected(target);
    }
  }

  void _onTapCancel() {
    setState(() => _pressed = false);
    scheduleMicrotask(() {
      if (!mounted || _dragging) return;
      setState(() => _page = _committed.toDouble());
    });
  }

  void _cancel() {
    if (!_dragging) return;
    setState(() {
      _pressed = false;
      _dragging = false;
      _page = _committed.toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color activeColor = Theme.of(context).colorScheme.primary;
    final int selectedIndex = _page.round().clamp(0, widget.count - 1);
    const double inset = AppTokens.padChipV;

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double itemW = constraints.maxWidth / widget.count;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _press(d.localPosition.dx, itemW),
            onTapUp: (_) => _release(),
            onTapCancel: _onTapCancel,
            onHorizontalDragStart: (d) => _dragStart(d.localPosition.dx, itemW),
            onHorizontalDragUpdate: (d) =>
                _dragUpdate(d.localPosition.dx, itemW),
            onHorizontalDragEnd: (_) => _release(),
            onHorizontalDragCancel: _cancel,
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(widget.height / 2),
                        color: AppTokens.glassTint(isDark, true).first,
                        border:
                            Border.all(color: AppTokens.glassBorder(isDark)),
                      ),
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: _dragging ? Duration.zero : AppTokens.durFast,
                  curve: Curves.easeOutCubic,
                  left: _page * itemW + inset,
                  top: inset,
                  bottom: inset,
                  width: itemW - inset * 2,
                  child: QScale(
                    pressed: _pressed,
                    scale: AppTokens.pillGrow,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                            (widget.height - inset * 2) / 2),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: AppTokens.accentGradient(activeColor).colors,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: activeColor.withValues(alpha: 0.32),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Row(
                  children: List<Widget>.generate(
                    widget.count,
                    (int i) => Expanded(
                      child: Center(
                        child: widget.itemBuilder(i, i == selectedIndex),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
