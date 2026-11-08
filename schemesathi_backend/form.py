import os
from datetime import datetime, timezone
from typing import Optional

from dotenv import load_dotenv
from pydantic import BaseModel, Field
from pymongo import MongoClient

load_dotenv()

MONGO_URI = os.getenv("MONGO_URI", "mongodb://localhost:27017")
DB_NAME = os.getenv("DB_NAME", "flutter_app")
COLLECTION_NAME = os.getenv("COLLECTION_NAME", "form_submissions")

client = MongoClient(MONGO_URI, serverSelectionTimeoutMS=5000)
collection = client[DB_NAME][COLLECTION_NAME]


class FormData(BaseModel):
    """Fields from Citizen Profile Setup form & contact forms."""

    # Core Citizen Profile Setup fields (New Multi-step schema + legacy compatibility)
    full_name: Optional[str] = Field(default=None, max_length=150)
    dob: Optional[str] = Field(default=None, max_length=50)
    gender: Optional[str] = Field(default=None, max_length=50)
    marital_status: Optional[str] = Field(default=None, max_length=50)

    # Step 2: Residence Details
    state: Optional[str] = Field(default=None, max_length=100)
    district: Optional[str] = Field(default=None, max_length=100)
    tehsil: Optional[str] = Field(default=None, max_length=100)
    area_type: Optional[str] = Field(default=None, max_length=50) # rural / urban / peri_urban
    domicile_status: Optional[str] = Field(default=None, max_length=50) # yes / in_progress / no
    local_residence_outside: Optional[bool] = Field(default=False)
    family_id: Optional[str] = Field(default=None, max_length=50)

    # Step 3: Occupation & Study
    occupation: Optional[str] = Field(default=None, max_length=100)
    study_level: Optional[str] = Field(default=None, max_length=100)
    education_course: Optional[str] = Field(default=None, max_length=150)
    institution_type: Optional[str] = Field(default=None, max_length=100)
    school_or_college_name: Optional[str] = Field(default=None, max_length=200)

    # Step 4: Special Eligibility
    social_category: Optional[str] = Field(default=None, max_length=100)
    caste_certificate_status: Optional[str] = Field(default=None, max_length=100)
    pwd_status: Optional[str] = Field(default=None, max_length=100)
    minority_status: Optional[str] = Field(default=None, max_length=100)
    income_certificate_status: Optional[str] = Field(default=None, max_length=100)

    # Step 5: Documents
    documents: Optional[list[str]] = Field(default=[])

    # Legacy fields
    annual_income: Optional[str] = Field(default=None, max_length=100)
    tenth_board: Optional[str] = Field(default=None, max_length=100)
    tenth_marks: Optional[str] = Field(default=None, max_length=50)
    twelfth_board: Optional[str] = Field(default=None, max_length=100)
    twelfth_marks: Optional[str] = Field(default=None, max_length=50)
    twelfth_stream: Optional[str] = Field(default=None, max_length=100)
    language: Optional[str] = Field(default="EN", max_length=20)

    # Legacy / optional fields for backward compatibility
    name: Optional[str] = Field(default=None, max_length=100)
    email: Optional[str] = Field(default=None, max_length=200)
    clerk_user_id: Optional[str] = Field(default=None, max_length=150)
    phone: Optional[str] = Field(default=None, max_length=20)
    message: Optional[str] = Field(default=None, max_length=1000)


def save_form(data: FormData) -> dict:
    document = data.model_dump(exclude_none=True)

    if document.get("email"):
        document["email"] = document["email"].strip().lower()

    now = datetime.now(timezone.utc)
    document["updated_at"] = now
    display_name = data.full_name or data.name or "Citizen"

    # 1. Update citizen_profiles as single authoritative source of truth
    from user_profile_service import profiles_collection, calculate_profile_completion

    profile_filter = {}
    if document.get("clerk_user_id"):
        profile_filter["clerk_user_id"] = document["clerk_user_id"]
    elif document.get("email"):
        profile_filter["email"] = document["email"]

    profile_id = None
    has_changes = True

    if profile_filter:
        existing_profile = profiles_collection.find_one(profile_filter)
        if existing_profile:
            # Compare incoming form fields against existing profile fields to detect real edits
            # Ignore volatile/metadata fields like updated_at, created_at, _id, etc.
            ignored_fields = {
                "_id",
                "created_at",
                "updated_at",
                "profile_completion_percentage",
                "missing_core_fields",
                "submission_type",
                "submitted_at",
                "source",
            }
            has_changes = False
            for k, v in document.items():
                if k in ignored_fields:
                    continue
                exist_val = existing_profile.get(k)
                # Normalize types for comparison (e.g. lists, strings)
                if isinstance(v, list) and isinstance(exist_val, list):
                    if sorted([str(x) for x in v]) != sorted([str(x) for x in exist_val]):
                        has_changes = True
                        break
                elif str(v or "").strip() != str(exist_val or "").strip():
                    has_changes = True
                    break
        else:
            existing_profile = {}

        merged_profile = {**existing_profile, **document}
        pct, missing = calculate_profile_completion(merged_profile)
        document["profile_completion_percentage"] = pct
        document["missing_core_fields"] = missing

        prof_result = profiles_collection.update_one(
            profile_filter,
            {
                "$set": document,
                "$setOnInsert": {"created_at": now},
            },
            upsert=True,
        )
        profile_id = str(prof_result.upserted_id) if prof_result.upserted_id else (
            str(existing_profile.get("_id")) if existing_profile.get("_id") else None
        )

    # 2. Store in form_submissions as an immutable revision audit log ONLY if changes were made
    audit_id = None
    if has_changes:
        audit_entry = {
            **document,
            "submission_type": "audit_log",
            "submitted_at": now,
            "source": "citizen_form_setup",
        }
        # Remove any MongoDB _id reference from merged dict so new audit entry gets unique id
        audit_entry.pop("_id", None)
        audit_result = collection.insert_one(audit_entry)
        audit_id = str(audit_result.inserted_id)

    return {
        "status": "success",
        "message": f"Thanks {display_name}, your profile was saved successfully." if has_changes else f"Welcome back {display_name}, your profile is already up to date.",
        "id": profile_id or audit_id,
        "audit_id": audit_id,
        "has_changes": has_changes,
    }