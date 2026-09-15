import json
from pathlib import Path
from subprocess import CalledProcessError
from threading import Event, Thread

import psycopg
from boto3.exceptions import S3UploadFailedError
from botocore.exceptions import BotoCoreError, ClientError

from job_queue import (
    delete_message,
    extend_message_visibility,
    receive_message,
)
from jobs import (
    get_job,
    get_video,
    mark_job_completed,
    mark_job_failed,
    mark_job_processing,
    update_job_heartbeat,
)
from storage import download_input, upload_output
from transcoder import transcode_to_720

HEARTBEAT_INTERVAL = 30
VISIBILITY_EXTENSION = 180

INPUT_DIR = Path("temp_inputs")
OUTPUT_DIR = Path("temp_outputs")


def heartbeat_loop(job_id: int, receipt_handle: str, stop_event: Event) -> None:
    while not stop_event.wait(HEARTBEAT_INTERVAL):
        try:
            update_job_heartbeat(job_id)
        except psycopg.Error as error:
            print(f"Database heartbeat failed for job {job_id}: {error}")

        try:
            extend_message_visibility(receipt_handle, VISIBILITY_EXTENSION)
        except (BotoCoreError, ClientError) as error:
            print(f"SQS heartbeat failed for job {job_id}: {error}")


def process_message(message: dict) -> None:
    payload = json.loads(message["Body"])
    job_id = payload["job_id"]
    receipt_handle = message["ReceiptHandle"]

    if not mark_job_processing(job_id):
        job = get_job(job_id)

        if job is not None and job["status"] == "completed":
            delete_message(receipt_handle)

        return

    try:
        extend_message_visibility(receipt_handle, VISIBILITY_EXTENSION)
    except (BotoCoreError, ClientError) as error:
        print(f"Initial visibility extension failed for job {job_id}: {error}")

    video = get_video(job_id)
    if video is None:
        mark_job_failed(job_id, "No video found")
        print(f"Job {job_id} failed: no video found")
        return

    stop_event = Event()

    heartbeat_thread = Thread(
        target=heartbeat_loop,
        args=(job_id, receipt_handle, stop_event),
        daemon=True,
    )

    heartbeat_thread.start()

    input_key = video["input_key"]
    video_path = INPUT_DIR / f"{job_id}_{Path(input_key).name}"

    output_path = OUTPUT_DIR / f"{job_id}/720p.mp4"
    output_key = f"outputs/{job_id}/720.mp4"

    print(f"Processing job: {job_id}")

    try:
        download_input(input_key, video_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)

        transcode_to_720(video_path, output_path)
        upload_output(output_key, output_path)
    except CalledProcessError as error:
        error_message = error.stderr
        mark_job_failed(job_id, error_message)

        print(f"Job {job_id} failed: {error_message}")

        return
    except (BotoCoreError, ClientError, S3UploadFailedError) as error:
        error_message = f"S3 operation failed: {error}"
        mark_job_failed(job_id, error_message)

        print(f"Job {job_id} failed: {error_message}")

    except OSError as error:
        error_message = f"Local system operation failed: {error}"
        mark_job_failed(job_id, error_message)

        print(f"Job {job_id} failed: {error_message}")

    else:
        mark_job_completed(job_id, output_key)
        delete_message(receipt_handle)

        print(f"Finished job {job_id}")

    finally:
        stop_event.set()
        heartbeat_thread.join(timeout=5)

        video_path.unlink(missing_ok=True)
        output_path.unlink(missing_ok=True)


def run_worker() -> None:
    INPUT_DIR.mkdir(exist_ok=True)
    OUTPUT_DIR.mkdir(exist_ok=True)

    print("Worker is waiting for job...")

    while True:
        message = receive_message()

        if message is None:
            continue

        process_message(message)


if __name__ == "__main__":
    run_worker()
