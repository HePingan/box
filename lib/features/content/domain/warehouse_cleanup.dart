import 'package:box/core/storage/cache_store.dart';
import 'package:box/features/content/domain/warehouse_models.dart';

/// 手填收藏入口下线后的一次性清理。
///
/// 手填对话框（原 `_showAddDialog`，同时挂在内容页 ＋ 和「导入资源」卡上）写出的
/// 条目 `sourceLabel == '手动收藏'`。入口撤掉后这些条目再没有任何界面能维护它们
/// —— 不能新增也不能编辑，只能干看着，属于死数据，所以随入口一起清掉。
///
/// 清理边界（重要）：
///  * 只碰 [warehouseNamespace] 也就是 `warehouse_center` 这一个 namespace；
///  * 只删 `sourceLabel == '手动收藏'` 的条目；
///  * 书架条目（`sourceLabel == '书架'`）来自 `NovelModule.bookshelf` 实时同步，
///    压根不落在这个 store 里，因此清理伤不到真实书架；影视收藏同理另有存储。
///
/// 单独成文件而不是塞在页面里：清理是一次性数据迁移，和 UI 无关，
/// 放在 domain 层才能被测试直接调用，也方便日后确认「这段能删了没」。
class WarehouseCleanup {
  WarehouseCleanup({CacheStore? cache, WarehouseStore? store})
    : _store =
          store ??
          WarehouseStore(
            cache: cache ?? CacheStore(namespace: warehouseNamespace),
          );

  final WarehouseStore _store;

  /// 执行清理，返回实际删除的条目数。幂等：再调一次返回 0。
  Future<int> run() => _store.purgeManualEntries();
}

/// 手填收藏所在的 CacheStore namespace。
const String warehouseNamespace = 'warehouse_center';
