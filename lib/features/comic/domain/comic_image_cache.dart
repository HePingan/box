// 在线漫画的图片缓存：把章节图落到本地，翻页时先用本地那份。
//
// 三条底线：
//   * 下载失败**如实抛**（由界面显示"这张没下来，点重试"），不静默给占位图；
//   * 同一个地址的并发请求只发一次（翻页来回滑时很常见）；
//   * 缓存目录在系统缓存目录下，用户清缓存/系统清缓存都不会影响别处。
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'comic_image_edges.dart';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

/// 图片缓存：`url → 本地文件`。
///
/// **每一张图都必须有截止时间**（2026-10-01 用户报「封面图一直转圈」就是这里没有上限）：
/// 没有超时的下载会永远停在"转圈"那一态，界面上既没有图、也没有原因 —— 用户只能说
/// "一直转圈"，我这边连是"连不上"还是"下到一半卡住"都分不出来。
class ComicImageCache {
  ComicImageCache({
    this.httpClientFactory,
    Map<String, String> Function(String url)? headerFor,
    Future<Directory> Function()? tempDirProvider,
    this.maxBytes = defaultMaxBytes,
    this.maxFiles = defaultMaxFiles,
    this.pruneEveryWrites = defaultPruneEveryWrites,
    this.connectTimeout = defaultConnectTimeout,
    this.idleTimeout = defaultIdleTimeout,
    this.totalTimeout = defaultTotalTimeout,
    this.alternatePorts = defaultAlternatePorts,
    this.maxAttempts = defaultMaxAttempts,
    this.maxParallel = defaultMaxParallel,
    this.foregroundReserved = defaultForegroundReserved,
    ComicImageEdges? edges,
  }) : edges = edges ?? ComicImageEdges(),
       headerFor = headerFor ?? _noHeaders,
       tempDirProvider = tempDirProvider ?? getTemporaryDirectory;

  /// 可注入（测试用）：默认走 `HttpClient()`。
  final HttpClient Function()? httpClientFactory;

  /// 图床边缘 IP 记忆：域名解析出的 IP 里混着一半死 IP（2026-10-02 实测），
  /// 记住哪个通、失败时直连它 —— 详见 [ComicImageEdges]。
  final ComicImageEdges edges;

  /// 可注入（测试用）：缓存根目录，默认系统临时目录。
  final Future<Directory> Function() tempDirProvider;

  /// 连上图片服务器的上限（连不上要**说出来**，不能一直转圈）。
  final Duration connectTimeout;

  /// 两个数据块之间的最长间隔：这么长时间一个新字节都没有 = 这条连接已经废了。
  ///
  /// 为什么要单独的"闲着"超时：连接被接住了、响应头也回来了，但正文一个字节不来
  /// （移动网上很常见）—— 这种卡死连接不会自己断，靠总时长兜底会让用户白等。
  final Duration idleTimeout;

  /// 整张图（含收字节、落盘）的上限，兜底用。
  final Duration totalTimeout;

  static const Duration defaultConnectTimeout = Duration(seconds: 15);
  static const Duration defaultIdleTimeout = Duration(seconds: 15);
  static const Duration defaultTotalTimeout = Duration(seconds: 90);

  /// 换个端口再试一次（`原端口 → 备选端口`）。
  ///
  /// 2026-10-01 用户报「图床连不上 (tuer.justpic01pt.com)：Connection reset by peer」：
  /// 那本漫画的图床挂在 **`:666`** 上，而 `:666` 在**手机那条网**上会被掐断 —— 同一张图
  /// 换 443 就是好的（实测 `https://tuer.justpic01pt.com/picbed/…` 不带端口返回同一份字节，
  /// 服务器侧也验过 `:666` 与 `:443` 内容一致）。所以直连失败时先自己换端口重试一次，
  /// 用户在运营商封端口时不必等我们发版。
  final Map<int, int> alternatePorts;

  static const Map<int, int> defaultAlternatePorts = {666: 443};

  /// 取**这个地址**的图要带的头（默认空表）。
  ///
  /// 为什么按地址给、而不是一张固定表：图片地址里既有图床（直连取，只要手机 UA），
  /// 也有经自建中转包出来的地址（要 `X-Box-Token`，否则每张 401）。规则见
  /// [comicImageHeadersFor]。令牌仍然**只在请求头**里，不进地址、不进日志。
  final Map<String, String> Function(String url) headerFor;

  static Map<String, String> _noHeaders(String url) => const <String, String>{};

  /// 这张图**最后是用哪个地址取通的**（原地址被掐断时会换端口，见 [alternatePorts]）。
  ///
  /// 自检要拿它说清「是换了端口才通的」：只说"下下来了"，用户下次换台网/换张图又懵；
  /// 说出「原来的 :666 被掐断、443 才通」，才看得懂自己那条网发生了什么。
  final Map<String, String> _usedAddress = {};

  String? usedAddress(String url) => _usedAddress[url];

  final Map<String, Future<File>> _inFlight = {};
  Directory? _dir;

  Future<Directory> _cacheDir() async {
    final cached = _dir;
    if (cached != null) return cached;
    final base = await tempDirProvider();
    final dir = Directory('${base.path}/comic_online_images');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  /// 已经下好的本地文件（没有就 null）。
  Future<File?> cachedFile(String url) async {
    final dir = await _cacheDir();
    final f = File('${dir.path}/${_key(url)}');
    return await f.exists() ? f : null;
  }

  /// 取图：有缓存直接用，没有就下载。**失败抛出**（带原因）。
  ///
  /// [lowPriority]：预取这类"顺手"的活传 true —— 它只占 [foregroundReserved] 之外的名额，
  /// 且**有前台在排队时不抢名额**（见 [_canStart]）。
  ///
  /// [dest]：**离线下载专用** —— 字节直接写进这个文件（调用方给的是离线目录里的路径），
  /// 不进 temp 缓存、也不参与那套 300MB/4000 张的淘汰。其余一模一样：同样的每次连接
  /// 截止时间、同样的 `:666` → 443 换端口、同样的"被掐断就按同一地址重试"。
  /// 这么做的理由：离线下载没必要再写一套取图逻辑，写一套就一定会漏掉上面某一条。
  Future<File> fetch(
    String url, {
    bool lowPriority = false,
    File? dest,
    int? maxAttempts,
  }) {
    final key = url;
    final running = _inFlight[key];
    if (running != null) return running;
    final future = _fetchOnce(
      url,
      low: lowPriority,
      dest: dest,
      attemptBudget: maxAttempts,
    ).whenComplete(() {
      // 注意：这里**必须是块体**（返回 void）。写成 `=> _inFlight.remove(key)`
      // 的话，`whenComplete` 会把"回调的返回值"当成还要再等的 Future —— 而
      // `remove` 返回的正是**这个 Future 自己**，于是它永远在等自己完成。
      //
      // 后果就是 2026-10-01 用户报的形态：图片其实早就下完了（甚至已经落盘），
      // 但 `fetch` 的 Future 永远不 complete —— 封面、阅读页第一张全在转圈，
      // 而自检的"搜索/详情/取图"三步全通（它们不走这里），看着就"说不通"。
      _inFlight.remove(key);
    });
    _inFlight[key] = future;
    return future;
  }

  Future<File> _fetchOnce(
    String url, {
    required bool low,
    File? dest,
    int? attemptBudget,
  }) async {
    if (dest != null) {
      // 离线下载：目标文件已经在了就直接用（**离线下载的续传就靠这一条** ——
      // 不数计数、不认清单里的 done，文件在就算下过，杀进程重启后天然接着下）。
      if (await dest.exists()) return dest;
    } else {
      final existing = await cachedFile(url);
      if (existing != null) return existing;
    }

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      throw ComicImageException('图片地址不合法：$url');
    }
    final host = uri.host.isEmpty ? url : uri.host;

    // 要试的地址队列：先原地址，再换端口的同一张图（见 [alternatePorts]）。
    // 失败是「被掐断」这类**一闪而过**的错时，把原地址再排一次 —— 2026-10-01 用户实测
    // 同样的地址在手机浏览器里能打开，说明那条路本身通，被掐断多半是偶发（图床对同一
    // 来源的短时并发敏感），重试一次往往就成了。
    final queue = Queue<_Candidate>()..addAll(await _candidatesFor(uri));
    final triedIps = <String>{};
    var attempts = 0;
    ComicImageException? last;
    await _acquire(low: low);
    try {
      final budget = attemptBudget ?? maxAttempts;
      while (queue.isNotEmpty && attempts < budget) {
        final candidate = queue.removeFirst();
        attempts++;
        final ip = candidate.ip;
        if (ip != null) triedIps.add(ip);
        try {
          final file = await _transfer(candidate, url, host, dest: dest);
          _usedAddress[url] = candidate.label;
          if (ip != null) {
            // 直连这个 IP 通了：记住它，下次先走它。
            // 实测：走域名 10/15（随机挑 IP，一半是死的），直连好 IP 15/15。
            edges.markGood(host, ip).catchError((_) {});
          }
          return file;
        } on ComicImageException catch (e) {
          // 只有**网络层**的失败才值得换个地址再来一次：HTTP 码、0 字节、地址不合法
          // 再试一百次也是一样的结果。
          if (!e.retryable) rethrow;
          last = e;
          if (ip != null) {
            // 直连这个 IP 也没通：标坏（30 分钟内不再用它），再从没试过的 IP 里
            // 补一个进队列 —— 域名给的那串里一半是死的，换一个试比原地址硬重试有用。
            edges.markBad(host, ip).catchError((_) {});
            final more = await edges
                .fallbackIps(host, tried: triedIps, limit: 1)
                .catchError((_) => const <String>[]);
            final fresh = more.isEmpty ? null : more.first;
            if (fresh != null) queue.add(_Candidate(uri, fresh));
          } else if (e.transient) {
            queue.add(_Candidate(uri, null));
          }
        }
      }
    } finally {
      _release(low: low);
    }
    // 一条都没成：把"试过哪几个端口、试了几次"说出来，用户才知道不是我们没试。
    // 注意**把 transient/retryable 带出去**：聚合之后的这句话才是调用方（离线下载）
    // 看到的错误，丢了标记它就无从判断"值不值得等一会儿重来"。
    throw ComicImageException(
      '${last!.message}（${_triedLabel(uri)}共试了 $attempts 次）',
      retryable: last.retryable,
      transient: last.transient,
    );
  }

  /// 最多试几个地址（原地址 + 换端口 + 补一次原地址）。
  final int maxAttempts;

  static const int defaultMaxAttempts = 3;

  /// 这张图按什么顺序试地址。
  ///
  /// 顺序（2026-10-02 按实测重排）：**已知通着的边缘 IP 直连** → 域名原地址 →
  /// 换端口的域名地址 → 没试过的别的 IP 直连。以前只有后两条，而域名解析出的
  /// 10 个 IP 里有 5 个是全死的 —— 走域名等于掷硬币（10/15），直连好 IP 是 15/15。
  Future<List<_Candidate>> _candidatesFor(Uri uri) async {
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    final alt = alternatePorts[port];
    final out = <_Candidate>[];

    String? good;
    var ips = const <String>[];
    try {
      good = await edges.preferred(uri.host);
      // 解析 + 滤掉已知坏 IP（`comic_img_edges` 记着哪几个通）。上限 4：够换了，
      // 再多也只是把 attempts 烧在同一批死 IP 上。
      ips = await edges.fallbackIps(uri.host, limit: 4);
    } catch (_) {
      // 记忆读不出来就按老路走（不联网、不报错）。
    }

    // **自己挑 IP，不交给系统掷硬币。** 2026-10-02 实测（175）：图床域名解析出 10 个 IP，
    // 其中 5 个整段全死；**走域名连发 30 张失败 9 成**（用户看到的"下到第 1 张就 reset"
    // 就是这个），自己逐个直连通着的那几个：0 失败。所以解析出来的 IP 全排在前面，
    // 域名只当"IP 都没成"的最后兜底。
    if (good != null) out.add(_Candidate(uri, good));
    for (final ip in ips) {
      if (ip != good) out.add(_Candidate(uri, ip));
    }
    if (alt != null && alt != port) {
      final altUri = uri.replace(port: alt);
      final altIps = <String>[...ips];
      if (good != null) altIps.insert(0, good);
      for (final ip in altIps) {
        out.add(_Candidate(altUri, ip));
      }
      out.add(_Candidate(altUri, null));
    }
    out.add(_Candidate(uri, null));
    return out;
  }

  /// 自检/排查用：这张图会按什么顺序、试哪些地址。
  @visibleForTesting
  Future<List<String>> debugCandidateLabels(String url) async {
    final uri = Uri.parse(url);
    return [for (final c in await _candidatesFor(uri)) c.label];
  }

  static String _triedLabel(Uri uri) {
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    return ':$port 这条路';
  }

  /// 同时最多几张图在下载（其余排队）。
  ///
  /// 为什么要限（2026-10-01）：列表一屏近十个封面、每张各开一条新 TLS 连接，境外图床和
  /// 运营商网关对这种小突发很敏感 —— 掐掉几条，用户看到的就是"有的出来了、有的转圈"。
  /// 限到 4 条以后失败面小得多，而总耗时几乎不变（瓶颈在对端不在我们这儿）。
  final int maxParallel;

  static const int defaultMaxParallel = 4;

  /// 给**前台**（正在读的那一话、列表/详情上的封面）留出的名额。
  ///
  /// 为什么要有优先级（2026-10-01）：预取（下一话开头几张）和正在读的那一话**共用同一个
  /// 缓存实例**，也就共用同一个并发池 —— 翻到下一话之前预取正在跑那 3 张，正文的图就排在
  /// 它们后面，用户体感是"翻页更慢了"。低优先级的活最多占 `maxParallel - foregroundReserved`
  /// 个名额，而且**有前台在排队时它不抢**。
  final int foregroundReserved;

  static const int defaultForegroundReserved = 2;

  int _running = 0;

  /// 其中低优先级占着的名额数。
  int _runningLow = 0;

  final Queue<Completer<void>> _highWaiters = Queue<Completer<void>>();
  final Queue<Completer<void>> _lowWaiters = Queue<Completer<void>>();

  /// 低优先级最多同时占几个名额（至少留 1 个给前台，免得自己把自己堵死）。
  int get _lowLimit => (maxParallel - foregroundReserved).clamp(1, maxParallel);

  HttpClient? _client;

  /// 整个缓存实例共用一个 HttpClient。
  ///
  /// 2026-10-01 之前是**每张图各造一个 client、下完就 force close**：一屏近十个封面
  /// 就是十条新建 TLS 连接、下完全拆。图床与运营商网关对"同一来源的短时新建连接数"
  /// 敏感（用户那张网上偶发 `Connection reset by peer`，而同一个地址在手机浏览器里打得开
  /// —— 浏览器正是复用连接的）。改成共用之后连接会复用，`maxConnectionsPerHost`
  /// 又把每台主机的并发卡在 [maxParallel] 条。
  HttpClient _http() {
    final injected = httpClientFactory;
    final client = _client ??= (injected != null ? injected() : HttpClient());
    client.connectionTimeout = connectTimeout;
    client.maxConnectionsPerHost = maxParallel;
    // 闲置连接别攥太久：手机网络的中转设备会先一步把长时间不动的连接拆掉，
    // 那时我们再写就正好撞上 reset。10 秒是个安全的中间值。
    client.idleTimeout = const Duration(seconds: 10);
    return client;
  }

  /// 关掉共用连接（页面销毁时调用；不调也只是让连接闲置到期）。
  void close() {
    _client?.close(force: true);
    _client = null;
  }

  Future<void> _acquire({required bool low}) {
    if (_canStart(low)) {
      _grant(low);
      return Future<void>.value();
    }
    final waiter = Completer<void>();
    (low ? _lowWaiters : _highWaiters).add(waiter);
    return waiter.future;
  }

  /// 现在能不能开一条：[low] 为真时还要看"前台没在排队"和"自己没占满"。
  bool _canStart(bool low) {
    if (_running >= maxParallel) return false;
    if (!low) return true;
    return _highWaiters.isEmpty && _runningLow < _lowLimit;
  }

  void _grant(bool low) {
    _running++;
    if (low) _runningLow++;
  }

  /// 直连某个 IP 的客户端：`connectionFactory` 只换连接地址，
  /// URL / SNI / 证书校验仍然都是域名那一套。
  ///
  /// **按 IP 复用**（不是每张图各建一个）：否则直连虽然躲开了死 IP，却把
  /// "同一条连接连续取图"这个 345 就修好的东西又丢了 —— 每张图一次 TLS 握手，
  /// 图床对这种小突发同样敏感（那条用例 `顺序取多张会复用同一条连接` 就是钉它的）。
  HttpClient _pinnedClient(String ip) {
    final cached = _pinnedClients[ip];
    if (cached != null) return cached;
    final client = HttpClient();
    // 注意别写成级联：lambda 体是表达式，`..` 会被吃进 lambda 里。
    client.connectionFactory =
        (Uri uri, String? proxyHost, int? proxyPort) {
          // 配了代理就走代理（别绕过它直连 IP —— 那种网络下直连多半是不通的）；
          // 没配代理才把连接地址换成这个 IP，URL/SNI/证书仍然都是域名那一套。
          if (proxyHost != null) {
            return Socket.startConnect(proxyHost, proxyPort ?? uri.port);
          }
          return Socket.startConnect(ip, uri.port);
        };
    client.connectionTimeout = connectTimeout;
    client.idleTimeout = idleTimeout;
    _pinnedClients[ip] = client;
    return client;
  }

  /// 直连用到的 client（按 IP 存，随缓存实例一起活）。
  final Map<String, HttpClient> _pinnedClients = {};

  void _release({required bool low}) {
    _running--;
    if (low) _runningLow--;
    // 刚空出来的名额转给排队者：**前台优先**；低优先级只在没人等前台、且没到自己上限时才接
    // （否则预取会把名额占着，用户翻页继续排队）。
    if (_highWaiters.isNotEmpty && _canStart(false)) {
      // 名额转给排队者时**必须把它叫醒**：`removeFirst()` 只是把它从队列里拿出来，
      // 不 complete 的话那个 `await _acquire()` 永远不返回 —— 图就卡在队列里（实测过）。
      final waiter = _highWaiters.removeFirst();
      _grant(false);
      waiter.complete();
      return;
    }
    if (_lowWaiters.isNotEmpty && _canStart(true)) {
      final waiter = _lowWaiters.removeFirst();
      _grant(true);
      waiter.complete();
    }
  }

  /// 真正下这一张（[uri] 是本次要连的地址，[url] 是**缓存键 / 请求头判据**用的原始地址）。
  Future<File> _transfer(
    _Candidate candidate,
    String url,
    String host, {
    File? dest,
  }) async {
    final uri = candidate.uri;
    final pinned = candidate.ip;
    // 直连某个边缘 IP：连接层换地址，TLS 仍按域名验证（见 [ComicImageEdges]）。
    // 这种客户端绑死一个 IP，用完就关 —— 留着没意义。
    final client = pinned == null ? _http() : _pinnedClient(pinned);
    try {
      final HttpClientRequest req;
      try {
        req = await client.getUrl(uri);
      } on TimeoutException {
        throw ComicImageException(
          '图床连不上（$host）：等了 ${_dur(connectTimeout)}都没连上',
          retryable: true,
        );
      } catch (e) {
        // 连不上（DNS 失败 / 连接被拒 / 连接被重置）也要说清楚 —— 这类错以前会被
        // 裹成一句"图片下载失败"，看不出是**没连上**还是**下到一半断了**。
        // 顺手把术语翻成人话：用户看到 `errno = 104` 除了截图给我没有任何用处。
        throw ComicImageException(
          '图床连不上（$host）：${_netReason(e)}',
          retryable: true,
          transient: _isTransientNetError(e),
        );
      }
      req.headers.set(HttpHeaders.acceptHeader, 'image/*,*/*;q=0.8');
      headerFor(url).forEach((k, v) {
        req.headers.set(k, v);
      });
      final HttpClientResponse resp;
      try {
        resp = await req.close().timeout(connectTimeout);
      } on TimeoutException {
        throw ComicImageException(
          '图床没响应（$host）：连上了但等了 ${_dur(connectTimeout)}一个字节都没收到',
          retryable: true,
        );
      }
      if (resp.statusCode != 200) {
        // 把正文丢掉再抛：不读干会留着这条连接（force close 也不保证对端立刻释放）。
        await resp.drain<void>().catchError((_) {});
        throw ComicImageException(
          '这张图没下来（HTTP ${resp.statusCode}，$host）',
          // 5xx 是服务端一时抽风（CDN 节点过载常见），换条路再试有意义；
          // 4xx（404/403）说明这个地址本来就没有，别白试。
          retryable: resp.statusCode >= 500,
          transient: resp.statusCode >= 500,
        );
      }
      final bytes = await _readBody(resp, host);
      if (bytes.isEmpty) {
        throw ComicImageException('这张图是空的（0 字节，$host）');
      }
      final File out;
      if (dest != null) {
        // 离线下载：写进调用方给的路径，先 .part 再改名（写一半被杀掉不会留半张图
        // 假扮成"已下载"）。**不**碰 temp 缓存的上限淘汰：用户主动下的内容不该因为
        // "存太久了"被清掉，那是缓存才该有的行为。
        out = dest;
        final part = File('${dest.path}.part');
        await part.writeAsBytes(bytes, flush: true);
        await part.rename(dest.path);
      } else {
        final dir = await _cacheDir();
        final tmp = File('${dir.path}/${_key(url)}.part');
        await tmp.writeAsBytes(bytes, flush: true);
        out = File('${dir.path}/${_key(url)}');
        await tmp.rename(out.path);
        // 下完一张顺手看一眼上限（每 16 张才真去全盘数一次：全盘 list 是 O(文件数)，
        // 209 张一话挨张扫一遍是白跑）。
        await _maybePrune();
      }
      return out;
    } on ComicImageException {
      rethrow;
    } catch (e) {
      throw ComicImageException(
        '图片下载失败（$host）：${_netReason(e)}',
        retryable: true,
        transient: _isTransientNetError(e),
      );
    } finally {
      // 两种 client 都**不关**：共享 pool 才能复用连接（每张图各开一条新连接正是
      // 被图床掐的原因之一，见 [_http]）；直连那个按 IP 复用，见 [_pinnedClient]。
    }
  }

  /// 读完整张图，带**两道截止时间**（闲着 15 秒 / 总共 90 秒）。
  ///
  /// 这里以前是裸 `resp.fold(...)`：对端把连接挂住（移动网上的常事）就永远收不到
  /// 结束信号，界面上只剩一个转圈 —— 用户报的「封面图加载不出来」正是这个形态。
  Future<List<int>> _readBody(HttpClientResponse resp, String host) async {
    try {
      return await resp
          .timeout(
            idleTimeout,
            onTimeout: (sink) {
              sink.addError(
                ComicImageException(
                  '图床卡住了（$host）：${_dur(idleTimeout)}一个新字节都没有',
                  retryable: true,
                ),
              );
              sink.close();
            },
          )
          .fold<List<int>>(<int>[], (a, b) => a..addAll(b))
          .timeout(
            totalTimeout,
            onTimeout: () => throw ComicImageException(
              '这张图下载超时（$host）：等了 ${_dur(totalTimeout)}还没下完',
              retryable: true,
            ),
          );
    } on ComicImageException {
      rethrow;
    } catch (e) {
      throw ComicImageException(
        '图片下载中断（$host）：${_netReason(e)}',
        retryable: true,
        transient: _isTransientNetError(e),
      );
    }
  }

  /// 已经缓存的张数（界面上如实显示缓存情况用）。
  Future<int> cachedCount(List<String> urls) async {
    var n = 0;
    for (final u in urls) {
      if (await cachedFile(u) != null) n++;
    }
    return n;
  }

  /// 缓存占用的字节数（界面显示用；统计的是**这个实例**用的那个目录）。
  Future<int> sizeBytes() async {
    final dir = await _cacheDir();
    return _bytesIn(dir);
  }

  /// 清空缓存（用户手动触发）。
  Future<void> clear() async {
    final dir = await _cacheDir();
    if (await dir.exists()) await dir.delete(recursive: true);
    _dir = null;
    _inFlight.clear();
    _usedAddress.clear();
  }

  // ── 上限与清理（设置页的「清理缓存」也走这里）───────────────────────

  /// 默认上限：超过就按**最旧的先删**（构造时可覆盖，单测用小值）。
  ///
  /// 为什么必须有：单话实测最多 209 张 × ~48KB ≈ 10MB，翻几本书就上百 MB，
  /// 而它全落在系统缓存目录里 —— 不设上限就是"用户手机空间被慢慢吃掉，界面上还看不出来"。
  static const int defaultMaxBytes = 300 * 1024 * 1024; // 300MB
  static const int defaultMaxFiles = 4000;

  /// 每下这么多张才全盘数一次（见 [_maybePrune]）。
  static const int defaultPruneEveryWrites = 16;

  /// 上限（超过就删最旧的）。
  final int maxBytes;
  final int maxFiles;

  /// 每下多少张查一次上限。
  final int pruneEveryWrites;

  int _writesSincePrune = 0;

  Future<void> _maybePrune() async {
    if (++_writesSincePrune < pruneEveryWrites) return;
    _writesSincePrune = 0;
    await _prune();
  }

  /// 刚下好的图**最少保留多久**：正在显示的那张被删掉会闪一下破图标。
  static const Duration _minAge = Duration(minutes: 5);

  /// 缓存目录（静态版：设置页清缓存时不必造一个带请求头的实例）。
  static Future<Directory> cacheDirectory() async {
    final base = await getTemporaryDirectory();
    return Directory('${base.path}/comic_online_images');
  }

  static Future<int> _bytesIn(Directory dir) async {
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final e in dir.list()) {
      if (e is! File) continue;
      try {
        total += await e.length();
      } on FileSystemException {
        // 量不到就当 0：统计不该把「清缓存」这个动作本身挡下来。
      }
    }
    return total;
  }

  /// 当前占用字节数（[inDir] 只给单测用；不传就是真实缓存目录）。
  static Future<int> diskUsage({Directory? inDir}) async =>
      _bytesIn(inDir ?? await cacheDirectory());

  /// 清掉整个漫画图片缓存，返回**清出多少字节**（界面用它说人话）。
  ///
  /// [inDir] 只给单测用；不传就是真实缓存目录。
  static Future<int> clearAll({Directory? inDir}) async {
    final dir = inDir ?? await cacheDirectory();
    if (!await dir.exists()) return 0;
    final freed = await _bytesIn(dir);
    await dir.delete(recursive: true);
    return freed;
  }

  /// 单测入口：真实现由取图后按 [_maybePrune] 的节奏自动触发。
  @visibleForTesting
  Future<void> pruneNow() => _prune();

  /// 超上限就删最旧的（尽力而为：删不掉不算失败，这次的图已经拿到了）。
  Future<void> _prune() async {
    try {
      final dir = await _cacheDir();
      final files = <File>[];
      var total = 0;
      await for (final e in dir.list()) {
        if (e is! File) continue;
        files.add(e);
        total += await e.length();
      }
      var count = files.length;
      if (count <= maxFiles && total <= maxBytes) return;
      // 旧 → 新：先删最旧的，最近 [_minAge] 内的一律不动（可能正在显示）。
      final stats = <File, FileStat>{};
      for (final f in files) {
        stats[f] = await f.stat();
      }
      files.sort(
        (a, b) => stats[a]!.modified.compareTo(stats[b]!.modified),
      );
      final cutoff = DateTime.now().subtract(_minAge);
      for (final f in files) {
        if (count <= maxFiles && total <= maxBytes) break;
        final st = stats[f]!;
        if (st.modified.isAfter(cutoff)) continue;
        total -= st.size;
        count -= 1;
        try {
          await f.delete();
        } on FileSystemException {
          // 删不掉（被占用 / 已不存在）不影响这次取图；下次再清。
        }
      }
    } on FileSystemException {
      // 清理只是尽力而为：真正的失败（下载）已经在上面如实抛了。
    }
  }

  static String _key(String url) => sha1.convert(utf8.encode(url)).toString();

  /// 时长说人话：`inSeconds` 会把 100 毫秒说成"0 秒"（自检里看着像没等），
  /// 一秒以下一律用毫秒。
  static String _dur(Duration d) => d.inMilliseconds < 1000
      ? '${d.inMilliseconds} 毫秒'
      : '${d.inSeconds} 秒';

  static String _short(Object e) {
    final s = e.toString();
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }

  /// 「一闪而过」的网络错：被对方掐断 / 连接被提前关掉 / 服务端 5xx。
  ///
  /// 与 [retryable] 分开是因为两者的**代价不一样**：换端口只多花一次连接，而"同一地址
  /// 再试一次"要再等一整套超时 —— 只有这种一眼看着像偶发的错才值得。
  static bool _isTransientNetError(Object e) {
    final s = e.toString();
    return s.contains('Connection reset') ||
        s.contains('errno = 104') ||
        s.contains('Connection closed');
  }

  /// 网络层的异常翻成人话。
  ///
  /// 2026-10-01 用户截图里那行是 `SocketException: Connection reset by peer (OS Error:
  /// Connection reset by peer, errno = 104), address = …` —— 一屏都是术语，他除了截图
  /// 给我帮不上任何忙；而这几种情况的**处置恰好是不一样的**（换端口能救的、只能等的、
  /// 得找运维的），所以先分清楚再显示。
  static String _netReason(Object e) {
    final s = e.toString();
    if (s.contains('Connection reset') || s.contains('errno = 104')) {
      return '连接被对方掐断（端口被运营商/网关拦，或对端拒绝）';
    }
    if (s.contains('Connection closed')) return '连接被对方提前关掉';
    if (s.contains('Failed host lookup') || s.contains('nodename nor servname')) {
      return '域名解析不出来（DNS 或本地网络的问题）';
    }
    if (s.contains('Connection refused')) return '对方拒绝连接（端口没开）';
    if (s.contains('Network is unreachable') || s.contains('No route to host')) {
      return '网络不通（这条路到不了对方）';
    }
    if (s.contains('timed out') || s.contains('TimeoutException')) {
      return '等太久没响应';
    }
    return _short(e);
  }
}

/// 取图失败（可以给人看）。
class ComicImageException implements Exception {
  ComicImageException(
    this.message, {
    this.retryable = false,
    this.transient = false,
  });

  final String message;

  /// 值不值得**换个地址再试一次**：连不上、被掐断、卡住这类网络层的失败，换端口往往就好了；
  /// HTTP 4xx、0 字节这种再试一百次也一样，直接抛给用户别浪费时间。
  final bool retryable;

  /// 是不是「一闪而过」的错（被对方掐断 / 连接被提前关掉 / 服务端 5xx）。
  ///
  /// 这类错**同一个地址再试一次**往往就成（用户实测：同样的地址在手机浏览器里能打开）；
  /// 而超时不是 —— 那是这条网本来就慢，再来一遍只会让用户多等一个超时。
  final bool transient;

  @override
  String toString() => message;
}

/// 一个"要试的地址"：URL + 可选的"直连哪个 IP"。
///
/// 直连只换**连接层**地址（见 [ComicImageCache._pinnedClient]）：请求里的 Host、
/// TLS 的 SNI 与证书校验仍按 URL 里的域名来 —— 因此不是"绕过证书"，是"避开
/// 域名里那半死不活的 A 记录"。
class _Candidate {
  const _Candidate(this.uri, this.ip);

  final Uri uri;

  /// null = 走域名解析（老路）。
  final String? ip;

  /// 日志/排查用：这张图最后是从哪儿取到的。
  String get label => ip == null ? uri.toString() : '${uri.toString()} @$ip';
}
