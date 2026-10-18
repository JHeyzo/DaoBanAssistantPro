// 普通玻璃与省电降级的结构性护栏。
//
// 标准玻璃必须使用「模糊 + 真实饱和度」复合滤镜；低端设备关闭 BackdropFilter，
// 以免为平色背景付出不必要的渲染开销。底栏标准档的提交时机与按压状态也由这里覆盖。

import 'dart:ui' show ImageFilter;

import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/app_info.dart';
import 'package:shiftassistantpro/core/design_tokens.dart';
import 'package:shiftassistantpro/core/glass/glass.dart';
import 'package:shiftassistantpro/core/motion.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/features/home/home_shell.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/plugin_channels.dart';

/// 装配一个 GlassPanel 并取回它那层 `BackdropFilter` 的 filter。
Future<ImageFilter?> _panelFilter(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: Center(
          child: GlassPanel(child: SizedBox(width: 40, height: 40)),
        ),
      ),
    ),
  );
  return tester.widget<BackdropFilter>(find.byType(BackdropFilter)).filter;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    await initializeDateFormatting('en');
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() {
    lowEndDevice = false;
    recomputeGlassTiers();
  });

  test('glassSaturation 就是 spec 写的 Rec.709 保亮度矩阵（s = 1.2）', () {
    const double s = 1.2;
    const double lr = 0.2126;
    const double lg = 0.7152;
    const double lb = 0.0722;
    const double invSat = 1 - s;
    expect(
      AppTokens.glassSaturation,
      const ColorFilter.matrix(<double>[
        invSat * lr + s,
        invSat * lg,
        invSat * lb,
        0,
        0,
        invSat * lr,
        invSat * lg + s,
        invSat * lb,
        0,
        0,
        invSat * lr,
        invSat * lg,
        invSat * lb + s,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]),
    );
  });

  testWidgets('标准档：GlassPanel 的 filter 恰好是「模糊 + 饱和度」的复合', (tester) async {
    final filter = await _panelFilter(tester);
    expect(
      filter,
      ImageFilter.compose(
        outer: ImageFilter.blur(
            sigmaX: AppTokens.blurPanel, sigmaY: AppTokens.blurPanel),
        inner: AppTokens.glassSaturation,
      ),
    );
  });

  testWidgets('标准档：GlassBlur 的 filter 也是「模糊 + 饱和度」的复合', (tester) async {
    const sigma = 8.0;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              ColoredBox(color: Color(0xFF7A8A9A)),
              GlassBlur(
                sigma: sigma,
                child: SizedBox(width: 40, height: 40),
              ),
            ],
          ),
        ),
      ),
    );

    final backdrop = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(
      backdrop.filter,
      ImageFilter.compose(
        outer: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        inner: AppTokens.glassSaturation,
      ),
    );
  });

  testWidgets('省电档：GlassBlur 不套 filter，GlassPanel 不挂 BackdropFilter',
      (tester) async {
    lowEndDevice = true;
    recomputeGlassTiers();
    expect(glassBlurDisabled.value, isTrue);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              GlassBlur(
                sigma: 8,
                child: SizedBox(width: 40, height: 40),
              ),
              GlassPanel(child: SizedBox(width: 40, height: 40)),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
  });

  Future<void> pumpShell(WidgetTester tester,
      {Size size = const Size(420, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // 主壳首帧后会请求权限；这里测底栏而非权限引导。
    stubPluginChannels(overlayPermissionGranted: true);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarded': true,
      'lastSeenVersion': appVersion,
    });
    final raw = sqlite3.sqlite3.openInMemory();
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);

    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[databaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: HomeShell()),
    ));
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(find.byType(ModalBarrier).hitTestable(), findsNothing,
        reason: '底栏交互夹具不能被启动弹窗的模态遮罩拦截');
  }

  Future<void> disposeShell(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
  }

  Offset lastTab(WidgetTester tester) {
    final Rect nav = tester.getRect(find.byKey(const Key('glass-nav-bar')));
    return Offset(nav.left + nav.width * 0.85, nav.center.dy);
  }

  testWidgets('标准底栏交互：按住期间页面不动、松手才提交', (tester) async {
    await pumpShell(tester);
    final PageController controller =
        tester.widget<PageView>(find.byType(PageView)).controller!;
    final TestGesture gesture = await tester.startGesture(lastTab(tester));
    final pagesWhileHeld = <int>[];
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      pagesWhileHeld.add(controller.page!.round());
    }
    await gesture.up();
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    final int pageAfterRelease = controller.page!.round();
    await disposeShell(tester);

    expect(pagesWhileHeld, everyElement(0), reason: '按住期间页面就不该动');
    expect(pageAfterRelease, 3, reason: '松手要落在滑块最终所在的那一格');
  });

  testWidgets('标准档：系统取消按压后回到未按住状态', (tester) async {
    await pumpShell(tester);
    bool pressed() => tester
        .widget<QScale>(find.descendant(
            of: find.byKey(const Key('glass-nav-bar')),
            matching: find.byType(QScale)))
        .pressed;

    final Rect nav = tester.getRect(find.byKey(const Key('glass-nav-bar')));
    final TestGesture gesture = await tester.startGesture(nav.center);
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(pressed(), isTrue, reason: '按下了却没进入按住态');

    await gesture.cancel();
    await tester.pump(const Duration(milliseconds: 100));
    expect(pressed(), isFalse, reason: '_pressed 卡在 true —— 胶囊会一直放大');
    await disposeShell(tester);
  });
}
