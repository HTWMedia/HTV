import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../style/index.dart';
import 'tv_dialog_frame.dart';

/// 频道选择弹窗
///
/// 与常规写法的关键差异：不给每个频道项套原生 Focus。
/// 原生焦点遍历下，「保存」排在上百个频道之后，遥控器根本走不到；
/// 这里改用容器层 Focus + 「区域 / 下标」模型自行绘制高亮，
/// 列表走到头再往下就落到底部按钮区，保存始终可达。
class ChannelSelectDialog extends StatefulWidget {
  const ChannelSelectDialog({
    super.key,
    required this.allChannels,
    required this.selected,
  });

  final List<String> allChannels;

  /// 初始已选频道
  final Set<String> selected;

  /// 返回用户确认后的选中集合；取消则为 null
  static Future<Set<String>?> show(
    BuildContext context, {
    required List<String> allChannels,
    required Set<String> selected,
  }) =>
      showDialog<Set<String>>(
        context: context,
        builder: (_) => ChannelSelectDialog(
          allChannels: allChannels,
          selected: selected,
        ),
      );

  @override
  State<ChannelSelectDialog> createState() => _ChannelSelectDialogState();
}

class _ChannelSelectDialogState extends State<ChannelSelectDialog>
    with TvDialogEditStateMixin<ChannelSelectDialog> {
  /// 焦点区域
  static const int areaSearch = 0;
  static const int areaAction = 1;
  static const int areaList = 2;
  static const int areaBottom = 3;
  static const int areaCount = 4;

  /// 列表行高（设计稿单位），用于滚动定位
  static const double listRowHeight = 60;

  late final Set<String> _selected;

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode(debugLabel: 'ChannelSearchField');
  final _scrollController = ScrollController();
  final _itemKeys = <int, GlobalKey>{};

  String _filter = '';
  int _area = areaList;
  int _actionIndex = 0;
  int _bottomIndex = 1;
  int _listIndex = 0;

  @override
  FocusNode get tvEditFocusNode => _searchFocusNode;

  @override
  void onTvEditingChanged(bool editing) {
    // 直接用 _searchFocusNode 点击进来时，把高亮同步到搜索框，
    // 否则会出现「焦点在搜索框、高亮却在频道列表」的错位
    if (editing) _area = areaSearch;
  }

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.selected);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<String> get _channels {
    if (_filter.isEmpty) return widget.allChannels;
    final q = _filter.toLowerCase();
    return widget.allChannels.where((n) => n.toLowerCase().contains(q)).toList();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final common = tvHandleCommonKey(event);
    if (common != null) return common;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveVertical(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveVertical(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _moveHorizontal(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _moveHorizontal(1);
      return KeyEventResult.handled;
    }
    if (isTvConfirmKey(key)) {
      _activate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 上下方向键：列表区内移动条目，走到首尾再跨区；其它区直接跨区
  void _moveVertical(int step) {
    if (_area == areaList) {
      final list = _channels;
      if (list.isEmpty) {
        _moveArea(step);
        return;
      }
      final next = _listIndex + step;
      if (next < 0) {
        setState(() => _listIndex = 0);
        _moveArea(-1);
        return;
      }
      if (next >= list.length) {
        _moveArea(1);
        return;
      }
      setState(() => _listIndex = next);
      _ensureVisible(next);
      return;
    }
    _moveArea(step);
  }

  void _moveArea(int step) {
    setState(() {
      _area = ((_area + step) % areaCount + areaCount) % areaCount;
    });
    if (_area == areaList) {
      _ensureVisible(_listIndex);
    }
  }

  void _moveHorizontal(int step) {
    switch (_area) {
      case areaAction:
        setState(() => _actionIndex = (_actionIndex + step).clamp(0, 1));
        break;
      case areaBottom:
        setState(() => _bottomIndex = (_bottomIndex + step).clamp(0, 1));
        break;
      default:
        break;
    }
  }

  void _activate() {
    switch (_area) {
      case areaSearch:
        tvEnterEditing();
        break;
      case areaAction:
        setState(() {
          if (_actionIndex == 0) {
            _selected.addAll(widget.allChannels);
          } else {
            _selected.clear();
          }
        });
        break;
      case areaList:
        final channel = _channels.elementAtOrNull(_listIndex);
        if (channel != null) _toggle(channel);
        break;
      case areaBottom:
        if (_bottomIndex == 0) {
          Navigator.pop(context);
        } else {
          Navigator.pop(context, _selected);
        }
        break;
    }
  }

  void _toggle(String channel) {
    setState(() {
      if (_selected.contains(channel)) {
        _selected.remove(channel);
      } else {
        _selected.add(channel);
      }
    });
  }

  /// 保证下标对应行可见（行尚未构建时先按行高粗调，再在下一帧校正）
  void _ensureVisible(int index, {bool retry = true}) {
    final keyContext = _itemKeys[index]?.currentContext;
    if (keyContext != null) {
      Scrollable.ensureVisible(
        keyContext,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        alignment: 0.5,
      );
      return;
    }
    if (!retry || !_scrollController.hasClients) return;
    final target = (index * listRowHeight.h - 120)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.jumpTo(target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureVisible(index, retry: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final fg = AppTheme.fg(context);
    final channels = _channels;
    return TvDialogFrame(
      focusNode: tvRootFocusNode,
      onKeyEvent: _handleKey,
      maxWidth: 600,
      maxHeight: 700,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '选择频道',
            style: AppTheme.text(fg, 36.sp),
          ),
          SizedBox(height: 16.h),
          TvDialogField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            hint: '搜索频道...',
            // 非编辑态下，高亮是否落在搜索区
            active: tvEditing || _area == areaSearch,
            verticalPadding: 6,
            leading: Icon(Icons.search, color: fg, size: 28.sp),
            onTap: tvEnterEditing,
            onSubmitted: (_) => tvExitEditing(),
            onChanged: (v) => setState(() {
              _filter = v;
              _listIndex = 0;
              _area = areaList;
            }),
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              TvDialogChip(
                label: '全选',
                highlighted: _area == areaAction && _actionIndex == 0,
                onTap: () => setState(() {
                  _area = areaAction;
                  _actionIndex = 0;
                  _selected.addAll(widget.allChannels);
                }),
              ),
              SizedBox(width: 16.w),
              TvDialogChip(
                label: '取消全选',
                highlighted: _area == areaAction && _actionIndex == 1,
                onTap: () => setState(() {
                  _area = areaAction;
                  _actionIndex = 1;
                  _selected.clear();
                }),
              ),
              const Spacer(),
              Text(
                '已选 ${_selected.length}',
                style: AppTheme.text(AppTheme.fgFaded(context, AppTheme.oTertiary), 22.sp),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Expanded(child: _buildList(channels)),
          SizedBox(height: 12.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TvDialogChip(
                label: '取消',
                highlighted: _area == areaBottom && _bottomIndex == 0,
                onTap: () => Navigator.pop(context),
              ),
              SizedBox(width: 16.w),
              TvDialogChip(
                label: '保存 (${_selected.length})',
                highlighted: _area == areaBottom && _bottomIndex == 1,
                onTap: () => Navigator.pop(context, _selected),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<String> channels) {
    if (channels.isEmpty) {
      return Center(
        child: Text(
          '无匹配频道',
          style: AppTheme.text(AppTheme.fgFaded(context, AppTheme.oTertiary), 26.sp),
        ),
      );
    }
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: channels.length,
        itemBuilder: (context, index) => _buildRow(channels[index], index),
      ),
    );
  }

  Widget _buildRow(String channel, int index) {
    final fg = AppTheme.fg(context);
    final isChecked = _selected.contains(channel);
    final highlighted = _area == areaList && _listIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _area = areaList;
          _listIndex = index;
        });
        _toggle(channel);
      },
      child: Container(
        key: _itemKeys.putIfAbsent(index, () => GlobalKey()),
        height: listRowHeight.h,
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        decoration: BoxDecoration(
          color: isChecked ? AppTheme.fgFaded(context, 0.15) : null,
          borderRadius: BorderRadius.circular(8).r,
          border: Border.all(
            color: highlighted ? fg : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isChecked ? Icons.check_box : Icons.check_box_outline_blank,
              color: fg,
              size: 28.sp,
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                channel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.text(fg, 26.sp),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
