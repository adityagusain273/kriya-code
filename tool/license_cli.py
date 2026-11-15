#!/usr/bin/env python3
import os
import sys
import argparse
import base64
import uuid
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.primitives import hashes, serialization

KEY_PATH = Path(__file__).parent / "bcode_license_private.pem"

def load_or_generate_key() -> rsa.RSAPrivateKey:
    pem_b64 = os.environ.get("LICENSE_PRIVATE_KEY_B64")
    if pem_b64:
        pem_data = base64.b64decode(pem_b64.strip())
        return serialization.load_pem_private_key(pem_data, password=None)
    pem_env = os.environ.get("LICENSE_PRIVATE_KEY_PEM")
    if pem_env:
        return serialization.load_pem_private_key(pem_env.strip().encode("utf-8"), password=None)
    if KEY_PATH.exists():
        with open(KEY_PATH, "rb") as f:
            return serialization.load_pem_private_key(f.read(), password=None)
    
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    with open(KEY_PATH, "wb") as f:
        f.write(
            key.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.PKCS8,
                encryption_algorithm=serialization.NoEncryption(),
            )
        )
    return key

def sign_license(priv_key: rsa.RSAPrivateKey, payload: str) -> str:
    data = payload.strip().encode("utf-8")
    sig = priv_key.sign(data, padding.PKCS1v15(), hashes.SHA256())
    b64_payload = base64.urlsafe_b64encode(data).decode("utf-8").rstrip("=")
    b64_sig = base64.urlsafe_b64encode(sig).decode("utf-8").rstrip("=")
    return f"BCODE.{b64_payload}.{b64_sig}"

def main():
    parser = argparse.ArgumentParser(description="B Code Pro License Key Generator")
    subparsers = parser.add_subparsers(dest="command")

    subparsers.add_parser("init", help="Generate private key and show public modulus")
    subparsers.add_parser("show-public", help="Print public modulus for Flutter code")

    issue_p = subparsers.add_parser("issue", help="Issue a license key for a user")
    issue_p.add_argument("user", help="User email, UPI UTR, or identifier")

    batch_p = subparsers.add_parser("batch", help="Generate a CSV batch for Gumroad / Lemon Squeezy")
    batch_p.add_argument("--count", type=int, default=100, help="Number of keys to generate")
    batch_p.add_argument("--out", type=str, default="gumroad_keys.csv", help="Output CSV filename")

    args = parser.parse_args()
    priv_key = load_or_generate_key()
    pub_numbers = priv_key.public_key().public_numbers()
    modulus_hex = hex(pub_numbers.n)[2:]

    if args.command in ("init", "show-public"):
        print("=== B CODE RSA-2048 PUBLIC MODULUS ===")
        print(modulus_hex)
        print(f"\nPrivate key saved to: {KEY_PATH}")
    elif args.command == "issue":
        key_str = sign_license(priv_key, f"pro:{args.user}")
        print(f"License Key for '{args.user}':\n")
        print(key_str)
    elif args.command == "batch":
        count = args.count
        out_path = Path(args.out)
        with open(out_path, "w") as f:
            f.write("License Key\n")
            for _ in range(count):
                batch_id = uuid.uuid4().hex[:12]
                k = sign_license(priv_key, f"pro:{batch_id}")
                f.write(f"{k}\n")
        print(f"Generated {count} license keys in {out_path.resolve()}")
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
