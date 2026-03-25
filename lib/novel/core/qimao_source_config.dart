class QimaoSourceConfig {
  const QimaoSourceConfig._();

  static const String baseUrl = 'http://api.lemiyigou.com';

  static const Map<String, String> headers = {
    'User-Agent': 'okhttp/4.9.2',
    'client-device': '2d37f6b5b6b2605373092c3dc65a3b39',
    'client-brand': 'Redmi',
    'client-version': '2.3.0',
    'client-name': 'app.maoyankanshu.novel',
    'client-source': 'android',
          'Authorization': 'bearereyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJodHRwOlwvXC9hcGkuanhndHp4Yy5jb21cL2F1dGhcL3RoaXJkIiwiaWF0IjoxNjgzODkxNjUyLCJleHAiOjE3NzcyMDM2NTIsIm5iZiI6MTY4Mzg5MTY1MiwianRpIjoiR2JxWmI4bGZkbTVLYzBIViIsInN1YiI6Njg3ODYyLCJwcnYiOiJhMWNiMDM3MTgwMjk2YzZhMTkzOGVmMzBiNDM3OTQ2NzJkZDAxNmM1In0.mMxaC2SVyZKyjC6rdUqFVv5d9w_X36o0AdKD7szvE_Q',
  };
}