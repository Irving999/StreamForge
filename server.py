import uuid
import psycopg
import logging
from pathlib import Path
from job_queue import send_message
from jobs import get_job, create_video_and_job
from storage import upload_input, delete_object
from botocore.exceptions import BotoCoreError, ClientError
from fastapi import FastAPI, UploadFile, File, HTTPException

app = FastAPI()

logger = logging.getLogger(__name__)

ALLOWED_EXTENSIONS = {".mp4", ".mov", ".mkv", ".webm"}
ALLOWED_CONTENT_TYPES = {
    "video/mp4",
    "video/quicktime",
    "video/x-matroska",
    "video/webm",
}
    
@app.post("/videos/")
async def upload_video(file: UploadFile = File(...)):
    extension = Path(file.filename).suffix.lower()

    if extension not in ALLOWED_EXTENSIONS or file.content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(status_code=400, detail="Only video files are allowed")

    stored_filename = f"{uuid.uuid4()}{extension}"
    input_key = f"uploads/{stored_filename}"

    upload_input(input_key, file.file)

    try:
        video_id, job_id = create_video_and_job(
            file.filename,
            stored_filename,
            input_key,
            file.content_type,
            file.size,
        )
    except psycopg.Error as error:
        try:
            delete_object(input_key)
        except (BotoCoreError, ClientError):
            logger.exception("Could not delete orphaned S3 object: %s", input_key)        
        raise HTTPException(
            status_code=500,
            detail="Could not create video job"
        ) from error

    send_message(job_id)

    return {
        "video_id": video_id,
        "job_id": job_id,
        "filename": file.filename,
        "content-type": file.content_type,
        "size": file.size,
        "input_key": input_key
    }

@app.get("/jobs/{job_id}")
def get_jobs(job_id: int):
    job = get_job(job_id)

    if job is None:
        raise HTTPException(status_code=404, detail="Job not found")

    return job