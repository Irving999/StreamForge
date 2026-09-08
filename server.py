from fastapi import FastAPI, UploadFile, File

app = FastAPI()
    
@app.post("/videos/")
async def upload_video(file: UploadFile = File(...)):
    return {
        "filename": file.filename,
        "content-type": file.content_type,
        "size": file.size
    }