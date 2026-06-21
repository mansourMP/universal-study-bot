# API v2 routes - Normalized vocabulary and content endpoints
from .vocabulary import router as vocabulary_router
from .search import router as search_router
from .content import router as content_router
from .tutor import router as tutor_router

__all__ = ["vocabulary_router", "search_router", "content_router", "tutor_router"]
