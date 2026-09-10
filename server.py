import uuid
import psycopg
from pathlib import Path
from storage import upload_input
from job_queue import enqueue_job
from jobs import get_job, create_video_and_job
from fastapi import FastAPI, UploadFile, File, HTTPException

app = FastAPI()

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
        raise HTTPException(
            status_code=500,
            detail="Could not create video job"
        ) from error

    enqueue_job(job_id)

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