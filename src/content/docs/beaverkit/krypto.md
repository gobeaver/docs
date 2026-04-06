---
title: krypto
description: Crypto utilities — passwords, AES, JWT, HMAC, RSA, OTP.
sidebar:
  order: 3
---

`krypto` is the cryptography toolbox. Includes:

- Password hashing with **bcrypt** and **argon2id**
- **AES-GCM** symmetric encryption
- **JWT** signing and verification (RS256 and HS256)
- **HMAC** helpers
- **RSA** key generation
- **OTP** (TOTP/HOTP)
- Secure random generation

All defaults are chosen to satisfy the security baseline in the GoBeaver
project guidelines (Argon2id or bcrypt cost ≥ 12, AES-256-GCM, etc.).
