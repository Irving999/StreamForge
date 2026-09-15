from fastapi.testclient import TestClient

from server import app

import psycopg


client = TestClient(app)


def test_get_existing_job(test_job):
    _, job_id = test_job

    response = client.get(f"/jobs/{job_id}")

    assert response.status_code == 200

    data = response.json()

    assert data["id"] == job_id
    assert data["status"] == "queued"

def test_get_missing_job_returns_404():
    response = client.get("/jobs/999999999")

    assert response.status_code == 404
    assert response.json() == {
        "detail": "Job not found"
    }

def test_upload_rejects_non_video_file():
    response = client.post(
        "/videos/",
        files={
            "file": ("notes.txt", b"hello world", "text/plain")
        },
    )

    assert response.status_code == 400
    assert response.json() == {
        "detail": "Only video files are allowed"
    }

def test_upload_valid_video(monkeypatch):
    uploaded_keys = []
    queued_jobs = []

    def fake_upload_input(input_key, file):
        uploaded_keys.append(input_key)

    def fake_create_video_and_job(*args, **kwargs):
        return 10, 20

    def fake_send_message(job_id):
        queued_jobs.append(job_id)

    monkeypatch.setattr("server.upload_input", fake_upload_input)
    monkeypatch.setattr(
        "server.create_video_and_job",
        fake_create_video_and_job,
    )
    monkeypatch.setattr("server.send_message", fake_send_message)

    response = client.post(
        "/videos/",
        files={
            "file": ("test.mp4", b"fake video data", "video/mp4")
        },
    )

    assert response.status_code == 200

    data = response.json()

    assert data["filename"] == "test.mp4"
    assert data["video_id"] == 10
    assert data["job_id"] == 20
    assert data["input_key"] == uploaded_keys[0]
    assert queued_jobs == [20]

def test_upload_deletes_s3_object_if_database_fails(monkeypatch):
    uploaded_keys = []
    deleted_keys = []
    queued_jobs = []

    def fake_upload_input(input_key, file):
        uploaded_keys.append(input_key)

    def fake_create_video_and_job(*args, **kwargs):
        raise psycopg.OperationalError("database unavailable")

    def fake_delete_object(input_key):
        deleted_keys.append(input_key)

    def fake_send_message(job_id):
        queued_jobs.append(job_id)

    monkeypatch.setattr("server.upload_input", fake_upload_input)
    monkeypatch.setattr("server.create_video_and_job", fake_create_video_and_job)
    monkeypatch.setattr("server.delete_object", fake_delete_object)
    monkeypatch.setattr("server.send_message", fake_send_message)

    response = client.post(
        "/videos/",
        files={
            "file": ("test.mp4", b"fake video data", "video/mp4")
        },
    )

    assert response.status_code == 500
    assert response.json() == {
        "detail": "Could not create video job"
    }

    assert len(uploaded_keys) == 1
    assert deleted_keys == uploaded_keys
    assert queued_jobs == []