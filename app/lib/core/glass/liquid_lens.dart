// 液态透镜已删除（2026-10-18）：2094 行液态物理引擎因测试失败且无维护价值被移除。
// 此文件保留空实现以保证编译通过，实际渲染为普通子组件，无液态效果。
// 基础玻璃拟态（GlassTile/GlassButton）不受影响。

import 'package:flutter/widgets.dart';

/// 液态透镜控制器（空实现）
class LiquidLensController extends ChangeNotifier {
  LiquidLensController({
    required this.itemCount,
    required this.onSelect,
  });

  final int itemCount;
  final ValueChanged<int> onSelect;

  double get centerX => 0;
  dynamic get shape => _FakeShape();

  void dispose() {}
}

class _FakeShape {
  double get centerX => 0;
  double get height => 0;
  Size get size => Size.zero;
}

/// 液态透镜度量（空实现）
class LiquidLensMetrics {
  const LiquidLensMetrics({
    required this.capsuleHeight,
  });

  final double capsuleHeight;

  static LiquidLensMetrics forCapsule(double h) => LiquidLensMetrics(capsuleHeight: h);
}

/// 液态透镜（空实现：直接渲染 child，无液态效果）
class LiquidLens extends StatelessWidget {
  const LiquidLens({
    super.key,
    required this.controller,
    required this.metrics,
    required this.builder,
  });

  final LiquidLensController controller;
  final LiquidLensMetrics metrics;
  final Widget Function(BuildContext context, int index) builder;

  @override
  Widget build(BuildContext context) {
    // 直接渲染第一个子项，无液态变形
    return builder(context, 0);
  }
}
