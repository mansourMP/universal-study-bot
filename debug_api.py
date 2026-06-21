import os
import json
import urllib.request as urlrequest
import urllib.error as urlerror

DEEPSEEK_API_KEY = os.getenv("DEEPSEEK_API_KEY", "").strip()
DEEPSEEK_BASE_URL = os.getenv("DEEPSEEK_API_BASE", "https://api.deepseek.com/v1").rstrip("/")

def _http_post_json(url, headers, payload):
    print(f"Connecting to {url}...", flush=True)
    body = json.dumps(payload).encode("utf-8")
    req = urlrequest.Request(url, data=body, headers=headers, method="POST")
    try:
        with urlrequest.urlopen(req, timeout=30) as resp:
            print("Response received!", flush=True)
            return json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        print(f"Error: {e}", flush=True)
        return None

def test():
    if not DEEPSEEK_API_KEY:
        print("No API Key found!")
        return

    payload = {
        "model": "deepseek-chat",
        "messages": [{"role": "user", "content": "Hello, are you working?"}],
        "max_tokens": 10
    }
    headers = {
        "Authorization": f"Bearer {DEEPSEEK_API_KEY}",
        "Content-Type": "application/json"
    }
    
    res = _http_post_json(f"{DEEPSEEK_BASE_URL}/chat/completions", headers, payload)
    if res:
        print("Success:", json.dumps(res, indent=2))

if __name__ == "__main__":
    test()
