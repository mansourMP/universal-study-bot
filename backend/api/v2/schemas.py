from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime
import uuid

class APIStudySet(BaseModel):
    id: Optional[str] = Field(default_factory=lambda: str(uuid.uuid4()))
    title: str
    condensed_notes_html: Optional[str] = None
    full_text_chunks: List[str] = Field(default_factory=list)
    depth: Optional[str] = None
    image_urls: List[str] = Field(default_factory=list)
    image_captions: List[str] = Field(default_factory=list)

    class Config:
        populate_by_name = True
        json_encoders = {datetime: lambda v: v.isoformat()}

class UsageEstimate(BaseModel):
    tokens_in: int
    tokens_out: int
    tokens_total: int
    stardust: int
