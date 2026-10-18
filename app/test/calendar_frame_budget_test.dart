// app/test/calendar_frame_budget_test.dart
//
// **护栏**：标准日历点选切换日期时，一帧重建的 widget 数应保持较小。
// 日期块的位置由 `AnimatedPositioned` 驱动，不应为此重建整页。
import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/calendar/calendar_screen.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// 一帧里重建了多少个 element。
///
/// 用框架自带的 `debugOnRebuildDirtyWidget`（`Element.rebuild()` 里逐个回调）——
/// 它数的是**真的重跑过 build 的那些**，比「树上有多少个 widget」有鉴别力得多。
Future<int> _rebuildsInOneFrame(
  WidgetTester tester, {
  required Future<void> Function() act,
}) async {
  var n = 0;
  var on = false;
  debugOnRebuildDirtyWidget = (Element e, bool wasDirty) {
    if (on) n++;
  };

  await act();
  await tester.pump(); // 处理这一下交互本身
  on = true;
  await tester.pump(const Duration(milliseconds: 16)); // 动画里的一帧

  // ⚠️ **必须在测试体里还原**（`addTearDown` 跑在框架的自检之后 —— 与
  // `glow_layer_test.dart` 同一条）。
  debugOnRebuildDirtyWidget = null;
  return n;
}

Future<void> _pumpCalendar(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final raw = sqlite3.sqlite3.openInMemory();
  final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
  addTearDown(db.close);

  final d = defaultSchedule();
  await AppRepository(db).saveSchedule(
    name: d.name,
    anchorDate: dateOnly(DateTime.now()),
    classes: d.classes,
    cycle: d.cycle,
    makeCurrent: true,
    teamCount: d.teamCount,
    teamNames: d.teamNames,
    ourTeamIndex: 0,
    teamOffsets: d.teamOffsets,
  );

  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[databaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: CalendarScreen()),
  ));
  await tester.pumpAndSettle();
}

/// 收尾：主动拆掉界面，并推一下时钟让 drift 取消查询流时排的那个零时长定时器真的跑掉。
///
/// 不这么做，框架会在测试体结束时抛「A Timer is still pending even after the widget
/// tree was disposed」—— 表现是这条用例**挂到超时**才失败（`calendar_screen_test.dart`
/// 的 `_disposeCalendar` 是同一件事）。
Future<void> _disposeCalendar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 20));
}

/// 点一个**离今天够远**的日子 —— 那会起一次滑行（每帧都在动），正是要量的场景。
Finder _farDay() {
  final int today = DateTime.now().day;
  return find.byKey(
      ValueKey<String>('day-card-${today > 15 ? today - 7 : today + 7}'));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh');
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('标准档点日期动画时，一帧重建的 widget 数 ≤ 20', (tester) async {
    await _pumpCalendar(tester);
    final int n =
        await _rebuildsInOneFrame(tester, act: () => tester.tap(_farDay()));
    expect(n, lessThanOrEqualTo(20),
        reason: '标准选中块应由 AnimatedPositioned 动画驱动，而不是重建整页；实测：$n');
    await _disposeCalendar(tester);
  });
}
