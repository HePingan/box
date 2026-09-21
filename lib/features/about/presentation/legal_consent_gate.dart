import 'package:flutter/material.dart';

import '../../../design_system/app_tokens.dart';
import '../data/legal_documents.dart';
import 'legal_document_page.dart';

/// 首次启动的协议闸门。
///
/// 设计取舍（都有实际理由）：
///  - **拦返回键**：用 `PopScope(canPop: false)`。不拦的话用户按返回就绕过了
///    闸门直接进应用，同意流程等于没有。
///  - **必须滚到底才能同意**：这不是刁难用户，而是"同意"要有据可依。按钮在
///    没读完时保持禁用并给出提示，而不是藏起来让人以为界面坏了。
///  - **不提供"不同意"进入应用的路径**：不同意只能退出应用。协议本身就是使用
///    前提，给一个"跳过"等于协议不成立。
///  - 正文用 [LegalDocumentPage] 里的同一套渲染组件，避免闸门和复查页两处
///    文案排版不一致。
class LegalConsentGate extends StatefulWidget {
  const LegalConsentGate({
    super.key,
    required this.isReconsent,
    required this.onAccept,
    required this.onDecline,
  });

  /// true 表示"协议已更新，请重新确认"，false 表示首次同意。
  /// 老用户看到"请阅读并同意"会以为应用被重装了，措辞要区分。
  final bool isReconsent;

  /// 同意回调。返回 false 表示写入失败，闸门会提示用户重试而不是假装成功。
  final Future<bool> Function() onAccept;

  final VoidCallback onDecline;

  @override
  State<LegalConsentGate> createState() => _LegalConsentGateState();
}

class _LegalConsentGateState extends State<LegalConsentGate> {
  final ScrollController _controller = ScrollController();

  /// 是否已滚到底。初值 false；若内容比屏幕短（不可滚动），
  /// 首帧后会被置为 true —— 否则短内容永远滚不到底，用户被永久卡住。
  bool _reachedEnd = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    // 内容不足一屏时没有滚动事件，必须在布局完成后主动判一次。
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncReachedEnd());
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() => _syncReachedEnd();

  void _syncReachedEnd() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    // maxScrollExtent == 0 表示内容不可滚动，直接视为已读完。
    // 留 24px 容差：不少设备滚到底会差几个像素，卡在 0.5px 上不给点同意很荒谬。
    final atEnd = position.maxScrollExtent <= 0 ||
        position.pixels >= position.maxScrollExtent - 24;
    if (atEnd != _reachedEnd) {
      setState(() => _reachedEnd = atEnd);
    }
  }

  Future<void> _accept() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final ok = await widget.onAccept();
    if (!mounted) return;
    if (!ok) {
      // 写入失败必须说出来：静默失败的话用户下次启动又被拦，且不知为何。
      setState(() {
        _submitting = false;
        _error = '同意状态保存失败，请重试。若反复失败，请检查设备存储空间。';
      });
    }
    // 成功时不 setState：外层会把闸门整体替换掉。
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isReconsent ? '协议已更新' : '欢迎使用';
    final lead = widget.isReconsent
        ? '我们更新了用户协议与隐私政策，请重新阅读并确认后继续使用。'
        : '在开始使用前，请阅读并同意以下用户协议与隐私政策。';

    // canPop: false —— 不拦返回键，用户按一下就绕过了整个同意流程。
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppTokens.background,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      key: const ValueKey('legal_gate_title'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      lead,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.6,
                        color: AppTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppTokens.surface,
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                    border: Border.all(color: AppTokens.cardBorder),
                  ),
                  child: ListView(
                    key: const ValueKey('legal_gate_scroll'),
                    controller: _controller,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      if (LegalDocuments.isDraft) const LegalDraftBanner(),
                      _docTitle(LegalDocuments.userAgreementTitle),
                      ...LegalDocuments.userAgreement.map(
                        (c) => LegalClauseView(clause: c),
                      ),
                      const Divider(height: 32),
                      _docTitle(LegalDocuments.privacyPolicyTitle),
                      ...LegalDocuments.privacyPolicy.map(
                        (c) => LegalClauseView(clause: c),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '（以上为全文结束）',
                        key: ValueKey('legal_gate_end_marker'),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTokens.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _docTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppTokens.textPrimary,
          ),
        ),
      );

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                key: const ValueKey('legal_gate_error'),
                style: const TextStyle(fontSize: 12, color: AppTokens.danger),
              ),
            ),
          if (!_reachedEnd)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                '请滑动阅读至全文末尾',
                key: ValueKey('legal_gate_scroll_hint'),
                style: TextStyle(fontSize: 12, color: AppTokens.textTertiary),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const ValueKey('legal_gate_accept'),
              // 禁用而非隐藏：按钮消失会让人以为界面出错了。
              onPressed: (_reachedEnd && !_submitting) ? _accept : null,
              child: Text(_submitting ? '正在保存…' : '同意并继续'),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const ValueKey('legal_gate_decline'),
            onPressed: _submitting ? null : widget.onDecline,
            child: const Text(
              '不同意并退出',
              style: TextStyle(color: AppTokens.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}
