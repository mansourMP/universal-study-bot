# 🐉 Dragon Chinese Learning App

## Quick Start (One Command!)

### Start Everything

```bash
cd "/Users/mansur/universal_study_bot org"
./start_app.sh
```

This will:
1. ✅ Start the backend server (port 8000)
2. ✅ Launch the Flutter app in a new terminal

---

## Or Start Components Separately

### Backend Only

```bash
cd "/Users/mansur/universal_study_bot org"
./start_backend.sh
```

### Flutter Only

```bash
cd "/Users/mansur/universal_study_bot org/dragon_chinese"
flutter run
```

---

## Verify Everything is Running

### Check Backend

```bash
curl http://localhost:8000/health
# Should return: {"status":"ok"}
```

### Test Quick Study API

```bash
curl -X POST "http://localhost:8000/api/v2/learning/session/start?unit_id=UNIT_HSK1_001&word_count=5" \
  -H "X-API-Key: test_key_12345"
```

Returns 5 words with batch exercises!

---

## Stop Everything

### Stop Backend

```bash
pkill -f "uvicorn.*main:app"
```

### Stop Flutter

Press `q` in the Flutter terminal

---

## What's New: Quick Study 🎯

**Problem Solved**: No more learning 1 word per lesson!

**New Feature**: Learn 5-10 words in one session
- ✅ Backend API ready
- ⏸️ Flutter UI pending (4-6 hours to build)

**API Endpoint**: `/api/v2/learning/session/start`

---

## Current Status

- ✅ Backend server running on port 8000
- ✅ Quick Study API working
- ✅ 20 HSK1 units in database
- ⏸️ Flutter UI for Quick Study (not built yet)

---

## Troubleshooting

**Backend won't start?**
```bash
# Check if port 8000 is in use
lsof -i :8000
# Kill any process using it
pkill -f "uvicorn.*main:app"
# Try again
./start_backend.sh
```

**Flutter build errors?**
```bash
cd dragon_chinese
flutter clean
flutter pub get
flutter run
```

---

## Development

- **Backend**: Auto-reloads when you edit Python files
- **Flutter**: Press `r` for hot reload, `R` for full restart

---

## Documentation

- [HOW_TO_RUN.md](./HOW_TO_RUN.md) - Detailed setup guide
- [Quick Study Walkthrough](file:///Users/mansur/.gemini/antigravity/brain/b935899e-80a4-4ec5-bfdd-ed1e79d43eed/quick_study_walkthrough.md) - New feature docs

---

**Ready to learn Chinese? Run `./start_app.sh` and get started! 🚀**
