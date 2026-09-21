import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:box/design_system/app_tokens.dart';
import 'package:box/tool_web_page.dart';

import '../../domain/custom_site.dart';
import '../../domain/custom_site_store.dart';

/// 工具页「我的收藏」区块。
///
/// 刻意不复用 `ExpandableCategoryCard`：那个卡片的数据模型是 `List<String>`
/// （只有工具名，没有 URL），硬把自定义网址塞进去要么丢 URL、要么污染所有
/// 内置分类的模型。独立区块的改动面小得多。
class CustomSiteSection extends StatefulWidget {
  const CustomSiteSection({super.key, this.store});

  /// 允许注入，便于 widget 测试替换持久化。
  final CustomSiteStore? store;

  @override
  State<CustomSiteSection> createState() => _CustomSiteSectionState();
}

class _CustomSiteSectionState extends State<CustomSiteSection> {
  late final CustomSiteStore _store = widget.store ?? CustomSiteStore();
  List<CustomSite> _sites = const <CustomSite>[];
  bool _loading = true;
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final sites = await _store.load();
    if (!mounted) return;
    setState(() {
      _sites = sites;
      _loading = false;
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _open(CustomSite site) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ToolWebPage(title: site.title, url: site.url),
      ),
    );
  }

  Future<void> _showAddSheet() async {
    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('添加网站'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: urlCtrl,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: '网址',
                  hintText: 'example.com 或 https://example.com',
                ),
                validator: (value) {
                  final probe = CustomSite.tryCreate(
                    title: 'probe',
                    url: value ?? '',
                  );
                  // 校验直接复用领域层，避免 UI 和存储两套规则各判一套。
                  return probe == null ? '请填写有效的 http/https 网址' : null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: '名称（留空则用域名）'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (submitted != true) return;
    final added = await _store.add(title: titleCtrl.text, url: urlCtrl.text);
    if (added == null) {
      _toast('网址无效，没有保存');
      return;
    }
    await _reload();
    _toast('已收藏 ${added.title}');
  }

  Future<void> _confirmRemove(CustomSite site) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除收藏'),
        content: Text('删除「${site.title}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _store.remove(site.id);
    await _reload();
  }

  Future<void> _shareAll() async {
    if (_sites.isEmpty) {
      _toast('还没有收藏可以分享');
      return;
    }
    // 复制到剪贴板而不是拉起系统分享：这份 JSON 的用途是贴给朋友，
    // 剪贴板在所有机型上行为一致，也不引入新依赖。
    await Clipboard.setData(
      ClipboardData(text: CustomSiteShare.encode(_sites)),
    );
    _toast('已复制 ${_sites.length} 条收藏，粘贴发给朋友即可');
  }

  Future<void> _importFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text ?? '';
    if (raw.trim().isEmpty) {
      _toast('剪贴板是空的');
      return;
    }
    final incoming = CustomSiteShare.decode(raw);
    if (incoming.isEmpty) {
      _toast('剪贴板里没有可导入的网址');
      return;
    }
    final added = await _store.importAll(incoming);
    await _reload();
    _toast(
      added == 0
          ? '这 ${incoming.length} 条都已经收藏过了'
          : '导入 $added 条（共识别 ${incoming.length} 条）',
    );
  }

  @override
  Widget build(BuildContext context) {
    // 用 Material 而不是带白底的 Container 承载：ListTile 会把背景与水波纹
    // 画在最近的 Material 祖先上，中间夹一个有 color 的 DecoratedBox 会把
    // 这些效果整个盖掉 —— 表现是列表项点下去没有任何反馈。
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7ECF5)),
        boxShadow: AppTokens.shadowSm(color: AppTokens.violet),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        gradient: AppTokens.violetGradient,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.bookmark_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '我的收藏',
                            style: TextStyle(
                              color: AppTokens.textPrimary,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            _loading
                                ? '加载中'
                                : (_sites.isEmpty
                                      ? '添加你常用的网站，可导出分享'
                                      : '${_sites.length} 个网站'),
                            style: const TextStyle(
                              color: AppTokens.textSecondary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '添加网站',
                      icon: const Icon(Icons.add_rounded, size: 20),
                      onPressed: _showAddSheet,
                    ),
                    PopupMenuButton<String>(
                      tooltip: '更多',
                      icon: const Icon(Icons.more_horiz_rounded, size: 20),
                      onSelected: (value) {
                        if (value == 'share') _shareAll();
                        if (value == 'import') _importFromClipboard();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'share', child: Text('复制分享内容')),
                        PopupMenuItem(value: 'import', child: Text('从剪贴板导入')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded && !_loading) ...[
              if (_sites.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Text(
                    '点右上角 ＋ 添加第一个网站。收藏会随「本地备份」一起导出，也能复制成一段文本发给朋友。',
                    style: TextStyle(
                      color: AppTokens.textSecondary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                )
              else
                ..._sites.map(
                  (site) => ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.public_rounded,
                      size: 18,
                      color: AppTokens.violet,
                    ),
                    title: Text(
                      site.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      site.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    onTap: () => _open(site),
                    trailing: IconButton(
                      tooltip: '删除',
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      onPressed: () => _confirmRemove(site),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
