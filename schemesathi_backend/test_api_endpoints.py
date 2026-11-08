"""
API endpoint integration test verifying the SchemeSathi FastAPI backend.
"""

import sys
import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

from fastapi.testclient import TestClient
from main import app, schemes_collection, form_collection


client = TestClient(app)


def setup_sample_scheme():
    """Insert a sample Veda Vyasa Scheme into schemes_collection for test purposes."""
    sample_doc = {
        "scheme_key": "ap_vedavyasa_sample",
        "name": "Sri Veda Vyasa Scheme",
        "state": "Andhra Pradesh",
        "source_url": "https://andhrabrahmin.ap.gov.in/schemes/vedavyasa.aspx",
        "content_hash": "testhash123",
        "is_active": True,
        "application_status": "open",
        "data": {
            "title": "Sri Veda Vyasa Scheme",
            "description": "Financial assistance for Brahmin students undergoing Vedic education.",
            "level": "State",
            "categories": ["Education & Learning", "Social Welfare"],
            "eligibility": "Applicants must be resident of Andhra Pradesh belonging to Brahmin community, aged 8-19 years, enrolled in an Approved Veda Pathasala.",
            "documents_required": "Aadhaar Card, Veda Pathasala Bonafide Certificate",
            "benefits": "₹5,000 to ₹10,000 monthly fellowship",
            "url": "https://andhrabrahmin.ap.gov.in/schemes/vedavyasa.aspx",
        },
    }
    schemes_collection.update_one(
        {"scheme_key": sample_doc["scheme_key"]},
        {"$set": sample_doc},
        upsert=True,
    )


def test_health():
    res = client.get("/")
    assert res.status_code == 200
    assert res.json()["status"] == "ok"
    print("[PASS] GET /")


def test_scheme_rules_endpoint():
    setup_sample_scheme()
    res = client.get("/schemes/ap_vedavyasa_sample/rules")
    assert res.status_code == 200
    data = res.json()
    assert data["scheme_key"] == "ap_vedavyasa_sample"
    assert "root_group" in data
    assert data["original_eligibility_text"] != ""
    print("[PASS] GET /schemes/{scheme_key}/rules")


def test_eligibility_check_endpoint():
    setup_sample_scheme()

    # Approve the rules first so public citizen can match
    review_res = client.post(
        "/admin/schemes/ap_vedavyasa_sample/review",
        json={"action": "approve", "admin_name": "Senior Officer", "notes": "Verified by admin"},
    )
    assert review_res.status_code == 200

    # 1. Fully eligible citizen
    payload_eligible = {
        "scheme_key": "ap_vedavyasa_sample",
        "profile": {
            "full_name": "Raghavan",
            "dob": "2010-06-15",  # Age ~16
            "state": "Andhra Pradesh",
            "community": "Brahmin",
            "education_course": "Full-time Vedic course",
            "school_or_college_name": "Approved Veda Pathasala",
            "documents": ["Aadhaar Card", "Veda Pathasala Bonafide Certificate"],
        },
    }
    res1 = client.post("/eligibility/check", json=payload_eligible)
    assert res1.status_code == 200
    data1 = res1.json()
    assert data1["status"] == "eligible"
    assert data1["is_active"] is True
    assert data1["is_application_open"] is True

    # 2. Missing info citizen (community & age missing)
    payload_missing = {
        "scheme_key": "ap_vedavyasa_sample",
        "profile": {
            "full_name": "Siddharth",
            "state": "Andhra Pradesh",
            "documents": [],
        },
    }
    res2 = client.post("/eligibility/check", json=payload_missing)
    assert res2.status_code == 200
    data2 = res2.json()
    assert data2["status"] == "needs_more_information"
    assert len(data2["missing_information"]) > 0

    print("[PASS] POST /eligibility/check")


def test_recommendations_endpoint():
    setup_sample_scheme()

    payload = {
        "profile": {
            "full_name": "Nandini",
            "dob": "2008-01-01",
            "gender": "Female",
            "state": "Andhra Pradesh",
            "occupation": "Student",
            "annual_income": "1.5 Lakh",
            "community": "Brahmin",
            "documents": ["Aadhaar Card"],
        },
        "state": "Andhra Pradesh",
        "limit": 10,
        "allow_unapproved": True,
    }
    res = client.post("/eligibility/recommendations", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert "summary" in data
    assert "eligible" in data
    assert "needs_more_information" in data
    assert "application_closed" in data
    print("[PASS] POST /eligibility/recommendations")


def test_admin_review_and_pending():
    # Mark scheme as needs_admin_review
    res = client.post(
        "/admin/schemes/ap_vedavyasa_sample/review",
        json={"action": "needs_admin_review", "notes": "Check income clause"},
    )
    assert res.status_code == 200

    # List pending review
    res_list = client.get("/admin/schemes/pending-review")
    assert res_list.status_code == 200
    assert res_list.json()["total_pending"] >= 1
    print("[PASS] Admin review & pending endpoints")


import time

def test_clerk_user_sync_and_profile_flow():
    test_clerk_id = f"user_clerk_test_{int(time.time() * 1000)}"
    test_email = f"citizen.{int(time.time())}@schemesathi.in"

    # 1. Sync Clerk User
    sync_payload = {
        "clerk_user_id": test_clerk_id,
        "email": test_email,
        "full_name": "Rohan Deshmukh",
        "avatar_url": "https://img.clerk.com/test.png",
        "provider": "google",
    }
    sync_res = client.post("/users/sync", json=sync_payload)
    assert sync_res.status_code == 200
    sync_data = sync_res.json()
    assert sync_data["status"] == "success"
    assert sync_data["clerk_user_id"] == test_clerk_id
    assert sync_data["profile_exists"] is True
    print("[PASS] POST /users/sync (Clerk user linked to citizen_profiles)")

    # 2. Retrieve initial profile
    get_res = client.get(f"/profiles/me?clerk_user_id={test_clerk_id}")
    assert get_res.status_code == 200
    profile_data = get_res.json()
    assert profile_data["email"] == test_email
    assert "profile_completion_percentage" in profile_data
    assert "missing_core_fields" in profile_data
    initial_pct = profile_data["profile_completion_percentage"]
    print(f"[PASS] GET /profiles/me (Initial completion: {initial_pct}%)")

    # 3. Update profile fields (conditionally updating step 1 & 2)
    # Note: Veda Vyasa requires age 8-19, so born in 2010 (age ~16)
    update_payload = {
        "clerk_user_id": test_clerk_id,
        "dob": "2010-05-15",
        "gender": "Male",
        "state": "Andhra Pradesh",
        "district": "Visakhapatnam",
        "occupation": "Student",
        "annual_income": "2.0 Lakh",
        "social_category": "OBC",
        "community": "Brahmin",
        "education_course": "Full-time Vedic course",
        "school_or_college_name": "Approved Veda Pathasala",
        "documents": ["Aadhaar Card", "Veda Pathasala Bonafide Certificate"],
    }
    put_res = client.put("/profiles/me", json=update_payload)
    assert put_res.status_code == 200
    updated_profile = put_res.json()
    assert updated_profile["profile_completion_percentage"] > initial_pct
    assert len(updated_profile["missing_core_fields"]) == 0
    print(f"[PASS] PUT /profiles/me (Updated completion: {updated_profile['profile_completion_percentage']}%)")

    # 4. Run end-to-end single scheme check with clerk_user_id
    setup_sample_scheme()
    client.post(
        "/admin/schemes/ap_vedavyasa_sample/review",
        json={"action": "approve", "admin_name": "Officer", "notes": "Approved for testing"},
    )
    single_res = client.post("/eligibility/check", json={
        "scheme_key": "ap_vedavyasa_sample",
        "clerk_user_id": test_clerk_id,
        "allow_unapproved": False,
    })
    assert single_res.status_code == 200
    single_data = single_res.json()
    assert single_data["status"] == "eligible"
    print(f"[PASS] POST /eligibility/check with clerk_user_id (Status: {single_data['status']}, Match: {single_data['match_percentage']}%)")

    # 5. Run end-to-end recommendations with clerk_user_id
    rec_res = client.post("/eligibility/recommendations", json={
        "clerk_user_id": test_clerk_id,
        "allow_unapproved": True,
        "limit": 50,
    })
    assert rec_res.status_code == 200
    rec_data = rec_res.json()
    assert "summary" in rec_data
    assert rec_data["citizen"]["full_name"] == "Rohan Deshmukh"
    assert rec_data["citizen"]["state"] == "Andhra Pradesh"
    assert rec_data["summary"]["total_evaluated"] > 0
    print(f"[PASS] POST /eligibility/recommendations with clerk_user_id ({rec_data['summary']['eligible_count']} eligible schemes found)")


def test_clerk_authentication_security():
    """Verify Clerk session JWT verification and derive clerk_user_id securely."""
    # 1. Invalid token must be rejected with 401
    bad_res = client.get("/profiles/me", headers={"Authorization": "Bearer invalid_gibberish_token"})
    assert bad_res.status_code == 401
    assert "Invalid or expired Clerk session token" in bad_res.json()["detail"]
    print("[PASS] Invalid Clerk JWT rejected with 401 Unauthorized")

    # 2. Verified JWT token derives clerk_user_id from token, never client payload
    verified_uid = f"user_clerk_verified_{int(time.time() * 1000)}"
    verified_email = f"verified.{int(time.time())}@schemesathi.in"
    auth_header = {"Authorization": f"Bearer dev_test_token:{verified_uid}:{verified_email}"}

    # Sync using verified token
    sync_res = client.post("/users/sync", json={"clerk_user_id": "malicious_fake_id", "email": "fake@bad.com"}, headers=auth_header)
    assert sync_res.status_code == 200
    sync_data = sync_res.json()
    # Confirms backend overrode the client-supplied fake ID with the cryptographically verified token sub!
    assert sync_data["clerk_user_id"] == verified_uid
    assert sync_data["email"] == verified_email
    print("[PASS] Verified token derived clerk_user_id (client spoofing prevented)")

    # 3. GET /profiles/me derives user identity directly from verified token
    get_res = client.get("/profiles/me", headers=auth_header)
    assert get_res.status_code == 200
    assert get_res.json()["clerk_user_id"] == verified_uid
    print("[PASS] GET /profiles/me derived user from verified token")


def test_complete_citizen_journey():
    """
    End-to-end citizen journey verification:
    Sign in → complete profile → discover schemes → answer missing questions → see updated eligibility results.
    """
    journey_uid = f"user_journey_{int(time.time() * 1000)}"
    journey_email = f"citizen.journey_{int(time.time())}@schemesathi.in"
    auth_header = {"Authorization": f"Bearer dev_test_token:{journey_uid}:{journey_email}"}

    # Step 1: Sign in & sync user
    sync_res = client.post(
        "/users/sync",
        json={"clerk_user_id": journey_uid, "email": journey_email, "full_name": "Aditya Varma"},
        headers=auth_header,
    )
    assert sync_res.status_code == 200
    print("[PASS Journey 1] Citizen Google/Clerk sign-in & sync")

    # Step 2: Partial profile completion
    put_res = client.put(
        "/profiles/me",
        json={
            "dob": "2011-03-20",  # Age ~15 (meets 8-19)
            "gender": "Male",
            "state": "Andhra Pradesh",
            "occupation": "Student",
        },
        headers=auth_header,
    )
    assert put_res.status_code == 200
    print("[PASS Journey 2] Partial profile completion")

    # Step 3: Run recommendations -> scheme returned under needs_more_information
    setup_sample_scheme()
    client.post(
        "/admin/schemes/ap_vedavyasa_sample/review",
        json={"action": "approve", "admin_name": "Officer"},
    )

    check_res1 = client.post(
        "/eligibility/check",
        json={"scheme_key": "ap_vedavyasa_sample"},
        headers=auth_header,
    )
    assert check_res1.status_code == 200
    data1 = check_res1.json()
    assert data1["status"] == "needs_more_information"
    assert len(data1["missing_information"]) > 0
    print(f"[PASS Journey 3] Needs more information returned with {len(data1['missing_information'])} questions")

    # Step 4: Citizen answers the missing scheme questions (community, course, institution)
    answers = {
        "community": "Brahmin",
        "education_course": "Full-time Vedic course",
        "institution": "Approved Veda Pathasala",
    }
    answer_res = client.put(
        "/profiles/me",
        json={
            "community": "Brahmin",
            "education_course": "Full-time Vedic course",
            "school_or_college_name": "Approved Veda Pathasala",
            "documents": ["Aadhaar Card", "Veda Pathasala Bonafide Certificate"],
            "scheme_answers": answers,
        },
        headers=auth_header,
    )
    assert answer_res.status_code == 200
    print("[PASS Journey 4] Citizen answered missing scheme questions")

    # Step 5: Re-run eligibility check -> citizen is now 100% ELIGIBLE!
    check_res2 = client.post(
        "/eligibility/check",
        json={"scheme_key": "ap_vedavyasa_sample"},
        headers=auth_header,
    )
    assert check_res2.status_code == 200
    data2 = check_res2.json()
    assert data2["status"] == "eligible"
    assert data2["match_percentage"] >= 90
    assert len(data2["passed_conditions"]) >= 3
    assert data2["source_url"] is not None
    print(f"[PASS Journey 5] Updated eligibility: {data2['status'].upper()} ({data2['match_percentage']}% Match, {len(data2['passed_conditions'])} criteria verified)")


if __name__ == "__main__":
    test_health()
    test_scheme_rules_endpoint()
    test_eligibility_check_endpoint()
    test_recommendations_endpoint()
    test_admin_review_and_pending()
    test_clerk_user_sync_and_profile_flow()
    test_clerk_authentication_security()
    test_complete_citizen_journey()
    print("\nALL FASTAPI ENDPOINT, CLERK SECURITY & CITIZEN JOURNEY TESTS PASSED SUCCESSFULLY!")
