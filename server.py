from dotenv import load_dotenv
import psycopg
import os
import shutil
import uuid
from pathlib import Path
from fastapi import FastAPI, UploadFile, File

app = FastAPI()
UPLOAD_DIR = Path("uploads")
UPLOAD_DIR.mkdir(exist_ok=True)

load_dotenv()
    
@app.post("/videos/")
async def upload_video(file: UploadFile = File(...)):
    extension = Path(file.filename).suffix
    safe_filename = f"{uuid.uuid4()}{extension}"
    file_path = UPLOAD_DIR / safe_filename

    with file_path.open("wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    conn = psycopg.connect(
        host=os.getenv("DB_HOST"),
        port=os.getenv("DB_PORT"),
        dbname=os.getenv("DB_NAME"),
        user=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD"),
    )

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

    conn.commit()

    cur.close()
    conn.close()

    return {
        "video_id": video_id,
        "filename": file.filename,
        "content-type": file.content_type,
        "size": file.size,
        "saved_to": str(file_path)
    }