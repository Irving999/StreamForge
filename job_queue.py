import os
import redis
from dotenv import load_dotenv

load_dotenv()

client = redis.Redis(
    host=os.getenv("REDIS_HOST"),
    port=int(os.getenv("REDIS_PORT")),
    db=int(os.getenv("REDIS_DB")),
    decode_responses=True,
    socket_timeout=None,
)

def enqueue_job(job_id: int):
    client.rpush("processing_queue", str(job_id))

def dequeue_job() -> int:
    _, job_id = client.blpop("processing_queue")
    return int(job_id)