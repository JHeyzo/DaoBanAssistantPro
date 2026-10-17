// app/test/alarm_reschedule_budget_test.dart
//
// 护栏：一次 `rescheduleAll` 到底往原生发多少次跨端调用。
//
// 旧版是每条闹钟一次 `scheduleNativeAlarm`（46 条 + 日志 = 99 次跨端）。
// 新版走系统闹钟通道：一次 `scheduleSystemAlarmHousekeeping` 推 30 天表，
// 今天剩下的才逐条 `createSystemAlarm`。跨端次数从 99 降到个位数。
import 'package:drift/drift.dart' as drift show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftassistantpro/core/l10n.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/domain/shift_templates.dart';
import 'package:shiftassistantpro/features/alarm/alarm_service.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

const MethodChannel _channel =
    MethodChannel('com.daoban.shiftassistantpro/settings');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('zh');
    drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('一次 rescheduleAll 的跨端调用不超过 55 次', () async {
    final raw = sqlite3.sqlite3.openInMemory();
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);

    final repo = AppRepository(db);
    final template =
        shiftTemplates.firstWhere((x) => x.id == 'four_crew_three_shift');
    await repo.saveSchedule(
      name: template.subtitle,
      anchorDate: dateOnly(DateTime.now()),
      classes: template.classes,
      cycle: template.cycle,
      makeCurrent: true,
      teamCount: template.teamCount,
      teamNames: L10n.defaultTeamNames(template.teamCount),
      ourTeamIndex: 0,
      teamOffsets: template.teamOffsets,
    );

    final calls = <String, int>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls[call.method] = (calls[call.method] ?? 0) + 1;
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null));

    await AlarmService.rescheduleAll(repo);

    final int total = calls.values.fold<int>(0, (a, b) => a + b);
    expect(total, lessThanOrEqualTo(55),
        reason: '系统闹钟通道下跨端应该是个位数。实测本次：$total');
    expect(calls['logInfo'] ?? 0, lessThanOrEqualTo(3),
        reason: '只许剩收尾那几条汇总，不许逐条记');
    // 正面：30 天表必须一次推过去
    expect(calls['scheduleSystemAlarmHousekeeping'] ?? 0, equals(1),
        reason: '未来 30 天的闹钟表要一次推给原生 housekeeping');
    // 反面：不再逐条排原生响铃闹钟
    expect(calls['scheduleNativeAlarm'] ?? 0, equals(0),
        reason: 'App 不再自己响铃，不该再调 scheduleNativeAlarm');
  });
}
