import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/vod_item.dart';

/// 文件功能：利用 Isolate 异步解析大数据量 JSON
/// 实现：将解析任务从 UI 线程搬移到后台线程
class IsolateParser {
  
  // 使用 compute 函数开启临时后台线程
  static Future<List<VodItem>> parseVodList(String jsonBody) async {
    return await compute(_decodeAndMap, jsonBody);
  }

  // 这是运行在后台线程的独立函数
  static List<VodItem> _decodeAndMap(String body) {
    final Map<String, dynamic> data = jsonDecode(body);
    final List<dynamic> list = data['list'] ?? [];
    
    // 在后台线程完成大循环映射
    return list.map((e) => VodItem.fromJson(e)).toList();
  }
}