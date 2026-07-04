// 小说源字段名常量 —— 集中管理所有硬编码的 JSON/HTML 字段名映射。
//
// 规则书源（RuleBookSource）在解析不同站点的 JSON 数据时，
// 各字段名可能不同，但语义相同。本文件将这些"别名"集中定义，
// 避免散落在各个 source 文件中导致维护困难。

/// 书名/标题字段别名
const List<String> fieldBookTitle = [
  'name',
  'title',
  'novelName',
  'bookName',
];

/// 作者字段别名
const List<String> fieldAuthor = [
  'author',
  'authorName',
  'writer',
];

/// 简介字段别名
const List<String> fieldIntro = [
  'intro',
  'summary',
  'desc',
  'description',
  'introduction',
];

/// 封面字段别名
const List<String> fieldCover = [
  'coverUrl',
  'cover',
  'img',
  'thumb',
  'imageUrl',
  'image',
];

/// 分类/类别字段别名
const List<String> fieldCategory = [
  'category',
  'kind',
  'className',
  'classname',
  'tags',
];

/// 详情 URL 字段别名
const List<String> fieldDetailUrl = [
  'bookUrl',
  'detailUrl',
  'url',
  'link',
  'href',
];

/// 状态字段别名
const List<String> fieldStatus = [
  'status',
  'bookStatus',
  'isFinish',
];

/// 字数字段别名
const List<String> fieldWordCount = [
  'wordCount',
  'wordNum',
  'words',
  'size',
];

/// 章节列表字段别名
const List<String> fieldChapterList = [
  'chapterList',
  'list',
  'toc',
  'chapters',
];

/// 章节名称字段别名
const List<String> fieldChapterName = [
  'chapterName',
  'name',
  'title',
  'chapName',
];

/// 章节 URL 字段别名
const List<String> fieldChapterUrl = [
  'chapterUrl',
  'url',
  'path',
  'href',
  'link',
];

/// ID 字段别名（用于 bookId / novelId 等）
const List<String> fieldId = [
  'novelId',
  'bookId',
  'id',
  'novelid',
  'bookid',
];

/// 搜索结果的搜索 URL 参数名
const String searchQueryParam = 'wd';

/// 阅读进度相关字段
const List<String> fieldProgress = [
  'lastReadChapterIndex',
  'lastReadChapter',
  'lastChapterIndex',
  'chapterIndex',
  'lastReadTime',
  'readTime',
];

/// 内容字段别名
const List<String> fieldContent = [
  'content',
  'chapterContent',
  'text',
  'body',
  'html',
];

/// 章节总数字段别名
const List<String> fieldChapterCount = [
  'chapterCount',
  'totalChapters',
  'chapterNum',
  'count',
];

/// 目录基础 URL 字段别名
const List<String> fieldChapterBaseUrl = [
  'chapterBaseUrl',
  'baseUrl',
  'rootUrl',
];
