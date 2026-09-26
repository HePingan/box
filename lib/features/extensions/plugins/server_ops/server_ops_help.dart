// 运维通道的「凭据小抄」：四栏对应关系 + 生成/撤销命令 + 四个坑。
//
// 为什么放进 App 而不是只在服务器上放个文件：用户的原话是"我怕忘记了"——
// 而他随手能翻的是 App；服务器上那份要跨过文件页才能看到。
//
// **这里不许出现任何口令/令牌**（面板会被截屏，这个页面也会被截屏）：
// 只放"怎么做"，不放"是什么"。有专门的用例守着这一条。

/// 小抄全文（设置 → 运维通道设置 → 凭据怎么生成）。
const String opsCredentialHelpText = '''
四栏别填串
  用户名 + 口令            → 文件页、终端
  只读接口地址 + 设备令牌   → 系统页（进程/服务/日志/端口/磁盘/体检）
  两台机器的口令与令牌都不通用，各填各的。

  只读接口地址：主服务端  https://box.hpa888.top/opsapi
                175 那台  https://box.hpa888.top/opsapi175

填错的典型现象
  文件页说"用户名或密码不正确"  → 口令那一格不对（多半把设备令牌填进去了）
  系统页说"这台机器还没接只读接口" → 缺设备令牌
  终端一直转圈                  → 1.20.47 起会直接提示"口令不对"

生成 / 撤销（在 App 的终端页连主服务器就能跑）
  python3 /usr/local/sbin/box_channel_cred.py issue --label 名字 --host 175
  python3 /usr/local/sbin/box_channel_cred.py issue --label 名字 --host 175 --read-only
  python3 /usr/local/sbin/box_channel_cred.py list
  python3 /usr/local/sbin/box_channel_cred.py revoke --label 名字 --host 175
  （--host 可选 hpa888 或 175）

四个坑
  1. 口令只在屏幕上出现一次（"只在下面出现一次"那一行）→ 立刻存进 App；
     服务端只存哈希、不留明文，丢了只能重新签。
  2. 已存在的名字不能重签：换个名字签（App 里"用户名"那格也要改），或先 revoke 再签
     （正在用它的设备会当场失效）。
  3. revoke 吃的是基础名（hpa888-ferry，不是 ro-hpa888-ferry）；撤完用 list 复核那一行真没了。
  4. 只读凭据（--read-only）只能读文件：写不了、也进不了终端（服务端强制）。

进不去任何页面时
  让 Hermes 给这台签一条只读凭据当"过河"：拿它打开文件页 → 读到他放的填报文件 →
  把"用户名 + 口令"两格换成可写的那一对 → 用完让他把只读那条撤掉。
''';

/// 小抄里必须出现的几件事（用例据此守着"别把关键一步漏掉"）。
const List<String> opsCredentialHelpMustMention = <String>[
  '用户名 + 口令',
  '设备令牌',
  'box_channel_cred.py',
  '--read-only',
  'revoke',
  '只存哈希',
];
