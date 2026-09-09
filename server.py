import shutil
import uuid
from pathlib import Path
from job_queue import enqueue_job
from jobs import get_job, create_video_and_job
from fastapi import FastAPI, UploadFile, File, HTTPException

app = FastAPI()
UPLOAD_DIR = Path("uploads")
UPLOAD_DIR.mkdir(exist_ok=True)
    
@app.post("/videos/")
async def upload_video(file: UploadFile = File(...)):
    extension = Path(file.filename).suffix
    safe_filename = f"{uuid.uuid4()}{extension}"
    file_path = UPLOAD_DIR / safe_filename

    with file_path.open("wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    video_id, job_id = create_video_and_job(
        file.filename,
        safe_filename,
        str(file_path),
        file.content_type,
        file.size,
    )

    enqueue_job(job_id)

    return {
        "video_id": video_id,
        "job_id": job_id,
        "filename": file.filename,
        "content-type": file.content_type,
        "size": file.size,
        "saved_to": str(file_path)
    }

@app.get("/jobs/{job_id}")
def get_jobs(job_id: int):
    job = get_job(job_id)

    if job is None:
        raise HTTPException(status_code=404, detail="Job not found")

    return job