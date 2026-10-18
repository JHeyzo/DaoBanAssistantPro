// app/tool/gif/render_gifs_test.dart
//
// 逐帧出图 → `scripts/make_gif.py` 合成动图。
//
// **为什么不放在 `tool/visual/`**：那里的 300 条是**回归护栏**（把界面出图留档、供
// 人工审阅与前后对比），这里是**产出素材**（更新简介、商店页要用的动图）。两者的产物
// 与跑法都不同，混在一起会让护栏的条数随「这次要不要出动图」浮动。
//
// 只拍**动**的东西 —— 静止就能看明白的走 `tool/visual/` 那条线（长期记忆
// `prefer-gifs-for-feature-demos`）。
//
// 跑法：
//   flutter test tool/gif/render_gifs_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/widgets/glass_check.dart';
import 'package:shiftassistantpro/core/widgets/glass_switch.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/profile/app_dialogs.dart';

import '../visual/visual_harness.dart';

const List<({String suffix, Brightness brightness})> _modes =
    <({String suffix, Brightness brightness})>[
  (suffix: 'light', brightness: Brightness.light),
  (suffix: 'dark', brightness: Brightness.dark),
];

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    await ensureVisualFonts();
  });
  setUp(setUpVisualPrefs);

  Future<AppDatabase> freshDb() async {
    final db = await makeVisualDatabase();
    addTearDown(db.close);
    return db;
  }

  // 开关按一下：拍按钮状态切换。
  for (final ({String suffix, Brightness brightness}) v in _modes) {
    testWidgets('开关按一下 · ${v.suffix}', (tester) async {
      final db = await freshDb();
      late TestGesture gesture;
      bool released = false;
      await renderFrames(
        tester,
        prefix: 'switch_${v.suffix}_',
        home: const _SwitchBoard(),
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        brightness: v.brightness,
        count: 30,
        step: const Duration(milliseconds: 60),
        onFrame: (tester, i) async {
          if (i == 0) {
            gesture = await tester.startGesture(
                tester.getCenter(find.byKey(const ValueKey<bool>(true))));
            addTearDown(() {
              if (!released) return gesture.up();
              return Future<void>.value();
            });
          } else if (i == 14) {
            await gesture.up();
            released = true;
          }
          await tester.pump(const Duration(milliseconds: 16));
        },
      );
    });
  }
  // ④ 待办打勾：拍勾画出与取消的动画。
  testWidgets('待办打勾 · standard', (WidgetTester tester) async {
    await renderFrames(
      tester,
      prefix: 'check_std_',
      home: const _CheckGifHost(),
      overrides: const <Override>[],
      count: 70,
      step: const Duration(milliseconds: 16),
      onFrame: (WidgetTester t, int i) async {
        if (i == 6 || i == 44) await t.tap(find.byType(GlassCheck).first);
      },
    );
  });

  // ⑥ 弹窗的**凝聚**入场 / 消散退场。
  //
  //    起点小一圈、糊一层，过程中一起收敛到清晰 —— 玻璃该有的样子是「从模糊里
  //    凝出来」，而不是一张不透明卡片被点亮。驱动用的是路由自己的动画，所以退场
  //    不用另写一份。
  //
  //    取「开始使用」那个弹窗：内容够长（九条带圆点的短句），凝聚过程在白底上
  //    也看得出来；而且它是纯文案、不用库。
  for (final v in _modes) {
    testWidgets('弹窗 · 凝聚入场 · ${v.suffix}', (WidgetTester tester) async {
      final GlobalKey host = GlobalKey();
      await renderFrames(
        tester,
        prefix: 'dialog_condense_${v.suffix}_',
        home: Scaffold(key: host, body: const SizedBox.expand()),
        overrides: const <Override>[],
        brightness: v.brightness,
        count: 22,
        step: const Duration(milliseconds: 16),
        onFrame: (WidgetTester t, int i) async {
          if (i == 0) showGettingStartedDialog(host.currentContext!);
        },
      );
    });
  }
}

/// 开关特写用的板子：一行「开」一行「关」，单看开关本身。
class _SwitchBoard extends StatelessWidget {
  const _SwitchBoard();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            for (final bool v in <bool>[true, false])
              Padding(
                padding: const EdgeInsets.all(AppTokens.space2xl),
                child: GlassSwitch(
                  key: ValueKey<bool>(v),
                  value: v,
                  onChanged: (bool _) {},
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 三枚待办的勾（拍「勾出来」那一刻；最后一枚按住看液态档那枚滴凸出去）。
class _CheckGifHost extends StatelessWidget {
  const _CheckGifHost();

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              GlassCheck(value: false, onChanged: _ignore),
              SizedBox(height: AppTokens.space2xl),
              GlassCheck(value: true, onChanged: _ignore),
              SizedBox(height: AppTokens.space2xl),
              GlassCheck(value: false, onChanged: _ignore),
            ],
          ),
        ),
      );

  static void _ignore(bool _) {}
}
