#!/usr/bin/env python3
"""
Kriya Pro Activation Telegram Bot
Handles buyer payment submissions in a simple, foolproof 2-step conversational flow:
  Step 1: Ask for UPI UTR / Reference number (or payment screenshot)
  Step 2: Ask for Kriya Device ID
Once submitted, it sends a high-priority approval notification to the admin with
[✅ Approve & Send Key] and [❌ Reject] buttons.

Supports:
- Webhook mode (automatic on Render via RENDER_EXTERNAL_URL) so incoming Telegram messages
  hit Render directly and wake up spun-down instances.
- Long-polling fallback mode (for local testing without a public domain).
- Built-in HTTP health check endpoint on GET / (for Render & keep-alive pingers like UptimeRobot).
"""

import os
import sys
import re
import json
import time
import hmac
import secrets
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

DEVICE_REGEX = re.compile(r"(?:KRIYA|BCODE)[-_][A-Z0-9]{8}", re.IGNORECASE)
UTR_REGEX = re.compile(r"\b\d{8,18}\b")

def load_env():
    if ENV_FILE.exists():
        with open(ENV_FILE, "r") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    os.environ.setdefault(k.strip(), v.strip())

class StateStore:
    def __init__(self, db_url: str | None = None, state_file: Path | None = None):
        self.db_url = db_url or os.environ.get("DATABASE_URL")
        self.state_file = state_file or STATE_FILE
        self._pg_conn = None
        self._sqlite_conn = None
        self._backend = "json"
        self._init_backend()

    def _init_backend(self):
        if self.db_url:
            if self.db_url.startswith("postgres://") or self.db_url.startswith("postgresql://"):
                try:
                    import psycopg2
                    url = self.db_url
                    if url.startswith("postgres://"):
                        url = "postgresql://" + url[len("postgres://"):]
                    self._pg_conn = psycopg2.connect(url)
                    self._pg_conn.autocommit = True
                    with self._pg_conn.cursor() as cur:
                        cur.execute("""
                            CREATE TABLE IF NOT EXISTS bcode_bot_state (
                                id INT PRIMARY KEY,
                                data JSONB,
                                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                            );
                        """)
                    self._backend = "postgres"
                    print("🗄️ State store connected to PostgreSQL database")
                    return
                except Exception as e:
                    print(f"⚠️ Failed to connect to PostgreSQL ({e}), falling back to file/SQLite.", file=sys.stderr)
            elif self.db_url.startswith("sqlite://"):
                try:
                    import sqlite3
                    path = self.db_url[len("sqlite://"):] or "bot_state.db"
                    self._sqlite_conn = sqlite3.connect(path, check_same_thread=False)
                    with self._sqlite_conn:
                        self._sqlite_conn.execute("""
                            CREATE TABLE IF NOT EXISTS bcode_bot_state (
                                id INTEGER PRIMARY KEY,
                                data TEXT,
                                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                            );
                        """)
                    self._backend = "sqlite"
                    print(f"🗄️ State store connected to SQLite database ({path})")
                    return
                except Exception as e:
                    print(f"⚠️ Failed to connect to SQLite ({e}), falling back to file.", file=sys.stderr)

        self._backend = "json"

    def _get_pg_conn(self):
        try:
            if self._pg_conn is None or self._pg_conn.closed:
                import psycopg2
                url = self.db_url
                if url.startswith("postgres://"):
                    url = "postgresql://" + url[len("postgres://"):]
                self._pg_conn = psycopg2.connect(url)
                self._pg_conn.autocommit = True
            else:
                with self._pg_conn.cursor() as cur:
                    cur.execute("SELECT 1")
        except Exception:
            import psycopg2
            url = self.db_url
            if url.startswith("postgres://"):
                url = "postgresql://" + url[len("postgres://"):]
            self._pg_conn = psycopg2.connect(url)
            self._pg_conn.autocommit = True
        return self._pg_conn

    def load(self) -> dict:
        default_state = {
            "offset": 0,
            "admin_id": None,
            "pending": {},
            "sessions": {},
            "blocked_users": [],
            "rejections": {},
            "used_utrs": [],
        }

        if self._backend == "postgres":
            try:
                conn = self._get_pg_conn()
                with conn.cursor() as cur:
                    cur.execute("SELECT data FROM bcode_bot_state WHERE id = 1;")
                    row = cur.fetchone()
                    if row and row[0]:
                        data = row[0]
                        if isinstance(data, str):
                            data = json.loads(data)
                        for k, v in default_state.items():
                            data.setdefault(k, v)
                        return data
                    else:
                        initial = self._load_file(default_state)
                        self.save(initial)
                        return initial
            except Exception as e:
                print(f"⚠️ Error reading from Postgres: {e}, falling back to file", file=sys.stderr)

        elif self._backend == "sqlite":
            try:
                with self._sqlite_conn:
                    cur = self._sqlite_conn.cursor()
                    cur.execute("SELECT data FROM bcode_bot_state WHERE id = 1;")
                    row = cur.fetchone()
                    if row and row[0]:
                        data = json.loads(row[0])
                        for k, v in default_state.items():
                            data.setdefault(k, v)
                        return data
                    else:
                        initial = self._load_file(default_state)
                        self.save(initial)
                        return initial
            except Exception as e:
                print(f"⚠️ Error reading from SQLite: {e}, falling back to file", file=sys.stderr)

        return self._load_file(default_state)

    def _load_file(self, default_state: dict) -> dict:
        if self.state_file and self.state_file.exists():
            try:
                with open(self.state_file, "r") as f:
                    data = json.load(f)
                    for k, v in default_state.items():
                        data.setdefault(k, v)
                    return data
            except Exception:
                pass
        return dict(default_state)

    def save(self, state: dict):
        raw_json = json.dumps(state)

        if self._backend == "postgres":
            try:
                conn = self._get_pg_conn()
                with conn.cursor() as cur:
                    cur.execute("""
                        INSERT INTO bcode_bot_state (id, data, updated_at)
                        VALUES (1, %s::jsonb, CURRENT_TIMESTAMP)
                        ON CONFLICT (id) DO UPDATE
                        SET data = EXCLUDED.data, updated_at = CURRENT_TIMESTAMP;
                    """, (raw_json,))
            except Exception as e:
                print(f"⚠️ Error saving state to Postgres: {e}", file=sys.stderr)

        elif self._backend == "sqlite":
            try:
                with self._sqlite_conn:
                    self._sqlite_conn.execute("""
                        INSERT INTO bcode_bot_state (id, data, updated_at)
                        VALUES (1, ?, CURRENT_TIMESTAMP)
                        ON CONFLICT(id) DO UPDATE
                        SET data = excluded.data, updated_at = CURRENT_TIMESTAMP;
                    """, (raw_json,))
            except Exception as e:
                print(f"⚠️ Error saving state to SQLite: {e}", file=sys.stderr)

        if self.state_file:
            try:
                tmp = self.state_file.with_suffix(".tmp")
                with open(tmp, "w") as f:
                    f.write(raw_json)
                tmp.replace(self.state_file)
            except Exception:
                pass

_STORE = None

def get_store(db_url: str | None = None) -> StateStore:
    global _STORE
    if _STORE is None or (db_url and _STORE.db_url != db_url):
        load_env()
        _STORE = StateStore(db_url=db_url)
    return _STORE

def load_state() -> dict:
    return get_store().load()

def save_state(state: dict):
    get_store().save(state)

class BotHttpHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        self.wfile.write(b"Kriya Code Pro Telegram Bot is online and healthy!\n")

    def do_POST(self):
        if self.path != "/webhook":
            self.send_response(404)
            self.end_headers()
            return

        # Without this, anyone who knows the Render URL can POST a forged
        # update: "/setadmin" makes them the admin, a fake purchase creates a
        # pending request, and "app_<id>" hands them a signed Pro licence.
        bot = getattr(self.server, "bot", None)
        expected = getattr(bot, "webhook_secret", None)
        supplied = self.headers.get("X-Telegram-Bot-Api-Secret-Token", "")
        if not expected or not hmac.compare_digest(supplied, expected):
            self.send_response(401)
            self.end_headers()
            return

        try:
            content_length = int(self.headers.get("Content-Length", 0))
        except (TypeError, ValueError):
            content_length = 0
        if content_length <= 0 or content_length > 1_000_000:
            self.send_response(413)
            self.end_headers()
            return

        body = self.rfile.read(content_length)
        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        self.wfile.write(b"OK")

        try:
            update = json.loads(body.decode("utf-8"))
            if bot:
                threading.Thread(target=bot.handle_update, args=(update,), daemon=True).start()
        except Exception as e:
            print(f"[WEBHOOK JSON ERROR] {e}", file=sys.stderr)

    def log_message(self, format, *args):
        return

class TelegramBot:
    def __init__(self, token: str, admin_id: int | None = None):
        self.token = token
        self.api_url = f"https://api.telegram.org/bot{token}"
        self.state = load_state()
        if admin_id:
            self.state["admin_id"] = admin_id
            save_state(self.state)
        # Regenerated per process; setup_webhook() registers it with Telegram,
        # so a restart rotates it instead of leaving a shared secret on disk.
        self.webhook_secret = os.environ.get("TELEGRAM_WEBHOOK_SECRET") or secrets.token_urlsafe(32)
        self._lock = threading.Lock()
        self.priv_key = load_or_generate_key(generate_if_missing=False)

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

    def setup_webhook(self, external_url: str):
        webhook_url = f"{external_url.rstrip('/')}/webhook"
        res = self.call(
            "setWebhook",
            {
                "url": webhook_url,
                "secret_token": self.webhook_secret,
                "allowed_updates": ["message", "callback_query"],
                "drop_pending_updates": False,
            },
        )
        if res.get("ok"):
            print(f"🔗 Webhook registered with Telegram: {webhook_url}")
            return True
        print(f"⚠️ Failed to register webhook: {res.get('error') or res}")
        return False

    def remove_webhook(self):
        res = self.call("deleteWebhook")
        if res.get("ok"):
            print("🔄 Webhook removed from Telegram. Falling back to polling mode.")

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
        clean_utr = utr.strip()
        used_utrs = set(self.state.get("used_utrs", []))
        if clean_utr in used_utrs:
            self.send_message(
                chat_id,
                "⚠️ *Invalid or already processed UTR.*\n\n"
                f"The reference number `{clean_utr}` has already been processed or flagged. "
                "Each UPI transaction reference can only be used once.\n\n"
                "If you believe this is an error, please message @bakadev directly with your payment receipt.",
            )
            return

        req_id = f"{chat_id}_{int(time.time())}"
        self.state["pending"][req_id] = {
            "chat_id": chat_id,
            "username": username,
            "device_id": device_id,
            "utr": clean_utr,
            "photo_id": photo_id,
        }
        save_state(self.state)

        # 1. Confirm to Buyer
        buyer_confirmation = (
            f"Payment details received for device `{device_id}`.\n"
            f"UTR / Ref: `{clean_utr}`\n\n"
            "I have forwarded your request to Aditya for manual verification. "
            "Because Kriya is built and maintained by an individual developer, please allow up to 6 hours for approval. "
            "The developer is human too and might be in class, working, or asleep.\n\n"
            "As soon as the transaction is confirmed, your offline Pro key will arrive right here in this chat.\n\n"
            "Thank you for your patience and for supporting Kriya."
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
            f"🧾 *UTR / Ref:* `{clean_utr}`\n\n"
            "Check your bank/UPI app for ₹49. Tap below to issue license:"
        )

        buttons = {
            "inline_keyboard": [
                [
                    {"text": "✅ Approve", "callback_data": f"app_{req_id}"},
                    {"text": "❌ Reject", "callback_data": f"rej_{req_id}"},
                    {"text": "🚫 Reject & Block", "callback_data": f"blk_{req_id}"},
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

    def run_polling(self):
        print("🤖 Kriya Pro Bot started. Polling Telegram...")
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
        # Webhook mode handles each update on its own thread; the state file is
        # read-modify-written, so unserialized updates can drop or duplicate a
        # pending request.
        with self._lock:
            self._handle_update(update)

    def _handle_update(self, update: dict):
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

        # 0. Drop messages from blocked users immediately
        if chat_id in self.state.get("blocked_users", []):
            return

        # Check for active cooldown from repeated failed verifications
        user_rej = self.state.get("rejections", {}).get(str(chat_id), {})
        cooldown_until = user_rej.get("cooldown_until", 0)
        if cooldown_until > time.time() and not text.startswith("/unblock"):
            remaining_hours = int((cooldown_until - time.time()) / 3600) + 1
            self.send_message(
                chat_id,
                f"⏳ *Account temporarily on cooldown.*\n\n"
                f"Due to multiple failed verifications, submissions are paused for {remaining_hours} hour(s).\n"
                "If this is a mistake, please reach out directly to @bakadev on Telegram with your payment receipt.",
            )
            return

        # Admin unblock command: /unblock <user_id>
        if text.startswith("/unblock"):
            if self.state.get("admin_id") != chat_id:
                self.send_message(chat_id, "⛔ Not authorised.")
                return
            parts = text.split()
            if len(parts) == 2 and parts[1].isdigit():
                target_id = int(parts[1])
                blocked = self.state.setdefault("blocked_users", [])
                if target_id in blocked:
                    blocked.remove(target_id)
                self.state.get("rejections", {}).pop(str(target_id), None)
                save_state(self.state)
                self.send_message(chat_id, f"✅ User `{target_id}` has been unblocked.")
            else:
                self.send_message(chat_id, "Usage: `/unblock <user_id>`")
            return

        # 1. Admin setup command: /setadmin
        if text.startswith("/setadmin"):
            # Only the operator configured through ADMIN_CHAT_ID may claim
            # admin. The old code promoted whoever sent this first, which let
            # any buyer approve their own purchase.
            if self.state.get("admin_id") != chat_id:
                self.send_message(
                    chat_id,
                    "⛔ Not authorised. Set ADMIN_CHAT_ID on the bot host to register the admin.",
                )
                return
            self.send_message(
                chat_id,
                f"✅ *You are the registered Admin.* (ID: `{chat_id}`)\n"
                "All buyer approval requests will be sent to this chat with notification alerts.",
            )
            return

        # 2. Reset session command: /reset or /cancel
        if text in ("/reset", "/cancel"):
            # Also cancel any pending request if user explicitly resets
            pending_to_del = [k for k, v in self.state.get("pending", {}).items() if v.get("chat_id") == chat_id]
            for k in pending_to_del:
                del self.state["pending"][k]
            if str(chat_id) in self.state.get("sessions", {}):
                del self.state["sessions"][str(chat_id)]
            save_state(self.state)
            self.send_message(
                chat_id,
                "🔄 *Session and pending requests reset.*\n\n"
                "Type /start to begin a fresh Pro activation.",
            )
            return

        # 3. Limit to 1 active pending request per user to prevent notification flooding
        has_pending = any(req.get("chat_id") == chat_id for req in self.state.get("pending", {}).values())
        if has_pending and chat_id != self.state.get("admin_id") and not text.startswith("/"):
            self.send_message(
                chat_id,
                "⏳ *Submission already pending review.*\n\n"
                "You already have a payment submission waiting for verification. "
                "Please allow up to 6 hours for Aditya to review your transaction. "
                "You will receive your Pro key here once confirmed.\n\n"
                "_(Send /cancel if you made an error and need to restart)_",
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
                    "👋 *Welcome to Kriya Pro Activation!*\n\n"
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
                    "👋 *Welcome to Kriya Pro Activation!*\n\n"
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
            device_id = device_match.group(0).upper().replace('_', '-')
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
                dev_id = device_match.group(0).upper().replace('_', '-')
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
                "1️⃣ Open **Kriya** on your phone\n"
                "2️⃣ Go to **Settings → Upgrade to Pro**\n"
                "3️⃣ Tap the 📋 copy button next to **YOUR DEVICE ID** (format: `KRIYA-XXXXXXXX`)\n"
                "4️⃣ Paste it here below:",
            )
            return

        # STEP 2: Awaiting Device ID
        elif current_step == "AWAITING_DEVICE_ID":
            if device_match:
                device_id = device_match.group(0).upper().replace('_', '-')
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
                    "Please paste the exact Device ID displayed in Kriya (format: `KRIYA-XXXXXXXX`).\n\n"
                    "👉 Find it inside **Kriya → Settings → Upgrade to Pro**.\n"
                    "_(Send /reset if you want to start over)_",
                )
                return

    def handle_callback(self, query: dict):
        callback_id = query["id"]
        data = query.get("data", "")
        message = query.get("message", {})
        chat_id = message.get("chat", {}).get("id")
        message_id = message.get("message_id")

        # Inline buttons are reachable by anyone who can see the message, and
        # Telegram echoes the presser in `from`. Signing a licence without this
        # check means a forged "app_<id>" callback mints Pro for free.
        if query.get("from", {}).get("id") != self.state.get("admin_id"):
            self.answer_callback(callback_id, "Not authorised.")
            return

        if data.startswith("app_"):
            req_id = data[4:]
            req = self.state["pending"].get(req_id)
            if not req:
                self.answer_callback(callback_id, "Request expired or already handled.")
                return

            device_id = req["device_id"]
            buyer_chat_id = req["chat_id"]
            buyer_user = req["username"]

            # Generate RSA-2048 device-locked 6-month license key
            expiry_epoch = int(time.time()) + 180 * 86400
            license_key = sign_license(self.priv_key, f"pro:{device_id}:{expiry_epoch}")

            # Send to buyer
            buyer_msg = (
                "🎉 *Payment Approved! Kriya Pro is Ready!*\n\n"
                f"Your license key for device `{device_id}`:\n\n"
                f"`{license_key}`\n\n"
                "*(Tap the code above to copy)*\n\n"
                "👉 Open Kriya → Tap *Enter License Key* → Paste and activate your 6-Month Semester Pass!"
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
            utr = req.get("utr", "")
            if utr and utr not in self.state.setdefault("used_utrs", []):
                self.state["used_utrs"].append(utr)
            self.state.get("rejections", {}).pop(str(buyer_chat_id), None)
            save_state(self.state)

        elif data.startswith("rej_"):
            req_id = data[4:]
            req = self.state["pending"].get(req_id)
            if not req:
                self.answer_callback(callback_id, "Request expired or already handled.")
                return

            buyer_chat_id = req["chat_id"]
            device_id = req["device_id"]

            rejections = self.state.setdefault("rejections", {})
            user_rej = rejections.setdefault(str(buyer_chat_id), {"count": 0, "cooldown_until": 0})
            user_rej["count"] += 1

            if user_rej["count"] >= 3:
                user_rej["cooldown_until"] = time.time() + 86400
                user_rej["count"] = 0
                self.send_message(
                    buyer_chat_id,
                    f"❌ *Verification failed for Device `{device_id}` (3rd attempt).*\n\n"
                    "Your account has been placed on a 24-hour cooldown. "
                    "If you made a genuine payment, please contact @bakadev directly on Telegram with your receipt.",
                )
                admin_msg = f"❌ *REJECTED & 24h COOLDOWN* for Device `{device_id}` (@{req['username']})"
            else:
                attempts_left = 3 - user_rej["count"]
                self.send_message(
                    buyer_chat_id,
                    f"❌ *Payment verification failed for Device `{device_id}`.*\n\n"
                    f"The transaction could not be matched. Please double-check your 12-digit UTR or contact @bakadev directly. "
                    f"({attempts_left} attempt(s) remaining before a 24h cooldown).",
                )
                admin_msg = f"❌ *REJECTED* (Strike {user_rej['count']}/3) for Device `{device_id}` (@{req['username']})"

            self.edit_message(chat_id, message_id, admin_msg, reply_markup={"inline_keyboard": []})
            self.answer_callback(callback_id, "❌ Rejected.")

            del self.state["pending"][req_id]
            save_state(self.state)

        elif data.startswith("blk_"):
            req_id = data[4:]
            req = self.state["pending"].get(req_id)
            if not req:
                self.answer_callback(callback_id, "Request expired or already handled.")
                return

            buyer_chat_id = req["chat_id"]
            device_id = req["device_id"]
            utr = req.get("utr", "")

            blocked = self.state.setdefault("blocked_users", [])
            if buyer_chat_id not in blocked:
                blocked.append(buyer_chat_id)

            if utr and utr not in self.state.setdefault("used_utrs", []):
                self.state["used_utrs"].append(utr)

            self.send_message(
                buyer_chat_id,
                "🚫 *Your account has been blocked due to suspicious activity or repeated spam.*",
            )

            admin_msg = f"🚫 *REJECTED & BLOCKED* buyer @{req['username']} (Device `{device_id}`)"
            self.edit_message(chat_id, message_id, admin_msg, reply_markup={"inline_keyboard": []})
            self.answer_callback(callback_id, "🚫 User blocked permanently.")

            del self.state["pending"][req_id]
            save_state(self.state)

def main():
    load_env()
    parser = argparse.ArgumentParser(description="Kriya Pro Telegram Bot")
    parser.add_argument("--token", default=os.environ.get("TELEGRAM_BOT_TOKEN"), help="Bot API token")
    parser.add_argument("--admin", type=int, default=os.environ.get("ADMIN_CHAT_ID"), help="Admin chat ID")
    parser.add_argument("--port", type=int, default=int(os.environ.get("PORT", "8080")), help="HTTP health/webhook port")
    parser.add_argument("--url", default=os.environ.get("RENDER_EXTERNAL_URL"), help="Public external URL for webhooks")
    parser.add_argument("--db", default=os.environ.get("DATABASE_URL"), help="Database URL (postgresql:// or sqlite://)")
    args = parser.parse_args()

    if args.db:
        get_store(args.db)

    if not args.token:
        print("Error: No bot token provided. Set TELEGRAM_BOT_TOKEN in tool/.env or pass --token", file=sys.stderr)
        sys.exit(1)

    try:
        bot = TelegramBot(args.token, args.admin)
    except RuntimeError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    # Start HTTP server on port
    try:
        server = HTTPServer(("0.0.0.0", args.port), BotHttpHandler)
        server.bot = bot
        threading.Thread(target=server.serve_forever, daemon=True).start()
        print(f"🌐 HTTP server listening on 0.0.0.0:{args.port}")
    except Exception as e:
        print(f"⚠️ Could not bind HTTP server on {args.port}: {e}")

    if args.url:
        if not bot.setup_webhook(args.url):
            # Updates Telegram delivers without the registered secret header are
            # rejected, so a bot that stayed in webhook mode here would look
            # online and answer nothing.
            print("⚠️ Falling back to long polling.")
            bot.run_polling()
            return
        print(f"🤖 Bot running in WEBHOOK mode on {args.url}")
        try:
            while True:
                time.sleep(3600)
        except KeyboardInterrupt:
            print("\n🛑 Bot stopped.")
    else:
        bot.remove_webhook()
        bot.run_polling()

if __name__ == "__main__":
    main()
