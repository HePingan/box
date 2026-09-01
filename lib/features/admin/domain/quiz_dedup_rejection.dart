/// 服务端查重拒绝的识别与解释。
///
/// 服务端把「更新已有题目」当成「新建题目」来校验唯一性：
/// 拿 `:id` 读出库里那条记录，用它自己的题干去查重，于是撞上自己。
///
/// 两条路都被同一套校验封死：
///   `PATCH /admin/quiz/questions/:id` -> 题干与完整选项集已存在，不能合并覆盖
///   `POST  /admin/quiz/questions`     -> 题干与完整选项集已存在，不能重复创建
///
/// 客户端无法绕过——实测只发 `{"image": url}` 一个字段（请求体里
/// 根本没有题干和选项）也照样被拒，证明查重与请求内容无关。
/// 修复点在服务端，不在这里。
class QuizDedupRejection {
  const QuizDedupRejection._();

  /// 是否是查重拒绝。
  ///
  /// 只认这一类文案，避免把网络错误、鉴权失败也归为查重
  /// （那些是可以重试的，查重不是）。
  static bool matches(String error) {
    if (error.contains('不能合并覆盖') || error.contains('不能重复创建')) {
      return true;
    }
    // 兜住文案微调，但要求同时出现「已存在」和「选项」，
    // 免得「分类名已存在」这类无关冲突被误判。
    return error.contains('已存在') && error.contains('选项');
  }

  /// 给用户看的解释。要能直接转给后端，所以保留原始报错和接口路径。
  static String explain(String rawError) {
    return '服务端拒绝了这次改图：$rawError\n\n'
        '这是服务端的校验缺陷，不是图片或网络的问题：'
        '本次请求只发了 image 一个字段，请求体里没有题干也没有选项，'
        '服务端却拿题目自己的题干去查重，撞上了它自己。\n\n'
        '需要后端修 PATCH /admin/quiz/questions/:id 的唯一性校验，'
        '让它排除 :id 自身那条记录。在此之前，云端已有题目无法补图。';
  }
}
