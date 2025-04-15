echo "[OPS MISSION] Pulling battery status..."
termux-battery-status > ~/battery_report.txt

echo "[OPS MISSION] Reading clipboard contents..."
termux-clipboard-get > ~/clipboard.txt

echo "[OPS MISSION] Triggering vibration..."
termux-vibrate -d 400

echo "[OPS MISSION] Displaying mission result..."
termux-toast "Battery scanned, clipboard saved."

echo "[OPS MISSION] Done."
