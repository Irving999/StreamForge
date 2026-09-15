from database import get_db_connection
from jobs import get_job, mark_job_processing, mark_job_failed

def test_queued_job_can_be_claimed(test_job):
    _, job_id = test_job

    claimed = mark_job_processing(job_id)
    job = get_job(job_id)

    assert claimed is True
    assert job["status"] == "processing"

def test_completed_job_cannot_be_claimed(test_job):
    video_id, job_id = test_job

    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute(
        """
        UPDATE jobs
        SET status = 'completed'
        WHERE id = %s
        """,
        (job_id,),
    )

    conn.commit()
    cur.close()
    conn.close()

    claimed = mark_job_processing(job_id)

    assert claimed is False

def test_fresh_processing_job_cannot_be_claimed_again(test_job):
    _, job_id = test_job

    first_claim = mark_job_processing(job_id)
    second_claim = mark_job_processing(job_id)

    assert first_claim is True
    assert second_claim is False

def test_stale_processing_job_can_be_reclaimed(test_job):
    _, job_id = test_job

    first_claim = mark_job_processing(job_id)
    assert first_claim is True

    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute(
        """
        UPDATE jobs
        SET heartbeat_at = NOW() - INTERVAL '3 minutes'
        WHERE id = %s
        """,
        (job_id,),
    )

    conn.commit()
    cur.close()
    conn.close()

    second_claim = mark_job_processing(job_id)

    assert second_claim is True

def test_failed_job_can_be_retried_and_error_is_cleared(test_job):
    _, job_id = test_job

    mark_job_failed(job_id, "something broke")

    failed_job = get_job(job_id)

    assert failed_job["status"] == "failed"
    assert failed_job["error"] == "something broke"

    claimed = mark_job_processing(job_id)
    retried_job = get_job(job_id)

    assert claimed is True
    assert retried_job["status"] == "processing"
    assert retried_job["error"] is None
