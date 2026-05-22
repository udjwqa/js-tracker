#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "=== JS Tracker Build ==="

if [ ! -d "node_modules" ]; then
  echo "[1/2] Installing dependencies..."
  npm install 2>&1 | tail -1
else
  echo "[1/2] Dependencies OK"
fi

echo "[2/2] Obfuscating tracker.js..."
npx javascript-obfuscator tracker.js --output tracker.min.js --config obfuscator.json

ORIG=$(wc -c < tracker.js | tr -d ' ')
OBF=$(wc -c < tracker.min.js | tr -d ' ')
echo ""
echo "Done!"
echo "  tracker.js     → ${ORIG} bytes (source)"
echo "  tracker.min.js → ${OBF} bytes (obfuscated)"
echo ""
echo "Проверка: grep -c 'getBattery\|VirtualBox\|SwiftShader\|accelerometer' tracker.min.js"
grep -c 'getBattery\|VirtualBox\|SwiftShader\|accelerometer' tracker.min.js && echo "  ⚠ Найдены читаемые строки!" || echo "  ✓ Строки зашифрованы, ничего не найдено"
