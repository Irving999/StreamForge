import os

import pytest
from database import get_db_connection
from jobs import create_video_and_job


@pytest.fixture(scope="session", autouse=True)
def require_test_database():
    is_test_database = (
        os.getenv("DB_HOST") in {"localhost", "127.0.0.1"}
        and os.getenv("DB_PORT") == "5433"
        and os.getenv("DB_NAME") == "streamforge_test"
    )

    if not is_test_database:
        pytest.exit("Refusing to run tests outside the local test database")


@pytest.fixture
def test_job():
    video_id, job_id = create_video_and_job(
        original_filename="test.mp4",
        stored_filename="test.mp4",
        input_key="uploads/test.mp4",
        content_type="video/mp4",
        size=123,
    )

    yield video_id, job_id

    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute("DELETE FROM jobs WHERE id = %s", (job_id,))
    cur.execute("DELETE FROM videos WHERE id = %s", (video_id,))

    conn.commit()
    cur.close()
    conn.close()
