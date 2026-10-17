// 排班轮换引擎 —— 纯 Dart，无 Flutter 依赖，可直接 dart test。
//
// 两层模型：
//   classes —— 班次定义（白班/上夜班/休班…），一个班次只定义一次
//   cycle   —— 周期序列，长度即周期，元素是 classes 的下标
//
// 核心公式：
//   某班组某天的班次 = classes[ cycle[ (目标日 − 基准日 + 班组偏移) mod 周期 ] ]

import 'package:characters/characters.dart';

// `defaultSchedule()` 的文案要按当前语言生成。`l10n.dart` 只依赖 intl
// （纯 Dart），所以本文件「无 Flutter 依赖、可直接 dart test」的性质不变。
import '../core/l10n.dart';

/// 小时+分钟 → 分钟自午夜（0..1439）。
int toMinutes(int hour, int minute) => hour * 60 + minute;

/// 两个日期之间的"整日"差，用 UTC 日期整数计算，规避时区/夏令时。
int daysBetween(DateTime a, DateTime b) {
  final da = DateTime.utc(a.year, a.month, a.day);
  final db = DateTime.utc(b.year, b.month, b.day);
  return db.difference(da).inDays;
}

/// 取 UTC 的"纯日期"（时间归零）。
DateTime dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// 两个 DateTime 是不是同一天。
///
/// **不能写成 `a == b`**：`DateTime.==` 连 `isUtc` 一起比，而 [dateOnly] 给的是
/// UTC 日期、日历网格里逐格构造的是本地日期 —— 同一天也会判成不等。日历上
/// 「今天加粗」与「选中那格的胶囊实心」都靠这个判断，用 `==` 会静默失效
/// （网格里的「今天」因此从来没加粗过）。
bool isSameDay(DateTime a, DateTime b) => daysBetween(a, b) == 0;

/// 纯日期 → 自 epoch 的天数（按天闹钟覆盖表的主键）。
int dayNumber(DateTime date) {
  final d = DateTime.utc(date.year, date.month, date.day);
  return d.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
}

/// 分钟数 → `HH:mm`，供日历与编辑器共用。1440 恰好显示为 `24:00`。
///
/// [minutes] 可以超过 1440（跨过午夜后继续累加），调用方负责先减掉 1440
/// 并自行补「次日」前缀。
String formatClock(int minutes) {
  if (minutes == 1440) return '24:00';
  final m = minutes % 1440;
  final h = (m ~/ 60).toString().padLeft(2, '0');
  return '$h:${(m % 60).toString().padLeft(2, '0')}';
}

/// 一个班次上的**一条**联动闹钟。
///
/// [minute] 是钟面值（0..1439，分钟自午夜）。[label] 是可选名字（「起床」「午休」），
/// 为空时响铃标题退回「白班提醒」。名字的空白由**输入侧**（编辑器）负责 trim，
/// 值类型本身不做归一化 —— 它是纯数据，跟库里存的一致。
class ShiftAlarm {
  const ShiftAlarm({
    required this.minute,
    this.label,
    this.postDutyMinute,
    this.skipOnDutyDay = false,
  });

  final int minute;
  final String? label;

  /// 值班次日的替代时间（null = 跟平时一样）。
  final int? postDutyMinute;

  /// 值班当天是否跳过这条闹钟。
  final bool skipOnDutyDay;

  @override
  bool operator ==(Object other) =>
      other is ShiftAlarm &&
      other.minute == minute &&
      other.label == label &&
      other.postDutyMinute == postDutyMinute &&
      other.skipOnDutyDay == skipOnDutyDay;

  @override
  int get hashCode =>
      Object.hash(minute, label, postDutyMinute, skipOnDutyDay);

  @override
  String toString() =>
      'ShiftAlarm($minute${label == null ? '' : ', $label'}${postDutyMinute == null ? '' : ', postDuty: $postDutyMinute'}${skipOnDutyDay ? ', skipOnDuty' : ''})';
}

/// 「值班次日」闹钟规则：前一天含值班标记的班次时，当天班次的第一条联动闹钟
/// 改用 [minute]（只换第一条 —— 那是起床那条；午休之类的其余各条不动）。
///
/// 值班按**语义标记**认（[ShiftClass.isDuty]），不按班次名 —— v0.11.2 及以前按
/// 名认，季度轮换改名就断（`dutyClassName` 已删）。
class PostDutyAlarmRule {
  const PostDutyAlarmRule({required this.minute});

  /// 改用的钟点（自午夜分钟数，如 7*60+45）。
  final int minute;
}

/// [date] 的前一天是否含值班（按语义标记认；前一天是休班/无班不算）。
bool isPostDutyDay(ShiftSource source, DateTime date, PostDutyAlarmRule rule) {
  final prev = source.shiftsOn(DateTime(date.year, date.month, date.day - 1));
  return prev.any((c) => c.isDuty && !c.isRest);
}

/// 建议的值班班种：有标 duty 的直接拿它；没有时退回旧逻辑（名字含「值」/duty
/// 的优先，其次跨夜的非休息班次，再次第一个非休息班次）；都没有返回空串
/// （调用方此时不应启用规则）。
String suggestDutyClassName(Iterable<ShiftClass> classes) {
  for (final c in classes) {
    if (c.isDuty && !c.isRest) return c.name;
  }
  ShiftClass? fallback;
  ShiftClass? crossNight;
  for (final c in classes) {
    if (c.isRest) continue;
    fallback ??= c;
    final n = c.name.toLowerCase();
    if (n.contains('值') || n.contains('duty')) return c.name;
    if (crossNight == null && c.endsNextDay) crossNight = c;
  }
  return crossNight?.name ?? fallback?.name ?? '';
}

/// 值班次日规则的默认时刻：第一个开着联动闹钟的非休息班种的第一条闹钟 + 30 分钟
/// （「比平时多睡半小时」）；没有配闹钟的班种时落回 07:45。
int defaultPostDutyMinute(Iterable<ShiftClass> classes) {
  for (final c in classes) {
    if (!c.isRest && c.alarmEnabled && c.alarms.isNotEmpty) {
      return (c.alarms.first.minute + 30) % 1440;
    }
  }
  return 7 * 60 + 45;
}

/// 一个班次最多挂几个联动闹钟。
///
/// **不是产品口味，是原生 id 空间的硬上限**：原生 id 是
/// `序号 × 天数窗口 + 天数偏移`（见 `alarm_service.dart` 的 `_shiftDaysHorizon`），
/// Kotlin 侧 `cancelAllNativeAlarms` 扫的是 `0..400`（`MainActivity.kt:550`）。
/// 6 × 60 = 360 ≤ 400 刚好放得下。**改这个数或改天数窗口，必须同时改另一边。**
const int maxAlarmsPerShift = 6;

/// 某条闹钟的钟点落在上班的**前一天**还是**班次当天**。
///
/// 规则（spec §4.2）：
///   ① 钟点落在**值班窗口内**（`[start, end)`，按班次相对时刻算 —— 跨午夜与
///      24 小时班都成立）→ **当天**。班中间的闹钟（白班的午休 12:30、零点班的
///      班中 03:00）要的就是这一档。
///   ② 否则钟点**晚于上班钟点** → **前一天**。00:00 上班、23:00 响铃排前一天的
///      23:00 —— 排在班次当天就已经是班后 15 小时（v0.8.9 修好的那条）。
///   ③ 否则 → **当天**。
///
/// 与旧规则（`alarm.minute > start` 一条判据）的差异**只有第 ① 档**：旧规则会把
/// 班中间的闹钟搬到 20 多小时前。其余钟点逐条相同，包括两个边界 ——
/// 正好等于下班时刻 / 下班之后的钟点走第 ② ③ 档，落哪天取决于它相对上班钟点的
/// 大小（00:00 班的 08:00 → 前一天；20:00 班的 08:00 → 当天），两种形状都与旧规则
/// 逐字相同。这两类钟点用户真想要的是「次日」，两档模型表达不了，见 spec §9。
///
/// 时间没填：上班没填 → 判不了，按当天（不瞎挪一天）；下班没填 → 窗口算不出，
/// 退回旧规则（只按上班钟点判）。
bool alarmFallsOnPreviousDay(ShiftClass shift, ShiftAlarm alarm) {
  final s = shift.startMinute;
  if (s == null) return false;
  final e = shift.endMinute;
  if (e != null) {
    // 值班时长。**班次有两种存法**：累计式（24 小时值班 480 → 1920）与回绕式
    // （夜班 20:30 → 08:30 存成 510 < 1230 —— 内置 12 小时制模板与编辑器产出的
    // 都是这一种）。所以要补一天再减：直接 `e - s` 在回绕式下**是负的**，窗口
    // 判据会静默失效、班中闹钟又回到前一天（独立审查抓出来的；`shift_rotation_test`
    // 里「回绕式存法的跨午夜班」与「两种存法同解」两条是它的护栏）。
    final span = e > s ? e - s : e - s + _dayMinutes;
    final rel = ((alarm.minute - s) % _dayMinutes + _dayMinutes) % _dayMinutes;
    if (rel < span) return false;
  }
  return alarm.minute > s;
}

const int _dayMinutes = 1440;

/// 两个闹钟列表逐条相等（本文件不引 Flutter，拿不到 `listEquals`）。
bool _sameAlarms(List<ShiftAlarm> a, List<ShiftAlarm> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 班次语义标记：一个班次在排班语义上属于哪一类。
///
/// 这是 v0.11.3 引入的「语义身份」—— 改名、调序、删班次都不影响它。
/// 值班次日闹钟、休息规则的「跟随值班」、日历的红折角，认的都是它，
/// 不再认班次名（v0.11.2 及以前按名认，季度轮换改名就断）。
enum ShiftTag {
  /// 工作：普通的班（白班、夜班…）。
  work,

  /// 值班：行政班的值班（17:00–次日 08:30 那种）。三班倒没有值班，
  /// 只有深夜班/浅夜班 —— 那些标「工作」，别标「值班」。
  duty,

  /// 休息：不响联动闹钟。
  rest,
}

/// 班次定义：一个班次只定义一次，周期里的每一天引用它。
class ShiftClass {
  const ShiftClass({
    this.id,
    required this.name,
    this.abbr,
    this.startMinute,
    this.endMinute,
    this.isRest = false,
    this.isDuty = false,
    this.color = 0xFF5B7FFF,
    this.alarmEnabled = false,
    this.alarms = const [],
  });

  /// 库里的行 id；null = 还没落库的新班次。
  ///
  /// **这个字段是「按天改班」能成立的前提**：覆盖表引用的是班次定义，而
  /// `saveSchedule` 从前每次保存都把班次行删光重建、id 全变 —— 有了稳定 id，
  /// 覆盖才指得住（spec §4）。
  final int? id;

  /// 班次名（自由文本），如 白班 / 上夜班 / 下夜班 / 大休。
  final String name;

  /// 日历格子里的 1~2 字简称；为空时按 [name] 推断。
  final String? abbr;

  /// 工作开始时间（分钟自开始日午夜）。
  final int? startMinute;

  /// 工作结束时间（分钟自开始日午夜）；跨过午夜后继续累加，
  /// 因此 24 小时班的值班是 480 → 1920（08:00 → 次日 08:00）。
  final int? endMinute;

  /// 是否休息日（不响联动闹钟）。
  final bool isRest;

  /// 是否值班（语义标记）。与 [isRest] 互斥 —— 两个都 true 是非法状态，
  /// 以 [isRest] 为准（[tag] 里 rest 优先）。
  final bool isDuty;

  /// 语义标记：[isRest] → rest，[isDuty] → duty，否则 work。
  ShiftTag get tag => isRest ? ShiftTag.rest : (isDuty ? ShiftTag.duty : ShiftTag.work);

  /// 日历格子的 ARGB 颜色。
  final int color;

  /// 联动闹钟总开关：关掉**不清空** [alarms]（用户手滑关一下不该丢配置）。
  final bool alarmEnabled;

  /// 这个班次的联动闹钟（有序）。
  ///
  /// **顺序就是原生 id 里的「序号」**（见 `alarm_service.dart` 的 `_shiftDaysHorizon`）——
  /// 所以用户在编辑页里调整顺序会让闹钟换号（可接受：编辑之后必然重排、`cancelAll`
  /// 先跑），但**重排本身绝不能重新编号**。上限 [maxAlarmsPerShift]。
  final List<ShiftAlarm> alarms;

  /// 工作窗口是否跨过午夜。
  bool get crossesMidnight {
    final s = startMinute, e = endMinute;
    if (s == null || e == null) return false;
    return e < s || e > 1440;
  }

  /// 结束时间的钟面值（0..1439）；跨到次日时已减掉 1440。
  int? get endClockMinute => endMinute == null ? null : endMinute! % 1440;

  /// 结束时间是否落在次日（含 24:00 与 24 小时班）。
  bool get endsNextDay {
    final s = startMinute, e = endMinute;
    if (s == null || e == null) return false;
    return e >= 1440 || e < s;
  }

  /// 日历格子显示的简称：优先用 [abbr]，为空时按名称推断。
  ///
  /// 用 `characters.first`（整字素簇）而不是 `substring(0, 1)`：
  /// 后者会把 emoji 等增补平面字符切成半个代理对，旧代码用的就是前者。
  String get shortLabel {
    final a = abbr?.trim();
    if (a != null && a.isNotEmpty) return a;
    if (isRest) return '休';
    if (name.contains('白') || name.contains('早')) return '白';
    if (name.contains('夜')) return '夜';
    return name.isEmpty ? '·' : name.characters.first;
  }

  ShiftClass copyWith({
    int? id,
    String? name,
    String? abbr,
    int? startMinute,
    int? endMinute,
    bool? isRest,
    bool? isDuty,
    int? color,
    bool? alarmEnabled,
    List<ShiftAlarm>? alarms,
  }) {
    return ShiftClass(
      id: id ?? this.id,
      name: name ?? this.name,
      abbr: abbr ?? this.abbr,
      startMinute: startMinute ?? this.startMinute,
      endMinute: endMinute ?? this.endMinute,
      isRest: isRest ?? this.isRest,
      isDuty: isDuty ?? this.isDuty,
      color: color ?? this.color,
      alarmEnabled: alarmEnabled ?? this.alarmEnabled,
      alarms: alarms ?? this.alarms,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ShiftClass &&
      other.id == id &&
      other.name == name &&
      other.abbr == abbr &&
      other.startMinute == startMinute &&
      other.endMinute == endMinute &&
      other.isRest == isRest &&
      other.isDuty == isDuty &&
      other.color == color &&
      other.alarmEnabled == alarmEnabled &&
      _sameAlarms(other.alarms, alarms);

  @override
  int get hashCode => Object.hash(id, name, abbr, startMinute, endMinute,
      isRest, isDuty, color, alarmEnabled, Object.hashAll(alarms));

  @override
  String toString() => 'ShiftClass($name, tag=$tag)';
}

/// 「某天什么班」的**唯一**查询面 —— 日历、闹钟、桌面小组件都只依赖它。
///
/// 抽出来是为了让「单套方案」与「按天衔接的多套方案」（`ScheduleChain`，
/// 见 `schedule_chain.dart`）在调用点**无法区分**：`planShiftAlarms` /
/// `AlarmService.reschedule` 从前收的是 `ShiftSchedule`，改成收这个接口之后
/// 传哪一边都对，而调用点拿到的就是「一个能回答某天什么班的东西」。
///
/// v0.11.3 起返回**列表**：一天可以叠多个班次（如白班 + 值班）。
/// 空列表 = 那天没有班次（空白表 / 无方案）。
abstract class ShiftSource {
  /// 某天的班次列表（按班次定义的顺序）；那天没有班次返回空列表。
  List<ShiftClass> shiftsOn(DateTime date);

  /// 日志用的一行描述。**不是用户可见文案**（Kotlin 的日志串本来就是中文，
  /// 仓库既有惯例）。
  String get label;
}

/// 休息规则的模式。
enum RestRuleMode {
  /// 不用规则：休息日写进周期里（ legacy 行为，三班倒那种）。
  none,

  /// 固定星期：每周固定某几天休息（如双休）。
  fixedWeekdays,

  /// 跟随值班：值班日的星期几 → 休息日的星期几（如周四值 → 周六休）。
  followDuty,
}

/// 休息规则（一套方案一条；null / mode=none = 不用规则）。
///
/// 设计见 v0.11.3：「休息跟星期走 → 用规则；休息跟节奏走 → 写进周期」。
/// 规则是「轮转层」之上的「休息层」，引擎把两层合并。
class RestRule {
  const RestRule({
    this.mode = RestRuleMode.none,
    this.fixedWeekdays = const {},
    this.followDutyMap = const {},
  });

  final RestRuleMode mode;

  /// 固定星期的休息日（1=周一 … 7=周日）。
  final Set<int> fixedWeekdays;

  /// 跟随值班的映射：值班日星期几 → 休息日星期几（1=周一 … 7=周日）。
  /// 如 {4: 6, 5: 7} = 周四值→周六休、周五值→周日休。
  final Map<int, int> followDutyMap;

  bool get isNone => mode == RestRuleMode.none;

  /// JSON 编解码（存 `shift_schedule_rows.rest_rule` 列）。
  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'fixedWeekdays': fixedWeekdays.toList()..sort(),
        'followDutyMap': {
          for (final e in followDutyMap.entries) '${e.key}': e.value,
        },
      };

  static RestRule fromJson(Map<String, dynamic> json) {
    final mode = RestRuleMode.values.firstWhere(
      (m) => m.name == json['mode'],
      orElse: () => RestRuleMode.none,
    );
    final fixed = <int>{};
    final fw = json['fixedWeekdays'];
    if (fw is List) {
      for (final e in fw) {
        final v = (e as num?)?.toInt();
        if (v != null && v >= 1 && v <= 7) fixed.add(v);
      }
    }
    final map = <int, int>{};
    final fm = json['followDutyMap'];
    if (fm is Map) {
      fm.forEach((k, v) {
        final kk = int.tryParse('$k');
        final vv = (v as num?)?.toInt();
        if (kk != null && kk >= 1 && kk <= 7 && vv != null && vv >= 1 && vv <= 7) {
          map[kk] = vv;
        }
      });
    }
    return RestRule(mode: mode, fixedWeekdays: fixed, followDutyMap: map);
  }

  @override
  bool operator ==(Object other) =>
      other is RestRule &&
      other.mode == mode &&
      other.fixedWeekdays.length == fixedWeekdays.length &&
      other.fixedWeekdays.containsAll(fixedWeekdays) &&
      other.followDutyMap.length == followDutyMap.length &&
      followDutyMap.entries
          .every((e) => other.followDutyMap[e.key] == e.value);

  @override
  int get hashCode =>
      Object.hash(mode, Object.hashAll(fixedWeekdays.toList()..sort()),
          Object.hashAll(followDutyMap.entries.map((e) => '${e.key}:${e.value}')));

  @override
  String toString() =>
      'RestRule($mode, fixed=$fixedWeekdays, follow=$followDutyMap)';
}

/// 休息规则算出来的休息日用的**合成班次**（不落库、不参与班次定义）。
///
/// 休息规则是「层」，不是「班次定义」—— 它不需要用户事先定义一个休班，
/// 引擎在解析时直接合成。显示为「休」，灰色，不响闹钟。
ShiftClass syntheticRestClass() => ShiftClass(
      name: L10n.t('休息', 'Rest'),
      abbr: L10n.t('休', 'R'),
      isRest: true,
      color: 0xFF9AA0B4,
    );

/// 一天的班次按「休 > 值 > 白」取一个代表（本月统计、桌面小组件摘要用）。
///
/// 互斥计数：一天只算一次，优先级休最高、值次之、白最后
/// （用户 2026-10-17 定；如 10 月：休4 · 白19 · 值8）。
ShiftClass? primaryByPriority(List<ShiftClass> shifts) {
  if (shifts.isEmpty) return null;
  for (final s in shifts) {
    if (s.isRest) return s;
  }
  for (final s in shifts) {
    if (s.isDuty) return s;
  }
  return shifts.first;
}

/// 一套排班方案（班次定义 + 轮换周期 + 多班组 + 休息规则）。
class ShiftSchedule implements ShiftSource {
  const ShiftSchedule({
    required this.name,
    required this.anchorDate,
    required this.classes,
    required this.cycle,
    this.teamCount = 4,
    this.teamNames = const ['一班', '二班', '三班', '四班'],
    this.ourTeamIndex = 0,
    this.teamOffsets = const [],
    this.dayOverrides = const {},
    this.restRule = const RestRule(),
  });

  /// 空白表（跟随法定节假日）：周期为空。
  bool get isBlank => cycle.isEmpty;

  final String name;

  /// 基准日：各班组在此日期的周期位置由 [teamOffsets] 显式指定。
  final DateTime anchorDate;

  /// 班次定义。
  final List<ShiftClass> classes;

  /// 周期序列：长度即周期天数，每个元素是**一天的班次下标列表**
  /// （v0.11.3 起一天可叠多个班次，如 [白班, 值班]）。
  /// 空列表的那天 = 当天无班（一般只出现在「不用规则」又手写了空天的旧数据）。
  final List<List<int>> cycle;

  /// 班组数。
  final int teamCount;

  /// 班组名（长度与 teamCount 一致）。
  final List<String> teamNames;

  /// 我们是第几个班组。
  final int ourTeamIndex;

  /// 每个班组相对基准日的天数偏移（长度与 teamCount 一致）；
  /// 为空时回退到旧的「按 ourTeamIndex 错开」逻辑。
  final List<int> teamOffsets;

  /// 按天改班覆盖：`dayNumber(日期) → classes 下标`。
  ///
  /// 覆盖**整天**：那天原来是几个班次都被这一个替代（与其它班次查询同口径，
  /// 存的是下标，不是 classId —— 库里存 classId，由 `ActiveSchedule.toDomain()`
  /// 转换过来）。
  ///
  /// 只作用于**我们班组**：[teamShifts] 不查它。
  final Map<int, int> dayOverrides;

  /// 休息规则（轮转层之上的休息层）。
  final RestRule restRule;

  int get cycleLength => cycle.length;

  @override
  String get label => name;

  /// 我们班组的班次列表：先查按天覆盖，没有覆盖才按轮转算（含休息规则）。
  ///
  /// **覆盖只在 `shiftsOn` 这一层生效**，所以四个消费者 —— 日历格子、底栏
  /// 信息卡、闹钟重排（`AlarmService.reschedule`）、闹钟页「未来 30 天」 ——
  /// 全都自动跟着走。而 [teamShifts] 不查覆盖，「查看其他班组」看到的仍是纯
  /// 轮转，别人的班不会被我的调整改掉。
  ///
  /// 覆盖下标越界（班次被删、历史脏数据）时**回退到轮转**，不抛异常。
  /// 空白表（无周期）仍返回空列表，覆盖不改变这一点。
  @override
  List<ShiftClass> shiftsOn(DateTime date) {
    final ov = dayOverrides[dayNumber(date)];
    if (ov != null && ov >= 0 && ov < classes.length) return [classes[ov]];
    return teamShifts(ourTeamIndex, date);
  }

  /// 指定班组在某天的班次列表；空白表（无周期）返回空列表。
  ///
  /// 含休息规则：规则是**按班组**算的（各班组的值班日不同，跟随值班的休息日
  /// 也不同）。查某天「有没有班表在管」用 `ScheduleChain.hasScheduleOn`，
  /// 别用这个判空。
  List<ShiftClass> teamShifts(int teamIndex, DateTime date) {
    if (cycle.isEmpty) return const [];
    final base = (teamIndex >= 0 && teamIndex < teamOffsets.length)
        ? teamOffsets[teamIndex]
        : teamIndex - ourTeamIndex; // 回退：旧的按班组错开
    final offset = daysBetween(anchorDate, date) + base;
    var idx = offset % cycleLength;
    if (idx < 0) idx += cycleLength;
    final dayClasses = <ShiftClass>[];
    for (final classIndex in cycle[idx]) {
      if (classIndex >= 0 && classIndex < classes.length) {
        dayClasses.add(classes[classIndex]);
      }
    }
    // 值班优先：当天含值班标记，休息规则让路（值班日不能同时是休息日）。
    if (dayClasses.any((c) => c.isDuty && !c.isRest)) return dayClasses;
    // 休息规则命中：合成一个休息班次替代当天。
    if (_isRestByRule(teamIndex, date)) return [syntheticRestClass()];
    return dayClasses;
  }

  /// 这天按休息规则是不是休息日（不含「值班优先」那条，调用方自己判）。
  ///
  /// 用**纯轮转**查过去 7 天的值班日（不递归进休息规则、不查按天覆盖 ——
  /// 覆盖是「我们班组」的手工调整，不该反过来驱动规则）。
  bool _isRestByRule(int teamIndex, DateTime date) {
    final rule = restRule;
    if (rule.isNone || cycle.isEmpty) return false;
    switch (rule.mode) {
      case RestRuleMode.none:
        return false;
      case RestRuleMode.fixedWeekdays:
        return rule.fixedWeekdays.contains(date.weekday);
      case RestRuleMode.followDuty:
        if (rule.followDutyMap.isEmpty) return false;
        for (var i = 1; i <= 7; i++) {
          final past = date.subtract(Duration(days: i));
          final pastClasses = _rawTeamShifts(teamIndex, past);
          if (!pastClasses.any((c) => c.isDuty && !c.isRest)) continue;
          // 取离今天最近的那个值班日（i 从 1 往大走，第一个命中的就是最近的）。
          final mapped = rule.followDutyMap[past.weekday];
          return mapped == date.weekday;
        }
        return false;
    }
  }

  /// 纯轮转（不含休息规则、不含按天覆盖）：给休息规则查「过去的值班日」用，
  /// 避免递归。
  List<ShiftClass> _rawTeamShifts(int teamIndex, DateTime date) {
    if (cycle.isEmpty) return const [];
    final base = (teamIndex >= 0 && teamIndex < teamOffsets.length)
        ? teamOffsets[teamIndex]
        : teamIndex - ourTeamIndex;
    final offset = daysBetween(anchorDate, date) + base;
    var idx = offset % cycleLength;
    if (idx < 0) idx += cycleLength;
    final out = <ShiftClass>[];
    for (final classIndex in cycle[idx]) {
      if (classIndex >= 0 && classIndex < classes.length) {
        out.add(classes[classIndex]);
      }
    }
    return out;
  }
}

/// 两个班组在周期上的**同一天**被排到同一个工作班次。
///
/// 「撞班」是班组错位（[ShiftSchedule.teamOffsets]）与周期长度不匹配的症状。
/// 2026-09-21 的用户反馈就是它：把五班三倒从 5 天一轮改成 10 天一轮（每个班连排
/// 两天），而各班组仍按 1 天错开 —— 于是同一天有两个班组上同样的班。
class CrewClash {
  const CrewClash({
    required this.cycleDay,
    required this.teamA,
    required this.teamB,
    required this.shift,
  });

  /// 周期内第几天（**1 起**，与界面上的「第 N 天」同一口径）。
  final int cycleDay;

  /// 相撞的两个班组下标，[teamA] 恒小于 [teamB]。
  final int teamA;
  final int teamB;

  /// 撞在一起的那个班次。
  final ShiftClass shift;
}

/// 扫**一个完整周期**，列出「两个班组同一天上同一个班」的日子。
///
/// 只扫一个周期就够：班组错位是常数偏移，整张表以周期长度重复。
/// 判等用 `identical` —— 同一份 [ShiftSchedule] 里 `teamShift` 返回的是
/// `classes` 里同一个实例，用 `==` 会把内容相同的两个**不同班次定义**也认成撞班。
///
/// 休息班次不算撞（两个班组同时休是正常的），空白表（无周期 / 无班次定义）返回空表。
List<CrewClash> crewClashes(ShiftSchedule s) {
  if (s.cycle.isEmpty || s.classes.isEmpty) return const [];
  final out = <CrewClash>[];
  for (var k = 0; k < s.cycleLength; k++) {
    final date = s.anchorDate.add(Duration(days: k));
    // 每个班组当天的工作班次（去休息；休息规则已含在 teamShifts 里）。
    final working = <int, List<ShiftClass>>{};
    for (var t = 0; t < s.teamCount; t++) {
      final list =
          s.teamShifts(t, date).where((c) => !c.isRest).toList();
      if (list.isNotEmpty) working[t] = list;
    }
    final teams = working.keys.toList()..sort();
    for (var i = 0; i < teams.length; i++) {
      for (var j = i + 1; j < teams.length; j++) {
        // 两队 shares 同一个工作班次实例即撞班（判等用 identical，见下）。
        for (final a in working[teams[i]]!) {
          for (final b in working[teams[j]]!) {
            if (identical(a, b)) {
              out.add(CrewClash(
                cycleDay: k + 1,
                teamA: teams[i],
                teamB: teams[j],
                shift: a,
              ));
            }
          }
        }
      }
    }
  }
  return out;
}

/// 班组错位的**均分**规则：第 i 个班组落在周期的 `i × 周期长度 ÷ 班组数` 天处
/// （四舍五入）。
///
/// 这不是新发明的规则 —— **全部内置多班组模板的 `teamOffsets` 都是它算出来的**
/// （四班两倒 4/4 → 0/1/2/3、两班倒 14/2 → 0/7、DuPont 28/4 → 0/7/14/21、
/// 五班四倒 5/5 → 0/1/2/3/4……），由 `shift_templates_test.dart` 逐条守着。
/// 用它把「周期长度改了、各班组还按老间隔错开」造成的撞班一次抹平。
///
/// [keepIndex] / [keepOffset] 指定一个**保持不动**的班组（通常是「我们班组」）：
/// 均分是为了让别人不再和自己撞班，不该顺手把用户自己的周期起始日挪走。
///
/// 班组数多于周期天数时，整数错位必然有重复（抽屉原理）—— 那是配置本身的问题，
/// 不是这条规则能救的。
List<int> evenTeamOffsets(
  int cycleLength,
  int teamCount, {
  int keepIndex = 0,
  int keepOffset = 0,
}) {
  if (cycleLength <= 0 || teamCount <= 0) return const [];
  final evenly = <int>[
    for (var i = 0; i < teamCount; i++) (i * cycleLength / teamCount).round(),
  ];
  final shift = (keepIndex >= 0 && keepIndex < teamCount)
      ? keepOffset - evenly[keepIndex]
      : 0;
  return <int>[for (final e in evenly) e + shift];
}

/// 默认「四班两倒」配置：白班 → 上夜班 → 下夜班 → 大休（4 天周期），4 个班组错开。
///
/// 名称与班次名按**当前语言**生成：返回值有三条落库/入界面路径 ——
/// `seedIfEmpty` 首启播种、「我自己排」进编辑器、编辑器从空白表切回普通表。
/// 英文界面下这三条路都不该产出中文，所以文案不能硬编码。
ShiftSchedule defaultSchedule() {
  final anchor = DateTime.utc(2025, 1, 6); // 占位基准日（我们班组的第 1 天）
  return ShiftSchedule(
    name: L10n.t('四班两倒', '4-crew 2-shift'),
    anchorDate: anchor,
    teamCount: 4,
    teamNames: L10n.defaultTeamNames(4),
    ourTeamIndex: 0,
    teamOffsets: const [0, 1, 2, 3],
    cycle: const [
      [0],
      [1],
      [2],
      [3],
    ],
    classes: [
      ShiftClass(
        name: L10n.t('白班', 'Day shift'),
        abbr: L10n.t('白', 'D'),
        startMinute: 8 * 60 + 30,
        endMinute: 20 * 60 + 30,
        color: 0xFF4C8DFF,
        alarmEnabled: true,
        alarms: const [ShiftAlarm(minute: 7 * 60)],
      ),
      ShiftClass(
        name: L10n.t('上夜班', 'Night shift'),
        abbr: L10n.t('夜', 'N'),
        startMinute: 20 * 60 + 30,
        endMinute: 8 * 60 + 30,
        color: 0xFF7A5CFF,
        alarmEnabled: true,
        alarms: const [ShiftAlarm(minute: 19 * 60 + 30)],
      ),
      ShiftClass(
        name: L10n.t('下夜班', 'Off after nights'),
        abbr: L10n.t('休', 'O'),
        isRest: true,
        color: 0xFF9AA0B4,
      ),
      ShiftClass(
        name: L10n.t('大休', 'Long rest'),
        abbr: L10n.t('休', 'R'),
        isRest: true,
        color: 0xFF5A5F73,
      ),
    ],
  );
}
