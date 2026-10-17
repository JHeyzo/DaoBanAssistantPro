// app/test/post_duty_alarm_test.dart
//
// 「值班次日」闹钟规则 —— `PostDutyAlarmRule` / `isPostDutyDay` /
// `effectiveDayAlarms` / `planShiftAlarms(..., postDutyRule:)` /
// `suggestDutyClassName` / `defaultPostDutyMinute`。
//
// 背景（v0.11.2 用户痛点）：闹钟只能按「班种」设。用户要的是按「班次」——
// 普通白班 7:15 起床，但值班（17:00 → 次日 08:30）熬一宿之后，次日早上的
// 白班要 7:45。规则：前一天是值班班种时，当天第一条班次闹钟改用规则时刻。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:shiftassistantpro/features/alarm/alarm_service.dart';

const _rule = PostDutyAlarmRule(minute: 7 * 60 + 45);

/// 两天一循环：9/21（周一）值班、9/22 白班、9/23 值班……
ShiftSchedule _schedule() => ShiftSchedule(
      name: '测试',
      anchorDate: DateTime.utc(2026, 9, 21),
      classes: const [
        ShiftClass(
            id: 1,
            name: '白班',
            abbr: '白',
            startMinute: 8 * 60,
            endMinute: 17 * 60,
            alarmEnabled: true,
            alarms: [ShiftAlarm(minute: 7 * 60 + 15)]),
        ShiftClass(
            id: 2,
            name: '值班',
            abbr: '值',
            startMinute: 17 * 60,
            endMinute: 8 * 60,
            isDuty: true,
            alarmEnabled: true,
            alarms: [ShiftAlarm(minute: 16 * 60 + 30)]),
        ShiftClass(id: 3, name: '休班', abbr: '休', isRest: true),
      ],
      cycle: const [[1], [0]],
      teamCount: 1,
      teamNames: const ['我'],
      teamOffsets: const [0],
    );

void main() {
  group('isPostDutyDay', () {
    test('值班次日为真，其余为假', () {
      final s = _schedule();
      // 9/21 值班 → 9/22 是值班次日
      expect(isPostDutyDay(s, DateTime(2026, 9, 22), _rule), isTrue);
      // 9/22 白班 → 9/23 不是
      expect(isPostDutyDay(s, DateTime(2026, 9, 23), _rule), isFalse);
      // 9/23 值班 → 9/24 是
      expect(isPostDutyDay(s, DateTime(2026, 9, 24), _rule), isTrue);
    });

    // v0.11.3 起按语义标记匹配，不再按班次名 —— 此测试已废弃
    // test('班次名对不上不命中', () {
    //   final s = _schedule();
    //   const other =
    //       PostDutyAlarmRule(minute: 7 * 60 + 45);
    //   expect(isPostDutyDay(s, DateTime(2026, 9, 22), other), isFalse);
    // });
  });

  group('effectiveDayAlarms', () {
    test('命中时只换第一条，label 保留', () {
      final s = _schedule();
      final t = s.shiftsOn(DateTime(2026, 9, 22)).first;
      expect(t.name, '白班');
      final eff = effectiveDayAlarms(s, DateTime(2026, 9, 22), t, _rule);
      expect(eff.length, 1);
      expect(eff.first.minute, 7 * 60 + 45);
    });

    test('未命中时返回原列表本体', () {
      final s = _schedule();
      final t = s.shiftsOn(DateTime(2026, 9, 23)).first;
      expect(identical(effectiveDayAlarms(s, DateTime(2026, 9, 23), t, _rule),
          t.alarms), isTrue);
    });

    test('rule 为 null 时返回原列表本体', () {
      final s = _schedule();
      final t = s.shiftsOn(DateTime(2026, 9, 22)).first;
      expect(
          identical(effectiveDayAlarms(s, DateTime(2026, 9, 22), t, null),
              t.alarms),
          isTrue);
    });

    test('多条闹钟只换第一条，其余不动', () {
      final s = ShiftSchedule(
        name: '测试',
        anchorDate: DateTime.utc(2026, 9, 21),
        classes: const [
          ShiftClass(
              id: 1,
              name: '白班',
              startMinute: 8 * 60,
              endMinute: 17 * 60,
              alarmEnabled: true,
              alarms: [
                ShiftAlarm(minute: 7 * 60 + 15, label: '起床'),
                ShiftAlarm(minute: 12 * 60 + 30, label: '午休'),
              ]),
          ShiftClass(
              id: 2, name: '值班', startMinute: 17 * 60, endMinute: 8 * 60, isDuty: true),
        ],
        cycle: const [[1], [0]],
        teamCount: 1,
        teamNames: const ['我'],
        teamOffsets: const [0],
      );
      final t = s.shiftsOn(DateTime(2026, 9, 22)).first;
      final eff = effectiveDayAlarms(s, DateTime(2026, 9, 22), t, _rule);
      expect(eff.length, 2);
      expect(eff[0].minute, 7 * 60 + 45);
      expect(eff[0].label, '起床');
      expect(eff[1].minute, 12 * 60 + 30);
      expect(eff[1].label, '午休');
    });
  });

  group('planShiftAlarms + postDutyRule', () {
    test('值班次日 7:45，非值班次日 7:15', () {
      final s = _schedule();
      final plans = planShiftAlarms(s,
          from: DateTime(2026, 9, 21), days: 3, postDutyRule: _rule);
      // 9/21 值班 16:30、9/22 白班 7:45（规则）、9/23 值班 16:30
      final byDay = <int, List<ShiftAlarmPlan>>{};
      for (final p in plans) {
        byDay.putIfAbsent(p.offset, () => []).add(p);
      }
      expect(byDay[0]!.single.alarm.minute, 16 * 60 + 30);
      expect(byDay[1]!.single.alarm.minute, 7 * 60 + 45);
      expect(byDay[1]!.single.alarmIndex, 0);
      expect(byDay[2]!.single.alarm.minute, 16 * 60 + 30);
    });

    test('不传 rule 时行为不变（7:15）', () {
      final s = _schedule();
      final plans =
          planShiftAlarms(s, from: DateTime(2026, 9, 21), days: 3);
      final second =
          plans.firstWhere((p) => p.offset == 1);
      expect(second.alarm.minute, 7 * 60 + 15);
    });

    test('规则时刻参与「前一天」落点重算', () {
      // 规则时刻 23:00 晚于白班上班钟点 → 落到前一天晚上（既有两档模型的语义）。
      const nightRule =
          PostDutyAlarmRule(minute: 23 * 60);
      final s = _schedule();
      final plans = planShiftAlarms(s,
          from: DateTime(2026, 9, 21), days: 3, postDutyRule: nightRule);
      final second = plans.firstWhere((p) => p.offset == 1);
      expect(second.fireAt, DateTime(2026, 9, 21, 23, 0));
    });
  });

  group('suggestDutyClassName', () {
    test('名字含「值」优先', () {
      expect(
          suggestDutyClassName(const [
            ShiftClass(name: '白班'),
            ShiftClass(name: '值班'),
            ShiftClass(name: '休班', isRest: true),
          ]),
          '值班');
    });

    test('没有含值的名字时选跨夜班', () {
      expect(
          suggestDutyClassName(const [
            ShiftClass(
                name: '白班', startMinute: 8 * 60, endMinute: 17 * 60),
            ShiftClass(
                name: '夜班', startMinute: 22 * 60, endMinute: 6 * 60),
          ]),
          '夜班');
    });

    test('全是休班返回空串', () {
      expect(
          suggestDutyClassName(
              const [ShiftClass(name: '休班', isRest: true)]),
          '');
    });
  });

  group('defaultPostDutyMinute', () {
    test('第一个开着闹钟的班种的第一条 +30 分钟', () {
      expect(
          defaultPostDutyMinute(const [
            ShiftClass(name: '休班', isRest: true),
            ShiftClass(
                name: '白班',
                alarmEnabled: true,
                alarms: [ShiftAlarm(minute: 7 * 60 + 15)]),
          ]),
          7 * 60 + 45);
    });

    test('没有配闹钟的班种时落回 07:45', () {
      expect(defaultPostDutyMinute(const [ShiftClass(name: '白班')]),
          7 * 60 + 45);
    });
  });
}
