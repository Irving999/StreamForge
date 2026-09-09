import redis
from database import get_db_connection

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
        cur.close()
        conn.close()
        raise RuntimeError(f"No video found for job {job_id}")

    print(f"Processing job: {job_id}")
    print(f"Original file {video['original_filename']}")
    print(f"Input path: {video['stored_path']}")

    cur.close()
    conn.close()