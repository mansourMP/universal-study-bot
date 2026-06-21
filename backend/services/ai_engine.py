import os
import json
from typing import List, Dict, Optional, Any
from openai import OpenAI

# Load environment directly or pass in configuration
# For simplicity in this refactor, we assume env vars are loaded by main app

DEEPSEEK_MODEL = os.getenv("DEEPSEEK_MODEL", "deepseek-reasoner") # Default to Reasoner!
DEEPSEEK_API_KEY = os.getenv("DEEPSEEK_API_KEY")
DEEPSEEK_BASE_URL = os.getenv("DEEPSEEK_API_BASE", "https://api.deepseek.com/v1")

OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4o")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")

deepseek_client = OpenAI(api_key=DEEPSEEK_API_KEY, base_url=DEEPSEEK_BASE_URL) if DEEPSEEK_API_KEY else None
openai_client = OpenAI(api_key=OPENAI_API_KEY) if OPENAI_API_KEY else None

def run_chat_completion(
    messages: List[Dict[str, str]],
    temperature: float = 0.4,
    ai_provider: Optional[str] = None,
    max_tokens: Optional[int] = None,
    allow_fallback: bool = True,
) -> str:
    """
    Unified chat completion wrapper for DeepSeek/OpenAI.
    """
    last_error = None

    def _create_completion(llm_client: OpenAI, model: str) -> str:
        payload = {"model": model, "messages": messages}
        # DeepSeek-Reasoner doesn't support 'temperature' in standard way sometimes, 
        # but we'll include it for compatibility if model is chat
        if "reasoner" not in model:
             payload["temperature"] = temperature
        
        if max_tokens is not None:
            payload["max_tokens"] = max_tokens
        
        response = llm_client.chat.completions.create(**payload)
        return response.choices[0].message.content.strip()

    def _try_deepseek() -> str:
        if deepseek_client is None:
            raise RuntimeError("DeepSeek client not configured.")
        return _create_completion(deepseek_client, DEEPSEEK_MODEL)

    def _try_openai() -> str:
        if openai_client is None:
            raise RuntimeError("OpenAI client not configured.")
        return _create_completion(openai_client, OPENAI_MODEL)

    # Provider Selection Logic
    if ai_provider == "deepseek":
        try:
            return _try_deepseek()
        except Exception as exc:
            last_error = exc
        if allow_fallback:
            try:
                return _try_openai()
            except Exception as exc:
                last_error = exc
    elif ai_provider == "openai":
        try:
            return _try_openai()
        except Exception as exc:
            last_error = exc
        if allow_fallback:
            try:
                return _try_deepseek()
            except Exception as exc:
                last_error = exc
    else: # Default
        if deepseek_client:
            try:
                return _try_deepseek()
            except Exception as exc:
                last_error = exc
                if openai_client and allow_fallback:
                    try:
                        return _try_openai()
                    except Exception as exc_fb:
                        last_error = exc_fb
        elif openai_client:
            try:
                return _try_openai()
            except Exception as exc:
                last_error = exc
        else:
            raise RuntimeError("No LLM clients configured.")

    raise RuntimeError(f"No chat provider available or all failed. Last error: {last_error}")
