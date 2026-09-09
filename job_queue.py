import redis

client = redis.Redis(
    host="localhost",
    port=6379,
    db=0,
    decode_responses=True,
)

def enqueue_job(job_id: int):
    client.rpush("processing_queue", str(job_id))