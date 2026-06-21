#!/bin/bash
# Start Backend Server - Run this to make articles appear in iOS app

echo "🚀 Starting Know AI Backend Server..."
echo ""

cd "$(dirname "$0")"

# Check if virtual environment exists
if [ ! -d ".venv" ]; then
    echo "❌ Virtual environment not found. Run setup first."
    exit 1
fi

# Activate venv and start server
source .venv/bin/activate

echo "✅ Virtual environment activated"
echo "🌐 Starting FastAPI server on http://0.0.0.0:8000"
echo ""
echo "📱 Your iOS app can now fetch articles from the Explore tab!"
echo "⚠️  Keep this terminal window open while using the app"
echo ""
echo "Press Ctrl+C to stop the server"
echo "----------------------------------------"

# Use uvicorn directly since main.py doesn't have an entry point
uvicorn main:app --host 127.0.0.1 --port 8000 --reload
