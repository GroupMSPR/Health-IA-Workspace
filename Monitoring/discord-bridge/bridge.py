#!/usr/bin/env python3
"""Bridge Alertmanager → Discord webhook (format embed natif Discord)."""
from http.server import HTTPServer, BaseHTTPRequestHandler
import json, urllib.request, os, sys

DISCORD_WEBHOOK = os.environ.get("DISCORD_WEBHOOK", "")
PORT = 9094

COLORS = {"firing": 0xFF4444, "resolved": 0x44BB44}
ICONS  = {"firing": "🔴", "resolved": "✅"}


class BridgeHandler(BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        print(f"[alertmanager-discord] {fmt % args}", flush=True)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        try:
            body = json.loads(self.rfile.read(length))
        except Exception:
            self.send_response(400); self.end_headers(); return

        embeds = []
        for alert in body.get("alerts", []):
            status      = alert.get("status", "firing")
            labels      = alert.get("labels", {})
            annotations = alert.get("annotations", {})

            icon  = ICONS.get(status, "⚠️")
            color = COLORS.get(status, 0xFFAA00)
            name  = labels.get("alertname", "Alerte")
            summary = annotations.get("summary", "")
            description = annotations.get("description", "")
            severity = labels.get("severity", "?")
            instance = labels.get("instance", labels.get("service", ""))

            fields = [
                {"name": "Sévérité", "value": severity.upper(), "inline": True},
                {"name": "Status",   "value": status.upper(),   "inline": True},
            ]
            if instance:
                fields.append({"name": "Service", "value": f"`{instance}`", "inline": False})
            if description:
                fields.append({"name": "Détail", "value": description, "inline": False})

            embeds.append({
                "title":       f"{icon}  {name}",
                "description": summary,
                "color":       color,
                "fields":      fields,
                "footer":      {"text": "HealthAI Coach — Monitoring"},
            })

        if not embeds:
            self.send_response(200); self.end_headers(); self.wfile.write(b"OK"); return

        # Discord limite à 10 embeds par message
        payload = json.dumps({"embeds": embeds[:10]}).encode()
        req = urllib.request.Request(
            DISCORD_WEBHOOK,
            data=payload,
            headers={
                "Content-Type": "application/json",
                "User-Agent": "HealthAI-Monitoring/1.0 (Alertmanager Discord Bridge)",
            },
            method="POST",
        )
        try:
            resp = urllib.request.urlopen(req, timeout=10)
            print(f"[alertmanager-discord] Discord → {resp.status}", flush=True)
        except urllib.error.HTTPError as e:
            body_err = e.read().decode()
            print(f"[alertmanager-discord] Discord erreur {e.code}: {body_err}", flush=True)
        except Exception as e:
            print(f"[alertmanager-discord] Erreur réseau: {e}", flush=True)

        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")


if __name__ == "__main__":
    if not DISCORD_WEBHOOK:
        print("ERREUR: variable DISCORD_WEBHOOK non définie", file=sys.stderr)
        sys.exit(1)
    print(f"[alertmanager-discord] Écoute sur 0.0.0.0:{PORT}", flush=True)
    HTTPServer(("0.0.0.0", PORT), BridgeHandler).serve_forever()
