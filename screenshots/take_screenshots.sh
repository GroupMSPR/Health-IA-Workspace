#!/bin/bash
# Script de capture automatique des dashboards Grafana
# Lancer depuis un terminal WSL avec : bash screenshots/take_screenshots.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Installation des dépendances système ==="
sudo apt-get install -y \
  libnspr4 libnss3 libatk1.0-0 libatk-bridge2.0-0 \
  libcups2 libdrm2 libxcomposite1 libxdamage1 libxfixes3 \
  libxrandr2 libgbm1 libxkbcommon0 libpango-1.0-0 libcairo2 \
  libatspi2.0-0 2>/dev/null

echo ""
echo "=== Capture des dashboards Grafana ==="
python3 take_screenshots.py

echo ""
echo "=== Captures disponibles dans : $SCRIPT_DIR ==="
ls -lh "$SCRIPT_DIR"/*.png 2>/dev/null || echo "Aucun fichier PNG trouvé"
