import 'package:flutter/material.dart';

// 全局 Drawer Key
final GlobalKey<ScaffoldState> appScaffoldKey = GlobalKey<ScaffoldState>();

// 路由观察器：用于视频首页从详情/播放器返回时刷新“最近播放”
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();