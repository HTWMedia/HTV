import 'dart:convert';

import 'package:mobx/mobx.dart';
import 'package:video_player_example/common/index.dart';
//import 'package:package_info_plus/package_info_plus.dart';

part 'update.g.dart';

class UpdateStore = UpdateStoreBase with _$UpdateStore;

int _compareVersions(String version1, String version2) {
  List<int> v1 = version1.split('.').map(int.parse).toList();
  List<int> v2 = version2.split('.').map(int.parse).toList();

  // 对比主版本号、次版本号和修订号
  for (int i = 0; i < 3; i++) {
    if (v1[i] < v2[i]) {
      return -1;
    } else if (v1[i] > v2[i]) {
      return 1;
    }
  }

  // 如果三个号码都相同，则版本相同
  return 0;
}

final _logger = LoggerUtil.create(['更新']);

abstract class UpdateStoreBase with Store {
  /// 当前版本
  @observable
  String currentVersion = '0.0.0';

  /// 最新release
  @observable
  var latestRelease = GithubRelease(tagName: 'v0.0.0', downloadUrl: '', description: '');

  /// 发现更新
  @computed
  bool get hasUpdate => _compareVersions(latestRelease.tagName.substring(1), currentVersion) > 0;

  /// 正在更新
  @observable
  bool updating = false;

  /// 获取最新release
  @action
  Future<void> refreshLatestRelease() async {
    if (hasUpdate) return;

    try {
      _logger.debug('开始检查更新: ${Constants.githubReleaseLatest}');

      currentVersion = '1.0.0';

      final result = jsonDecode(await RequestUtil.get(Constants.githubReleaseLatest));
      latestRelease = GithubRelease(
        tagName: result['tag_name'],
        downloadUrl: result['assets'][0]['browser_download_url'],
        description: result['body'],
      );

      _logger.debug('检查更新成功: ${latestRelease.tagName}');

      // AppSettings.lastLatestVersion 防止提示频繁
      if (hasUpdate && AppSettings.lastLatestVersion != latestRelease.tagName) {
        //showToast('发现新版本: ${latestRelease.tagName}');
        AppSettings.lastLatestVersion = latestRelease.tagName;
      }
    } catch (e, st) {
      _logger.handle(e, st);
      //showToast('检查更新失败');
      rethrow;
    }
  }

  /// 下载安装包并安装
  Future<void> downloadAndInstall() async {
    /*if (!hasUpdate) return;
    if (updating) return;

    updating = true;
    _logger.debug('正在下载更新: ${latestRelease.tagName}');
    showToast('正在下载更新: ${latestRelease.tagName}', duration: const Duration(seconds: 10));

    try {
      final path = await RequestUtil.download(
        url: '${Constants.githubProxy}${latestRelease.downloadUrl}',
        directory: (await getTemporaryDirectory()).path,
        name: 'my_tv-latest.apk',
        onProgress: (percent) {
          _logger.debug('正在下载更新: ${percent.toInt()}%');
          showToast('正在下载更新: ${percent.toInt()}%', duration: const Duration(seconds: 10));
        },
      );

      _logger.debug('下载更新成功: $path');
      showToast('下载更新成功');

      if (await Permission.requestInstallPackages.request().isGranted) {
        await ApkInstaller.installApk(path);
      } else {
        showToast('请授予安装权限');
      }
    } catch (e, st) {
      _logger.handle(e, st);
      showToast('下载更新失败');
      rethrow;
    } finally {
      updating = false;
    }*/
  }
}