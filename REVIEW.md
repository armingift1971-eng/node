# بررسی فنی PasarGuard-Node روی Railway

**تاریخ بررسی:** 2026-10-02  
**مخزن:** `https://github.com/x4gpanell/PasarGuard-Node`  
**commit بررسی‌شده:** `43f5de960e491a4c59d2b40d1ba7a90651cb85e0`  
**شاخه:** `main`  
**وضعیت مخزن:** public، فقط دو فایل اجرایی، بدون source code پنل یا اپلیکیشن Node.js مستقل

## 1. نتیجه اجرایی

این پروژه خودش «پنل پاسارگاد» نیست؛ یک image wrapper بسیار کوچک برای اجرای image رسمی `pasarguard/node:latest` است. تمام منطق اصلی از image upstream می‌آید و repository فعلی فقط این کارها را انجام می‌دهد:

1. نصب `openssl` روی image رسمی.
2. ساخت خودکار گواهی self-signed در `/var/lib/pg-node/certs`.
3. ساخت یا بازیابی API key از `/var/lib/pg-node/api_key.txt`.
4. چاپ Address، Port، API Key و متن certificate در log.
5. اجرای `./main` متعلق به image رسمی PasarGuard Node.

بنابراین تغییرات UI، API پنل، مدیریت کاربران یا منطق Xray در این مخزن قابل انجام نیست؛ مگر اینکه هدف تغییر wrapper، startup، پیکربندی deployment یا fork کردن source اصلی upstream باشد.

## 2. فایل‌های موجود

| فایل | نقش | وضعیت |
|---|---|---|
| `Dockerfile` | ساخت image از `pasarguard/node:latest` و تعریف environment/entrypoint | ساده و قابل build، ولی وابسته به tag شناور `latest` |
| `entrypoint.sh` | ساخت certificate/API key و اجرای `./main` | از نظر `sh -n` سالم، اما چند ریسک عملیاتی دارد |
| `REVIEW.md` | همین گزارش | افزوده‌شده در محیط بررسی |

هیچ‌کدام از موارد زیر در مخزن فعلی وجود ندارد: `package.json`، کد JavaScript/TypeScript، backend پنل، frontend، migration، تست، `railway.toml`، healthcheck، compose file، lockfile یا CI.

## 3. جریان اجرای فعلی

### Dockerfile

```dockerfile
FROM pasarguard/node:latest
RUN apk add --no-cache openssl
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENV NODE_HOST=0.0.0.0 \\
    SERVICE_PORT=62050 \\
    SSL_CERT_FILE=/var/lib/pg-node/certs/ssl_cert.pem \\
    SSL_KEY_FILE=/var/lib/pg-node/certs/ssl_key.pem
ENTRYPOINT ["/entrypoint.sh"]
```

### entrypoint

- `DATA_DIR=/var/lib/pg-node`
- certificate: `/var/lib/pg-node/certs/ssl_cert.pem`
- private key: `/var/lib/pg-node/certs/ssl_key.pem`
- generated API key: `/var/lib/pg-node/api_key.txt`
- hostname گواهی: `${RAILWAY_PRIVATE_DOMAIN:-node}`
- اگر فایل‌های certificate وجود نداشته باشند، گواهی RSA 2048 با اعتبار 3650 روز ساخته می‌شود.
- اگر `API_KEY` از قبل تعیین نشده باشد، از volume خوانده یا UUID تصادفی ساخته می‌شود.
- در پایان `exec ./main` اجرا می‌شود.

## 4. مقایسه با upstream

در upstream فعلی PasarGuard Node نسخه `v0.5.4`، image رسمی این متغیرها را می‌خواند:

- `SERVICE_PORT`، مقدار پیش‌فرض `62050`
- `NODE_HOST`، مقدار پیش‌فرض `0.0.0.0`
- `SERVICE_PROTOCOL`، مقدار پیش‌فرض `grpc`
- `API_KEY`، باید UUID معتبر باشد
- `SSL_CERT_FILE` و `SSL_KEY_FILE`
- `GENERATED_CONFIG_PATH`
- تنظیمات WireGuard با پیشوند `PG_NODE_WG_*`

upstream هنگام startup certificate و key را فقط load می‌کند و خودش گواهی را تولید نمی‌کند؛ این بخش کاملاً توسط wrapper فعلی انجام می‌شود.

احراز هویت API در upstream با header زیر انجام می‌شود:

```text
x-api-key: <valid UUID>
```

گواهی client باید با certificate سرور trust شود و hostname آن با SAN certificate مطابقت داشته باشد.

## 5. موارد درست و مثبت

- `NODE_HOST=0.0.0.0` برای container درست است.
- مسیرهای certificate با defaultهای upstream هماهنگ‌اند.
- استفاده از volume برای نگه‌داری certificate و API key ایده درستی است.
- `exec ./main` باعث می‌شود process اصلی PID 1 باشد و signalهای Railway را بهتر دریافت کند.
- `set -e` باعث می‌شود در صورت شکست جدی ساخت certificate، container بی‌صدا ادامه ندهد.
- quotation بیشتر مسیرها و متغیرهای shell رعایت شده است.
- `sh -n entrypoint.sh` بدون خطا اجرا شد.
- در مخزن بررسی‌شده secret hardcode‌شده، درخواست شبکه هنگام startup یا `eval` مشاهده نشد.

## 6. مشکلات و ریسک‌های مهم

### بحرانی/عملیاتی

#### 6.1 استفاده از `pasarguard/node:latest`

هر deploy مجدد ممکن است بدون تغییر کد wrapper، نسخه متفاوت upstream را دریافت کند. این موضوع می‌تواند باعث تغییر API، رفتار certificate، dependency یا ناسازگاری با پنل شود.

**پیشنهاد:** image را به نسخه ثابت pin کنید، مثلاً یک tag معتبر upstream مثل `pasarguard/node:v0.5.4` یا digest دقیق. پس از تست، فقط به‌صورت کنترل‌شده update شود.

#### 6.2 پورت برای Railway قابل تنظیم نیست

Dockerfile و entrypoint مقدار `SERVICE_PORT=62050` را hardcode کرده‌اند و `PORT` تزریق‌شده توسط Railway را نادیده می‌گیرند. اگر public TCP proxy یا تنظیم port سرویس روی 62050 نباشد، سرویس از بیرون در دسترس نخواهد بود.

**نکته:** Railway private networking فقط بین serviceهای همان project/environment قابل استفاده است. `RAILWAY_PRIVATE_DOMAIN` آدرس داخلی است، نه آدرس عمومی قابل اتصال از هر پنل خارجی.

**پیشنهاد:** رفتار مورد انتظار را مشخص کنید:

- اگر پنل و node در یک Railway project هستند: private domain و port داخلی مناسب است.
- اگر پنل بیرون از Railway است: باید public TCP exposure/domain و mapping صحیح port تنظیم شود.
- اگر Railway port متغیر می‌دهد: `SERVICE_PORT` باید از `PORT` با fallback مناسب استفاده کند، مشروط به اینکه نوع proxy انتخابی واقعاً gRPC/TLS را پشتیبانی کند.

#### 6.3 نیازمندی‌های WireGuard روی Railway

upstream Docker Compose برای قابلیت‌های WireGuard از `NET_ADMIN` و kernel interface استفاده می‌کند. image رسمی ابزارهای WireGuard، nftables و iproute2 را دارد، اما Dockerfile فعلی هیچ `cap_add`ای تعریف نمی‌کند و Railway نیز ممکن است اجازه لازم برای kernel WireGuard را ندهد.

در نتیجه ممکن است خود API بالا بیاید ولی backendهای WireGuard/Xray یا routing عملیاتی کار نکنند.

**پیشنهاد:** قبل از هر تغییر، مشخص کنید این deployment فقط node کنترل‌گر است یا باید واقعاً tunnel/WireGuard و ترافیک proxy را اجرا کند. اگر WireGuard لازم است، محدودیت قابلیت‌های Railway باید با یک smoke test واقعی بررسی شود؛ صرفاً بالا آمدن process کافی نیست.

#### 6.4 وابستگی به volume

بدون volume متصل به `/var/lib/pg-node`، با restart/redeploy certificate و API key دوباره ساخته می‌شوند. در آن حالت پنل ممکن است به‌دلیل تغییر certificate یا API key دیگر نتواند به node وصل شود.

**الزام deployment:** یک Railway Volume با mount path دقیق `/var/lib/pg-node`.

### امنیتی

#### 6.5 چاپ API key خصوصی در log

اسکریپت API key را در log چاپ می‌کند. Logهای Railway معمولاً توسط اعضای پروژه قابل مشاهده‌اند و ممکن است export یا forward شوند.

**پیشنهاد:** API key را فقط هنگام setup به روش کنترل‌شده نمایش دهید، یا با flag اختیاری چاپ کنید؛ در حالت عادی مقدار کامل در log نوشته نشود.

#### 6.6 سطح دسترسی فایل‌ها صریح نیست

فایل API key با mode پیش‌فرض process ساخته می‌شود و certificate/private key نیز mode صریح ندارند. در image فعلی process احتمالاً root است، اما بهتر است permissionها مشخص باشند:

- directory با `0700`
- API key و private key با `0600`
- certificate عمومی با `0644`

#### 6.7 ساخت certificate با heredoc و مقدار محیطی خام

`RAILWAY_PRIVATE_DOMAIN` مستقیماً داخل فایل openssl config قرار می‌گیرد. این مقدار در حالت عادی توسط Railway کنترل می‌شود، ولی برای robustness باید validate شود و فقط hostname معتبر پذیرفته شود. در غیر این صورت newline یا کاراکترهای خاص می‌توانند config را خراب کنند.

#### 6.8 نبودن key rotation/renewal

certificate ده‌ساله ساخته می‌شود و فقط نبودن فایل بررسی می‌شود. اگر hostname، SAN یا key تغییر کند، اسکریپت certificate قدیمی را نگه می‌دارد و آن را regenerate نمی‌کند.

**پیشنهاد:** metadata certificate با hostname فعلی بررسی شود و در صورت mismatch، با رفتار مشخص rotate شود؛ البته rotation باید با اطلاع پنل انجام شود.

#### 6.9 API key دستی validate نمی‌شود

اگر `API_KEY` در Railway Variables اشتباه یا non-UUID باشد، wrapper آن را بدون validation export می‌کند و خطا در upstream رخ می‌دهد. بهتر است startup قبل از اجرای `main` UUID را validate کند و پیام واضح بدهد.

### نگه‌داری و reproducibility

- هیچ healthcheck یا smoke test وجود ندارد.
- هیچ CI برای build image یا shell lint وجود ندارد.
- source image به صورت mutable از Docker Hub دریافت می‌شود.
- هیچ README یا راهنمای Railway داخل fork وجود ندارد.
- `Dockerfile` و اسکریپت کامنت فارسی دارند که مشکلی ندارد، ولی مستندات deployment کافی نیست.
- در sandbox ابزار `docker` و `shellcheck` نصب نبود؛ بنابراین image build و lint کامل انجام نشد. بررسی syntax با `sh -n` موفق بود.

## 7. چک‌لیست صحیح deployment روی Railway

1. ساخت service از همین repository و اطمینان از تشخیص `Dockerfile`.
2. ساخت Volume با mount path `/var/lib/pg-node`.
3. تعیین `API_KEY` به‌صورت UUID معتبر و نگه‌داری امن آن.
4. تصمیم‌گیری درباره `SERVICE_PROTOCOL=grpc` یا `rest`؛ رفتار فعلی پیش‌فرض gRPC است.
5. تنظیم public TCP یا private networking بر اساس محل پنل.
6. اطمینان از اینکه port خارجی به port داخلی `62050` map می‌شود، یا اصلاح wrapper برای استفاده از port runtime.
7. ثبت certificate تولیدشده در پنل، با hostname دقیقاً مطابق SAN آن.
8. تست TLS و احراز هویت با `x-api-key`.
9. تست endpointهای پایه و سپس تست backend/Xray/WireGuard.
10. pin کردن نسخه image پس از موفقیت smoke test.

## 8. تست‌هایی که انجام شد

- clone موفق مخزن public.
- بررسی commit، branch و tree.
- بررسی کامل Dockerfile و entrypoint.
- بررسی upstream source/config/listener/auth/TLS.
- `sh -n entrypoint.sh`: موفق.
- بررسی وجود secret hardcode‌شده یا network fetch در wrapper: موردی مشاهده نشد.
- build واقعی Docker: انجام نشد، چون executable مربوط به Docker در sandbox موجود نیست.
- shell lint با ShellCheck: انجام نشد، چون ShellCheck در sandbox موجود نیست.
- تست واقعی Railway، volume، public TCP و WireGuard: بدون credential/project Railway قابل انجام نیست.

## 9. پیشنهاد ترتیب تغییرات بعدی

### مرحله اول: پایدارسازی deployment

- pin کردن image version/digest
- configurable کردن port و hostname
- validate کردن UUID API key
- permission صحیح فایل‌ها
- اضافه کردن healthcheck/smoke test
- مستندسازی کامل متغیرها و Volume Railway

### مرحله دوم: رفع امنیت عملیاتی

- حذف چاپ کامل API key از log یا gated کردن آن
- کنترل SAN و hostname
- طراحی rotation برای certificate/key
- اضافه کردن حداقل‌های امنیتی container در صورت سازگاری با upstream

### مرحله سوم: سازگاری واقعی با Railway

- تصمیم قطعی private/public networking
- تست gRPC over TLS از محل پنل
- بررسی محدودیت NET_ADMIN/WireGuard
- در صورت عدم امکان WireGuard در Railway، تفکیک control-plane و data-plane یا انتقال node به VM مناسب

## 10. جمع‌بندی برای شروع تغییرات

این fork برای «اجرای سریع PasarGuard Node با certificate و API key خودکار» طراحی شده و در حالت ساده قابل فهم است؛ اما هنوز production-ready و Railway-agnostic نیست. مهم‌ترین سؤال قبل از پیاده‌سازی تغییرات این است:

> آیا هدف فقط بالا آوردن API node روی Railway است، یا باید Xray/WireGuard و عبور واقعی ترافیک کاربران نیز داخل Railway انجام شود؟

پاسخ این سؤال معماری و نوع تغییرات بعدی را کاملاً تعیین می‌کند.
