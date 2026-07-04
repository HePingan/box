import 'kuaiyan_novel_source.dart';
import 'maoyan_novel_source.dart';
import 'novel_source.dart';
import 'rule_novel_source.dart';
import 'wtzw_novel_source.dart';

class NovelSourceFactory {
  static NovelSource fromBookSourceJson(Map<String, dynamic> json) {
    if (WtzwNovelSource.supportsBookSourceJson(json)) {
      return WtzwNovelSource.fromBookSourceJson(json);
    }

    if (MaoYanNovelSource.supportsBookSourceJson(json)) {
      return MaoYanNovelSource.fromBookSourceJson(json);
    }

    if (KuaiYanNovelSource.supportsBookSourceJson(json)) {
      return KuaiYanNovelSource.fromBookSourceJson(json);
    }

    return RuleNovelSource.fromBookSourceJson(json);
  }
}
