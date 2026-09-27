// 内置漫画源：包子漫画（Legado 书源格式，来源：用户提供的「包子漫画.json」，2026-09-27）。
//
// 为什么以「配置」形态放在 App 里而不是把站点逻辑写死在代码里：
//   * 站点有 WAF，规则会随站点改版失效 —— 规则是数据，改数据不该等发版（Step 4 会做成
//     从服务器热更新；本轮先内置，保证自检与后续在线的规则与这份书源逐字一致）。
//   * 只保留运行需要的字段：Legado 专有的 UI/统计字段（customOrder、weight、respondTime…）
//     与本 App 无关，去掉以免误导读者以为它们生效。
//
// 已知边界（写在这里，免得后面靠猜）：
//   * `init` / `chapterList` 里的 `java.t2s`（繁转简）本 App **不实现** —— 需要词表，
//     先只影响繁体章节的显示，不影响取数。
//   * `ruleBookInfo.tocUrl` 里的 `@harf@` 是这个书源自身的笔误；本 App 直接用详情页的
//     章节链接（已实测 1211 章可读），不依赖这条规则。
const String kSeedComicSourceJson = r'''
{
  "mirrors": ["https://cn.baozimhcn.com", "https://cn.bzmgcn.com", "https://www.baozimh.com"],
  "bookSourceName": "包子漫画（优）",
  "bookSourceUrl": "https://cn.baozimhcn.com",
  "bookSourceType": 2,
  "searchUrl": "https://cn.baozimhcn.com/search?q={{key}}",
  "exploreUrl": "<js>\nvar sort = [];\nvar push = function(title, url, type1, type2) {\n    sort.push({\n        title: title,\n        url: url,\n        style: {\n            layout_flexGrow: type1,\n            layout_flexBasisPercent: type2\n        }\n    });\n};\n\nvar typeNames = [\"全部\", \"恋爱\", \"纯爱\", \"古风\", \"异能\", \"悬疑\", \"剧情\", \"科幻\", \"奇幻\", \"玄幻\", \"穿越\", \"冒险\", \"推理\", \"武侠\", \"格斗\", \"战争\", \"热血\", \"搞笑\", \"大女主\", \"都市\", \"总裁\", \"后宫\", \"日常\", \"韩漫\", \"少年\", \"其它\"];\nvar types = [\"all\",\"lianai\",\"chunai\",\"gufeng\",\"yineng\",\"xuanyi\",\"juqing\",\"kehuan\",\"qihuan\",\"xuanhuan\",\"chuanyue\",\"mouxian\",\"tuili\",\"wuxia\",\"gedou\",\"zhanzheng\",\"rexie\",\"gaoxiao\",\"danuzhu\",\"dushi\",\"zongcai\",\"hougong\",\"richang\",\"hanman\",\"shaonian\",\"qita\"];\n\ntypeNames.forEach(function(item, index) {\n    var url = \"https://cn.baozimhcn.com/api/bzmhq/amp_comic_list?type=\" + types[index] + \"&region=all&filter=&page={{page}}&limit=36&language=cn&__amp_source_origin=https%3A%2F%2Fcn.baozimhcn.com\";\n    push(item, url, 1, 0.25);\n});\nJSON.stringify(sort)\n</js>",
  "header": "@js:\nJSON.stringify({\n\"Accept-Language\": \"zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7\"\n})",
  "ruleSearch": {
    "author": "class.tags text-truncate@text",
    "bookList": "class.comics-card pure-u-1-2 pure-u-sm-1-2 pure-u-md-1-4 pure-u-lg-1-6",
    "bookUrl": "class.comics-card pure-u-1-2 pure-u-sm-1-2 pure-u-md-1-4 pure-u-lg-1-6@tag.a@href",
    "coverUrl": "tag.amp-img.0@src",
    "kind": "class.tabs cls@text",
    "lastChapter": "class.comics-chapters__item.0@text",
    "name": "class.comics-card__title text-truncate@text"
  },
  "ruleBookInfo": {
    "author": "class.comics-detail__author@text",
    "coverUrl": "tag.amp-img.0@src",
    "init": "<js>java.t2s(result)</js>",
    "intro": "class.comics-detail__desc overflow-hidden@text",
    "kind": "class.tag-list@text",
    "lastChapter": "class.comics-chapters__item.0@text",
    "name": "class.comics-detail__title@text",
    "tocUrl": "class.pure-u-1-1 pure-u-sm-1-2 pure-u-md-1-3 pure-u-lg-1-4 comics-chapters@tag.a@harf@class.comics-chapters__item@text"
  },
  "ruleExplore": {
    "author": "$.author",
    "bookList": "$.items[*]",
    "bookUrl": "https://cn.baozimhcn.com/comic/{{$.comic_id}}",
    "coverUrl": "https://static-tw.baozimhcn.com/cover/{{$.topic_img}}",
    "kind": "$.type_names",
    "name": "$.name"
  },
  "ruleToc": {
    "chapterList": "<js>java.t2s(result)</js>\nclass.pure-u-1-1 pure-u-sm-1-2 pure-u-md-1-3 pure-u-lg-1-4 comics-chapters",
    "chapterName": "tag.span@text",
    "chapterUrl": "tag.a@href"
  },
  "ruleContent": {
    "content": "@js:\nlet n =java.getElements('class.comic-contain@amp-img')\nlet c=[];\n    Array.from(n).forEach(x=>{\n    c.push({\n    link:x.attr('data-src')\n})    \n}) \nvar imgTags = c.map(item => `<img src=\"${item.link}\">`).join('\\n');\n    imgTags;",
    "imageStyle": "FULL",
    "title": "class.title"
  },
  "bookSourceComment": "// Error: Connection reset",
  "enabledExplore": true
}
''';
