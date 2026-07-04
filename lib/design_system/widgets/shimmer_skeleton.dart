import 'dart:math';
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════
// Shimmer 骨架屏基座
// ═══════════════════════════════════════════════════════════════════

/// 带动画的 shimmer 光效扫描层
class Shimmer extends StatefulWidget {
  const Shimmer({
    super.key,
    this.duration = const Duration(milliseconds: 1500),
    required this.child,
  });

  final Duration duration;
  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            final pos = _anim.value;
            // 从左到右扫描
            return LinearGradient(
              begin: Alignment(-1.0 + pos * 2.5, 0),
              end: Alignment(-0.6 + pos * 2.5, 0),
              colors: const [
                Color(0xFFEEEEEE),
                Color(0xFFFAFAFA),
                Color(0xFFEEEEEE),
              ],
              stops: const [0.0, 0.45, 0.9],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// 骨架占位块 — 圆角矩形
class ShimmerBlock extends StatelessWidget {
  const ShimmerBlock({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 8,
    this.margin,
  });

  final double? width;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: const Color(0xFFEEEEEE),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 详情页骨架
// ═══════════════════════════════════════════════════════════════════

/// 小说详情页骨架屏
class DetailPageSkeleton extends StatelessWidget {
  const DetailPageSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F3FF),
      body: Shimmer(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 200,
              collapsedHeight: 56,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(color: const Color(0xFFEEEEEE)),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 封面 + 书名区域
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShimmerBlock(
                          width: 88,
                          height: 124,
                          borderRadius: 14,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ShimmerBlock(
                                width: screenWidth * 0.45,
                                height: 20,
                              ),
                              const SizedBox(height: 8),
                              ShimmerBlock(
                                width: screenWidth * 0.3,
                                height: 14,
                              ),
                              const SizedBox(height: 8),
                              ShimmerBlock(
                                width: screenWidth * 0.35,
                                height: 14,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  ShimmerBlock(
                                    width: 40,
                                    height: 22,
                                    borderRadius: 20,
                                  ),
                                  const SizedBox(width: 6),
                                  ShimmerBlock(
                                    width: 50,
                                    height: 22,
                                    borderRadius: 20,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // 简介区域
                    ShimmerBlock(
                      width: 80,
                      height: 16,
                    ),
                    const SizedBox(height: 10),
                    ...List.generate(4, (i) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: ShimmerBlock(
                        width: screenWidth * (0.6 + Random().nextDouble() * 0.35),
                        height: 12,
                        borderRadius: 4,
                      ),
                    )),
                    const SizedBox(height: 24),
                    // 操作按钮
                    ShimmerBlock(
                      width: double.infinity,
                      height: 48,
                      borderRadius: 14,
                    ),
                    const SizedBox(height: 24),
                    // 章节列表区域
                    ShimmerBlock(
                      width: 60,
                      height: 16,
                    ),
                    const SizedBox(height: 10),
                    ...List.generate(8, (i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          ShimmerBlock(
                            width: 18,
                            height: 18,
                            borderRadius: 4,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ShimmerBlock(
                              height: 12,
                              borderRadius: 4,
                            ),
                          ),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 书架页骨架
// ═══════════════════════════════════════════════════════════════════

/// 书架页骨架屏
class BookshelfSkeleton extends StatelessWidget {
  const BookshelfSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 头部标题骨架
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFEEEEEE),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              ShimmerBlock(width: 20, height: 20, borderRadius: 4),
              const SizedBox(width: 8),
              ShimmerBlock(width: 100, height: 18, borderRadius: 4),
              const Spacer(),
              ShimmerBlock(width: 40, height: 14, borderRadius: 4),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Tab 骨架
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              ShimmerBlock(width: 40, height: 14, borderRadius: 4),
              const SizedBox(width: 24),
              ShimmerBlock(width: 40, height: 14, borderRadius: 4),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // 分隔线
        const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
        const SizedBox(height: 16),
        // 列表骨架
        Expanded(
          child: Shimmer(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 6,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _BookshelfTileSkeleton(),
            ),
          ),
        ),
      ],
    );
  }
}

class _BookshelfTileSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEEEEEE),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ShimmerBlock(width: 48, height: 64, borderRadius: 8),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBlock(width: 160, height: 16, borderRadius: 4),
                const SizedBox(height: 6),
                ShimmerBlock(width: 100, height: 12, borderRadius: 4),
                const SizedBox(height: 6),
                Row(
                  children: [
                    ShimmerBlock(width: 50, height: 18, borderRadius: 8),
                    const SizedBox(width: 6),
                    ShimmerBlock(width: 40, height: 18, borderRadius: 8),
                  ],
                ),
              ],
            ),
          ),
          ShimmerBlock(width: 18, height: 18, borderRadius: 9),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 书本列表/搜书结果骨架
// ═══════════════════════════════════════════════════════════════════

/// 搜书结果列表骨架屏
class BookListSkeleton extends StatelessWidget {
  const BookListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Shimmer(
        child: Column(
          children: List.generate(5, (i) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _BookCardSkeleton(),
          )),
        ),
      ),
    );
  }
}

class _BookCardSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEEEEEE),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerBlock(width: 72, height: 96, borderRadius: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBlock(
                  width: screenWidth * 0.45,
                  height: 18,
                  borderRadius: 4,
                ),
                const SizedBox(height: 8),
                ShimmerBlock(
                  width: screenWidth * 0.3,
                  height: 13,
                  borderRadius: 4,
                ),
                const SizedBox(height: 8),
                ShimmerBlock(
                  width: screenWidth * 0.6,
                  height: 32,
                  borderRadius: 8,
                ),
                const SizedBox(height: 8),
                ShimmerBlock(
                  width: screenWidth * 0.5,
                  height: 13,
                  borderRadius: 4,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 阅读器骨架
// ═══════════════════════════════════════════════════════════════════

/// 阅读器加载骨架屏（匹配已有 reader_page 风格）
class ReaderSkeleton extends StatelessWidget {
  const ReaderSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: const Color(0xFFFDFBF7),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Shimmer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: kToolbarHeight + 20),
              // 标题
              ShimmerBlock(width: screenWidth * 0.5, height: 18, borderRadius: 4),
              const SizedBox(height: 24),
              // 正文占位行
              ...List.generate(15, (i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ShimmerBlock(
                  width: screenWidth * (0.5 + (i % 5) * 0.08),
                  height: 14,
                  borderRadius: 4,
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }
}
