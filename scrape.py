import requests
from bs4 import BeautifulSoup
import random
import time
from fake_useragent import UserAgent  # برای نصب: pip install fake-useragent
import socket  # برای تست latency

# لیست لینک‌های منبع (شما باید این‌ها را جایگزین کنید)
source_urls = [
    "https://raw.githubusercontent.com/vAHiD55555/ProxyScraper_/refs/heads/main/proxies/socks.txt",  # لینک اول که دادید
    "https://raw.githubusercontent.com/vAHiD55555/ProxyScraper_/refs/heads/main/proxies/http.txt"   # لینک دوم که دادید
]

# تنظیمات
test_url = "http://www.google.com"  # URL برای تست پروکسی‌ها
max_latency = 2.0  # حداک��ر latency مجاز (ثانیه) - فقط پروکسی‌های سریع‌تر انتخاب می‌شوند
top_n_proxies = 10  # تعداد بهترین پروکسی‌ها برای خروجی
output_file = "proxy_pack.txt"

# فانکشن برای obfuscation: ایجاد User-agent تصادفی و delay
def get_random_headers():
    ua = UserAgent()
    return {
        "User-Agent": ua.random,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": random.choice(["en-US,en;q=0.5", "fa-IR,fa;q=0.8"]),
        "Referer": random.choice(source_urls)  # برای شبیه‌سازی مراجعه از یک سایت واقعی
    }

def scrape_proxies(url):
    headers = get_random_headers()
    try:
        response = requests.get(url, headers=headers, timeout=10)
        response.raise_for_status()  # چک کردن errorهای HTTP
        soup = BeautifulSoup(response.text, 'html.parser')
        
        # فرض کنیم پروکسی‌ها در یک table با تگ‌های خاص هستند (باید بر اساس سایت تنظیم شود)
        # مثال: اگر پروکسی‌ها در تگ td باشند
        proxies = []
        for row in soup.find_all('tr'):  # تنظیم بر اساس ساختار سایت
            cells = row.find_all('td')
            if len(cells) >= 2:  # فرض کنیم ستون اول IP و دوم Port باشد
                ip = cells[0].text.strip()
                port = cells[1].text.strip()
                proxy = f"http://{ip}:{port}"  # یا socks5، بسته به سایت
                proxies.append(proxy)
        return proxies
    except Exception as e:
        print(f"Error scraping {url}: {e}")
        return []

def test_proxy(proxy):
    # تست پروکسی با اندازه‌گیری latency
    try:
        start_time = time.time()
        proxies = {
            "http": proxy,
            "https": proxy
        }
        response = requests.get(test_url, proxies=proxies, timeout=5)
        end_time = time.time()
        latency = end_time - start_time
        if response.status_code == 200 and latency < max_latency:
            return proxy, latency  # بازگشت پروکسی و latency اگر موفق باشد
        else:
            return None, None
    except requests.RequestException:
        return None, None  # پروکسی کار نمی‌کند

def main():
    all_proxies = []
    
    # Scraping از هر لینک با obfuscation
    for url in source_urls:
        headers = get_random_headers()
        time.sleep(random.uniform(1, 5))  # delay تصادفی برای جلوگیری از ban
        proxies_from_source = scrape_proxies(url)
        all_proxies.extend(proxies_from_source)
        time.sleep(random.uniform(2, 4))  # delay بیشتر بین سایت‌ها
    
    # حذف duplicates و تست پروکسی‌ها
    unique_proxies = list(set(all_proxies))
    working_proxies = []
    for proxy in unique_proxies:
        tested_proxy, latency = test_proxy(proxy)
        if tested_proxy:
            working_proxies.append((tested_proxy, latency))  # ذخیره پروکسی و latency
    
    # sort بر اساس latency (کمترین latency بهترین است)
    working_proxies.sort(key=lambda x: x[1])
    
    # انتخاب top N
    top_proxies = [proxy for proxy, _ in working_proxies[:top_n_proxies]]
    
    # ساخت فایل خروجی
    with open(output_file, "w") as f:
        for proxy in top_proxies:
            f.write(f"{proxy}\n")  # یا می‌توانید نوع پروکسی (http/socks) اضافه کنید
    
    print(f"فایل {output_file} با {len(top_proxies)} پروکسی برتر ساخته شد.")

if __name__ == "__main__":
    main()
