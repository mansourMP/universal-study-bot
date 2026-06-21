"""
Smart caching system for vocabulary data
Uses LRU cache with automatic expiration
"""

import time
import json
import hashlib
from typing import Optional, Any, Dict
from functools import wraps

class SmartCache:
    def __init__(self, ttl: int = 300, max_size: int = 1000):
        """
        Args:
            ttl: Time to live in seconds (default 5 minutes)
            max_size: Maximum number of cached items
        """
        self.cache: Dict[str, tuple[Any, float]] = {}
        self.ttl = ttl
        self.max_size = max_size
        self.hits = 0
        self.misses = 0
    
    def get(self, key: str) -> Optional[Any]:
        """Get cached value if not expired"""
        if key in self.cache:
            value, timestamp = self.cache[key]
            if time.time() - timestamp < self.ttl:
                self.hits += 1
                return value
            else:
                # Expired, remove it
                del self.cache[key]
        
        self.misses += 1
        return None
    
    def set(self, key: str, value: Any):
        """Set cached value with timestamp"""
        # If cache is full, remove oldest item
        if len(self.cache) >= self.max_size:
            oldest_key = min(self.cache.items(), key=lambda x: x[1][1])[0]
            del self.cache[oldest_key]
        
        self.cache[key] = (value, time.time())
    
    def clear(self):
        """Clear all cache"""
        self.cache.clear()
        self.hits = 0
        self.misses = 0
    
    def stats(self) -> Dict:
        """Get cache statistics"""
        total = self.hits + self.misses
        hit_rate = (self.hits / total * 100) if total > 0 else 0
        
        return {
            "size": len(self.cache),
            "max_size": self.max_size,
            "hits": self.hits,
            "misses": self.misses,
            "hit_rate": f"{hit_rate:.1f}%",
            "ttl_seconds": self.ttl
        }
    
    @staticmethod
    def make_key(*args, **kwargs) -> str:
        """Generate cache key from arguments"""
        key_str = json.dumps({
            'args': [str(a) for a in args],
            'kwargs': {k: str(v) for k, v in kwargs.items()}
        }, sort_keys=True)
        return hashlib.md5(key_str.encode()).hexdigest()


def cached(ttl: int = 300):
    """Decorator for caching function results"""
    cache = SmartCache(ttl=ttl)
    
    def decorator(func):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            # Generate cache key
            cache_key = SmartCache.make_key(func.__name__, *args, **kwargs)
            
            # Check cache
            cached_value = cache.get(cache_key)
            if cached_value is not None:
                return cached_value
            
            # Call function
            result = await func(*args, **kwargs)
            
            # Cache result
            cache.set(cache_key, result)
            
            return result
        
        # Attach cache for inspection
        wrapper.cache = cache
        return wrapper
    
    return decorator
