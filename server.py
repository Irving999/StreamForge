import shutil
import uuid
from pathlib import Path
from database import get_db_connection
from fastapi import FastAPI, UploadFile, File

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

    video_id = cur.fetchone()[0]

    cur.execute(
        """
        INSERT INTO jobs (video_id)
        VALUES (%s)
        RETURNING id;
        """,
        (video_id,)
    )

    job_id = cur.fetchone()[0]

    conn.commit()

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