# 伪装计算器界面：按真机资源表对齐（2026-11-15）

被仿对象：`com.android.bbkcalculator` 15.6.1.1（versionCode 15060101）。下面所有数值都
是从 `/root/calc-probe.apk` 的资源表里读出来的，不是估的。取法：

```bash
A=/opt/android-sdk/build-tools/34.0.0/aapt2
$A dump resources calc-probe.apk > /tmp/calc_res.txt     # 资源：布局文件、颜色、dimen、字符串
$A dump xmltree --file res/-w.xml calc-probe.apk         # nex_activity_calculator_port
$A dump xmltree --file res/q4.xml calc-probe.apk         # nex_pad_numeric
$A dump xmltree --file res/g8.xml calc-probe.apk         # nex_pad_operator_one_col
```

资源 ID 到值的对照在 `/tmp/calc_res.txt` 里 `resource 0x... color/xxx` 后面那一行。

## 上一版错在哪

| 项 | 上一版（猜的） | 真机（资源表） |
|---|---|---|
| 符号/等号色 | `#0F77FF`（vivo 系统蓝） | **`#ED4D47`**（`color/symbol_text_color` / `calculator_base_color`） |
| 键位 | 5 行 × 4 列，`AC ⌫ % ÷` 起头 | **6 行 × 4 列**，`mc m+ m− \| mr` 起头 |
| 记忆键 | 无 | mc / m+ / m− / mr |
| 科学键 | 无 | sin/cos/tan/反三角、ln/log、√、π、e、()、x^y、! |
| 顶部按钮 | 无 | 历史、科学计算器切换（各 42dp） |
| 角度模式 | 无 | 显示区左上 `Deg`/`Rad` 12sp `#878787`（`id/mode`） |

`#0F77FF` 那个坑值得记：它在 APK 里出现十几次，但每一处都属于
`originui_button_*_rom15_0` 这样的 **originui 组件库**资源与 `vivo_upgrade_0F77FF`，
不是这支应用自己的调色板。**颜色值出现在资源表里 ≠ 这个应用在用**，得看它挂在哪个
资源名下、以及布局/样式有没有引用它。

## 实测数值（现在是契约测试里钉的）

| 项 | 值 | 出处 |
|---|---|---|
| 屏幕底色 | `#F8F8F8` | `color/calculator_background` |
| 键区底色 | `#FAFAFA` | 布局里 GridLayout 的 `android:background` |
| 公式行 | 48sp `#BF000000`，monospace，右对齐 | `dimen/input_size`、`color/edit_text_color` |
| 结果行 | 28sp `#878787` | `dimen/result_size`、`color/result_text_color` |
| 数字键 | `#595959` 23sp | `color/number_text_color` |
| 符号键（AC/%/±/÷×−+） | `#ED4D47`；AC 21sp、% 与 ± 25sp、运算符 28sp | `color/symbol_text_color`、样式里各 key 的 textSize |
| 记忆键 mc/m+/m−/mr | `#878787` 23sp | `color/m_text_color` |
| 科学函数键 | `#878787` | `color/fun_text_color` |
| `=` 键 | 白字（`color/equal_text_color`）+ `#ED4D47` 实心块，圆角 30dp | `style/rom_four_button_equal_style`、`dimen/radius_size` |
| 按键按下底色 | `#E0E0E0` | `color/number_press_background_color` |
| 键区高度 | 296dp（h612dp 326 / h682dp 386），左右边距 20dp（w390dp 27dp） | `dimen/keybord_height`、`dimen/keybord_margin` |
| 顶部按钮 | 42dp 触区，图标 24dp，距顶 6dp | `dimen/btn_max_size`、`nex_activity_calculator_port` |

键位顺序（`nex_pad_numeric` 三列 + `nex_pad_operator_one_col` 一列，逐行读 XML 得到）：

```
mc   m+   m-   | mr
AC   %    +/-  | ÷
7    8    9    | ×
4    5    6    | −
1    2    3    | +
.    0    ←    | =
```

## 实现

- `lib/features/disguise/domain/calculator_engine.dart`：把内核补成真机能算的地步 ——
  括号、乘方（右结合）、阶乘、`sin/cos/tan/asin/acos/atan/ln/log/√`、常量 `π`/`e`、
  记忆体（mc/m+/m−/mr）、`Deg`/`Rad`。**每个键位都真的能用**，否则就是摆样子。
  三角函数默认按角度制（真机顶部那枚 `Deg`），可切换。
- `lib/features/disguise/presentation/calculator_disguise_page.dart`：布局与配色按上表，
  按键有 `#E0E0E0` 按压反馈（没有反馈会觉得「像假的」）。
- `test/disguise/calculator_disguise_layout_test.dart`：把色值、字号、键位、Deg/Rad、
  记忆键、历史面板、科学键全部钉成契约测试。

## 不可考的部分（如实写下来）

1. **科学键的排列是运行时代码塞进去的**：把所有 `res/*.xml` 里的二进制资源 id 扫了一遍，
   `string/fun_sin`、`fun_cos`、`op_sqrt` 这些只出现在代码里，没有任何布局引用。
   所以真机的科学键长什么样、怎么排，从 APK 里读不出来 —— 我们按同一套视觉语言
   排了三行（`2nd sin cos tan ln` / `π e ( ) √` / `xʸ x² 1/x n!`）。
2. **数字键是否有自己的底色**：`color/number_background_color`（`#F2F2F2`）存在，但
   没有任何 style 引用它，可能是运行时代码画的。现在按键是透明的（只有按下才上色）。
3. **历史记录是否落盘**：我们只留内存（旁人手感一样，不落盘更安全）。
