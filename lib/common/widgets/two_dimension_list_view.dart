import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player_example/common/widgets/delay_renderer.dart';

import '../enums/debug_setting.dart';
import 'easy_keyboard_listener.dart';

class TwoDimensionListView extends StatefulWidget {
  const TwoDimensionListView({
    super.key,
    this.initialPosition = const (row: 0, col: 0),
    required this.size,
    this.scrollOffset = const (row: 0, col: 0),
    this.gap = const (row: 0, col: 0),
    this.rowTopBuilder,
    this.headerHeightBuilder,
    required this.itemCount,
    required this.itemBuilder,
    this.onSelect,
    this.onLongSelect,
    this.verticalLayout = false,
    this.viewportHeight,

  });

  /// 初始位置
  final ({int row, int col}) initialPosition;

  // 尺寸
  final ({double rowHeight, double colWidth}) size;

  /// 滚动偏移
  final ({double row, double col}) scrollOffset;

  /// 间隔
  final ({double row, double col}) gap;

  /// 行顶部
  final Widget Function(BuildContext context, int row)? rowTopBuilder;

  /// 每行顶部高度（竖向布局），默认 40
  final double Function(int row)? headerHeightBuilder;

  /// 元素数量
  final ({int row, int Function(int row) col}) itemCount;

  /// 元素
  final Widget Function(BuildContext context, ({int row, int col}) position, bool isSelected) itemBuilder;

  /// 选中事件
  final void Function(({int row, int col}) position)? onSelect;

  /// 持续长选中事件
  final void Function(({int row, int col}) position)? onLongSelect;

  /// 竖向排列
  final bool verticalLayout;

  /// 竖向布局时每行的高度限制（等于父容器视口高度）
  final double? viewportHeight;

  @override
  State<TwoDimensionListView> createState() => _TwoDimensionListViewState();
}

class _TwoDimensionListViewState extends State<TwoDimensionListView> {
  final _focusNode = FocusNode();
  static const double _topPadding = 20.0;

  /// 本次按键是否已触发过长按（用于松手时抑制短按）
  bool _longSelectFired = false;

  /// 是否启用长按：仅在调用方传入 onLongSelect 时启用，
  /// 未启用时保持原有「按下即触发」行为，避免影响其它调用点。
  bool get _longSelectEnabled => widget.onLongSelect != null;

  /// 竖向布局下从 row 出发，按 step 方向寻找第一个含元素的行
  ///
  /// 若目标行为空行，直接落过去会让列号变成 -1，
  /// 表现为"选中框消失、按 OK 没有反应"，遥控器像失灵一样。
  int? _findRowWithItem(int row, int step) {
    for (var r = row; r >= 0 && r < widget.itemCount.row; r += step) {
      if (widget.itemCount.col(r) > 0) return r;
    }
    return null;
  }

  bool _handleSelect() {
    if (!_focusNode.hasFocus) return false;
    if (_position.row >= 0 && _position.col >= 0) {
      widget.onSelect?.call(_position);
    }
    return true;
  }

  /// 垂直滚动控制器
  late final ScrollController _verticalScrollController;

  /// 水平滚动控制器
  late final ScrollController _horizontalScrollController;

  /// 当前选中位置。
  ///
  /// 以 ValueNotifier 作为唯一真源：每个 tile 各自订阅它，移动焦点时
  /// 只重建「失去选中的那个」和「得到选中的那个」，而不是整表 setState。
  /// 竖向布局动辄几百个频道，全表重建在按方向键连换台时会明显掉帧。
  late final ValueNotifier<({int row, int col})> _positionNotifier =
      ValueNotifier<({int row, int col})>(widget.initialPosition);

  ({int row, int col}) get _position => _positionNotifier.value;
  set _position(({int row, int col}) value) => _positionNotifier.value = value;

  /// 竖向布局的一维 slot 索引，见 [_buildSlots]。横向布局下恒为 null。
  List<_Slot>? _slots;

  /// 竖向模式下一组之前的累积高度（滚动到分组头）
  double _getVerticalScrollOffset(int row) {
    if (widget.verticalLayout) {
      if (row <= 0) return _topPadding;
      double offset = row * widget.gap.row;
      for (int i = 0; i < row; i++) {
        final headerH = widget.headerHeightBuilder?.call(i) ?? 40;
        final n = widget.itemCount.col(i);
        offset += headerH;
        // 必须判 n > 0：空组实际只占「分组头 + 组间距」，
        // 套公式会多算 (n-1)*gap.col = -gap.col，往后每组都累积一个偏差，
        // 表现为跨过一个空分组后，跳到该组的频道时定位整体偏高。
        if (n > 0) offset += n * widget.size.rowHeight + (n - 1) * widget.gap.col;
      }
      return offset + _topPadding;
    }
    final size = widget.size.rowHeight;
    return (row + widget.scrollOffset.row) * (size + widget.gap.row);
  }

  /// 水平滚动偏移
  double _getHorizontalScrollOffset(int idx) {
    final size = widget.verticalLayout ? widget.size.rowHeight : widget.size.colWidth;
    return (idx + widget.scrollOffset.col) * (size + widget.gap.col);
  }

  /// 改变选中
  Future<void> _changePosition({required int row, required int col, bool jumpTo = false}) async {
    final prevRow = _position.row;
    final prevCol = _position.col;

    // 只把「选中位置变了」这件事广播给订阅者，由对应 tile 自行重建
    _position = (row: row, col: col);

    // 横向模式下行内列表挂的水平 ScrollController 归属随行切换而变，
    // 换 controller 只能整表重建（横向行数本来就少，代价可忽略）。
    if (!widget.verticalLayout && row != prevRow && mounted) {
      setState(() {});
    }

    _focusNode.requestFocus();

    if (widget.verticalLayout) {
      if (row != prevRow) {
        // 切换分组时滚动到适当位置
        double offset;
        final colCount = widget.itemCount.col(row);
        if (col == colCount - 1) {
          // 跳到分组最后一条时，滚动到分组底部
          final groupEnd = _getVerticalScrollOffset(row + 1);
          offset = (groupEnd - (widget.viewportHeight ?? 480)).clamp(0.0, groupEnd);
        } else {
          offset = _getVerticalScrollOffset(row);
        }
        (jumpTo ? _verticalScrollController.jumpTo(offset) : _verticalScrollController.animateTo(
          offset.clamp(
            _verticalScrollController.position.minScrollExtent,
            _verticalScrollController.position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        ));
      } else if (col != prevCol && widget.viewportHeight != null) {
        // 同分组内滚动，保持选中项可见
        final groupStart = _getVerticalScrollOffset(row);
        final headerH = widget.headerHeightBuilder?.call(row) ?? 40;
        final itemTop = groupStart + headerH + col * (widget.size.rowHeight + widget.gap.col);
        final itemBottom = itemTop + widget.size.rowHeight;
        final scrollPos = _verticalScrollController.offset;

        if (itemTop < scrollPos) {
          (jumpTo ? _verticalScrollController.jumpTo(itemTop) : _verticalScrollController.animateTo(
            itemTop.clamp(
              _verticalScrollController.position.minScrollExtent,
              _verticalScrollController.position.maxScrollExtent,
            ),
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          ));
        } else if (itemBottom > scrollPos + widget.viewportHeight!) {
          final targetOffset = itemBottom - widget.viewportHeight!;
          (jumpTo ? _verticalScrollController.jumpTo(targetOffset) : _verticalScrollController.animateTo(
            targetOffset.clamp(
              _verticalScrollController.position.minScrollExtent,
              _verticalScrollController.position.maxScrollExtent,
            ),
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          ));
        }
      }
    } else {
      if (jumpTo) {
        _verticalScrollController.jumpTo(_getVerticalScrollOffset(row).clamp(
          _verticalScrollController.position.minScrollExtent,
          _verticalScrollController.position.maxScrollExtent,
        ));
        _horizontalScrollController.jumpTo(_getHorizontalScrollOffset(col).clamp(
          _horizontalScrollController.position.minScrollExtent,
          _horizontalScrollController.position.maxScrollExtent,
        ));
      } else {
        await Future.wait([
          _verticalScrollController.animateTo(
            _getVerticalScrollOffset(row).clamp(
              _verticalScrollController.position.minScrollExtent,
              _verticalScrollController.position.maxScrollExtent,
            ),
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          ),
          _horizontalScrollController.animateTo(
            _getHorizontalScrollOffset(col).clamp(
              _horizontalScrollController.position.minScrollExtent,
              _horizontalScrollController.position.maxScrollExtent,
            ),
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          ),
        ]);
      }
    }
  }

  void _initData() {
    _verticalScrollController =
        ScrollController(initialScrollOffset: widget.verticalLayout ? 0 : _getVerticalScrollOffset(widget.initialPosition.row));
    _horizontalScrollController =
        ScrollController(initialScrollOffset: _getHorizontalScrollOffset(widget.initialPosition.col));

    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   _verticalScrollController.jumpTo(_getVerticalScrollOffset(widget.initialPosition.row).clamp(
    //     _verticalScrollController.position.minScrollExtent,
    //     _verticalScrollController.position.maxScrollExtent,
    //   ));

    //   _horizontalScrollController.jumpTo(_getHorizontalScrollOffset(widget.initialPosition.col).clamp(
    //     _horizontalScrollController.position.minScrollExtent,
    //     _horizontalScrollController.position.maxScrollExtent,
    //   ));
    // });
  }

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _positionNotifier.dispose();
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 竖向布局要把「分组头 + 分组内频道 + 间距」压平成一维 slot 序列。
    // 每次 build 重算一次：只是几百个轻量 slot 描述（int/double），
    // 滚动过程中不会重跑 build，所以既没有额外滚动开销，又能保证外部数据
    // 变化后索引一定是最新的。
    _slots = widget.verticalLayout ? _buildSlots() : null;

    final list = _buildRowList();
    final child = widget.verticalLayout
        ? Scrollbar(controller: _verticalScrollController, thumbVisibility: true, child: list)
        : list;
    return _buildKeyboardListener(child: child);
  }

  Widget _buildRowList() {
    // 竖向布局：单层 CustomScrollView + SliverList。
    //
    // 原来是「外层 shrinkWrap ListView（每组一个 item）套内层 shrinkWrap +
    // NeverScrollable 的 ListView」。ShrinkWrappingViewport 必须量过全部子项
    // 才能算出自身高度，于是几百个频道一次性 build + layout，虚拟化完全失效；
    // 而 _changePosition 又是 setState，遥控器按一次方向键就全表重排一次。
    // 压平成单个 SliverList 后只 build 视口内的条目，且几何尺寸完全一致
    // （见 _buildSlots 注释），_getVerticalScrollOffset 的偏移计算无需改动。
    if (widget.verticalLayout) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.viewportHeight ?? double.infinity),
        child: CustomScrollView(
          controller: _verticalScrollController,
          slivers: [
            SliverToBoxAdapter(child: SizedBox(height: _topPadding)),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                _buildVerticalSlot,
                childCount: _slots!.length,
              ),
            ),
          ],
        ),
      );
    }
    // cacheExtent 保持默认：原来写死 0 等于关掉视口外的预渲染区，快速滑动会白屏
    return ListView.separated(
      controller: _verticalScrollController,
      scrollDirection: Axis.vertical,
      separatorBuilder: (context, index) => SizedBox(height: widget.gap.row),
      itemCount: widget.itemCount.row + 1,
      itemBuilder: (context, index) {
        if (index == widget.itemCount.row) {
          return Container();
        }

        return SizedBox(
          height: widget.size.rowHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              widget.rowTopBuilder?.call(context, index) ?? Container(),
              Expanded(child: _buildColList(row: index)),
            ],
          ).delayed(enable: DebugSettings.delayRender),
        );
      },
    );
  }

  /// 横向布局下一个分组的行内列表。
  ///
  /// 横向模式的外层 ListView 不是 shrinkWrap，内层列表装在固定高度的 Expanded 里，
  /// 本身就是真正的 Viewport，虚拟化是生效的，不需要像竖向那样改造。
  Widget _buildColList({required int row}) {
    final scrollController = _position.row == row ? _horizontalScrollController : null;
    final listView = ListView.separated(
      controller: scrollController,
      scrollDirection: Axis.horizontal,
      separatorBuilder: (context, index) => SizedBox(width: widget.gap.col),
      itemCount: widget.itemCount.col(row) + 1,
      itemBuilder: (context, index) {
        if (index == widget.itemCount.col(row)) {
          return Container();
        }

        return GestureDetector(
          onTap: () {
            _changePosition(row: row, col: index);
            widget.onSelect?.call((row: row, col: index));
          },
          onLongPress: () {
            HapticFeedback.mediumImpact();
            _changePosition(row: row, col: index);
            widget.onLongSelect?.call((row: row, col: index));
          },
          child: SizedBox(
            width: widget.size.colWidth,
            child: _buildSelectableTile(row: row, col: index),
          ),
        );
      },
    );
    if (scrollController != null) {
      return Scrollbar(controller: scrollController, thumbVisibility: true, child: listView);
    }
    return listView;
  }

  /// 竖向布局的一维 slot 序列（分组头 / 频道 / 间距），每次 build 重建。
  ///
  /// 排布必须与原 shrinkWrap 版本逐像素一致，否则 _getVerticalScrollOffset
  /// 算出来的滚动位置会偏。原结构是：
  ///   padding(top: 20) → 每组 [分组头] + [频道间 gap.col] → 组间 gap.row（最后一组后面也有）
  ///                                                      → 末尾一个零高度的空 Container
  /// 这里压平成：20 的头部 Spacer → 每组 [header][item, gap.col, item, ...] → gap.row
  List<_Slot> _buildSlots() {
    final slots = <_Slot>[];
    final rows = widget.itemCount.row;
    for (var r = 0; r < rows; r++) {
      slots.add(_Slot.header(r));
      final n = widget.itemCount.col(r);
      for (var c = 0; c < n; c++) {
        if (c > 0) slots.add(_Slot.gap(widget.gap.col));
        slots.add(_Slot.item(r, c));
      }
      slots.add(_Slot.gap(widget.gap.row));
    }
    return slots;
  }

  Widget _buildVerticalSlot(BuildContext context, int index) {
    final slot = _slots![index];
    return switch (slot.type) {
      _SlotType.header => (widget.rowTopBuilder?.call(context, slot.row) ?? const SizedBox.shrink())
          .delayed(enable: DebugSettings.delayRender),
      _SlotType.gap => SizedBox(height: slot.height),
      _SlotType.item => _buildVerticalItem(row: slot.row, col: slot.col),
    };
  }

  Widget _buildVerticalItem({required int row, required int col}) {
    return GestureDetector(
      onTap: () {
        _changePosition(row: row, col: col);
        widget.onSelect?.call((row: row, col: col));
      },
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _changePosition(row: row, col: col);
        widget.onLongSelect?.call((row: row, col: col));
      },
      child: SizedBox(
        height: widget.size.rowHeight,
        child: _buildSelectableTile(row: row, col: col),
      ),
    );
  }

  /// 订阅选中位置的一个格子。
  ///
  /// 用 ValueListenableBuilder 的话，**每一个**可见格子都会在位置变化时
  /// 跟着 rebuild（它们都订阅了同一个 notifier），等于没省。
  /// _SelectableTile 只在这一格自己的选中状态真正翻转时才 setState，
  /// 于是移动焦点真正只重建「失去选中」和「得到选中」两个格子，
  /// 同屏其余上百个订阅者只是空跑一次比较，不落地任何 rebuild。
  Widget _buildSelectableTile({required int row, required int col}) {
    return _SelectableTile(
      position: _positionNotifier,
      row: row,
      col: col,
      builder: (context, position, isSelected) => widget
          .itemBuilder(context, position, isSelected)
          .delayed(enable: DebugSettings.delayRender),
    );
  }

  /// 监听键盘事件
  Widget _buildKeyboardListener({required Widget child}) {
    return EasyKeyboardListener(
      autofocus: true,
      focusNode: _focusNode,
      onKeyTap: {
        LogicalKeyboardKey.arrowUp: widget.verticalLayout
            ? () {
                if (!_focusNode.hasFocus) return false;
                if (_position.col > 0) {
                  _changePosition(row: _position.row, col: _position.col - 1);
                  return true;
                }
                final target = _findRowWithItem(_position.row - 1, -1);
                if (target == null) return false;
                _changePosition(row: target, col: widget.itemCount.col(target) - 1);
                return true;
              }
            : () {
                if (!_focusNode.hasFocus) return false;
                if (_position.row > 0) {
                  _changePosition(row: _position.row - 1, col: 0);
                  return true;
                }
                return false;
              },
        LogicalKeyboardKey.arrowDown: widget.verticalLayout
            ? () {
                if (!_focusNode.hasFocus) return false;
                final maxCol = widget.itemCount.col(_position.row) - 1;
                if (_position.col < maxCol) {
                  _changePosition(row: _position.row, col: _position.col + 1);
                  return true;
                }
                final target = _findRowWithItem(_position.row + 1, 1);
                if (target == null) return false;
                _changePosition(row: target, col: 0);
                return true;
              }
            : () {
                if (!_focusNode.hasFocus) return false;
                if (_position.row < widget.itemCount.row - 1) {
                  _changePosition(row: _position.row + 1, col: 0);
                  return true;
                }
                return false;
              },
        LogicalKeyboardKey.arrowLeft: widget.verticalLayout
            ? () => true
            : () {
                if (!_focusNode.hasFocus) return false;
                if (_position.col > 0) {
                  _changePosition(row: _position.row, col: _position.col - 1);
                } else {
                  _changePosition(row: _position.row, col: widget.itemCount.col(_position.row) - 1);
                }
                return true;
              },
        LogicalKeyboardKey.arrowRight: widget.verticalLayout
            ? () => true
            : () {
                if (!_focusNode.hasFocus) return false;
                if (_position.col < widget.itemCount.col(_position.row) - 1) {
                  _changePosition(row: _position.row, col: _position.col + 1);
                } else {
                  _changePosition(row: _position.row, col: 0);
                }
                return true;
              },
        // 启用长按时不在按下瞬间触发短按，改由松手时判定（见 onKeyUp）
        if (!_longSelectEnabled)
          LogicalKeyboardKey.select: () => _handleSelect(),
      },
      onKeyLongTap: {
        LogicalKeyboardKey.select: () {
          if (!_focusNode.hasFocus) return false;
          if (_position.row >= 0 && _position.col >= 0) {
            _longSelectFired = true;
            widget.onLongSelect?.call(_position);
          }
          return true;
        },
      },
      onKeyUp: _longSelectEnabled
          ? {
              LogicalKeyboardKey.select: () {
                if (!_focusNode.hasFocus) return false;
                // 长按已处理过，松手不再触发短按
                if (_longSelectFired) {
                  _longSelectFired = false;
                  return true;
                }
                return _handleSelect();
              },
            }
          : null,
      onKeyRepeat: {
        LogicalKeyboardKey.arrowUp: widget.verticalLayout
            ? () {
                if (!_focusNode.hasFocus) return false;
                if (_position.col > 0) {
                  _changePosition(row: _position.row, col: _position.col - 1, jumpTo: true);
                  return true;
                }
                final target = _findRowWithItem(_position.row - 1, -1);
                if (target != null) {
                  _changePosition(row: target, col: widget.itemCount.col(target) - 1, jumpTo: true);
                }
                return true;
              }
            : () {
                if (!_focusNode.hasFocus) return false;
                if (_position.row > 0) {
                  _changePosition(row: _position.row - 1, col: 0, jumpTo: true);
                  return true;
                }
                return true;
              },
        LogicalKeyboardKey.arrowDown: widget.verticalLayout
            ? () {
                if (!_focusNode.hasFocus) return false;
                final maxCol = widget.itemCount.col(_position.row) - 1;
                if (_position.col < maxCol) {
                  _changePosition(row: _position.row, col: _position.col + 1, jumpTo: true);
                  return true;
                }
                final target = _findRowWithItem(_position.row + 1, 1);
                if (target != null) {
                  _changePosition(row: target, col: 0, jumpTo: true);
                }
                return true;
              }
            : () {
                if (!_focusNode.hasFocus) return false;
                if (_position.row < widget.itemCount.row - 1) {
                  _changePosition(row: _position.row + 1, col: 0, jumpTo: true);
                  return true;
                }
                return false;
              },
        LogicalKeyboardKey.arrowLeft: widget.verticalLayout
            ? () => true
            : () {
                if (!_focusNode.hasFocus) return false;
                if (_position.col > 0) {
                  _changePosition(row: _position.row, col: _position.col - 1, jumpTo: true);
                }
                return true;
              },
        LogicalKeyboardKey.arrowRight: widget.verticalLayout
            ? () => true
            : () {
                if (!_focusNode.hasFocus) return false;
                if (_position.col < widget.itemCount.col(_position.row) - 1) {
                  _changePosition(row: _position.row, col: _position.col + 1, jumpTo: true);
                }
                return true;
              },
      },
      child: child,
    );
  }
}

/// 竖向布局一维序列中的槽位类型
enum _SlotType { header, item, gap }
/// 竖向布局一维序列中的槽位。
///
/// 只是描述壳层（这一格是什么），不含 Widget，
/// 因此每个 build 重算整个序列的开销可以忽略。
class _Slot {
  const _Slot.header(this.row)
      : type = _SlotType.header,
        col = -1,
        height = 0;

  const _Slot.item(this.row, this.col)
      : type = _SlotType.item,
        height = 0;

  const _Slot.gap(this.height)
      : type = _SlotType.gap,
        row = -1,
        col = -1;

  final _SlotType type;
  final int row;
  final int col;
  final double height;
}

/// 一个订阅了选中位置、但只在自己「选中状态翻转」时才重建的格子。
///
/// 直接挂 ValueListenableBuilder 的话，每次位置变化所有可见格子都会 rebuild；
/// 这里在监听回调里先比较「这一格是否真的是新旧选中项」，不是就什么都不做。
class _SelectableTile extends StatefulWidget {
  const _SelectableTile({
    required this.position,
    required this.row,
    required this.col,
    required this.builder,
  });

  final ValueListenable<({int row, int col})> position;
  final int row;
  final int col;
  final Widget Function(BuildContext context, ({int row, int col}) position, bool isSelected) builder;

  @override
  State<_SelectableTile> createState() => _SelectableTileState();
}

class _SelectableTileState extends State<_SelectableTile> {
  late bool _selected = _computeSelected();

  bool _computeSelected() {
    final p = widget.position.value;
    return p.row == widget.row && p.col == widget.col;
  }

  @override
  void initState() {
    super.initState();
    widget.position.addListener(_onPositionChanged);
  }

  @override
  void didUpdateWidget(covariant _SelectableTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position) {
      oldWidget.position.removeListener(_onPositionChanged);
      widget.position.addListener(_onPositionChanged);
    }
    // 行数/列数等外部数据变化导致的父级重建，这里同步一次即可
    _selected = _computeSelected();
  }

  void _onPositionChanged() {
    final next = _computeSelected();
    if (next == _selected) return;
    setState(() => _selected = next);
  }

  @override
  void dispose() {
    widget.position.removeListener(_onPositionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, (row: widget.row, col: widget.col), _selected);
}
