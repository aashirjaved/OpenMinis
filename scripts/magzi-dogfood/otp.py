"""Local dogfood only: plant a known login code for <email> (no SMTP on this Mac).

Run right after the app taps "Send code"; verify uses the newest OTP row.
usage: otp.py <state_dir> <email> [code]
"""
import hashlib, os, sqlite3, sys, time

state, email = sys.argv[1], sys.argv[2]
code = sys.argv[3] if len(sys.argv) > 3 else "424242"
db = sqlite3.connect(f"{state}/mobile.db")
uid = db.execute("SELECT user_id FROM mobile_users WHERE email=?", (email,)).fetchone()[0]
salt = os.urandom(16).hex()
now = int(time.time() * 1000)
db.execute("INSERT INTO mobile_email_otps(otp_id,user_id,email,code_salt_hex,code_hash_hex,created_at_ms,expires_at_ms) VALUES(?,?,?,?,?,?,?)",
           (f"otp_dev_{now}", uid, email, salt, hashlib.sha256(f"{salt}:{code}".encode()).hexdigest(), now + 1000, now + 600000))
db.commit()
print(f"planted code {code} for {email}")
