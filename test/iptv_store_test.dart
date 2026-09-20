import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_example/common/index.dart';

void main() {
  test('源列表为空时上下换台不崩溃', () {
    final store = IptvStore();

    // 首次启动还没拉到源时的状态：iptvList 为空，currentIptv 还是占位值
    expect(store.iptvList, isEmpty);

    // 修复前这里会走 iptvList.last / .first，抛 Bad state: No element
    expect(() => store.getPrevIptv(), returnsNormally);
    expect(() => store.getNextIptv(), returnsNormally);
    // 拿不到别的频道就停在原地，播放器不会因为没有目标而出错
    expect(store.getPrevIptv(), store.currentIptv);
    expect(store.getNextIptv(), store.currentIptv);
  });

  test('只有一个频道时前后换台仍是它自己', () {
    final store = IptvStore();
    store.iptvGroupList = [
      IptvGroup(
        name: '测试',
        idx: 0,
        list: [
          Iptv(idx: 0, channel: 1, groupIdx: 0, name: 'CCTV-1', url: 'http://a.test/1.m3u8', tvgName: 'CCTV1'),
        ],
      ),
    ];

    final only = store.iptvList.single;
    expect(store.getPrevIptv(), only);
    expect(store.getNextIptv(), only);
  });

  test('换台到列表尾部/头部会环绕', () {
    final store = IptvStore();
    store.iptvGroupList = [
      IptvGroup(
        name: '测试',
        idx: 0,
        list: [
          for (var i = 0; i < 3; i++)
            Iptv(idx: i, channel: i + 1, groupIdx: 0, name: 'CH$i', url: 'http://a.test/$i.m3u8', tvgName: 'CH$i'),
        ],
      ),
    ];

    final list = store.iptvList;
    // 当前频道不在列表里（例如清空源之后），前后都得给出可用结果而不是越界
    expect(store.getPrevIptv(), list.last);
    expect(store.getNextIptv(), list.first);

    store.currentIptv = list.first;
    expect(store.getPrevIptv(), list.last);
    expect(store.getNextIptv(), list[1]);

    store.currentIptv = list.last;
    expect(store.getNextIptv(), list.first);
  });
}
