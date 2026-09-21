#!/usr/bin/env bash
# 免密钥公共接口可用性实测脚本。
#
# 用途：给「工具页接线」提供真实证据 —— 只有这里实测通过的接口才允许写进
# kToolTargets。每个接口连打 5 次，记录 HTTP 码、耗时、响应首段。
#
# 用法：bash tool/probe_public_apis.sh [次数]
set -uo pipefail

ROUNDS="${1:-5}"
UA='Mozilla/5.0 (Linux; Android 14) BoxApp/probe'

probe() {
  local name="$1" url="$2"
  local ok=0 total=0 body=""
  for _ in $(seq 1 "$ROUNDS"); do
    local out code time
    out=$(curl -s -m 8 -A "$UA" -w '\n__HTTP__%{http_code}__T__%{time_total}' "$url" 2>/dev/null)
    code=$(printf '%s' "$out" | tail -1 | sed -n 's/.*__HTTP__\([0-9]*\)__T__.*/\1/p')
    time=$(printf '%s' "$out" | tail -1 | sed -n 's/.*__T__\(.*\)/\1/p')
    [ "$code" = "200" ] && ok=$((ok+1))
    total=$((total+1))
    if [ -z "$body" ] && [ "$code" = "200" ]; then
      body=$(printf '%s' "$out" | sed '$d' | tr -d '\n' | cut -c1-220)
    fi
    LAST_TIME="$time"
  done
  printf '%-18s %s/%s  %ss  %s\n' "$name" "$ok" "$total" "${LAST_TIME:-?}" "${body:0:200}"
}

echo "════════ 免密钥接口实测（每个 ${ROUNDS} 次）════════"
probe "每日英语"      "https://open.iciba.com/dsapi/"
probe "60s读世界"     "https://60s.viki.moe/v2/60s"
probe "历史上的今天"   "https://60s.viki.moe/v2/today_in_history"
probe "垃圾分类"      "https://60s.viki.moe/v2/rubbish?word=%E7%94%B5%E6%B1%A0"
probe "老黄历"        "https://60s.viki.moe/v2/luck"
probe "汇率60s"       "https://60s.viki.moe/v2/exchange_rate?currency=CNY"
probe "农历/日历"     "https://60s.viki.moe/v2/today"
probe "必应壁纸"      "https://60s.viki.moe/v2/bing"
probe "百度热搜"      "https://60s.viki.moe/v2/baidu/realtime"
probe "IP查询60s"     "https://60s.viki.moe/v2/ip"
probe "成语词典"      "https://60s.viki.moe/v2/chengyu"
probe "藏头诗"        "https://60s.viki.moe/v2/acrostic?words=%E6%98%A5%E5%A4%8F%E7%A7%8B%E5%86%AC"
probe "汉字查询"      "https://60s.viki.moe/v2/hash?content=box"
probe "毒鸡汤"        "https://api.oick.cn/api/dutang"
probe "舔狗日记"      "https://api.oick.cn/api/tiangou"
probe "渣男语录"      "https://api.oick.cn/api/zhanan"
probe "彩虹屁"        "https://api.oick.cn/api/caihongpi"
probe "笑话"          "https://api.oick.cn/api/joke"
probe "脑筋急转弯"     "https://api.oick.cn/api/nnjzw"
probe "弱智吧"        "https://api.oick.cn/api/ruozhiba"
probe "菜谱搜索"      "https://api.pearktrue.cn/api/caipu/?keyword=%E7%95%AA%E8%8C%84"
probe "手机归属地"     "https://cx.shouji.360.cn/phonearea.php?number=13800138000"
probe "翻译LibreTr"   "https://translate.astian.org/languages"
probe "翻译MyMemory"  "https://api.mymemory.translated.net/get?q=hello&langpair=en|zh"
probe "近义词"        "https://api.pearktrue.cn/api/synonym/?word=%E9%AB%98%E5%85%B4"
probe "快递查询"      "https://api.pearktrue.cn/api/express/?number=SF1234567890"
echo "════════ 结束 ════════"
