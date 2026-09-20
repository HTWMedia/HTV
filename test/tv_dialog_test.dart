import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_example/common/widgets/tv_channel_select_dialog.dart';
import 'package:video_player_example/common/widgets/tv_text_edit_dialog.dart';

/// 和 main.dart 一致的 ScreenUtil 初始化。
/// 少了这一步，`.sp` 会在 build 里抛 LateInitializationError（_minTextAdapt 未初始化）。
Widget _wrapScreenUtil(Widget app) => ScreenUtilInit(
      designSize: const Size(1920, 1080),
      minTextAdapt: true,
      child: app,
    );

/// 弹窗宿主：用真实路由弹出，这样 Navigator.pop 的结果才断言得到
Widget _host({
  required String label,
  required Widget dialog,
}) {
  return MaterialApp(
    home: Builder(
      builder: (ctx) => Scaffold(
        body: TextButton(
          onPressed: () => showDialog<void>(context: ctx, builder: (_) => dialog),
          child: Text(label),
        ),
      ),
    ),
  );
}

Future<void> _pressKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

Future<void> _pressKeyTwiceFor(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
}

void main() {
  testWidgets('文本编辑弹窗：初始值回填、取消不落值', (tester) async {
    final saved = <String>[];
    final app = _host(
      label: 'open',
      dialog: TvTextEditDialog(
        title: '用户参数',
        hint: '输入参数',
        initialValue: 'old-value',
        onSave: saved.add,
      ),
    );

    await tester.pumpWidget(_wrapScreenUtil(app));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('用户参数'), findsOneWidget);
    expect(find.text('old-value'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);

    // 焦点环：输入框 → 取消。取消不该触发 onSave
    await _pressKey(tester, LogicalKeyboardKey.arrowDown);
    await _pressKey(tester, LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(saved, isEmpty);
    expect(find.byType(TvTextEditDialog), findsNothing);
  });

  testWidgets('文本编辑弹窗：走到保存并回填改动', (tester) async {
    final saved = <String>[];
    final app = _host(
      label: 'open',
      dialog: TvTextEditDialog(
        title: '自定义直播源',
        hint: '输入订阅链接',
        initialValue: '',
        onSave: saved.add,
      ),
    );

    await tester.pumpWidget(_wrapScreenUtil(app));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'http://example.com/tv.m3u');
    await tester.pumpAndSettle();

    // enterText 会把焦点交给 EditableText，mixin 随即判定为编辑态；
    // 此时方向键归输入框，必须先按返回键退出编辑才能继续走焦点环
    await _pressKey(tester, LogicalKeyboardKey.escape);

    // 输入框 → 取消 → 保存
    await _pressKey(tester, LogicalKeyboardKey.arrowDown);
    await _pressKey(tester, LogicalKeyboardKey.arrowDown);
    await _pressKey(tester, LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(saved, ['http://example.com/tv.m3u']);
    expect(find.byType(TvTextEditDialog), findsNothing);
  });

  testWidgets('编辑态优先吃掉返回键：第一次退出编辑，第二次才关闭弹窗', (tester) async {
    final app = _host(
      label: 'open',
      dialog: TvTextEditDialog(
        title: '用户参数',
        hint: '输入参数',
        initialValue: '',
        onSave: (_) {},
      ),
    );

    await tester.pumpWidget(_wrapScreenUtil(app));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 焦点默认在输入框上，按 OK 进入编辑态
    await _pressKey(tester, LogicalKeyboardKey.select);

    await _pressKey(tester, LogicalKeyboardKey.escape);
    expect(find.byType(TvTextEditDialog), findsOneWidget, reason: '编辑态下第一次返回键只退出编辑');

    await _pressKey(tester, LogicalKeyboardKey.escape);
    expect(find.byType(TvTextEditDialog), findsNothing, reason: '非编辑态下返回键关闭弹窗');
  });

  testWidgets('编辑态下方向键不跑出输入框也不关闭弹窗', (tester) async {
    final saved = <String>[];
    final app = _host(
      label: 'open',
      dialog: TvTextEditDialog(
        title: '用户参数',
        hint: '输入参数',
        initialValue: '',
        onSave: saved.add,
      ),
    );

    await tester.pumpWidget(_wrapScreenUtil(app));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await _pressKey(tester, LogicalKeyboardKey.select); // 进入编辑态
    await _pressKey(tester, LogicalKeyboardKey.arrowDown);
    await _pressKey(tester, LogicalKeyboardKey.arrowDown);

    expect(saved, isEmpty);
    expect(find.byType(TvTextEditDialog), findsOneWidget);
  });

  testWidgets('频道弹窗：勾选、全选与保存回传', (tester) async {
    Set<String>? result;
    const group = ['CCTV-1', 'CCTV-2', '浙江卫视', '湖南卫视'];
    await tester.pumpWidget(_wrapScreenUtil(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await ChannelSelectDialog.show(
                ctx,
                allChannels: group,
                selected: {'CCTV-1'},
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    )));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('CCTV-1'), findsOneWidget);
    expect(find.text('浙江卫视'), findsOneWidget);
    expect(find.text('已选 1'), findsOneWidget);

    // 全选
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 4'), findsOneWidget);

    // 取消一个：焦点默认在列表首行，点第三行即可（Tap 与 OK 键走同一套 _toggle）
    await tester.tap(find.text('浙江卫视'));
    await tester.pumpAndSettle();
    expect(find.text('已选 3'), findsOneWidget);

    await tester.tap(find.textContaining('保存'));
    await tester.pumpAndSettle();

    expect(result, {'CCTV-1', 'CCTV-2', '湖南卫视'});
  });

  testWidgets('频道弹窗：返回键关闭且不回传结果', (tester) async {
    Object? result;
    const group = ['CCTV-1'];
    await tester.pumpWidget(_wrapScreenUtil(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await ChannelSelectDialog.show(
                ctx,
                allChannels: group,
                selected: {'CCTV-1'},
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    )));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ChannelSelectDialog), findsOneWidget);

    await _pressKeyTwiceFor(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(ChannelSelectDialog), findsNothing);
    expect(result, isNull, reason: '返回键关闭视为取消，不应回传选中集合');
  });

  testWidgets('频道弹窗：搜索框过滤列表', (tester) async {
    const group = ['CCTV-1', '浙江卫视', '湖南卫视'];
    await tester.pumpWidget(_wrapScreenUtil(MaterialApp(
      home: Scaffold(
        body: ChannelSelectDialog(allChannels: group, selected: <String>{}),
      ),
    )));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '卫视');
    await tester.pumpAndSettle();

    expect(find.text('CCTV-1'), findsNothing);
    expect(find.text('浙江卫视'), findsOneWidget);
    expect(find.text('湖南卫视'), findsOneWidget);
  });
}
