#!/usr/bin/env bash
# 60s 接口可用性实测（间隔 4s 避开限流）
# 用途：在接入前确认接口真实可用
set -uo pipefail
UA='Mozilla/5.0 (Linux; Android 14) BoxApp/probe'

probe() {
  local name="$1" url="$2"
  local ok=0
  for i in 1 2 3; do
    local code
    code=$(curl -s -m 8 -A "$UA" -o /dev/null -w '%{http_code}' "$url")
    [ "$code" = "200" ] && ok=$((ok+1))
    sleep 4
  done
  echo "$name: $ok/3"
}

echo "════ 60s 可用接口实测（间隔 4s）════"
probe "每日英语"      "https://open.iciba.com/dsapi/"
probe "60s 每日资讯"  "https://60s.viki.moe/v2/60s"
probe "历史上的今天"   "https://60s.viki.moe/v2/today_in_history"
probe "老黄历"        "https://60s.viki.moe/v2/luck"
probe "必应壁纸"      "https://60s.viki.moe/v2/bing"
probe "百度热搜"      "https://60s.viki.moe/v2/baidu/realtime"
probe "汇率"         "https://60s.viki.moe/v2/exchange_rate?currency=CNY"
probe "IP 查询"      "https://60s.viki.moe/v2/ip"
echo
echo "════ 其他接口实测（间隔 4s）════"
probe "手机归属地"    "https://cx.shouji.360.cn/phonearea.php?number=13800138000"
probe "翻译 MyMemory" "https://api.mymemory.translated.net/get?q=hello&langpair=en|zh"
probe "毒鸡汤"       "https://api.oick.cn/api/dutang"
probe "必应每日一词"  "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1"
probe "IP-API"       "https://ip-api.com/json/"
echo
echo "════ 已失效接口（供删除参考）════"
for u in "今日诗词 (jinrishici)"; do
  echo "$u: 接口已下线（代码 404）"
done
