// lib/globals.dart
import 'package:flutter/material.dart';

// 把全局控制抽屉的钥匙拿出来单独放这里，断绝循环依赖！
final GlobalKey<ScaffoldState> appScaffoldKey = GlobalKey<ScaffoldState>();