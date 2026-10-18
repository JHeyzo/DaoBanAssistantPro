import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_scan.dart';

// 液态组件已删除：保留普通玻璃效果，不允许为了旧测试重新恢复液态引擎。
const _removedPaths = <String>[
  'lib/core/glass/liquid_lens.dart',
  'lib/core/glass/liquid_lens_controller.dart',
  'lib/core/glass/liquid_lens_metrics.dart',
  'lib/core/widgets/liquid_track.dart',
  'lib/core/widgets/lens_warped_cell.dart',
  'lib/features/calendar/calendar_lens.dart',
  'lib/features/calendar/calendar_range_band.dart',
  'lib/features/calendar/lens_warp_scope.dart',
];

List<String> _liquidReferences(String source) {
  final code = blankNonCode(source);
  return <String>[
    for (final symbol in <String>[
      'LiquidLens',
      'LiquidTrack',
      'LensWarpedCell',
      'CalendarLens',
      'CalendarRangeBand',
      'LensWarpScope',
      'liquidGlassActive',
      'liquidGlassEnabled',
      'setLiquidGlass',
    ])
      if (RegExp('\\b$symbol\\b').hasMatch(code)) symbol,
  ];
}

void main() {
  test('液态引擎与专用组件文件不再存在', () {
    expect(
      _removedPaths.where((path) => File(path).existsSync()),
      isEmpty,
      reason: '液态组件应删除，不能通过恢复实现或空桩满足旧测试。',
    );
  });

  test('生产代码不再引用液态组件或档位', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty, reason: '必须实际扫描生产源码。');
    final offenders = <String>[
      for (final file in files)
        if (_liquidReferences(file.readAsStringSync()).isNotEmpty) file.path,
    ];
    expect(offenders, isEmpty);
  });

  test('删除守门能识别真实引用并忽略历史注释和文案', () {
    expect(
        _liquidReferences('final x = LiquidLens();'), <String>['LiquidLens']);
    expect(_liquidReferences('liquidGlassActive.value = true;'),
        <String>['liquidGlassActive']);
    expect(_liquidReferences('// LiquidLens\nconst label = "LiquidLens";'),
        isEmpty);
  });
}
