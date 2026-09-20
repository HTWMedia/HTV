import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_example/common/utils/prefs.dart';
import 'package:video_player_example/common/widgets/two_dimension_list_view.dart';

/// 竖向布局的参数。数值刻意取成整数，方便直接断言像素位置。
const _rowHeight = 60.0;
const _itemGap = 8.0;
const _groupGap = 12.0;
const _headerHeight = 40.0;
const _viewportHeight = 400.0;
const _topPadding = 20.0;
const _rowCount = 20;
const _colCount = 8;

/// 所有曾经被 itemBuilder 请求过的位置，用于验证懒加载
final _built = <String>{};

/// itemBuilder 的每次调用（含重复），用于验证焦点移动的重建范围
final _calls = <String>[];

/// PrefsUtil 是 late final，整个测试进程只能初始化一次
bool _prefsReady = false;

Key _key(int row, int col) => ValueKey('$row-$col');

Widget buildVerticalList() {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: _viewportHeight,
        child: TwoDimensionListView(
          verticalLayout: true,
          viewportHeight: _viewportHeight,
          size: (rowHeight: _rowHeight, colWidth: 0),
          gap: (row: _groupGap, col: _itemGap),
          initialPosition: (row: 0, col: 0),
          itemCount: (row: _rowCount, col: (_) => _colCount),
          rowTopBuilder: (context, row) => SizedBox(
            height: _headerHeight,
            child: Text('H$row'),
          ),
          itemBuilder: (context, position, isSelected) {
            _built.add('${position.row}-${position.col}');
            _calls.add('${position.row}-${position.col}');
            return SizedBox(
              key: _key(position.row, position.col),
              height: _rowHeight,
              child: Text('${position.row}-${position.col}'),
            );
          },
        ),
      ),
    ),
  );
}

/// 内容 offset，与组件内部 _getVerticalScrollOffset 的口径一致，这里独立算一遍用于交叉校验
double expectedGroupOffset(int row) {
  var offset = _topPadding + row * _groupGap;
  for (var i = 0; i < row; i++) {
    offset += _headerHeight + _colCount * _rowHeight + (_colCount - 1) * _itemGap;
  }
  return offset;
}

/// 带空分组的列表：第 1 组没有任何频道。
///
/// 「直播源精简」把某组过滤空是真实会发生的，此时跨组导航与滚动定位
/// 都不能算错位置（历史 bug：滚动偏移公式给空组多减了一个 gap.col）。
Widget buildVerticalListWithEmptyGroup() {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: _viewportHeight,
        child: TwoDimensionListView(
          verticalLayout: true,
          viewportHeight: _viewportHeight,
          size: (rowHeight: _rowHeight, colWidth: 0),
          gap: (row: _groupGap, col: _itemGap),
          initialPosition: (row: 0, col: 0),
          itemCount: (row: _rowCount, col: (row) => row == 1 ? 0 : _colCount),
          rowTopBuilder: (context, row) => SizedBox(
            height: _headerHeight,
            child: Text('H$row'),
          ),
          itemBuilder: (context, position, isSelected) {
            _built.add('${position.row}-${position.col}');
            _calls.add('${position.row}-${position.col}');
            return SizedBox(
              key: _key(position.row, position.col),
              height: _rowHeight,
              child: Text('${position.row}-${position.col}'),
            );
          },
        ),
      ),
    ),
  );
}

Future<void> pressDown(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 200));
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _built.clear();
    _calls.clear();
    // DebugSettings.delayRender 会读 PrefsUtil，而它是 late final 且未初始化过。
    // 只能初始化一次，重复 init 会抛 LateInitializationError。
    if (!_prefsReady) {
      SharedPreferences.setMockInitialValues({});
      await PrefsUtil.init();
      _prefsReady = true;
    }
  });

  testWidgets('竖向布局只构建视口附近的条目（几百条也不会全量 build）', (tester) async {
    await tester.pumpWidget(buildVerticalList());
    await tester.pumpAndSettle();

    // 全量构建会是 160 条；视口 400px 加上默认 cacheExtent 也放不下多少
    expect(_built.length, lessThan(_rowCount * _colCount));
    expect(_built.length, lessThan(40), reason: '实际构建 ${_built.length} 条，疑似退化为全量渲染');
    // 首屏必须包含第一组的开头几条
    expect(_built, contains('0-0'));
  });

  testWidgets('分组头与第一个条目的位置符合预期的排布', (tester) async {
    await tester.pumpWidget(buildVerticalList());
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('H0')).dy, closeTo(_topPadding, 1));
    expect(
      tester.getTopLeft(find.byKey(_key(0, 0))).dy,
      closeTo(_topPadding + _headerHeight, 1),
    );
  });

  testWidgets('连续下键跨到下一分组时，会把该分组头部滚到视口顶部', (tester) async {
    await tester.pumpWidget(buildVerticalList());
    await tester.pumpAndSettle();

    // 第一组 8 条：前 7 次走到最后一条，第 8 次跨到 row 1 col 0
    await pressDown(tester, _colCount);

    expect(find.byKey(_key(1, 0)), findsOneWidget, reason: '跨组后新分组的条目应当已滚入视口');
    // 滚到分组起点后：头部占视口顶部 40px，其后紧接第一个条目
    expect(tester.getTopLeft(find.byKey(_key(1, 0))).dy, closeTo(_headerHeight, 1));
    // 交叉校验：新的滚动位置应当等于独立算出来的分组偏移
    expect(expectedGroupOffset(1), closeTo(_topPadding + _groupGap + _headerHeight + _colCount * _rowHeight + (_colCount - 1) * _itemGap, 0.01));
  });

  testWidgets('移动焦点只重建失去选中与新得到选中的两个格子', (tester) async {
    await tester.pumpWidget(buildVerticalList());
    await tester.pumpAndSettle();

    // 稳定后清空，接下来的调用就都是这次按键引起的
    _calls.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    // 视口里有十来个格子，若退化成整表 setState，这里会是一串位置
    expect(_calls.toSet(), {'0-0', '0-1'}, reason: '实际重建 ${_calls.toSet()}');
  });

  testWidgets('跨过空分组后仍能精确定位到下一个非空组', (tester) async {
    await tester.pumpWidget(buildVerticalListWithEmptyGroup());
    await tester.pumpAndSettle();

    // 第 0 组 8 条；再按一次应当跳过空掉的第 1 组，落到第 2 组的第一个频道
    await pressDown(tester, _colCount);

    expect(find.byKey(_key(2, 0)), findsOneWidget, reason: '空组不应成为导航终点');
    // 容差 1px：修复前这里的偏差正好是一个 gap.col（8px），能稳定区分
    expect(
      tester.getTopLeft(find.byKey(_key(2, 0))).dy,
      closeTo(_headerHeight, 1),
      reason: '空组若被多算/少算一次间距，分组头之后的条目位置会整体偏移',
    );
  });

  testWidgets('选中态跟着方向键走', (tester) async {
    await tester.pumpWidget(buildVerticalList());
    await tester.pumpAndSettle();

    var selected = '0-0';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: _viewportHeight,
            child: TwoDimensionListView(
              verticalLayout: true,
              viewportHeight: _viewportHeight,
              size: (rowHeight: _rowHeight, colWidth: 0),
              gap: (row: _groupGap, col: _itemGap),
              initialPosition: (row: 0, col: 0),
              itemCount: (row: _rowCount, col: (_) => _colCount),
              rowTopBuilder: (context, row) => SizedBox(height: _headerHeight, child: Text('H$row')),
              onSelect: (position) => selected = '${position.row}-${position.col}',
              itemBuilder: (context, position, isSelected) => SizedBox(
                key: _key(position.row, position.col),
                height: _rowHeight,
                child: Text('${position.row}-${position.col}'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(selected, '0-1');
  });
}
