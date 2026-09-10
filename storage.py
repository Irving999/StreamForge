import os
import boto3
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()

bucket_name = os.getenv("S3_BUCKET")
s3 = boto3.client("s3", region_name=os.getenv("AWS_REGION"))

def upload_input(key: str, file_obj) -> None:
    s3.upload_fileobj(file_obj, bucket_name, key)

def download_input(key: str, local_path: str | Path) -> None:
    s3.download_file(bucket_name, key, str(local_path))

def upload_output(key: str, local_path: str | Path) -> None:
    s3.upload_file(str(local_path), bucket_name, key)