from pathlib import Path
from subprocess import CalledProcessError

from jobs import (
    get_job_video,
    mark_job_processing,
    mark_job_completed,
    mark_job_failed
)
from job_queue import dequeue_job
from transcoder import transcode_to_720

OUTPUT_DIR = Path("outputs")
OUTPUT_DIR.mkdir(exist_ok=True)

print("Worker is waiting for job...")

while True:
    job_id = dequeue_job()
    mark_job_processing(job_id)
    video = get_job_video(job_id)

    if video is None:
        mark_job_failed(job_id, "No video found")
        print(f"Job {job_id} failed: no video found")
        continue

    video_path = video["stored_path"]

    print(f"Processing job: {job_id}")
    print(f"Original file {video['original_filename']}")
    print(f"Input path: {video_path}")

    output_path = OUTPUT_DIR / f"{job_id}_720p.mp4"

    try:
        transcode_to_720(video_path, output_path)
    except CalledProcessError as error:
        error_message = error.stderr
        mark_job_failed(job_id, error_message)
        print(f"Job {job_id} failed: {error_message}")
        continue

    mark_job_completed(job_id, str(output_path))

    print(f"Finished job {job_id}")
    print(f"Output: {output_path}")