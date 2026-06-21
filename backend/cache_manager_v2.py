"""
cache_manager_v2.py - Thread-safe LRU cache with TTL, metrics, and prefix-based TTL overrides

Features:
- Thread-safe with RLock
- LRU eviction when max_size reached
- TTL-based expiration
- Per-prefix TTL overrides
- Comprehensive metrics (hits, misses, evictions, expired)
- Prefix-based invalidation

Usage:
    from cache_manager_v2 import CACHE
    
    # Basic usage
    value = CACHE.get("key")
    if value is None:
        value = expensive_operation()
        CACHE.set("key", value)
    
    # With decorator
    @CACHE.cached(prefix="vocab")
    def get_vocabulary(lang, level):
        return db.query(...)
"""

import time
import hashlib
import json
import threading
from collections import OrderedDict
from dataclasses import dataclass, field
from typing import Optional, Any, Dict, Callable, TypeVar
from functools import wraps


@dataclass
class CacheStats:
    """Track cache performance metrics"""
    hits: int = 0
    misses: int = 0
    sets: int = 0
    evictions: int = 0
    expired: int = 0
    
    def hit_rate(self) -> float:
        total = self.hits + self.misses
        return (self.hits / total * 100) if total > 0 else 0.0
    
    def to_dict(self) -> Dict:
        return {
            "hits": self.hits,
            "misses": self.misses,
            "sets": self.sets,
            "evictions": self.evictions,
            "expired": self.expired,
            "hit_rate": f"{self.hit_rate():.1f}%"
        }


class SmartCacheV2:
    """
    Thread-safe LRU cache with TTL and metrics.
    
    Args:
        ttl: Default time-to-live in seconds (default: 300)
        max_size: Maximum number of cached items (default: 2000)
    """
    
    def __init__(self, ttl: int = 300, max_size: int = 2000):
        self.ttl = ttl
        self.max_size = max_size
        self._cache: OrderedDict[str, tuple[Any, float]] = OrderedDict()
        self._lock = threading.RLock()
        self._stats = CacheStats()
        self._ttl_overrides: Dict[str, int] = {}
    
    def set_ttl_for_prefix(self, prefix: str, ttl: int):
        """Set custom TTL for keys starting with a specific prefix"""
        with self._lock:
            self._ttl_overrides[prefix] = ttl
    
    def _get_ttl(self, key: str) -> int:
        """Get TTL for key, checking prefix overrides first"""
        for prefix, ttl in self._ttl_overrides.items():
            if key.startswith(prefix):
                return ttl
        return self.ttl
    
    def get(self, key: str) -> Optional[Any]:
        """
        Get value from cache.
        Returns None if not found or expired.
        """
        with self._lock:
            if key not in self._cache:
                self._stats.misses += 1
                return None
            
            value, expires_at = self._cache[key]
            
            if time.time() > expires_at:
                del self._cache[key]
                self._stats.expired += 1
                self._stats.misses += 1
                return None
            
            # Move to end (most recently used)
            self._cache.move_to_end(key)
            self._stats.hits += 1
            return value
    
    def set(self, key: str, value: Any, ttl: Optional[int] = None):
        """
        Set value in cache with optional custom TTL.
        Evicts oldest items if at capacity.
        """
        effective_ttl = ttl if ttl is not None else self._get_ttl(key)
        expires_at = time.time() + effective_ttl
        
        with self._lock:
            # Evict if at capacity
            while len(self._cache) >= self.max_size:
                self._cache.popitem(last=False)  # Remove oldest (first) item
                self._stats.evictions += 1
            
            self._cache[key] = (value, expires_at)
            self._cache.move_to_end(key)
            self._stats.sets += 1
    
    def delete(self, key: str) -> bool:
        """Delete a specific key. Returns True if key existed."""
        with self._lock:
            if key in self._cache:
                del self._cache[key]
                return True
            return False
    
    def invalidate_prefix(self, prefix: str) -> int:
        """
        Invalidate all keys matching prefix.
        Returns number of keys deleted.
        """
        with self._lock:
            to_delete = [k for k in self._cache if k.startswith(prefix)]
            for k in to_delete:
                del self._cache[k]
            return len(to_delete)
    
    def clear(self):
        """Clear all cached data and reset stats"""
        with self._lock:
            self._cache.clear()
            self._stats = CacheStats()
    
    def stats(self) -> Dict:
        """Get cache statistics"""
        with self._lock:
            return {
                "size": len(self._cache),
                "max_size": self.max_size,
                "default_ttl": self.ttl,
                "ttl_overrides": dict(self._ttl_overrides),
                **self._stats.to_dict()
            }
    
    @staticmethod
    def make_key(*args, **kwargs) -> str:
        """
        Generate a cache key from function arguments.
        Uses MD5 hash of JSON-serialized arguments.
        """
        key_data = {
            'args': [str(a) for a in args],
            'kwargs': {k: str(v) for k, v in sorted(kwargs.items())}
        }
        key_str = json.dumps(key_data, sort_keys=True)
        return hashlib.md5(key_str.encode()).hexdigest()
    
    def cached(self, prefix: str = "", ttl: Optional[int] = None):
        """
        Decorator for caching function results.
        
        Args:
            prefix: Key prefix for grouping/invalidation
            ttl: Custom TTL for this function (optional)
        
        Example:
            @cache.cached(prefix="vocab", ttl=600)
            def get_vocabulary(lang: str, level: int):
                return db.query(...)
        """
        def decorator(func: Callable) -> Callable:
            @wraps(func)
            def wrapper(*args, **kwargs):
                # Generate cache key
                key_suffix = self.make_key(*args, **kwargs)
                key = f"{prefix}:{key_suffix}" if prefix else key_suffix
                
                # Try cache
                cached = self.get(key)
                if cached is not None:
                    return cached
                
                # Execute function
                result = func(*args, **kwargs)
                
                # Cache result
                self.set(key, result, ttl)
                return result
            
            # Add cache control methods to the wrapper
            wrapper.cache_invalidate = lambda: self.invalidate_prefix(f"{prefix}:")
            wrapper.cache_key = lambda *a, **kw: f"{prefix}:{self.make_key(*a, **kw)}"
            
            return wrapper
        return decorator


# Global cache instance with recommended settings
CACHE = SmartCacheV2(ttl=300, max_size=2000)

# Configure TTL overrides for different data types
CACHE.set_ttl_for_prefix("vocab:", 300)        # 5 min for vocabulary
CACHE.set_ttl_for_prefix("concept:", 600)      # 10 min for concept details
CACHE.set_ttl_for_prefix("search:", 60)        # 1 min for search results
CACHE.set_ttl_for_prefix("feed:", 120)         # 2 min for content feed
CACHE.set_ttl_for_prefix("content:", 600)      # 10 min for content details
CACHE.set_ttl_for_prefix("transcript:", 3600)  # 1 hour for transcripts


# Convenience functions
def get_cache_stats() -> Dict:
    """Get global cache statistics"""
    return CACHE.stats()


def invalidate_vocabulary_cache():
    """Invalidate all vocabulary-related cache entries"""
    count = CACHE.invalidate_prefix("vocab:")
    count += CACHE.invalidate_prefix("concept:")
    count += CACHE.invalidate_prefix("search:")
    return count


def invalidate_content_cache():
    """Invalidate all content-related cache entries"""
    count = CACHE.invalidate_prefix("feed:")
    count += CACHE.invalidate_prefix("content:")
    count += CACHE.invalidate_prefix("transcript:")
    return count
