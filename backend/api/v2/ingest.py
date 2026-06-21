from fastapi import APIRouter, Depends, UploadFile, File, Form, HTTPException, Request
from typing import Optional, Dict
from ai_guard import ai_guard_dependency
from pydantic import BaseModel
from api.v2.schemas import APIStudySet
from services.ingestion import extract_text_and_images_from_upload, build_study_set_from_text

# Use main app's save_study_set if possible, or import from a db service
# For refactor, we'll assume a shared save function will be available or we return the set
# Ideally, database logic should be in a service too.
# We'll use a placeholder for persistent storage in this refactor step.
def save_study_set(study_set: APIStudySet):
    # This should be replaced by DB call
    pass

router = APIRouter(prefix="/api/v2/ingest", tags=["Ingestion"])

class IngestResponse(BaseModel):
    success: bool
    study_set: Optional[APIStudySet] = None
    error: Optional[str] = None
    usage: Optional[dict] = None

@router.post("/file", response_model=IngestResponse)
async def ingest_file(
    http_request: Request,
    file: UploadFile = File(...),
    source_type: str = Form(...),
    depth: Optional[str] = Form(None),
    include_images: Optional[bool] = Form(False),
    max_images: Optional[int] = Form(None),
    _: None = Depends(ai_guard_dependency),
):
    """
    Ingests a raw file (PDF, Doc, etc.) and converts it into a Study Set using AI.
    """
    try:
        max_images_value = max(1, min(10, max_images or 10))
        
        # 1. Extract content
        extracted_text, image_paths = await extract_text_and_images_from_upload(
            file,
            source_type,
            max_images=max_images_value,
        )
        
        # 2. Build Study Set (AI Processing)
        # Note: Resolve provider from request/config if needed
        study_set, usage = await build_study_set_from_text(
            extracted_text,
            source_type,
            depth,
            title_hint=file.filename,
            image_paths=image_paths,
            include_image_captions=bool(include_images),
            ai_provider="deepseek",  # Default to our new upgraded brain!
            allow_fallback=True,
        )
        
        # 3. Save
        save_study_set(study_set)
        
        return IngestResponse(
            success=True, 
            study_set=study_set, 
            error=None, 
            usage=usage.dict()
        )
        
    except HTTPException as exc:
        return IngestResponse(success=False, error=str(exc.detail))
    except Exception as exc:
        return IngestResponse(success=False, error=str(exc))
