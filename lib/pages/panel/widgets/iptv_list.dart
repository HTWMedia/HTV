
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get_it/get_it.dart';
import 'package:video_player_example/common/index.dart';
import 'package:video_player_example/pages/settings/view.dart';

import '../../../common/widgets/two_dimension_list_view.dart';

class PanelIptvList extends StatefulWidget {
  const PanelIptvList({super.key});

  @override
  State<PanelIptvList> createState() => _PanelIptvListState();
}

class _PanelIptvListState extends State<PanelIptvList> {
  final iptvStore = GetIt.I<IptvStore>();

  int get _sourceCount => iptvStore.currentSources.length;
  bool get _hasSourceSwitch => _sourceCount > 1;
  int get _groupCount => iptvStore.iptvGroupList.length;

  /// 顶部固定行：收藏 / 源切换（可选） / 设置
  /// 收藏行常驻（为空时显示引导文案），避免行数随收藏增减变化导致焦点越界
  int get _favoriteRow => 0;
  int _sourceRow() => _hasSourceSwitch ? 1 : -1;
  int _settingsRow() => _hasSourceSwitch ? 2 : 1;
  int get _topRowCount => _settingsRow() + 1;

  int get _rowCount => _topRowCount + _groupCount;
  int _groupRow(int row) => row - _topRowCount;

  /// 指定行的分组，越界或不在频道行时返回 null
  ///
  /// 「直播源精简」「同名去重」可能让 groupIdx 与实际位置不一致，
  /// 直接按下标取值会越界崩溃，这里统一收敛。
  IptvGroup? _groupAt(({int row, int col}) position) {
    if (position.row < _topRowCount) return null;
    return iptvStore.iptvGroupList.elementAtOrNull(_groupRow(position.row));
  }

  /// 指定行的列数（按位置换算，不依赖 Iptv.groupIdx）
  int _colCount(int row) {
    if (row == _favoriteRow) {
      return iptvStore.favoriteIptvList.isEmpty ? 1 : iptvStore.favoriteIptvList.length;
    }
    if (row == _sourceRow() || row == _settingsRow()) return 1;
    final group = _groupAt((row: row, col: 0));
    return group?.list.length ?? 0;
  }

  /// 初始焦点位置
  ///
  /// 重排后 groupIdx/idx 已与列表位置一致，但仍收敛一次：
  /// 一旦越界，面板会"没有任何高亮项"，且首次按键取行数时直接崩溃。
  ({int row, int col}) get _initialPosition {
    final row = (iptvStore.currentIptv.groupIdx + _topRowCount).clamp(0, _rowCount - 1).toInt();
    final colCount = _colCount(row);
    if (colCount == 0) return (row: row, col: 0);
    final rawCol = iptvStore.currentIptv.idx;
    return (row: row, col: rawCol < 0 ? 0 : rawCol.clamp(0, colCount - 1).toInt());
  }

  /// 取指定位置的频道，非频道行返回 null
  Iptv? _iptvAt(({int row, int col}) position) {
    if (position.row == _favoriteRow) {
      final list = iptvStore.favoriteIptvList;
      if (position.col < list.length) return list[position.col];
      return null;
    }
    if (position.row == _sourceRow() || position.row == _settingsRow()) return null;
    final group = _groupAt(position);
    if (group == null) return null;
    if (position.col < group.list.length) return group.list[position.col];
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return Observer(builder: (context) {
        final favoriteList = iptvStore.favoriteIptvList;

        return TwoDimensionListView(
          verticalLayout: true,
          viewportHeight: constraints.maxHeight,
          initialPosition: _initialPosition,
          size: (rowHeight: 100.h, colWidth: 0),
          scrollOffset: (row: 0, col: 0),
          gap: (row: 12.h, col: 4.h),
          headerHeightBuilder: (row) => row == _sourceRow() || row == _settingsRow() ? 0 : 40,
          itemCount: (
            row: _rowCount,
            col: (row) => _colCount(row),
          ),
          rowTopBuilder: (context, row) {
            if (row == _sourceRow() || row == _settingsRow()) return const SizedBox.shrink();
            final group = _groupAt((row: row, col: 0));
            final title = row == _favoriteRow ? '收 藏' : (group?.name ?? '');
            return Padding(
              padding: EdgeInsets.only(bottom: 10.h),
              child: Text(
                title,
                style: AppTheme.text(AppTheme.fg(context), 24.sp, weight: FontWeight.bold),
              ),
            );
          },
          onSelect: (position) {
            if (position.row == _sourceRow()) {
              iptvStore.switchToNextSource();
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(SnackBar(
                  content: Text('已切换到源 ${iptvStore.currentSourceIndex + 1}/$_sourceCount'),
                  duration: const Duration(milliseconds: 1500),
                ));
              return;
            }
            if (position.row == _settingsRow()) {
              NavigatorUtil.push(context, const SettingsPage());
              return;
            }
            final iptv = _iptvAt(position);
            if (iptv == null) return; // 收藏为空时的引导项
            iptvStore.currentIptv = iptv;
            Navigator.pop(context);
          },
          onLongSelect: (position) {
            final iptv = _iptvAt(position);
            if (iptv == null) return; // 源、设置、以及收藏为空时的引导项不参与收藏

            iptvStore.toggleFavorite(iptv).then((nowFavorite) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(SnackBar(
                  content: Text(nowFavorite ? '已收藏「${iptv.name}」' : '已取消收藏「${iptv.name}」'),
                  duration: const Duration(milliseconds: 1200),
                ));
            });
          },
          itemBuilder: (context, position, isSelected) {
            if (position.row == _sourceRow()) return _buildSourceItem(isSelected);
            if (position.row == _settingsRow()) return _buildSettingsItem(isSelected);
            if (position.row == _favoriteRow) {
              // 取消收藏后本行列数会减少，可能暂时越界，回退到引导项
              if (position.col >= favoriteList.length) return _buildFavoriteEmptyItem(isSelected);
              return _buildIptvItem(favoriteList[position.col], isSelected);
            }
            final group = _groupAt(position);
            if (group == null || position.col >= group.list.length) return const SizedBox.shrink();
            return _buildIptvItem(group.list[position.col], isSelected);
          },
        );
      });
    });
  }

  /// 统一的列表块外壳：选中为前景色实心，未选中为半透明白。
  ///
  /// 这套「padding + 圆角 + 选中/未选中背景」原本在收藏引导、源切换、设置、
  /// 频道四个地方各抄了一遍，改配色要点四遍。
  ///
  /// 注：padding 由原来三处的 `symmetric(horizontal: 20.w, vertical: 10.h)`
  /// 统一成 `.r`（第四个频道项原本就是这么写的）。16:9 屏幕上两者完全等价，
  /// 只在非 16:9 设备上会有细微差别，换来的是可维护性。
  Widget _buildTile({required bool isSelected, required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10).r,
      decoration: BoxDecoration(
        color: AppTheme.tileFill(context, isSelected),
      ),
      child: child,
    );
  }

  /// 收藏为空时的引导项
  Widget _buildFavoriteEmptyItem(bool isSelected) {
    return _buildTile(
      isSelected: isSelected,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '长按 OK 键收藏当前频道',
          style: AppTheme.text(AppTheme.tileTextFaded(context, isSelected, 0.8), 26.sp),
          maxLines: 1,
        ),
      ),
    );
  }

  Widget _buildSourceItem(bool isSelected) {
    return _buildTile(
      isSelected: isSelected,
      child: Observer(
        builder: (_) => Text(
          '源 ${iptvStore.currentSourceIndex + 1}/$_sourceCount',
          style: AppTheme.text(AppTheme.tileText(context, isSelected), 30.sp),
        ),
      ),
    );
  }

  Widget _buildSettingsItem(bool isSelected) {
    final contentColor = AppTheme.tileText(context, isSelected);
    return _buildTile(
      isSelected: isSelected,
      child: Row(
        children: [
          Icon(Icons.settings, color: contentColor, size: 30.sp),
          SizedBox(width: 12.w),
          Text(
            '设 置',
            style: AppTheme.text(contentColor, 30.sp),
          ),
        ],
      ),
    );
  }

  Widget _buildIptvItem(Iptv iptv, bool isSelected) {
    return _buildTile(
      isSelected: isSelected,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Observer(
            builder: (_) {
              final favorite = iptvStore.isFavorite(iptv);
              return Row(
                children: [
                  if (favorite)
                    Padding(
                      padding: EdgeInsets.only(right: 8.w),
                      child: Icon(
                        Icons.star_rounded,
                        size: 26.sp,
                        color: isSelected ? Colors.amber.shade700 : Colors.amber,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      iptv.name,
                      style: AppTheme.text(AppTheme.tileText(context, isSelected), 30.sp),
                      maxLines: 1,
                    ),
                  ),
                ],
              );
            },
          ),
          Observer(
            builder: (_) => Text(
              iptvStore.getIptvProgrammes(iptv).current,
              style: AppTheme.text(AppTheme.tileTextFaded(context, isSelected, 0.8), 24.sp),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}
