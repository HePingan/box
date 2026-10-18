# 第四轮：3000 行级文件拆分（2026-10-18）

> 承接第三轮待办第 3 条。三个 agent 并行（本地工具 / 在线漫画 / 工具页），
> 主 agent 负责本地工具、集成与护栏修复。

## 一、结果

| 文件 | 拆分前 | 拆分后 |
|---|---|---|
| `local_tool_panels.dart` | **3772** | 176（主）+ 4 part（693/818/1030/1085） |
| `comic_online_page.dart` | **3223** | 711（主）+ 4 part（461/564/764/776） |
| `api_hub_page.dart` | **2904** | 679（主）+ 5 part（121/396/403/616/755） |

拆分后全部在 1100 行以下，主文件都在 700 行左右。

## 二、一个关键的技术发现（两个 agent 独立验证）

**不能用 `extension ... on _State`**（仓库里 `image_generator` 是那种写法）：

`setState` 是 `State` 的 **protected** 成员，只有 `State` 子类**和
`on` 类型是它的 mixin** 才允许调用。extension 挂在 State 子类上调用 `setState`
会触发 `invalid_use_of_protected_member`（漫画页实测约 30 条警告），
外加 `unqualified_reference_to_static_member_of_extended_type` 硬错误。

采用的形状：

```dart
abstract class _XxxStateBase extends State<Xxx> { /* 字段 + 共用核心 */ }
mixin _XxxReaderMixin on _XxxStateBase { ... }
mixin _XxxBrowseMixin on _XxxReaderMixin { ... }
class _XxxState extends _XxxStateBase
    with _XxxReaderMixin, _XxxBrowseMixin { /* initState/dispose/build */ }
```

链式 `on` 保持同一库作用域，私有成员照旧可用；被后声明的簇调用、但在前面簇里
实现的方法，在基类里声明成 abstract。

## 三、拆分暴露的系统性问题：护栏会静默失效

这是本轮最有价值的发现。本仓有 **50+ 个「读源码做断言」的护栏**，代码一挪地方，
护栏还盯着老路径。两种失效：

| 断言类型 | 失效方式 | 危险度 |
|---|---|---|
| 「必须出现」 | 挪走后找不到 → 红 | 低（会被发现） |
| 「不许出现」 | 挪走后找不到 → **永远绿** | **高（静默）** |

本轮实际抓到 3 处：

1. `local_tool_page_layout_test` 读 `local_tool_panels.dart` 找
   `_DecibelPanelBodyState`（分贝仪护栏）→ 改为扫整个 presentation 目录。
2. `about_content_accuracy_test` 读同一文件找「显示的名字是 极客匣」
   （权限文案与实际应用名一致）→ 改为扫目录。
3. `dark_shell_sources_test` 的白名单点名 `comic_online_page.dart` 豁免
   （沉浸式黑底白控件），代码进了 `*_reader_chrome.part.dart` → 白名单跟着走。
   **刻意只放 reader_chrome**，不放开整个前缀 —— 那等于给拆分后的文件开后门。

### 新增元护栏

`test/lint/source_guard_paths_exist_test.dart`：

1. 扫 `test/` 里所有写死的 `lib/**.dart` 字面量，要求文件真实存在
   （负向断言如「那份重复实现必须不存在」按上下文豁免）。
2. 扫 `lib/` 里所有 `*.part.dart`，要求同目录有主文件确实 `part` 了它
   —— 漏了 `part` 的 part 文件根本不参与编译，类被引用时才报错，没人引用就永久静默。

局限如实写在文件里：只能发现「路径不存在」，发现不了「路径存在但内容搬走了」。

## 四、行为保真的证据

- **api_hub**：脚本切分 + 断言切片拼回去与原文件**逐字节一致**；随后把每个 part
  的正文抽出来再与原始切片 diff，4 个全部 IDENTICAL。
- **comic**：对每一行非空行做多重集比较，3014 行原始内容中**只有 2 行未复现**
  （`static String _describe` 签名、旧的 class 声明行）。唯一文本改动是
  `static String _describe` → `String _describe`（mixin 不能无限定地引用扩展类型的
  静态成员，而该方法不碰实例状态，4 个调用点全都逐字节不变）。

## 五、验证

| 项 | 结果 |
|---|---|
| `flutter analyze` | **10 issues**（与基线一致，零新增） |
| 全量测试 | **4607 通过 / 3 跳过 / 0 失败**（本轮起点 4605） |
| 新增测试 | 2 条元护栏 |

## 六、提交

```
b2cae80 test(lint): 元护栏——源码级护栏引用的路径必须存在
4521eaf refactor(api-hub): 工具页 2904 行拆成主文件 + 5 个 part
14f3a01 refactor(comic): 在线漫画页 3223 行拆成主文件 + 4 个 part
cfb0e6f refactor(local-tools): 3772 行拆成主文件 + 4 个 part
```

已推送 `origin/master`（`4003fbd..b2cae80`）。

## 七、仍待办

1. **全量测试偶发失败**：`test/utils/local_secret_codec_test.dart` 在并行全量时
   偶发（单独跑与目录跑均稳定）。属既有时序问题。
2. **图片工具剩余 7 条**（压缩/格式转换/水印/拼接等）：需图像编解码依赖。
3. **音乐阶段 2/3**：接入 `HomePluginArea.music` 分区；本地扫描需 MediaStore 权限。
