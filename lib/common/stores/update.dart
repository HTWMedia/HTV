import 'dart:convert';
import 'dart:io';

import 'package:mobx/mobx.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player_example/common/index.dart';

part 'update.g.dart';

class UpdateStore = UpdateStoreBase with _$UpdateStore;

int _compareVersions(String version1, String version2) {
  List<int> v1 = version1.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  List<int> v2 = version2.split('.').map((s) => int.tryParse(s) ?? 0).toList();

  final len = v1.length > v2.length ? v1.length : v2.length;
  for (int i = 0; i < len; i++) {
    final a = i < v1.length ? v1[i] : 0;
    final b = i < v2.length ? v2[i] : 0;
    if (a < b) return -1;
    if (a > b) return 1;
  }

  return 0;
}

final _logger = LoggerUtil.create(['更新']);

abstract class UpdateStoreBase with Store {
  @observable
  String currentVersion = '1.0.0';

  @observable
  var latestRelease = GithubRelease(tagName: 'v0.0.0', downloadUrl: '', description: '');

  @computed
  bool get hasUpdate => _compareVersions(latestRelease.tagName.substring(1), currentVersion) > 0;

  @observable
  bool updating = false;

  @observable
  String downloadProgress = '';

  bool _versionLoaded = false;

  /// 上次真的打过 GitHub release 接口的时间，配合 [_releaseCheckInterval] 做节流
  DateTime? _lastReleaseCheckAt;

  /// 上一次请求还没回来
  bool _releaseChecking = false;

  /// 两次检查之间的最小间隔。
  ///
  /// 播放页初始化和设置页 initState 都会调 refreshLatestRelease，
  /// 设置页又是每次打开都重建一次，不节流等于反复打 GitHub API。
  static const _releaseCheckInterval = Duration(minutes: 10);

  @action
  Future<void> loadCurrentVersion() async {
    if (_versionLoaded) return;
    try {
      final info = await PackageInfo.fromPlatform();
      currentVersion = info.version;
      _versionLoaded = true;
      _logger.debug('当前版本: $currentVersion');
    } catch (e) {
      _logger.debug('获取版本失败: $e');
    }
  }

  @action
  Future<void> refreshLatestRelease() async {
    if (hasUpdate) return;

    if (_releaseChecking) return;
    final last = _lastReleaseCheckAt;
    if (last != null && DateTime.now().difference(last) < _releaseCheckInterval) {
      _logger.debug('跳过更新检查：距上次不足 ${_releaseCheckInterval.inMinutes} 分钟');
      return;
    }

    _releaseChecking = true;
    try {
      _logger.debug('开始检查更新');

      GithubRelease? release;

      // 优先通过代理请求 GitHub API
      final proxyUrl = '${Constants.githubProxy}${Constants.githubReleaseApi}';
      final proxied = await _fetchRelease(proxyUrl);
      if (proxied != null) release = proxied;

      // 代理失败，直接请求 GitHub API
      if (release == null) {
        final direct = await _fetchRelease(Constants.githubReleaseApi);
        if (direct != null) release = direct;
      }

      if (release == null) {
        _logger.debug('检查更新失败: 无法获取 release 信息');
        return;
      }

      latestRelease = release;
      _logger.debug('检查更新成功: ${release.tagName}');

      if (hasUpdate && AppSettings.lastLatestVersion != release.tagName) {
        AppSettings.lastLatestVersion = release.tagName;
      }
    } catch (e, st) {
      _logger.handle(e, st);
    } finally {
      _releaseChecking = false;
      // 失败也算一次尝试，同样计入节流窗口，避免网络不通时反复重试
      _lastReleaseCheckAt = DateTime.now();
    }
  }

  Future<GithubRelease?> _fetchRelease(String url) async {
    try {
      final result = jsonDecode(await RequestUtil.get(url));
      if (result is! Map || result['tag_name'] == null) return null;

      return GithubRelease(
        tagName: result['tag_name'] ?? 'v0.0.0',
        downloadUrl: result['assets'] != null && result['assets'].isNotEmpty
            ? result['assets'][0]['browser_download_url'] ?? ''
            : '',
        description: result['body'] ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> downloadAndInstall() async {
    if (!hasUpdate || updating) return;

    updating = true;
    downloadProgress = '准备下载...';
    _logger.debug('正在下载更新: ${latestRelease.tagName}');

    try {
      final dir = await getTemporaryDirectory();
      final savePath = '${dir.path}/htv-${latestRelease.tagName}.apk';

      // 通过代理加速下载
      var downloadUrl = '${Constants.githubProxy}${latestRelease.downloadUrl}';

      final path = await RequestUtil.download(
        url: downloadUrl,
        savePath: savePath,
        onProgress: (progress) {
          final percent = (progress * 100).toInt();
          downloadProgress = '下载中 $percent%';
          _logger.debug('下载进度: $percent%');
        },
      );

      if (path == null) {
        // 代理失败，直连下载
        downloadUrl = latestRelease.downloadUrl;
      }

      final finalPath = path ?? await RequestUtil.download(
        url: downloadUrl,
        savePath: savePath,
        onProgress: (progress) {
          final percent = (progress * 100).toInt();
          downloadProgress = '下载中 $percent%';
        },
      );

      if (finalPath == null) {
        _logger.debug('下载更新失败');
        downloadProgress = '下载失败';
        updating = false;
        return;
      }

      _logger.debug('下载更新成功: $finalPath');
      downloadProgress = '正在安装...';

      await _installApk(finalPath);

      updating = false;
      downloadProgress = '';
    } catch (e, st) {
      _logger.handle(e, st);
      downloadProgress = '更新失败';
      updating = false;
    }
  }

  Future<void> _installApk(String path) async {
    try {
      await Process.run('am', [
        'start',
        '-a', 'android.intent.action.VIEW',
        '-d', 'file://$path',
        '-t', 'application/vnd.android.package-archive',
      ]);
    } catch (e) {
      _logger.error('安装失败: $e');
    }
  }
}
