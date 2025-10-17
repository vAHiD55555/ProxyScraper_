#!/usr/bin/env bash
# استفاده از -e برای خروج در صورت بروز خطا و -u برای جلوگیری از استفاده از متغیرهای تعریف نشده
set -euo pipefail

# این اسکریپت هم به صورت اتوماتیک در گیت‌هاب اکشن اجرا می‌شود و هم دستی قابل اجراست.
# استفاده:
# اجرای دستی: bash scripts/check_and_make_pac.sh [check|make|both]
# حالت‌ها: check (بررسی پراکسی)، make (ساخت PAC)، both (هر دو)
# در صورت عدم وجود آرگومان، حالت پیش‌فرض "both" اجرا می‌شود.

TIMEOUT=8
CHECK_URL="https://api.ipify.org"
OUT_PAC="proxies.pac"
OK_LIST="proxies_ok.txt"
BAD_LIST="proxies_failed.txt"
TMPDIR="tmp"
MAX_JOBS=12

# تغییر مسیر به پوشه اصلی پروژه
cd "$(dirname "$0")/.." || exit 1

# پاک کردن فایل‌های خروجی قبلی و ساخت فایل‌های خالی
rm -f "$OK_LIST" "$BAD_LIST" "$OUT_PAC"
touch "$OK_LIST" "$BAD_LIST"

# تابع برای ادغام فایل‌ها: حذف کامنت‌ها، حذف فضاهای خالی اضافی و خطوط خالی
merge_files() {
  local f="$1"
  if [[ -f "$f" ]]; then
    # sed: حذف هر چیزی بعد از #
    # awk: حذف فضاهای خالی ابتدا و انتهای خط و فشرده‌سازی فضاهای میانی
    # grep: حذف خطوط کاملاً خالی
    sed 's/#.*//g' "$f" | awk '{$1=$1};1' | grep -E '.+'
  fi
}

echo "[*] دریافت آی‌پی خارجی فعلی شما..."
# دریافت آی‌پی خارجی خودتان برای شناسایی پراکسی‌های سالم
LOCAL_IP=$(curl -s --max-time $TIMEOUT "$CHECK_URL" || echo "unknown")
echo "آی‌پی شما: $LOCAL_IP"

PROXIES=()
# جمع‌آوری پراکسی‌ها از فایل‌های موقت
for line in $(merge_files "$TMPDIR/http.txt"); do
  PROXIES+=("$line")
done
for line in $(merge_files "$TMPDIR/socks5.txt"); do
  PROXIES+=("$line")
done
# جمع‌آوری پراکسی‌ها از فایل proxies.txt
if [[ -f "proxies.txt" ]]; then
  while IFS= read -r l; do
    [[ -z "$l" ]] && continue
    PROXIES+=("$l")
  done < proxies.txt
fi

echo "[*] تعداد کل پراکسی‌ها: ${#PROXIES[@]}"

# تابع اصلی تست پراکسی - به صورت جداگانه export می‌شود تا توسط xargs قابل اجرا باشد
test_proxy_once() {
  proxy="$1"
  proto=""
  target="$proxy"

  # تشخیص پروتکل (socks5 یا http/https)
  if [[ "$proxy" =~ ^socks5 ]]; then
    proto="socks5"
    target="${proxy#*://}" # حذف "socks5://"
  elif [[ "$proxy" =~ ^https?:// ]]; then
    proto="http"
    target="${proxy#*://}" # حذف "http(s)://"
  elif echo "$proxy" | grep -q ':'; then
    proto="http"
    target="$proxy" # فرض می‌کنیم اگر پروتکل ذکر نشده باشد، http است.
  else
    return 1 # قالب نامعتبر
  fi

  # تنظیم گزینه‌های cURL بر اساس پروتکل
  if [[ "$proto" == "socks5" ]]; then
    curl_opts=(--socks5-hostname "$target")
  else
    curl_opts=(-x "http://$target")
  fi

  # تست اتصال: اگر آی‌پی با آی‌پی لوکال یکسان نباشد، پراکسی سالم است.
  out=$(curl -s "${curl_opts[@]}" --max-time $TIMEOUT --connect-timeout $TIMEOUT "$CHECK_URL" 2>/dev/null || echo "")

  # بررسی نتیجه: آیا خروجی غیر خالی است و با آی‌پی لوکال یکسان نیست؟
  if [[ -n "$out" && "$out" != "$LOCAL_IP" ]]; then
    echo "$proxy" >> "$OK_LIST"
    return 0 # پراکسی سالم
  else
    echo "$proxy" >> "$BAD_LIST"
    return 1 # پراکسی خراب
  fi
}

# export کردن تابع و متغیرهای مورد نیاز برای xargs
export -f test_proxy_once
export OK_LIST BAD_LIST LOCAL_IP TIMEOUT CHECK_URL

# --- اجرای حالت check ---
# اصلاح شده: استفاده از ${1:-} برای جلوگیری از خطای unbound variable
if [[ "${1:-}" == "check" || "${1:-}" == "both" || -z "${1:-}" ]]; then
  echo "[*] شروع بررسی پراکسی‌ها..."
  # اجرای تست‌ها به صورت موازی با استفاده از xargs
  printf "%s\n" "${PROXIES[@]}" | xargs -P "$MAX_JOBS" -I {} bash -c 'test_proxy_once "$@"' _ {}
  echo "[*] تعداد پراکسی سالم: $(wc -l < "$OK_LIST")"
  echo "[*] تعداد پراکسی خراب: $(wc -l < "$BAD_LIST")"
fi

# --- اجرای حالت make ---
# اصلاح شده: استفاده از ${1:-} برای جلوگیری از خطای unbound variable
if [[ "${1:-}" == "make" || "${1:-}" == "both" || -z "${1:-}" ]]; then
  if [[ -s "$OK_LIST" ]]; then
    proxy=$(head -n 1 "$OK_LIST")
    # ترفند ساده برای رمزگذاری (obfuscation) پراکسی
    proxy_obfuscated=$(echo "$proxy" | rev)
    
    # ساخت فایل PAC
    cat > "$OUT_PAC" <<EOF
function FindProxyForURL(url, host) {
  // این یک ترفند ساده برای رمزگذاری رشته "PROXY" است.
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
