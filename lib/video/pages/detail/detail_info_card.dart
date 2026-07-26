import 'package:flutter/material.dart';

import '../../models/video_source.dart';
import '../../models/vod_item.dart';

import '../../../design_system/app_tokens.dart';

/// 影片资料卡：纯资料表 + 可折叠简介。
///
/// 封面、标题、总集数/线路等已在页面顶部头部呈现，这里不再重复，
/// 只承载「来源/分类/更新/时间/地区/导演/主演 + 剧情简介」这类次级信息。
class DetailInfoCard extends StatefulWidget {
  const DetailInfoCard({super.key, required this.detail, required this.source});

  final VodItem detail;
  final VideoSource source;

  @override
  State<DetailInfoCard> createState() => _DetailInfoCardState();
}

class _DetailInfoCardState extends State<DetailInfoCard> {
  bool _synopsisExpanded = false;

  // 统一设计 token，避免圆角/描边/间距各处跳变。
  static const double _cardRadius = 20;
  static const double _innerRadius = 12;
  static const Color _border = Color(0xFFE7ECF5);
  static const Color _fill = Color(0xFFF8FAFC);
  static const Color _iconMuted = Color(0xFF94A3B8);

  String? _text(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }

  String? _normalizeSynopsis(String? raw) {
    final sourceText = _text(raw);
    if (sourceText == null) return null;

    var text = sourceText
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");

    text = text
        .replaceAll(RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(
            r'</\s*(p|div|li|section|article|tr|h[1-6])\s*>',
            caseSensitive: false,
          ),
          '\n',
        )
        .replaceAll(RegExp(r'<\s*p[^>]*>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<\s*div[^>]*>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<[^>]+>'), '');

    final lines = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (lines.isEmpty) return null;
    return lines.join('\n');
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: _fill,
        borderRadius: BorderRadius.circular(_innerRadius),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: _iconMuted),
          const SizedBox(width: 8),
          Text(
            '$label：',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTokens.inkDark,
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            // 与选集/播放的金橙强调统一，去掉此前独立的黄色。
            color: const Color(0xFFFB923C),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            color: AppTokens.inkDark,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _buildSynopsis(String synopsis) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('剧情简介'),
        const SizedBox(height: 8),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: Text(
            synopsis,
            maxLines: _synopsisExpanded ? null : 3,
            overflow: _synopsisExpanded
                ? TextOverflow.visible
                : TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 13,
              height: 1.55,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _synopsisExpanded = !_synopsisExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _synopsisExpanded ? '收起' : '展开',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    _synopsisExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: const Color(0xFF64748B),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final synopsis = _normalizeSynopsis(detail.vodContent);
    final category = _text(detail.typeName) ?? '未分类';
    final status = _text(detail.vodRemarks) ?? '未知';
    final time = _text(detail.vodTime) ?? _text(detail.vodYear) ?? '暂无';
    final area = _text(detail.vodArea);
    final lang = _text(detail.vodLang);
    final director = _text(detail.vodDirector);
    final actor = _text(detail.vodActor);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
        // B5：扁平次级卡，无阴影，只用浅描边，把视觉主体让给播放器。
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('影片资料'),
          const SizedBox(height: 12),
          _infoRow(Icons.source_rounded, '来源', widget.source.name),
          const SizedBox(height: 8),
          _infoRow(Icons.category_rounded, '分类', category),
          const SizedBox(height: 8),
          _infoRow(Icons.update_rounded, '更新', status),
          const SizedBox(height: 8),
          _infoRow(Icons.schedule_rounded, '时间', time),
          if (area != null || lang != null) ...[
            const SizedBox(height: 8),
            _infoRow(
              Icons.travel_explore_rounded,
              '地区/语言',
              [area, lang].whereType<String>().join(' · '),
            ),
          ],
          if (director != null) ...[
            const SizedBox(height: 8),
            _infoRow(Icons.movie_creation_rounded, '导演', director),
          ],
          if (actor != null) ...[
            const SizedBox(height: 8),
            _infoRow(Icons.groups_rounded, '主演', actor),
          ],
          if (synopsis != null && synopsis.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildSynopsis(synopsis),
          ],
        ],
      ),
    );
  }
}
