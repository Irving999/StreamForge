import shutil
import uuid
from pathlib import Path
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

    return {
        "filename": file.filename,
        "content-type": file.content_type,
        "size": file.size,
        "saved_to": str(file_path)
    }