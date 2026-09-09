import shutil
import uuid
from pathlib import Path
from database import get_db_connection
from job_queue import enqueue_job
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

    conn = get_db_connection()

    cur = conn.cursor()

    cur.execute(
        """
        INSERT INTO videos (
            original_filename,
            stored_filename,
            stored_path,
            content_type,
            size
        )
        VALUES (%s, %s, %s, %s, %s)
        RETURNING id;
        """,
        (
            file.filename,
            safe_filename,
            str(file_path),
            file.content_type,
            file.size,
        )
    )

    video_id = cur.fetchone()["id"]

    cur.execute(
        """
        INSERT INTO jobs (video_id)
        VALUES (%s)
        RETURNING id;
        """,
        (video_id,)
    )

    job_id = cur.fetchone()["id"]

    conn.commit()

    enqueue_job(job_id)

    cur.close()
    conn.close()

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
    conn = get_db_connection()

    cur = conn.cursor()

    cur.execute(
        """
        SELECT * FROM jobs
        WHERE id = %s
        """,
        (job_id,),
    )

    job = cur.fetchone()

    if job is None:
        cur.close()
        conn.close()
        raise HTTPException(status_code=404, detail="Job not found")

    cur.close()
    conn.close()

    return job