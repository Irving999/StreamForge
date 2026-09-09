from database import get_db_connection

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