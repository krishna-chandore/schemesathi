import os
import json
import redis
from dotenv import load_dotenv

load_dotenv()

REDIS_URL = os.getenv("REDIS_URL")

if not REDIS_URL:
    raise RuntimeError("REDIS_URL not found in .env file")

redis_client = redis.from_url(
    REDIS_URL,
    decode_responses=True
)


def get_schemes(state):
    data = redis_client.get(f"schemes:{state}")
    return json.loads(data) if data else None


def save_schemes(state, schemes, ttl=86400):
    redis_client.setex(
        f"schemes:{state}",
        ttl,
        json.dumps(schemes, ensure_ascii=False)
    )