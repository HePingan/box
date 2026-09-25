// 服务器运维插件：串行传输队列（A2 上传 / A3 批量删除共用）。
//
// 为什么并发恒为 1：手机上行带宽有限，多个大文件同时 PUT 会把每个都拖成"龟速"，
// 还容易触发服务端限流；串行也能让"第 i/n"的进度对用户可预期。
//
// 为什么单独抽成纯函数而不是塞进页面：串行、可取消、失败不打断整批这三条是
// **队列语义**，不是 UI 细节。放在纯 Dart 里可以直接用闭包断言并发数，
// 不必依赖 widget 的帧时序（用 widget 测并发要摆弄 Completer，很脆）。

import 'package:box/features/extensions/plugins/remote_storage/domain/remote_storage_models.dart';

/// 队列里某一项失败了。
class OpsQueueFailure {
  const OpsQueueFailure(this.index, this.error);

  final int index;
  final Object error;
}

/// [runOpsSerialQueue] 的结果。
class OpsQueueResult {
  const OpsQueueResult({
    required this.total,
    required this.succeeded,
    required this.failures,
    required this.canceled,
  });

  final int total;
  final int succeeded;
  final List<OpsQueueFailure> failures;

  /// 用户取消（不是失败）：取消后剩下的项**没有发起**。
  final bool canceled;

  int get failedCount => failures.length;

  bool get allSucceeded => !canceled && failures.isEmpty && succeeded == total;

  /// 给人看的一句结论（成功 / 部分失败 / 已取消）。
  String summary(String noun) {
    if (canceled) {
      return '已取消$noun：完成 $succeeded/$total 项';
    }
    if (failures.isEmpty) {
      return '$noun完成：共 $total 项';
    }
    return '$noun完成 $succeeded/$total 项，失败 ${failures.length} 项';
  }
}

/// 逐项串行执行 [task]（并发恒为 1）。返回统计，不抛错。
///
/// 语义（三条都是验收标准）：
///   * **并发恒为 1**：前一项 `await` 结束才发起下一项；
///   * **取消后不再发起后续项**：每发起一项前检查 [cancel]；在途那一项靠它自己
///     的 `cancel:` 参数中断（传输层会抛 [TransferCanceledException]，被映射成
///     [RemoteStorageError.canceled]）；
///   * **失败不打断整批**：某一项抛出只记录进 [OpsQueueResult.failures]，
///     继续下一项。
///
/// [onStart] 在每项发起前回调一次（UI 用它显示"第 i/n"）。
Future<OpsQueueResult> runOpsSerialQueue({
  required int total,
  required TransferCancelToken cancel,
  required Future<void> Function(int index) task,
  void Function(int index)? onStart,
}) async {
  final failures = <OpsQueueFailure>[];
  var succeeded = 0;
  var canceled = false;

  for (var i = 0; i < total; i++) {
    if (cancel.isCanceled) {
      canceled = true;
      break;
    }
    onStart?.call(i);
    try {
      await task(i);
      succeeded += 1;
    } catch (error) {
      // 取消与失败要分开：取消是用户意愿，不该在"失败 n 项"里报出来。
      if (cancel.isCanceled ||
          error is TransferCanceledException ||
          (error is RemoteStorageException &&
              error.kind == RemoteStorageError.canceled)) {
        canceled = true;
        break;
      }
      failures.add(OpsQueueFailure(i, error));
    }
  }

  return OpsQueueResult(
    total: total,
    succeeded: succeeded,
    failures: failures,
    canceled: canceled,
  );
}
