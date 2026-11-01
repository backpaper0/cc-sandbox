#!/bin/bash
# Claude Code のステータスライン。
# 標準入力でセッション情報の JSON を受け取り、次の形式で1行出力する:
#   [モデル名] コンテキスト使用率 | コスト(USD と JPY) | 5時間・7日間のレート制限
input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
FIVE_H_PCT=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' | cut -d. -f1)
SEVEN_D_PCT=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' | cut -d. -f1)
FIVE_H_RESET_AT=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
SEVEN_D_RESET_AT=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; RESET='\033[0m'

# 使用率(0-100)に応じて色を選ぶ
color_for_pct() {
  local p="$1"
  if [ "$p" -ge 90 ]; then echo "$RED"
  elif [ "$p" -ge 70 ]; then echo "$YELLOW"
  else echo "$GREEN"; fi
}

# 使用率(0-100)からミニバーを作る
bar_for_pct() {
  local p="$1"
  local filled=$((p / 10)); local empty=$((10 - filled))
  printf -v fill "%${filled}s"; printf -v pad "%${empty}s"
  echo "${fill// /█}${pad// /░}"
}

# コンテキスト使用状況に基づいてバーの色を選択します
BAR_COLOR=$(color_for_pct "$PCT")
BAR=$(bar_for_pct "$PCT")

COST_FMT=$(printf '$%.2f' "$COST")

# USD -> JPY 為替レート取得(キャッシュ付き、失敗時はキャッシュ or 既定値にフォールバック)
# キャッシュファイルの中身は「レート UNIXタイムスタンプ」。6時間(21600秒)以内なら再取得しない
RATE_CACHE="$HOME/.claude/.usdjpy_rate_cache"
DEFAULT_RATE=150
USDJPY_RATE=""

if [ -f "$RATE_CACHE" ]; then
  CACHE_TS=$(cut -d' ' -f2 "$RATE_CACHE" 2>/dev/null)
  CACHE_RATE=$(cut -d' ' -f1 "$RATE_CACHE" 2>/dev/null)
  NOW=$(date +%s)
  if [ -n "$CACHE_TS" ] && [ -n "$CACHE_RATE" ] && [ $((NOW - CACHE_TS)) -lt 21600 ]; then
    USDJPY_RATE="$CACHE_RATE"
  fi
fi

if [ -z "$USDJPY_RATE" ]; then
  FETCHED=$(curl -s --max-time 2 "https://api.frankfurter.app/latest?from=USD&to=JPY" 2>/dev/null | jq -r '.rates.JPY // empty' 2>/dev/null)
  if [ -n "$FETCHED" ]; then
    USDJPY_RATE="$FETCHED"
    echo "$FETCHED $(date +%s)" > "$RATE_CACHE" 2>/dev/null
  elif [ -f "$RATE_CACHE" ]; then
    USDJPY_RATE=$(cut -d' ' -f1 "$RATE_CACHE" 2>/dev/null)
  fi
fi

[ -z "$USDJPY_RATE" ] && USDJPY_RATE="$DEFAULT_RATE"

JPY_VALUE=$(awk -v c="$COST" -v r="$USDJPY_RATE" 'BEGIN{printf "%.0f", c*r}')
JPY_FMT=$(printf '¥%s' "$JPY_VALUE" | sed ':a;s/\(¥[0-9]*\)\([0-9]\{3\}\)/\1,\2/;ta')
COST_FMT="${COST_FMT} (${JPY_FMT})"

# レート制限(5時間/7日間)の可視化
RATE_STR=""
if [ -n "$FIVE_H_PCT" ]; then
  FIVE_H_COLOR=$(color_for_pct "$FIVE_H_PCT")
  FIVE_H_BAR=$(bar_for_pct "$FIVE_H_PCT")
  FIVE_H_RESET_STR=""
  if [ -n "$FIVE_H_RESET_AT" ]; then
    FIVE_H_RESET_FMT=$(date -d "@${FIVE_H_RESET_AT}" "+%H:%M" 2>/dev/null || date -r "${FIVE_H_RESET_AT}" "+%H:%M" 2>/dev/null)
    [ -n "$FIVE_H_RESET_FMT" ] && FIVE_H_RESET_STR=" (→${FIVE_H_RESET_FMT})"
  fi
  RATE_STR="${RATE_STR} | 5h ${FIVE_H_COLOR}${FIVE_H_BAR}${RESET} ${FIVE_H_PCT}%${FIVE_H_RESET_STR}"
fi
if [ -n "$SEVEN_D_PCT" ]; then
  SEVEN_D_COLOR=$(color_for_pct "$SEVEN_D_PCT")
  SEVEN_D_BAR=$(bar_for_pct "$SEVEN_D_PCT")
  SEVEN_D_RESET_STR=""
  if [ -n "$SEVEN_D_RESET_AT" ]; then
    SEVEN_D_RESET_FMT=$(date -d "@${SEVEN_D_RESET_AT}" "+%m/%d %H:%M" 2>/dev/null || date -r "${SEVEN_D_RESET_AT}" "+%m/%d %H:%M" 2>/dev/null)
    [ -n "$SEVEN_D_RESET_FMT" ] && SEVEN_D_RESET_STR=" (→${SEVEN_D_RESET_FMT})"
  fi
  RATE_STR="${RATE_STR} | 7d ${SEVEN_D_COLOR}${SEVEN_D_BAR}${RESET} ${SEVEN_D_PCT}%${SEVEN_D_RESET_STR}"
fi

echo -e "${CYAN}[$MODEL]${RESET} ${BAR_COLOR}${BAR}${RESET} ${PCT}% | ${YELLOW}${COST_FMT}${RESET}${RATE_STR}"
