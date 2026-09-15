import json

from subprocess import CalledProcessError

import worker


def test_process_message_completes_job_and_deletes_message(monkeypatch, tmp_path):
    completed_jobs = []
    deleted_receipts = []

    message = {
        "Body": json.dumps({"job_id": 123}),
        "ReceiptHandle": "receipt-123",
    }

    monkeypatch.setattr(worker, "mark_job_processing", lambda job_id: True)

    monkeypatch.setattr(
        worker,
        "get_video",
        lambda job_id: {
            "input_key": "uploads/test.mp4",
        },
    )

    monkeypatch.setattr(worker, "extend_message_visibility", lambda *args: None)
    monkeypatch.setattr(worker, "download_input", lambda *args: None)
    monkeypatch.setattr(worker, "transcode_to_720", lambda *args: None)
    monkeypatch.setattr(worker, "upload_output", lambda *args: None)

    monkeypatch.setattr(
        worker,
        "mark_job_completed",
        lambda job_id, output_key: completed_jobs.append((job_id, output_key)),
    )

    monkeypatch.setattr(
        worker,
        "delete_message",
        lambda receipt_handle: deleted_receipts.append(receipt_handle),
    )

    monkeypatch.setattr(worker, "INPUT_DIR", tmp_path / "inputs")
    monkeypatch.setattr(worker, "OUTPUT_DIR", tmp_path / "outputs")

    worker.process_message(message)

    assert completed_jobs == [
        (123, "outputs/123/720.mp4")
    ]

    assert deleted_receipts == [
        "receipt-123"
    ]


def test_process_message_marks_job_failed_when_transcode_fails(monkeypatch, tmp_path):
    failed_jobs = []
    deleted_receipts = []

    message = {
        "Body": json.dumps({"job_id": 123}),
        "ReceiptHandle": "receipt-123",
    }

    monkeypatch.setattr(worker, "mark_job_processing", lambda job_id: True)

    monkeypatch.setattr(
        worker,
        "get_video",
        lambda job_id: {
            "input_key": "uploads/test.mp4",
        },
    )

    monkeypatch.setattr(worker, "extend_message_visibility", lambda *args: None)
    monkeypatch.setattr(worker, "download_input", lambda *args: None)

    def fake_transcode(*args):
        raise CalledProcessError(
            returncode=1,
            cmd=["ffmpeg"],
            stderr="ffmpeg failed",
        )

    monkeypatch.setattr(worker, "transcode_to_720", fake_transcode)
    monkeypatch.setattr(worker, "upload_output", lambda *args: None)

    monkeypatch.setattr(
        worker,
        "mark_job_failed",
        lambda job_id, error: failed_jobs.append((job_id, error)),
    )

    monkeypatch.setattr(
        worker,
        "delete_message",
        lambda receipt_handle: deleted_receipts.append(receipt_handle),
    )

    monkeypatch.setattr(worker, "INPUT_DIR", tmp_path / "inputs")
    monkeypatch.setattr(worker, "OUTPUT_DIR", tmp_path / "outputs")

    worker.process_message(message)

    assert failed_jobs == [
        (123, "ffmpeg failed")
    ]

    assert deleted_receipts == []


def test_completed_job_message_is_deleted_without_reprocessing(monkeypatch):
    deleted_receipts = []
    transcoded = []

    message = {
        "Body": json.dumps({"job_id": 123}),
        "ReceiptHandle": "receipt-123",
    }

    monkeypatch.setattr(worker, "mark_job_processing", lambda job_id: False)

    monkeypatch.setattr(
        worker,
        "get_job",
        lambda job_id: {
            "id": job_id,
            "status": "completed",
        },
    )

    monkeypatch.setattr(
        worker,
        "delete_message",
        lambda receipt_handle: deleted_receipts.append(receipt_handle),
    )

    monkeypatch.setattr(
        worker,
        "transcode_to_720",
        lambda *args: transcoded.append(True),
    )

    worker.process_message(message)

    assert deleted_receipts == ["receipt-123"]
    assert transcoded == []


def test_missing_video_marks_job_failed(monkeypatch):
    failed_jobs = []
    transcoded = []
    deleted_receipts = []

    message = {
        "Body": json.dumps({"job_id": 123}),
        "ReceiptHandle": "receipt-123",
    }

    monkeypatch.setattr(worker, "mark_job_processing", lambda job_id: True)
    monkeypatch.setattr(worker, "extend_message_visibility", lambda *args: None)
    monkeypatch.setattr(worker, "get_video", lambda job_id: None)

    monkeypatch.setattr(
        worker,
        "mark_job_failed",
        lambda job_id, error: failed_jobs.append((job_id, error)),
    )

    monkeypatch.setattr(
        worker,
        "transcode_to_720",
        lambda *args: transcoded.append(True),
    )

    monkeypatch.setattr(
        worker,
        "delete_message",
        lambda receipt_handle: deleted_receipts.append(receipt_handle),
    )

    worker.process_message(message)

    assert failed_jobs == [(123, "No video found")]
    assert transcoded == []
    assert deleted_receipts == []