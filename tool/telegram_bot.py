#!/usr/bin/env python3
"""
B Code Pro Activation Telegram Bot
Handles buyer payment submissions (UTR + Device ID) and allows the admin
to approve with a single tap, automatically delivering an offline RSA-2048 key.
"""

import os
import sys
import re
import json
import time
import argparse
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
import requests
from pathlib import Path

# Import RSA key generator from license_cli.py
sys.path.insert(0, str(Path(__file__).parent))
from license_cli import load_or_generate_key, sign_license

STATE_FILE = Path(__file__).parent / "bot_state.json"
ENV_FILE = Path(__file__).parent / ".env"

DEVICE_REGEX = re.compile(r"BCODE-[A-Z0-9]{8}", re.IGNORECASE)

def load_env():
    if ENV_FILE.exists():
        with open(ENV_FILE, "r") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    os.environ.setdefault(k.strip(), v.strip())

def load_state() -> dict:
    if STATE_FILE.exists():
        try:
            with open(STATE_FILE, "r") as f:
                return json.load(f)
        except Exception:
            pass
    return {"offset": 0, "admin_id": None, "pending": {}}

def save_state(state: dict):
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)

def start_health_server(port: int = 8080):
    class HealthHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.send_header("Content-type", "text/plain")
            self.end_headers()
            self.wfile.write(b"B Code Pro Telegram Bot is online and healthy!\n")

        def log_message(self, format, *args):
            return

    try:
        server = HTTPServer(("0.0.0.0", port), HealthHandler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        print(f"🌐 Health server listening on 0.0.0.0:{port}")
    except Exception as e:
        print(f"⚠️ Could not bind health server on {port}: {e}")

class TelegramBot:
    def __init__(self, token: str, admin_id: int | None = None):
        self.token = token
        self.api_url = f"https://api.telegram.org/bot{token}"
        self.state = load_state()
        if admin_id:
            self.state["admin_id"] = admin_id
            save_state(self.state)
        self.priv_key = load_or_generate_key()

    def call(self, method: str, data: dict = None, files: dict = None) -> dict:
        try:
            url = f"{self.api_url}/{method}"
            if files:
                r = requests.post(url, data=data, files=files, timeout=30)
            else:
                r = requests.post(url, json=data, timeout=30)
            return r.json()
        except Exception as e:
            print(f"[API ERROR] {method}: {e}", file=sys.stderr)
            return {"ok": False, "error": str(e)}

    def send_message(self, chat_id: int, text: str, reply_markup: dict = None):
        payload = {
            "chat_id": chat_id,
            "text": text,
            "parse_mode": "Markdown",
        }
        if reply_markup:
            payload["reply_markup"] = reply_markup
        return self.call("sendMessage", payload)

    def edit_message(self, chat_id: int, message_id: int, text: str, reply_markup: dict = None):
        payload = {
            "chat_id": chat_id,
            "message_id": message_id,
            "text": text,
            "parse_mode": "Markdown",
        }
        if reply_markup is not None:
            payload["reply_markup"] = reply_markup
        return self.call("editMessageText", payload)

    def answer_callback(self, callback_id: str, text: str = None):
        payload = {"callback_query_id": callback_id}
        if text:
            payload["text"] = text
        return self.call("answerCallbackQuery", payload)

    def run(self):
        print("🤖 B Code Pro Bot started. Polling Telegram...")
        admin = self.state.get("admin_id")
        if admin:
            print(f"👑 Admin ID set to: {admin}")
        else:
            print("⚠️ Admin ID not set! Send /setadmin to the bot to link your account.")

        while True:
            try:
                res = self.call("getUpdates", {"offset": self.state["offset"], "timeout": 20})
                if not res.get("ok"):
                    time.sleep(3)
                    continue

                for update in res.get("result", []):
                    self.state["offset"] = update["update_id"] + 1
                    save_state(self.state)
                    self.handle_update(update)
            except KeyboardInterrupt:
                print("\n🛑 Bot stopped.")
                break
            except Exception as e:
                print(f"[LOOP ERROR] {e}", file=sys.stderr)
                time.sleep(3)

    def handle_update(self, update: dict):
        if "callback_query" in update:
            self.handle_callback(update["callback_query"])
            return

        message = update.get("message")
        if not message:
            return

        chat_id = message["chat"]["id"]
        sender = message.get("from", {})
        username = sender.get("username", sender.get("first_name", "User"))
        text = message.get("text", "") or message.get("caption", "")

        # Command: /setadmin
        if text.startswith("/setadmin"):
            self.state["admin_id"] = chat_id
            save_state(self.state)
            self.send_message(
                chat_id,
                f"✅ *You are now registered as Admin!* (ID: `{chat_id}`)\n"
                "All buyer approval requests will be sent to this chat with Approve/Reject buttons.",
            )
            return

        # Command: /start
        if text.startswith("/start"):
            device_match = DEVICE_REGEX.search(text)
            dev_str = device_match.group(0).upper() if device_match else ""

            welcome = (
                "👋 *Welcome to B Code Pro Activation!*\n\n"
                "Get your lifetime offline Pro key in 2 simple steps:\n\n"
                "1️⃣ Pay *₹49* via any UPI app to: `bakadev@upi` (Aditya)\n"
                "2️⃣ Reply here with your *Device ID* and *12-digit UPI UTR / Reference number* (or screenshot).\n\n"
            )
            if dev_str:
                welcome += f"Detected Device ID from app: `{dev_str}`\nJust send your UPI UTR or payment screenshot now!"
            else:
                welcome += "You can find your Device ID inside *B Code → Upgrade to Pro*."

            self.send_message(chat_id, welcome)
            return

        # Check if buyer is submitting Device ID & UTR or screenshot
        device_match = DEVICE_REGEX.search(text)
        if not device_match:
            self.send_message(
                chat_id,
                "⚠️ *Device ID not found in your message.*\n\n"
                "Please make sure your message includes your Device ID (format: `BCODE-XXXXXXXX`), "
                "which is displayed in B Code's Upgrade screen.",
            )
            return

        device_id = device_match.group(0).upper()
        req_id = f"{chat_id}_{int(time.time())}"

        # Save pending request
        self.state["pending"][req_id] = {
            "chat_id": chat_id,
            "username": username,
            "device_id": device_id,
            "text": text,
        }
        save_state(self.state)

        # Confirm to buyer
        self.send_message(
            chat_id,
            f"⏳ *Payment submitted for Device `{device_id}`!*\n\n"
            "Aditya is verifying the transaction. Your Pro license key will be delivered "
            "directly in this chat as soon as approved (typically within minutes).\n"
            "Thank you for supporting B Code! 🚀",
        )

        # Notify Admin
        admin_id = self.state.get("admin_id")
        if not admin_id:
            print(f"[ALERT] New purchase for {device_id} from @{username}, but no admin_id configured!")
            return

        admin_text = (
            "🔔 *New B Code Pro Purchase Request!*\n\n"
            f"👤 *Buyer:* @{username} (ID: `{chat_id}`)\n"
            f"📱 *Device ID:* `{device_id}`\n"
            f"📝 *Note/Text:* {text}\n\n"
            "Check your bank/UPI app for ₹49. Tap below to issue license:"
        )

        buttons = {
            "inline_keyboard": [
                [
                    {"text": "✅ Approve & Send Key", "callback_data": f"app_{req_id}"},
                    {"text": "❌ Reject", "callback_data": f"rej_{req_id}"},
                ]
            ]
        }

        # If user attached a photo, forward the photo to admin
        if "photo" in message:
            photo_id = message["photo"][-1]["file_id"]
            self.call(
                "sendPhoto",
                {
                    "chat_id": admin_id,
                    "photo": photo_id,
                    "caption": admin_text,
                    "parse_mode": "Markdown",
                    "reply_markup": buttons,
                },
            )
        else:
            self.send_message(admin_id, admin_text, reply_markup=buttons)

    def handle_callback(self, query: dict):
        callback_id = query["id"]
        data = query.get("data", "")
        message = query.get("message", {})
        chat_id = message.get("chat", {}).get("id")
        message_id = message.get("message_id")

        if data.startswith("app_"):
            req_id = data[4:]
            req = self.state["pending"].get(req_id)
            if not req:
                self.answer_callback(callback_id, "Request expired or already handled.")
                return

            device_id = req["device_id"]
            buyer_chat_id = req["chat_id"]
            buyer_user = req["username"]

            # Generate RSA-2048 device-locked key
            license_key = sign_license(self.priv_key, f"pro:{device_id}")

            # Send to buyer
            buyer_msg = (
                "🎉 *Payment Approved! B Code Pro is Ready!*\n\n"
                f"Your license key for device `{device_id}`:\n\n"
                f"`{license_key}`\n\n"
                "*(Tap the code above to copy)*\n\n"
                "👉 Open B Code → Tap *Enter License Key* → Paste and activate Pro offline forever!"
            )
            self.send_message(buyer_chat_id, buyer_msg)

            # Update Admin message
            admin_msg = (
                f"✅ *APPROVED & DELIVERED*\n\n"
                f"👤 Buyer: @{buyer_user}\n"
                f"📱 Device: `{device_id}`\n"
                f"🔑 Key: `{license_key}`"
            )
            self.edit_message(chat_id, message_id, admin_msg, reply_markup={"inline_keyboard": []})
            self.answer_callback(callback_id, "✅ Key delivered to buyer!")

            del self.state["pending"][req_id]
            save_state(self.state)

        elif data.startswith("rej_"):
            req_id = data[4:]
            req = self.state["pending"].get(req_id)
            if not req:
                self.answer_callback(callback_id, "Request expired or already handled.")
                return

            buyer_chat_id = req["chat_id"]
            device_id = req["device_id"]

            self.send_message(
                buyer_chat_id,
                f"❌ *Payment verification failed for Device `{device_id}`.*\n\n"
                "The transaction could not be matched. Please verify your UTR number or message @bakadev directly.",
            )

            admin_msg = f"❌ *REJECTED* for Device `{device_id}` (@{req['username']})"
            self.edit_message(chat_id, message_id, admin_msg, reply_markup={"inline_keyboard": []})
            self.answer_callback(callback_id, "❌ Rejected.")

            del self.state["pending"][req_id]
            save_state(self.state)

def main():
    load_env()
    parser = argparse.ArgumentParser(description="B Code Pro Telegram Bot")
    parser.add_argument("--token", default=os.environ.get("TELEGRAM_BOT_TOKEN"), help="Bot API token")
    parser.add_argument("--admin", type=int, default=os.environ.get("ADMIN_CHAT_ID"), help="Admin chat ID")
    parser.add_argument("--port", type=int, default=int(os.environ.get("PORT", "8080")), help="HTTP health port")
    args = parser.parse_args()

    if not args.token:
        print("Error: No bot token provided. Set TELEGRAM_BOT_TOKEN in tool/.env or pass --token", file=sys.stderr)
        sys.exit(1)

    start_health_server(args.port)
    bot = TelegramBot(args.token, args.admin)
    bot.run()

if __name__ == "__main__":
    main()
