// GlassCheck 标准档：玻璃圆环、勾按路径描画、点击切换完成状态。
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/widgets/glass_check.dart';

void main() {
  testWidgets('未勾选时的标准玻璃圆环在浅色底上仍清晰可见', (tester) async {
    tester.view.physicalSize = const Size(120, 120);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final GlobalKey key = GlobalKey();

    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: const ColoredBox(
          color: Color(0xFFF5F6FA),
          child: Center(
            child: GlassCheck(value: false, onChanged: _ignore),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    late List<int> pixels;
    await tester.runAsync(() async {
      final RenderRepaintBoundary boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 1);
      final ByteData? data =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      pixels = data!.buffer.asUint8List().toList();
    });
    int darkest = 255;
    for (int i = 0; i < pixels.length; i += 4) {
      if (pixels[i + 3] < 128) continue;
      final int luma =
          (pixels[i] * 299 + pixels[i + 1] * 587 + pixels[i + 2] * 114) ~/ 1000;
      if (luma < darkest) darkest = luma;
    }
    expect(darkest, lessThan(170), reason: '圆环描边在浅色背景上不可见');
  });

  test('勾按进度描出来：半程长度等于完整长度的一半', () {
    final double fullLength = checkMarkPath(28).computeMetrics().first.length;
    final double halfLength =
        checkMarkPathAt(28, 0.5).computeMetrics().first.length;

    expect(halfLength, closeTo(fullLength / 2, fullLength * 0.02));
    expect(checkMarkPathAt(28, 0).computeMetrics().isEmpty, isTrue);
    expect(
      checkMarkPathAt(28, 1).computeMetrics().first.length,
      closeTo(fullLength, 0.01),
    );
  });

  testWidgets('点击只切换一次，外部状态更新同步显示', (tester) async {
    final List<bool> calls = <bool>[];
    bool value = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) => GlassCheck(
              value: value,
              onChanged: (bool next) {
                calls.add(next);
                setState(() => value = next);
              },
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byType(GlassCheck));
    await tester.pumpAndSettle();

    expect(calls, <bool>[true]);
    expect(tester.widget<GlassCheck>(find.byType(GlassCheck)).value, isTrue);
  });

  testWidgets('置灰时点击不改变值', (tester) async {
    int calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: GlassCheck(
            value: false,
            enabled: false,
            onChanged: (_) => calls++,
          ),
        ),
      ),
    ));
    await tester.tap(find.byType(GlassCheck));
    await tester.pumpAndSettle();

    expect(calls, 0);
  });
}

void _ignore(bool _) {}
