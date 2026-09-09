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
        stored_path: str,
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
            stored_path,
            content_type,
            size
        )
        VALUES (%s, %s, %s, %s, %s)
        RETURNING id;
        """,
        (
            original_filename,
            stored_filename,
            stored_path,
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

def get_job_video(job_id: int) -> dict | None:
    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute(
        """
        SELECT
            jobs.id AS job_id,
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

    cur.close()
    conn.close()

    return video

def mark_job_processing(job_id: int) -> None:
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

    cur.close()
    conn.close()

def mark_job_completed(job_id: int, output_path: str) -> None:
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
        (output_path, job_id,),
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