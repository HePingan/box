/// 权限说明页的内容。
///
/// 这一页为什么值得单开：Android 自己的权限弹窗只会念系统原文 —— 无障碍服务的
/// 原文是「可以查看屏幕上的所有内容并控制设备」，看着像木马。**只有应用自己**能把它
/// 翻译成人话，并说清「为什么需要 / 什么时候用到 / 不给会怎样 / 怎么关掉」。
/// 直装（非应用商店）的应用尤其需要这一步自证。
///
/// 纪律：每条 [PermissionNote.manifestName] **必须与
/// `android/app/src/main/AndroidManifest.xml` 里的 `android:name` 逐字一致**。
/// `test/features/about/permission_notes_test.dart` 拿两边做**双向集合比对**：
/// 漏写一条（用户看不到解释）或多写一条（解释一个并不存在的权限）都会红。
/// 加权限时请同时在这里加一条；删权限时也要把这边的删掉。
library;

class PermissionNote {
  const PermissionNote({
    required this.manifestName,
    required this.title,
    required this.why,
    required this.when,
    required this.ifDenied,
    required this.howToRevoke,
  });

  /// 与 `AndroidManifest.xml` 里的 `android:name` 逐字一致。
  final String manifestName;

  /// 给人看的名字（「麦克风」而不是 `RECORD_AUDIO`）。
  final String title;

  final String why;

  /// 什么时候会用到（用户最关心的其实是这一条）。
  final String when;

  /// 拒绝/关掉之后会怎样 —— 必须如实，不能写「没有任何影响」。
  final String ifDenied;

  /// 去哪里关（能关的写具体路径，关不掉的如实说关不掉）。
  final String howToRevoke;
}

/// 页面顶部的一句话。
///
/// 条数**现算**而不是写死「13 项」：写死的数字在增删权限后会变成假话，
/// 而这一页最不能出的就是假话。
String permissionIntro() =>
    '应用一共声明 ${kPermissionNotes.length} 项权限与系统能力，逐条列在下面。'
    '除「麦克风」会在你点「开始测量」时当场申请外，其余都不需要你在使用时点同意：'
    '它们要么在安装时声明，要么需要你自己去系统设置里手动开启'
    '（只有无障碍服务与悬浮窗是这样）。';

/// 页面底部的一句话。
const String kPermissionOutro =
    '关掉任何一项都不会让应用打不开：受影响的功能会给出提示，其余照常可用。'
    '任何时候都可以按上面的路径收回这些权限；卸载应用即全部收回。';

/// 13 项权限/能力，逐条对应清单里的声明。
///
/// 排列顺序按「普通 → 敏感」：网络类在前，麦克风、无障碍这类用户最在意的在后，
/// 顺着读下来像是一次交代，而不是把最吓人的放开头。
const List<PermissionNote> kPermissionNotes = [
  PermissionNote(
    manifestName: 'android.permission.INTERNET',
    title: '网络访问',
    why: '检索影视与小说内容源、检查更新、登录与云同步、浏览插件市场，全靠它。',
    when: '打开任何需要联网的功能时。',
    ifDenied:
        '这是安装时声明的基础权限，没有它应用无法联网；部分系统可在应用详情里单独关闭联网。',
    howToRevoke: '多数系统不提供单独开关，可在系统设置的本应用详情页关闭「联网」；'
        '没有该开关时只能卸载。',
  ),
  PermissionNote(
    manifestName: 'android.permission.ACCESS_NETWORK_STATE',
    title: '网络状态',
    why: '判断当前是不是在移动网络、有没有断网，好给出「网络不可用」的提示，'
        '而不是让播放器一直转圈。',
    when: '开始播放、下载、检查更新前。',
    ifDenied: '权限声明仍在，应用可能把「断网」当成「加载慢」，提示会不准。',
    howToRevoke: '安装时声明的基础权限，系统不提供单独开关。',
  ),
  PermissionNote(
    manifestName: 'android.permission.REQUEST_INSTALL_PACKAGES',
    title: '安装应用（应用内更新）',
    why: '应用内更新下载完安装包后，直接调起系统安装器，省掉「去文件管理器找 APK」这一步。',
    when: '你点「检查更新」并下载完新版本时。',
    ifDenied: '更新包仍会下载，但需要在文件管理器里手动点击安装。',
    howToRevoke: '系统设置 → 应用 → 极客匣 → 安装未知应用，可随时关闭。',
  ),
  PermissionNote(
    manifestName: 'android.permission.READ_EXTERNAL_STORAGE',
    title: '读取存储',
    why: '读取你自己放到手机里的备份文件、以及下载目录里的内容。',
    when: '导入备份、从手机里选文件、读取已下载的内容时。',
    ifDenied: '无法导入外部文件；应用内部的数据不受影响。',
    howToRevoke: '系统设置 → 应用 → 极客匣 → 权限 → 存储。',
  ),
  PermissionNote(
    manifestName: 'android.permission.WRITE_EXTERNAL_STORAGE',
    title: '写入存储',
    why: '把更新安装包、导出的备份文件、下载的内容保存到手机里。',
    when: '下载、导出备份时。',
    ifDenied: '下载与导出会失败并给出提示。',
    howToRevoke: '系统设置 → 应用 → 极客匣 → 权限 → 存储。',
  ),
  PermissionNote(
    manifestName: 'android.permission.POST_NOTIFICATIONS',
    title: '通知',
    why: '显示下载进度与后台任务的完成提示（视频下载、漫画缓存、传输）。',
    when: '有下载或后台任务在运行时。',
    ifDenied: '收不到进度通知，任务本身照常进行。',
    howToRevoke: '系统设置 → 应用 → 极客匣 → 通知。',
  ),
  PermissionNote(
    manifestName: 'android.permission.FOREGROUND_SERVICE',
    title: '前台服务',
    why: '让下载、后台播放这类长任务在被切到后台时不被系统回收（Android 14 起要求'
        '声明具体类型，见下面三条）。',
    when: '视频下载、后台/息屏播放、漫画缓存、跨设备传输时。',
    ifDenied: '后台任务随时可能被系统中断，回到前台要重新开始。',
    howToRevoke: '安装时声明的基础权限，系统不提供单独开关。',
  ),
  PermissionNote(
    manifestName: 'android.permission.FOREGROUND_SERVICE_DATA_SYNC',
    title: '前台服务：数据同步',
    why: '声明下载/传输这类前台服务的具体类型（Android 14+ 的要求）。',
    when: '视频下载、漫画缓存、跨设备传输进行时。',
    ifDenied: '同上：后台任务可能被中断。',
    howToRevoke: '安装时声明的基础权限，系统不提供单独开关。',
  ),
  PermissionNote(
    manifestName: 'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK',
    title: '前台服务：媒体播放',
    why: '声明播放类前台服务的类型，用于后台播放与息屏播放。',
    when: '播放中切到后台或锁屏时。',
    ifDenied: '切到后台或息屏时播放可能被系统中断。',
    howToRevoke: '安装时声明的基础权限，系统不提供单独开关。',
  ),
  PermissionNote(
    manifestName: 'android.permission.MODIFY_AUDIO_SETTINGS',
    title: '音频设置',
    why: '播放器里右侧上下拖动可以调音量，需要改媒体流的音量。',
    when: '播放时用拖动手势调音量。',
    ifDenied: '拖动手势调不了音量，改用手机音量键即可。',
    howToRevoke: '安装时声明的基础权限，系统不提供单独开关。',
  ),
  PermissionNote(
    manifestName: 'android.permission.SYSTEM_ALERT_WINDOW',
    title: '悬浮窗（答题辅助插件）',
    why: '答题辅助插件要把答案显示在题库 App 之上，需要悬浮窗；关闭插件后不需要它。',
    when: '只有你在插件设置里启用答题辅助插件之后。',
    ifDenied: '插件不可用，应用的其它功能完全正常。',
    howToRevoke: '系统设置 → 应用 → 极客匣 → 显示在其他应用上层（悬浮窗），可随时关闭。',
  ),
  PermissionNote(
    manifestName: 'android.permission.BIND_ACCESSIBILITY_SERVICE',
    title: '无障碍服务（答题读屏）',
    why: '答题辅助插件靠它读取屏幕上的题目文字（抗屏蔽），以及按你框选的区域截图'
        '交给**你自己配置的** OCR 地址。系统弹窗把它描述成「查看屏幕上的所有内容并'
        '控制设备」—— 在本应用里它的用途只有读题与截图，不模拟点击、不读其它应用数据。',
    when: '只有你**手动**在系统设置里开启本应用的无障碍服务、并启用答题辅助插件之后；'
        '不开启时它完全不工作。',
    ifDenied: '答题辅助插件不可用（读屏与截图搜题都不可用），其它功能完全正常。',
    howToRevoke:
        '系统设置 → 无障碍 → 已安装的服务 → 极客匣 → 关闭。这是随时可关的开关，'
        '关掉即刻失效。',
  ),
  PermissionNote(
    manifestName: 'android.permission.RECORD_AUDIO',
    title: '麦克风（分贝仪）',
    why: '分贝仪需要读麦克风的振幅来估算环境噪音。振幅**只在本机换算成数字**，不录音、'
        '不上传、不保存音频。',
    when: '只有你在本地工具里点「开始测量」时才会申请；不点就不申请。',
    ifDenied: '分贝仪不可用，应用的其它功能完全正常。',
    howToRevoke: '系统设置 → 应用 → 极客匣 → 权限 → 麦克风；也可以在弹窗里直接拒绝。',
  ),
];
