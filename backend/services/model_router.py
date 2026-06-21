import asyncio
import os
from typing import Any, Dict, List, Optional, Tuple

import httpx
from openai import OpenAI

DEFAULT_PROVIDER = os.getenv("AI_PROVIDER_DEFAULT", "gemini").lower()
SUPPORTED_PROVIDERS = {"gemini", "openai", "deepseek"}

GEMINI_API_KEY = os.getenv("GOOGLE_API_KEY")
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-1.5-flash")

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-mini")

DEEPSEEK_API_KEY = os.getenv("DEEPSEEK_API_KEY")
DEEPSEEK_MODEL = os.getenv("DEEPSEEK_MODEL", "deepseek-chat")
DEEPSEEK_BASE_URL = os.getenv("DEEPSEEK_API_BASE", "https://api.deepseek.com/v1")

_openai_client = OpenAI(api_key=OPENAI_API_KEY) if OPENAI_API_KEY else None
_deepseek_client = (
    OpenAI(api_key=DEEPSEEK_API_KEY, base_url=DEEPSEEK_BASE_URL)
    if DEEPSEEK_API_KEY
    else None
)


def _dedupe(items: List[str]) -> List[str]:
    seen: set[str] = set()
    output: List[str] = []
    for item in items:
        if item in seen:
            continue
        seen.add(item)
        output.append(item)
    return output


def _provider_order(
    ai_provider: Optional[str],
    allow_fallback: bool,
) -> List[str]:
    requested = _resolve_requested_provider(ai_provider)

    if not allow_fallback:
        return [requested]

    preferred = [requested, DEFAULT_PROVIDER, "gemini", "openai", "deepseek"]
    return _dedupe([provider for provider in preferred if provider in SUPPORTED_PROVIDERS])


def _resolve_requested_provider(ai_provider: Optional[str]) -> str:
    requested = (ai_provider or DEFAULT_PROVIDER).strip().lower()
    if requested in SUPPORTED_PROVIDERS:
        return requested
    if DEFAULT_PROVIDER in SUPPORTED_PROVIDERS:
        return DEFAULT_PROVIDER
    return "gemini"


def _provider_model(provider: str) -> str:
    if provider == "gemini":
        return GEMINI_MODEL
    if provider == "openai":
        return OPENAI_MODEL
    if provider == "deepseek":
        return DEEPSEEK_MODEL
    return "unknown"


def _to_openai_messages(messages: List[Dict[str, str]]) -> List[Dict[str, str]]:
    output: List[Dict[str, str]] = []
    for message in messages:
        role = (message.get("role") or "user").strip().lower()
        if role not in {"system", "user", "assistant"}:
            role = "user"
        content = (message.get("content") or "").strip()
        if not content:
            continue
        output.append({"role": role, "content": content})
    return output


def _to_gemini_payload(
    messages: List[Dict[str, str]],
    temperature: float,
    max_tokens: Optional[int],
) -> Dict[str, Any]:
    system_lines: List[str] = []
    contents: List[Dict[str, Any]] = []

    for message in messages:
        role = (message.get("role") or "user").strip().lower()
        content = (message.get("content") or "").strip()
        if not content:
            continue
        if role == "system":
            system_lines.append(content)
            continue
        gemini_role = "model" if role == "assistant" else "user"
        contents.append({"role": gemini_role, "parts": [{"text": content}]})

    if not contents:
        contents = [{"role": "user", "parts": [{"text": "Hello"}]}]

    payload: Dict[str, Any] = {
        "contents": contents,
        "generationConfig": {"temperature": temperature},
    }
    if max_tokens is not None:
        payload["generationConfig"]["maxOutputTokens"] = max_tokens
    if system_lines:
        payload["systemInstruction"] = {"parts": [{"text": "\n\n".join(system_lines)}]}
    return payload


async def _call_gemini(
    messages: List[Dict[str, str]],
    temperature: float,
    max_tokens: Optional[int],
) -> str:
    if not GEMINI_API_KEY:
        raise RuntimeError("Gemini API key missing")

    url = (
        f"https://generativelanguage.googleapis.com/v1beta/models/"
        f"{GEMINI_MODEL}:generateContent"
    )
    params = {"key": GEMINI_API_KEY}
    payload = _to_gemini_payload(messages, temperature, max_tokens)

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(url, params=params, json=payload)
    if response.status_code >= 400:
        raise RuntimeError(f"Gemini request failed: {response.status_code} {response.text}")

    data = response.json()
    candidates = data.get("candidates") or []
    if not candidates:
        raise RuntimeError(f"Gemini returned no candidates: {data}")
    parts = (candidates[0].get("content") or {}).get("parts") or []
    text = "\n".join(part.get("text", "") for part in parts if part.get("text"))
    if not text.strip():
        raise RuntimeError(f"Gemini returned empty response: {data}")
    return text.strip()


async def _call_openai_compatible(
    client: OpenAI,
    model: str,
    messages: List[Dict[str, str]],
    temperature: float,
    max_tokens: Optional[int],
) -> str:
    payload: Dict[str, Any] = {"model": model, "messages": _to_openai_messages(messages)}
    if "reasoner" not in model:
        payload["temperature"] = temperature
    if max_tokens is not None:
        payload["max_tokens"] = max_tokens

    def _request() -> str:
        response = client.chat.completions.create(**payload)
        return (response.choices[0].message.content or "").strip()

    text = await asyncio.to_thread(_request)
    if not text:
        raise RuntimeError("Provider returned empty response")
    return text


async def run_chat_completion(
    messages: List[Dict[str, str]],
    temperature: float = 0.3,
    ai_provider: Optional[str] = None,
    max_tokens: Optional[int] = 500,
    allow_fallback: bool = True,
) -> Tuple[str, str, str]:
    """
    Backward-compatible router API.
    Returns: (reply_text, provider_used, model_used)
    """
    reply, provider, model, _ = await run_chat_completion_with_metadata(
        messages=messages,
        temperature=temperature,
        ai_provider=ai_provider,
        max_tokens=max_tokens,
        allow_fallback=allow_fallback,
    )
    return reply, provider, model


async def run_chat_completion_with_metadata(
    messages: List[Dict[str, str]],
    temperature: float = 0.3,
    ai_provider: Optional[str] = None,
    max_tokens: Optional[int] = 500,
    allow_fallback: bool = True,
) -> Tuple[str, str, str, Dict[str, Any]]:
    """
    Universal model router.
    Returns: (reply_text, provider_used, model_used, routing_metadata)
    """
    requested_provider = _resolve_requested_provider(ai_provider)
    errors: List[str] = []
    attempts: List[Dict[str, Any]] = []

    for provider in _provider_order(ai_provider, allow_fallback):
        model_name = _provider_model(provider)
        attempt: Dict[str, Any] = {
            "provider": provider,
            "model": model_name,
            "success": False,
        }
        try:
            if provider == "gemini":
                text = await _call_gemini(messages, temperature, max_tokens)
                attempt["success"] = True
                attempts.append(attempt)
                return (
                    text,
                    "gemini",
                    GEMINI_MODEL,
                    {
                        "requested_provider": requested_provider,
                        "fallback_used": requested_provider != "gemini",
                        "provider_attempts": attempts,
                    },
                )
            if provider == "openai":
                if _openai_client is None:
                    raise RuntimeError("OpenAI API key missing")
                text = await _call_openai_compatible(
                    _openai_client,
                    OPENAI_MODEL,
                    messages,
                    temperature,
                    max_tokens,
                )
                attempt["success"] = True
                attempts.append(attempt)
                return (
                    text,
                    "openai",
                    OPENAI_MODEL,
                    {
                        "requested_provider": requested_provider,
                        "fallback_used": requested_provider != "openai",
                        "provider_attempts": attempts,
                    },
                )
            if provider == "deepseek":
                if _deepseek_client is None:
                    raise RuntimeError("DeepSeek API key missing")
                text = await _call_openai_compatible(
                    _deepseek_client,
                    DEEPSEEK_MODEL,
                    messages,
                    temperature,
                    max_tokens,
                )
                attempt["success"] = True
                attempts.append(attempt)
                return (
                    text,
                    "deepseek",
                    DEEPSEEK_MODEL,
                    {
                        "requested_provider": requested_provider,
                        "fallback_used": requested_provider != "deepseek",
                        "provider_attempts": attempts,
                    },
                )
        except Exception as exc:
            attempt["error"] = str(exc)
            attempts.append(attempt)
            errors.append(f"{provider}: {exc}")
            continue

    raise RuntimeError(f"No model provider succeeded. Errors: {' | '.join(errors)}")
