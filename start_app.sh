#!/bin/bash
# Complete startup script for Dragon Chinese App
# Starts backend and Flutter app

echo "🐉 Dragon Chinese Learning App - Complete Startup"
echo "=================================================="
echo ""

# Start backend
echo "1️⃣ Starting Backend Server..."
cd "$(dirname "$0")"
chmod +x start_backend.sh
./start_backend.sh

if [ $? -ne 0 ]; then
    echo "❌ Backend failed to start. Aborting."
    exit 1
fi

echo ""
echo "2️⃣ Starting Flutter App..."
echo "Opening new terminal for Flutter..."
echo ""

# Start Flutter in a new terminal window
osascript <<EOF
tell application "Terminal"
    do script "cd '$(pwd)/dragon_chinese' && echo '🎨 Starting Flutter App...' && flutter run"
    activate
end tell
EOF

echo "✅ All services started!"
echo ""
echo "📱 Flutter app is launching in a new terminal window"
echo "🌐 Backend API: http://localhost:8000"
echo ""
echo "To stop everything:"
echo "  Backend: pkill -f 'uvicorn.*main:app'"
echo "  Flutter: Press 'q' in the Flutter terminal"
