import 'package:flutter/material.dart';

class PublicApiToolDefinition {
  const PublicApiToolDefinition({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.provider,
    required this.group,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String provider;
  final String group;
}

class PublicApiRegistry {
  const PublicApiRegistry._();

  static const weather = PublicApiToolDefinition(
    id: 'weather',
    title: '天气预报',
    subtitle: '国内网络实测最快，免密钥天气接口',
    icon: Icons.wb_cloudy_rounded,
    color: Color(0xFF0EA5E9),
    provider: 'Open-Meteo',
    group: '常用',
  );

  static const currency = PublicApiToolDefinition(
    id: 'currency',
    title: '汇率换算',
    subtitle: '国内网络可用，偶尔响应偏慢',
    icon: Icons.currency_exchange_rounded,
    color: Color(0xFF10B981),
    provider: 'Frankfurter',
    group: '常用',
  );

  static const holidays = PublicApiToolDefinition(
    id: 'holidays',
    title: '节假日查询',
    subtitle: '中国节假日公开数据，国内网络可用',
    icon: Icons.event_available_rounded,
    color: Color(0xFFFF7A45),
    provider: 'Nager.Date',
    group: '常用',
  );

  static const dictionary = PublicApiToolDefinition(
    id: 'dictionary',
    title: '英文词典',
    subtitle: '国内网络实测可用的英文释义接口',
    icon: Icons.translate_rounded,
    color: Color(0xFF8B5CF6),
    provider: 'Free Dictionary',
    group: '文本',
  );

  static const mockData = PublicApiToolDefinition(
    id: 'mock',
    title: 'Mock 用户',
    subtitle: '国内网络实测可用，快速生成用户资料',
    icon: Icons.badge_rounded,
    color: Color(0xFF14B8A6),
    provider: 'DummyJSON Users',
    group: '开发',
  );

  static const qrCode = PublicApiToolDefinition(
    id: 'qr',
    title: '二维码生成',
    subtitle: '文本或链接一键转二维码图片',
    icon: Icons.qr_code_2_rounded,
    color: Color(0xFF7C3AED),
    provider: 'QR Server',
    group: '开发',
  );

  static const avatar = PublicApiToolDefinition(
    id: 'avatar',
    title: '头像生成',
    subtitle: '国内实测可用，按名称生成头像',
    icon: Icons.account_circle_rounded,
    color: Color(0xFF6366F1),
    provider: 'UI Avatars',
    group: '开发',
  );

  static const coverImage = PublicApiToolDefinition(
    id: 'cover',
    title: '随机封面',
    subtitle: '国内实测可用，生成测试封面图',
    icon: Icons.photo_size_select_actual_rounded,
    color: Color(0xFF0EA5E9),
    provider: 'Picsum',
    group: '开发',
  );

  static const shortLink = PublicApiToolDefinition(
    id: 'shortlink',
    title: '短链接生成',
    subtitle: '把长链接压缩为方便分享的短链',
    icon: Icons.link_rounded,
    color: Color(0xFF059669),
    provider: 'CleanURI',
    group: '网络',
  );

  static const ipLookup = PublicApiToolDefinition(
    id: 'ip',
    title: '公网 IP',
    subtitle: '查询当前出口 IP 与基础归属信息',
    icon: Icons.public_rounded,
    color: Color(0xFF2563EB),
    provider: 'IPinfo / IPify',
    group: '网络',
  );

  static const dummyImage = PublicApiToolDefinition(
    id: 'dummy_image',
    title: '占位图生成',
    subtitle: '快速生成设计/开发占位图 URL',
    icon: Icons.image_rounded,
    color: Color(0xFFEC4899),
    provider: 'DummyImage',
    group: '开发',
  );

  static const directory = PublicApiToolDefinition(
    id: 'directory',
    title: '可用 API 清单',
    subtitle: '只展示本轮实测可用的免密钥接口',
    icon: Icons.travel_explore_rounded,
    color: Color(0xFFF59E0B),
    provider: 'local curated list',
    group: '目录',
  );

  static const all = [
    weather,
    currency,
    holidays,
    ipLookup,
    shortLink,
    dictionary,
    mockData,
    qrCode,
    avatar,
    coverImage,
    dummyImage,
    directory,
  ];

  static const groups = ['常用', '网络', '文本', '开发', '目录'];

  static PublicApiToolDefinition byId(String id) {
    return all.firstWhere((tool) => tool.id == id, orElse: () => weather);
  }
}
