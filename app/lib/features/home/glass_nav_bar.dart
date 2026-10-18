// app/lib/features/home/glass_nav_bar.dart
//
// 底部导航的悬浮玻璃胶囊（标准档）。

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import '../../core/glass/glass.dart';
import '../../core/layout.dart';
import '../../core/motion.dart';
import '../../core/widgets/app_icon.dart';

/// 悬浮玻璃胶囊导航：点击切整数 tab，拖拽跟手、松手停在手指位置。
class GlassNavBar extends StatefulWidget {
  const GlassNavBar({
    super.key,
    required this.controller,
    required this.items,
  });

  final PageController controller;
  final List<(IconData, String)> items;

  @override
  State<GlassNavBar> createState() => _GlassNavBarState();
}

class _GlassNavBarState extends State<GlassNavBar> {
  static const _outerPad = 24.0;
  static const _innerPad = AppTokens.gapIconText;
  static const _capsuleHeight = 64.0;
  static const _capsuleHeightShort = 52.0;
  static const _outerPadShort = 16.0;

  int _committedIndex = 0;
  double _page = 0;
  double _grabOffset = 0;
  bool _pressed = false;
  bool _dragging = false;
  bool _drivingPage = false;

  PageController get controller => widget.controller;
  List<(IconData, String)> get items => widget.items;

  @override
  void initState() {
    super.initState();
    _committedIndex = controller.initialPage;
    _page = _committedIndex.toDouble();
    controller.addListener(_syncFromController);
  }

  @override
  void dispose() {
    controller.removeListener(_syncFromController);
    super.dispose();
  }

  void _syncFromController() {
    if (_drivingPage || !controller.hasClients) return;
    final double? page = controller.page;
    if (page == null) return;
    final int index = page.round().clamp(0, items.length - 1);
    if (_committedIndex == index && (_page - page).abs() < 0.001) return;
    setState(() {
      _committedIndex = index;
      _page = page;
    });
  }

  double _clampPage(double page) => page.clamp(0.0, items.length - 1.0);

  void _press(double dx, double itemW) {
    setState(() {
      _pressed = true;
      _dragging = false;
      _page = _clampPage(dx / itemW - 0.5);
    });
  }

  void _dragStart(double dx, double itemW) {
    setState(() {
      _dragging = true;
      _pressed = true;
      _grabOffset = dx / itemW - 0.5 - _page;
    });
  }

  void _dragUpdate(double dx, double itemW) {
    setState(() => _page = _clampPage(dx / itemW - 0.5 - _grabOffset));
  }

  void _release() {
    final int target = _page.round().clamp(0, items.length - 1);
    setState(() {
      _committedIndex = target;
      _page = target.toDouble();
      _pressed = false;
      _dragging = false;
    });
    if (controller.hasClients && controller.page?.round() != target) {
      _drivingPage = true;
      controller
          .animateToPage(target,
              duration: AppTokens.durMed, curve: Curves.easeOutCubic)
          .whenComplete(() => _drivingPage = false);
    }
  }

  void _onTapCancel() {
    setState(() => _pressed = false);
    // Tap cancellation is delivered immediately before horizontal-drag start when
    // that recognizer wins. Defer rollback so the drag can retain its grab offset.
    scheduleMicrotask(() {
      if (!mounted || _dragging) return;
      setState(() => _page = _committedIndex.toDouble());
    });
  }

  void _cancel() {
    if (!_dragging) return;
    setState(() {
      _dragging = false;
      _pressed = false;
      _page = _committedIndex.toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isShort = AppLayout.of(context).isShort;
    final double capsuleH = isShort ? _capsuleHeightShort : _capsuleHeight;
    final double outerPad = isShort ? _outerPadShort : _outerPad;
    final Color activeColor = Theme.of(context).colorScheme.primary;
    final Color inactiveColor =
        AppTokens.navInactiveForeground(context, isDark: isDark);
    final Color fg = AppTokens.navForeground(isDark, activeColor);
    final int selectedIndex = _page.round().clamp(0, items.length - 1);

    return QScale(
      pressed: _pressed,
      scale: AppTokens.pillGrow,
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: outerPad),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: _page),
            duration: _dragging ? Duration.zero : AppTokens.durFast,
            curve: Curves.easeOutCubic,
            builder: (context, page, _) => TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: _pressed ? 1.0 : 0.0),
              duration: AppTokens.durMed,
              curve: Curves.easeOutBack,
              builder: (context, swell, __) => ClipRRect(
                borderRadius: BorderRadius.circular(capsuleH / 2),
                child: GlassBlur(
                  sigma: AppTokens.blurPanel,
                  child: Container(
                    height: capsuleH,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(capsuleH / 2),
                      border: Border.all(color: AppTokens.navBorder(isDark)),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: AppTokens.navFill(isDark),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(_innerPad),
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final double itemW = c.maxWidth / items.length;
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (d) => _press(d.localPosition.dx, itemW),
                            onTapUp: (_) => _release(),
                            onTapCancel: _onTapCancel,
                            onHorizontalDragStart: (d) =>
                                _dragStart(d.localPosition.dx, itemW),
                            onHorizontalDragUpdate: (d) =>
                                _dragUpdate(d.localPosition.dx, itemW),
                            onHorizontalDragEnd: (_) => _release(),
                            onHorizontalDragCancel: _cancel,
                            child: Stack(
                              children: [
                                AnimatedPositioned(
                                  key: const Key('nav-highlight'),
                                  duration: _dragging
                                      ? Duration.zero
                                      : AppTokens.durFast,
                                  curve: Curves.easeOutCubic,
                                  left: page * itemW,
                                  top: 0,
                                  bottom: 0,
                                  width: itemW,
                                  child: AnimatedScale(
                                    scale: _pressed ? 1.22 : 1.0,
                                    duration: AppTokens.durMed,
                                    curve: Curves.easeOutBack,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(
                                            AppTokens.radiusL),
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: AppTokens.accentGradient(
                                                  activeColor)
                                              .colors,
                                        ),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                              alpha: isDark ? 0.28 : 0.85),
                                        ),
                                        boxShadow: <BoxShadow>[
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.12),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                _iconsRow(
                                    isShort, fg, inactiveColor, selectedIndex),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconsRow(
    bool isShort,
    Color fg,
    Color inactiveColor,
    int selectedIndex,
  ) {
    return Row(
      children: List.generate(items.length, (i) {
        final bool selected = i == selectedIndex;
        return Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(
                items[i].$1,
                size: isShort ? AppTokens.iconMd : AppTokens.iconLg,
                color: selected ? fg : inactiveColor,
              ),
              const SizedBox(height: AppTokens.gapHair),
              Text(
                items[i].$2,
                style: AppTokens.tinyLabel.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? fg : inactiveColor,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
