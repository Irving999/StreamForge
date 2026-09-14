import json
from pathlib import Path
from transcoder import transcode_to_720
from subprocess import CalledProcessError
from boto3.exceptions import S3UploadFailedError
from storage import download_input, upload_output
from job_queue import receive_message, delete_message
from botocore.exceptions import BotoCoreError, ClientError
from jobs import (
    get_video,
    mark_job_processing,
    mark_job_completed,
    mark_job_failed
)


INPUT_DIR = Path("temp_inputs")
INPUT_DIR.mkdir(exist_ok=True)

OUTPUT_DIR = Path("temp_outputs")
OUTPUT_DIR.mkdir(exist_ok=True)

print("Worker is waiting for job...")

while True:
    message = receive_message()

    if message is None:
        continue

    payload = json.loads(message["Body"])
    job_id = payload["job_id"]
    receipt_handle = message["ReceiptHandle"]

    mark_job_processing(job_id)
    video = get_video(job_id)

    if video is None:
        mark_job_failed(job_id, "No video found")
        print(f"Job {job_id} failed: no video found")
        continue

    input_key = video["input_key"]
    video_path = INPUT_DIR / f"{job_id}_{Path(input_key).name}"

    print(f"Processing job: {job_id}")
    print(f"Original file {video['original_filename']}")

    output_path = OUTPUT_DIR / f"{job_id}/720p.mp4"
    output_key = f"outputs/{job_id}/720.mp4"

    try:
        download_input(input_key, video_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        transcode_to_720(video_path, output_path)
        upload_output(output_key, output_path)
    except CalledProcessError as error:
        error_message = error.stderr
        mark_job_failed(job_id, error_message)
        print(f"Job {job_id} failed: {error_message}")
        continue
    except (BotoCoreError, ClientError, S3UploadFailedError) as error:
        message = f"S3 operation failed: {error}"
        mark_job_failed(job_id, message)
        print(message)
    except OSError as error:
        message = f"Local system operation failed: {error}"
        mark_job_failed(job_id, message)
        print(message)
    else:
        mark_job_completed(job_id, output_key)
        delete_message(receipt_handle)
        print(f"Finished job {job_id}")
        print(f"Output key: {output_key}")
    finally:
        video_path.unlink(missing_ok=True)
        output_path.unlink(missing_ok=True)