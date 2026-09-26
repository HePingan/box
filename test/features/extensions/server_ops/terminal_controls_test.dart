// 服务器运维插件：「终端」页纯逻辑的用例（A6）。
//
// 为什么要这么测：终端页的交互全在 WebView 里，而 WebView 在单测里起不来
// （构造 WebViewController 需要平台实现，直接抛）。所以把"发出去的指令对不对"
// 全部抽成纯函数在这里验证——真机上 ttyd 是否照单接收属于**未验证**，
// 那部分只能靠真机（方案 A6 的验收标准写的就是真机截图）。
import 'package:box/features/extensions/plugins/server_ops/terminal_controls.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 造一个 WebResourceError：这个类的构造器是公开的 const 构造器，
/// 所以"错误 → 人话"这条映射不用真机也能逐类型跑一遍。
WebResourceError _err(
  WebResourceErrorType? type, {
  int code = -1,
  String description = '',
  bool? isForMainFrame,
}) =>
    WebResourceError(
      errorCode: code,
      description: description,
      errorType: type,
      isForMainFrame: isForMainFrame,
    );

void main() {
  group('辅助键 → 注入片段', () {
    test('每个辅助键都发 keydown + keyup，且打到 xterm 的输入框上', () {
      for (final key in TerminalAuxKey.values) {
        final js = terminalAuxKeyJs(key);
        expect(
          js,
          contains(terminalInputSelector),
          reason: '${key.name} 必须打在 xterm 自己的 textarea 上，打 document 无效',
        );
        expect(js, contains('new KeyboardEvent("keydown"'), reason: key.name);
        expect(
          js,
          contains('new KeyboardEvent("keyup"'),
          reason: '${key.name}：只发 keydown 会让前端以为键一直按着',
        );
        expect(js, contains('"${key.jsKey}"'), reason: '${key.name} 的 key');
        expect(js, contains('"${key.jsKey}"'), reason: '${key.name} 的 code');
        expect(js, contains('keyCode: ${key.keyCode}'), reason: key.name);
      }
    });

    test('默认不带 Ctrl；ctrl:true 时两个事件都带上 ctrlKey', () {
      final plain = terminalAuxKeyJs(TerminalAuxKey.tab);
      expect(plain, contains('ctrlKey: false'));
      expect(plain, isNot(contains('ctrlKey: true')));

      final withCtrl = terminalAuxKeyJs(TerminalAuxKey.arrowLeft, ctrl: true);
      expect(withCtrl, contains('ctrlKey: true'));
      expect(withCtrl, contains('"ArrowLeft"'));
    });

    test('方向键与 Tab 的键值是平台一致的那一套', () {
      // 写错一个字母就是"按了没反应"，且真机上很难看出是注入错了还是页面没收。
      expect(TerminalAuxKey.tab.jsKey, 'Tab');
      expect(TerminalAuxKey.tab.keyCode, 9);
      expect(TerminalAuxKey.arrowUp.jsKey, 'ArrowUp');
      expect(TerminalAuxKey.arrowUp.keyCode, 38);
      expect(TerminalAuxKey.arrowDown.jsKey, 'ArrowDown');
      expect(TerminalAuxKey.arrowDown.keyCode, 40);
      expect(TerminalAuxKey.arrowLeft.jsKey, 'ArrowLeft');
      expect(TerminalAuxKey.arrowLeft.keyCode, 37);
      expect(TerminalAuxKey.arrowRight.jsKey, 'ArrowRight');
      expect(TerminalAuxKey.arrowRight.keyCode, 39);
    });
  });

  group('Ctrl 组合键 → 注入片段', () {
    test('大小写都收，统一注入小写 key + ctrlKey', () {
      final lower = terminalCtrlComboJs('c');
      expect(lower, contains('"c"'));
      expect(lower, contains('"KeyC"'));
      expect(lower, contains('ctrlKey: true'));

      final upper = terminalCtrlComboJs('C');
      expect(upper, contains('"c"'), reason: '大写也要归一到小写，xterm 只认 key:c');
      expect(upper, contains('"KeyC"'));
    });

    test('Ctrl+C 的 keyCode 是 C 的码位（xterm 的 \x03 就靠它）', () {
      expect(terminalCtrlComboJs('c'), contains('keyCode: 67'));
      expect(terminalCtrlComboJs('d'), contains('keyCode: 68'));
      expect(terminalCtrlComboJs('r'), contains('keyCode: 82'));
    });

    test('非单字母直接拒绝（免得拼出一个服务端看不懂的事件）', () {
      expect(() => terminalCtrlComboJs(''), throwsArgumentError);
      expect(() => terminalCtrlComboJs('cd'), throwsArgumentError);
    });

    test('清单里的每一条都能生成合法片段（加一条不会漏改）', () {
      expect(terminalCtrlCombos, isNotEmpty);
      for (final (letter, label) in terminalCtrlCombos) {
        expect(letter.length, 1, reason: label);
        expect(letter, letter.toLowerCase(), reason: label);
        expect(terminalCtrlComboJs(letter), contains('ctrlKey: true'));
      }
    });
  });

  group('粘贴 → 注入片段', () {
    test('文本按 JSON 转义嵌入，引号/换行/反斜杠/中文都不会破坏脚本', () {
      const tricky = 'echo "hi"\nls -l \\\n运维 测试 +.txt';
      final js = terminalPasteJs(tricky);
      // 原文里的换行与引号必须以转义形式出现，否则注入的 JS 会语法错误。
      expect(js, contains(r'\n'));
      expect(js, contains(r'\"'));
      expect(js, contains(r'\\'));
      expect(js, contains('运维 测试 +.txt'));
      // 不能让未转义的换行把语句切断。
      final literalLine = js
          .split('\n')
          .firstWhere((line) => line.contains('var text ='));
      expect(literalLine, contains(r'\n'));
    });

    test('空文本不发注入（返回前先短路）', () {
      final js = terminalPasteJs('');
      expect(js, contains('if (!text)'));
      expect(js, contains('var text = ""'));
    });

    test('三级兜底都对 xterm 有效：term.paste → insertText → 手派发 input', () {
      final js = terminalPasteJs('x');
      expect(js, contains('window.term.paste'));
      expect(js, contains('execCommand("insertText"'));
      expect(js, contains(r'new Event("input"'));
      expect(js, contains(terminalInputSelector));
    });
  });

  group('字号 → 注入片段', () {
    test('按默认为基准算 zoom：默认 1.000，最大 2.000', () {
      expect(
        terminalFontScaleJs(terminalFontSizeDefault),
        contains('"1.000"'),
      );
      expect(terminalFontScaleJs(terminalFontSizeMax), contains('"2.000"'));
    });

    test('越界先夹住再算（传 999 不会写出 zoom 999）', () {
      final js = terminalFontScaleJs(999);
      expect(js, contains('"2.000"'));
      expect(js, isNot(contains('999')));
      expect(terminalFontScaleJs(0), contains('"0.643"'));
    });

    test('缩放后派发 resize，让 xterm 重算行列', () {
      expect(terminalFontScaleJs(20), contains('new Event("resize")'));
    });
  });

  group('字号的解析与边界', () {
    test('默认值就是默认值；解析不了也回默认值（不抛）', () {
      expect(parseTerminalFontSize(null), terminalFontSizeDefault);
      expect(parseTerminalFontSize(''), terminalFontSizeDefault);
      expect(parseTerminalFontSize('abc'), terminalFontSizeDefault);
      expect(parseTerminalFontSize(double.nan), terminalFontSizeDefault);
      expect(parseTerminalFontSize(double.infinity), terminalFontSizeDefault);
      expect(
        parseTerminalFontSize(double.negativeInfinity),
        terminalFontSizeDefault,
      );
    });

    test('上下界夹住：8→9，100→28', () {
      expect(parseTerminalFontSize('8'), terminalFontSizeMin);
      expect(parseTerminalFontSize('100'), terminalFontSizeMax);
      expect(parseTerminalFontSize(8), terminalFontSizeMin);
      expect(parseTerminalFontSize(100), terminalFontSizeMax);
      expect(clampTerminalFontSize(-5), terminalFontSizeMin);
    });

    test('合法值原样通过（老版本存的 int 也要认）', () {
      expect(parseTerminalFontSize('16'), 16);
      expect(parseTerminalFontSize(' 16 '), 16);
      expect(parseTerminalFontSize(20), 20);
      expect(parseTerminalFontSize(17.5), 17.5);
      expect(parseTerminalFontSize(terminalFontSizeMax), terminalFontSizeMax);
      expect(parseTerminalFontSize(terminalFontSizeMin), terminalFontSizeMin);
    });

    test('键名按方案用 serverOps.term. 前缀，与 dav 的键分开', () {
      expect(terminalFontSizeKey, 'serverOps.term.fontSize');
      expect(terminalFontSizeKey, startsWith('serverOps.term.'));
      expect(terminalFontSizeKey, isNot(startsWith('serverOps.dav.')));
    });

    test('存 → 读往返一致；盘上的脏值不会把页面搞崩', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await saveTerminalFontSize(22);
      expect(await loadTerminalFontSize(), 22);

      // 存进去也被夹过界：999 不会原样落盘。
      await saveTerminalFontSize(999);
      expect(await loadTerminalFontSize(), terminalFontSizeMax);

      SharedPreferences.setMockInitialValues(<String, Object>{
        terminalFontSizeKey: '垃圾值',
      });
      expect(await loadTerminalFontSize(), terminalFontSizeDefault);
    });
  });

  group('断线原因 → 中文人话', () {
    test('只有主文档的错才算断线（子资源失败不弹提示）', () {
      expect(terminalErrorIsFatal(_err(WebResourceErrorType.connect, isForMainFrame: true)), isTrue);
      expect(
        terminalErrorIsFatal(_err(WebResourceErrorType.io, isForMainFrame: false)),
        isFalse,
        reason: '字体/图标失败不该让用户以为终端断了',
      );
      expect(
        terminalErrorIsFatal(_err(WebResourceErrorType.unknown)),
        isTrue,
        reason: 'isForMainFrame 未知时宁可多报一条，也别漏掉真正的断线',
      );
    });

    test('四类"下一步该改什么"分得开，不都是「加载失败」', () {
      final timeout = terminalErrorHint(_err(WebResourceErrorType.timeout));
      final auth = terminalErrorHint(_err(WebResourceErrorType.authentication));
      final notFound = terminalErrorHint(_err(WebResourceErrorType.fileNotFound));
      final ssl = terminalErrorHint(_err(WebResourceErrorType.failedSslHandshake));

      expect(timeout, contains('超时'));
      expect(auth, contains('口令'));
      expect(notFound, contains('地址'));
      expect(ssl, contains('证书'));
      expect({timeout, auth, notFound, ssl}, hasLength(4), reason: '四类必须各不相同');
    });

    test('原始描述被带上（真机反馈里自带线索），空描述不留空括号', () {
      final withText = terminalErrorHint(
        _err(WebResourceErrorType.connect, description: 'ERR_CONNECTION_REFUSED'),
      );
      expect(withText, contains('ERR_CONNECTION_REFUSED'));

      final empty = terminalErrorHint(
        _err(WebResourceErrorType.unknown, description: ''),
      );
      expect(empty, isNot(contains('（）')));
      expect(empty, contains('「重连」'));
    });

    test('每个 WebResourceErrorType 都有话说，且没有一条是空的', () {
      for (final type in WebResourceErrorType.values) {
        final hint = terminalErrorHint(_err(type, description: 'x'));
        expect(hint.trim(), isNotEmpty, reason: type.name);
        expect(hint, contains('x'), reason: '${type.name} 应带原始描述');
      }
      final unknown = terminalErrorHint(_err(null));
      expect(unknown.trim(), isNotEmpty);
    });

    test('可恢复的那几类都指向「重连」或设置（给用户一条出路）', () {
      for (final type in <WebResourceErrorType>[
        WebResourceErrorType.timeout,
        WebResourceErrorType.connect,
        WebResourceErrorType.io,
        WebResourceErrorType.webContentProcessTerminated,
        WebResourceErrorType.webViewInvalidated,
        WebResourceErrorType.unknown,
      ]) {
        expect(terminalErrorHint(_err(type)), contains('重连'), reason: type.name);
      }
    });

    test('兜底提示与空剪贴板提示都是中文人话', () {
      expect(terminalWatchdogHint, contains('重连'));
      expect(terminalWatchdogHint, contains('测试连接'));
      expect(terminalClipboardEmptyHint, contains('剪贴板'));
    });
  });

  group('终端认证闸门（口令不对时不许无限转圈）', () {
    test('第一次挑战照常应答，第二次就取消', () {
      final gate = TerminalAuthGate();
      expect(gate.register(), 1);
      expect(gate.shouldAnswer, isTrue, reason: '第一次挑战是正常的');
      expect(gate.register(), 2);
      expect(gate.shouldAnswer, isFalse,
          reason: '同一台机器 realm 固定，再来一次就是口令被拒了');
    });

    test('重新加载要清零，否则"重连"永远取消', () {
      final gate = TerminalAuthGate();
      gate.register();
      gate.register();
      expect(gate.shouldAnswer, isFalse);
      gate.reset();
      expect(gate.challenges, 0);
      expect(gate.register(), 1);
      expect(gate.shouldAnswer, isTrue);
    });

    test('提示要点名"口令那一格"+ 别和设备令牌搞混', () {
      expect(terminalAuthFailedHint, contains('口令'));
      expect(terminalAuthFailedHint, contains('设备令牌'),
          reason: '真机上就是把设备令牌填进了口令格；提示必须点破');
      expect(terminalAuthFailedHint, contains('重连'));
    });
  });
}
