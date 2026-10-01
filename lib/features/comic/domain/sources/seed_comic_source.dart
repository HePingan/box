// 内置漫画源（Legado 书源格式的子集）。
//
// 为什么以「配置」形态放在 App 里而不是把站点逻辑写死在代码里：
//   * 站点有 WAF，规则会随站点改版失效 —— 规则是数据，改数据不该等发版；
//   * 只保留运行需要的字段：Legado 专有的 UI/统计字段（customOrder、weight、respondTime…）
//     与本 App 无关，去掉以免误导读者以为它们生效。
//
// ── 一览 ─────────────────────────────────────────────────────────
//   * 野蛮漫画（默认）：**手机能直连**（站点挑客户端特征 —— 桌面 UA 会被 307 掉，
//     直连必须带手机 UA，见 comic_fetcher.dart）。取数默认直连；**配了设备令牌才走中转**
//     （`relay` 段）。图片地址在取图接口里，不在 HTML 里 —— 直连与中转共用同一套分批取图。
//   * 包子漫画：站点对手机与机房都丢连接（2026-09-27 起），保留配置仅供参考/自检。
library;

// ── 野蛮漫画（默认源） ─────────────────────────────────────────────
//
// 站点事实（2026-09-28 实测，规则就是照着这些写的，不要凭印象改）：
//   * 搜索：`GET /search?searchkey=<关键字>` → `li.comic-item`（实测「海贼」21 条），
//     书名 `p.title`、书链 `a[href]`（`/book/7530/`）、封面 `img[src]`
//     （在 `tuer.justpic01pt.com:666`，**直连可取**：实测 200 / 48 KB / image/jpeg）。
//   * 详情：`GET /book/<id>/` → 书名 `h1#js_comic-title`、作者 `span.author`、
//     简介 `p#js_desc_content`、目录 `li.comic-chapter-item` 里的 `a`
//     （实测 398 话，`/chapter/7530/772668.html`）。
//     ⚠️ 书名**不能**用 `h1.name`：那个 h1 里嵌着 `<span class="author">`，
//     取 text 会拼成「海贼王~尾田栄一郎」。
//   * 章节取图：图片地址**不在 HTML 里**。章节页有一行 JS
//     `let read={aid:'7530',cid:'772668',apiCid:'772668',picCount:209,…}`，
//     再 `POST /api/comic/read/pics`（表单 `id=<cid>&aid=<aid>&offset=<起点>`）
//     分批取，**一批 5 张**（响应里带 `total`）。所以这份源没有 `ruleContent`
//     —— 用 HTML 规则根本取不到图，写了反而是假的。
const String kSeedComicSourceYemanJson = r'''
{
  "bookSourceName": "野蛮漫画",
  "bookSourceUrl": "https://yemancomic.com",
  "bookSourceType": 2,
  "searchUrl": "https://yemancomic.com/search?searchkey={{key}}",
  "relay": {
    "endpoint": "https://box.hpa888.top/comicrelay/fetch",
    "chapterApi": {
      "pics": "/api/comic/read/pics",
      "index": "/api/comic/read/index"
    }
  },
  "ruleSearch": {
    "bookList": "class.comic-item",
    "name": "class.title@text",
    "bookUrl": "tag.a.0@href",
    "coverUrl": "tag.img@src"
  },
  "ruleBookInfo": {
    "name": "id.js_comic-title@text",
    "author": "class.author@text",
    "coverUrl": "tag.img.0@src",
    "intro": "id.js_desc_content@text",
    "tocUrl": "class.comic-chapter-item@tag.a@text"
  },
  "ruleToc": {
    "chapterName": "tag.a@text",
    "chapterUrl": "tag.a@href"
  },
  "exploreUrl": "全部::https://yemancomic.com/comiclists/9/全部/3/{{page}}.html\n热血::https://yemancomic.com/comiclists/9/热血/3/{{page}}.html\n恋爱::https://yemancomic.com/comiclists/9/爱情/3/{{page}}.html\n纯爱::https://yemancomic.com/comiclists/9/纯爱/3/{{page}}.html\n奇幻::https://yemancomic.com/comiclists/9/奇幻/3/{{page}}.html\n冒险::https://yemancomic.com/comiclists/9/冒险/3/{{page}}.html\n搞笑::https://yemancomic.com/comiclists/9/搞笑/3/{{page}}.html\n悬疑::https://yemancomic.com/comiclists/9/悬疑/3/{{page}}.html\n科幻::https://yemancomic.com/comiclists/9/科幻/3/{{page}}.html\n剧情::https://yemancomic.com/comiclists/9/剧情/3/{{page}}.html\n古风::https://yemancomic.com/comiclists/9/古风/3/{{page}}.html\n校园::https://yemancomic.com/comiclists/9/校园/3/{{page}}.html",
  "ruleExplore": {
    "bookList": "class.comic-item",
    "name": "class.title@text",
    "bookUrl": "tag.a.0@href",
    "coverUrl": "tag.img@src"
  },
  "bookSourceComment": "// 手机直接能访问本站（要带手机 UA，桌面 UA 会被 307 挡）；图在 /api/comic/read/pics（一批 10 张）；配了设备令牌才经自建中转"
}
''';

// ── 包子漫画（保留；当前站点可达性已坏） ─────────────────────────────
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

/// 内置书源清单：**野蛮漫画排第一**（在线页默认选中的就是第一份）。
/// 顺序就是界面上的顺序，也是"默认用哪个源"的答案。
const List<String> kSeedComicSourcesJson = <String>[
  kSeedComicSourceYemanJson,
  kSeedComicSourceJson,
];

/// 内置源的界面备注（键 = 书源名）。只用于**展示**，不影响取数。
///
/// 「漫画源自检」页与在线页的源菜单都读这里，所以每一条都要是**当前仍然成立**的事实，
/// 别把已经过时的判断留在界面上（这类备注用户直接看得到）。
const Map<String, String> kSeedComicSourceNotes = <String, String>{
  '野蛮漫画': '取数默认直连（站点挑客户端特征：手机 UA 才给页面）；配了设备令牌才走中转',
  '包子漫画（优）': '当前在手机网上连不上（连接被重置），列出来仅供参考；'
      '它 ruleBookInfo.tocUrl 第 3 段是自身的笔误，本 App 用详情页的章节链接',
};
