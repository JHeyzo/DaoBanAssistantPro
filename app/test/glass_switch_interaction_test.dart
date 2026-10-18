// GlassSwitch 标准档交互回归。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/core/widgets/glass_switch.dart';

void main() {
  testWidgets('启用时点按只翻转一次并更新开关状态', (tester) async {
    final List<bool> calls = <bool>[];
    bool value = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) =>
                GlassSwitch(
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
    await tester.tap(find.byType(GlassSwitch));
    await tester.pumpAndSettle();

    expect(calls, <bool>[true]);
    expect(tester.widget<GlassSwitch>(find.byType(GlassSwitch)).value, isTrue);
  });

  testWidgets('置灰状态不可交互', (tester) async {
    int calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: GlassSwitch(
            value: false,
            enabled: false,
            onChanged: (_) => calls++,
          ),
        ),
      ),
    ));
    await tester.tap(find.byType(GlassSwitch));
    await tester.pumpAndSettle();

    expect(calls, 0);
  });
}
