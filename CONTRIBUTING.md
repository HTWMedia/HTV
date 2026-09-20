# 贡献指南 / Contributing

感谢愿意为 HTV 出力！无论是报一个失效频道、修一个 UI 细节还是加一个新功能，都欢迎。

## 反馈比写代码更重要

发现问题请优先提 Issue / Discussion（见下方模板），一份带「现象 + 地区 + 网络 + 版本」的反馈
比十句「看不了了」有用得多。**不需要会写代码也能贡献。**

## 开发环境

- Flutter `>=3.13.0`（Dart SDK `^3.1.0`），建议用与 `pubspec.lock` 一致的版本
- Android 构建需要 Android SDK；调试真机建议直接用电视盒子或手机

```bash
git clone https://github.com/HTWMedia/HTV.git
cd HTV
flutter pub get

# MobX 状态管理使用代码生成，改动 store 后需要重新生成：
dart run build_runner build --delete-conflicting-outputs

# 运行
flutter run

# 测试
flutter test
```

> 播放内核使用 `fijkplayer_ijkfix`（基于 ijkplayer 的定制版）。
> 如果依赖拉取失败，先确认已能访问 pub.dev；仍失败请开 Issue 说明。

## 目录结构

```
lib/
  main.dart              # 启动与全局初始化
  common/
    api/                 # 网络接口
    stores/              # MobX 状态（iptv / player 等）
    utils/               # 工具（含源健康度记忆 source_health.dart）
    widgets/  components/  style/  i18n/
  pages/
    iptv/  panel/  settings/   # 三大页面
```

## 代码约定

- 状态管理用 MobX：页面只管渲染，状态放 `common/stores`，别在 Widget 里堆业务逻辑
- 注释用中文，解释「为什么」而不是复述代码
- 所有交互都要兼顾**遥控器**（方向键 / OK 键 / 菜单键）与**触屏**两套操作
- 改动涉及换源 / 起播 / 卡顿判定逻辑时，请在 `test/` 里补对应用例（现有 58 个测试要保持全绿）
- 提交前跑一遍 `flutter analyze` 和 `flutter test`

## Pull Request 流程

1. Fork → 建分支（`feat/xxx` 或 `fix/xxx`）
2. 一个 PR 只做一件事，改动能说清楚「为什么」
3. 描述里写清：改了什么、为什么改、怎么验证的（最好附真机测试结果）
4. 不要顺手格式化没改过的文件，diff 越小越快合并

## 红线（请务必遵守）

**不要向仓库提交任何具体直播源地址、频道清单、订阅链接或鉴权参数。**
仓库里的源列表来自服务端下发，这是刻意的架构——版权风险不落在代码仓库里。
涉及「加源 / 换源」的 PR，请只改逻辑，不写死数据，否则无法合并。

## 想加新功能？

先开 Issue / Discussion 讨论，避免做完发现方向不对。大改动（换播放器、改架构）请一定先聊。
