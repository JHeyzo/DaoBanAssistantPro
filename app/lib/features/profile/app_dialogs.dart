import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/design_tokens.dart';
import '../../core/l10n.dart';
import '../../core/update_checker.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/glass_action_button.dart';
import '../../core/widgets/glass_dialog.dart';
import '../alarm/alarm_service.dart';

/// 统一风格的应用弹窗（版本更新 / 使用帮助），配色跟随主题主色。
void showAppInfoDialog(
  BuildContext context, {
  required String title,
  required String content,
}) {
  showGlassDialog<void>(
    context: context,
    builder: (dialogContext) => GlassDialog(
      title: title,
      showClose: true,
      // **不要再套一层 `ConstrainedBox(420) + SingleChildScrollView`**：那会造出
      // 第二个、更小的视口，正文仍然在它自己的底边被切断（而且切在按钮上方一点点，
      // 看着还是像有块板子）。`GlassDialog` 现在自己就是「整块面板高的滚动区 +
      // 浮在上面的动作行」，交给它就行。
      content: Text(
        content,
        style: AppTokens.rowSecondary.copyWith(height: 1.55),
      ),
      actions: [
        GlassActionButton(
          variant: GlassActionVariant.primary,
          onPressed: () => Navigator.pop(dialogContext),
          label: L10n.ok,
        ),
      ],
    ),
  );
}

const String _changelogZh = 'v0.11.4\n'
    '· 闹钟规则引擎：每条闹钟可单独设「值班次日时间」（值班次日改用此时刻，不设则跟平时一样）与「值班当天跳过」（值班当天这条不响）；在班次编辑器里点闹钟行的展开箭头设置\n'
    '· 删掉「闹钟」页的全局「值班次日闹钟」卡片（只换第一条的逻辑已由按条规则替代）\n'
    '· 班次结束时间选择器加「次日」开关：跨天的结束时间不再写死，可切回当天\n'
    '· 法定节假日在日历上改标绿「休」字（与调休「班」统一格式），不再标红\n'
    '\n'

    'v0.11.3\n'
    '· 排班模型重做：一天可叠多个班次（如白班+值班同日）；班次新增「工作/值班/休息」语义标记，改名调序不再弄断闹钟与休息规则\n'
    '· 新增「休息规则」：跟随值班（周几值→周几休，可选预设）/ 固定星期 / 不用规则；休息日由规则自动算出，不用手排28天\n'
    '· 模板系统拆除：内置模板库与「我的模板」删除，新建只留「空白模板」+「导入配置文件」，编辑页可「导出配置文件」\n'
    '· 日历视觉重做：扁平布局，日期收进圆角方章，值班显示为右上红折角（蓝章斜切+实心红三角）\n'
    '· 「值班次日闹钟」改按语义标记自动认值班，不用再手动选班种\n'
    '· 新增「黄历宜忌」开关（我的→设置，默认关）\n'
    '\n'

    'v0.11.2\n'
    '· 去掉每次打开 App 都会跳出来的「全屏通知」授权：ColorOS 适配版的闹钟走系统时钟响，本来就不需要这个权限，之前是每次冷启动白跳一次设置页\n'
    '· 新增「值班次日闹钟」：前一天是值班时，次日第一条班次闹钟自动改用单独设的时间（只换起床那条）。在「闹钟」页开关、设时间、认值班班种；排定与闹钟页显示是同一套算法，不会对不上\n'
    '· 从模板新建排班时，可以选「周期第 1 天是几号」了（默认今天，可拨到昨天/明天/任意天）—— 此前写死当天，值班相位对不上只能去编辑器里手动挪\n'
    '\n'

    'v0.11.1\n'
    '· 系统闹钟通道（ColorOS 适配）：App 不再自己响铃 —— 每天 00:30 按排班表把当天闹钟静默写入系统时钟，由系统时钟响铃；OPPO 手表通过「手机闹钟提醒」同步（免打扰+睡眠模式下仍跟随）\n'
    '· 新增 28 天排班模板「长白班，每 4 天值一次班，每周休一天」：白班 08:30–17:00、值班 17:00–次日 08:30，每 4 天一值、每周休一天（周六/周日）；28 天循环自动延展，配一年只需按季度衔接多套（周期起始日须锚定周一）\n'
    '· 待办提醒统一走普通通知（不再有全屏响铃样式）\n'
    '· 「检查更新」已指向本 fork 的 Releases\n'
    '\n'

;

const String _changelogEn = 'v0.11.4\n'
    '· Per-alarm duty rules: each alarm can have its own "post-duty time" (used on the day after a duty day; unset = same as usual) and "skip on duty day"; tap the expand arrow on an alarm row in the schedule editor\n'
    '· Removed the global "post-duty alarm" card from the Alarm tab (replaced by per-alarm rules)\n'
    '· Shift end-time picker gains a "next day" toggle: overnight end times are no longer sticky\n'
    '· Legal holidays show a green 休 marker on the calendar (same format as makeup-workday 班), no longer red\n'
    '\n'

    'v0.11.3\n'
    '· Schedule model rework: multiple shifts per day (e.g. day + duty on the same day); shifts now carry a Work/Duty/Rest semantic tag — renaming or reordering no longer breaks alarms and rest rules\n'
    '· New "Rest rule": follow-duty (which weekday to rest after a duty on a given weekday, with presets) / fixed weekdays / no rule; rest days are computed automatically, no more hand-laying 28 days\n'
    '· Template system removed: built-in library and "My templates" deleted; creating a schedule offers "Blank template" + "Import config file", the editor can "Export config file"\n'
    '· Calendar visual rework: flat layout, date inside a rounded-square chip, duty shown as a red folded corner (blue chip with diagonal cut + solid red triangle)\n'
    '· "Post-duty alarm" now auto-detects duty by semantic tag, no manual shift picking\n'
    '· New "Daily almanac" toggle (Profile → Settings, off by default)\n'
    '\n'

    'v0.11.2\n'
    '· Removed the full-screen notification permission prompt that popped up on every launch: the ColorOS build rings via the system clock and never needed that permission — it was a dead settings page every cold start\n'
    '· New \"Post-duty alarm\": when the previous day was a duty shift, the first shift alarm the next day automatically uses a separate time (only the wake-up one). Toggle it, set the time and pick the duty shift on the Alarm tab; scheduling and display share the same logic\n'
    '· Creating a schedule from a template now asks \"which date is day 1 of the cycle?\" (defaults to today, can be yesterday / tomorrow / any day) — it used to be hard-coded to today, forcing phase fixes through the editor\n'
    '\n'

    'v0.11.1\n'
    '· System alarm channel (ColorOS): the app no longer rings by itself — every day at 00:30 it silently writes that day\'s alarms into the system clock, which rings instead; OPPO watches sync via "phone alarm alerts" (follows even under DND + sleep mode)\n'
    '· New 28-day template "Day shift, on duty every 4 days, one rest day per week": day 08:30–17:00, duty 17:00–08:30 next day, duty every 4 days, one rest day (Sat/Sun) per week; the 28-day cycle extends indefinitely — chain quarterly sets to cover a year (cycle start must anchor on Monday)\n'
    '· Todo reminders are plain notifications now (no more full-screen ringing style)\n'
    '· "Check for updates" now points at this fork\'s Releases\n'
    '\n'

;
String get appChangelog => L10n.isEn ? _changelogEn : _changelogZh;

void showChangelogDialog(BuildContext context) {
  showAppInfoDialog(context, title: L10n.changelog, content: appChangelog);
}

/// 检查更新结果弹窗：展示正式版与测试版两个通道，各自可下载（仅当比当前新）。
void showUpdateDialog(BuildContext context, UpdateCheckResult result) {
  const current = appVersion;
  showGlassDialog<void>(
    context: context,
    builder: (dialogContext) => GlassDialog(
      title: L10n.checkUpdate,
      showClose: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${L10n.version}：v$current',
            style: AppTokens.labelStrong,
          ),
          Text(
            L10n.currentVersionHint,
            style: AppTokens.tinyLabel
                .copyWith(color: AppTokens.inkMuted(dialogContext)),
          ),
          _updateChannelRow(context, dialogContext, L10n.stableChannel,
              L10n.stableChannelHint, result.latestStable, current),
          _updateChannelRow(context, dialogContext, L10n.testChannel,
              L10n.testChannelHint, result.latestPrerelease, current),
        ],
      ),
      actions: const [],
    ),
  );
}

/// 检查更新失败的提示：说清「连不上 GitHub、国内要开代理」。
///
/// 走弹窗而不是 snack —— snack 只停 2 秒，这条提示却要用户读完再去做一件事。
void showUpdateFailedDialog(BuildContext context) {
  showAppInfoDialog(
    context,
    title: L10n.checkUpdate,
    content: L10n.updateCheckFailed,
  );
}

Widget _updateChannelRow(
    BuildContext outer, BuildContext ctx, String label, String hint,
    UpdateInfo? info, String current) {
  final muted = AppTokens.inkMuted(ctx);
  final downloadable = info == null
      ? null
      : (UpdateChecker.compareVersion(info.version, current) > 0 ? info : null);
  return Padding(
    padding: const EdgeInsets.only(top: AppTokens.spaceMd),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTokens.labelStrong),
              Text(
                info == null ? L10n.channelNone : 'v${info.version}',
                style: AppTokens.rowSecondary.copyWith(color: muted),
              ),
              Text(hint, style: AppTokens.tinyLabel.copyWith(color: muted)),
            ],
          ),
        ),
        if (downloadable != null)
          GlassActionButton(
            variant: GlassActionVariant.primary,
            onPressed: () {
              Navigator.pop(ctx);
              _downloadAndInstall(outer, downloadable);
            },
            label: L10n.download,
          )
        else
          Text(L10n.alreadyLatest,
              style: AppTokens.rowSecondary.copyWith(color: muted)),
      ],
    ),
  );
}

/// 帮助类弹窗的公共外壳：同一个 [GlassDialog]、同样的滚动上限与「知道了」。
///
/// 「开始使用」与「使用帮助」只有内容不同，壳子必须一模一样 —— 各写一套的话
/// 两个弹窗的圆角、滚动上限、按钮措辞会慢慢漂开。
void _showHelpDialog(
  BuildContext context, {
  required String title,
  required Widget content,
}) {
  showGlassDialog<void>(
    context: context,
    builder: (dialogContext) => GlassDialog(
      title: title,
      showClose: true,
      // **不要再套 `ConstrainedBox(maxHeight: …) + SingleChildScrollView`。**
      // 它造出**第二个更小的视口**：正文在那个高度就结束，面板底下空一截，
      // 用户读成「按钮没浮起来、底下压着一层蒙版」（2026-10-01 反馈）。
      // `GlassDialog` 自己的内容区就铺满面板、并负责滚动，动作行由它用
      // `Positioned` 浮在上面 —— 这里只要把 content 原样交给它。
      // （v0.10.0 从 `showAppInfoDialog` 里拆掉的就是这两层，这个调用点当时漏了。）
      content: content,
      actions: [
        GlassActionButton(
          variant: GlassActionVariant.primary,
          onPressed: () => Navigator.pop(dialogContext),
          label: L10n.ok,
        ),
      ],
    ),
  );
}

/// 首次启动弹的「开始使用」。
///
/// **不要退回成直接弹「使用帮助」**（2026-09-23 改的）：那份是九个条目、
/// 一千多字的说明书，当欢迎页用等于没写 —— 新用户第一眼要知道的是「现在该
/// 干什么」。完整说明仍在「我的 → 使用帮助」里，这条路径由最后一句话指出去。
void showGettingStartedDialog(BuildContext context) {
  final muted = AppTokens.inkMuted(context);
  _showHelpDialog(
    context,
    title: L10n.gettingStarted,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(L10n.gettingStartedLead,
            style: AppTokens.rowSecondary.copyWith(height: 1.45, color: muted)),
        const SizedBox(height: 16),
        _GuideEntry(
            icon: Icons.edit_calendar_outlined,
            title: L10n.gettingStartedSchedTitle,
            lines: [L10n.gettingStartedSchedBody],
            bulleted: false),
        const SizedBox(height: 16),
        _GuideEntry(
            icon: Icons.shield_outlined,
            title: L10n.gettingStartedPermTitle,
            lines: [L10n.gettingStartedPermBody],
            bulleted: false),
        const SizedBox(height: 16),
        _GuideEntry(
            icon: Icons.touch_app_outlined,
            title: L10n.gettingStartedOverrideTitle,
            lines: [L10n.gettingStartedOverrideBody],
            bulleted: false),
        const SizedBox(height: 20),
        const Divider(height: 1),
        const SizedBox(height: 12),
        Text(L10n.gettingStartedMore,
            style: AppTokens.rowSecondary.copyWith(height: 1.45, color: muted)),
      ],
    ),
  );
}

/// 「我的 → 桌面小组件」那一行的说明弹层。
///
/// 正文与《使用帮助》里的同一条目**共用一份文案**（`L10n.guideWidgetDesc`）——
/// 各写一份的话，改了这边忘了那边，就成了「说明书和 App 说的不一样」。
/// 弹窗标题已经把「是什么」说了，条目里不再顶一行标题（`title: null`）。
void showWidgetGuideDialog(BuildContext context) {
  _showHelpDialog(
    context,
    title: L10n.guideWidgetTitle,
    content: _GuideEntry(
      icon: Icons.widgets_outlined,
      title: null,
      lines: L10n.guideWidgetDesc,
    ),
  );
}

void showUsageGuideDialog(BuildContext context) {
  final items = <(IconData, String, List<String>)>[
    (Icons.calendar_month_outlined, L10n.guideCalTitle, L10n.guideCalDesc),
    (Icons.tune_outlined, L10n.guideSchedTitle, L10n.guideSchedDesc),
    (Icons.alarm_outlined, L10n.guideAlarmTitle, L10n.guideAlarmDesc),
    (Icons.event_note_outlined, L10n.guideTodoTitle, L10n.guideTodoDesc),
    (Icons.widgets_outlined, L10n.guideWidgetTitle, L10n.guideWidgetDesc),
    (Icons.palette_outlined, L10n.guideAppearanceTitle,
        L10n.guideAppearanceDesc),
    (Icons.aspect_ratio_outlined, L10n.guideLayoutTitle, L10n.guideLayoutDesc),
    (Icons.shield_outlined, L10n.guidePermTitle, L10n.guidePermDesc),
    (Icons.system_update_outlined, L10n.guideUpdateTitle,
        L10n.guideUpdateDesc),
  ];

  _showHelpDialog(
    context,
    title: L10n.usageGuide,
    content: Column(
      children: [
        for (final it in items) ...[
          _GuideEntry(icon: it.$1, title: it.$2, lines: it.$3),
          const SizedBox(height: 16),
        ],
      ],
    ),
  );
}

/// 帮助弹窗里的一条：图标 + 标题 + 正文行。
///
/// [lines] 多于一行时每行前面加一个小圆点（参考条目是多项并列，得能扫）；
/// 只有一行、且是引导语时把 [bulleted] 关掉 —— 单条正文顶个圆点像没写完的列表。
class _GuideEntry extends StatelessWidget {
  const _GuideEntry({
    required this.icon,
    required this.title,
    required this.lines,
    this.bulleted = true,
  });

  final IconData icon;

  /// 条目标题。**为空时整行标题不画**（连那 8dp 间距一起）—— 「我的 → 桌面小组件」
  /// 那个说明弹层只有一份并列的短句，弹窗标题已经说了是什么，条目再顶一行标题
  /// 就是同一句话说两遍。
  final String? title;
  final List<String> lines;
  final bool bulleted;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final muted = AppTokens.inkMuted(context);
    final body =
        AppTokens.rowSecondary.copyWith(height: 1.45, color: muted);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: 0.28),
                accent.withValues(alpha: 0.10),
              ],
            ),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: AppIcon(icon, size: AppTokens.iconMd, color: accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Text(title!, style: AppTokens.labelStrong),
                const SizedBox(height: AppTokens.padChipV),
              ],
              for (var i = 0; i < lines.length; i++) ...[
                if (i > 0) const SizedBox(height: AppTokens.spaceXs),
                if (!bulleted)
                  Text(lines[i], style: body)
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 圆点用固定 4dp（设计语言里「被改过的那天」也是这个尺寸），
                      // 不跟字号缩放 —— 小窗下缩到 1~2px 就等于没有。
                      // 上边距是把它压到首行文字中线上（spaceSm = 8），
                      // 7 那种值不上 4px 栅格，会打红 design_tokens_test。
                      Container(
                        width: 4,
                        height: 4,
                        margin: const EdgeInsets.only(top: AppTokens.spaceSm),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: muted.withValues(alpha: 0.75),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 走 Expanded 而不是给整段加「· 」前缀：英文条目会折行，
                      // 前缀写法的第二行会顶到最左边、看不出是同一条。
                      Expanded(child: Text(lines[i], style: body)),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 关闭更新弹窗后，弹出下载进度弹窗（内部完成下载并自动拉起系统安装器）。
void _downloadAndInstall(BuildContext context, UpdateInfo info) {
  showGlassDialog<void>(
    context: context,
    // 下载做到一半不许被点掉。
    barrierDismissible: false,
    builder: (_) => _DownloadProgressDialog(info: info),
  );
}

/// 下载进度玻璃弹窗：实时百分比；下载完自动关闭并拉起安装，失败则就地提示。
class _DownloadProgressDialog extends StatefulWidget {
  const _DownloadProgressDialog({required this.info});

  final UpdateInfo info;

  @override
  State<_DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  /// -1 = 不确定进度（转圈），0–100 = 百分比。
  int _percent = -1;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final file = await UpdateChecker.downloadApk(widget.info, onProgress: (p) {
      if (mounted) setState(() => _percent = p);
    });
    if (!mounted) return;
    if (file != null) {
      Navigator.pop(context);
      await AlarmService.installApk(file.path);
    } else {
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final muted = AppTokens.inkMuted(context);
    return GlassDialog(
      title: L10n.downloadingUpdate,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'v${widget.info.version}',
            style: AppTokens.labelSecondary,
          ),
          const SizedBox(height: 16),
          if (_failed)
            Text(L10n.downloadFailed,
                style: AppTokens.rowSecondary.copyWith(color: muted))
          else if (_percent >= 0) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTokens.radiusS),
              child: LinearProgressIndicator(
                value: _percent / 100,
                minHeight: 6,
                color: accent,
                backgroundColor: accent.withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(height: 8),
            Text('$_percent%',
                style: AppTokens.rowSecondary.copyWith(color: muted)),
          ] else ...[
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
            const SizedBox(height: AppTokens.gapIconTextLg),
            Text(L10n.downloadingUpdate,
                style: AppTokens.rowSecondary.copyWith(color: muted)),
          ],
        ],
      ),
      actions: [
        if (_failed)
          GlassActionButton(
            onPressed: () => Navigator.pop(context),
            label: L10n.close,
          ),
      ],
    );
  }
}
