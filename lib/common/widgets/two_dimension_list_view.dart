import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player_example/common/index.dart';
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
    required this.itemCount,
    required this.itemBuilder,
    this.onSelect,
    this.onLongSelect,
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

  /// 元素数量
  final ({int row, int Function(int row) col}) itemCount;

  /// 元素
  final Widget Function(BuildContext context, ({int row, int col}) position, bool isSelected) itemBuilder;

  /// 选中事件
  final void Function(({int row, int col}) position)? onSelect;

  /// 持续长选中事件
  final void Function(({int row, int col}) position)? onLongSelect;

  @override
  State<TwoDimensionListView> createState() => _TwoDimensionListViewState();
}

class _TwoDimensionListViewState extends State<TwoDimensionListView> {
  final _focusNode = FocusNode();

  /// 垂直滚动控制器
  late final ScrollController _verticalScrollController;

  /// 水平滚动控制器
  late final ScrollController _horizontalScrollController;

  /// 当前选中
  late var _position = widget.initialPosition;

  /// 垂直滚动偏移
  double _getVerticalScrollOffset(int idx) {
    return (idx + widget.scrollOffset.row) * (widget.size.rowHeight + widget.gap.row);
  }

  /// 水平滚动偏移
  double _getHorizontalScrollOffset(int idx) {
    return (idx + widget.scrollOffset.col) * (widget.size.colWidth + widget.gap.col);
  }

  /// 改变选中
  Future<void> _changePosition({required int row, required int col, bool jumpTo = false}) async {
    setState(() {
      _position = (row: row, col: col);
    });

    if (jumpTo) {
      _verticalScrollController.jumpTo(_getVerticalScrollOffset(_position.row).clamp(
        _verticalScrollController.position.minScrollExtent,
        _verticalScrollController.position.maxScrollExtent,
      ));

      _horizontalScrollController.jumpTo(_getHorizontalScrollOffset(_position.col).clamp(
        _horizontalScrollController.position.minScrollExtent,
        _horizontalScrollController.position.maxScrollExtent,
      ));
    } else {
      await _verticalScrollController.animateTo(
        _getVerticalScrollOffset(_position.row).clamp(
          _verticalScrollController.position.minScrollExtent,
          _verticalScrollController.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 300),
        curve: Curves.linear,
      );

      await _horizontalScrollController.animateTo(
        _getHorizontalScrollOffset(_position.col).clamp(
          _horizontalScrollController.position.minScrollExtent,
          _horizontalScrollController.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 300),
        curve: Curves.linear,
      );
    }
  }

  void _initData() {
    _verticalScrollController =
        ScrollController(initialScrollOffset: _getVerticalScrollOffset(widget.initialPosition.row));
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
  Widget build(BuildContext context) {
    return _buildKeyboardListener(child: _buildRowList());
  }

  Widget _buildRowList() {
    return ListView.separated(
      cacheExtent: 0,
      controller: _verticalScrollController,
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

  Widget _buildColList({required int row}) {
    return ListView.separated(
      cacheExtent: 0,
      controller: _position.row == row ? _horizontalScrollController : null,
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
            child: widget
                .itemBuilder(
              context,
              (row: row, col: index),
              row == _position.row && index == _position.col,
            )
                .delayed(enable: DebugSettings.delayRender),
          ),
        );
      },
    );
  }

  /// 监听键盘事件
  Widget _buildKeyboardListener({required Widget child}) {
    return EasyKeyboardListener(
      autofocus: true,
      focusNode: _focusNode,
      onKeyTap: {
        LogicalKeyboardKey.arrowUp: () {
          if (_position.row > 0) {
            _changePosition(row: _position.row - 1, col: 0);
          } else {
            _changePosition(row: widget.itemCount.row - 1, col: 0);
          }
        },
        LogicalKeyboardKey.arrowDown: () {
          if (_position.row < widget.itemCount.row - 1) {
            _changePosition(row: _position.row + 1, col: 0);
          } else {
            _changePosition(row: 0, col: 0);
          }
        },
        LogicalKeyboardKey.arrowLeft: () {
          if (_position.col > 0) {
            _changePosition(row: _position.row, col: _position.col - 1);
          } else {
            _changePosition(row: _position.row, col: widget.itemCount.col(_position.row) - 1);
          }
        },
        LogicalKeyboardKey.arrowRight: () {
          if (_position.col < widget.itemCount.col(_position.row) - 1) {
            _changePosition(row: _position.row, col: _position.col + 1);
          } else {
            _changePosition(row: _position.row, col: 0);
          }
        },
        LogicalKeyboardKey.select: () {
          if (_position.row >= 0 && _position.col >= 0) {
            widget.onSelect?.call(_position);
          }
        },
      },
      onKeyLongTap: {
        LogicalKeyboardKey.select: () {
          if (_position.row >= 0 && _position.col >= 0) {
            widget.onLongSelect?.call(_position);
          }
        },
      },
      onKeyRepeat: {
        LogicalKeyboardKey.arrowUp: () {
          if (_position.row > 0) {
            _changePosition(row: _position.row - 1, col: 0, jumpTo: true);
          }
        },
        LogicalKeyboardKey.arrowDown: () {
          if (_position.row < widget.itemCount.row - 1) {
            _changePosition(row: _position.row + 1, col: 0, jumpTo: true);
          }
        },
        LogicalKeyboardKey.arrowLeft: () {
          if (_position.col > 0) {
            _changePosition(row: _position.row, col: _position.col - 1, jumpTo: true);
          }
        },
        LogicalKeyboardKey.arrowRight: () {
          if (_position.col < widget.itemCount.col(_position.row) - 1) {
            _changePosition(row: _position.row, col: _position.col + 1, jumpTo: true);
          }
        },
      },
      child: child,
    );
  }
}
