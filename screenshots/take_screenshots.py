"""
Script de capture automatique des dashboards Grafana
Usage : python3 take_screenshots.py
"""

from playwright.sync_api import sync_playwright
import time
import os

GRAFANA_URL = "http://localhost:3000"
LOGIN = "admin"
PASSWORD = "admin"
OUT_DIR = os.path.dirname(os.path.abspath(__file__))

# Chaque dashboard : (nom_fichier, uid, time_range)
DASHBOARDS = [
    ("dashboard-monitoring.png",   "healthai-monitoring-main", "now-1h",  "now"),
    ("dashboard-users.png",        "adszhtx",                  "now-1y",  "now"),
    ("dashboard-foods.png",        "adx4wcl",                  "now-5y",  "now"),
    ("dashboard-exercises.png",    "advpcp7",                   "now-5y",  "now"),
    ("dashboard-health.png",       "ad8srgr",                  "now-1y",  "now"),
    ("dashboard-application.png",  "healthai-app-dashboard",   "now-30d", "now"),
]

def take_screenshots():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(viewport={"width": 1600, "height": 900})
        page = context.new_page()

        # 1. Connexion à Grafana
        print("Connexion à Grafana...")
        page.goto(f"{GRAFANA_URL}/login")
        page.wait_for_load_state("networkidle")
        page.fill('input[name="user"]', LOGIN)
        page.fill('input[name="password"]', PASSWORD)
        page.click('button[type="submit"]')
        page.wait_for_load_state("networkidle")
        time.sleep(2)
        print("  ✅ Connecté")

        # 2. Capture de chaque dashboard
        for filename, uid, from_time, to_time in DASHBOARDS:
            url = f"{GRAFANA_URL}/d/{uid}?orgId=1&from={from_time}&to={to_time}&kiosk=tv"
            print(f"Capture : {filename}...")
            try:
                page.goto(url)
                page.wait_for_load_state("networkidle")
                time.sleep(4)  # Attendre que les panels chargent les données

                out_path = os.path.join(OUT_DIR, filename)
                page.screenshot(path=out_path, full_page=False)
                print(f"  ✅ Sauvegardé → {out_path}")
            except Exception as e:
                print(f"  ❌ Erreur : {e}")

        browser.close()
        print("\nCaptures terminées ! Fichiers dans :", OUT_DIR)

if __name__ == "__main__":
    take_screenshots()
