import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

/// 虚拟滚动列表
class SliverListView {
  SliverListView._();

  static Widget separated({
    ScrollController? controller,
    Axis scrollDirection = Axis.vertical,
    required int itemCount,
    required Widget Function(BuildContext, int) separatorBuilder,
    required Widget? Function(BuildContext, int) itemBuilder,
    bool endSeparator = false,
  }) {
    return CustomScrollView(
      controller: controller,
      scrollDirection: scrollDirection,
      slivers: [
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              // 分隔符
              if (index.isOdd) {
                return separatorBuilder(context, index ~/ 2);
              }

              final itemIndex = index ~/ 2;
              return itemBuilder(context, itemIndex);
            },
            childCount: itemCount * 2 - (endSeparator ? 0 : 1), // 考虑到分隔符
          ),
        ),
      ],
    );
  }
}
