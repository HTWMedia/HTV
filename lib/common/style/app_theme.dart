import 'package:flutter/material.dart';

/// 主题色与文本样式的统一出口。
///
/// 原来几乎每个 build 都重复写着 `Theme.of(context).colorScheme.onBackground`
/// 以及 `.withOpacity(0.8)` 之类——同一个语义的值散落在十几处文件里，
/// 改一个配色要点十几地方。这里把「前景/背景 + 常用透明度」「列表块填充 +
/// 反色文本」「半屏遮罩」这些成对出现的取值收进来。
class AppTheme {
  AppTheme._();

  // ---------- 取值 ----------

  /// 前景色（默认主题下是黑底上的白）
  static Color fg(BuildContext context) => Theme.of(context).colorScheme.onBackground;

  /// 背景色
  static Color bg(BuildContext context) => Theme.of(context).colorScheme.background;

  /// 带透明度的前景色
  static Color fgFaded(BuildContext context, double opacity) => fg(context).withOpacity(opacity);

  /// 带透明度的背景色
  static Color bgFaded(BuildContext context, double opacity) => bg(context).withOpacity(opacity);

  /// 错误色
  static Color error(BuildContext context) => Theme.of(context).colorScheme.error;

  // ---------- 列表块（选中高亮/反色文本） ----------

  /// 未选中时列表块的填充色。
  /// 写成 const 是为了避开每帧 `Colors.white.withOpacity(0.12)` 的重复求值。
  static const unselectedTileFill = Color(0x1FFFFFFF); // Colors.white.withOpacity(0.12)

  /// 列表块填充色：选中为前景色实心，未选中为半透明白
  static Color tileFill(BuildContext context, bool selected) =>
      selected ? fg(context) : unselectedTileFill;

  /// 列表块上的文本色，与 [tileFill] 反色
  static Color tileText(BuildContext context, bool selected) =>
      selected ? bg(context) : fg(context);

  /// 列表块上的次要文本色
  static Color tileTextFaded(BuildContext context, bool selected, double opacity) =>
      tileText(context, selected).withOpacity(opacity);

  // ---------- 常用透明度档位 ----------

  /// 主文本
  static const oPrimary = 1.0;

  /// 次级文本（节目单、副标题等）
  static const oSecondary = 0.8;

  /// 三级文本（下载进度、提示语）
  static const oTertiary = 0.6;

  /// 弱化文本（「已是最新」、引导语）
  static const oSubtle = 0.4;

  // ---------- 其它 ----------

  /// 半屏弹窗的遮罩底色（原来是 `Colors.black.withOpacity(0.5)` 抄了三遍）
  static const scrim = Color(0x80000000);

  /// 统一构造 TextStyle。
  ///
  /// 本 App 的主题会给默认文本样式带上装饰，所以每处 Text 都得显式写
  /// `decoration: TextDecoration.none`——集中在这里处理，省得漏一个就出现黄线。
  static TextStyle text(
    Color color,
    double fontSize, {
    FontWeight? weight,
    double? height,
  }) =>
      TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: weight,
        height: height,
        decoration: TextDecoration.none,
      );
}
