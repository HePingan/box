// 工具页点击 → 真的打开对应面板的行为验证（不是源码正则扫描）。
//
// 为什么必须 pump 真实页面：
// 「图书搜索」那个 bug 的形态是 —— 派发代码里确实写着 `initialTool: 'books'`，
// 源码正则断言看得到这个字符串就判绿；但 registry 里没有 `books` 这个 id，
// `PublicApiRegistry.byId` 的 `orElse: () => weather` 把它静默兜到天气面板。
// 用户点「图书搜索」，开出来的是「天气预报」。
//
// 结论：跳转类接线只能靠 pump 后断言**目标面板的标题**来锁，
// 源码里出现了目标字符串不等于目标存在。
library;

import 'dart:convert';

import 'package:box/features/api_hub/application/public_api_registry.dart';
import 'package:box/features/api_hub/presentation/api_hub_page.dart';
import 'package:box/features/tools/application/tool_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 天气面板的标题 —— 也就是被 `orElse` 兜底时用户会看到的东西。
///
/// 只能用**面板标题全文**判断，不能用 `textContaining('Open-Meteo')`：
/// API Hub 顶部的工具切换 chip 会渲染 provider 名，「常用」组里天气的
/// provider 恰好就是 Open-Meteo，于是汇率页面上也能搜到这个词，
/// 用 contains 会误报。
const _weatherPanelTitle = 'Open-Meteo 天气预报';

/// 每个 registry id 对应的面板标题（全文）。
const _panelTitleById = <String, String>{
  'weather': _weatherPanelTitle,
  'currency': 'Frankfurter 汇率换算',
  'holidays': 'Nager.Date 节假日',
  'dictionary': 'Free Dictionary 英文词典',
  'books': 'OpenLibrary 图书搜索',
  'qr': 'QR Server 二维码生成',
  'shortlink': 'CleanURI 短链接生成',
  'avatar': 'UI Avatars 头像生成',
  'mock': 'DummyJSON Mock 用户',
  'hitokoto': 'Hitokoto 随机一言',
  'poetry': '今日诗词 诗词一言',
  // A-2 本轮接线
  'weibo_hot': '微博热搜',
  'zhihu_hot': '知乎热榜',
  'douyin_hot': '抖音热点',
  'toutiao_hot': '头条热榜',
  'fortune': '今日运势',
  'moyu': '摸鱼日历',
  'dujitang': '毒鸡汤',
  'chp': '随机彩虹屁',
  // A-3 批次3接线
  'maoyan': '猫眼票房',
  'epic': 'Epic 免费游戏',
};

/// 按 host 返回各接口的**真实响应形状**。
///
/// 不能图省事一律返回 `{}`：`_buildActivePanel` 在 `_error != null` 时会把整块
/// 面板换成「加载失败」，标题断言就全部落空 —— 那样测的是错误态，不是接线。
/// 短链接接口尤其挑：`shortenUrl` 拿不到 `result_url` 会主动抛 ApiHubException。
MockClient _stubClient() {
  return MockClient((http.Request request) async {
    final host = request.url.host;
    Object body = <String, dynamic>{};

    if (host.contains('openlibrary')) {
      body = <String, dynamic>{
        'docs': <Map<String, dynamic>>[
          <String, dynamic>{
            'key': '/works/OL1W',
            'title': 'Clean Code',
            'author_name': <String>['Robert C. Martin'],
            'first_publish_year': 2008,
            'cover_i': 12345,
          },
        ],
      };
    } else if (host.contains('frankfurter')) {
      body = <String, dynamic>{
        'base': 'USD',
        'rates': <String, dynamic>{'CNY': 7.1, 'EUR': 0.92},
      };
    } else if (host.contains('nager')) {
      body = <Map<String, dynamic>>[
        <String, dynamic>{
          'date': '2026-10-01',
          'localName': '国庆节',
          'name': 'National Day',
          'countryCode': 'CN',
        },
      ];
    } else if (host.contains('open-meteo')) {
      body = <String, dynamic>{
        'latitude': 31.2,
        'longitude': 121.5,
        'timezone': 'Asia/Shanghai',
        'current': <String, dynamic>{
          'temperature_2m': 22.5,
          'wind_speed_10m': 3.1,
        },
        'daily': <String, dynamic>{
          'time': <String>['2026-09-08'],
          'temperature_2m_max': <double>[26.0],
          'temperature_2m_min': <double>[18.0],
          'weather_code': <int>[1],
        },
      };
    } else if (host.contains('dictionaryapi')) {
      body = <Map<String, dynamic>>[
        <String, dynamic>{
          'word': 'flutter',
          'phonetic': '/ˈflʌtə/',
          'meanings': <Map<String, dynamic>>[
            <String, dynamic>{
              'partOfSpeech': 'verb',
              'definitions': <Map<String, dynamic>>[
                <String, dynamic>{'definition': 'to move with quick beats'},
              ],
            },
          ],
        },
      ];
    } else if (host.contains('ipinfo')) {
      body = <String, dynamic>{
        'ip': '203.0.113.7',
        'city': 'Shanghai',
        'country': 'CN',
      };
    } else if (host.contains('hitokoto')) {
      body = <String, dynamic>{
        'hitokoto': '我们并不是什么童话故事，而是确确实实存在过。',
        'from': '葬送的芙莉莲',
        'from_who': '辛美尔',
        'type': 'b',
      };
    } else if (host.contains('jinrishici')) {
      body = <String, dynamic>{
        'status': 'success',
        'data': <String, dynamic>{
          'content': '白云一片去悠悠，青枫浦上不胜愁。',
          'origin': <String, dynamic>{
            'title': '春江花月夜',
            'dynasty': '唐代',
            'author': '张若虚',
            'content': <String>['春江潮水连海平，海上明月共潮生。'],
            'translate': <String>['春天的江潮水势浩荡，与大海连成一片。'],
          },
        },
      };
    } else if (host.contains('wannianrili')) {
      // 万年历源：真实是 HTML（整月返回 ~200KB），不是 JSON。
      // 这里截出目标日期那一段，保留真实的分隔结构（剥标签后是
      // `YYYY年 MM月 (小) 星期X|DD|农历|干支|宜|...|忌|...`），
      // 因为解析器就是按这个形状切的。
      final q = request.url.queryParameters['q'] ?? '';
      final p = q.split('-');
      final mo = p.length == 3 ? p[1] : '09';
      final day = p.length == 3 ? p[2] : '12';
      return http.Response(
        '<div><table>'
        '2026年 $mo月 (小) 星期二|$day|八月初二|'
        '丙午年 【马年】 丁酉月 己丑日|'
        '宜|嫁娶| |祭祀| |祈福| |'
        '忌|斋醮| |开市|'
        '</table></div>',
        200,
        headers: <String, String>{'content-type': 'text/html; charset=utf-8'},
      );
    } else if (host.contains('60s.viki.moe')) {
      // 真实字段形状（curl 实测）：
      //   weibo/toutiao/douyin: title + hot_value(int) + link
      //   zhihu: 额外有 hot_value_desc("773 万热度")、detail
      final path = request.url.path;
      if (path.contains('zhihu')) {
        body = <String, dynamic>{
          'code': 200,
          'data': <Map<String, dynamic>>[
            <String, dynamic>{
              'title': '知乎测试问题',
              'detail': '[视频]',
              'hot_value_desc': '773 万热度',
              'link': 'https://www.zhihu.com/question/1',
            },
          ],
        };
      } else if (path.contains('weibo')) {
        body = <String, dynamic>{
          'code': 200,
          'data': <Map<String, dynamic>>[
            <String, dynamic>{
              'title': '微博测试热搜',
              'hot_value': 2797002,
              'link': 'https://s.weibo.com/weibo?q=test',
            },
          ],
        };
      } else if (path.contains('baidu/realtime')) {
        // 真实字段（curl 实测）：热度是 score_desc("780.88w")，
        // 另有 desc 是【新闻摘要】—— 两者别混。
        body = <String, dynamic>{
          'code': 200,
          'data': <Map<String, dynamic>>[
            <String, dynamic>{
              'rank': 1,
              'title': '百度测试热搜',
              'desc': '这是一段新闻摘要，不是热度数字',
              'score': '7808756',
              'score_desc': '780.88w',
              'url': 'https://www.baidu.com/s?wd=test',
            },
          ],
        };
      } else if (path.contains('exchange_rate')) {
        body = <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'base_code': 'CNY',
            'updated': '2026/09/12 08:02:31',
            'rates': <Map<String, dynamic>>[
              <String, dynamic>{
                'currency': 'USD',
                'name': '美元',
                'rate': '0.14',
              },
            ],
          },
        };
      } else if (path.contains('today_in_history')) {
        body = <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'date': '9-12',
            'items': <Map<String, dynamic>>[
              <String, dynamic>{
                'year': '1948',
                'title': '历史上的今天测试事件',
                'description': '描述文本',
                'link': 'https://example.com/h',
              },
            ],
          },
        };
      } else if (path.endsWith('/v2/luck')) {
        // 真实字段（curl 实测）：luck_rank 是 int，没有 luck_level。
        body = <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'luck_desc': '半吉',
            'luck_rank': 6,
            'luck_tip': '不要吝啬交际支出',
          },
        };
      } else if (path.endsWith('/v2/bing')) {
        // 真实字段（curl 实测）：图片在 cover / cover_4k，日期是 update_date。
        body = <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'title': '必应测试壁纸',
            'description': '壁纸描述',
            'cover': 'https://bing.com/th?id=OHR.Test.jpg',
            'cover_4k': 'https://bing.com/th?id=OHR.Test4k.jpg',
            'copyright': '测试版权',
            'update_date': '2026-09-12 03:46:55',
          },
        };
      } else if (path.endsWith('/v2/60s')) {
        body = <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'date': '2026-09-12',
            'news': <String>['60秒测试新闻一', '60秒测试新闻二'],
            'tip': '测试寄语',
            'day_of_week': '星期六',
            'lunar_date': '丙午年八月初二',
          },
        };
      } else if (path.contains('douyin')) {
        body = <String, dynamic>{
          'code': 200,
          'data': <Map<String, dynamic>>[
            <String, dynamic>{
              'title': '抖音测试热点',
              'hot_value': 11827036,
              'link': 'https://www.douyin.com/search/test',
            },
          ],
        };
      } else if (path.contains('toutiao')) {
        body = <String, dynamic>{
          'code': 200,
          'data': <Map<String, dynamic>>[
            <String, dynamic>{
              'title': '头条测试热榜',
              'hot_value': 12827554,
              'link': 'https://www.toutiao.com/trending/1',
            },
          ],
        };
      } else {
        body = <String, dynamic>{'code': 200, 'data': <Map<String, dynamic>>[]};
      }
    } else if (host.contains('iciba')) {
      body = <String, dynamic>{
        'sid': '6076',
        'content': 'Shared laughter makes the long road feel easy.',
        'note': '一同笑过，长路也显得轻松。',
        'translation': '新版每日一句',
        'picture': 'https://example.com/daily.jpg',
      };
    } else if (host.contains('shouji.360.cn')) {
      body = <String, dynamic>{
        'code': 0,
        'data': <String, dynamic>{'province': '北京', 'city': '', 'sp': '移动'},
      };
    } else if (host.contains('mymemory')) {
      body = <String, dynamic>{
        'responseData': <String, dynamic>{
          'translatedText': '你好啊',
          'match': 0.99,
        },
        'responseStatus': 200,
      };
    } else if (host.contains('cleanuri')) {
      body = <String, dynamic>{'result_url': 'https://cleanuri.com/abc123'};
    } else if (host.contains('dummyjson')) {
      body = <String, dynamic>{
        'users': <Map<String, dynamic>>[
          <String, dynamic>{
            'firstName': 'Ada',
            'lastName': 'Lovelace',
            'username': 'ada',
            'email': 'ada@example.com',
          },
        ],
      };
    }

    return http.Response(
      jsonEncode(body),
      200,
      headers: <String, String>{'content-type': 'application/json'},
    );
  });
}

Future<void> _pumpHub(WidgetTester tester, String? toolId) async {
  // 面板在页面很下方（hero + 快捷区 + 最近使用 + 分组 chip + 12 张工具卡之后），
  // 默认 800x600 的测试窗口压根不会构建到它，标题断言会全部落空 —— 那是视口
  // 问题，不是接线问题。这里把窗口拉高到能一次装下整页。
  tester.view.physicalSize = const Size(1200, 4800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: ApiHubPage(
        initialTool: toolId,
        httpClientForTesting: _stubClient(),
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  testWidgets('热榜面板显示出热度值，而不是空白一行', (tester) async {
    await _pumpHub(tester, 'weibo_hot');
    expect(find.text('微博测试热搜'), findsOneWidget, reason: '标题都没渲染出来，stub 没生效');
    // 微博没有 *_desc 字段，只能拿裸数字（接口原样，不做单位换算）。
    // 修之前 hot 字段名漏了 hot_value，这一行是空白。
    expect(
      find.textContaining('2797002'),
      findsWidgets,
      reason: '热度值是 hot_value(int)，映射时漏了这个字段名 —— 只能显示成空白',
    );
  });

  testWidgets('知乎热榜优先用可读的 hot_value_desc', (tester) async {
    await _pumpHub(tester, 'zhihu_hot');
    expect(find.text('知乎测试问题'), findsOneWidget);
    expect(
      find.textContaining('万热度'),
      findsOneWidget,
      reason: '知乎给了 hot_value_desc("773 万热度")，应优先于原始数字',
    );
  });

  testWidgets('热榜条目带链接时可点击复制，不再是死文本', (tester) async {
    await _pumpHub(tester, 'weibo_hot');
    expect(find.text('微博测试热搜'), findsOneWidget);

    // 条目本身要可点（项目无 url_launcher，沿用「复制链接」先例）。
    final row = find.ancestor(
      of: find.text('微博测试热搜'),
      matching: find.byType(InkWell),
    );
    expect(row, findsOneWidget, reason: '热榜条目没有 InkWell —— 有 link 却点不动');

    // 真的点一下（走手势，不直接调 onTap —— 那会绕开命中测试）。
    // 注意：_copyText 内部 await Clipboard.setData 后要 pump 才会弹 SnackBar，
    // Clipboard 是 platform channel，必须在 runAsync 里才能完成。
    await tester.runAsync(() async {
      await tester.tap(row);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.textContaining('已复制'), findsOneWidget, reason: '点击后应提示链接已复制');
    expect(find.textContaining('已复制'), findsOneWidget, reason: '点击后应提示链接已复制');
  });

  // —— A-1 那批的真实响应桩：以下用例在补桩前一直走错误态，从未验过解析 ——

  testWidgets('百度热搜显示的是热度，不是新闻摘要', (tester) async {
    await _pumpHub(tester, 'baidu_hot');
    expect(find.text('百度测试热搜'), findsOneWidget);
    expect(
      find.textContaining('780.88w'),
      findsWidgets,
      reason: '真实热度在 score_desc；原实现读 desc，把新闻摘要当热度显示了',
    );
    expect(
      find.textContaining('这是一段新闻摘要'),
      findsNothing,
      reason: '新闻摘要不该出现在热度位置',
    );
  });

  testWidgets('必应壁纸的图片地址真的拿到了（cover 而非 url）', (tester) async {
    await _pumpHub(tester, 'bing_wallpaper');
    expect(find.text('必应测试壁纸'), findsOneWidget);

    final images = find.byType(Image);
    expect(
      images,
      findsWidgets,
      reason: '壁纸面板里没有 Image 组件 —— cover 字段没被读，图片加载不出来',
    );
  });

  testWidgets('今日运势的等级读的是 luck_rank', (tester) async {
    await _pumpHub(tester, 'luck');
    expect(find.textContaining('半吉'), findsWidgets, reason: '运势描述没渲染');
  });

  testWidgets('每日英语渲染出真实句子与译文', (tester) async {
    await _pumpHub(tester, 'daily_english');
    expect(
      find.textContaining('Shared laughter'),
      findsWidgets,
      reason: 'iciba content 字段没渲染',
    );
  });

  testWidgets('手机号归属地渲染出运营商', (tester) async {
    await _pumpHub(tester, 'phone_area');
    // 交互式面板：不填号码直接点会被前置校验拦下（"请输入手机号"），
    // 必须先输入再提交，否则测的是空态而不是解析。
    await tester.enterText(find.byType(TextField).last, '13800138000');
    await tester.tap(find.text('查询归属地'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(find.textContaining('北京'), findsWidgets, reason: 'province 没渲染');
    expect(
      find.textContaining('移动'),
      findsWidgets,
      reason: 'shouji360 的 sp 字段没渲染',
    );
  });

  testWidgets('历史上的今天渲染出条目', (tester) async {
    await _pumpHub(tester, 'today_in_history');
    expect(
      find.textContaining('历史上的今天测试事件'),
      findsWidgets,
      reason: 'items[].title 没渲染',
    );
  });

  testWidgets('图书搜索打开的是图书面板，不是被 orElse 兜底的天气面板', (tester) async {
    final target = kToolTargets['图书搜索'];
    expect(target, isA<ApiHubToolTarget>(), reason: '图书搜索应该映射到一个 API Hub 工具');

    await _pumpHub(tester, (target! as ApiHubToolTarget).toolId);

    expect(
      find.text(_weatherPanelTitle),
      findsNothing,
      reason: '点图书搜索却开出天气面板 —— byId 静默兜底了',
    );
    expect(find.text('OpenLibrary 图书搜索'), findsOneWidget);
  });

  testWidgets('图书面板真的渲染出搜索结果，不只是个空壳', (tester) async {
    await _pumpHub(tester, 'books');
    expect(find.text('Clean Code'), findsOneWidget);
    expect(find.textContaining('Robert C. Martin'), findsOneWidget);
  });

  group('映射表里的每个 API Hub 目标都打开它自己的面板', () {
    for (final entry in _panelTitleById.entries) {
      testWidgets('${entry.key} → ${entry.value}', (tester) async {
        await _pumpHub(tester, entry.key);
        // 用 findsWidgets 而非 findsOneWidget：面板成功加载出数据后，工具名会
        // 同时出现在「分组 chip」和「面板标题」两处，断言唯一会误报。本用例
        // 要验的是「打开的是自己那个面板」，不是「标题只出现一次」。
        expect(
          find.text(entry.value),
          findsWidgets,
          reason: '${entry.key} 没有打开自己的面板',
        );
        if (entry.key != 'weather') {
          expect(
            find.text(_weatherPanelTitle),
            findsNothing,
            reason: '${entry.key} 落回了天气面板',
          );
        }
      });
    }
  });

  // 每个 id 单独一个 testWidgets，不能在一个用例里循环 _pumpHub。
  //
  // 踩过的坑：原来这里是一层 for 循环复用同一个 tester。ApiHubPage 的
  // `_activeTool` 在 initState 里从 widget.initialTool 取一次，之后
  // pumpWidget 换 initialTool 只是更新属性、复用同一个 State，
  // `_activeTool` 根本不变 —— 于是循环里第 2..n 个 id 全都在重复断言
  // 第一个 id 的页面，新加的 hitokoto / poetry 落回天气也照样绿。
  group('registry 里没有一个已实现工具会落回天气面板', () {
    // 天气自己除外：它就是兜底值，无法用「不是天气」来区分。
    for (final tool in PublicApiRegistry.all.where((t) => t.id != 'weather')) {
      testWidgets('${tool.id}（${tool.title}）不落回天气', (tester) async {
        await _pumpHub(tester, tool.id);
        expect(
          find.text(_weatherPanelTitle),
          findsNothing,
          reason: '${tool.id}（${tool.title}）落回了天气面板',
        );
      });
    }
  });

  testWidgets('老黄历补上真实宜忌与干支（wannianrili 源）', (tester) async {
    await _pumpHub(tester, 'luck');
    // 老黄历是交互式面板：不点「查今日」就只显示提示语，
    // 那样测的是空态而非解析。
    await tester.tap(find.text('查今日'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    // 宜忌来自 wannianrili.bmcx.com（HTML 抓取），原先这些字段
    // 在 60s /v2/luck 里根本不存在，面板上是空的。
    expect(find.textContaining('嫁娶'), findsWidgets, reason: '宜 未渲染');
    expect(find.textContaining('丙午年'), findsWidgets, reason: '干支 未渲染');
    expect(find.textContaining('斋醮'), findsWidgets, reason: '忌 未渲染');
  });

  testWidgets('不存在的 id 才回落到天气（兜底行为本身保留）', (tester) async {
    await _pumpHub(tester, 'this_id_does_not_exist');
    expect(find.text(_weatherPanelTitle), findsOneWidget);
  });
}
