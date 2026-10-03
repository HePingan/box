# 后台播放与画中画（⑥）：设计与取舍（2026-10-03）

## A. 画中画（PiP）

- 清单：`MainActivity` 加 `android:supportsPictureInPicture="true"`（`resizeableActivity`
  与 `configChanges` 早就有了，所以缩窗不会重建 Activity）。
- 原生：`PlayerPipChannel.kt`（通道 `top.hpa888.box/player_pip`）——
  `isSupported` / `enter` / `setAutoEnter`，并把 `onPictureInPictureModeChanged`
  的结果推回 Dart（`pipModeChanged`）。
- Dart：`player_pip_channel.dart`（含 `isInPip` 的 `ValueNotifier`）。

### 只在全屏播放态开

PiP 缩的是**整个 Activity**，不是某一个 widget。内嵌在详情页里进小窗，用户看到的是
整个详情页被压扁 —— 没有意义。所以：

- 小窗按钮只出现在 **全屏** 态的底栏；
- `setAutoEnter`（播放中上滑回桌面自动进小窗，API 31+）只在
  **全屏 + 正在播放** 时开启，其它情况一律关掉 —— 否则用户只是浏览，一上滑就莫名缩窗。

### 小窗里要「让路」

Android 进小窗时会给我们 `onPause`，Flutter 报 `paused`。容器原来在 `paused` 时
**暂停播放**（这是切后台的设计），进小窗就会被误伤，所以加了一条前置判断：

```dart
if (_pipChannel.isInPip.value) return;   // 小窗不是「切后台」
```

同时小窗里收起顶栏/底栏（`_onPipChanged`），点击也不再展开控件（交给系统的小窗菜单）。

## B. 后台播放 / 息屏播放

- 清单：`FOREGROUND_SERVICE_MEDIA_PLAYBACK` 权限 + `PlaybackKeepAliveService`
  （`foregroundServiceType="mediaPlayback"`）。
- 原生：`PlaybackKeepAliveService.kt`（通知渠道 `video_playback_channel`、
  通知 ID **1004**、看门狗 30 分钟、音频焦点）+ `PlaybackNotificationChannel.kt`
  （通道 `top.hpa888.box/video_playback`）。
- Dart：`playback_notification_channel.dart`、`playback_background_policy.dart`、
  `video_playback_settings.dart`（默认**开**，播放器倍速面板里有开关）。

### 时机：必须趁前台就挂（这条最容易做错）

Android 12+ **不允许 App 退到后台之后再启动前台服务**
（`ForegroundServiceStartNotAllowedException`）。所以「等切后台再 startForeground」的
方案在现代系统上直接失败。落地做法是：**一开播就挂**（`_maybeStartPlaybackNotification`
挂在播放状态变化里），代价是开着这个开关时，前台看剧也会有一条常驻媒体通知
（Android 对后台播放的硬要求）。关掉开关 = 没有通知，也没有后台出声。

回到前台**不撤**通知：服务停了就再也起不来（同样是那条后台启动限制）。
只在「离开播放器 / 关掉开关 / 看门狗超时」时收工。

### 谁决定暂停

`PlaybackBackgroundPolicy`（纯逻辑，有测试）：
- `shouldKeepPlaying(enabled, isPlaying, isPip)`：切后台该不该继续出声；
- `shouldResumeOnForeground(keptPlaying, wasPlayingBeforeBackground)`：回前台要不要恢复
  （保活时它一直在播，恢复反而会把用户在通知栏按的暂停顶回去）；
- `shouldRunService(enabled, isPlaying, isPip)`：该不该挂前台服务。

### 音频焦点

服务 `requestAudioFocus`，被抢（来电 / 别的 App 放音）时推 `audioFocusLost` 回 Dart，
由 Dart 暂停 —— **策略留在能测的一侧**，原生只负责「说一声」。

## 验证

- Dart：新增 31 条用例（画中画 8 + 后台策略 11 + 设置 5 + 通知通道 7），
  `flutter analyze --no-fatal-infos` 28 = 基线。
- 原生：`./gradlew :app:compileDebugKotlin`（`BUILD_EXIT=0`）。
- 尚未在真机验证：小窗比例/退回全屏、息屏是否真的不断声、通知按钮是否按得动 ——
  这些只有真机能定，见汇报里的「需要你手机验」。
