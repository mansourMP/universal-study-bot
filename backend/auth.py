"""
Authentication and API Key Management
Protects your API from unauthorized access
"""

from fastapi import HTTPException, Security, Request, Depends
from fastapi.security import APIKeyHeader
import hashlib
import secrets
import os
from typing import Optional

API_KEY_HEADER = APIKeyHeader(name="X-API-Key", auto_error=False)

# In production, store these in a database
# For now, use environment variable or hardcoded (change these!)
VALID_API_KEYS = {
    # Format: hashed_key: user_id
    # Generate with: hashlib.sha256("your-secret-key".encode()).hexdigest()
}

def load_api_keys():
    """Load API keys from environment or config"""
    # Example: Load from environment
    ios_key = os.getenv("IOS_APP_API_KEY")
    if ios_key:
        hashed = hashlib.sha256(ios_key.encode()).hexdigest()
        VALID_API_KEYS[hashed] = "ios_app"
    
    # Add more keys as needed
    admin_key = os.getenv("ADMIN_API_KEY")
    if admin_key:
        hashed = hashlib.sha256(admin_key.encode()).hexdigest()
        VALID_API_KEYS[hashed] = "admin"

# Load keys on startup
load_api_keys()

def _auth_disabled() -> bool:
    value = os.getenv("AUTH_DISABLED", "")
    return value.lower() in {"1", "true", "yes"}


from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
security_bearer = HTTPBearer(auto_error=False)

async def verify_api_key(
    request: Request,
    api_key_header: str = Security(API_KEY_HEADER),
    bearer: Optional[HTTPAuthorizationCredentials] = Security(security_bearer)
) -> str:
    """
    Verify API key (X-API-Key header OR Bearer token) and return client ID.
    Usage:
        @app.get("/api/protected")
        async def protected_endpoint(client_id: str = Depends(verify_api_key)):
            # Client is verified
            pass
    """
    if _auth_disabled():
        return "dev_client"

    # DEV BYPASS: If a user_id is provided in headers, allow it for dev
    # In production, remove this or guard with environment variable
    if request.headers.get("X-User-Id"):
       return "dev_client"

    # 1. Try X-API-Key header
    api_key = api_key_header
    
    # 2. Try Bearer token
    if not api_key and bearer:
        api_key = bearer.credentials
    
    if not api_key:
        raise HTTPException(
            status_code=401,
            detail="Authentication required. Provide X-API-Key header or Bearer token."
        )
    
    # Hash the provided key
    hashed = hashlib.sha256(api_key.encode()).hexdigest()
    
    # Check if valid
    if hashed not in VALID_API_KEYS:
        raise HTTPException(
            status_code=403,
            detail="Invalid API key"
        )
    
    # Return client ID (e.g., "ios_app", "admin")
    return VALID_API_KEYS[hashed]


async def get_user_id(request: Request) -> str:
    """
    Extract user ID from X-User-Id header.
    Returns 'anonymous' if not present, or raises error if strict mode required.
    """
    user_id = request.headers.get("X-User-Id")
    if not user_id:
        return "anonymous"
    return user_id


async def require_user_id(request: Request) -> str:
    """
    Strictly require X-User-Id header.
    """
    if _auth_disabled():
        return "anonymous"
    user_id = request.headers.get("X-User-Id")
    if not user_id:
        raise HTTPException(status_code=400, detail="X-User-Id header required")
    return user_id


async def optional_api_key(api_key: str = Security(API_KEY_HEADER)) -> Optional[str]:
    """
    Optional API key verification
    Returns user_id if valid, None if no key provided
    
    Usage:
        @app.get("/api/public")
        async def public_endpoint(user_id: Optional[str] = Depends(optional_api_key)):
            if user_id:
                # Authenticated user
                return {"premium": True}
            else:
                # Anonymous user
                return {"premium": False}
    """
    if not api_key:
        return None
    
    try:
        return await verify_api_key(api_key)
    except HTTPException:
        return None


def generate_api_key() -> str:
    """
    Generate a new API key
    
    Usage:
        >>> key = generate_api_key()
        >>> print(f"API Key: {key}")
        >>> print(f"Hashed: {hashlib.sha256(key.encode()).hexdigest()}")
    """
    return secrets.token_urlsafe(32)


def hash_api_key(key: str) -> str:
    """Hash an API key for storage"""
    return hashlib.sha256(key.encode()).hexdigest()


# Rate limiting per user
class UserRateLimiter:
    """Track API usage per user"""
    
    def __init__(self):
        self.usage = {}  # user_id -> {count, reset_time}
    
    def check_limit(self, user_id: str, limit: int = 100, window: int = 3600) -> bool:
        """
        Check if user is within rate limit
        
        Args:
            user_id: User identifier
            limit: Max requests per window
            window: Time window in seconds (default 1 hour)
        
        Returns:
            True if within limit, False if exceeded
        """
        import time
        now = time.time()
        
        if user_id not in self.usage:
            self.usage[user_id] = {'count': 1, 'reset_time': now + window}
            return True
        
        user_data = self.usage[user_id]
        
        # Reset if window expired
        if now > user_data['reset_time']:
            self.usage[user_id] = {'count': 1, 'reset_time': now + window}
            return True
        
        # Check limit
        if user_data['count'] >= limit:
            return False
        
        # Increment count
        user_data['count'] += 1
        return True
    
    def get_usage(self, user_id: str) -> dict:
        """Get current usage for user"""
        if user_id not in self.usage:
            return {'count': 0, 'limit': 100}
        
        return {
            'count': self.usage[user_id]['count'],
            'limit': 100,
            'reset_at': self.usage[user_id]['reset_time']
        }


# Global rate limiter
user_rate_limiter = UserRateLimiter()


async def check_user_rate_limit(user_id: str = Depends(require_user_id)):
    """
    Dependency to check user rate limit (per-user, not per API key)
    
    Usage:
        @app.get("/api/expensive")
        async def expensive_endpoint(user_id: str = Depends(check_user_rate_limit)):
            # User is within rate limit
            return {"result": "success"}
    """
    if not user_rate_limiter.check_limit(user_id):
        raise HTTPException(
            status_code=429,
            detail="Rate limit exceeded. Try again later."
        )
    return user_id

async def check_user_premium_status(user_id: str = Depends(require_user_id)) -> bool:
    """
    Check if user is premium.
    TODO: Replace this with real database lookup (e.g., SELECT is_premium FROM users...)
    """
    # MOCK IMPLEMENTATION:
    # Allow if user_id starts with 'premium_' OR it's our test user 'test_user' (for now)
    # In production, this MUST query your users database synced with Apple StoreKit.
    if user_id.startswith("premium_") or user_id == "test_user":
        return True
    return False
