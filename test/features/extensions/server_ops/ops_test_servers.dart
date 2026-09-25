// 服务器运维插件用例共用的假服务器 / 假设置（B1 多服务器模型）。
//
// 为什么集中一份：五个文件页用例原本各自抄了一份一模一样的 `ServerOpsSettings`，
// 多服务器模型一改就得同步改五处 —— 抄错一处就是"用例绿着、行为变了"。
//
// 口径：
//   * 地址与真实构建默认值一致（这样断言里出现的就是用户真会看到的地址），
//     但用例一律注入假服务/假传输，**不会有任何真实请求**；
//   * 口令只放进内存缓存（对应"从加密存储读出来的那一刻"），不落盘。
import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';

/// 主服务端（阿里云 hpa888）。
const ServerOpsServer testPrimaryServer = ServerOpsServer(
  id: 'hpa888',
  label: '阿里云 · 主服务端',
  baseUrl: 'https://box.hpa888.top/dav',
  user: 'boxops',
  terminalUrl: 'https://box.hpa888.top/term/',
  snapshotId: 'hpa888',
);

/// 构建 / 监控机（腾讯云 175，经 hpa888 的 nginx location 暴露）。
const ServerOpsServer testSecondaryServer = ServerOpsServer(
  id: 'tencent175',
  label: '腾讯云 · 构建/监控机',
  baseUrl: 'https://box.hpa888.top/dav175',
  user: 'boxops',
  terminalUrl: 'https://box.hpa888.top/term175/',
  snapshotId: 'tencent175',
);

/// 一台机器、口令已配：单服务器时代那些用例的等价物。
const ServerOpsSettings testSettingsPrimary = ServerOpsSettings(
  servers: [testPrimaryServer],
  selectedServerId: 'hpa888',
  passwords: {'hpa888': 'pw'},
);

/// 两台机器、都配了口令、当前停在 175 上：切换类用例用。
const ServerOpsSettings testSettingsOnSecondary = ServerOpsSettings(
  servers: [testPrimaryServer, testSecondaryServer],
  selectedServerId: 'tencent175',
  passwords: {'hpa888': 'pw', 'tencent175': 'pw'},
);

/// 主服务器、口令与**设备令牌**都配好：写档（解压 / 权限属主 / 服务启停）用例用。
///
/// 令牌与口令是两套凭据 —— 只配口令的用例不该走只读接口，配了令牌的才会发 POST。
const ServerOpsSettings testSettingsWithApiToken = ServerOpsSettings(
  servers: [testPrimaryServer],
  selectedServerId: 'hpa888',
  passwords: {'hpa888': 'pw'},
  apiTokens: {'hpa888': 'tk'},
);
