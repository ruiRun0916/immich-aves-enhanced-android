# Immich-Aves Enhanced Android

把 [Aves](https://github.com/deckerst/aves) 的界面语言与交互方式，移植到
[Immich](https://github.com/immich-app/immich) 的安卓客户端上。

> **本项目基于 [immich-app/immich](https://github.com/immich-app/immich) 修改，界面交互参考 [deckerst/aves](https://github.com/deckerst/aves)。**
> 上游版权与许可归各自作者所有，详见文末「来源与许可」。

---

## 这个项目解决什么问题

Immich 官方客户端功能完整，但它的界面是「工具型」的：顶栏是 logo、筛选要进独立页面、底栏只有 4 个 tab。
Aves 是 Android 上体验最好的本地相册应用，它的顶栏是一行文字标题 + 动作图标、筛选是紧凑胶囊、
底栏是一条 9 图标的玻璃栏、照片查看器上浮着一层信息叠加层。

这个项目把 Aves 那套**视觉与交互**搬到 Immich 上，同时保留 Immich 的云端同步、相册、地图、标签能力。

**只改移动端，服务端一行没动。** 你仍然连自己部署的 Immich 服务器。

---

## 当前状态

| 项 | 状态 |
|---|---|
| 最新版本 | **v3.5.1**（2026-10-27） |
| 分支 | `feat/immich-aves-enhanced` |
| 静态分析 | `lib/` 下 0 issue |
| 单元测试 | `flutter test test/domain` 101/101 通过 |
| 真机验证 | ⚠️ **部分**。APK 已能在小米 11 Ultra 上安装启动，登录流程尚未跑通 |

> 仓库里没有放 APK —— 安装包体积 180MB+，不进版本库。需要的话自己按下面「构建」一节编。

---

## 已实现的功能

### 幻灯片

- 全屏播放，按设定间隔自动切换
- 六种过渡动画：**滑动 / 视差滚动 / 淡入淡出 / 放大 / 无 / 随机**
- 重复播放、随机播放、填充屏幕（裁切铺满）
- 动画缩放效果（Ken Burns 缓慢推近）
- 时间间隔 1~60 秒
- 视频处理：静音播放 / 带声音 / 跳过
- 播放中左右滑动手动翻页，点一下画面收起控制栏

### 查看器叠加层

浮在照片上的一层信息卡片，每一项都能单独关掉：

- 顶部：序号与总数、文件名、日期、分辨率、拍摄参数（`ƒ/2.4 1/833 2.6mm ISO51`）、地点、星级、描述
- 右上：位置胶囊（点击进全屏地图）
- 右侧：实时缩放倍率
- 左下：直方图（亮度 / RGB / 关闭）
- 底部：胶片条，点击可跳页

**级联规则**：「显示信息」是「拍摄详情 / 评分和标签 / 描述」的父开关，关掉后这三项在设置页整行置灰、渲染层也同步失效。

### 顶栏与底栏

- Aves 式顶栏：文字标题 + 一排动作图标，反向滑动任意距离自动浮回（含 snap）
- 紧凑筛选胶囊：全部 / 云端 / 本地 / 筛选
- 布局控制胶囊：升降序、布局、排序、分区
- 底部单条玻璃栏：4 个 tab + dock 前 5 项 = 9 个图标，带实时磨砂
- 上滑全屏（底栏跟手滑出）、下滑恢复

### 浏览与筛选

- 综合浏览 / 服务器图库 / 本地图库三种模式
- 4 种布局（马赛克 / 网格 / 列表 / 日历）、4 种分区、6 种排序
- 1~8 列缩放
- 服务器相册、本地图库支持就地筛选
- 全景统计（格式、年份、地点、相机排行）

---

## 构建

### 环境要求

- Flutter SDK（项目基于 Flutter 3.x，Dart `>=3.12.0`）
- JDK 17
- Android SDK（build-tools 34、platform 34+）

本项目在本机的 Flutter 装在非标准路径，所以下面的命令都写绝对路径，按自己环境调整。

### 命令

```bash
cd mobile

# 依赖
flutter pub get

# 静态分析（lib 下应为 0 issue）
flutter analyze

# 单元测试
flutter test test/domain

# 编译 release
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

### 已知的报错（不是你弄坏的）

`flutter analyze` 会报约 28 条错误，全部在：

- `integration_test/` —— `pubspec.yaml` 里 `integration_test` 依赖被注释掉了，这些文件必然报 URI 不存在
- `test/drift/main/*`、`test/medium/*` —— drift 的 schema 代码没生成

判定标准：**`lib/` 目录下 0 issue** 即为通过。

---

## 代码结构（新增部分）

```
mobile/lib/
├── providers/
│   ├── aves_settings.provider.dart          # 布局/分区/排序/列数/dock 配置
│   ├── aves_scroll_chrome.provider.dart     # 滚动驱动的界面外壳显隐
│   ├── aves_slideshow.provider.dart         # 幻灯片设置
│   ├── aves_overlay.provider.dart           # 叠加层设置（含级联派生 getter）
│   └── album_media_filter.provider.dart     # 相册内就地筛选
├── presentation/
│   ├── pages/
│   │   ├── aves_slideshow.page.dart         # 幻灯片播放器
│   │   ├── aves_slideshow_settings.page.dart
│   │   ├── aves_overlay_settings.page.dart
│   │   ├── aves_statistics.page.dart
│   │   └── dev/main_timeline.page.dart      # 主时间线（大改）
│   └── widgets/
│       ├── timeline/
│       │   ├── aves_timeline_header.widget.dart
│       │   ├── aves_floating_header_sliver.widget.dart
│       │   ├── aves_control_bar.widget.dart
│       │   ├── aves_floating_dock_slider.widget.dart
│       │   └── aves_calendar_view.widget.dart
│       ├── common/aves_blurred_surface.widget.dart
│       ├── asset_viewer/
│       │   ├── aves_overlay_layer.widget.dart
│       │   ├── aves_histogram.widget.dart
│       │   ├── aves_viewer_bridge.dart
│       │   ├── aves_viewer_overlay_host.widget.dart
│       │   └── asset_details/aves_metadata_panel.widget.dart
│       └── settings/
│           ├── aves_customization_sheet.widget.dart
│           └── asset_viewer_settings/aves_viewer_entries.dart
└── widgets/settings/asset_viewer_settings/    # 设置页重排
```

---

## 与 Aves 的对照

做这个项目时反复对照 Aves 源码，几个关键参数记录在此，避免凭感觉改：

| 元素 | Aves 规格 | 本项目 |
|---|---|---|
| 顶栏 | 文字标题 + 动作图标（无 logo） | 一致 |
| 筛选栏胶囊 | `minChipHeight = 48`，行高 60 | 44 / 56 |
| 布局栏 | 4 胶囊，高 60 | 一致 |
| 浮动栏 | 圆角 8 + 1px 描边 + `blur(sigma 4)` + 0.85 底色 | 一致 |
| 底栏图标数 | 一条，9 个 | 一致 |
| 磨砂关闭 | 用恒等矩阵，不改组件树 | 一致 |
| 叠加层级联 | 「显示信息」为父开关 | 一致 |

---

## 已知问题

- **真机登录流程未跑通** —— APK 能装能启动，首启页填完服务器地址后点「下一步」没有跳转，待排查
- 排序只在日期分组内生效，跨分组不重排
- 本地 MediaStore 文件夹相册的筛选尚未接入（v3.5.2 开发中）
- APK 体积 189MB，未做 ABI 拆分

---

## 来源与许可

### 上游项目

- **[immich-app/immich](https://github.com/immich-app/immich)** —— 本项目代码基础。Immich 采用 **AGPL-3.0** 许可。
  本仓库是在其安卓客户端（`mobile/`）上做的修改，服务端代码原样保留、未作改动。
- **[deckerst/aves](https://github.com/deckerst/aves)** —— 界面与交互设计的参考来源。Aves 采用 **GPL-3.0** 许可。
  本项目**未复制 Aves 的源代码**，界面元素是按观察其表现与源码结构后重新实现的；
  涉及的设计语言（磨砂玻璃、浮动栏、胶囊筛选、叠加层）属于交互范式，不构成代码衍生。

### 本仓库许可

本仓库包含 Immich 的完整源码，因此**整体沿用 AGPL-3.0**，详见 [LICENSE](LICENSE)。

如果你分发本项目的修改版，需要同样以 AGPL-3.0 公开源代码。

---

## 相关文档

项目开发过程中的交接文档与调研记录（在仓库外的本地目录，不随源码发布）：

- `HANDOFF-2026-10-27-v3.5.1.md` —— 2026-10-27 的增量交接（幻灯片 + 叠加层）
- `IMMICH_AVES_PROJECT_HANDOFF.md` —— 项目整体交接
- `DEEPSEEK_DEV_GUIDE.md` —— 开发环境细节
