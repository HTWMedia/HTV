import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get_it/get_it.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:video_player_example/common/index.dart';

import '../../../common/widgets/two_dimension_list_view.dart';

class SettingGroup {
  final String name;
  final List<SettingItem> items;

  SettingGroup({required this.name, required this.items});
}

class SettingItem {
  final String title;
  final String Function() value;
  final String Function() description;
  final void Function() onTap;
  final void Function()? onLongTap;

  SettingItem({
    required this.title,
    required this.value,
    required this.description,
    required this.onTap,
    this.onLongTap,
  });
}

class SettingsMain extends StatefulWidget {
  const SettingsMain({super.key});

  @override
  State<SettingsMain> createState() => _SettingsMainState();
}

class _SettingsMainState extends State<SettingsMain> {
  final iptvStore = GetIt.I<IptvStore>();
  final updateStore = GetIt.I<UpdateStore>();

  late final List<SettingItem> _settingItemList;

  String _formatDuration(int ms) {
    if (ms < 60000) {
      return '${ms ~/ 1000}秒';
    } else if (ms < 3600000) {
      return '${ms ~/ 60000}分钟';
    } else {
      return '${ms ~/ 3600000}小时';
    }
  }

  void _showAssignUserDialog() {
    _showTvTextEditDialog(
      title: '用户参数',
      hint: '输入参数',
      initialValue: PrefsUtil.getString('assign_user') ?? '',
      maxWidth: 500,
      fontSize: 16,
      onSave: (value) {
        PrefsUtil.setString('assign_user', value);
        IptvSettings.iptvSourceCacheTime = 0;
        iptvStore.refreshIptvList().then((_) { if (mounted) setState(() {}); });
      },
    );
  }

  /// 电视端文本编辑弹窗
  ///
  /// Flutter 的按键分发顺序是「叶子节点 → 根」(focus_manager.dart:1995)，
  /// 而 EditableText 在最内层就把上下方向键映射成了光标移动
  /// (editable_text.dart:4835)。输入框一旦拿到焦点，外层 Focus 便再也收不到方向键，
  /// 「保存」按钮因此不可达；电视端又没有输入法，onSubmitted 同样不会触发。
  /// 所以改由容器层统一托管按键：方向键在各元素间移动焦点，OK 键执行当前元素。
  /// 具体实现对所有文本文件复用同一份，见 TvTextEditDialog。
  void _showTvTextEditDialog({
    required String title,
    required String hint,
    required String initialValue,
    required ValueChanged<String> onSave,
    String? subtitle,
    List<TvDialogButton> extraButtons = const <TvDialogButton>[],
    double maxWidth = 500,
    double fontSize = 24,
  }) {
    showDialog(
      context: context,
      builder: (_) => TvTextEditDialog(
        title: title,
        subtitle: subtitle,
        hint: hint,
        initialValue: initialValue,
        onSave: onSave,
        extraButtons: extraButtons,
        maxWidth: maxWidth,
        fontSize: fontSize,
      ),
    );
  }

  void _showChannelSelectDialog() async {
    final allChannels = await IptvUtil.getAllChannelNames();
    if (!mounted) return;
    if (allChannels.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('无可选频道，请先获取直播源')));
      return;
    }

    final initialSelected = Set<String>.from(IptvSettings.allowedChannels.isNotEmpty
        ? IptvSettings.allowedChannels
        : allChannels.where((n) => n.toLowerCase().startsWith('cctv') || n.endsWith('卫视')));

    final result = await ChannelSelectDialog.show(
      context,
      allChannels: allChannels,
      selected: initialSelected,
    );

    if (result != null && mounted) {
      IptvSettings.allowedChannels = result.toList();
      IptvSettings.iptvSourceSimplify = true;
      IptvSettings.epgCacheHash = 0;
      iptvStore.refreshIptvList().then((_) { if (mounted) setState(() {}); });
    }
  }

  void _showCustomSourceDialog() {
    _showTvTextEditDialog(
      title: '自定义直播源',
      subtitle: '支持 m3u 订阅链接与 TVBox 链接，也可用手机扫码后在网页填写',
      hint: '输入订阅链接',
      initialValue: IptvSettings.customIptvSource,
      maxWidth: 700,
      fontSize: 24,
      extraButtons: [
        TvDialogButton(label: '二维码', onPressed: _showServerQrcode),
      ],
      onSave: (value) {
        IptvSettings.customIptvSource = value.trim();
        IptvSettings.iptvSourceSimplify = false;
        IptvSettings.iptvSourceCacheTime = 0;
        IptvSettings.epgCacheHash = 0;
        iptvStore.refreshIptvList().then((_) { if (mounted) setState(() {}); });
      },
    );
  }

  /// 默认源服务地址
  ///
  /// 壳源分离的关键入口：把写死的服务端地址变成可配置项。
  /// 留空 = 停用内置源，App 退化为纯播放器，只加载用户自己的订阅。
  void _showDefaultApiDialog() {
    _showTvTextEditDialog(
      title: '默认源服务',
      subtitle: '留空表示停用内置源，届时只加载「自定义直播源」里填写的订阅',
      hint: '输入接口地址',
      initialValue: IptvSettings.defaultIptvSourceApi,
      maxWidth: 700,
      fontSize: 20,
      onSave: (value) {
        IptvSettings.defaultIptvSourceApi = value.trim();
        IptvSettings.epgCacheHash = 0;
        iptvStore.refreshIptvList().then((_) { if (mounted) setState(() {}); });
      },
    );
  }

  void _showServerQrcode() {
    final fg = AppTheme.fg(context);
    NavigatorUtil.push(
      context,
      TvModalScaffold(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '扫描二维码设置',
                style: AppTheme.text(fg, 36.sp),
              ),
              SizedBox(height: 12.h),
              Text(
                HttpServerUtil.serverUrl,
                style: AppTheme.text(AppTheme.fgFaded(context, 0.7), 24.sp),
              ),
              SizedBox(height: 24.h),
              Container(
                decoration: BoxDecoration(
                  color: fg,
                  borderRadius: BorderRadius.circular(20).r,
                ),
                padding: const EdgeInsets.all(8),
                child: SizedBox(
                  height: 300.h,
                  width: 300.h,
                  child: PrettyQrView.data(
                    data: HttpServerUtil.serverUrl,
                    decoration: PrettyQrDecoration(
                      shape: PrettyQrSmoothSymbol(
                        color: AppTheme.bg(context),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 24.h),
              Text(
                '点击空白处或按 ESC 返回',
                style: AppTheme.text(AppTheme.fgFaded(context, 0.5), 20.sp),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 社区与反馈：展示 QQ 群二维码
  ///
  /// 用内置图片资产而不是 qm.qq.com 的加群链接再生成二维码——
  /// 那种链接带时效 key，会过期；官方生成的群二维码图最稳。
  void _showCommunityQrcode() {
    final fg = AppTheme.fg(context);
    NavigatorUtil.push(
      context,
      TvModalScaffold(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '扫码加入交流群',
                style: AppTheme.text(fg, 36.sp),
              ),
              SizedBox(height: 12.h),
              Text(
                '频道失效、问题反馈、交流用法（任选其一，一群人满请进二群）',
                style: AppTheme.text(AppTheme.fgFaded(context, 0.7), 24.sp),
              ),
              SizedBox(height: 24.h),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _groupQrCard('assets/images/qq-group1.jpg', '一群 2166024531'),
                  SizedBox(width: 48.w),
                  _groupQrCard('assets/images/qq-group2.jpg', '二群 1067526818'),
                ],
              ),
              SizedBox(height: 24.h),
              Text(
                '点击空白处或按 ESC 返回',
                style: AppTheme.text(AppTheme.fgFaded(context, 0.5), 20.sp),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _groupQrCard(String asset, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16).r,
          child: Image.asset(
            asset,
            height: 340.h,
            fit: BoxFit.cover,
          ),
        ),
        SizedBox(height: 12.h),
        Text(
          label,
          style: AppTheme.text(AppTheme.fg(context), 26.sp),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    refreshSettingGroupList();

    // 同样要判 mounted：init 是异步的，用户可能在服务起来前就退出了设置页
    HttpServerUtil.init().then((_) { if (mounted) setState(() {}); });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
        height: 190.w + 20.h,
        child: TwoDimensionListView(
        size: (rowHeight: 190.w, colWidth: 400.w),
        scrollOffset: (row: 0, col: -1),
        gap: (row: 20.h, col: 20.w),
        itemCount: (
        row: 1,
        col: (_) => _settingItemList.length,
        ),
        onSelect: (position) => setState(() {
          _settingItemList.elementAtOrNull(position.col)?.onTap();
        }),
        onLongSelect: (position) => setState(() {
          _settingItemList.elementAtOrNull(position.col)?.onLongTap?.call();
        }),
        itemBuilder: (context, position, isSelected) {
          final item = _settingItemList[position.col];

          return _buildSettingItem(item, isSelected);
        },
      ),
    );
  }

  Widget _buildSettingItem(SettingItem item, bool isSelected) {
    final textColor = AppTheme.tileText(context, isSelected);

    return Container(
      padding: const EdgeInsets.all(30).r,
      decoration: BoxDecoration(
        color: isSelected
            ? AppTheme.fg(context)
            : AppTheme.bgFaded(context, 0.8),
        borderRadius: BorderRadius.circular(20).r,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                item.title,
                style: AppTheme.text(textColor, 30.sp),
              ),
              Text(
                item.value(),
                style: AppTheme.text(textColor, 30.sp),
              ),
            ],
          ),
          Text(
            item.description(),
            style: AppTheme.text(textColor, 24.sp),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          )
        ],
      ),
    );
  }

  void refreshSettingGroupList() {
    final groupList = [
      SettingGroup(name: '应用', items: [
        SettingItem(
          title: '用户参数',
          value: () {
            final v = PrefsUtil.getString('assign_user') ?? '';
            return v.length > 8 ? '${v.substring(0, 8)}...' : v;
          },
          description: () => '点击编辑',
          onTap: () => _showAssignUserDialog(),
        ),
        SettingItem(
          title: '开机自启',
          value: () => AppSettings.bootLaunch ? '启用' : '禁用',
          description: () => '下次重启生效',
          onTap: () {
            AppSettings.bootLaunch = !AppSettings.bootLaunch;
            // 这类开关不走网络请求，没有异步回调替我们刷新，
            // 少了这句点击后界面纹丝不动，用户会以为没点上。
            setState(() {});
          },
        ),
      ]),
      SettingGroup(name: '控制', items: [
        SettingItem(
          title: '换台反转',
          value: () => IptvSettings.channelChangeFlip ? '反转' : '正常',
          description: () => IptvSettings.channelChangeFlip ? '方向键上：下一个频道\n方向键下：上一个频道' : '方向键上：上一个频道\n方向键下：下一个频道',
          onTap: () {
            IptvSettings.channelChangeFlip = !IptvSettings.channelChangeFlip;
            // 同「开机自启」：纯开关，靠手动 rebuild 让同一个 item 重新求值 value/description
            setState(() {});
          },
        ),
      ]),
      SettingGroup(name: '直播源', items: [
        SettingItem(
          title: '默认源服务',
          value: () {
            final api = IptvSettings.defaultIptvSourceApi;
            if (api.isEmpty) return '已停用';
            return api.length > 28 ? '${api.substring(0, 28)}...' : api;
          },
          description: () => IptvSettings.defaultIptvSourceApi.isEmpty
              ? '当前只加载自定义源；点击重新配置，长按恢复默认'
              : '点击编辑接口地址（清空即停用内置源）',
          onTap: () => _showDefaultApiDialog(),
          onLongTap: () {
            IptvSettings.defaultIptvSourceApi = Constants.defaultIptvSourceApi;
            IptvSettings.epgCacheHash = 0;
            iptvStore.refreshIptvList().then((_) { if (mounted) setState(() {}); });
          },
        ),
        SettingItem(
          title: '直播源精简',
          value: () {
            if (!IptvSettings.iptvSourceSimplify) return '禁用';
            final count = IptvSettings.allowedChannels.length;
            return count > 0 ? '启用 ($count个频道)' : '启用';
          },
          description: () {
            if (!IptvSettings.iptvSourceSimplify) return '显示完整直播源';
            final count = IptvSettings.allowedChannels.length;
            if (count > 0) return '仅显示已选频道，点击自定义';
            return '显示精简直播源(仅央视、地方卫视)';
          },
          onTap: () {
            if (IptvSettings.iptvSourceSimplify) {
              _showChannelSelectDialog();
            } else {
              IptvSettings.iptvSourceSimplify = true;
              IptvSettings.epgCacheHash = 0;
              iptvStore.refreshIptvList().then((_) { if (mounted) setState(() {}); });
            }
          },
          onLongTap: () {
            if (!IptvSettings.iptvSourceSimplify) return;
            IptvSettings.iptvSourceSimplify = false;
            IptvSettings.epgCacheHash = 0;
            iptvStore.refreshIptvList().then((_) { if (mounted) setState(() {}); });
          },
        ),
        SettingItem(
          title: '自定义直播源',
          value: () => IptvSettings.customIptvSource.isNotEmpty ? '已启用' : '未启用',
          description: () {
            if (IptvSettings.customIptvSource.isEmpty) return '点击设置订阅链接';
            final src = IptvSettings.customIptvSource;
            return src.length > 35 ? '${src.substring(0, 35)}...' : src;
          },
          onTap: () => _showCustomSourceDialog(),
          onLongTap: () {
            IptvSettings.customIptvSource = '';
            IptvSettings.iptvSourceCacheTime = 0;
            IptvSettings.epgCacheHash = 0;
            iptvStore.refreshIptvList().then((_) { if (mounted) setState(() {}); });
          },
        ),
        SettingItem(
          title: '直播源缓存',
          value: () => _formatDuration(IptvSettings.iptvSourceCacheKeepTime),
          description: () => IptvSettings.iptvSourceCacheTime > 0 ? "已缓存(点击清除缓存)" : "未缓存",
          onTap: () {
            if (IptvSettings.iptvSourceCacheTime > 0) {
              IptvSettings.iptvSourceCacheTime = 0;
              iptvStore.refreshIptvList().then((_) { if (mounted) setState(() {}); });
            }
          },
        ),
      ]),
      SettingGroup(name: '节目单', items: [
        SettingItem(
          title: '节目单',
          value: () => IptvSettings.epgEnable ? '启用' : '禁用',
          description: () => '首次加载时可能会有跳帧风险',
          onTap: () {
            IptvSettings.epgEnable = !IptvSettings.epgEnable;
            iptvStore.refreshEpgList().then((_) { if (mounted) setState(() {}); });
          },
        ),
        SettingItem(
          title: '自定义节目单',
          value: () => IptvSettings.customEpgXml.isNotEmpty ? '已启用' : '未启用',
          description: () => IptvSettings.customEpgXml.isNotEmpty ? '长按恢复默认' : '点击查看网址二维码',
          onTap: () => _showServerQrcode(),
          onLongTap: () {
            IptvSettings.customEpgXml = '';
            IptvSettings.epgXmlCacheTime = 0;
            IptvSettings.epgCacheHash = 0;
            iptvStore.refreshEpgList().then((_) { if (mounted) setState(() {}); });
          },
        ),
        SettingItem(
          title: '节目单缓存',
          value: () => '当天',
          description: () => IptvSettings.epgXmlCacheTime > 0 ? "已缓存(点击清除缓存)" : "未缓存",
          onTap: () {
            if (IptvSettings.epgXmlCacheTime > 0) {
              IptvSettings.epgXmlCacheTime = 0;
              IptvSettings.epgCacheHash = 0;
              iptvStore.refreshEpgList().then((_) { if (mounted) setState(() {}); });
            }
          },
        ),
        SettingItem(
          title: '回看诊断',
          value: () => '偏移 ${IptvSettings.catchupUtcOffsetHours}h',
          description: () => '点击诊断当前频道能否回看（会比对回看与直播的返回内容）；长按切换时区偏移',
          onTap: () => _runCatchupProbe(),
          onLongTap: () {
            IptvSettings.catchupUtcOffsetHours =
                IptvSettings.catchupUtcOffsetHours == 8 ? 0 : 8;
            setState(() {});
            ScaffoldMessenger.of(context)
              ..clearSnackBars()
              ..showSnackBar(SnackBar(
                content: Text('回看时区偏移已改为 ${IptvSettings.catchupUtcOffsetHours}h'),
                duration: const Duration(seconds: 2),
              ));
          },
        ),
      ]),
      SettingGroup(name: '社区与反馈', items: [
        SettingItem(
          title: 'QQ 交流群',
          value: () => '2166024531 / 1067526818',
          description: () => '频道失效反馈、交流用法；点击显示群二维码',
          onTap: () => _showCommunityQrcode(),
        ),
        SettingItem(
          title: '问题反馈',
          value: () => '',
          description: () => '也可到 GitHub Discussions 发帖（可检索、永久留档）',
          onTap: () {
            _showProbeResult(
              'GitHub Discussions',
              'github.com/HTWMedia/HTV → Discussions\n发帖时请带上：频道名 + 现象 + 地区/网络 + App 版本',
            );
          },
        ),
      ]),
      SettingGroup(name: '更多', items: [
        SettingItem(
          title: '更多设置',
          value: () => '',
          description: () => '访问以下网址进行配置：${HttpServerUtil.serverUrl}',
          onTap: () => _showServerQrcode(),
        ),
      ]),
    ];

    _settingItemList = groupList.expand((element) => element.items).toList();
  }

  void _showProbeResult(String title, String detail) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('$title\n$detail'),
        duration: const Duration(seconds: 6),
      ));
  }

  /// 拉取播放列表正文（原始字节），用于回看与直播逐字节比对
  Future<({int status, List<int> bytes})> _fetchPlaylist(String url) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final req =
          await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 10));
      final resp = await req.close().timeout(const Duration(seconds: 10));
      final bytes = <int>[];
      await resp.forEach(bytes.addAll);
      return (status: resp.statusCode, bytes: bytes);
    } catch (e) {
      return (status: -1, bytes: const <int>[]);
    } finally {
      client?.close(force: true);
    }
  }

  bool _sameBytes(List<int> a, List<int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 源类型说明，用来解释"为什么这个频道回看不可用"
  ///
  /// 这几条都是实测结论：给地址追加回看参数后，服务端返回的播放列表
  /// 与直播逐字节相同，即参数被直接忽略。
  String _sourceKind(Iptv iptv) {
    final url = iptv.url.split(';').first.trim().toLowerCase();
    if (url.isEmpty) return '源地址为空';
    if (url.contains('key=txiptv') || url.contains('/tsfile/live/')) {
      return '运营商公网转播(txiptv)，playseek 参数实测被忽略';
    }
    if (url.contains('cctvnews.cctv.com')) {
      return '央视官方 HLS，lbacks 参数实测被忽略';
    }
    return '普通直播源，服务端未声明回看能力';
  }

  /// 回看能力探测
  ///
  /// 先确认源是否声明了 catchup，再用最近一个已播完的节目拼地址。
  /// 关键一步是**与直播地址逐字节比对**：很多服务端只是忽略未知参数、
  /// 照样返回直播列表，那时"HTTP 200"是假象，放出来的还是直播流。
  Future<void> _runCatchupProbe() async {
    final playerStore = GetIt.I<PlayerStore>();
    final iptv = iptvStore.currentIptv;

    if (!iptv.supportCatchup) {
      _showProbeResult(
        '回看不可用',
        '${iptv.name}：${_sourceKind(iptv)}\n源数据未下发 catchup 字段，App 无法自行拼出回看地址',
      );
      return;
    }

    final programmes = iptvStore.getProgrammes(iptv);
    final target = CatchupUtil.pickProbeProgramme(programmes);
    if (target == null) {
      _showProbeResult(
        '没有可回看的节目',
        programmes.isEmpty ? 'EPG 里没有 ${iptv.name}' : '${iptv.name} 今天还没有播完的节目',
      );
      return;
    }

    final urls =
        CatchupUtil.buildUrls(iptv, startMs: target.start, stopMs: target.stop);
    LoggerUtil.debug('回看探测候选: ${urls.join('  |  ')}');
    if (urls.isEmpty) {
      _showProbeResult('无法拼出回看地址', '${iptv.name} 的 catchup 模板为空');
      return;
    }

    final liveUrl = iptv.url.split(';').first.trim();
    final live = await _fetchPlaylist(liveUrl);

    String? playUrl;
    final report = <String>[];
    for (final url in urls) {
      final r = await _fetchPlaylist(url);
      if (r.status < 0) {
        report.add('请求失败（超时或不可达）');
        continue;
      }
      if (r.status >= 400) {
        report.add('HTTP ${r.status}');
        continue;
      }
      if (live.status >= 0 && live.bytes.isNotEmpty && _sameBytes(live.bytes, r.bytes)) {
        report.add('HTTP ${r.status}，但内容与直播逐字节相同 → 参数被忽略');
        continue;
      }
      report.add('HTTP ${r.status} 且内容与直播不同，疑似真实录像');
      playUrl ??= url;
    }

    if (playUrl == null) {
      _showProbeResult('回看未生效', '《${target.title}》\n${report.join('\n')}');
      return;
    }

    await playerStore.playCatchup(iptv, url: playUrl);
    _showProbeResult(
      '回看《${target.title}》已开始',
      '按返回键观看；若画面是直播而不是片头，说明时区偏移要调',
    );
  }
}
