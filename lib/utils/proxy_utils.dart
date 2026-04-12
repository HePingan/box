/// 全局代理包裹函数：让一切资源走你的专属 shuabu 节点
String wrapWithProxy(String rawUrl) {
  final url = rawUrl.trim();
  if (url.isEmpty || !url.startsWith('http')) return url;
  
  // 刚才你配好的专属域名！
  const proxyHost = 'https://proxy.shuabu.eu.org';
  
  if (url.contains('shuabu.eu.org')) return url; // 防止重复套娃
  
  // 效果：https://proxy.shuabu.eu.org/https://api.zuidapi.com/...
  return '$proxyHost/$url';
}