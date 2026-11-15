#!/usr/bin/env python3
"""
B Code Pro Activation Telegram Bot
Handles buyer payment submissions in a simple, foolproof 2-step conversational flow:
  Step 1: Ask for UPI UTR / Reference number (or payment screenshot)
  Step 2: Ask for B Code Device ID
Once submitted, it sends a high-priority approval notification to the admin with
[✅ Approve & Send Key] and [❌ Reject] buttons.
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
UTR_REGEX = re.compile(r"\b\d{8,18}\b")

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
                data = json.load(f)
                data.setdefault("offset", 0)
                data.setdefault("admin_id", None)
                data.setdefault("pending", {})
                data.setdefault("sessions", {})
                return data
        except Exception:
            pass
    return {"offset": 0, "admin_id": None, "pending": {}, "sessions": {}}

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

    def send_message(self, chat_id: int, text: str, reply_markup: dict = None, disable_notification: bool = False):
        payload = {
            "chat_id": chat_id,
            "text": text,
            "parse_mode": "Markdown",
            "disable_notification": disable_notification,
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

    def submit_request(self, chat_id: int, username: str, device_id: str, utr: str, photo_id: str | None = None):
        req_id = f"{chat_id}_{int(time.time())}"
        self.state["pending"][req_id] = {
            "chat_id": chat_id,
            "username": username,
            "device_id": device_id,
            "utr": utr,
            "photo_id": photo_id,
        }
        save_state(self.state)

        # 1. Confirm to Buyer
        buyer_confirmation = (
            f"Payment details received for device `{device_id}`.\n"
            f"UTR / Ref: `{utr}`\n\n"
            "I have forwarded your request to Aditya for manual verification. "
            "Because B Code is built and maintained by an individual developer, please allow up to 6 hours for approval. "
            "The developer is human too and might be in class, working, or asleep.\n\n"
            "As soon as the transaction is confirmed, your offline Pro key will arrive right here in this chat.\n\n"
            "Thank you for your patience and for supporting B Code."
        )
        self.send_message(chat_id, buyer_confirmation)

        # 2. Alert Admin with High Priority (disable_notification=False ensures sound/vibration alert)
        admin_id = self.state.get("admin_id")
        if not admin_id:
            print(f"[ALERT] New purchase for {device_id} from @{username}, but no admin_id configured!")
            return

        admin_text = (
            "🚨 *NEW PRO PURCHASE PENDING APPROVAL!*\n\n"
            f"👤 *Buyer:* @{username} (ID: `{chat_id}`)\n"
            f"📱 *Device ID:* `{device_id}`\n"
            f"🧾 *UTR / Ref:* `{utr}`\n\n"
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

        if photo_id:
            self.call(
                "sendPhoto",
                {
                    "chat_id": admin_id,
                    "photo": photo_id,
                    "caption": admin_text,
                    "parse_mode": "Markdown",
                    "reply_markup": buttons,
                    "disable_notification": False,
                },
            )
        else:
            self.send_message(admin_id, admin_text, reply_markup=buttons, disable_notification=False)

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
        text = (message.get("text", "") or message.get("caption", "")).strip()
        photo = message.get("photo")

        # 1. Admin setup command: /setadmin
        if text.startswith("/setadmin"):
            self.state["admin_id"] = chat_id
            save_state(self.state)
            self.send_message(
                chat_id,
                f"✅ *You are now registered as Admin!* (ID: `{chat_id}`)\n"
                "All buyer approval requests will be sent to this chat with notification alerts.",
            )
            return

        # 2. Reset session command: /reset or /cancel
        if text in ("/reset", "/cancel"):
            if str(chat_id) in self.state.get("sessions", {}):
                del self.state["sessions"][str(chat_id)]
                save_state(self.state)
            self.send_message(
                chat_id,
                "🔄 *Session reset.*\n\n"
                "Type /start to begin a fresh Pro activation.",
            )
            return

        # 3. Start command: /start (fresh start or deep link)
        if text.startswith("/start"):
            # Check for deep-linked device ID (e.g. /start BCODE-C1707253 or /start BCODE_C1707253)
            deep_dev = DEVICE_REGEX.search(text.replace("_", "-"))
            session = {"step": "AWAITING_UTR"}
            if deep_dev:
                dev_id = deep_dev.group(0).upper()
                session["device_id"] = dev_id
                self.state.setdefault("sessions", {})[str(chat_id)] = session
                save_state(self.state)

                welcome = (
                    "👋 *Welcome to B Code Pro Activation!*\n\n"
                    f"📱 *Device ID Detected:* `{dev_id}`\n\n"
                    "━━━━━━━━━━━━━━━━━━\n"
                    "📌 *STEP 1: Pay ₹49*\n"
                    "━━━━━━━━━━━━━━━━━━\n"
                    "Pay *₹49* via any UPI app (GPay, PhonePe, Paytm, BHIM) to:\n"
                    "👉 `bakadev@upi` (Aditya)\n\n"
                    "━━━━━━━━━━━━━━━━━━\n"
                    "📌 *STEP 2: Send UTR Number*\n"
                    "━━━━━━━━━━━━━━━━━━\n"
                    "Once paid, reply below with your **12-digit UPI UTR / Reference number** "
                    "(or upload a payment screenshot):"
                )
            else:
                self.state.setdefault("sessions", {})[str(chat_id)] = session
                save_state(self.state)

                welcome = (
                    "👋 *Welcome to B Code Pro Activation!*\n\n"
                    "Get lifetime offline access to all compilers & remove ads for just *₹49*.\n\n"
                    "━━━━━━━━━━━━━━━━━━\n"
                    "📌 *STEP 1: Pay ₹49*\n"
                    "━━━━━━━━━━━━━━━━━━\n"
                    "Pay *₹49* via any UPI app (GPay, PhonePe, Paytm, etc.) to:\n"
                    "👉 `bakadev@upi` (Aditya)\n\n"
                    "━━━━━━━━━━━━━━━━━━\n"
                    "📌 *STEP 2: Send UTR Number*\n"
                    "━━━━━━━━━━━━━━━━━━\n"
                    "Once paid, reply below with your **12-digit UPI UTR / Reference number** "
                    "(or upload a payment screenshot):"
                )

            self.send_message(chat_id, welcome)
            return

        # 4. Message / Photo handling with 2-step conversational state
        sessions = self.state.setdefault("sessions", {})
        session = sessions.setdefault(str(chat_id), {"step": "AWAITING_UTR"})

        device_match = DEVICE_REGEX.search(text)
        utr_match = UTR_REGEX.search(text)
        photo_id = photo[-1]["file_id"] if photo else None

        # FAST PATH: If message contains BOTH a valid Device ID and a UTR/Screenshot
        if device_match and (utr_match or photo_id or session.get("utr")):
            device_id = device_match.group(0).upper()
            utr = utr_match.group(0) if utr_match else (session.get("utr") or ("Screenshot attached" if photo_id else text.strip()))
            p_id = photo_id or session.get("photo_id")
            self.submit_request(chat_id, username, device_id, utr, p_id)
            if str(chat_id) in sessions:
                del sessions[str(chat_id)]
                save_state(self.state)
            return

        current_step = session.get("step", "AWAITING_UTR")

        # STEP 1: Awaiting UTR / Payment confirmation
        if current_step == "AWAITING_UTR":
            # If user sent Device ID first instead of UTR
            if device_match and not utr_match and not photo_id:
                dev_id = device_match.group(0).upper()
                session["device_id"] = dev_id
                save_state(self.state)
                self.send_message(
                    chat_id,
                    f"📱 *Device ID saved:* `{dev_id}`\n\n"
                    "Now please send your **12-digit UPI UTR / Reference number** "
                    "(or payment screenshot) to complete your submission:",
                )
                return

            # Extract UTR value
            if utr_match:
                utr_val = utr_match.group(0)
            elif photo_id:
                utr_val = text.strip() if text.strip() else "Screenshot attached"
            elif text.strip():
                utr_val = text.strip()
            else:
                utr_val = "Payment submitted"

            session["utr"] = utr_val
            if photo_id:
                session["photo_id"] = photo_id

            # If Device ID was already saved earlier (e.g. via deep-link /start)
            if session.get("device_id"):
                self.submit_request(chat_id, username, session["device_id"], utr_val, session.get("photo_id"))
                if str(chat_id) in sessions:
                    del sessions[str(chat_id)]
                    save_state(self.state)
                return

            # Advance to Step 2: Ask for Device ID
            session["step"] = "AWAITING_DEVICE_ID"
            save_state(self.state)

            self.send_message(
                chat_id,
                f"✅ *Payment details received!*\n"
                f"🧾 *UTR / Ref:* `{utr_val}`\n\n"
                "━━━━━━━━━━━━━━━━━━\n"
                "📌 *STEP 2: Send Your Device ID*\n"
                "━━━━━━━━━━━━━━━━━━\n"
                "Now please send your **Device ID** so your license key can be locked to your phone:\n\n"
                "1️⃣ Open **B Code** on your phone\n"
                "2️⃣ Go to **Settings → Upgrade to Pro**\n"
                "3️⃣ Tap the 📋 copy button next to **YOUR DEVICE ID** (format: `BCODE-XXXXXXXX`)\n"
                "4️⃣ Paste it here below:",
            )
            return

        # STEP 2: Awaiting Device ID
        elif current_step == "AWAITING_DEVICE_ID":
            if device_match:
                device_id = device_match.group(0).upper()
                utr = session.get("utr", "Payment verified")
                p_id = photo_id or session.get("photo_id")
                self.submit_request(chat_id, username, device_id, utr, p_id)
                if str(chat_id) in sessions:
                    del sessions[str(chat_id)]
                    save_state(self.state)
                return
            else:
                self.send_message(
                    chat_id,
                    "⚠️ *Device ID not recognized.*\n\n"
                    "Please paste the exact Device ID displayed in B Code (format: `BCODE-XXXXXXXX`).\n\n"
                    "👉 Find it inside **B Code → Settings → Upgrade to Pro**.\n"
                    "_(Send /reset if you want to start over)_",
                )
                return

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
