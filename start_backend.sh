#!/bin/bash
# Startup script for Dragon Chinese Learning App
# This starts the backend server

echo "🚀 Starting Dragon Chinese Backend..."

# Navigate to backend directory
cd "$(dirname "$0")/backend"

# Kill any existing backend processes
echo "📋 Checking for existing processes..."
pkill -f "uvicorn.*main:app" 2>/dev/null
sleep 2

# Pick python runtime (prefer 3.13 if available)
if command -v python3.13 >/dev/null 2>&1; then
  PYTHON_BIN="python3.13"
else
  PYTHON_BIN="python3"
fi

# Optional hot-reload (off by default for stability)
if [ "${BACKEND_RELOAD:-0}" = "1" ]; then
  RELOAD_FLAG="--reload"
else
  RELOAD_FLAG=""
fi

# Start the backend server
echo "🔧 Starting backend server on port 8000 (reload=${BACKEND_RELOAD:-0})..."
$PYTHON_BIN -m uvicorn main:app --host 127.0.0.1 --port 8000 $RELOAD_FLAG >/tmp/backend.log 2>&1 &

# Wait for server to start
echo "⏳ Waiting for server to start..."
sleep 5

# Test if server is running
if curl -s http://localhost:8000/health > /dev/null; then
    echo "✅ Backend server is running!"
    echo "📍 API: http://localhost:8000"
    echo "📚 Docs: http://localhost:8000/docs"
    echo "🪵 Logs: tail -f /tmp/backend.log"
    echo ""
    echo "🎯 Quick Study API Test:"
    echo "curl -X POST 'http://localhost:8000/api/v2/learning/session/start?unit_id=UNIT_HSK1_001&word_count=5' -H 'X-API-Key: test_key_12345'"
    echo ""
    echo "To stop: pkill -f 'uvicorn.*main:app'"
else
    echo "❌ Backend failed to start. Check logs:"
    echo "tail -f /tmp/backend.log"
    exit 1
fi
