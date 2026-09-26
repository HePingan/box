// 服务器运维插件：「系统」页签（C2 只读档的门面）。
//
// 这一页回答的是宝塔面板里最常用的那几问：**谁在吃 CPU、某个服务活着没、日志尾巴是什么、
// 端口被谁占了、哪个目录在长、有没有人在试我的密码**。文件页做不到这些 —— rclone 只讲文件。
//
// 形状与另三个页签一致：
//   * 进门就并行拉全套，**每个小节各自记错误**：一节挂了不该把整页打黑（上一页踩过这坑）；
//   * 没有令牌/地址时给"去哪填"的引导，而不是一句 failed；
//   * 每次刷新往 A9 的请求日志记一条（入口=系统），真机出问题时截图自带证据；
//   * 令牌只从设置里取，只交给客户端，**页面任何文本都不打印它**。

import 'package:flutter/material.dart';

import 'package:box/features/extensions/plugins/server_ops/server_ops_api_client.dart';
import 'package:box/features/extensions/plugins/server_ops/monitor_models.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_disk.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_runtime.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_request_log.dart';
import 'package:box/features/extensions/plugins/server_ops/server_ops_settings.dart';

class ServerOpsSystemTab extends StatefulWidget {
  const ServerOpsSystemTab({
    super.key,
    this.settings = const ServerOpsSettings(),
    this.clientFactory,
  });

  final ServerOpsSettings settings;

  /// 用例注入假客户端（默认按设置里的地址/令牌现造一个）。
  final OpsApiClient Function(ServerOpsSettings settings)? clientFactory;

  @override
  State<ServerOpsSystemTab> createState() => _ServerOpsSystemTabState();
}

class _ServerOpsSystemTabState extends State<ServerOpsSystemTab> {
  OpsOverview? _overview;
  List<OpsProcess> _processes = const [];
  List<OpsServiceUnit> _services = const [];
  List<OpsPort> _ports = const [];
  List<OpsDiskRow> _diskRows = const [];
  OpsSessions? _sessions;
  List<OpsAuditEntry> _audit = const [];

  /// 白名单里有哪些日志文件（最近的排前面）。`logs` 管"读某个文件的尾巴"，
  /// 这一节管"有哪些文件可读"—— 以前这半步只能靠人在终端里 ls。
  List<OpsLogFile> _logFiles = const [];
  static const int _logRows = 4;

  /// 通道凭据使用情况（最近 7 天）。只有边缘机那条入口看得到（日志在边缘机写）。
  OpsChannelUsage? _channel;

  /// 体检：站点快照（证书天数/在线）+ 隧道单元 + 巡检日志。
  ///
  /// 这三样**不是这台机器的**指标，而是"整条链路还活着吗" —— 证书到期、隧道断、
  /// 巡检不再跑，全是静默的：页面照常刷新、数字照常显示，直到通道某天全黑。
  MonitorSnapshot? _monitors;
  List<OpsServiceUnit> _tunnelUnits = const <OpsServiceUnit>[];
  OpsLogTail? _patrol;

  final Map<String, String> _errors = <String, String>{};
  bool _loading = false;
  bool _auditTried = false;

  /// 这把令牌能干什么。拉不到就当作"只有读"（写按钮不显示，而不是点了才 403）。
  OpsCapabilities? _caps;

  String _procSort = 'cpu';
  String _serviceFilter = '';
  bool _onlyInteresting = true;
  String _diskPath = '/var/log';
  final TextEditingController _filterCtl = TextEditingController();
  final TextEditingController _diskCtl = TextEditingController(text: '/var/log');

  bool get _configured =>
      widget.settings.effectiveApiUrl.isNotEmpty && widget.settings.hasApiToken;

  OpsApiClient _client() {
    final factory = widget.clientFactory;
    if (factory != null) return factory(widget.settings);
    return OpsApiClient(
      baseUrl: widget.settings.effectiveApiUrl,
      token: widget.settings.effectiveApiToken,
    );
  }

  @override
  void initState() {
    super.initState();
    if (_configured) _refresh();
  }

  @override
  void didUpdateWidget(covariant ServerOpsSystemTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 顶部切换器换了机器 / 用户刚填了令牌 → 重新拉（否则页面停在上一台的数字上）。
    final changed = oldWidget.settings.effectiveApiUrl !=
            widget.settings.effectiveApiUrl ||
        oldWidget.settings.effectiveApiToken != widget.settings.effectiveApiToken;
    if (changed && _configured) _refresh();
  }

  @override
  void dispose() {
    _filterCtl.dispose();
    _diskCtl.dispose();
    super.dispose();
  }

  void _log(bool ok, String detail, DateTime started) {
    serverOpsRequestLog.record(
      OpsRequestRecord(
        entry: '系统',
        serverId: widget.settings.currentServer.id,
        serverLabel: widget.settings.currentServer.label,
        ok: ok,
        detail: detail,
        duration: DateTime.now().difference(started),
        at: started,
      ),
    );
  }

  /// 并行拉全套；每节独立成败（一节挂了只挂那一节）。
  Future<void> _refresh() async {
    if (!_configured) return;
    final started = DateTime.now();
    if (mounted) setState(() => _loading = true);
    final client = _client();
    final errors = <String, String>{};
    final label = widget.settings.currentServer.label;

    Future<T?> pull<T>(String section, Future<T> Function() run) async {
      try {
        return await run();
      } on OpsApiException catch (e) {
        errors[section] = e.message;
        return null;
      } catch (e) {
        errors[section] = '$e';
        return null;
      }
    }

    final caps = await pull('能力', client.capabilities);
    final results = await Future.wait<Object?>([
      pull('概览', client.overview),
      pull('进程', () => client.processes(sort: _procSort, limit: 15)),
      pull('服务', () => client.services(filter: _serviceFilter, limit: 200)),
      pull('端口', client.ports),
      pull('磁盘目录', () => client.diskUsage(_diskPath)),
      pull('登录记录', client.sessions),
      pull('日志文件', () => client.logFiles(limit: 40)),
      pull('通道凭据', client.channel),
      pull('体检站点', () => serverOpsMonitorService.fetch()),
      pull('隧道', () => client.services(filter: 'tunnel', limit: 20)),
      pull('巡检', () => client.logs('/var/log/security-patrol.log', lines: 6)),
    ]);
    final audit = await pull('服务端审计', () => client.audit(limit: 30));
    // 只有自己造的客户端才关；用例注入的那个由用例管（关掉会让后续断言炸）。
    if (widget.clientFactory == null) client.close();

    if (!mounted) return;
    final ok = errors.isEmpty;
    setState(() {
      if (results[0] != null) _overview = results[0] as OpsOverview;
      if (results[1] != null) _processes = results[1] as List<OpsProcess>;
      if (results[2] != null) _services = results[2] as List<OpsServiceUnit>;
      if (results[3] != null) _ports = results[3] as List<OpsPort>;
      if (results[4] != null) _diskRows = results[4] as List<OpsDiskRow>;
      if (results[5] != null) _sessions = results[5] as OpsSessions;
      if (results[6] != null) _logFiles = results[6] as List<OpsLogFile>;
      if (results[7] != null) _channel = results[7] as OpsChannelUsage;
      if (results[8] != null) _monitors = results[8] as MonitorSnapshot;
      if (results[9] != null) _tunnelUnits = results[9] as List<OpsServiceUnit>;
      if (results[10] != null) _patrol = results[10] as OpsLogTail;
      if (audit != null) _audit = audit;
      if (caps != null) _caps = caps;
      _auditTried = true;
      _errors
        ..clear()
        ..addAll(errors);
      _loading = false;
    });
    final ov = _overview;
    _log(
      ok,
      ok
          ? '已刷新 $label：${ov == null ? '' : '${ov.cores} 核 · 负载 ${ov.load1.toStringAsFixed(2)} · '
              '内存 ${ov.memUsedPercent.toStringAsFixed(0)}% · '}'
              '进程 ${_processes.length} 条 · 服务 ${_services.length} 个 · 端口 ${_ports.length} 条'
          : '${errors.values.first}（共 ${errors.length} 节失败）',
      started,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_configured) return _notConfigured(context);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          _topBar(context),
          if (_errors.containsKey('概览')) _errorCard('概览', _errors['概览']!),
          if (_overview != null) _overviewCard(_overview!),
          _healthCard(),
          _sectionGap(),
          if (_errors.containsKey('进程')) _errorCard('进程', _errors['进程']!),
          _processCard(),
          _sectionGap(),
          if (_errors.containsKey('服务')) _errorCard('服务', _errors['服务']!),
          _serviceCard(),
          _sectionGap(),
          if (_errors.containsKey('端口')) _errorCard('端口', _errors['端口']!),
          _portsCard(),
          _sectionGap(),
          if (_errors.containsKey('磁盘目录'))
            _errorCard('磁盘目录', _errors['磁盘目录']!),
          _diskCard(),
          _sectionGap(),
          if (_errors.containsKey('日志文件'))
            _errorCard('日志文件', _errors['日志文件']!),
          _logCard(),
          _sectionGap(),
          if (_errors.containsKey('登录记录'))
            _errorCard('登录记录', _errors['登录记录']!),
          _sessionsCard(),
          _sectionGap(),
          _auditCard(),
          _sectionGap(),
          if (_errors.containsKey('通道凭据'))
            _errorCard('通道凭据', _errors['通道凭据']!),
          _channelCard(),
        ],
      ),
    );
  }

  // ── 外壳 ────────────────────────────────────────────────────────

  Widget _topBar(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              widget.settings.currentServer.label,
              style: Theme.of(context).textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_loading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              tooltip: '刷新',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
        ],
      );

  Widget _notConfigured(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('这台机器还没接只读接口',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text('系统页（进程/服务/日志/端口）走的是只读运维接口，'
                      '与文件页的口令**不是同一个凭据**：'),
                  const SizedBox(height: 8),
                  Text('· 接口地址：${widget.settings.effectiveApiUrl.isEmpty ? '（这台没默认值，要手填）' : widget.settings.effectiveApiUrl}'),
                  Text('· 设备令牌：${widget.settings.hasApiToken ? '已填' : '（还没填）'}'),
                  const SizedBox(height: 12),
                  const Text('去「设置 → 服务器」把这两项补齐即可。'),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _sectionGap() => const SizedBox(height: 12);

  Widget _cardShell(String title, Widget child, {Widget? trailing}) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 6),
              child,
            ],
          ),
        ),
      );

  /// 通道凭据（文件/终端那个口令层的使用情况）。
  ///
  /// 为什么放在这一页：它和"服务端审计"一样是**跨设备**的数据，而且回答的是
  /// "现在还有谁在用通道口令、用的是哪一条" —— 旧口令能不能退休就看这一张。
  Widget _channelCard() {
    final theme = Theme.of(context);
    final c = _channel;
    if (c == null) {
      return _cardShell('通道凭据（最近 7 天）', const Text('（没有数据）'));
    }
    if (!c.available) {
      return _cardShell(
        '通道凭据（最近 7 天）',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.reason.isEmpty ? '这台机器的 API 看不到通道访问日志' : c.reason),
            if (c.hint.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(c.hint, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      );
    }
    return _cardShell(
      '通道凭据（最近 ${c.windowDays} 天）',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (c.users.isEmpty)
            const Text('窗口内没有通道访问记录')
          else
            for (final u in c.users)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${u.user}'
                            '${u.readOnly ? '（只读）' : ''}'
                            '${u.stillValid ? '' : '（已撤销）'}',
                            style: theme.textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text('${u.count} 次',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                    Text(
                      '${u.entries.keys.join('/')}'
                      '${u.denied > 0 ? ' · 被拒 ${u.denied} 次' : ''}'
                      ' · 最近 ${u.lastSeen}${u.lastIp.isEmpty ? '' : '（${u.lastIp}）'}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
          if (c.unused.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '签了但没用过：${c.unused.join('、')}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            '只统计入口与次数，不记录具体路径；口令本体与哈希都不在返回里。',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(String section, String message) => Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.error_outline, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('$section：$message')),
            ],
          ),
        ),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 76,
              child: Text(k, style: Theme.of(context).textTheme.bodySmall),
            ),
            Expanded(child: SelectableText(v, style: Theme.of(context).textTheme.bodySmall)),
          ],
        ),
      );

  Widget _bar(String label, double percent) {
    final warn = percent >= 85;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
              Text('${percent.toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: warn ? Theme.of(context).colorScheme.error : null,
                        fontWeight: warn ? FontWeight.bold : null,
                      )),
            ],
          ),
          const SizedBox(height: 3),
          LinearProgressIndicator(
            value: (percent / 100).clamp(0.0, 1.0),
            minHeight: 5,
          ),
        ],
      ),
    );
  }

  // ── 各小节 ──────────────────────────────────────────────────────

  Widget _overviewCard(OpsOverview ov) => _cardShell(
        '概览',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv('主机', ov.hostname),
            _kv('系统', '${ov.osPretty}（内核 ${ov.kernel}）'),
            _kv('运行', formatUptime(ov.uptimeSeconds)),
            _kv('负载', '${ov.load1.toStringAsFixed(2)} / ${ov.load5.toStringAsFixed(2)} / '
                '${ov.load15.toStringAsFixed(2)}（${ov.cores} 核，每核 ${ov.loadPerCore.toStringAsFixed(2)}）'),
            _kv('CPU', ov.cpuModel),
            const SizedBox(height: 6),
            _bar('内存 ${formatBytes(ov.memUsed)} / ${formatBytes(ov.memTotal)}',
                ov.memUsedPercent),
            if (ov.swapTotal > 0)
              _bar('Swap ${formatBytes(ov.swapUsed)} / ${formatBytes(ov.swapTotal)}',
                  ov.swapUsedPercent),
            if (ov.disks.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('磁盘', style: Theme.of(context).textTheme.bodySmall),
              for (final d in ov.disks)
                _bar('${d.mount}  ${d.used} / ${d.size}（剩 ${d.avail}）',
                    double.tryParse(d.usePercent.replaceAll('%', '')) ?? 0),
            ],
          ],
        ),
      );

  Widget _processCard() => _cardShell(
        '进程（前 15）',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'cpu', label: Text('按 CPU')),
                ButtonSegment(value: 'mem', label: Text('按内存')),
              ],
              selected: {_procSort},
              onSelectionChanged: (s) {
                setState(() => _procSort = s.first);
                _refresh();
              },
            ),
            const SizedBox(height: 6),
            if (_processes.isEmpty)
              const Text('（没有数据）')
            else
              for (final p in _processes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('${p.name}  #${p.pid}',
                                style: Theme.of(context).textTheme.bodyMedium),
                          ),
                          Text('CPU ${p.cpuPercent.toStringAsFixed(1)}% · '
                              '内存 ${p.memPercent.toStringAsFixed(1)}% · '
                              '${formatBytes(p.rssKb * 1024)}',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                      Text('${p.user} · 已跑 ${p.elapsed} · ${p.args}',
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
          ],
        ),
      );

  Widget _serviceCard() {
    final shown = _onlyInteresting
        ? _services.where((s) => s.active == 'active' || s.isFailed).toList()
        : _services;
    final failed = _services.where((s) => s.isFailed).length;
    return _cardShell(
      '服务（${shown.length} 个${failed > 0 ? '，$failed 个失败' : ''}）',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _filterCtl,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: '按名字/说明过滤（如 nginx）',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (v) {
                    setState(() => _serviceFilter = v);
                    _refresh();
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '应用过滤',
                onPressed: () {
                  setState(() => _serviceFilter = _filterCtl.text);
                  _refresh();
                },
                icon: const Icon(Icons.search),
              ),
            ],
          ),
          Row(
            children: [
              const Expanded(child: Text('只看运行中/失败')),
              Switch(
                value: _onlyInteresting,
                onChanged: (v) => setState(() => _onlyInteresting = v),
              ),
            ],
          ),
          if (shown.isEmpty)
            const Text('（没有数据）')
          else
            for (final s in shown.take(60))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  s.isFailed ? Icons.error_outline : Icons.check_circle_outline,
                  size: 18,
                  color: s.isFailed ? Theme.of(context).colorScheme.error : null,
                ),
                title: Text(s.unit),
                subtitle: Text('${s.active}/${s.sub} · ${s.enabled}'
                    '${s.description.isEmpty ? '' : ' · ${s.description}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                onTap: () => _openService(s.unit),
              ),
        ],
      ),
    );
  }

  Future<void> _openService(String unit) async {
    final started = DateTime.now();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ServiceSheet(
        unit: unit,
        client: _client(),
        caps: _caps,
        onResult: (ok, detail) => _log(ok, '服务 $unit：$detail', started),
        // 写成功之后刷新父页（服务列表的状态就跟着变了）
        onChanged: _refresh,
      ),
    );
  }

  Widget _portsCard() => _cardShell(
        '端口监听（${_ports.length} 条）',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_ports.isEmpty)
              const Text('（没有数据）')
            else
              for (final p in _ports)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('${p.local}  ${p.process}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ),
                      Text(p.proto, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
          ],
        ),
      );

  /// 日志小节：先给最近改动的几个文件，其余的在弹层里选。
  ///
  /// 为什么不一次列 40 条：这一节在"系统"页里，用户九成只是要看**最近**的那几个；
  /// 全列出来会把页面撑成长条，反而不好找。
  Widget _logCard() => _cardShell(
        '日志（白名单：/var/log、/www/wwwlogs、更新服务日志）',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_logFiles.isEmpty)
              const Text('（没有数据）')
            else ...[
              for (final f in _logFiles.take(_logRows))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(f.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${formatBytes(f.size)} · ${f.mtime}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => _openLogFile(f),
                ),
              if (_logFiles.length > _logRows)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _openLogList,
                    child: Text('看全部 ${_logFiles.length} 个'),
                  ),
                ),
            ],
          ],
        ),
      );

  Future<void> _openLogList() async {
    final picked = await showModalBottomSheet<OpsLogFile>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LogListSheet(files: _logFiles),
    );
    if (picked != null && mounted) await _openLogFile(picked);
  }

  Future<void> _openLogFile(OpsLogFile f) async {
    final started = DateTime.now();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LogTailSheet(
        file: f,
        client: _client(),
        onResult: (ok, detail) => _log(ok, '日志 ${f.name}：$detail', started),
      ),
    );
  }

  /// 体检卡：证书还剩几天 / 站点在不在线 / 隧道单元 / 巡检最近一次。
  ///
  /// 数据来源是**已有的**三处：站点快照（175 每 2 分钟采 Uptime Kuma，里面本来就有
  /// certDays）、只读接口的服务列表、巡检日志。这里不新采任何东西 —— 缺的只是"摆到
  /// 手机上一眼能看到"。
  Widget _healthCard() {
    final theme = Theme.of(context);
    return _cardShell(
        '体检',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_monitors case final m?) ...[
              for (final entry in m.nearestCerts())
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      Icon(
                        entry.certUrgent
                            ? Icons.error_outline_rounded
                            : entry.certTight
                                ? Icons.warning_amber_rounded
                                : Icons.verified_outlined,
                        size: 15,
                        color: entry.certUrgent
                            ? theme.colorScheme.error
                            : entry.certTight
                                ? Colors.orange
                                : theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${entry.name} 的证书还有 ${entry.certDays} 天',
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              Text(
                '证书：${m.nearestCerts().length} 张最近的 / 共 ${m.total} 个站点里 '
                '${m.monitors.where((x) => x.certDays != null).length} 个拿得到天数；'
                '证书一般 30 天内会提醒、14 天内该动手',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 4),
              _fact(
                theme,
                m.allUp ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                m.allUp
                    ? '站点 ${m.upCount}/${m.total} 全部在线'
                    : '站点 ${m.upCount}/${m.total}，挂了：${m.downNames.join('、')}',
              ),
            ] else
              Text('站点快照没取到（体检需要它来算证书天数）',
                  style: theme.textTheme.bodySmall),
            if (_tunnelUnits.isNotEmpty)
              _fact(
                theme,
                Icons.cable_rounded,
                _tunnelUnits.map((u) => '${u.unit} ${u.active}').join('；'),
              ),
            if (_patrol case final p?) ...[
              _fact(theme, Icons.health_and_safety_outlined, '巡检 ${_patrolWhen(p)}'),
              if (_patrolLastLine(p) case final last?)
                Padding(
                  padding: const EdgeInsets.only(left: 21, top: 2),
                  child: Text(
                    last,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                      fontSize: 10,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ],
        ),
      );
  }

  /// 一行"图标 + 说明"（体检卡里用；本文件没有现成的，别去借 host_tab 的私有件）。
  Widget _fact(ThemeData theme, IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: theme.colorScheme.outline),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text, style: theme.textTheme.bodySmall),
            ),
          ],
        ),
      );

  /// 巡检"最近一次什么时候跑的"。服务端回了 mtime 就说准；老服务端没这个字段就
  /// 只说"有这个日志"，**不编一个时间**。
  String _patrolWhen(OpsLogTail p) {
    final at = p.mtime;
    if (at == null) return '有日志（服务端没回时间）';
    final d = DateTime.now().difference(at);
    final stale = d.inHours > 48;
    final ago = d.inMinutes < 1
        ? '刚刚'
        : d.inHours < 1
            ? '${d.inMinutes} 分钟前'
            : d.inHours < 48
                ? '${d.inHours} 小时前'
                : '${d.inDays} 天前';
    return '$ago${stale ? '（超过 48 小时没跑了，检查 cron）' : ''}';
  }

  String? _patrolLastLine(OpsLogTail p) {
    final lines = p.content
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return lines.isEmpty ? null : lines.last;
  }

  Widget _diskCard() => _cardShell(
        '目录占用',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _diskCtl,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '/var/log',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (v) => _runDisk(v),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _runDisk(_diskCtl.text),
                  child: const Text('查'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // 找"谁把盘吃满了"靠的就是这颗「上一级」：一路点下去看得见每一层的占比。
            Row(
              children: [
                IconButton(
                  tooltip: '上一级',
                  visualDensity: VisualDensity.compact,
                  onPressed: opsParentPath(_diskPath) == null
                      ? null
                      : () => _runDisk(opsParentPath(_diskPath)!),
                  icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                ),
                IconButton(
                  tooltip: '从根目录开始找',
                  visualDensity: VisualDensity.compact,
                  onPressed: _diskPath == '/' ? null : () => _runDisk('/'),
                  icon: const Icon(Icons.home_outlined, size: 18),
                ),
                Expanded(
                  child: Text('当前：$_diskPath',
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                if (_diskRows.isNotEmpty)
                  Text('${_diskRows.length} 项',
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            if (_errors['磁盘目录'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('拉取失败：${_errors['磁盘目录']}',
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 2),
            if (_diskRows.isEmpty)
              const Text('（没有数据）')
            else
              for (final r in _sortedDiskRows())
                InkWell(
                  onTap: _loading ? null : () => _runDisk(r.path),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 66,
                          child: Text(r.size,
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.path,
                                  style: Theme.of(context).textTheme.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: opsDiskBarShare(
                                      opsParseHumanSize(r.size), _diskRows),
                                  minHeight: 3,
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, size: 16),
                      ],
                    ),
                  ),
                ),
            const Divider(height: 18),
            Text('清理', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(
              _caps?.write == true
                  ? '先问一句"能清多少"，确认了才动手；清多狠由服务端定死，手机上改不了。'
                  : '这把令牌没有写权限：要看能清多少可以，真清要带 --write 重签令牌。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final mode in kOpsCleanupModes)
                  OutlinedButton.icon(
                    onPressed: (_loading || _caps?.write != true)
                        ? null
                        : () => _runCleanup(mode),
                    icon: const Icon(Icons.cleaning_services_outlined, size: 16),
                    label: Text(mode.label),
                  ),
              ],
            ),
            if (_errors['清理'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('清理失败：${_errors['清理']}',
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      );

  List<OpsDiskRow> _sortedDiskRows() => opsSortDiskRowsBySize(_diskRows);

  /// 清理：**先 dry 问一句"能清多少"**，把数字摆给用户看，再问要不要真清。
  ///
  /// 不做"点一下就清"：这是在别人的生产机上动刀，先看数字再确认是这条流程的全部意义。
  Future<void> _runCleanup(OpsCleanupMode mode) async {
    if (_loading) return;
    final client = _client();
    setState(() {
      _loading = true;
      _errors.remove('清理');
    });
    Map<String, dynamic> preview;
    try {
      preview = await client.cleanup(mode.key, dry: true);
    } on OpsApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errors['清理'] = e.message;
        });
      }
      return;
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errors['清理'] = '$e';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _loading = false);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('清理「${mode.label}」？'),
        content: Text('${_cleanupPreviewText(mode, preview)}\n\n'
            '${mode.hint}\n'
            '只清这一类，不碰别的目录；清掉就没了，不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清理')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _loading = true);
    try {
      final d = await client.cleanup(mode.key);
      final freed = d['freedBytes'];
      final text = opsCleanupResultText(mode.key, freed is int ? freed : 0);
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(text)));
        _log(true, text, DateTime.now());
      }
      await _refresh();
    } on OpsApiException catch (e) {
      if (mounted) {
        setState(() => _errors['清理'] = e.message);
        _log(false, '清理 ${mode.key} 失败', DateTime.now());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 预览文案：数字全部来自服务端（`limits` 也在响应里，App 不写死配额）。
  String _cleanupPreviewText(OpsCleanupMode mode, Map<String, dynamic> p) {
    final limits = p['limits'] is Map ? p['limits'] as Map : const {};
    switch (mode.key) {
      case 'tmp':
        final n = p['count'] is int ? p['count'] as int : 0;
        final b = p['bytes'] is int ? p['bytes'] as int : 0;
        final days = limits['tmpKeepDays'] ?? 7;
        return '这台机器上有 $n 个 $days 天没动过的临时文件，约 ${opsFormatBytes(b)}。';
      case 'apt':
        final before = (p['before'] ?? '').toString().trim();
        return before.isEmpty
            ? '软件包缓存看起来是空的（清不出多少）。'
            : '当前缓存：$before';
      default:
        final before = (p['before'] ?? '').toString().trim();
        final mb = limits['journalKeepMB'] ?? 200;
        return '${before.isEmpty ? '' : '$before\n'}清理后只保留最近 $mb MB 的日志。';
    }
  }

  void _runDisk(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return;
    setState(() => _diskPath = trimmed);
    _refresh();
  }

  Widget _sessionsCard() {
    final s = _sessions;
    Widget line(Map<String, dynamic> row) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Text(
            '${row['user'] ?? '?'}  ${row['tty'] ?? ''}  ${row['from'] ?? ''}  ${row['at'] ?? ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
    return _cardShell(
      '登录记录',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (s == null)
            const Text('（没有数据）')
          else ...[
            Text('最近登录', style: Theme.of(context).textTheme.bodySmall),
            if (s.logins.isEmpty) const Text('（无）') else ...s.logins.map(line),
            const SizedBox(height: 6),
            Text('失败登录',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: s.failedLogins.isEmpty
                          ? null
                          : Theme.of(context).colorScheme.error,
                    )),
            if (s.failedLogins.isEmpty)
              const Text('（无）')
            else
              ...s.failedLogins.map(line),
          ],
        ],
      ),
    );
  }

  Widget _auditCard() {
    if (_auditTried && _errors.containsKey('服务端审计')) {
      return _errorCard('服务端审计', _errors['服务端审计']!);
    }
    return _cardShell(
      '服务端审计（最近 ${_audit.length} 条）',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('这条流水是**服务端**记的：谁（令牌 label）从哪个 IP 调了什么动作、成不成。'
              '它要 admin 令牌才能读。',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          if (_audit.isEmpty)
            const Text('（没有数据）')
          else
            for (final e in _audit)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  '${e.at}  ${e.action}  ${e.status}  ${e.ms}ms  ${e.tokenLabel}  ${e.ip}'
                  '${e.note.isEmpty ? '' : '  ${e.note}'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: e.isOk ? null : Theme.of(context).colorScheme.error,
                      ),
                ),
              ),
        ],
      ),
    );
  }
}

/// 单个服务的详情抽屉：状态 + 最近日志（journal）。
class _ServiceSheet extends StatefulWidget {
  const _ServiceSheet({
    required this.unit,
    required this.client,
    required this.onResult,
    this.caps,
    this.onChanged,
  });

  final String unit;
  final OpsApiClient client;
  final void Function(bool ok, String detail) onResult;

  /// 令牌能力（null = 拉不到，按"只有读"处理）。
  final OpsCapabilities? caps;

  /// 写成功后的回调（父页刷新列表）。
  final VoidCallback? onChanged;

  @override
  State<_ServiceSheet> createState() => _ServiceSheetState();
}

class _ServiceSheetState extends State<_ServiceSheet> {
  OpsServiceDetail? _detail;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.client.service(widget.unit, lines: 30);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _loading = false;
      });
      widget.onResult(true, '${d.activeState}/${d.subState}');
    } on OpsApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
      widget.onResult(false, e.message);
    }
  }

  static const Map<String, String> _opLabels = <String, String>{
    'start': '启动',
    'stop': '停止',
    'restart': '重启',
    'reload': '重载配置',
    'enable': '开机自启',
    'disable': '取消自启',
  };

  /// 停/禁用里"会把自己锁在门外"的那几个，按钮直接禁用并说明理由 ——
  /// 不让用户点了才知道（服务端也会拒，但界面先讲清楚）。
  bool _blocked(String op) {
    final caps = widget.caps;
    if (caps == null) return true;
    if (!caps.write) return true;
    if (op == 'stop' || op == 'disable') {
      return caps.stopBlockedReason(widget.unit) != null;
    }
    return false;
  }

  Future<void> _runOp(String op) async {
    final label = _opLabels[op] ?? op;
    if (widget.caps != null && !widget.caps!.write) {
      setState(() => _actionError =
          '这把令牌没有写权限：服务端用 box-ops-api.py token issue --label <名字> --write 重签一次，'
          '再把新令牌填到「设置 → 服务器」');
      return;
    }
    final reason = (op == 'stop' || op == 'disable')
        ? widget.caps?.stopBlockedReason(widget.unit)
        : null;
    if (reason != null) {
      setState(() => _actionError = reason);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$label ${widget.unit}？'),
        content: const Text('这会真的改动这台机器（服务端会记审计）。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(label)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      final d = await widget.client.serviceOp(widget.unit, op);
      widget.onResult(true, '$label 成功（${d['activeState'] ?? '?'}）');
      widget.onChanged?.call();
      await _load();
    } on OpsApiException catch (e) {
      if (!mounted) return;
      setState(() => _actionError = e.message);
      widget.onResult(false, '$label 失败：${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _actionBar(BuildContext context) {
    final caps = widget.caps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Text('操作', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        if (caps == null || !caps.write)
          // 不能加 const：style 里有 Theme.of(context)，那是方法调用（加 const 直接编译不过）。
          Text(
            '这把令牌只能读：想做服务启停/解压这类写动作，要在服务端用 --write 重签一次令牌。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final entry in _opLabels.entries)
              Tooltip(
                message: _blocked(entry.key)
                    ? (caps?.stopBlockedReason(widget.unit) ??
                        (caps == null || !caps.write ? '这把令牌没有写权限' : ''))
                    : '',
                child: OutlinedButton(
                  onPressed: (_busy || _blocked(entry.key)) ? null : () => _runOp(entry.key),
                  child: Text(entry.value),
                ),
              ),
          ],
        ),
        if (_busy) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(minHeight: 2),
        ],
        if (_actionError != null) ...[
          const SizedBox(height: 8),
          Text(_actionError!,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.error, fontSize: 12)),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        // 用 SingleChildScrollView + Column 而不是 ListView：这份内容本来就不长，
        // 惰性列表会让"最下面的操作按钮"在小屏上根本不被建出来（用例里就撞过：按钮找不到）。
        child: SingleChildScrollView(
          controller: controller,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Text(widget.unit, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Text(_error!, style: Theme.of(context).textTheme.bodySmall)
            else if (_detail != null) ...[
              Text('状态：${_detail!.activeState}/${_detail!.subState} · '
                  '开机自启：${_detail!.unitFileState}'),
              if (_detail!.mainPid.isNotEmpty && _detail!.mainPid != '0')
                Text('主进程：${_detail!.mainPid}'),
              if (_detail!.memoryBytes != null)
                Text('内存：${formatBytes(_detail!.memoryBytes!)}'),
              Text('重启次数：${_detail!.restarts}  启动于：${_detail!.since}'),
              const Divider(),
              Text('最近日志', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              SelectableText(_detail!.journal,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
              _actionBar(context),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── D2：日志弹层 ────────────────────────────────────────────────────

/// 「看全部日志」：把白名单里的日志文件列全，选一个交给 [_LogTailSheet]。
class _LogListSheet extends StatelessWidget {
  const _LogListSheet({required this.files});

  final List<OpsLogFile> files;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('日志文件（${files.length} 个，最近的在前）',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: files.length,
                itemBuilder: (context, i) {
                  final f = files[i];
                  return ListTile(
                    dense: true,
                    title: Text(f.name),
                    subtitle: Text('${f.path}\n${formatBytes(f.size)} · ${f.mtime}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall),
                    onTap: () => Navigator.of(context).pop(f),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个日志的尾巴。行数只有 100 / 500 两档 —— 服务端上限就是 500。
class _LogTailSheet extends StatefulWidget {
  const _LogTailSheet({
    required this.file,
    required this.client,
    required this.onResult,
  });

  final OpsLogFile file;
  final OpsApiClient client;
  final void Function(bool ok, String detail) onResult;

  @override
  State<_LogTailSheet> createState() => _LogTailSheetState();
}

class _LogTailSheetState extends State<_LogTailSheet> {
  OpsLogTail? _tail;
  String? _error;
  bool _loading = true;
  int _lines = 100;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final t = await widget.client.logs(widget.file.path, lines: _lines);
      if (!mounted) return;
      setState(() {
        _tail = t;
        _loading = false;
      });
      widget.onResult(true, '读了 ${t.lines} 行${t.truncated ? '（已截断）' : ''}');
    } on OpsApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
      widget.onResult(false, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.file.name,
                style: theme.textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text('${formatBytes(widget.file.size)} · ${widget.file.mtime}',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final n in const [100, 500])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('$n 行'),
                      selected: _lines == n,
                      onSelected: (_) {
                        if (_lines == n) return;
                        setState(() => _lines = n);
                        _load();
                      },
                    ),
                  ),
                const Spacer(),
                if (_loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    tooltip: '重新读',
                    onPressed: _load,
                    icon: const Icon(Icons.refresh, size: 18),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error))
            else
              Flexible(
                child: SingleChildScrollView(
                  reverse: true,
                  child: SelectableText(
                    (_tail?.content ?? '').isEmpty
                        ? '（这个文件是空的）'
                        : _tail!.content,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
