import 'dart:async';
import 'package:flutter/material.dart';
import 'reader_controller.dart';

class ReaderDirectorySheet extends StatefulWidget {
  const ReaderDirectorySheet({
    super.key,
    required this.controller,
    required this.bgColor,
    required this.textColor,
  });

  final ReaderController controller;
  final Color bgColor;
  final Color textColor;

  @override
  State<ReaderDirectorySheet> createState() => _ReaderDirectorySheetState();
}

class _ReaderDirectorySheetState extends State<ReaderDirectorySheet>
    with SingleTickerProviderStateMixin {
  static const double _itemHeight = 54.0;
  static const double _indicatorHeight = 46.0;

  final ScrollController _scrollController = ScrollController();
  
  // 👉 性能优化绝招：使用极轻量的 Notifier 单独控制滚动条位置，彻底脱离复杂的组件树重绘
  final ValueNotifier<double> _scrollRatioNotifier = ValueNotifier(0.0);

  bool _reversed = false;
  bool _jumpScheduled = false;
  bool _isDragging = false; // 标记是否正在被手指拖拽，拖动时挂起列表自身的重绘通知

  AnimationController? _fadeController;
  Timer? _hideIndicatorTimer;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    // 监听列表真实滚动，实时轻量更新滚动条百分比（非拖拽状态下才听列表的）
    _scrollController.addListener(() {
      if (!_isDragging && _scrollController.hasClients) {
        final maxExt = _scrollController.position.maxScrollExtent;
        if (maxExt > 0) {
          _scrollRatioNotifier.value = (_scrollController.offset / maxExt).clamp(0.0, 1.0);
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _showIndicator();
        _hideIndicatorWithDelay();
      }
    });
  }

  @override
  void dispose() {
    _hideIndicatorTimer?.cancel();
    _fadeController?.dispose();
    _scrollController.dispose();
    _scrollRatioNotifier.dispose();
    super.dispose();
  }

  void _showIndicator() {
    _hideIndicatorTimer?.cancel();
    if (_fadeController != null &&
        _fadeController!.status != AnimationStatus.forward &&
        _fadeController!.status != AnimationStatus.completed) {
      _fadeController!.forward();
    }
  }

  void _hideIndicatorWithDelay() {
    _hideIndicatorTimer?.cancel();
    _hideIndicatorTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted && _fadeController != null) {
        _fadeController!.reverse();
      }
    });
  }

  void _scheduleJumpNearCurrent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _jumpNearCurrent();
    });
  }

  void _jumpNearCurrent() {
    if (!_scrollController.hasClients) return;
    final total = widget.controller.totalChapters;
    if (total <= 0) return;

    final visualIndex = _reversed
        ? (total - 1 - widget.controller.chapterIndex)
        : widget.controller.chapterIndex;

    final targetOffset = ((visualIndex - 4).clamp(0, total - 1)) * _itemHeight;
    final maxExtent = _scrollController.position.maxScrollExtent;
    
    _scrollController.jumpTo(
      targetOffset.toDouble().clamp(0.0, maxExtent),
    );
  }

  // 👉 全新设计：极致丝滑的拖拽滑块
  Widget _buildSmoothDragHandle() {
    final total = widget.controller.totalChapters;
    if (total <= 0 || _fadeController == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        // 防止初次渲染还未拿到高度时的除零错误
        final areaHeight = constraints.maxHeight <= 0 ? 100.0 : constraints.maxHeight;
        final availableTravel = areaHeight - _indicatorHeight;

        void handleDrag(double localDy) {
          if (!_scrollController.hasClients || availableTravel <= 0) return;
          _showIndicator();
          
          final dy = localDy - (_indicatorHeight / 2);
          final ratio = (dy / availableTravel).clamp(0.0, 1.0);
          
          // 1. 让小滑块瞬间跟手（不经过事件循环队列排队等待）
          _scrollRatioNotifier.value = ratio;
          
          // 2. 指挥庞大的列表去跳跃
          _scrollController.jumpTo(
            _scrollController.position.maxScrollExtent * ratio,
          );
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque, // 热区全黑箱拦截，防止误触底层列表
          onVerticalDragDown: (d) {
            _isDragging = true;
            handleDrag(d.localPosition.dy);
          },
          onVerticalDragUpdate: (d) => handleDrag(d.localPosition.dy),
          onVerticalDragEnd: (_) {
            _isDragging = false;
            _hideIndicatorWithDelay();
          },
          onVerticalDragCancel: () {
            _isDragging = false;
            _hideIndicatorWithDelay();
          },
          child: FadeTransition(
            opacity: _fadeController!,
            child: SizedBox(
              width: 44, // 👉 大大增加感应宽度防脱手！右侧留出空白方便捏合
              height: areaHeight,
              child: ValueListenableBuilder<double>(
                valueListenable: _scrollRatioNotifier,
                builder: (context, ratio, child) {
                  // 👉 使用 GPU 硬件级的位移加速，彻底干掉因 setState 带来的卡顿
                  return Transform.translate(
                    offset: Offset(0.0, ratio * availableTravel),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: child,
                      ),
                    ),
                  );
                },
                child: Container(
                  width: 24,
                  height: _indicatorHeight,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.arrow_drop_up_rounded, size: 20, color: Colors.white),
                      Icon(Icons.arrow_drop_down_rounded, size: 20, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final total = controller.totalChapters;

        if (!_jumpScheduled) {
          _jumpScheduled = true;
          _scheduleJumpNearCurrent();
        }

        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.78,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 20, 12),
                  child: Row(
                    children: [
                      Text(
                        '目录',
                        style: TextStyle(
                          color: widget.textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${controller.chapterIndex + 1}/$total',
                        style: TextStyle(
                          color: widget.textColor.withOpacity(0.55),
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      
                      GestureDetector(
                        onTap: total <= 0
                            ? null
                            : () {
                                setState(() => _reversed = !_reversed);
                                if (_scrollController.hasClients) {
                                  _scrollController.jumpTo(0.0);
                                  _scrollRatioNotifier.value = 0.0;
                                }
                                _showIndicator();
                                _hideIndicatorWithDelay();
                              },
                        child: Text(
                          _reversed ? '正序' : '倒序',
                          style: TextStyle(
                            color: widget.textColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: widget.textColor.withOpacity(0.08)),
                Expanded(
                  child: total <= 0
                      ? Center(
                          child: Text(
                            '暂无章节',
                            style: TextStyle(
                              color: widget.textColor.withOpacity(0.55),
                            ),
                          ),
                        )
                      : Stack(
                          children: [
                            NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                if (notification is ScrollStartNotification ||
                                    notification is ScrollUpdateNotification) {
                                  _showIndicator();
                                } else if (notification is ScrollEndNotification) {
                                  if (!_isDragging) _hideIndicatorWithDelay();
                                }
                                return false; 
                              },
                              child: ListView.builder(
                                controller: _scrollController,
                                itemCount: total,
                                itemExtent: _itemHeight,
                                // 👉 只使用很弱的弹簧效果，防止与拖拽打架造成闪烁
                                physics: const ClampingScrollPhysics(), 
                                itemBuilder: (_, i) {
                                  final visualIndex = _reversed ? total - 1 - i : i;
                                  final chapter = controller.detail.chapters[visualIndex];
                                  final current = visualIndex == controller.chapterIndex;

                                  return Container(
                                    height: _itemHeight,
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: widget.textColor.withOpacity(0.04),
                                          width: 1,
                                        ),
                                      ),
                                    ),
                                    child: ListTile(
                                      dense: true,
                                      selected: current,
                                      title: Text(
                                        chapter.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: current ? Colors.orange : widget.textColor,
                                          fontWeight: current ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                      trailing: current
                                          ? const Icon(
                                              Icons.my_location_rounded,
                                              size: 16,
                                              color: Colors.orange,
                                            )
                                          : null,
                                      onTap: () {
                                        Navigator.pop(context, visualIndex);
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
                            
                            // 高性能物理渲染悬浮滚动条
                            Positioned(
                              top: 0,
                              bottom: 0,
                              right: 0,
                              width: 44, // 配合扩大的感应热区
                              child: _buildSmoothDragHandle(),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}