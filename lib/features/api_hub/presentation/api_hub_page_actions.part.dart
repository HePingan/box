part of './api_hub_page.dart';

// 加载与动作方法：_runActiveTool 的分发、各 _loadXxx 请求、纯本地构建
// （占位图 / 二维码 / 头像 / 封面）以及请求守卫 _guard。
//
// on `_ApiHubPageStateBase` 让它能直接读写状态的私有字段
// （_client / _error / _loading / 各 controller …）。

mixin _ApiHubPageActions on _ApiHubPageStateBase {
  Future<void> _runActiveTool() async {
    switch (_activeTool) {
      case 'currency':
        await _loadCurrency();
        return;
      case 'holidays':
        await _loadHolidays();
        return;
      case 'ip':
        await _loadIpInfo();
        return;
      case 'shortlink':
        return;
      case 'dictionary':
        await _loadDictionary();
        return;
      case 'books':
        await _searchBooks();
        return;
      case 'hitokoto':
        await _loadHitokoto();
        return;
      case 'poetry':
        await _loadPoetry();
        return;
      case 'dummy_image':
        _buildDummyImage();
        return;
      case 'qr':
        _buildQrCode();
        return;
      case 'avatar':
        _buildAvatar();
        return;
      case 'cover':
        _buildCoverImage();
        return;
      case 'mock':
        await _loadMockUsers();
        return;
      case 'directory':
        await _searchDirectory();
        return;
      // ——— A-1 本轮接线 ———
      case 'daily_english':
        await _loadDailyEnglish();
        return;
      case 'news60s':
        await _loadNews60s();
        return;
      case 'today_in_history':
        await _loadTodayInHistory();
        return;
      case 'luck':
        await _loadLuck();
        return;
      case 'bing_wallpaper':
        await _loadBingWallpaper();
        return;
      case 'baidu_hot':
        await _loadBaiduHot();
        return;
      case 'exchange_rate':
        await _loadExchangeRate();
        return;
      case 'ip_query':
        await _loadIpQuery();
        return;
      case 'phone_area':
        // 归属地必须由用户输入号码才有意义，不自动请求。
        return;
      case 'translate':
        // 翻译同理，等用户点「翻译」。
        return;
      case 'weibo_hot':
        await _loadHotList('weibo_hot');
        return;
      case 'zhihu_hot':
        await _loadHotList('zhihu_hot');
        return;
      case 'douyin_hot':
        await _loadHotList('douyin_hot');
        return;
      case 'toutiao_hot':
        await _loadHotList('toutiao_hot');
        return;
      case 'fortune':
        await _loadFortune();
        return;
      case 'moyu':
        await _loadMoyu();
        return;
      case 'dujitang':
        await _loadQuote('dujitang');
        return;
      case 'chp':
        await _loadQuote('chp');
        return;
      case 'maoyan':
        await _loadBoxOffice();
        return;
      case 'epic':
        await _loadEpicGames();
        return;
      case 'weather':
      default:
        await _loadWeather();
        return;
    }
  }

  Future<void> _loadCurrency() async {
    await _guard(() async {
      final amount = double.tryParse(_amountController.text.trim()) ?? 1;
      _converted = await _client.convertCurrency(
        amount: amount,
        from: _from,
        to: _to,
      );
      _rates = await _client.latestRates(base: _from);
    });
  }

  Future<void> _loadHolidays() async {
    await _guard(() async {
      _holidays = await _client.publicHolidays(
        year: DateTime.now().year,
        countryCode: 'CN',
      );
    });
  }

  Future<void> _loadWeather() async {
    await _guard(() async {
      _weather = await _client.weatherForecast(
        latitude: double.tryParse(_latController.text.trim()) ?? 31.2304,
        longitude: double.tryParse(_lonController.text.trim()) ?? 121.4737,
        days: 3,
      );
    });
  }

  Future<void> _loadDictionary() async {
    await _guard(() async {
      _dictionary = await _client.dictionaryLookup(_wordController.text);
    });
  }

  Future<void> _loadIpInfo() async {
    await _guard(() async {
      _ipInfo = await _client.currentIpInfo();
    });
  }

  Future<void> _shortenUrl() async {
    await _guard(() async {
      _shortLink = await _client.shortenUrl(_shortLinkController.text);
    });
  }

  void _buildDummyImage() {
    setState(() {
      _error = null;
      _dummyImage = _client.buildDummyImage(
        size: _imageSizeController.text,
        background: _imageBgController.text,
        foreground: _imageFgController.text,
        text: _imageTextController.text,
      );
    });
  }

  void _buildQrCode() {
    setState(() {
      _error = null;
      _qrCode = _client.buildQrCode(
        text: _qrTextController.text,
        size: _qrSizeController.text,
      );
    });
  }

  void _buildAvatar() {
    setState(() {
      _error = null;
      _avatar = _client.buildAvatar(
        name: _avatarNameController.text,
        background: _avatarBgController.text,
        foreground: _avatarFgController.text,
        size: _avatarSizeController.text,
      );
    });
  }

  void _buildCoverImage() {
    setState(() {
      _error = null;
      _coverImage = _client.buildCoverImage(
        width: _coverWidthController.text,
        height: _coverHeightController.text,
        seed: _coverSeedController.text,
      );
    });
  }

  Future<void> _searchBooks() async {
    await _guard(() async {
      _books = await _client.searchOpenLibrary(_bookController.text);
    });
  }

  Future<void> _loadHitokoto() async {
    await _guard(() async {
      _hitokoto = await _client.randomHitokoto();
    });
  }

  Future<void> _loadPoetry() async {
    await _guard(() async {
      _poetry = await _client.randomPoetry();
    });
  }

  Future<void> _loadMockUsers() async {
    await _guard(() async {
      _mockUsers = await _client.mockUsers(limit: 8);
    });
  }

  // ——— A-1 本轮接线的加载方法 ———

  Future<void> _loadDailyEnglish() async {
    await _guard(() async {
      _dailyEnglish = await _client.dailyEnglish();
    });
  }

  Future<void> _loadNews60s() async {
    await _guard(() async {
      _news60s = await _client.news60s();
    });
  }

  Future<void> _loadTodayInHistory() async {
    await _guard(() async {
      _historyEvents = await _client.todayInHistory();
    });
  }

  Future<void> _loadLuck() async {
    await _guard(() async {
      _luck = await _client.dailyLuck();
    });
  }

  Future<void> _loadBingWallpaper() async {
    await _guard(() async {
      _bingWallpaper = await _client.bingWallpaper();
    });
  }

  Future<void> _loadBaiduHot() async {
    await _guard(() async {
      _hotSearches = await _client.baiduHotSearch(limit: 30);
    });
  }

  // —— A-2 本轮接线：热榜 / 运势 / 摸鱼 / 语录 ——

  /// 热榜类统一加载，按 id 选平台。四个接口同源同构，只有路径不同。
  Future<void> _loadHotList(String id) async {
    await _guard(() async {
      switch (id) {
        case 'weibo_hot':
          _hotList = await _client.weiboHotSearch(limit: 30);
          return;
        case 'zhihu_hot':
          _hotList = await _client.zhihuHotSearch(limit: 30);
          return;
        case 'douyin_hot':
          _hotList = await _client.douyinHotSearch(limit: 30);
          return;
        case 'toutiao_hot':
          _hotList = await _client.toutiaoHotSearch(limit: 30);
          return;
      }
    });
  }

  Future<void> _loadFortune() async {
    await _guard(() async {
      _fortune = await _client.dailyFortune();
    });
  }

  Future<void> _loadMoyu() async {
    await _guard(() async {
      _moyu = await _client.moyuCalendar();
    });
  }

  Future<void> _loadBoxOffice() async {
    await _guard(() async {
      _boxOffice = await _client.boxOfficeRank(limit: 30);
    });
  }

  Future<void> _loadEpicGames() async {
    await _guard(() async {
      _epicGames = await _client.epicFreeGames();
    });
  }

  /// 语录类统一加载，按 id 选接口。
  Future<void> _loadQuote(String id) async {
    await _guard(() async {
      _quote = id == 'dujitang'
          ? await _client.dujitang()
          : await _client.rainbowFart();
    });
  }

  Future<void> _loadExchangeRate() async {
    await _guard(() async {
      _exchangeRate = await _client.exchangeRates(currency: 'CNY');
    });
  }

  Future<void> _loadIpQuery() async {
    await _guard(() async {
      _ipQuery = await _client.queryIp(ip: _ipQueryController.text.trim());
    });
  }

  Future<void> _loadPhoneArea() async {
    final number = _phoneController.text.trim();
    if (number.isEmpty) {
      setState(() => _error = '请输入手机号');
      return;
    }
    await _guard(() async {
      _phoneArea = await _client.phoneArea(number);
    });
  }

  Future<void> _runTranslate() async {
    final text = _translateController.text.trim();
    if (text.isEmpty) {
      setState(() => _error = '请输入要翻译的内容');
      return;
    }
    await _guard(() async {
      _translation = await _client.translate(
        text: text,
        from: _translateFrom,
        to: _translateTo,
      );
    });
  }

  Future<void> _searchDirectory() async {
    await _guard(() async {
      _directoryEntries = await PublicApiIndexLoader.search(
        query: _directoryController.text,
        category: _directoryCategory == '全部' ? null : _directoryCategory,
        noAuthOnly: true,
        httpsOnly: true,
        domesticOnly: true,
        limit: 80,
      );
    });
  }

  Future<void> _guard(Future<void> Function() run) async {
    // intent 用当前工具：切换工具后，旧工具的慢响应/报错不得再写状态，
    // 否则会出现「已经在看 IP，却弹天气接口的错误」这种串台。
    final token = _requestGeneration.begin(_activeTool);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await run();
    } catch (e) {
      // 原来是裸赋值：既没判过期，也没 setState —— 错误压根刷不到界面上。
      if (!mounted || !_requestGeneration.isCurrent(token)) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted && _requestGeneration.isCurrent(token)) {
        setState(() => _loading = false);
      }
    }
  }
}
