import 'package:flutter/material.dart';

class ToolCategory {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconBgColor;
  final List<String> tools;
  bool isExpanded;

  ToolCategory({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconBgColor,
    required this.tools,
    this.isExpanded = false,
  });
}

List<ToolCategory> createDefaultToolCategories() {
  return [
    ToolCategory(
      title: '日常工具',
      subtitle: '每日资讯、实用工具',
      icon: Icons.wb_sunny_outlined,
      iconBgColor: const Color(0xFF5A728D),
      isExpanded: true,
      tools: [
        '每日早报',
        '每日一文',
        '每日英语',
        '央视新闻',
        '步数修改',
        '在线翻译',
        '菜谱大全',
        '全国降水量',
        '历史上的今天',
        '节假日查询',
      ],
    ),
    ToolCategory(
      title: '系统操作',
      subtitle: '涉及系统相关的工具',
      icon: Icons.settings_applications_outlined,
      iconBgColor: const Color(0xFF587A9A),
      tools: [
        'APK提取',
        'APK.1安装器',
        '系统界面调节',
        '系统字体调节',
        '屏幕坏点检测',
        '提取手机壁纸',
        '空文件夹清理',
        '扬声器清灰',
        '动态视频壁纸',
        '查看设备信息',
        '刻度尺',
        '指南针',
        '水平仪',
        '分贝仪',
        '秒表',
        '计时器',
        '时间屏幕',
      ],
    ),

    // 👉 图片工具里第一个加上了 “在线PS”
    ToolCategory(
      title: '图片工具',
      subtitle: '图片处理相关的工具',
      icon: Icons.image_outlined,
      iconBgColor: Colors.teal,
      tools: [
        '在线PS',
        '图片压缩',
        '格式转换',
        '九宫格切图',
        '水印添加',
        '老照片修复',
        '黑白上色',
        '图片拼接',
        '壁纸提取',
      ],
    ),

    ToolCategory(
      title: '查询工具',
      subtitle: 'Query tools · 34个工具',
      icon: Icons.search_outlined,
      iconBgColor: const Color(0xFF4C5B99),
      tools: [
        '快递查询',
        '天气预报',
        'IP地址查询',
        '国内可用API',
        'Open-Meteo天气',
        '归属地查询',
        '老黄历',
        '成语词典',
        '近义词查询',
        '垃圾分类',
      ],
    ),
    ToolCategory(
      title: '提取工具',
      subtitle: '各大平台资源提取',
      icon: Icons.file_download_outlined,
      iconBgColor: Colors.blueAccent,
      tools: ['短视频去水印', '图集提取', '网页音频提取', 'B站封面提取', '文案提取', '图片文字识别'],
    ),
    ToolCategory(
      title: '开发工具',
      subtitle: '程序猿专属工具',
      icon: Icons.code,
      iconBgColor: Colors.deepPurple,
      tools: [
        'JSON格式化',
        '正则测试',
        'DummyJSON测试数据',
        '国内API清单',
        'Base64编解码',
        'MD5加密',
        '时间戳转换',
        '网页源码获取',
        'URL编码',
        '进制转换',
      ],
    ),
    ToolCategory(
      title: '文本工具',
      subtitle: 'Text tools · 39个工具',
      icon: Icons.text_fields,
      iconBgColor: const Color(0xFF7A8CD0),
      tools: [
        '汉字查询',
        '颜文字',
        '文本编辑器',
        '随机密码',
        '随机一言',
        '诗词一言',
        '随机一文',
        '六十秒读世界',
        '史上今日',
        '搜题',
        '翻译',
        '滚动弹幕',
        '历史上的今天',
        '藏头诗生成',
        '随机彩虹屁',
        '舔狗日记',
        '毒鸡汤',
        '笑话语录',
        '渣男语录',
        '随机弱智吧问答',
        '猜成语生成',
        '随机人设',
        '脑筋急转弯',
        '随机沙雕新闻',
      ],
    ),
    ToolCategory(
      title: '计算工具',
      subtitle: '各类计算换算',
      icon: Icons.calculate_outlined,
      iconBgColor: Colors.orange,
      tools: [
        '科学计算器',
        '亲戚称呼计算',
        '汇率换算',
        'API能力中心',
        '房贷计算器',
        'BMI计算',
        '单位换算',
        '大小写转换',
        '日期计算',
      ],
    ),
    ToolCategory(
      title: '其他工具',
      subtitle: '更多好玩的应用',
      icon: Icons.grid_view,
      iconBgColor: Colors.blueGrey,
      tools: ['摩斯密码', '二维码生成', '条形码扫描', 'LED字幕', '随机数生成', '手持弹幕', '全屏时钟'],
    ),
    ToolCategory(
      title: '趣味游戏',
      subtitle: '休闲娱乐小游戏',
      icon: Icons.sports_esports_outlined,
      iconBgColor: Colors.redAccent,
      tools: ['扫雷', '2048', '数字华容道', '五子棋', '贪吃蛇', '迷宫', '数独'],
    ),
  ];
}
