import redis
import subprocess
from pathlib import Path
from database import get_db_connection

OUTPUT_DIR = Path("outputs")
OUTPUT_DIR.mkdir(exist_ok=True)

client = redis.Redis(
    host="localhost",
    port=6379,
    db=0,
    decode_responses=True,
    socket_timeout=None,
)

print("Worker is waiting for job...")

while True:
    _, job_id = client.blpop("processing_queue")

    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute(
        """
        UPDATE jobs
        SET status = 'processing',
            started_at = NOW()
        WHERE id = %s
        """,
        (job_id,),
    )

    conn.commit()

    cur.execute(
        """
        SELECT
            jobs.id,
            jobs.video_id,
            videos.stored_path,
            videos.original_filename
        FROM jobs
        JOIN videos ON jobs.video_id = videos.id
        WHERE jobs.id = %s
        """,
        (job_id,),
    )

    video = cur.fetchone()

    if video is None:
        cur.execute(
            """
            UPDATE jobs
            SET status = 'failed',
                error = %s
            WHERE id = %s
            """,
            ("No video found for job", job_id),
        )
        
        conn.commit()
        cur.close()
        conn.close()

        print(f"Job {job_id} failed: no video found")
        continue

    video_path = video["stored_path"]

    cur.close()
    conn.close()

    print(f"Processing job: {job_id}")
    print(f"Original file {video['original_filename']}")
    print(f"Input path: {video_path}")

    output_path = OUTPUT_DIR / f"{job_id}_720p.mp4"

    try:
        subprocess.run(
            [
                "ffmpeg",
                "-i", video_path,
                "-vf", "scale=-2:720",
                "-c:v", "libx264",
                "-c:a", "aac",
                str(output_path)
            ],
            check=True,
            capture_output=True,
            text=True
        )
    except subprocess.CalledProcessError as error:
        conn = get_db_connection()
        cur = conn.cursor()

        error_message = error.stderr

        cur.execute(
            """
            UPDATE jobs
            SET status = 'failed',
                error = %s
            WHERE id = %s
            """,
            (error_message, job_id,),
        )

        conn.commit()
        cur.close()
        conn.close()

        print(f"Job {job_id} failed: {error_message}")
        continue

    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute(
        """
        UPDATE jobs
        SET status = 'completed',
            output_path = %s,
            completed_at = NOW()
        WHERE id = %s
        """,
        (str(output_path), job_id,),
    )

    conn.commit()
    cur.close()
    conn.close()

    print(f"Finished job {job_id}")
    print(f"Output: {output_path}")