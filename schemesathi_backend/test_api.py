"""
Quick test script for the form API (no Flutter needed).

1. Start the server in one terminal:
       uvicorn main:app --reload --port 8000
2. Run this in another terminal:
       python test_api.py
"""

import sys

import requests

BASE_URL = "http://127.0.0.1:8000"


def check_db_connection():
    """Check that MongoDB (from your .env) is reachable."""
    print("1) Testing MongoDB connection...")
    try:
        from form import client

        client.admin.command("ping")
        print("   OK - connected to MongoDB\n")
        return True
    except Exception as e:
        print(f"   FAILED - {e}\n")
        return False


def test_submit_valid():
    print("2) Submitting a valid form...")
    payload = {
        "name": "Krishna",
        "email": "krishna@example.com",
        "phone": "9876543210",
        "message": "Hello from the test script!",
    }
    r = requests.post(f"{BASE_URL}/submit", json=payload, timeout=10)
    print(f"   Status: {r.status_code}")
    print(f"   Response: {r.json()}\n")
    return r.status_code == 200


def test_submit_invalid():
    print("3) Submitting an invalid form (bad email, no name) - should be rejected...")
    payload = {"name": "", "email": "not-an-email"}
    r = requests.post(f"{BASE_URL}/submit", json=payload, timeout=10)
    print(f"   Status: {r.status_code} (expected 422)\n")
    return r.status_code == 422


def test_list():
    print("4) Fetching saved submissions...")
    r = requests.get(f"{BASE_URL}/submissions", params={"limit": 5}, timeout=10)
    print(f"   Status: {r.status_code}")
    for doc in r.json():
        print(f"   - {doc.get('name')} | {doc.get('email')} | {doc.get('created_at')}")
    print()
    return r.status_code == 200


if __name__ == "__main__":
    results = {"MongoDB connection": check_db_connection()}

    try:
        results["Valid submit"] = test_submit_valid()
        results["Invalid submit rejected"] = test_submit_invalid()
        results["List submissions"] = test_list()
    except requests.exceptions.ConnectionError:
        print("Could not reach the server. Is uvicorn running on port 8000?")
        sys.exit(1)

    print("=== Summary ===")
    for name, ok in results.items():
        print(f"{'PASS' if ok else 'FAIL'}  {name}")
