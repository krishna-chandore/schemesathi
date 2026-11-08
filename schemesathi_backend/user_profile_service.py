"""
Citizen Profile and User Identity Service for SchemeSathi.

Manages:
- MongoDB `users` collection linked to Clerk User IDs.
- MongoDB `citizen_profiles` collection linked 1-to-1 to Clerk identity.
- Profile completion calculation.
- Auto-migration from legacy `form_submissions` records when a Clerk user logs in.
"""

from __future__ import annotations

import os
import re
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple, Union
from pydantic import BaseModel, Field
from pymongo import ASCENDING, MongoClient, ReturnDocument

from eligibility_engine import CitizenProfile

# --------------------------------------------------------------------------- #
# Mongo Connection Setup
# --------------------------------------------------------------------------- #
MONGO_URI = os.getenv("MONGO_URI", "mongodb://localhost:27017")
MONGO_DB = os.getenv("MONGO_DB", "SchemeSathi")

client = MongoClient(MONGO_URI, serverSelectionTimeoutMS=5000)
db = client[MONGO_DB]

users_collection = db["users"]
profiles_collection = db["citizen_profiles"]
legacy_form_collection = db["form_submissions"]

# Ensure unique indexes
try:
    users_collection.create_index([("clerk_user_id", ASCENDING)], unique=True, name="uniq_clerk_user_id")
    users_collection.create_index([("email", ASCENDING)], name="idx_users_email")
    profiles_collection.create_index([("clerk_user_id", ASCENDING)], unique=True, name="uniq_profile_clerk_id")
    profiles_collection.create_index([("email", ASCENDING)], name="idx_profile_email")
except Exception:
    pass


# --------------------------------------------------------------------------- #
# Models
# --------------------------------------------------------------------------- #
class UserSyncPayload(BaseModel):
    clerk_user_id: str = Field(description="Unique Clerk user ID, e.g. user_2nK...")
    email: str = Field(description="User primary email address")
    full_name: Optional[str] = None
    avatar_url: Optional[str] = None
    provider: Optional[str] = "google"


class CitizenProfileUpdatePayload(BaseModel):
    clerk_user_id: Optional[str] = None
    email: Optional[str] = None

    # Step 1: Personal
    full_name: Optional[str] = None
    dob: Optional[str] = None
    gender: Optional[str] = None
    marital_status: Optional[str] = None

    # Step 2: Residence
    state: Optional[str] = None
    district: Optional[str] = None
    tehsil: Optional[str] = None
    area_type: Optional[str] = None  # rural / urban
    domicile_status: Optional[str] = None  # yes / in_progress / no
    local_residence_outside: Optional[bool] = None
    family_id: Optional[str] = None

    # Step 3: Occupation & Education
    occupation: Optional[str] = None
    study_level: Optional[str] = None
    education_course: Optional[str] = None
    institution_type: Optional[str] = None
    school_or_college_name: Optional[str] = None

    # Step 4: Special Eligibility
    social_category: Optional[str] = None  # General / OBC / SC / ST / EWS
    caste_certificate_status: Optional[str] = None
    community: Optional[str] = None
    pwd_status: Optional[Union[bool, str]] = None
    disability_percentage: Optional[float] = None
    minority_status: Optional[Union[bool, str]] = None
    income_certificate_status: Optional[str] = None
    annual_income: Optional[Union[float, int, str]] = None

    # Step 5: Documents & Custom Scheme Answers
    documents: Optional[List[str]] = None
    scheme_answers: Optional[Dict[str, Any]] = None

    # App Preferences
    language: Optional[str] = None


# Core evaluation fields used to calculate profile completeness
CORE_FIELDS = [
    "full_name",
    "dob",
    "gender",
    "state",
    "district",
    "occupation",
    "annual_income",
    "social_category",
]


def calculate_profile_completion(data: Dict[str, Any]) -> Tuple[int, List[str]]:
    """Calculates profile completion percentage and returns list of missing essential fields."""
    missing: List[str] = []
    filled = 0
    for f in CORE_FIELDS:
        val = data.get(f)
        if val is not None and str(val).strip():
            filled += 1
        else:
            missing.append(f)

    # Base percentage from 8 core fields (up to 80%)
    base_score = int((filled / len(CORE_FIELDS)) * 80)

    # Additional 20% for education/institution and documents
    bonus = 0
    if data.get("education_course") or data.get("study_level"):
        bonus += 10
    if data.get("documents") and len(data["documents"]) > 0:
        bonus += 10

    total_pct = min(100, base_score + bonus)
    return total_pct, missing


# --------------------------------------------------------------------------- #
# User & Profile Services
# --------------------------------------------------------------------------- #
class UserProfileService:
    @classmethod
    def sync_clerk_user(cls, payload: UserSyncPayload) -> Dict[str, Any]:
        """
        Syncs authenticated Clerk user to the `users` collection.
        If a citizen profile does not exist yet:
          1) Checks legacy `form_submissions` by email to migrate existing profile data.
          2) Creates new `citizen_profiles` document.
        """
        now = datetime.now(timezone.utc)
        clean_email = payload.email.strip().lower()

        # 1. Upsert users collection
        user_doc = {
            "clerk_user_id": payload.clerk_user_id,
            "email": clean_email,
            "full_name": payload.full_name,
            "avatar_url": payload.avatar_url,
            "provider": payload.provider or "google",
            "last_sign_in_at": now,
            "updated_at": now,
        }

        users_collection.update_one(
            {"clerk_user_id": payload.clerk_user_id},
            {
                "$set": user_doc,
                "$setOnInsert": {"created_at": now},
            },
            upsert=True,
        )

        # 2. Check or create citizen profile
        profile = profiles_collection.find_one({"clerk_user_id": payload.clerk_user_id})
        if not profile and clean_email:
            # Also check if existing profile was created with this email
            profile = profiles_collection.find_one({"email": clean_email})
            if profile:
                # Link existing profile with this clerk_user_id
                profiles_collection.update_one(
                    {"_id": profile["_id"]},
                    {"$set": {"clerk_user_id": payload.clerk_user_id, "updated_at": now}},
                )

        if not profile:
            # Check for legacy submission by email to migrate
            legacy_doc = legacy_form_collection.find_one(
                {"email": clean_email},
                sort=[("created_at", -1)],
            )

            new_profile: Dict[str, Any] = {
                "clerk_user_id": payload.clerk_user_id,
                "email": clean_email,
                "full_name": payload.full_name or (legacy_doc.get("full_name") if legacy_doc else None),
                "created_at": now,
                "updated_at": now,
                "documents": [],
                "scheme_answers": {},
            }

            if legacy_doc:
                # Migrate fields from legacy form submission
                migrate_keys = [
                    "dob", "gender", "marital_status", "state", "district", "tehsil",
                    "area_type", "domicile_status", "local_residence_outside", "family_id",
                    "occupation", "study_level", "education_course", "institution_type",
                    "school_or_college_name", "social_category", "caste_certificate_status",
                    "pwd_status", "minority_status", "income_certificate_status", "annual_income",
                    "documents",
                ]
                for k in migrate_keys:
                    if legacy_doc.get(k) is not None:
                        new_profile[k] = legacy_doc.get(k)

            pct, missing = calculate_profile_completion(new_profile)
            new_profile["profile_completion_percentage"] = pct
            new_profile["missing_core_fields"] = missing

            profiles_collection.update_one(
                {"clerk_user_id": payload.clerk_user_id},
                {"$set": new_profile},
                upsert=True,
            )
            profile = new_profile

        # Return combined status
        profile_data = dict(profile)
        if "_id" in profile_data:
            profile_data["_id"] = str(profile_data["_id"])

        pct, missing = calculate_profile_completion(profile_data)
        # Check if citizen has filled the form beyond default sign-in fields
        has_filled_form = bool(
            profile_data.get("dob")
            and profile_data.get("state")
            and profile_data.get("district")
        )
        return {
            "status": "success",
            "clerk_user_id": payload.clerk_user_id,
            "email": clean_email,
            "profile_exists": True,
            "has_completed_form": has_filled_form,
            "profile_completion_percentage": pct,
            "missing_core_fields": missing,
            "profile": profile_data,
        }

    @classmethod
    def get_profile(
        cls, clerk_user_id: Optional[str] = None, email: Optional[str] = None
    ) -> Optional[Dict[str, Any]]:
        """Retrieve citizen profile by clerk_user_id or email."""
        query = {}
        if clerk_user_id and clerk_user_id.strip():
            query["clerk_user_id"] = clerk_user_id.strip()
        elif email and email.strip():
            query["email"] = email.strip().lower()
        else:
            return None

        doc = profiles_collection.find_one(query)
        if not doc and email:
            # Fallback to legacy form collection
            legacy = legacy_form_collection.find_one({"email": email.strip().lower()}, sort=[("created_at", -1)])
            if legacy:
                doc = legacy

        if not doc:
            return None

        data = dict(doc)
        if "_id" in data:
            data["_id"] = str(data["_id"])

        pct, missing = calculate_profile_completion(data)
        data["profile_completion_percentage"] = pct
        data["missing_core_fields"] = missing
        return data

    @classmethod
    def update_profile(cls, payload: CitizenProfileUpdatePayload) -> Dict[str, Any]:
        """Update or create citizen profile in the `citizen_profiles` collection."""
        now = datetime.now(timezone.utc)
        query = {}
        if payload.clerk_user_id and payload.clerk_user_id.strip():
            query["clerk_user_id"] = payload.clerk_user_id.strip()
        elif payload.email and payload.email.strip():
            query["email"] = payload.email.strip().lower()
        else:
            raise ValueError("Either clerk_user_id or email must be provided to update profile.")

        update_dict = payload.model_dump(exclude_none=True)
        # Remove query keys from update dict
        update_dict.pop("clerk_user_id", None)
        if "email" in update_dict and not payload.clerk_user_id:
            pass  # keep email

        update_dict["updated_at"] = now

        # Handle nested scheme_answers if provided (merge rather than overwrite)
        scheme_answers_update = update_dict.pop("scheme_answers", None)

        set_payload = {**update_dict}
        if scheme_answers_update:
            for k, v in scheme_answers_update.items():
                set_payload[f"scheme_answers.{k}"] = v

        # Fetch current to recompute completion percentage
        current = profiles_collection.find_one(query) or {}
        merged = {**current, **update_dict}
        if scheme_answers_update:
            existing_ans = merged.get("scheme_answers") or {}
            existing_ans.update(scheme_answers_update)
            merged["scheme_answers"] = existing_ans

        pct, missing = calculate_profile_completion(merged)
        set_payload["profile_completion_percentage"] = pct
        set_payload["missing_core_fields"] = missing

        if payload.clerk_user_id:
            set_payload["clerk_user_id"] = payload.clerk_user_id
        if payload.email:
            set_payload["email"] = payload.email.strip().lower()

        updated_doc = profiles_collection.find_one_and_update(
            query,
            {
                "$set": set_payload,
                "$setOnInsert": {"created_at": now},
            },
            upsert=True,
            return_document=ReturnDocument.AFTER,
        )

        res = dict(updated_doc)
        if "_id" in res:
            res["_id"] = str(res["_id"])
        return res

    @classmethod
    def to_engine_profile(cls, profile_dict: Dict[str, Any]) -> CitizenProfile:
        """Adapts a citizen_profiles document into the engine's CitizenProfile model."""
        return CitizenProfile(
            full_name=profile_dict.get("full_name"),
            email=profile_dict.get("email"),
            dob=profile_dict.get("dob"),
            gender=profile_dict.get("gender"),
            marital_status=profile_dict.get("marital_status"),
            state=profile_dict.get("state"),
            district=profile_dict.get("district"),
            tehsil=profile_dict.get("tehsil"),
            area_type=profile_dict.get("area_type"),
            domicile_status=profile_dict.get("domicile_status"),
            occupation=profile_dict.get("occupation"),
            study_level=profile_dict.get("study_level"),
            education_course=profile_dict.get("education_course"),
            institution_type=profile_dict.get("institution_type"),
            school_or_college_name=profile_dict.get("school_or_college_name"),
            annual_income=profile_dict.get("annual_income"),
            social_category=profile_dict.get("social_category"),
            community=profile_dict.get("community"),
            pwd_status=profile_dict.get("pwd_status"),
            disability_percentage=profile_dict.get("disability_percentage"),
            minority_status=profile_dict.get("minority_status"),
            documents=profile_dict.get("documents") or [],
            scheme_answers=profile_dict.get("scheme_answers") or {},
        )
