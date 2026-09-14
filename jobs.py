from database import get_db_connection

def get_job(job_id: int) -> dict | None:
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

    cur.close()
    conn.close()

    return job

def create_video_and_job(
        original_filename: str,
        stored_filename: str,
        input_key: str,
        content_type: str | None,
        size: int | None,
) -> tuple[int, int]:
    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute(
        """
        INSERT INTO videos (
            original_filename,
            stored_filename,
            input_key,
            content_type,
            size
        )
        VALUES (%s, %s, %s, %s, %s)
        RETURNING id;
        """,
        (
            original_filename,
            stored_filename,
            input_key,
            content_type,
            size,
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

    cur.close()
    conn.close()

    return video_id, job_id

def get_video(job_id: int) -> dict | None:
    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute(
        """
        SELECT
            jobs.id AS job_id,
            jobs.video_id,
            videos.input_key,
            videos.original_filename
        FROM jobs
        JOIN videos ON jobs.video_id = videos.id
        WHERE jobs.id = %s
        """,
        (job_id,),
    )

    video = cur.fetchone()

    cur.close()
    conn.close()

    return video

def mark_job_processing(job_id: int) -> bool:
    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute(
        """
        UPDATE jobs
        SET status = 'processing',
            started_at = NOW(),
            heartbeat_at = NOW(),
            error = NULL
        WHERE id = %s
            AND (
                status IN ('queued', 'failed')
                OR (
                    status = 'processing'
                    AND heartbeat_at < NOW() - INTERVAL '2 minutes'
                )
            )
        RETURNING id
        """,
        (job_id,),
    )

    claimed = cur.fetchone() is not None

    conn.commit()
    cur.close()
    conn.close()

    return claimed

def mark_job_completed(job_id: int, output_key: str) -> None:
    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute(
        """
        UPDATE jobs
        SET status = 'completed',
            output_key = %s,
            completed_at = NOW()
        WHERE id = %s
        """,
        (output_key, job_id,),
    )

    conn.commit()

    cur.close()
    conn.close()

def mark_job_failed(job_id: int, error: str) -> None:
    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute(
        """
        UPDATE jobs
        SET status = 'failed',
            error = %s
        WHERE id = %s
        """,
        (error, job_id),
    )

    conn.commit()

    cur.close()
    conn.close()

def update_job_heartbeat(job_id: int) -> None:
    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute(
        """
        UPDATE jobs
        SET heartbeat_at = NOW()
        WHERE id = %s
            AND status = 'processing';
        """,
        (job_id,),
    )

    conn.commit()
    cur.close()
    conn.close()