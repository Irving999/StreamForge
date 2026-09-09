import redis

client = redis.Redis(
    host="localhost",
    port=6379,
    db=0,
    decode_responses=True,
    socket_timeout=None,
)

print("Worker is waiting for job...")

while True:
    _, job_id = client.blpop("processing_queue")
    print(f"Received job:{job_id}")