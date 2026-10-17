import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/design_tokens.dart';
import '../../core/l10n.dart';
import '../../core/widgets/centered_content.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_pressable.dart';
import '../../data/app_repository.dart';
import '../../domain/schedule_template.dart';
import '../../domain/shift_rotation.dart';

/// 选择页的返回值。
///
/// v0.11.3 起模板系统已拆除：只有「空白新建」与「导入配置文件」两种。
/// 返回 null 表示用户按返回键放弃，调用方应直接 return。
class ShiftTemplateChoice {
  const ShiftTemplateChoice.blank() : imported = null;
  const ShiftTemplateChoice.imported(ScheduleTemplate this.imported);

  /// 导入的配置文件；空白新建时为 null。
  final ScheduleTemplate? imported;

  /// 是否为空白新建。
  bool get isBlank => imported == null;
}

/// 「新建排班」：空白模板 + 导入配置文件。
///
/// v0.11.3 把内置模板库与「我的模板」整体删除（用户拍板：模板系统只留
/// 空白新建 + 配置文件导入/导出）。锚点日期不在这里选 —— 去编辑页
/// 「我这组从这个周期开始」拨（v0.11.2 那个创建流弹窗已删）。
///
/// 返回 null 表示用户按返回键放弃，调用方应直接 return。
class ShiftTemplatePickerScreen extends ConsumerWidget {
  const ShiftTemplatePickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.pickShiftPattern)),
      body: CenteredContent(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              L10n.pickShiftPatternHint,
              style: AppTokens.rowSecondary
                  .copyWith(color: AppTokens.inkMuted(context)),
            ),
            const SizedBox(height: AppTokens.spaceLg),
            _optionCard(
              context,
              icon: Icons.add_box_outlined,
              title: L10n.blankTemplate,
              subtitle: L10n.blankTemplateHint,
              onTap: () => Navigator.of(context).pop(
                const ShiftTemplateChoice.blank(),
              ),
            ),
            const SizedBox(height: AppTokens.spaceMd),
            _optionCard(
              context,
              icon: Icons.file_upload_outlined,
              title: L10n.importConfig,
              subtitle: L10n.importConfigHint,
              onTap: () async {
                final template = await _pickAndParseConfig(context, ref);
                if (template == null || !context.mounted) return;
                Navigator.of(context).pop(
                  ShiftTemplateChoice.imported(template),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GlassPressable(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radiusM),
        child: Container(
          padding: const EdgeInsets.all(AppTokens.spaceLg),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppTokens.radiusM),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(icon, size: 32, color: cs.primary),
              const SizedBox(width: AppTokens.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTokens.titleStrong),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: AppTokens.rowSecondary.copyWith(
                        color: AppTokens.inkMuted(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: AppTokens.inkMuted(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 选文件并解析配置文件。解析失败弹提示，返回 null。
  ///
  /// TODO(v0.11.3): 文件选择器接入（file_picker）。现在先占位。
  Future<ScheduleTemplate?> _pickAndParseConfig(
    BuildContext context,
    WidgetRef ref,
  ) async {
    if (!context.mounted) return null;
    await showGlassDialog(
      context: context,
      builder: (context) => GlassDialog(
        title: L10n.importConfig,
        content: Text(L10n.importNotImplemented),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(L10n.ok),
          ),
        ],
      ),
    );
    return null;
  }
}

/// 从选择页建排班：空白模板 / 导入配置文件二选一。
///
/// v0.11.3：锚点日期不在创建流选 —— 建完去编辑页拨
/// 「我这组从这个周期开始」（编辑器里已有）。
/// 返回新建方案的 id；按返回键放弃返回 null。
Future<int?> createScheduleFromTemplatePicker(
  BuildContext context,
  WidgetRef ref, {
  required bool makeCurrent,
}) async {
  final choice = await Navigator.of(context).push<ShiftTemplateChoice>(
    MaterialPageRoute(builder: (_) => const ShiftTemplatePickerScreen()),
  );
  // 按返回键放弃：不建方案
  if (choice == null || !context.mounted) return null;

  final imported = choice.imported;
  final d = defaultSchedule();
  return ref.read(appRepositoryProvider).saveSchedule(
        name: imported?.name ?? L10n.newSchedule,
        anchorDate: dateOnly(DateTime.now()),
        classes: imported?.classes ?? d.classes,
        cycle: imported?.cycle ?? d.cycle,
        restRule: imported?.restRule ?? const RestRule(),
        makeCurrent: makeCurrent,
        teamCount: imported?.teamCount ?? d.teamCount,
        teamNames: L10n.defaultTeamNames(imported?.teamCount ?? d.teamCount),
        ourTeamIndex: 0,
        teamOffsets: imported?.teamOffsets ?? d.teamOffsets,
      );
}
