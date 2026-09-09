import redis
from database import get_db_connection

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
    
    print(f"Processing job:{job_id}")