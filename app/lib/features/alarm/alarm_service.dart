import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n.dart';
import '../../data/app_repository.dart';
import '../../domain/recurring_todo.dart';
import '../../domain/shift_rotation.dart';
import '../../state/app_settings.dart';
import '../widget/widget_service.dart';

/// 没设时间的待办，提醒以当天这个整点为基准（「全天」那类待办没有更准的时点）。
const int allDayReminderHour = 9;

/// 「从文件中选择铃声」失败。[code] 是原生侧给的错误码。
///
/// 要单独成类而不是返回 null：**文件太大**和**读不出来**得在界面上说成两句话，
/// 否则用户只会对着同一个文件反复重试。
class RingtonePickException implements Exception {
  RingtonePickException(this.code);

  final String code;

  bool get isTooLarge => code == 'RINGTONE_TOO_LARGE';
}

/// 正在响铃的闹钟要显示的内容：主标题 +（可选的）说明。
///
/// 「某天要排一条班次联动闹钟」的一条决策结果。
///
/// [offset] 是距起点日的天数偏移（`0` = 起点当天）。原生 id 由 `offset` 与
/// [alarmIndex] 一起算出（`序号 × 天数窗口 + 天数偏移`，见 [planShiftAlarms] 与
/// `AlarmService._shiftDaysHorizon`）—— 这个映射必须保持不变，否则每次重排都会把
/// 闹钟换个号，用户设过的响铃记录会跟着错位。
class ShiftAlarmPlan {
  const ShiftAlarmPlan({
    required this.offset,
    required this.shift,
    required this.alarm,
    required this.alarmIndex,
    required this.fireAt,
  });

  final int offset;
  final ShiftClass shift;

  /// 要响的那一条闹钟。
  final ShiftAlarm alarm;

  /// 这个闹钟在 `shift.alarms` 里的下标 —— 原生 id 的「序号」就是它。
  final int alarmIndex;

  final DateTime fireAt;
}

/// 某天某个班次的**某一条**闹钟的响铃时刻。
///
/// 钟点取 [alarm] 的钟面值；[alarmFallsOnPreviousDay] 为真时整体前移一天 ——
/// 规则是「**不晚于上班时刻的最近一次该钟点**」，所以 00:00 上班、23:00 响铃排的是
/// 前一天 23:00（排在班次当天就已经是班后 15 小时了）。
///
/// 日期用 `DateTime(y, m, d - 1)` 重建而不是 `subtract(Duration(days: 1))`：
/// 后者减的是绝对 24 小时，碰上夏令时切换会把钟点也挪掉一小时。
DateTime shiftAlarmFireAt(DateTime date, ShiftClass shift, ShiftAlarm alarm) {
  final clock = alarm.minute;
  return alarmFallsOnPreviousDay(shift, alarm)
      ? DateTime(date.year, date.month, date.day - 1)
          .add(Duration(minutes: clock))
      : DateTime(date.year, date.month, date.day)
          .add(Duration(minutes: clock));
}

/// 值班次日规则命中时当天实际要响的闹钟列表：只把第一条换成规则时刻，
/// 其余各条原样。未命中或 [rule] 为 null 时返回 [shift.alarms] 本体。
///
/// 抽出来是因为排定（`planShiftAlarms`）与闹钟页显示各算一次，两处必须同解，
/// 否则页上写的时间和实际响的时间对不上。
/// 当天生效的闹钟列表（按条闹钟的日类型规则调整）。
///
/// 规则（v0.11.4 起按条配，替代全局「值班次日闹钟」）：
/// - 值班当天：`skipOnDutyDay` 为 true 的闹钟跳过（当天含值班标记的班次）。
/// - 值班次日：`postDutyMinute` 非空的闹钟改用该时间（前一天含值班标记）。
/// - 其余：按原时间。
List<ShiftAlarm> effectiveDayAlarms(
  ShiftSource source,
  DateTime date,
  ShiftClass shift,
) {
  if (shift.alarms.isEmpty) return shift.alarms;

  final dayShifts = source.shiftsOn(DateTime(date.year, date.month, date.day));
  final isDutyDay = dayShifts.any((c) => c.isDuty && !c.isRest);

  // 值班次日：前一天含值班标记（复用 isPostDutyDay 的判据，不依赖全局规则）。
  final prev = source.shiftsOn(DateTime(date.year, date.month, date.day - 1));
  final isPostDutyDay = prev.any((c) => c.isDuty && !c.isRest);

  final result = <ShiftAlarm>[];
  for (final alarm in shift.alarms) {
    // 值班当天跳过
    if (isDutyDay && alarm.skipOnDutyDay) continue;
    // 值班次日换时间
    if (isPostDutyDay && alarm.postDutyMinute != null) {
      result.add(ShiftAlarm(
        minute: alarm.postDutyMinute!,
        label: alarm.label,
        postDutyMinute: alarm.postDutyMinute,
        skipOnDutyDay: alarm.skipOnDutyDay,
      ));
    } else {
      result.add(alarm);
    }
  }
  return result;
}

/// 决定「未来 [days] 天里哪些天要排班次联动闹钟、各排在几点」。
///
/// 从 [AlarmService.reschedule] 的排定循环里抽出来的**纯**决策：不碰通知插件、
/// 不读 `DateTime.now()`（当前时刻由 [from] 传入）。抽出来是因为那段逻辑原本
/// 和 `scheduleNativeAlarm` 缠在一起，而项目没有可运行的原生插件目标，于是
/// 三条规格（spec §11：覆盖成休班不排 / 覆盖成别的班按那个班的时间排 /
/// 与「按天关闹钟」正交）**从来没有被任何测试盖到**。
///
/// 跳过条件与从前的循环逐条一致：
/// 那天没有班次 / 是休班 / 班次没开总开关 / 班次一条闹钟都没配 /
/// 那天被「按天关闹钟」显式关过（[overrides] 里值为 `false`）/
/// 算出来的触发时刻不晚于 [from]（今天这个点已经过去了）。
///
/// [postDutyRule] 命中时（前一天是值班班种），当天第一条闹钟改用规则时刻，
/// 见 [effectiveDayAlarms] —— 只换第一条，原生 id 的「序号」不变，不换号。
///
/// **一个班次挂了几个闹钟就出几条 plan**，各自算各自的触发时刻与落点。
///
/// 触发时刻由 [shiftAlarmFireAt] 算（可能是**前一天**晚上），但 `offset` 与原生
/// id 始终按**班次那一天**算 —— id 是 `序号 × 天数窗口 + 天数偏移`，跟着触发时刻走
/// 的话，每个午夜班的闹钟都会换号。**「序号」是闹钟在 `shift.alarms` 里的下标**：
/// 用户在编辑页里调整顺序会让闹钟换号（可接受 —— 编辑之后必然重排、`cancelAll`
/// 先跑），但**重排本身绝不能重新编号**，否则每次打开 App 都换一批。
///
/// 入参是 [ShiftSource] 而不是 `ShiftSchedule`：**「按天衔接」之后，某天归哪套方案
/// 是那条链自己知道的事**，而这里本来就逐天问一次「今天什么班」—— 换一个源进来
/// 即可，函数体一个字不用改（除了这一处 `source.shiftOn`）。原生的 id 算式因此
/// 天生安全：**同一天只归一套方案**，`offset` 相同的两天不可能同时存在。
///
/// 一条容易被误报成 bug 的语义：跨时段边界时，落在**前一天**的那条闹钟会排到
/// 「前一天所属那套方案」的日子里 —— 那是**对的**，闹钟属于那个班次、不属于
/// 触发日。落哪天由 [shiftAlarmFireAt] 里**班次自己的日期**决定，与「那天归哪套」
/// 无关，别把它「修」成按触发日解析。
List<ShiftAlarmPlan> planShiftAlarms(
  ShiftSource source, {
  required DateTime from,
  required int days,
  Map<int, bool> overrides = const {},
}) {
  final today = dateOnly(from);
  final plans = <ShiftAlarmPlan>[];
  for (var d = 0; d < days; d++) {
    final date = today.add(Duration(days: d));
    final shifts = source.shiftsOn(date);
    // 按天覆盖：该天被单独关闭则跳过
    if (overrides[dayNumber(date)] == false) continue;

    // 一天可叠多个班次（v0.11.3）：每个班次的闹钟都要排。
    // v0.11.4：按条闹钟的日类型规则（替代全局「值班次日闹钟」）。
    final isDutyDay = shifts.any((c) => c.isDuty && !c.isRest);
    final prev = source.shiftsOn(date.subtract(const Duration(days: 1)));
    final isPostDutyDay = prev.any((c) => c.isDuty && !c.isRest);
    for (final t in shifts) {
      if (t.isRest || !t.alarmEnabled || t.alarms.isEmpty) {
        continue;
      }

      for (var i = 0; i < t.alarms.length; i++) {
        var alarm = t.alarms[i];
        // 值班当天跳过
        if (isDutyDay && alarm.skipOnDutyDay) continue;
        // 值班次日换时间
        if (isPostDutyDay && alarm.postDutyMinute != null) {
          alarm = ShiftAlarm(
            minute: alarm.postDutyMinute!,
            label: alarm.label,
            postDutyMinute: alarm.postDutyMinute,
            skipOnDutyDay: alarm.skipOnDutyDay,
          );
        }
        final fireAt = shiftAlarmFireAt(date, t, alarm);
        if (!fireAt.isAfter(from)) continue;
        plans.add(ShiftAlarmPlan(
          offset: d,
          shift: t,
          alarm: alarm,
          alarmIndex: i,
          fireAt: fireAt,
        ));
      }
    }
  }
  return plans;
}

/// 一条重复待办提醒的排定计划。
///
/// 队首（[fireAt]）现在排给原生；[repeatTimes] 是它后面还跟着的几次 —— 一起递
/// 过去，由原生在响完之后**弹队首、续队尾**，所以 App 长期不开也不漏。
class RecurringAlarmPlan {
  const RecurringAlarmPlan({
    required this.seriesId,
    required this.fireAt,
    required this.repeatTimes,
  });

  final int seriesId;
  final DateTime fireAt;

  /// [fireAt] 之后的下几次触发时刻（升序，不含 [fireAt]）。
  final List<DateTime> repeatTimes;
}

/// 纯函数：把系列列表算成要排的提醒。**不碰通知通道、不读时钟**。
///
/// 抽出来是为了能直接单测 —— 它错了不会报错，只会**在错的时候提醒**或者
/// **根本不提醒**，两样都靠界面看不出来（与 [planShiftAlarms] 同一条理由）。
///
/// 关键的一条：时刻从 [from] **之后**算起（`upcomingFireTimes` 的语义），不是从
/// 「当前那一次的日期」算起 —— 下午打开 App 时今天那次早过去了，照那一次排等于
/// 永远排不上。
///
/// 规则**不递给原生**：那一串绝对时刻就是全部，原生只做「弹队首、续队尾」。
/// 把月份 / 星期掩码 / 提前提醒的偏移照抄一份到 Kotlin 会变成第二份实现，而原生
/// 在这个仓库里没有可跑的测试目标 —— 两份迟早对不上，症状还是「某天没响」。
List<RecurringAlarmPlan> planRecurringReminders(
  List<RecurringTodo> series, {
  required DateTime from,
  int days = 180,
  int cap = 200,
}) {
  final out = <RecurringAlarmPlan>[];
  for (final s in series) {
    final id = s.id;
    // 提醒的号是 `_recurringBaseId + 系列 id`，没有 id 就没有稳定的号可排。
    if (id == null) continue;
    final times = upcomingFireTimes(
      s,
      from: from,
      // 「没设时间按几点提醒」是提醒层的策略，领域层不知道也不该知道。
      clockMinute: s.timeMinute ?? allDayReminderHour * 60,
      days: days,
      cap: cap,
    );
    if (times.isEmpty) continue;
    out.add(RecurringAlarmPlan(
      seriesId: id,
      fireAt: times.first,
      repeatTimes: times.skip(1).toList(),
    ));
  }
  return out;
}

/// 某天这个班次**还有没有没响过的**闹钟 —— 闹钟页「未来 30 天」那一行留不留。
///
/// **不能只看第一条**（那是只有一个闹钟时的口径）：首条已响、后面还有时
/// （早餐闹钟 06:30 响过了、午休 12:30 还等着），整行会被「响过的自动隐藏」
/// 一起藏掉 —— 那一行的「按天关闹钟」开关也跟着没了，用户当天再也没法关掉
/// 剩下的那一条。（独立审查抓出来的；`shift_alarm_decision_test.dart` 里
/// 「首条已响、后面还有」与「零点班：起床在前一晚已响」两条是它的护栏。）
bool hasPendingShiftAlarm(ShiftClass shift, DateTime date, DateTime now) =>
    shift.alarms.any((a) => shiftAlarmFireAt(date, shift, a).isAfter(now));

/// 一次性自定义闹钟该落在哪天：`hour:minute` 的**下一次出现**。
///
/// **为什么不能就是「今天」**：新建闹钟时时间默认此刻、日期默认今天，两个默认叠在
/// 一起，触发时刻在按下「添加」之前就已经过去了。而一次性闹钟的排定判据是
/// `fire.isAfter(now)`（见 `reschedule`）—— 过去的那一刻直接**不排**，
/// `deleteExpiredOnceAlarms` 还会在下一次进闹钟页时把它删掉。用户看到的是「加了一
/// 条、它自己没了」。`repeatType` 的默认值从「每天」改成「一次性」之后（v0.9.6），
/// 这不是边角情况而是常态，所以日期一律由这里算。
///
/// 规则：今天这个钟点还没到就是今天，已经过了就顺延一天；[chosen] 是更晚的日期时
/// 听用户的（手选了日子的人比默认值清楚）。界面那行「日期」显示的就是它的结果，
/// 所以卡上写的永远等于真正会响的那天。
///
/// 返回的是**日期**（`dateOnly`，与库里 `onceDate` 那一列同形），不是带钟点的时刻：
/// 钟点单独存在 `hour`/`minute` 两列，排定时由 `reschedule` 现拼
/// （`DateTime(od.year, od.month, od.day, a.hour, a.minute)`）。
///
/// `alarm_screen_test.dart` 里「新建后直接添加」那条用例盯住落点，
/// `once_alarm_date_test.dart` 在纯函数上把边界逐条钉死。
DateTime nextOnceDate({
  required DateTime now,
  required DateTime chosen,
  required int hour,
  required int minute,
}) {
  final chosenAt = DateTime(chosen.year, chosen.month, chosen.day, hour, minute);
  final today = DateTime(now.year, now.month, now.day, hour, minute);
  // `day + 1` 交给 `DateTime` 归一化（月末、年末都跨得过去），不要自己加 24 小时
  // —— `Duration` 遇上夏令时会偏一小时。
  final occurrence = today.isAfter(now)
      ? today
      : DateTime(now.year, now.month, now.day + 1, hour, minute);
  return dateOnly(chosenAt.isAfter(occurrence) ? chosenAt : occurrence);
}

/// 联动班次闹钟 + 自定义闹钟服务。
///
/// 排班闹钟排定未来 `_shiftDaysHorizon` 天（60）；每次打开 App 自动续排，
/// 跟着排班走、不过期。自定义闹钟支持：一次性 / 每天 / 每周（可选星期几）。
class AlarmService {
  AlarmService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// 班次闹钟排定的天数窗口（`reschedule` 的 [days] 缺省值）。
  ///
  /// **它就是原生 id 里的那个 60**：id = `序号 × 本值 + 天数偏移`。所以它与
  /// `maxAlarmsPerShift`（6，见 `domain/shift_rotation.dart`）是一对：
  /// 6 × 60 = 360 ≤ 400，而 Kotlin 侧 `cancelAllNativeAlarms` 扫的是 0..400
  /// （`MainActivity.kt:550`）。**改这个值必须同时改那个上限与 Kotlin 的扫描范围。**
  static const int _shiftDaysHorizon = 60;

  /// 测试用只读出口：id 算式是「上限 6」的由来，得能在纯测试里断言。
  static int get shiftDaysHorizonForTesting => _shiftDaysHorizon;

  /// 待办提醒的原生 id 基址。
  ///
  /// **四段互不重叠**，原生侧按区间扫着取消（见 `MainActivity` 的几个 cancel 分支）：
  /// 班次 `0..400`、自定义闹钟 `10000..11000`、待办行 `20000..`（留到 39999）、
  /// 重复待办系列 `40000..41999`。
  ///
  /// 为什么把重复待办单列一段：它的号按**系列 id** 算，而待办行的号按**行 id** 算，
  /// 而行 id 只增不减（`AUTOINCREMENT` 永不复用）—— 两者共用一个自增序列的话，
  /// 行号迟早会把提醒的号挤出去，越界之后提醒排得下去、谁也取消不掉。
  static const _eventBaseId = 20000;

  /// 重复待办提醒的原生 id 基址（id = `40000 + 系列 id`）。
  static const _recurringBaseId = 40000;

  static Future<void> init() async {
    // ⚠️ **不要再把 `tz.initializeTimeZones()` 加回来**（2026-10-10 删）。
    //
    // 它从前是为了「以后可能要用 `flutter_local_notifications` 的时区型 API」而留着
    // 的，但全仓从来没有一处 `zonedSchedule` / `TZDateTime` —— 排定全部走原生
    // （epoch 毫秒）或 `scheduleNativeAlarm`。代价却是实打实的：`latest_all` 是全量
    // IANA 库，实测 **21ms**（宿主；真机更慢），而且它跑在 `main()` 里、**首帧之前**。
    //
    // 将来真要上时区型 API，除了把这一句加回来，还必须补 `tz.setLocalLocation`
    // —— 否则 `tz.local` 是 UTC，会整体差一个时区偏移（见 `scheduleTodoReminder` 的说明）。
    // 原生闹钟触发时（App 已在后台），MainActivity 通过此回调通知我们弹出响铃界面；
    // 待办提醒被点开时同样由它通知我们切到「待办」页。
    _settingsChannel.setMethodCallHandler(handleNativeCall);

    // 通知通道的名字要在系统「通知」设置里显示，得跟着界面语言走；而通道只能
    // 在原生侧建。启动时把当前语言的名字递过去（同名重复创建 = 更新，不是报错）。
    await ensureTodoChannel(L10n.todoReminderChannel);
    // 通知小图标必须是 drawable：插件用 getIdentifier(name, "drawable", pkg) 查它，
    // 而且是按**白剪影**渲染的 —— 塞一个满幅彩色的启动器图标进去只会得到一坨白块。
    // 原生 AlarmRingService 早就在用 drawable/ic_notification，这里与它对齐。
    const android = AndroidInitializationSettings('ic_notification');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );
    // 注意：这里不能清缓存——清了之后 cancelAll 就找不到已排定的 AlarmManager 闹钟，
    // 导致每次启动都累积新闹钟、最终撞上「500 条并发闹钟」上限。
    // 若缓存损坏，reschedule 里 cancelAll 的 try-catch 会兜底清一次。

    // 冷启动：检查是否由待办提醒的通知拉起
    final todoId = await getPendingTodoId();
    if (todoId != null) {
      await logInfo('Dart init: 冷启动读取 pendingTodoId=$todoId');
      openTodoRequested.value = true;
    }
  }

  /// 处理原生推过来的方法调用 —— 「原生说了什么、Dart 要做什么」的全套契约。
  ///
  /// **抽成静态方法是为了能单测**：`init()` 里那一堆插件初始化在 widget 测试里跑不起来，
  /// 而这里面每一条都是会静默出错的东西（漏一条就是「原生做了、界面没跟上」）。
  @visibleForTesting
  static Future<void> handleNativeCall(MethodCall call) async {
    if (call.method == 'onTodoTapped') {
      await logInfo('Dart 收到 onTodoTapped');
      openTodoRequested.value = true;
    }
    // 小组件某一天被点击（热启动路径）。它不参与上面那条 if/else ——
    // 单独一个 `if` 是有意的，别顺手并进去。
    if (call.method == 'onWidgetDayTapped') {
      WidgetService.onNativeDayTapped(call.arguments as int);
    }
  }

  static void _onNotificationResponse(NotificationResponse response) {
    // 通知点击只处理待办（openTodoRequested），闹钟已走系统时钟，不再经 App 响铃。
  }

  /// 请求通知 + 精确闹钟权限（须在 runApp 后调用，否则 Activity 未就绪会静默失败）。
  ///
  /// 注意：**不再请求全屏通知权限** —— ColorOS 适配版删掉了 App 自己的响铃链路，
  /// 闹钟走系统时钟响，不需要 `USE_FULL_SCREEN_INTENT`。此前每次冷启动都会调
  /// 全屏通知的权限请求，而 manifest 里根本没声明该权限，系统设置页的开关置灰、
  /// 永远授权不了，于是每次打开 App 都白跳一次设置页（v0.11.1 用户反馈）。
  static Future<void> requestPermissions() async {
    await requestNotificationsPermission();
    await requestExactAlarmsPermission();
  }

  static Future<void> requestNotificationsPermission() async {
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
  }

  static Future<void> requestExactAlarmsPermission() async {
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestExactAlarmsPermission();
  }

  /// 返回 (通知权限, 精确闹钟权限) 是否开启。
  static Future<(bool, bool)> checkPermissions() async {
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    bool notif = false, exact = false;
    try {
      notif = await androidImpl?.areNotificationsEnabled() ?? false;
    } catch (_) {}
    try {
      exact = await androidImpl?.canScheduleExactNotifications() ?? false;
    } catch (_) {}
    return (notif, exact);
  }

  static const _settingsChannel = MethodChannel(
      'com.daoban.shiftassistantpro/settings');

  /// 打开本应用的系统设置详情页（国产 ROM 上通常含「自启动」开关）。
  static Future<void> openAppSettings() async {
    try {
      await _settingsChannel.invokeMethod('openAppSettings');
    } catch (_) {}
  }

  /// 打开「显示悬浮窗」权限设置（弹响铃界面的 AOSP 层豁免靠它）。
  static Future<void> openOverlaySettings() async {
    try {
      await _settingsChannel.invokeMethod('openOverlaySettings');
    } catch (_) {}
  }

  /// 本应用是否已获得「显示悬浮窗」权限（`SYSTEM_ALERT_WINDOW`）。
  static Future<bool> checkOverlayPermission() async {
    try {
      return await _settingsChannel.invokeMethod('checkOverlayPermission') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// 这台机器上有没有小米的 App 权限页（非小米机型没有）。
  ///
  /// 那里装着一项**小米私有**的权限「后台弹出界面」，与上面的「显示悬浮窗」是
  /// 两回事：不开它，MIUI 会静默拒绝从后台拉起 Activity，闹钟只响、不弹界面。
  /// 这项权限读不到状态（没有公开 API），所以界面上只做「去查看」。
  static Future<bool> checkMiuiPermissionPage() async {
    try {
      return await _settingsChannel.invokeMethod('checkMiuiPermissionPage') ==
          true;
    } catch (_) {
      return false;
    }
  }

  /// 打开小米的 App 权限页；打不开返回 false，由调用方落回系统「应用信息」。
  static Future<bool> openMiuiPermissionPage() async {
    try {
      return await _settingsChannel.invokeMethod('openMiuiPermissionPage') ==
          true;
    } catch (_) {
      return false;
    }
  }

  /// 本应用是否已被忽略电池优化（后台闹钟可靠运行的关键）。
  static Future<bool> checkBatteryOptimization() async {
    try {
      return await _settingsChannel.invokeMethod('checkBatteryOptimization') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// 取消全部原生闹钟。
  static Future<void> cancelAllNativeAlarms() async {
    try {
      await _settingsChannel.invokeMethod('cancelAllNativeAlarms');
    } catch (_) {}
  }

  /// 按 id 取消全部通知闹钟（清理历史累积，避免撞上「500 条并发闹钟」上限）。
  static Future<void> cancelAllNotificationAlarms() async {
    try {
      await _settingsChannel.invokeMethod('cancelAllNotificationAlarms');
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // 系统闹钟通道（ColorOS 适配）：App 不再自己响铃，算好的闹钟静默写入系统时钟，
  // 手表通过「手机闹钟提醒」同步。每天 00:30 由原生 housekeeping 建当天那批。
  // ---------------------------------------------------------------------------

  /// 直接建一个系统闹钟（一次性 = 下一次到这个点；传 [days] 则为每周重复）。
  ///
  /// [days] 取 1..7（周一..周日），对应系统时钟「自定义」重复日。
  static Future<bool> createSystemAlarm(
    int hour,
    int minute,
    String message, {
    List<int>? days,
  }) async {
    try {
      // 去重：系统闹钟建了删不掉（ACTION_SET_ALARM 无删除 API），
      // 重复排定会叠加。用 SharedPreferences 记录已建的，同一天相同时分+文案只建一次。
      // （用户 2026-10-18 报：每次保存都多推一个闹钟进去）
      if (days == null) {
        final prefs = await SharedPreferences.getInstance();
        final now = DateTime.now();
        final key = 'sys_alarm_${now.year}-${now.month}-${now.day}_${hour}_${minute}_$message';
        if (prefs.getBool(key) == true) {
          return true; // 已建过，跳过
        }
        final ok = await _settingsChannel.invokeMethod<bool>('createSystemAlarm', {
          'hour': hour,
          'minute': minute,
          'message': message,
        });
        if (ok == true) {
          await prefs.setBool(key, true);
        }
        return ok ?? false;
      }
      final ok = await _settingsChannel.invokeMethod<bool>('createSystemAlarm', {
        'hour': hour,
        'minute': minute,
        'message': message,
        'days': days,
      });
      return ok ?? false;
    } catch (e) {
      await appendLog('createSystemAlarm 失败: $e');
      return false;
    }
  }

  /// 把未来 [days] 天的闹钟表推给原生 housekeeping。
  ///
  /// [daysJson] 形如 `[{"dayOffset":1,"alarms":[{"h":7,"m":30,"msg":"白班"}]}, …]`，
  /// dayOffset 以今天为 0（只推明天起）。原生每天 00:30 建当天那批系统闹钟。
  static Future<void> scheduleSystemAlarmHousekeeping(String daysJson) async {
    try {
      await _settingsChannel.invokeMethod(
          'scheduleSystemAlarmHousekeeping', {'daysJson': daysJson});
    } catch (e) {
      await appendLog('scheduleSystemAlarmHousekeeping 失败: $e');
    }
  }

  static Future<void> cancelSystemAlarmHousekeeping() async {
    try {
      await _settingsChannel.invokeMethod('cancelSystemAlarmHousekeeping');
    } catch (_) {}
  }

  /// 算出未来 [days] 天每天要写入系统时钟的闹钟表（班次闹钟 + 自定义闹钟）。
  ///
  /// 纯函数（可单测）：输入排班链与自定义闹钟，输出按天分组的 (时, 分, 文案)。
  /// 班次闹钟的触发时刻走 [shiftAlarmFireAt]（含「前一天」落点），按**触发日**分组；
  /// 自定义闹钟按重复类型判断每天响不响。一律只算明天起（dayOffset ≥ 1），
  /// 今天剩下的由调用方直接 [createSystemAlarm]（"下一次"就是今天）。
  static List<Map<String, dynamic>> planSystemAlarmDays(
    ShiftSource source,
    List<CustomAlarm> customAlarms, {
    required DateTime from,
    int days = 30,
    Map<int, bool> overrides = const {},
  }) {
    final today = dateOnly(from);
    final byDay = <int, List<Map<String, dynamic>>>{};

    void add(DateTime fireAt, String msg) {
      final dayOffset = dateOnly(fireAt).difference(today).inDays;
      if (dayOffset < 1 || dayOffset > days) return;
      byDay.putIfAbsent(dayOffset, () => []).add({
        'h': fireAt.hour,
        'm': fireAt.minute,
        'msg': msg,
      });
    }

    // 班次闹钟：planShiftAlarms 已算好触发时刻（含前一天落点）并滤掉已过的。
    // 注意 days+1：planShiftAlarms 的 days 含今天（offset 0），而这里只收明天起，
    // 多算一天才能凑满 days 天。
    for (final p in planShiftAlarms(source,
        from: from, days: days + 1, overrides: overrides)) {
      add(p.fireAt, L10n.shiftAlarmTitle(p.shift.name, p.alarm.label));
    }

    // 自定义闹钟：每天判断响不响。
    for (var d = 1; d <= days; d++) {
      final date = today.add(Duration(days: d));
      for (final a in customAlarms) {
        if (!a.enabled) continue;
        final fires = switch (a.repeatType) {
          0 => a.onceDate != null && dateOnly(a.onceDate!) == date,
          1 => true,
          _ => (a.weekdays & (1 << (date.weekday - 1))) != 0,
        };
        if (fires) {
          add(DateTime(date.year, date.month, date.day, a.hour, a.minute),
              '自定义闹钟');
        }
      }
    }

    // 待办提醒（开了「按闹钟响」的）：已并入系统闹钟？不 —— 待办提醒一律走普通通知。
    // App 不再自己响铃，「按闹钟响」降级为高优先级通知（见 rescheduleEventReminders）。

    return [
      for (final e in byDay.entries)
        {'dayOffset': e.key, 'alarms': e.value},
    ];
  }

  /// 查询设备物理内存（字节），用于低端机玻璃模糊降级；失败返回 -1。
  static Future<int> getTotalRamBytes() async {
    try {
      final v = await _settingsChannel.invokeMethod<int>('getTotalRamBytes');
      return v ?? -1;
    } catch (_) {
      return -1;
    }
  }

  /// 申请忽略电池优化（白名单），提高后台闹钟可靠性。
  static Future<void> requestIgnoreBatteryOptimizations() async {
    try {
      await _settingsChannel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {}
  }

  /// 清空 flutter_local_notifications 的「已排定通知」缓存。
  ///
  /// 该缓存是插件用 Gson 序列化到 SharedPreferences 的；一旦旧版本写入的数据
  /// 与当前反序列化逻辑不兼容，`cancel`/`cancelAll` 会抛
  /// `Missing type parameter`，导致所有重排都在第一步崩掉、闹钟永远排不进去。
  static Future<void> clearNotificationCache() async {
    try {
      await _settingsChannel.invokeMethod('clearNotificationCache');
    } catch (_) {}
  }

  /// 追加一条错误/崩溃日志到原生日志文件（可在「我的 → 查看日志」里查看）。
  static Future<void> appendLog(String msg) async {
    try {
      await _settingsChannel.invokeMethod('appendLog', {'msg': msg});
    } catch (_) {}
  }

  /// 追加一条普通信息日志（仅写入 Android Logcat，不落盘、应用内不可见）。
  static Future<void> logInfo(String msg) async {
    try {
      await _settingsChannel.invokeMethod('logInfo', {'msg': msg});
    } catch (_) {}
  }

  /// 读取原生日志文件内容。
  static Future<String> readLog() async {
    try {
      return await _settingsChannel.invokeMethod('readLog') ?? '';
    } catch (_) {
      return '';
    }
  }

  /// 清空原生日志文件。
  static Future<void> clearLog() async {
    try {
      await _settingsChannel.invokeMethod('clearLog');
    } catch (_) {}
  }

  /// 用系统浏览器打开 [url]（用于「检查更新」跳转下载页）。
  static Future<void> openUrl(String url) async {
    try {
      await _settingsChannel.invokeMethod('openUrl', {'url': url});
    } catch (_) {}
  }

  /// 用系统安装器打开本地 [path] 指向的 APK（走 FileProvider，见 MainActivity.kt）。
  static Future<void> installApk(String path) async {
    try {
      await _settingsChannel.invokeMethod('installApk', {'path': path});
    } catch (_) {}
  }

  /// 立即建一个 1 分钟后的测试系统闹钟，用于排查系统闹钟链路是否通。
  ///
  /// App 不再自己响铃：这里直接调系统时钟建一次性闹钟（"下一次到这个点"）。
  static Future<void> testAlarm() async {
    await logInfo('testAlarm: 开始建测试系统闹钟');
    final fire = DateTime.now().add(const Duration(minutes: 1));
    final ok = await createSystemAlarm(fire.hour, fire.minute, '测试闹钟');
    await logInfo('testAlarm: ${ok ? "成功" : "失败"}，约 ${fire.toIso8601String()} 触发');
  }

  /// 当前已排定的通知数量（排查用，失败返回 -1）。
  static Future<int> pendingNotificationCount() async {
    try {
      final list = await _plugin.pendingNotificationRequests();
      return list.length;
    } catch (_) {
      return -1;
    }
  }

  /// 列出系统里可用的铃声（标题 + URI）。
  static Future<List<({String title, String uri})>> listRingtones() async {
    try {
      final raw = await _settingsChannel.invokeMethod('listRingtones') as List?;
      return (raw ?? [])
          .map((e) => (
                title: (e as Map)['title'] as String? ?? '铃声',
                uri: e['uri'] as String? ?? '',
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 读取当前音量（alarm / notification / music），用于排查无声问题。
  static Future<Map<String, int>> getVolumeLevels() async {
    try {
      final raw = await _settingsChannel.invokeMethod('getVolumeLevels') as Map?;
      return (raw ?? const {}).map((k, v) => MapEntry(k.toString(), v as int));
    } catch (_) {
      return const {};
    }
  }

  /// 试听铃声：[uri] 为空则播放内置铃声。
  static Future<void> playRingtone(String? uri) async {
    try {
      await _settingsChannel.invokeMethod('playRingtone', {'uri': uri ?? ''});
    } catch (_) {}
  }

  /// 停止试听。
  static Future<void> stopRingtone() async {
    try {
      await _settingsChannel.invokeMethod('stopRingtone');
    } catch (_) {}
  }

  /// 「仅震动」——响铃时**不发声**，只有震动。
  ///
  /// 它和铃声 URI 存在**同一个** SharedPreferences 键（`ringtoneUri`）里，因为整条
  /// 链路本来就是一路的字符串：prefs → `AlarmScheduler` 的 Intent extra →
  /// `AlarmReceiver` → `AlarmRingService` → `AlarmSound`。另加一个布尔开关要同时改
  /// 这五处、还得改 `AlarmStore` 的开机重排记录，不值当。
  ///
  /// 它不可能与真实音源撞上：系统铃声是 `content://`、自选是 `file://`、内置**根本不存**
  /// 这个键（见 `profile_screen.dart` 写入的四个分支）。
  ///
  /// ⚠️ 与 Kotlin 侧的 `AlarmSound.VIBRATE_ONLY` **必须逐字一致**。两边各持一份常量
  /// 而不是互相 import（Dart 与 Kotlin 之间没有共享常量的通道），所以由
  /// `test/ringtone_vibrate_only_test.dart` 扫两边源码比对，改单边会当场变红。
  static const String vibrateOnlyRingtone = 'vibrateOnly';

  /// 让用户从系统文件选择器挑一个音频当铃声。
  ///
  /// 原生侧会把选中的文件**复制进应用私有目录**再返回 `file://` 路径 —— 不直接
  /// 用选择器给的 `content://`，那种授权不持久，重启或清理后就失效，而闹钟到点
  /// 读不到文件时用户是听不见错误的。
  ///
  /// 返回 `(显示名, URI)`；用户取消返回 null；失败抛 [RingtonePickException]。
  static Future<({String name, String uri})?> pickRingtoneFile() async {
    try {
      final raw =
          await _settingsChannel.invokeMethod('pickRingtoneFile') as Map?;
      if (raw == null) return null;
      final uri = raw['uri'] as String? ?? '';
      if (uri.isEmpty) return null;
      return (name: raw['name'] as String? ?? '', uri: uri);
    } on PlatformException catch (e) {
      throw RingtonePickException(e.code);
    } catch (e) {
      throw RingtonePickException('PICK_RINGTONE_FAILED');
    }
  }

  /// 删掉复制进私有目录的自选铃声文件（换回内置/系统铃声时用，不留垃圾）。
  static Future<void> clearRingtoneFile() async {
    try {
      await _settingsChannel.invokeMethod('clearRingtoneFile');
    } catch (_) {}
  }

  /// 让原生侧确保「待办提醒」通知通道存在，并（重新）设置它的显示名。
  ///
  /// 通道名要在系统「通知」设置里显示，所以必须跟着界面语言走。通道只能在原生侧
  /// 创建（通知由 `TodoReminderReceiver` 在后台发出），但语言只有 Dart 侧知道 ——
  /// 于是启动时由这里把当前语言的名字递过去。同名通道重复创建是更新而不是报错，
  /// 所以每次启动调一次就能跟着语言切换走。
  static Future<void> ensureTodoChannel(String name) async {
    try {
      await _settingsChannel
          .invokeMethod('ensureTodoChannel', {'name': name});
    } catch (_) {}
  }

  /// 排一条待办提醒（**普通通知**，不是全屏响铃闹钟）。
  ///
  /// **为什么不走 `flutter_local_notifications` 的 `zonedSchedule`**：它的排定
  /// API 只收 `TZDateTime`，而时区库的「本地时区」从来没设过（`init` 里只有
  /// `initializeTimeZones()`，依赖里也没有 `flutter_timezone`），`tz.local` 是
  /// UTC —— 照那样排，提醒会整体差一个时区偏移，而且不报错、只是时候不对。
  /// 原生这条走 epoch 毫秒，根本不碰时区。
  static Future<void> scheduleTodoReminder(
    int id,
    DateTime fireAt, {
    required String title,
    required String body,
    List<DateTime> repeatTimes = const [],
  }) async {
    try {
      await _settingsChannel.invokeMethod('scheduleTodoReminder', {
        'id': id,
        'millis': fireAt.millisecondsSinceEpoch,
        'title': title,
        'body': body,
        // 后续几次的绝对时刻（升序）。**规则不递过去** —— 原生只做「弹队首、
        // 续队尾」，规则判断全在 Dart 侧（那边有测试）。空数组 = 一次性提醒。
        'repeatTimes': [
          for (final t in repeatTimes) t.millisecondsSinceEpoch,
        ],
      });
    } catch (e) {
      await appendLog('scheduleTodoReminder 失败: $e');
    }
  }

  /// 取消全部待办提醒（按 id 区间扫，见 `_eventBaseId`）。
  static Future<void> cancelAllTodoReminders() async {
    try {
      await _settingsChannel.invokeMethod('cancelAllTodoReminders');
    } catch (_) {}
  }

  /// 用户点了待办提醒的通知 → 置位，壳子读到后切到「待办」页。
  ///
  /// 与 [ringingAlarm] 同一套机制：冷启动由 `init` 读原生侧的 pending 值置位，
  /// 热启动由原生侧反向 `onTodoTapped` 置位。
  static final ValueNotifier<bool> openTodoRequested = ValueNotifier<bool>(false);

  /// 读取由通知拉起时带着的待办 id（一次性）。
  static Future<int?> getPendingTodoId() async {
    try {
      final id = await _settingsChannel.invokeMethod('getPendingTodoId');
      return id is int ? id : null;
    } catch (_) {
      return null;
    }
  }

  /// 待办提醒的触发时刻；这条待办不需要提醒时返回 null。
  ///
  /// 基准时间：待办设了时间就按那个时间，没设时间按当天 [allDayReminderHour]:00
  /// —— 界面上允许只设提醒不设时间，没有基准就排不出提醒。
  /// `advanceRemindMinutes` 为 0 表示「准时」（事件当时提醒）。
  ///
  /// 抽成顶层纯函数是为了能直接单测时间推算：它错了不会报错，只会**在错的时候
  /// 提醒**，那是靠界面看不出来的。
  static DateTime? eventReminderTime(ScheduleEvent e) {
    final advance = e.advanceRemindMinutes;
    if (advance == null || e.isCompleted) return null;
    final base = e.timeMinute ?? allDayReminderHour * 60;
    // e.date 是 `dateOnly(...)` 存下的（UTC 日期），只取它的年月日再按本地时区
    // 重建 —— 直接用会带着 UTC 标志，交给原生算 epoch 毫秒时会差一个时区。
    final d = e.date;
    return DateTime(d.year, d.month, d.day)
        .add(Duration(minutes: base - advance));
  }

  /// 待办提醒通知的正文：日期 + 时间。
  ///
  /// 写**完整日期**而不是「今天 / 明天」：提前一天的那档提醒是在前一天响的，
  /// 写「今天」就错了。
  static String eventReminderBody(ScheduleEvent e) {
    final d = e.date;
    final date = L10n.monthDayWeekday(DateTime(d.year, d.month, d.day));
    final t = e.timeMinute;
    return t == null ? '$date · ${L10n.allDay}' : '$date · ${formatClock(t)}';
  }

  /// 一次把全部闹钟重排：先读齐库里的排班 / 自定义闹钟 / 按天覆盖 / 待办，
  /// 再交给 [reschedule]。
  ///
  /// 调用点原先各自读库再分别传进来（六处），加待办之后每处都还要多读一次 ——
  /// 与其让每个调用点抄一遍，不如在这里读齐。漏传一个参数不会报错，只会让
  /// 那类提醒静默不生效，所以这个「读齐」的动作只该有一份。
  static Future<void> rescheduleAll(AppRepository repo) async {
    // 读的是**整条链**：未来 60 天里可能跨时段边界，边界之后那几天的班属于别的
    // 方案 —— 只按当前方案排会排到错的班表上，直到冷启动才自愈。
    final schedules = await repo.getActiveSchedules();
    if (schedules == null) return;
    await reschedule(
      schedules.chain,
      await repo.listCustomAlarms(),
      overrides: await repo.listShiftAlarmOverrides(),
      events: await repo.listEvents(),
    );
    // 重复待办的提醒走独立号段，与上面那条链路互不影响（`reschedule` 里的
    // 待办那一段会跳过带 `seriesId` 的行）。
    await rescheduleRecurringReminders(await repo.listRecurringTodos());
  }

  /// 清除并按 [source] + [customAlarms] + [events] + [overrides] 重排所有闹钟。
  ///
  /// [overrides] 为按天覆盖（dayNumber → enabled）；值为 false 的日期跳过班次闹钟。
  /// [events] 是要排提醒的待办（`advanceRemindMinutes` 为 null 的跳过）。
  ///
  /// [source] 是 [ShiftSource] 而不是 `ShiftSchedule`，理由见 [planShiftAlarms]。
  static Future<void> reschedule(
    ShiftSource source,
    List<CustomAlarm> customAlarms, {
    int days = _shiftDaysHorizon,
    Map<int, bool> overrides = const {},
    List<ScheduleEvent> events = const [],
  }) async {
    // id 算式是 `序号 × _shiftDaysHorizon + 天数偏移`：`days` 一旦超过天数窗口，
    // 「某天的第 2 个闹钟」就会撞上「更晚那天的第 1 个闹钟」。今天两个调用点都走
    // 缺省值，所以这里只是把那条隐含约束写成断言（debug 生效）。
    assert(days <= _shiftDaysHorizon,
        'days（$days）不得超过天数窗口 $_shiftDaysHorizon —— 原生 id 会撞号');
    await logInfo(
        'reschedule: 开始，排班=${source.label}，自定义闹钟=${customAlarms.length} 个');
    final Stopwatch sw = Stopwatch()..start();
    // 先清掉可能已损坏的排定缓存，再 cancelAll（否则会抛 Missing type parameter）
    try {
      await _plugin.cancelAll();
    } catch (e) {
      await appendLog('reschedule: cancelAll 异常，清缓存重试: $e');
      await clearNotificationCache();
      try {
        await _plugin.cancelAll();
      } catch (e2) {
        await appendLog('reschedule: cancelAll 二次仍异常: $e2');
      }
    }
    // 按 id 兜底取消所有通知闹钟 + 原生闹钟 + 待办提醒，清理历史累积（避免 500 上限）
    await cancelAllNotificationAlarms();
    await cancelAllNativeAlarms();
    await cancelAllTodoReminders();

    // 1)+2) 班次联动闹钟 + 自定义闹钟：不再由 App 自己响铃，改走系统时钟。
    //
    // 「哪些天要排、各排几点」由 [planSystemAlarmDays] 这个纯函数决定（可单测）；
    // 这里只负责把决策推给原生 housekeeping（每天 00:30 建当天那批系统闹钟）。
    // 今天还没过的那几条，直接调系统闹钟（"下一次到这个点"就是今天）。
    final now = DateTime.now();
    final daysPlan = planSystemAlarmDays(source, customAlarms,
        from: now, days: 30, overrides: overrides);
    try {
      final json = jsonEncode(daysPlan);
      await scheduleSystemAlarmHousekeeping(json);
    } catch (e) {
      await appendLog('reschedule: 系统闹钟 housekeeping 排定失败: $e');
    }
    // 今天剩下的：直接建（此刻"下一次"就是今天）。
    final today = dateOnly(now);
    for (final p in planShiftAlarms(
        source, from: now, days: 1, overrides: overrides)) {
      if (dateOnly(p.fireAt) != today) continue;
      try {
        await createSystemAlarm(p.fireAt.hour, p.fireAt.minute,
            L10n.shiftAlarmTitle(p.shift.name, p.alarm.label));
      } catch (e) {
        await appendLog('reschedule: 今天的系统闹钟创建失败: $e');
      }
    }

    // 3) 待办提醒：普通通知，不进闹钟那套。
    //    App 不再自己响铃，「按闹钟响」降级为普通通知（每条待办只有一个日期、
    //    没有重复，所以一次排完就是全部）。
    await rescheduleEventReminders(events);
    // 一条汇总。
    await logInfo('reschedule: 完成 —— 系统闹钟表 ${daysPlan.length} 天、'
        '待办事件 ${events.length} 条，耗时 ${sw.elapsedMilliseconds}ms');
  }

  /// 只重排待办提醒（待办增删改之后调用）。
  ///
  /// 待办页的增删改**不**走 [rescheduleAll]：那会把上千条班次闹钟全部取消再
  /// 重排一遍，而勾一个复选框其实只需要改这一条待办的通知。
  ///
  /// App 不再自己响铃：待办提醒一律走普通通知（`alarmEnabled` 的「按闹钟响」
  /// 已降级，不再全屏 + 循环铃声）。
  static Future<void> rescheduleEventReminders(
      List<ScheduleEvent> events) async {
    await cancelAllTodoReminders();
    final now = DateTime.now();
    for (final e in events) {
      // **重复待办的「某一次」不在这里排**：它的提醒由系列那一条负责
      // （`rescheduleRecurringReminders`）。两处都排的话同一次会响两声。
      if (e.seriesId != null) continue;
      final fireAt = eventReminderTime(e);
      if (fireAt == null || !fireAt.isAfter(now)) continue;
      try {
        await scheduleTodoReminder(
          _eventBaseId + e.id,
          fireAt,
          title: e.title,
          body: eventReminderBody(e),
        );
      } catch (err) {
        await appendLog('rescheduleEventReminders: 排定失败: $err');
      }
    }
  }

  /// 重排全部重复待办的提醒（与 [rescheduleEventReminders] 分工，见那里的说明）。
  ///
  /// 每次都把整条时刻表**重新算一遍**再排：`cancelTodoReminders` 已经把这一段
  /// 清空了，所以这里排的就是全部 —— 停了、删了的系列自然不会再排上。
  ///
  /// App 不再自己响铃：`alarmEnabled` 的「按闹钟响」已降级为普通通知。
  static Future<void> rescheduleRecurringReminders(
      List<RecurringTodo> series) async {
    final plans = planRecurringReminders(series, from: DateTime.now());
    for (final p in plans) {
      final s = series.firstWhere((x) => x.id == p.seriesId);
      final id = _recurringBaseId + p.seriesId;
      try {
        await scheduleTodoReminder(
          id,
          p.fireAt,
          title: s.title,
          // 正文写**规则**不写日期：同一条提醒会跨很多次，写死日期第二次就是错的。
          body: s.ruleWithTime,
          repeatTimes: p.repeatTimes,
        );
      } catch (e) {
        await appendLog('rescheduleRecurringReminders: 排定失败: $e');
      }
    }
  }


  
  /// 下一次匹配 [weekdays] 位掩码（1<<(周一=0)…）中任意一天的 [hour]:[minute]。

}
