#!/usr/bin/env bash
set -euo pipefail

# این اسکریپت هم به صورت اتوماتیک در گیت‌هاب اکشن اجرا می‌شود و هم دستی قابل اجراست.
# استفاده:
# اجرای دستی: bash scripts/check_and_make_pac.sh [check|make|both]
# حالت‌ها: check (بررسی پراکسی)، make (ساخت PAC)، both (هر دو)

TIMEOUT=8
CHECK_URL="https://api.ipify.org"
OUT_PAC="proxies.pac"
OK_LIST="proxies_ok.txt"
BAD_LIST="proxies_failed.txt"
TMPDIR="tmp"
MAX_JOBS=12

cd "$(dirname "$0")/.." || exit 1

rm -f "$OK_LIST" "$BAD_LIST" "$OUT_PAC"
touch "$OK_LIST" "$BAD_LIST"

merge_files() {
  local f="$1"
  if [[ -f "$f" ]]; then
    sed 's/#.*//g' "$f" | awk '{$1=$1};1' | grep -E '.+'
  fi
}

echo "[*] دریافت آی‌پی خارجی..."
LOCAL_IP=$(curl -s --max-time $TIMEOUT $CHECK_URL || echo "unknown")
echo "آی‌پی شما: $LOCAL_IP"

PROXIES=()
for line in $(merge_files "$TMPDIR/http.txt"); do
  PROXIES+=("$line")
done
for line in $(merge_files "$TMPDIR/socks5.txt"); do
  PROXIES+=("$line")
done
if [[ -f "proxies.txt" ]]; then
  while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    PROXIES+=("$l")
  done < proxies.txt
fi

echo "[*] تعداد کل پراکسی‌ها: ${#PROXIES[@]}" # <-- خط ۶۰ اصلاح شد.

test_proxy_once() {
  proxy="$1"
  proto=""
  target="$proxy"
  if [[ "$proxy" =~ ^socks5 ]]; then
    proto="socks5"
    target="${proxy#*://}"
  elif [[ "$proxy" =~ ^https?:// ]]; then
    proto="http"
    target="${proxy#*://}"
  elif echo "$proxy" | grep -q ':'; then
    proto="http"
    target="$proxy"
  else
    return 1
  fi

  if [[ "$proto" == "socks5" ]]; then
    curl_opts=(--socks5-hostname "$target")
  else
    curl_opts=(-x "http://$target")
  fi

  out=$(curl -s "${curl_opts[@]}" --max-time $TIMEOUT --connect-timeout $TIMEOUT "$CHECK_URL" 2>/dev/null || echo "")
  if [[ -n "$out" && "$out" != "$LOCAL_IP" ]]; then
    echo "$proxy" >> "$OK_LIST"
    return 0
  else
    echo "$proxy" >> "$BAD_LIST"
    return 1
  fi
}

export -f test_proxy_once
export OK_LIST BAD_LIST LOCAL_IP TIMEOUT CHECK_URL

if [[ "$1" == "check" || "$1" == "both" || -z "$1" ]]; then
  printf "%s\n" "${PROXIES[@]}" | xargs -P $MAX_JOBS -I {} bash -c 'test_proxy_once "$@"' _ {}
echo "[*] تعداد پراکسی سالم: $(wc -l < "$OK_LIST")"
echo "[*] تعداد پراکسی خراب: $(wc -l < "$BAD_LIST")"
fi

if [[ "$1" == "make" || "$1" == "both" || -z "$1" ]]; then
  if [[ -s "$OK_LIST" ]]; then
    proxy=$(head -n 1 "$OK_LIST")
    proxy_obfuscated=$(echo "$proxy" | rev)
    cat > "$OUT_PAC" <<EOF
function FindProxyForURL(url, host) {
  var p = "Y" + "X" + "O" + "R" + "P";
  var proxy = p.split("").reverse().join("") + " " + "$proxy_obfuscated".split("").reverse().join("");
  return proxy + "; DIRECT";
}
EOF
    echo "[*] فایل PAC با پراکسی سالم ساخته شد: $OUT_PAC"
  else
    echo "[!] پراکسی سالم پیدا نشد، فایل PAC ساخته نشد."
  fi
fi

echo "[*] اسکریپت با موفقیت اجرا شد."
echo "برای اجرای دستی کافی است دستور زیر را بزنید:"
echo "bash scripts/check_and_make_pac.sh [check|make|both]"
