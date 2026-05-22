# JS Tracker — Поведенческий сборщик метрик для APK-клоаки

Это клиентская часть системы фильтрации. JavaScript-файл инжектится в Android WebView, тихо собирает метрики устройства и поведения юзера, потом отправляет их на бэкенд. Бэкенд скорит эти данные и решает — реальный это человек или эмулятор/модератор.

Скрипт полностью обфусцирован — все строки зашифрованы RC4, имена переменных в hex, control flow запутан. Модератор Google при анализе сетевых запросов не увидит ничего подозрительного.

---

## Что собирает и зачем

| Метрика | Как собирает | Зачем |
|---------|-------------|-------|
| Батарея | `navigator.getBattery()` | Эмуляторы отдают level=100%, chargingTime=0 — фейковые значения |
| Акселерометр | `devicemotion` event | Реальные телефоны вибрируют (микродвижения), эмуляторы — нулевая девиация |
| Таймзона | `Intl.DateTimeFormat().resolvedOptions().timeZone` | Сверяем с IP через IPinfo. Moscow + IP из LA = палево |
| Мышь vs Тач | `mousedown` + `touchstart` events | Клики мышкой без тач-событий = десктоп или эмулятор |
| WebGL GPU | `WEBGL_debug_renderer_info` | SwiftShader, VirtualBox, VMware = 100% эмулятор |
| Canvas FP | `canvas.toDataURL()` → hash | Уникальный отпечаток рендерера |
| Экран | `screen.width/height`, `devicePixelRatio` | Проверка разрешения и плотности |
| Железо | `navigator.hardwareConcurrency`, `deviceMemory` | 2 cores + 2GB = слабовато для реального юзера |
| Язык | `navigator.language` | Английский на русском трафике = подозрительно |
| Touch | `'ontouchstart' in window` | Нет тач-поддержки = десктоп |

---

## Как работает

```
WebView загружает tracker.js
         ↓
Мгновенно собирает: экран, WebGL, язык, тач, железо
         ↓
3 секунды собирает: батарея, акселерометр
         ↓
POST /api/collect → JSON со всеми метриками
         ↓
Бэкенд (scoring engine) скорит данные
         ↓
Результат пишется в PostgreSQL
         ↓
Видно в админке → Audit Log → клик → вкладка "JS метрики"
```

---

## Скоринг на бэкенде (что проверяется)

| Проверка | Баллы | Порог |
|----------|-------|-------|
| WebGL GPU в стоп-листе (SwiftShader etc) | +100 | автобан |
| Акселерометр < 0.08 m/s² (static_device) | +30 | конфигурируемый |
| Мышь без тача | +30 | конфигурируемый |
| Фейковая батарея (100%, chargingTime=0) | +50 | — |
| Таймзона расходится с IP > 2ч | +15 | timezoneDriftHours из конфига |
| Нет touch support | +20 | — |

---

## Обфускация

Исходник: `tracker.js` (5KB, читаемый)
Продакшн: `tracker.min.js` (94KB, каша из hex-массивов)

Пересобрать:
```bash
cd js-scripts
npm install
npm run build
```

Что применяется:
- RC4 шифрование всех строк
- Hex-имена переменных (`_0x4a2b`)
- Control flow flattening
- Dead code injection
- Self-defending (ломается при форматировании)

Проверка что строки зашифрованы:
```bash
grep -c "getBattery\|VirtualBox\|SwiftShader\|/api/collect" tracker.min.js
# Должно быть 0
```

---

## Подключение к WebView

```html
<script>
  window.__TRACKER_URL = "https://your-backend.com";
</script>
<script src="https://your-backend.com/tracker.js"></script>
```

Бэкенд на FastAPI отдаёт `GET /tracker.js` → обфускированную версию автоматически.

---

## Связь с остальными компонентами

- **Scoring Engine** (`/api/collect`) — принимает метрики, скорит, пишет в БД
- **Админ-панель** (вкладка "Активность" → клик по строке → "JS метрики") — показывает все метрики с индикаторами ОК/Подозрение
- **Конфигурация** (вкладка "Настройки") — пороги и веса настраиваются в реальном времени

---

## Тестирование

```bash
# Чистый юзер (score=0)
curl -X POST http://localhost:8000/api/collect -H "Content-Type: application/json" \
  -d '{"timezone":"Asia/Almaty","accelerometer":{"averageDeviation":0.5,"samples":50},"webgl":{"renderer":"Adreno 730"},"input":{"touchEvents":3,"touchSupported":true},"battery":{"level":0.7}}'

# Эмулятор (score=245)
curl -X POST http://localhost:8000/api/collect -H "Content-Type: application/json" \
  -d '{"timezone":"Etc/UTC","accelerometer":{"averageDeviation":0,"samples":30},"webgl":{"renderer":"ANGLE SwiftShader"},"input":{"mouseClicks":5,"touchEvents":0,"touchSupported":false},"battery":{"level":1.0,"chargingTime":0}}'
```

Или открой `test.html` в браузере — увидишь собранные метрики.
