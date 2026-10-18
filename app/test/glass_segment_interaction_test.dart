// GlassSegment 标准档的交互回归：点击选择、拖动吸附、取消恢复。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/widgets/glass_segment.dart';

void main() {
  Future<void> pumpSegment(
    WidgetTester tester, {
    int selected = 0,
    required ValueChanged<int> onSelected,
    Widget Function(Widget child)? wrap,
  }) async {
    Widget child = SizedBox(
      width: 300,
      child: GlassSegment(
        count: 3,
        selectedIndex: selected,
        onSelected: onSelected,
        itemBuilder: (int index, bool isSelected) => Text(
          '$index',
          key: ValueKey<String>('segment-$index'),
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
    if (wrap != null) child = wrap(child);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('点按另一段只提交一次对应索引', (tester) async {
    final List<int> selected = <int>[];
    await pumpSegment(tester, onSelected: selected.add);

    await tester.tap(find.byKey(const ValueKey<String>('segment-1')));
    await tester.pumpAndSettle();

    expect(selected, <int>[1]);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('segment-1')))
          .style!
          .fontWeight,
      FontWeight.w700,
    );
  });

  testWidgets('横向拖动跟手并在松手时吸附提交', (tester) async {
    final List<int> selected = <int>[];
    await pumpSegment(tester, onSelected: selected.add);

    final Rect box = tester.getRect(find.byType(GlassSegment));
    final TestGesture gesture = await tester.startGesture(
      Offset(box.left + 50, box.center.dy),
    );
    for (int i = 0; i < 24; i++) {
      await gesture.moveBy(const Offset(8.75, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selected, <int>[2]);
  });

  testWidgets('取消点按不会误提交，且高亮回到已选段', (tester) async {
    final List<int> selected = <int>[];
    await pumpSegment(
      tester,
      onSelected: selected.add,
      wrap: (Widget child) => GestureDetector(
        onVerticalDragStart: (_) {},
        child: child,
      ),
    );

    final Rect box = tester.getRect(find.byType(GlassSegment));
    final TestGesture gesture = await tester.startGesture(
      Offset(box.left + 250, box.center.dy),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(0, -40));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selected, isEmpty);
    final AnimatedPositioned highlight =
        tester.widget<AnimatedPositioned>(find.byType(AnimatedPositioned));
    expect(highlight.left, closeTo(AppTokens.padChipV, 0.01));
  });
}
