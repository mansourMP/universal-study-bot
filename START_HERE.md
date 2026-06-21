# 🐉 HOW TO RUN - 3 TERMINALS

## YOU NEED 3 SEPARATE TERMINALS

### TERMINAL 1: Backend Server

```bash
cd "/Users/mansur/universal_study_bot org/backend"
python3.13 -m uvicorn main:app --reload --port 8000
```

**Keep running!** Should show:
```
INFO:     Uvicorn running on http://127.0.0.1:8000
```

---

### TERMINAL 2: ngrok (Tunnel)

```bash
ngrok http 8000
```

**Keep running!** Copy the HTTPS URL it gives you (e.g., `https://abc123.ngrok.io`)

---

### TERMINAL 3: Flutter App

```bash
cd "/Users/mansur/universal_study_bot org/dragon_chinese"
flutter run
```

Select your device and **keep running!**

---

## Summary

- **Terminal 1** = Backend (localhost:8000)
- **Terminal 2** = ngrok (public HTTPS tunnel)
- **Terminal 3** = Flutter app

All 3 must stay open while using the app.

---

## To Stop

- **Terminal 1**: `Ctrl+C`
- **Terminal 2**: `Ctrl+C`
- **Terminal 3**: Press `q`

---

## Current Status

✅ **Terminal 1** (Backend) is ALREADY RUNNING  
⏸️ **Terminal 2** (ngrok) - You need to start this  
⏸️ **Terminal 3** (Flutter) - You need to start this
