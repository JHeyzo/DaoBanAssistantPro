import 'dart:convert';

import 'shift_rotation.dart';

/// 一套排班**配置文件**：把某套方案的**结构**存下来，可导出/导入。
///
/// v0.11.3 起模板系统已拆除内置库与「我的模板」，只留配置文件：
/// 新建排班时「空白模板」或「导入配置文件」二选一；编辑页可「导出配置文件」。
///
/// 结构 = 班次定义 + 周期序列（一格可多个班次）+ 休息规则 + 班组错位；
/// **不含**方案名之外的身份、基准日与按天覆盖 —— 那些是「这一套方案」的事，
/// 用配置建出来的新方案自己定（新建时基准日 = 今天、「我们班组」= 第 1 组）。
///
/// 保存时班组错位**归一化成「我们班组在第 0 位、错位 0」**：新建排班那条路
/// （`createScheduleFromTemplatePicker`）写死 `ourTeamIndex: 0`，不归一化的话
/// 用配置建出来的方案里「我们班组」会指到别人身上。
class ScheduleTemplate {
  const ScheduleTemplate({
    this.id,
    required this.name,
    required this.classes,
    required this.cycle,
    required this.restRule,
    required this.teamCount,
    required this.teamOffsets,
  });

  /// 库里的行 id；null = 还没落库（配置文件场景恒为 null）。
  final int? id;

  final String name;
  final List<ShiftClass> classes;

  /// 周期：一格可多个班次下标（如 `[白, 值]` 同一天）。
  final List<List<int>> cycle;

  /// 休息规则（none = 不用规则）。
  final RestRule restRule;

  final int teamCount;
  final List<int> teamOffsets;

  int get cycleLength => cycle.length;

  /// 每天同时在上班的班组数（供选择页卡片上那行「每天在岗 N 个班组」用）。
  ///
  /// 一格多个班次时，有任一非休息班次即算在岗。
  int get workingTeamsPerDay {
    if (cycle.isEmpty) return 0;
    var count = 0;
    for (var t = 0; t < teamCount; t++) {
      final offset = t < teamOffsets.length ? teamOffsets[t] : t;
      var idx = offset % cycle.length;
      if (idx < 0) idx += cycle.length;
      final dayClasses = cycle[idx];
      var working = false;
      for (final classIndex in dayClasses) {
        if (classIndex < 0 || classIndex >= classes.length) continue;
        if (!classes[classIndex].isRest) {
          working = true;
          break;
        }
      }
      if (working) count++;
    }
    return count;
  }

  /// 从一套方案里取配置；[name] 是配置名。
  ///
  /// 把「我们班组」转到第 0 位并让它的错位变成 0（整组一起平移，班组之间的
  /// 相对错位一个像素都不动）。错位表短于班组数时按回退规则补
  /// （`i - ourTeamIndex`），与域里算出来的结果保持一致。
  static ScheduleTemplate fromSchedule(ShiftSchedule s,
      {required String name}) {
    final n = s.teamCount;
    final ours = (s.ourTeamIndex >= 0 && s.ourTeamIndex < n) ? s.ourTeamIndex : 0;
    final offsets = <int>[
      for (var i = 0; i < n; i++)
        i < s.teamOffsets.length ? s.teamOffsets[i] : i - ours,
    ];
    final base = offsets.isEmpty ? 0 : offsets[ours];
    // 先按「我们班组打头」重排，再整体减去它的错位。
    final rotated = <int>[
      for (var i = 0; i < n; i++) offsets[(i + ours) % n],
    ];
    return ScheduleTemplate(
      name: name,
      classes: s.classes,
      cycle: s.cycle,
      restRule: s.restRule,
      teamCount: n,
      teamOffsets: [for (final o in rotated) o - base],
    );
  }

  /// 导出为配置文件 JSON（用户存文件）。
  String toConfigJson() => jsonEncode({
        'name': name,
        'version': 1,
        'classes': jsonDecode(encodeTemplateClasses(classes)),
        'cycle': cycle,
        'restRule': restRule.toJson(),
        'teamCount': teamCount,
        'teamOffsets': teamOffsets,
      });

  /// 从配置文件 JSON 解析；坏数据返回 null。
  static ScheduleTemplate? fromConfigJson(String raw) {
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final classes = decodeTemplateClasses(
        jsonEncode(map['classes'] ?? []),
      );
      final cycleRaw = map['cycle'];
      final cycle = <List<int>>[];
      if (cycleRaw is List) {
        for (final day in cycleRaw) {
          if (day is List) {
            cycle.add([
              for (final e in day)
                if (e is num) e.toInt(),
            ]);
          } else if (day is num) {
            // 兼容旧格式 List<int>：单数字视为单班次的一天。
            cycle.add([day.toInt()]);
          }
        }
      }
      final restRule = RestRule.fromJson(map['restRule']);
      final teamCount = (map['teamCount'] as num?)?.toInt() ?? 1;
      final offsetsRaw = map['teamOffsets'];
      final teamOffsets = <int>[];
      if (offsetsRaw is List) {
        for (final e in offsetsRaw) {
          if (e is num) teamOffsets.add(e.toInt());
        }
      }
      if (classes.isEmpty || cycle.isEmpty) return null;
      return ScheduleTemplate(
        name: '${map['name'] ?? ''}',
        classes: classes,
        cycle: cycle,
        restRule: restRule,
        teamCount: teamCount,
        teamOffsets: teamOffsets,
      );
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// 编解码
//
// 配置文件走 JSON（班次定义字段多、有可空值，CSV 会在空值上变得没法读）。
// 解码一律**容错**：坏数据返回空表/默认值，不让一份坏文件把导入流程废掉。
// ---------------------------------------------------------------------------

/// 周期 → JSON 数组（如 `[[0],[1],[0,1]]`）。
String encodeTemplateCycle(List<List<int>> cycle) => jsonEncode(cycle);

/// JSON 数组 → 周期；坏数据返回空表。
/// 兼容旧格式 `List<int>`（单数字视为单班次的一天）。
List<List<int>> decodeTemplateCycle(String raw) {
  if (raw.trim().isEmpty) return const [];
  try {
    final list = jsonDecode(raw);
    if (list is! List) return const [];
    return [
      for (final day in list)
        if (day is List)
          [for (final e in day) if (e is num) e.toInt()]
        else if (day is num)
          [day.toInt()],
    ];
  } catch (_) {
    return const [];
  }
}

String encodeTemplateOffsets(List<int> offsets) => offsets.join(',');

List<int> decodeTemplateOffsets(String raw) => decodeTemplateInts(raw);

/// 逗号分隔的整数串；空串返回空表，解析不出来的那一段按 0 处理
/// （与 `parseTeamOffsets` 同一条容错口径）。
List<int> decodeTemplateInts(String raw) {
  if (raw.trim().isEmpty) return const [];
  return raw.split(',').map((e) => int.tryParse(e.trim()) ?? 0).toList();
}

/// 班次定义 → JSON 数组。id 不存：配置里的班次不需要稳定身份（按天改班的覆盖
/// 只引用**方案**里的班次，与配置无关），存了反而会与新方案里的自增 id 撞车。
///
/// v0.11.3 起带 `isDuty`（语义标记：工作/值班/休息）。
String encodeTemplateClasses(List<ShiftClass> classes) => jsonEncode([
      for (final c in classes)
        {
          'name': c.name,
          'abbr': c.abbr,
          'startMinute': c.startMinute,
          'endMinute': c.endMinute,
          'isRest': c.isRest,
          'isDuty': c.isDuty,
          'color': c.color,
          'alarmEnabled': c.alarmEnabled,
          'alarms': [
            for (final a in c.alarms) {'minute': a.minute, 'label': a.label},
          ],
        }
    ]);

/// JSON 数组 → 班次定义；坏数据返回空表（调用方据此跳过这一条）。
List<ShiftClass> decodeTemplateClasses(String raw) {
  if (raw.trim().isEmpty) return const [];
  try {
    final list = jsonDecode(raw);
    if (list is! List) return const [];
    return [
      for (final e in list)
        if (e is Map)
          ShiftClass(
            name: '${e['name'] ?? ''}',
            abbr: e['abbr'] as String?,
            startMinute: (e['startMinute'] as num?)?.toInt(),
            endMinute: (e['endMinute'] as num?)?.toInt(),
            isRest: e['isRest'] == true,
            isDuty: e['isDuty'] == true,
            color: (e['color'] as num?)?.toInt() ?? 0xFF5B7FFF,
            alarmEnabled: e['alarmEnabled'] == true,
            alarms: _decodeAlarms(e),
          ),
    ];
  } catch (_) {
    return const [];
  }
}

/// 班次对象 → 闹钟列表。
///
/// 新格式读 `alarms`；**没有就回退**读旧的两个字段 —— 用户升级前存下的配置
/// 还在硬盘上，只有 `alarmEnabled` + `alarmMinute`。旧格式里
/// `alarmMinute` 为空 → 空表，**不能退化成「一条 0 点的闹钟」**。
List<ShiftAlarm> _decodeAlarms(Map e) {
  final list = e['alarms'];
  if (list is List) {
    return [
      for (final a in list)
        if (a is Map && a['minute'] is num)
          ShiftAlarm(
            minute: (a['minute'] as num).toInt(),
            label: a['label'] is String ? a['label'] as String : null,
          ),
    ];
  }
  final legacy = e['alarmMinute'];
  if (legacy is num) return [ShiftAlarm(minute: legacy.toInt())];
  return const [];
}
