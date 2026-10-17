// app/test/system_alarm_days_test.dart
//
// 系统闹钟通道的核心纯函数 `AlarmService.planSystemAlarmDays`：
// 把排班链 + 自定义闹钟算成「未来 30 天每天几点几分响」，推给原生 housekeeping。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/data/app_repository.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/alarm/alarm_service.dart';

/// 最小 ShiftSource：每天都是同一个班次。
class _FixedSource implements ShiftSource {
  _FixedSource(this.shift);
  final ShiftClass shift;
  @override
  String get label => 'fixed';
  @override
  ShiftClass? shiftOn(DateTime date) => shift;
  @override
  List<ShiftClass> shiftsOn(DateTime date) => [shift];
}

ShiftClass _dayShift({int alarmMinute = 7 * 60 + 30}) {
  return ShiftClass(
    name: '白班',
    startMinute: 8 * 60 + 30,
    endMinute: 17 * 60,
    alarmEnabled: true,
    alarms: [ShiftAlarm(label: '起床', minute: alarmMinute)],
  );
}

void main() {
  test('班次闹钟按触发日分组，dayOffset 从 1 开始（今天不算）', () {
    final source = _FixedSource(_dayShift());
    // 周一 10:00，闹钟 07:30（今天已过，明天起才算）
    final from = DateTime(2026, 10, 19, 10, 0); // 周一
    final days = AlarmService.planSystemAlarmDays(
      source,
      const [],
      from: from,
      days: 7,
    );
    // 7 天里每天 07:30，共 7 条（dayOffset 1..7）
    expect(days.length, 7);
    for (var i = 0; i < days.length; i++) {
      final d = days[i];
      expect(d['dayOffset'], i + 1);
      final alarms = d['alarms'] as List;
      expect(alarms.length, 1);
      expect(alarms[0]['h'], 7);
      expect(alarms[0]['m'], 30);
    }
  });

  test('前一天落点的闹钟按触发日分组（午夜班 23:00 响铃算前一天）', () {
    final shift = ShiftClass(
      name: '夜班',
      startMinute: 0, // 00:00 上班
      endMinute: 8 * 60,
      alarmEnabled: true,
      alarms: [ShiftAlarm(label: '起床', minute: 23 * 60)], // 23:00 响铃 → 前一天
    );
    final source = _FixedSource(shift);
    final from = DateTime(2026, 10, 19, 10, 0); // 周一
    final days = AlarmService.planSystemAlarmDays(
      source,
      const [],
      from: from,
      days: 3,
    );
    // 10-20 的夜班，闹钟落在 10-19 23:00（今天，dayOffset=0，不进 housekeeping 表，
    // 由调用方直接 createSystemAlarm）；
    // 10-21 的夜班落在 10-20 23:00（dayOffset=1），10-22 的落在 10-21（dayOffset=2）。
    expect(days.length, 2);
    expect(days[0]['dayOffset'], 1);
    expect((days[0]['alarms'] as List)[0]['h'], 23);
    expect(days[1]['dayOffset'], 2);
  });

  test('自定义闹钟：每天、每周、一次性都按规则进表', () {
    final source = _FixedSource(ShiftClass(
      name: '休',
      startMinute: 0,
      endMinute: 0,
      alarmEnabled: false,
      alarms: const [],
    ));
    final from = DateTime(2026, 10, 19, 10, 0); // 周一
    final custom = [
      CustomAlarm(id: 1, hour: 8, minute: 0, repeatType: 1, weekdays: 0, enabled: true), // 每天
      CustomAlarm(
          id: 2,
          hour: 9,
          minute: 0,
          repeatType: 2,
          weekdays: 1 << (2 - 1), // 仅周二
          enabled: true),
      CustomAlarm(
          id: 3,
          hour: 10,
          minute: 0,
          repeatType: 0,
          weekdays: 0,
          onceDate: DateTime(2026, 10, 21),
          enabled: true), // 仅 10-21
      CustomAlarm(id: 4, hour: 11, minute: 0, repeatType: 1, weekdays: 0, enabled: false), // 关掉的不算
    ];
    final days = AlarmService.planSystemAlarmDays(
      source,
      custom,
      from: from,
      days: 3,
    );
    // dayOffset=1 (10-20 周二): 每天(8:00) + 周二(9:00) = 2 条
    expect((days[0]['alarms'] as List).length, 2);
    // dayOffset=2 (10-21 周三): 每天(8:00) + 一次性(10:00) = 2 条
    expect((days[1]['alarms'] as List).length, 2);
    // dayOffset=3 (10-22 周四): 每天(8:00) = 1 条
    expect((days[2]['alarms'] as List).length, 1);
  });

  test('按天关闭的班次闹钟不进表（overrides）', () {
    final source = _FixedSource(_dayShift());
    final from = DateTime(2026, 10, 19, 10, 0);
    final tuesday = DateTime(2026, 10, 20);
    final days = AlarmService.planSystemAlarmDays(
      source,
      const [],
      from: from,
      days: 3,
      overrides: {dayNumber(tuesday): false},
    );
    // 周二被关了，所以 dayOffset=1 那天没有闹钟
    final d1 = days.firstWhere((d) => d['dayOffset'] == 1,
        orElse: () => {'alarms': []});
    expect((d1['alarms'] as List).isEmpty, isTrue);
  });
}
