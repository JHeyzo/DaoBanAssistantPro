import 'package:shiftassistantpro/domain/shift_rotation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DutyRotation JSON', () {
    test('toJson/fromJson round-trip', () {
      final r = DutyRotation(
        sequence: ['1234', '3421'],
        period: RotationPeriod.quarterly,
        sequenceStartDate: _d(2026, 1, 1),
      );
      final json = r.toJson();
      final back = DutyRotation.fromJson(json);
      expect(back.sequence, ['1234', '3421']);
      expect(back.period, RotationPeriod.quarterly);
      expect(back.sequenceStartDate, _d(2026, 1, 1));
    });
  });

  group('effectiveTeamOffsets', () {
    // 4 天周期，4 个班组，基准 offsets [0,1,2,3]，anchor 2026-01-05（周一）。
    ShiftSchedule scheduleWithRotation(DutyRotation? rotation) {
      return ShiftSchedule(
        name: 'test',
        anchorDate: _d(2026, 1, 5),
        classes: const [],
        cycle: const [
          [0],
          [0],
          [0],
          [0],
        ],
        teamCount: 4,
        teamOffsets: const [0, 1, 2, 3],
        dutyRotation: rotation,
      );
    }

    test('无轮换时返回原始 offsets', () {
      final s = scheduleWithRotation(null);
      expect(effectiveTeamOffsets(s, _d(2026, 4, 15)), [0, 1, 2, 3]);
    });

    test('第一轮（1234）offsets 不变', () {
      final s = scheduleWithRotation(DutyRotation(
        sequence: ['1234', '3421', '2143', '4312'],
        period: RotationPeriod.quarterly,
        sequenceStartDate: _d(2026, 1, 1),
      ));
      // Q1，顺序 1234 → offsets [0,1,2,3]
      expect(effectiveTeamOffsets(s, _d(2026, 2, 15)), [0, 1, 2, 3]);
    });

    test('第二轮（3421）offsets 重排', () {
      final s = scheduleWithRotation(DutyRotation(
        sequence: ['1234', '3421', '2143', '4312'],
        period: RotationPeriod.quarterly,
        sequenceStartDate: _d(2026, 1, 1),
      ));
      // Q2 nominal 从 4/1 开始。anchor 1/5，周期 4 天：
      // 周期起始日：1/5, 1/9, 1/13... 4/1 落在某个周期中间，
      // 实际切换日在 4/1 之后的第一个周期起始日。
      // 先算 4/1 之后的切换日：
      final switchDate = _nextCycleBoundaryAfterForTest(
        _d(2026, 1, 5),
        4,
        _d(2026, 4, 1),
      );
      // 切换日之后，顺序 3421 → team2→0, team3→1, team1→2, team0→3
      // 即 offsets [3,2,0,1]
      final after = switchDate.add(const Duration(days: 1));
      expect(effectiveTeamOffsets(s, after), [3, 2, 0, 1]);
      // 切换日之前一天，仍是 1234
      final before = switchDate.subtract(const Duration(days: 1));
      // before 可能在 Q1 或 Q2 nominal 区间内，但按规则应取上一轮
      final result = effectiveTeamOffsets(s, before);
      // 如果 before >= 1/1 且 < switchDate，应为 [0,1,2,3]
      expect(result, [0, 1, 2, 3]);
    });

    test('切换日当天用新顺序', () {
      final s = scheduleWithRotation(DutyRotation(
        sequence: ['1234', '3421'],
        period: RotationPeriod.quarterly,
        sequenceStartDate: _d(2026, 1, 1),
      ));
      final switchDate = _nextCycleBoundaryAfterForTest(
        _d(2026, 1, 5),
        4,
        _d(2026, 4, 1),
      );
      // 当天切 → 新顺序
      expect(effectiveTeamOffsets(s, switchDate), [3, 2, 0, 1]);
    });

    test('月度轮换', () {
      final s = scheduleWithRotation(DutyRotation(
        sequence: ['1234', '2341'],
        period: RotationPeriod.monthly,
        sequenceStartDate: _d(2026, 1, 1),
      ));
      // 1 月：1234
      expect(effectiveTeamOffsets(s, _d(2026, 1, 15)), [0, 1, 2, 3]);
      // 2 月 nominal 2/1，实际切换日在 2/1 后的第一个周期边界
      final switchDate = _nextCycleBoundaryAfterForTest(
        _d(2026, 1, 5),
        4,
        _d(2026, 2, 1),
      );
      final after = switchDate.add(const Duration(days: 1));
      // 2341 → team1→0, team2→1, team3→2, team0→3 → [3,0,1,2]
      expect(effectiveTeamOffsets(s, after), [3, 0, 1, 2]);
    });
  });
}

DateTime _d(int y, int m, int d) => DateTime(y, m, d);

/// 测试用的周期边界计算（与 domain 内的 _nextCycleBoundaryAfter 同逻辑）。
DateTime _nextCycleBoundaryAfterForTest(
    DateTime anchor, int cycleLength, DateTime nominalDate) {
  if (cycleLength <= 0) return nominalDate;
  final a = DateTime(anchor.year, anchor.month, anchor.day);
  final n = DateTime(nominalDate.year, nominalDate.month, nominalDate.day);
  final days = n.difference(a).inDays;
  var k = days ~/ cycleLength;
  if (days % cycleLength != 0 || days < 0) {
    if (days >= 0) k += 1;
  }
  if (k < 0) k = 0;
  return a.add(Duration(days: k * cycleLength));
}
