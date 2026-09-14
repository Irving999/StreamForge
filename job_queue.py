import os
import json
import boto3
from dotenv import load_dotenv

load_dotenv()

queue_url = os.getenv("SQS_QUEUE_URL")
sqs = boto3.client("sqs", region_name=os.getenv("AWS_REGION"))

def send_message(job_id: int) -> None:
    sqs.send_message(
        QueueUrl=queue_url,
        MessageBody=json.dumps({"job_id": job_id})
    )

def receive_message() -> dict | None:
    response = sqs.receive_message(
        QueueUrl=queue_url,
        MaxNumberOfMessages=1,
        WaitTimeSeconds=20,
    )

    messages = response.get("Messages", [])

    if not messages:
        return None

    return messages[0]

def delete_message(receiptHandle: str) -> None:
    sqs.delete_message(
        QueueUrl=queue_url,
        ReceiptHandle=receiptHandle,
    )

def extend_message_visibility(
        receipt_handle: str,
        visibility_timeout: int
) -> None:
    sqs.change_message_visibility(
        QueueUrl=queue_url,
        ReceiptHandle=receipt_handle,
        VisibilityTimeout=visibility_timeout,
    )