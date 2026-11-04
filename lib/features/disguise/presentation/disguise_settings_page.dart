import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../design_system/app_tokens.dart';
import '../../../design_system/settings_list.dart';
import '../data/disguise_platform.dart';
import '../domain/disguise_session.dart';
import '../domain/disguise_settings.dart';
import 'recovery_code_sheet.dart';
import 'text_prompt_dialog.dart';

/// 「伪装与隐私」设置页。
///
/// 这里要同时说清三件容易被误解的事，否则用户一定会当成 bug：
/// - **应用管理也显示计算器**：`application` 的静态 label/icon 直接写成「计算器」，
///   真身靠 MainActivity 覆写回「极客匣」。所以卸载/安装/权限弹窗都写「计算器」，
///   包名 `top.hpa888.box` 在应用详情里仍可见（改不了）。
/// - **更新会掉妆**：OTA 覆盖安装会把桌面图标重置回「极客匣」，下次启动自愈
///   （[DisguisePlatform.heal]），但更新完那一刻图标确实会变回去一下；
/// - **伪装不是加密**：挡住的是顺手拿起手机的人，挡不住 adb / root / 取证；
/// - **分身穿的是另一份数据**：分身里图标与口令都独立，[DisguisePlatform.isDuplicateApp]
///   报 true 时要在页面上明说。
///
/// 页面自己从 `SharedPreferences` 取存储（而不是构造函数注入）：路由表只接受
/// `WidgetBuilder`，注入实例就得再加一层全局作用域，为一个设置页不值得。
class DisguiseSettingsPage extends StatefulWidget {
  const DisguiseSettingsPage({super.key});

  @override
  State<DisguiseSettingsPage> createState() => _DisguiseSettingsPageState();
}

class _DisguiseSettingsPageState extends State<DisguiseSettingsPage> {
  DisguiseSettings? _settingsStore;
  bool _disguisedOnDesktop = false;
  bool _duplicateApp = false;
  bool _busy = false;
  String? _note;

  DisguiseSettings get _settings => _settingsStore!;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _settingsStore = DisguiseSettings(prefs));
    await _loadPlatformState();
  }

  Future<void> _loadPlatformState() async {
    final disguised = await DisguisePlatform.instance.isDisguised();
    final duplicate = await DisguisePlatform.instance.isDuplicateApp();
    if (!mounted) return;
    setState(() {
      _disguisedOnDesktop = disguised;
      _duplicateApp = duplicate;
    });
  }

  Future<void> _toggleDisguise(bool enabled) async {
    if (enabled && !_settings.hasPin) {
      // 没有口令就开伪装 = 把自己锁在外面（计算器界面无从解锁），先要口令。
      final ok = await _promptPin();
      if (!ok) return;
      // 顺手发一枚恢复码：这是用户最容易接受的时机，也是「后门是否存在」
      // 唯一能被主动告知的时刻。错过这里，后面要他自己去点「生成」。
      if (!_settings.hasRecoveryCode) {
        await _issueRecoveryCode();
        if (!mounted) return;
      }
    }
    setState(() => _busy = true);
    final applied = await DisguisePlatform.instance.setDisguised(enabled);
    await _settings.setEnabled(enabled);
    await DisguisePlatform.instance.setSecureRecents(
      enabled && _settings.secureRecents,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _disguisedOnDesktop = applied ? enabled : !enabled;
      _note = applied
          ? (enabled ? '已切换为「计算器」。回到桌面后如果图标没变，等 1–2 秒让桌面刷新。' : '已恢复「极客匣」图标。')
          : '切换失败：这台手机的桌面可能没有接受图标变更，稍后再试或重启桌面。';
    });
    if (!applied) {
      // 原生没切成功就不要在偏好里留下"已开启"，否则下次启动会把闸门打开
      // 却没有对应的图标，用户会以为应用坏了。
      await _settings.setEnabled(!enabled);
    }
  }

  Future<bool> _promptPin() async {
    final first = await _askPin('设置解锁口令', '4–12 位数字，只你自己知道');
    if (first == null) return false;
    final second = await _askPin('再输一次', '确认刚才的口令');
    if (second == null) return false;
    if (first != second) {
      if (!mounted) return false;
      setState(() => _note = '两次输入不一致，口令没有改动。');
      return false;
    }
    final ok = await _settings.setPin(first);
    if (!mounted) return ok;
    setState(() => _note = ok ? '口令已保存。' : '口令保存失败（存储不可用）。');
    return ok;
  }

  Future<String?> _askPin(String title, String hint) {
    return showTextPrompt(
      context,
      title: title,
      hint: hint,
      obscure: true,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      validate: (value) => DisguiseSettings.isValidPin(value)
          ? null
          : '必须是 ${DisguiseSettings.minPinLength}–'
                '${DisguiseSettings.maxPinLength} 位数字',
    );
  }

  /// 生成（或轮换）恢复码，并把明文给用户抄一次。
  Future<void> _issueRecoveryCode({bool askFirst = false}) async {
    if (askFirst && _settings.hasRecoveryCode) {
      final confirmed = await _confirm(
        '重新生成恢复码',
        '旧的恢复码会立刻作废。如果它抄在纸上或存在别处，记得一并划掉。',
      );
      if (!confirmed || !mounted) return;
    }
    final code = await _settings.issueRecoveryCode();
    if (!mounted) return;
    if (code == null) {
      setState(() => _note = '恢复码生成失败（存储不可用）。');
      return;
    }
    setState(() => _note = '恢复码已更新：旧码作废，新码只显示这一次。');
    await showRecoveryCodeDialog(context, code);
  }

  Future<bool> _confirm(String title, String body) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body, style: const TextStyle(fontSize: 13, height: 1.6)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _pickTrigger() async {
    final picked = await showModalBottomSheet<DisguiseTrigger>(
      context: context,
      backgroundColor: AppTokens.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                '解锁方式',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            for (final option in DisguiseTrigger.values)
              ListTile(
                title: Text(option.label),
                subtitle: Text(
                  option == DisguiseTrigger.equals
                      ? '在计算器里输入口令，然后按 ='
                      : '在计算器里长按 =，弹出口令框',
                ),
                trailing: option == _settings.trigger
                    ? Icon(Icons.check, color: AppTokens.primaryBlue)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(option),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await _settings.setTrigger(picked);
    if (!mounted) return;
    setState(() => _note = '解锁方式：${picked.label}');
  }

  Future<void> _pickRelockMinutes() async {
    const options = <int>[0, 1, 5, 15, 30];
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppTokens.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                '切后台后多久自动上锁',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            for (final minutes in options)
              ListTile(
                title: Text(minutes == 0 ? '不自动上锁' : '$minutes 分钟'),
                trailing: minutes == _settings.relockMinutes
                    ? Icon(Icons.check, color: AppTokens.primaryBlue)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(minutes),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await _settings.setRelockMinutes(picked);
    if (!mounted) return;
    setState(() => _note = picked == 0 ? '不自动上锁。' : '切后台 $picked 分钟后自动上锁。');
  }

  Future<void> _toggleSecureRecents(bool value) async {
    await _settings.setSecureRecents(value);
    await DisguisePlatform.instance.setSecureRecents(
      _settings.enabled && value,
    );
    if (!mounted) return;
    setState(() {});
  }

  void _lockNow() {
    DisguiseSession.instance.lock();
    // 闸门监听 session，这一下会把整棵树换回计算器，本页随之消失。
  }

  @override
  Widget build(BuildContext context) {
    if (_settingsStore == null) {
      return Scaffold(
        backgroundColor: AppTokens.background,
        appBar: AppBar(
          title: const Text('伪装与隐私'),
          backgroundColor: AppTokens.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: AppTokens.background,
      appBar: AppBar(
        title: const Text('伪装与隐私'),
        backgroundColor: AppTokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          SettingsSection(
            title: '伪装',
            children: [
              Material(
                color: Colors.transparent,
                child: SwitchListTile(
                  dense: true,
                  value: _settings.enabled,
                  onChanged: _busy
                      ? null
                      : (value) => unawaited(_toggleDisguise(value)),
                  title: const Text('伪装成计算器'),
                  subtitle: const Text('桌面图标与名称变成「计算器」，打开后先是一支能真算的计算器'),
                ),
              ),
              Divider(height: 1, color: AppTokens.divider),
              SettingsTile(
                icon: Icons.password_outlined,
                title: '解锁口令',
                subtitle: _settings.hasPin
                    ? '已设置（${DisguiseSettings.minPinLength}–${DisguiseSettings.maxPinLength} 位数字）'
                    : '还没设置：开启伪装前必须先设',
                trailingText: _settings.hasPin ? '修改' : '设置',
                trailingTextColor: AppTokens.primaryBlue,
                onTap: () => unawaited(_promptPin()),
              ),
              Divider(height: 1, color: AppTokens.divider),
              SettingsTile(
                icon: Icons.vpn_key_outlined,
                title: '恢复码',
                subtitle: _settings.hasRecoveryCode
                    ? '已生成。忘了口令时，在计算器界面按住结果行 5 秒可重设'
                    : '还没生成：忘了口令就只能清应用数据重装',
                trailingText: _settings.hasRecoveryCode ? '重新生成' : '生成',
                trailingTextColor: AppTokens.primaryBlue,
                onTap: () => unawaited(_issueRecoveryCode(askFirst: true)),
              ),
              Divider(height: 1, color: AppTokens.divider),
              SettingsTile(
                icon: Icons.touch_app_outlined,
                title: '解锁方式',
                subtitle: _settings.trigger == DisguiseTrigger.equals
                    ? '在计算器里输入口令后按 ='
                    : '在计算器里长按 = 弹出口令框',
                onTap: () => unawaited(_pickTrigger()),
              ),
              Divider(height: 1, color: AppTokens.divider),
              SettingsTile(
                icon: Icons.timer_outlined,
                title: '自动上锁',
                subtitle: '切到后台超过设定时间后，回到应用先看到计算器',
                trailingText: _settings.relockMinutes == 0
                    ? '不自动'
                    : '${_settings.relockMinutes} 分钟',
                trailingTextColor: AppTokens.primaryBlue,
                onTap: () => unawaited(_pickRelockMinutes()),
              ),
              Divider(height: 1, color: AppTokens.divider),
              Material(
                color: Colors.transparent,
                child: SwitchListTile(
                  dense: true,
                  value: _settings.secureRecents,
                  onChanged: (value) => unawaited(_toggleSecureRecents(value)),
                  title: const Text('遮住最近任务缩略图'),
                  subtitle: const Text(
                    '默认关闭：系统计算器不遮缩略图，开着会在多任务里显出一张空卡片，'
                    '和真计算器不一样。要隐私再打开（副作用：截图也会被系统拦下）',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsSection(
            title: '状态',
            children: [
              SettingsTile(
                icon: Icons.apps_outlined,
                title: '桌面图标',
                subtitle: _disguisedOnDesktop ? '当前显示为「计算器」' : '当前显示为「极客匣」',
                trailingText: '刷新',
                trailingTextColor: AppTokens.primaryBlue,
                onTap: () => unawaited(_loadPlatformState()),
              ),
              if (_duplicateApp) ...[
                Divider(height: 1, color: AppTokens.divider),
                const SettingsTile(
                  icon: Icons.content_copy_outlined,
                  title: '当前在分身 / 多用户身份下运行',
                  subtitle: '分身里是另一份应用数据：图标、口令、解锁状态都与主身份独立',
                  enabled: false,
                  onTap: null,
                ),
              ],
              Divider(height: 1, color: AppTokens.divider),
              SettingsTile(
                icon: Icons.lock_outline,
                title: '立即上锁',
                subtitle: '马上回到计算器界面，下次进入要重新输口令',
                enabled: _settings.enabled,
                onTap: _settings.enabled ? _lockNow : null,
              ),
            ],
          ),
          if (_note != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTokens.surface,
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                border: Border.all(color: AppTokens.divider),
              ),
              child: Text(
                _note!,
                style: TextStyle(fontSize: 12, color: AppTokens.textSecondary),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTokens.surface,
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              border: Border.all(color: AppTokens.divider),
            ),
            child: Text(
              '说明：\n'
              '· 这是一道障眼法，不是加密。挡住的是顺手拿起手机的人，挡不住 adb / root / 取证工具。\n'
              '· 忘了口令：在计算器界面按住结果行 5 秒，输入恢复码就能重设口令。恢复码只在生成时显示一次，没抄下来这条后门就不存在。\n'
              '· 应用更新会把桌面图标重置回「极客匣」，下次启动会自动切回计算器。\n'
              '· 伪装期间「分享到极客匣」不会出现在系统分享列表里（桌面入口换成了计算器）。\n'
              '· 如果手机自带同名计算器，桌面会出现两个「计算器」图标。\n'
              '· 设置 → 应用管理里，本应用的名字和图标也是「计算器」，搜「极客匣」搜不到；'
              '代价是卸载确认框、覆盖安装弹窗、权限弹窗都会写「计算器」，别认错。\n'
              '· 应用管理里点开详情仍能看到包名 top.hpa888.box —— 这一项改不了。',
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: AppTokens.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
