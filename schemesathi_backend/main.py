import os
import re
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Query, Body, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from pymongo import MongoClient, UpdateOne
from pymongo.errors import PyMongoError

from form import FormData, collection as form_collection, save_form
from eligibility_engine import (
    ApprovalStatus,
    ApplicationStatus,
    CitizenProfile,
    EligibilityEngine,
    EvaluationResult,
    EvaluationStatus,
    StructuredRuleExtractor,
    StructuredSchemeRules,
)
from user_profile_service import (
    UserProfileService,
    UserSyncPayload,
    CitizenProfileUpdatePayload,
    calculate_profile_completion,
)
from auth_security import (
    ClerkUser,
    get_current_clerk_user,
    get_optional_clerk_user,
)

# ---------------------------------------------------------------------------
# Load .env (already done by form.py, but explicit here for clarity)
# ---------------------------------------------------------------------------
load_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"))

# ---------------------------------------------------------------------------
# Schemes collection (populated by scheme_updater_worker.py)
# ---------------------------------------------------------------------------
_mongo_uri = os.getenv("MONGO_URI", "mongodb://localhost:27017")
_mongo_db = os.getenv("MONGO_DB", "SchemeSathi")
_schemes_col_name = os.getenv("SCHEMES_COLLECTION", "schemes")

_schemes_client = MongoClient(_mongo_uri, serverSelectionTimeoutMS=10000)
schemes_collection = _schemes_client[_mongo_db][_schemes_col_name]

# Initialize Engine
eligibility_engine = EligibilityEngine()

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------
app = FastAPI(title="SchemeSathi API & Eligibility Engine")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Profile Helpers ─────────────────────────────────────────────────────────
def _fetch_profile_from_db(email_or_name: str) -> Optional[Dict[str, Any]]:
    target = email_or_name.strip()
    if not target:
        return None
    # 1. First check unified citizen_profiles collection
    doc = UserProfileService.get_profile(email=target.lower())
    if doc and doc.get("full_name") and doc.get("state"):
        return doc

    # 2. Try exact email match in legacy form_submissions
    doc = form_collection.find_one({"email": target.lower()})
    if not doc:
        # Try full_name match in form_submissions
        doc = form_collection.find_one(
            {"full_name": re.compile(f"^{re.escape(target)}$", re.IGNORECASE)},
            sort=[("created_at", -1)],
        )
    return doc


def _build_citizen_profile(
    clerk_user_id: Optional[str] = None,
    email: Optional[str] = None,
    profile_data: Optional[CitizenProfile] = None,
    answers: Optional[Dict[str, Any]] = None,
) -> CitizenProfile:
    """Build CitizenProfile from DB or passed payload, merging answers."""
    if profile_data:
        p = profile_data.model_copy(deep=True)
        if answers:
            p.scheme_answers.update(answers)
        return p

    # Check dedicated citizen_profiles collection first
    prof_doc = UserProfileService.get_profile(clerk_user_id=clerk_user_id, email=email)
    if prof_doc:
        p = UserProfileService.to_engine_profile(prof_doc)
        if answers:
            p.scheme_answers.update(answers)
        return p

    # Fallback to legacy form_submissions collection
    if email:
        doc = _fetch_profile_from_db(email)
        if doc:
            p = CitizenProfile(
                full_name=doc.get("full_name") or doc.get("name"),
                email=doc.get("email"),
                phone=doc.get("phone"),
                dob=doc.get("dob"),
                gender=doc.get("gender"),
                marital_status=doc.get("marital_status"),
                state=doc.get("state"),
                district=doc.get("district"),
                tehsil=doc.get("tehsil"),
                area_type=doc.get("area_type"),
                domicile_status=doc.get("domicile_status"),
                occupation=doc.get("occupation"),
                study_level=doc.get("study_level"),
                education_course=doc.get("education_course"),
                institution_type=doc.get("institution_type"),
                school_or_college_name=doc.get("school_or_college_name"),
                annual_income=doc.get("annual_income"),
                social_category=doc.get("social_category"),
                community=doc.get("community"),
                pwd_status=doc.get("pwd_status"),
                minority_status=doc.get("minority_status"),
                documents=doc.get("documents") or [],
            )
            if answers:
                p.scheme_answers.update(answers)
            return p

    p = CitizenProfile()
    if answers:
        p.scheme_answers.update(answers)
    return p


def _get_scheme_rules_from_doc(doc: Dict[str, Any], auto_approve_if_missing: bool = True) -> StructuredSchemeRules:
    """Load StructuredSchemeRules from Mongo doc or synthesize with extractor."""
    if "structured_rules" in doc and isinstance(doc["structured_rules"], dict):
        try:
            return StructuredSchemeRules.model_validate(doc["structured_rules"])
        except Exception:
            pass

    # Extract on-the-fly from raw fields
    data = doc.get("data") or {}
    raw_elig = (
        data.get("eligibility")
        or data.get("Eligibility Criteria")
        or data.get("Eligibility (General)")
        or doc.get("original_eligibility_text")
        or ""
    )
    raw_docs = (
        data.get("documents_required")
        or data.get("Documents Required")
        or doc.get("original_documents_text")
        or ""
    )
    source_url = doc.get("source_url") or data.get("official_link") or data.get("url")
    scheme_key = doc.get("scheme_key") or data.get("slug") or str(doc.get("_id", "unknown"))
    name = doc.get("name") or data.get("title") or "Scheme"
    state = doc.get("state") or data.get("state")

    rules = StructuredRuleExtractor.extract_from_scheme(
        scheme_key=scheme_key,
        name=name,
        state=state,
        raw_eligibility=raw_elig,
        raw_documents=raw_docs,
        source_url=source_url,
        auto_approve=auto_approve_if_missing,
    )
    return rules


# ── Health ──────────────────────────────────────────────────────────────────
@app.get("/")
def root():
    return {
        "status": "ok",
        "service": "SchemeSathi API & Eligibility Engine",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


# ── Citizen form submission & Profile Management ────────────────────────────
@app.post("/users/sync")
def sync_clerk_user(
    payload: UserSyncPayload,
    current_user: Optional[ClerkUser] = Depends(get_optional_clerk_user),
):
    """
    Sync Clerk authenticated user into MongoDB 'users' and 'citizen_profiles' collections.
    Derives clerk_user_id securely from the verified JWT token when provided.
    """
    try:
        if current_user:
            payload.clerk_user_id = current_user.clerk_user_id
            if current_user.email:
                payload.email = current_user.email
        return UserProfileService.sync_clerk_user(payload)
    except PyMongoError as e:
        raise HTTPException(status_code=500, detail=f"Database error: {e}")


@app.get("/profiles/me")
def get_current_profile(
    current_user: Optional[ClerkUser] = Depends(get_optional_clerk_user),
    clerk_user_id: Optional[str] = Query(None, description="Clerk user ID (fallback)"),
    email: Optional[str] = Query(None, description="Citizen email address (fallback)"),
):
    """
    Retrieve citizen profile. If authenticated via Bearer token, derives clerk_user_id
    securely from token claims to prevent impersonation.
    """
    try:
        resolved_uid = current_user.clerk_user_id if current_user else clerk_user_id
        resolved_email = current_user.email if (current_user and current_user.email) else email
        profile = UserProfileService.get_profile(clerk_user_id=resolved_uid, email=resolved_email)
        if not profile:
            raise HTTPException(status_code=404, detail="Citizen profile not found")
        return profile
    except PyMongoError as e:
        raise HTTPException(status_code=500, detail=f"Database error: {e}")


@app.put("/profiles/me")
def update_current_profile(
    payload: CitizenProfileUpdatePayload,
    current_user: Optional[ClerkUser] = Depends(get_optional_clerk_user),
):
    """
    Update citizen profile fields in the 'citizen_profiles' collection
    and re-evaluate profile completeness score.
    Derives clerk_user_id securely from the verified session token.
    """
    try:
        if current_user:
            payload.clerk_user_id = current_user.clerk_user_id
            if current_user.email and not payload.email:
                payload.email = current_user.email
        return UserProfileService.update_profile(payload)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except PyMongoError as e:
        raise HTTPException(status_code=500, detail=f"Database error: {e}")


@app.post("/submit")
def submit_form(data: FormData):
    """Save citizen profile form to the form_submissions collection."""
    try:
        return save_form(data)
    except PyMongoError as e:
        raise HTTPException(status_code=500, detail=f"Database error: {e}")


# ── Check if citizen profile exists or get user profile state ────────────────
@app.get("/profile")
def get_user_profile(
    email: str = Query(None, description="User email to look up"),
    name: str = Query(None, description="User name to look up"),
):
    """Return citizen profile info (state, full_name, exists) for this user."""
    try:
        query_val = email or name
        if not query_val or not query_val.strip():
            return {"exists": False, "state": "Madhya Pradesh"}

        doc = _fetch_profile_from_db(query_val)
        if doc:
            return {
                "exists": True,
                "state": doc.get("state") or "Madhya Pradesh",
                "full_name": doc.get("full_name") or doc.get("name") or "",
                "district": doc.get("district") or "",
                "occupation": doc.get("occupation") or "",
                "social_category": doc.get("social_category") or "",
                "annual_income": doc.get("annual_income") or "",
            }

        return {"exists": False, "state": "Madhya Pradesh"}
    except PyMongoError as e:
        raise HTTPException(status_code=500, detail=f"Database error: {e}")


# ── Schemes (populated by scheme_updater_worker.py) ─────────────────────────
@app.get("/schemes")
def get_schemes(
    state: str = Query(None, description="Filter by state name (case-insensitive)"),
    limit: int = Query(500, ge=1, le=10000),
    skip: int = Query(0, ge=0),
):
    """
    Return schemes from the 'schemes' collection.
    Includes scheme_key, active/application state, and source url.
    """
    try:
        query = {}
        if state:
            escaped_state = re.escape(state.strip())
            query["state"] = re.compile(f"^{escaped_state}$", re.IGNORECASE)

        cursor = (
            schemes_collection.find(
                query,
                {
                    "_id": 0,
                    "scheme_key": 1,
                    "name": 1,
                    "state": 1,
                    "source_url": 1,
                    "is_active": 1,
                    "application_status": 1,
                    "official_expiry_date": 1,
                    "approval_status": 1,
                    "data.title": 1,
                    "data.description": 1,
                    "data.ministry": 1,
                    "data.level": 1,
                    "data.categories": 1,
                    "data.tags": 1,
                    "data.benefits": 1,
                    "data.url": 1,
                    "data.eligibility": 1,
                    "data.documents_required": 1,
                    "data.official_link": 1,
                    "data.application_mode": 1,
                    "data.application_process": 1,
                    "data.apply_link": 1,
                    "data.apply_links": 1,
                    "data.exclusions": 1,
                },
            )
            .sort([("state", 1), ("name", 1)])
            .skip(skip)
            .limit(limit)
        )
        return {"schemes": list(cursor)}
    except PyMongoError as e:
        raise HTTPException(status_code=500, detail=f"Database error: {e}")


@app.get("/schemes/latest")
def get_latest_schemes(
    state: Optional[str] = Query(None, description="Optional state filter"),
    limit: int = Query(10, ge=1, le=50),
):
    """
    Return the newest / latest schemes added to the platform, sorted by latest insertion (_id descending).
    Optionally prioritized by citizen state or Central/All India level.
    """
    try:
        query: Dict[str, Any] = {"is_active": {"$ne": False}}
        if state and state.strip().lower() != "all states" and state.strip().lower() != "all":
            escaped = re.escape(state.strip())
            query["$or"] = [
                {"state": re.compile(f"^{escaped}$", re.IGNORECASE)},
                {"state": re.compile(r"^(all\s*india|national|central)$", re.IGNORECASE)},
                {"data.level": re.compile(r"central", re.IGNORECASE)},
            ]

        # Fetch more candidates to ensure we return `limit` distinct schemes
        fetch_limit = min(limit * 4, 150)
        cursor = (
            schemes_collection.find(
                query,
                {
                    "_id": 1,
                    "scheme_key": 1,
                    "name": 1,
                    "state": 1,
                    "source_url": 1,
                    "is_active": 1,
                    "application_status": 1,
                    "official_expiry_date": 1,
                    "approval_status": 1,
                    "created_at": 1,
                    "updated_at": 1,
                    "data.title": 1,
                    "data.description": 1,
                    "data.ministry": 1,
                    "data.level": 1,
                    "data.categories": 1,
                    "data.tags": 1,
                    "data.benefits": 1,
                    "data.url": 1,
                    "data.eligibility": 1,
                    "data.documents_required": 1,
                    "data.official_link": 1,
                    "data.application_mode": 1,
                    "data.application_process": 1,
                    "data.apply_link": 1,
                    "data.apply_links": 1,
                },
            )
            .sort([("_id", -1)])
            .limit(fetch_limit)
        )

        results = []
        seen_titles = set()
        for doc in cursor:
            # Deduplicate by normalized scheme title so central schemes duplicated across states only appear once
            title = (doc.get("data", {}).get("title") or doc.get("name") or "").strip().lower()
            if not title or title in seen_titles:
                continue
            seen_titles.add(title)

            # Format object id and generation time
            gen_time = doc["_id"].generation_time.isoformat() if "_id" in doc else None
            doc["_id"] = str(doc["_id"])
            doc["created_at"] = doc.get("created_at") or gen_time
            if isinstance(doc["created_at"], datetime):
                doc["created_at"] = doc["created_at"].isoformat()
            if isinstance(doc.get("updated_at"), datetime):
                doc["updated_at"] = doc["updated_at"].isoformat()
            doc["is_new"] = True
            results.append(doc)
            if len(results) >= limit:
                break

        return {"schemes": results, "count": len(results)}
    except PyMongoError as e:
        raise HTTPException(status_code=500, detail=f"Database error: {e}")


@app.get("/schemes/states")
def list_states():
    """Return the list of all states that have schemes stored in the database."""
    try:
        states = schemes_collection.distinct("state")
        return {"states": sorted(states)}
    except PyMongoError as e:
        raise HTTPException(status_code=500, detail=f"Database error: {e}")


@app.get("/schemes/count")
def count_schemes(state: str = Query(None)):
    """Return the total number of schemes, optionally filtered by state."""
    try:
        query = {}
        if state:
            escaped_state = re.escape(state.strip())
            query["state"] = re.compile(f"^{escaped_state}$", re.IGNORECASE)
        return {"count": schemes_collection.count_documents(query)}
    except PyMongoError as e:
        raise HTTPException(status_code=500, detail=f"Database error: {e}")


# ── Structured Eligibility Rules & Citizen Matching Endpoints ───────────────

class SingleSchemeCheckRequest(BaseModel):
    scheme_key: str
    clerk_user_id: Optional[str] = None
    email: Optional[str] = None
    profile: Optional[CitizenProfile] = None
    answers: Optional[Dict[str, Any]] = Field(default_factory=dict)
    allow_unapproved: bool = False


class RecommendationsRequest(BaseModel):
    clerk_user_id: Optional[str] = None
    email: Optional[str] = None
    profile: Optional[CitizenProfile] = None
    answers: Optional[Dict[str, Any]] = Field(default_factory=dict)
    state: Optional[str] = None
    limit: int = Field(default=100, ge=1, le=500)
    allow_unapproved: bool = False


class AdminReviewRequest(BaseModel):
    action: str = Field(description="'approve', 'reject', 'needs_admin_review', or 'update'")
    admin_name: str = Field(default="Admin")
    notes: Optional[str] = None
    official_expiry_date: Optional[str] = None  # YYYY-MM-DD
    application_status: Optional[str] = None    # "open", "closed", "upcoming", "always_open"
    structured_rules: Optional[Dict[str, Any]] = None


@app.post("/eligibility/check")
def check_single_scheme_eligibility(
    req: SingleSchemeCheckRequest,
    current_user: Optional[ClerkUser] = Depends(get_optional_clerk_user),
):
    """
    Check eligibility of a citizen for a single scheme by scheme_key.
    Returns structured results including passed/failed conditions,
    missing info with scheme-specific questions, document checklist, and status.
    Derives clerk_user_id securely from verified session token if provided.
    """
    try:
        resolved_uid = current_user.clerk_user_id if current_user else req.clerk_user_id
        resolved_email = current_user.email if (current_user and current_user.email) else req.email

        scheme_doc = schemes_collection.find_one({"scheme_key": req.scheme_key})
        if not scheme_doc:
            # Fallback search by slug or name
            scheme_doc = schemes_collection.find_one({
                "$or": [
                    {"data.slug": req.scheme_key},
                    {"name": req.scheme_key},
                ]
            })
        if not scheme_doc:
            raise HTTPException(status_code=404, detail=f"Scheme '{req.scheme_key}' not found.")

        profile = _build_citizen_profile(
            clerk_user_id=resolved_uid,
            email=resolved_email,
            profile_data=req.profile,
            answers=req.answers,
        )
        scheme_rules = _get_scheme_rules_from_doc(scheme_doc, auto_approve_if_missing=True)

        result = eligibility_engine.evaluate(
            scheme=scheme_rules,
            profile=profile,
            allow_unapproved=req.allow_unapproved,
        )

        title = scheme_doc.get("data", {}).get("title") or scheme_doc.get("name") or req.scheme_key
        result.scheme_title = title
        return result.model_dump(mode="json")
    except PyMongoError as e:
        raise HTTPException(status_code=500, detail=f"Database error: {e}")


@app.post("/eligibility/recommendations")
def get_personalized_recommendations(
    req: RecommendationsRequest,
    current_user: Optional[ClerkUser] = Depends(get_optional_clerk_user),
):
    """
    Evaluates citizen profile against schemes in the database.
    Categorizes results into:
      - 'eligible': citizen satisfies conditions (ranked by match_percentage)
      - 'needs_more_information': citizen missing fields, includes scheme-specific questions
      - 'application_closed': citizen is qualified, but application window is closed/upcoming
      - 'ineligible': conditions not met
    Derives identity securely from verified session token if provided.
    """
    try:
        resolved_uid = current_user.clerk_user_id if current_user else req.clerk_user_id
        resolved_email = current_user.email if (current_user and current_user.email) else req.email

        profile = _build_citizen_profile(
            clerk_user_id=resolved_uid,
            email=resolved_email,
            profile_data=req.profile,
            answers=req.answers,
        )
        state_to_query = req.state or profile.state

        query: Dict[str, Any] = {"is_active": {"$ne": False}}
        if state_to_query and state_to_query.strip().lower() != "all states":
            escaped = re.escape(state_to_query.strip())
            # Match state or Central / All India
            query["$or"] = [
                {"state": re.compile(f"^{escaped}$", re.IGNORECASE)},
                {"state": re.compile(r"^(all\s*india|national|central)$", re.IGNORECASE)},
                {"data.level": re.compile(r"central", re.IGNORECASE)},
            ]

        cursor = schemes_collection.find(query).limit(req.limit)
        docs = list(cursor)

        eligible_list: List[Dict[str, Any]] = []
        needs_more_info_list: List[Dict[str, Any]] = []
        application_closed_list: List[Dict[str, Any]] = []
        ineligible_list: List[Dict[str, Any]] = []

        for doc in docs:
            scheme_rules = _get_scheme_rules_from_doc(doc, auto_approve_if_missing=True)
            res = eligibility_engine.evaluate(
                scheme=scheme_rules,
                profile=profile,
                allow_unapproved=req.allow_unapproved,
            )
            res.scheme_title = (
                doc.get("data", {}).get("title") or doc.get("name") or scheme_rules.scheme_key
            )
            res_dict = res.model_dump(mode="json")
            res_dict["name"] = res.scheme_title
            res_dict["title"] = res.scheme_title
            res_dict["category"] = (
                doc.get("data", {}).get("categories")
                or doc.get("data", {}).get("category")
                or "General"
            )
            res_dict["benefits"] = doc.get("data", {}).get("benefits") or ""
            res_dict["description"] = doc.get("data", {}).get("description") or ""
            res_dict["level"] = doc.get("data", {}).get("level") or "Central"
            res_dict["state"] = doc.get("state") or doc.get("data", {}).get("state")
            res_dict["tags"] = doc.get("data", {}).get("tags") or []
            res_dict["official_link"] = doc.get("data", {}).get("official_link") or doc.get("source_url") or ""
            res_dict["apply_link"] = doc.get("data", {}).get("apply_link") or res_dict["official_link"]
            res_dict["apply_links"] = doc.get("data", {}).get("apply_links") or []
            res_dict["application_process"] = doc.get("data", {}).get("application_process") or ""
            res_dict["application_mode"] = doc.get("data", {}).get("application_mode") or ""
            res_dict["documents_required"] = doc.get("data", {}).get("documents_required") or ""
            res_dict["eligibility"] = (
                doc.get("data", {}).get("eligibility")
                or doc.get("original_eligibility_text")
                or ""
            )
            res_dict["data"] = doc.get("data") or {}

            if res.status == EvaluationStatus.ELIGIBLE:
                if not res.is_application_open:
                    application_closed_list.append(res_dict)
                else:
                    eligible_list.append(res_dict)
            elif res.status == EvaluationStatus.NEEDS_MORE_INFORMATION:
                needs_more_info_list.append(res_dict)
            else:
                ineligible_list.append(res_dict)

        # Sort eligible schemes by relevance score:
        # Prioritize schemes matching the user's specific occupation / demographic context
        user_occ = (profile.occupation or "").lower()

        def _relevance_sort_key(item: Dict[str, Any]) -> tuple:
            title = (item.get("scheme_title") or "").lower()
            cat = str(item.get("category") or "").lower()
            desc = (item.get("description") or "").lower()
            
            # Occupation relevance boost
            occ_boost = 0
            if "student" in user_occ:
                if any(k in title or k in cat or k in desc for k in ["scholarship", "education", "student", "shiksha", "chatravriti", "chhatravritti"]):
                    occ_boost = 2
                elif any(k in title or k in cat for k in ["agriculture", "gau", "krshak", "farmer"]):
                    occ_boost = -1  # Deprioritize agricultural schemes for students
            elif "farmer" in user_occ:
                if any(k in title or k in cat or k in desc for k in ["kisan", "farmer", "agriculture", "krishi", "krshak", "gau"]):
                    occ_boost = 2
            
            # Match percentage primary, then occupation relevance
            return (item.get("match_percentage", 0), occ_boost)

        eligible_list.sort(key=_relevance_sort_key, reverse=True)
        needs_more_info_list.sort(key=_relevance_sort_key, reverse=True)

        return {
            "summary": {
                "total_evaluated": len(docs),
                "eligible_count": len(eligible_list),
                "needs_more_info_count": len(needs_more_info_list),
                "application_closed_count": len(application_closed_list),
                "ineligible_count": len(ineligible_list),
            },
            "citizen": {
                "full_name": profile.full_name,
                "state": profile.state,
                "occupation": profile.occupation,
                "calculated_age": profile.calculate_age(),
            },
            "eligible": eligible_list,
            "needs_more_information": needs_more_info_list,
            "application_closed": application_closed_list,
            "ineligible": ineligible_list[:20],  # Return first 20 ineligible for reference
        }
    except PyMongoError as e:
        raise HTTPException(status_code=500, detail=f"Database error: {e}")


# ── Upcoming Milestones ─────────────────────────────────────────────────────

@app.get("/upcoming-milestones")
def get_upcoming_milestones(
    email: Optional[str] = Query(None),
    clerk_user_id: Optional[str] = Query(None),
    current_user: Optional[ClerkUser] = Depends(get_optional_clerk_user),
):
    """
    Compute personalised upcoming milestones based on the citizen's profile.
    Returns a list of actionable items the user should prepare for, covering:
    - Age-based milestones (Voter ID at 18, Full DL at 21, Senior Citizen at 60…)
    - Missing critical documents (PAN, Voter ID, Domicile, Caste Certificate…)
    - Education / career transitions (graduation, skill-up, employment registration)
    - Family / social milestones (marriage registration, child birth registration, Aadhaar linkages)
    - Scheme application windows opening soon
    """
    from datetime import date, timedelta

    resolved_uid = (current_user.clerk_user_id if current_user else None) or clerk_user_id
    resolved_email = (current_user.email if current_user else None) or email

    profile = _build_citizen_profile(clerk_user_id=resolved_uid, email=resolved_email)

    milestones: List[Dict[str, Any]] = []

    # ── Helpers ──────────────────────────────────────────────────────────────
    today = date.today()

    def _age_exact() -> Optional[int]:
        return profile.calculate_age()

    def _months_until(target: date) -> int:
        delta = (target - today).days
        return max(0, round(delta / 30.44))

    def _birthday_this_year() -> Optional[date]:
        """Return next birthday on-or-after today."""
        raw = (profile.dob or "").strip()
        raw = re.sub(r"\s*([/\-\.])\s*", r"\1", raw)
        for fmt in ("%d/%m/%Y", "%d-%m-%Y", "%d.%m.%Y", "%Y-%m-%d"):
            try:
                bd = datetime.strptime(raw, fmt).date()
                # Birthday this year
                try:
                    candidate = bd.replace(year=today.year)
                except ValueError:
                    candidate = bd.replace(year=today.year, day=28)
                if candidate < today:
                    try:
                        candidate = bd.replace(year=today.year + 1)
                    except ValueError:
                        candidate = bd.replace(year=today.year + 1, day=28)
                return candidate
            except ValueError:
                continue
        return None

    def _has_doc(*keywords: str) -> bool:
        docs_lower = [d.lower() for d in (profile.documents or [])]
        return any(
            any(kw.lower() in doc for doc in docs_lower)
            for kw in keywords
        )

    def _add(
        milestone_id: str,
        title: str,
        subtitle: str,
        icon: str,
        color: str,
        priority: str,  # "urgent", "soon", "upcoming", "informational"
        action_label: str = "Learn More",
        action_url: Optional[str] = None,
        months_away: int = 0,
        category: str = "document",
    ):
        milestones.append({
            "id": milestone_id,
            "title": title,
            "subtitle": subtitle,
            "icon": icon,
            "color": color,
            "priority": priority,
            "action_label": action_label,
            "action_url": action_url,
            "months_away": months_away,
            "category": category,
        })

    # ─────────────────────────────────────────────────────────────────────────
    # 1. AGE-BASED MILESTONES
    # ─────────────────────────────────────────────────────────────────────────
    age = _age_exact()
    next_bday = _birthday_this_year()

    if age is not None:
        # ── Approaching 18 (within 6 months) ──
        if 17 <= age < 18 and next_bday:
            months = _months_until(next_bday)
            _add(
                "turning_18",
                f"You Turn 18 in ~{months} Month{'s' if months != 1 else ''}",
                "Register for Voter ID, PAN Card & Driving Licence as soon as you turn 18.",
                "cake",
                "#F97316",
                "soon",
                "Check Pre-Registration",
                "https://www.nvsp.in",
                months_away=months,
                category="age_milestone",
            )

        # ── Just turned 18 or older – check for missing Voter ID ──
        if age >= 18 and not _has_doc("voter", "epic", "electoral"):
            _add(
                "voter_id_missing",
                "Register for Voter ID (EPIC)",
                "You are eligible. Register online at voters.eci.gov.in – takes under 10 minutes.",
                "how_to_vote",
                "#2563EB",
                "urgent" if age >= 18 else "soon",
                "Register Now",
                "https://voters.eci.gov.in",
                category="document",
            )

        # ── Missing PAN Card (age ≥ 18) ──
        if age >= 18 and not _has_doc("pan", "permanent account"):
            _add(
                "pan_missing",
                "Apply for PAN Card",
                "PAN is mandatory for financial transactions, scholarships & income tax. Apply via NSDL/UTIITSL.",
                "credit_card",
                "#7C3AED",
                "urgent" if age >= 18 else "soon",
                "Apply Online",
                "https://www.onlineservices.nsdl.com/paam/endUserRegisterContact.html",
                category="document",
            )

        # ── Driving Licence – Learner's (age ≥ 16, full at 18) ──
        if 16 <= age < 18 and not _has_doc("driving", "learner"):
            _add(
                "learner_licence",
                "Apply for Learner's Licence",
                "You can apply for a Learner's Licence at 16. Full Driving Licence is available at 18.",
                "directions_car",
                "#0891B2",
                "informational",
                "Apply on Parivahan",
                "https://parivahan.gov.in/parivahan/",
                category="document",
            )

        if age >= 18 and not _has_doc("driving", "dl"):
            _add(
                "driving_licence",
                "Get a Driving Licence",
                "Apply for a Permanent Driving Licence at Parivahan. Required for two-wheelers & cars.",
                "directions_car",
                "#0891B2",
                "upcoming",
                "Apply on Parivahan",
                "https://parivahan.gov.in/parivahan/",
                category="document",
            )

        # ── Approaching 21 – Full Driving Licence ──
        if 20 <= age < 21 and next_bday:
            months = _months_until(next_bday)
            _add(
                "turning_21_dl",
                f"Full Driving Licence in ~{months} Month{'s' if months != 1 else ''}",
                "You can apply for a Commercial Vehicle DL at 21. Prepare your documents now.",
                "local_shipping",
                "#059669",
                "informational",
                "Know More",
                "https://parivahan.gov.in/parivahan/",
                months_away=months,
                category="age_milestone",
            )

        # ── Senior Citizen approaching 60 ──
        if 59 <= age < 60 and next_bday:
            months = _months_until(next_bday)
            _add(
                "turning_60",
                f"Senior Citizen Benefits in ~{months} Month{'s' if months != 1 else ''}",
                "At 60 you become eligible for Old Age Pension, Railway concessions & Pradhan Mantri Vaya Vandana Yojana.",
                "elderly",
                "#D97706",
                "soon",
                "Explore Schemes",
                None,
                months_away=months,
                category="age_milestone",
            )

    # ─────────────────────────────────────────────────────────────────────────
    # 2. CRITICAL DOCUMENT GAPS
    # ─────────────────────────────────────────────────────────────────────────

    # Aadhaar
    if not _has_doc("aadhaar", "aadhar", "uid"):
        _add(
            "aadhaar_missing",
            "Link / Enroll for Aadhaar",
            "Aadhaar is required for almost all government schemes and DBT transfers. Enroll at any Aadhaar Seva Kendra.",
            "fingerprint",
            "#DC2626",
            "urgent",
            "Find Nearest Center",
            "https://appointments.uidai.gov.in",
            category="document",
        )

    # Domicile Certificate
    if not _has_doc("domicile", "resident certificate", "mool niwas"):
        _add(
            "domicile_missing",
            "Obtain Domicile / Resident Certificate",
            "Required for state-level scholarships, hostels & most MP government schemes. Apply at your tehsil / MP E-District portal.",
            "home_work",
            "#0284C7",
            "urgent",
            "Apply via e-District",
            "https://mpedistrict.gov.in",
            category="document",
        )

    # Samagra ID (Madhya Pradesh specific)
    if (profile.state or "").lower().startswith("madhya") and not _has_doc("samagra"):
        _add(
            "samagra_missing",
            "Register for Samagra Family ID",
            "Samagra ID is mandatory for most MP state schemes including scholarships and food security.",
            "family_restroom",
            "#7C3AED",
            "urgent",
            "Register on Samagra",
            "https://samagra.gov.in",
            category="document",
        )

    # Caste Certificate – for OBC / SC / ST citizens
    social_cat = (profile.social_category or "").lower()
    if any(x in social_cat for x in ["obc", "sc ", "st ", "scheduled caste", "scheduled tribe", "backward"]):
        if not _has_doc("caste", "community certificate", "obc certificate"):
            _add(
                "caste_cert_missing",
                "Get Your Caste Certificate",
                "OBC/SC/ST caste certificate unlocks reserved scholarships, fee waivers, and priority in government jobs.",
                "verified_user",
                "#7C3AED",
                "urgent",
                "Apply at Tehsil",
                None,
                category="document",
            )

    # Income Certificate
    if not _has_doc("income certificate", "aay praman"):
        _add(
            "income_cert_missing",
            "Obtain Annual Income Certificate",
            "Required for means-tested scholarships, free ration, and housing schemes. Apply at your local SDM / tehsil office.",
            "receipt_long",
            "#D97706",
            "urgent" if (profile.occupation or "").lower() == "student" else "soon",
            "Apply at Tehsil",
            None,
            category="document",
        )

    # Aadhaar-linked Bank Account
    if not _has_doc("bank", "aadhaar-seed", "dbt"):
        _add(
            "bank_link",
            "Link Aadhaar to Bank Account",
            "DBT (Direct Benefit Transfer) for scholarships, pensions & LPG subsidy requires Aadhaar-linked bank account.",
            "account_balance",
            "#059669",
            "soon",
            "Visit Your Bank",
            None,
            category="document",
        )

    # DigiLocker
    if not _has_doc("digilocker", "digi locker"):
        _add(
            "digilocker",
            "Set Up DigiLocker Account",
            "Store all government documents digitally. Required for online scheme applications and instant verification.",
            "cloud_done",
            "#2563EB",
            "informational",
            "Create DigiLocker",
            "https://digilocker.gov.in",
            category="digital",
        )

    # ─────────────────────────────────────────────────────────────────────────
    # 3. STUDENT / EDUCATION MILESTONES
    # ─────────────────────────────────────────────────────────────────────────
    if (profile.occupation or "").lower() in ("student", "studying"):
        # APAAR / ABC Student ID
        if not _has_doc("apaar", "abc", "academic bank"):
            _add(
                "apaar_missing",
                "Register for APAAR / ABC Student ID",
                "Academic Bank of Credits (ABC) ID is now mandatory for scholarships & NEP 2020 credit transfers. Register on DigiLocker.",
                "school",
                "#0891B2",
                "urgent",
                "Register on DigiLocker",
                "https://digilocker.gov.in",
                category="education",
            )

        # Class 10 / 12 marks certificates
        study = (profile.study_level or "").lower()
        if "college" in study or "university" in study or "undergraduate" in study or "graduate" in study:
            if not _has_doc("10th", "tenth", "class x", "matriculation"):
                _add(
                    "tenth_marksheet",
                    "Upload Class 10 Marksheet",
                    "10th marksheet is required for college fee waivers, OBC/SC/ST scholarships, and Samagra verification.",
                    "menu_book",
                    "#0891B2",
                    "soon",
                    "Upload to DigiLocker",
                    "https://digilocker.gov.in",
                    category="education",
                )

        # PM Scholarship / National Scholarship Portal reminder
        _add(
            "nsp_scholarship",
            "Apply on National Scholarship Portal",
            "NSP opens every year (Aug–Oct). Check pre-matric, post-matric & merit scholarships before the window closes.",
            "workspace_premium",
            "#059669",
            "informational",
            "Visit NSP",
            "https://scholarships.gov.in",
            category="scheme",
        )

    # ─────────────────────────────────────────────────────────────────────────
    # 4. HEALTH & INSURANCE MILESTONES
    # ─────────────────────────────────────────────────────────────────────────
    # Ayushman Bharat – PM-JAY (income < 1L or BPL)
    income_str = (profile.annual_income or "").lower()
    is_low_income = any(x in income_str for x in ["antyodaya", "bpl", "1,00,000", "below poverty", "50,000"])
    if is_low_income and not _has_doc("ayushman", "pmjay", "pm-jay", "jan arogya"):
        _add(
            "ayushman_bharat",
            "Enroll in Ayushman Bharat (PM-JAY)",
            "Your income level qualifies you for ₹5 Lakh free hospital cover under PM-JAY. Check eligibility at pmjay.gov.in.",
            "local_hospital",
            "#DC2626",
            "urgent",
            "Check Eligibility",
            "https://beneficiary.nha.gov.in",
            category="health",
        )

    # PM Suraksha Bima Yojana (age 18-70)
    if age is not None and 18 <= age <= 70:
        if not _has_doc("pm suraksha", "pmsby", "accident insurance"):
            _add(
                "pmsby",
                "Enroll in PM Suraksha Bima Yojana",
                "Get accident insurance cover of ₹2 Lakh for just ₹20/year. Available at any bank for ages 18–70.",
                "shield",
                "#059669",
                "informational",
                "Enroll at Bank",
                "https://jansuraksha.gov.in",
                category="insurance",
            )

    # ─────────────────────────────────────────────────────────────────────────
    # 5. GENDER-SPECIFIC MILESTONES
    # ─────────────────────────────────────────────────────────────────────────
    gender = (profile.gender or "").lower()
    if "female" in gender or "woman" in gender or "girl" in gender:
        # PM Ujjwala Yojana (BPL/Antyodaya women)
        if is_low_income and not _has_doc("lpg", "ujjwala", "gas connection"):
            _add(
                "ujjwala",
                "Apply for PM Ujjwala Yojana – Free LPG",
                "BPL women get free LPG connection under Ujjwala 2.0. Apply at any gas agency with Aadhaar & ration card.",
                "local_fire_department",
                "#D97706",
                "soon",
                "Apply at Gas Agency",
                "https://www.pmuy.gov.in",
                category="scheme",
            )

        # Ladli Laxmi / other MP women schemes
        if (profile.state or "").lower().startswith("madhya"):
            _add(
                "ladli_laxmi",
                "Check Ladli Laxmi Yojana Benefits",
                "MP's Ladli Laxmi scheme provides financial support to girls. Check your enrollment status.",
                "favorite",
                "#DB2777",
                "informational",
                "Check Status",
                "https://ladlilaxmi.mp.gov.in",
                category="scheme",
            )

    # ─────────────────────────────────────────────────────────────────────────
    # 6. EMPLOYMENT / SKILL MILESTONES
    # ─────────────────────────────────────────────────────────────────────────
    if (profile.occupation or "").lower() in ("unemployed", "looking for job", "fresher"):
        _add(
            "employment_registration",
            "Register at Employment Exchange",
            "Register at the state Employment Exchange to access job alerts, skill training & reservation-based government jobs.",
            "work",
            "#2563EB",
            "urgent",
            "Register Online",
            "https://mprojgar.gov.in",
            category="employment",
        )
        _add(
            "skill_india",
            "Enroll in Skill India / PMKVY",
            "Free skill training with certificate under Pradhan Mantri Kaushal Vikas Yojana. Enroll at skill.gov.in.",
            "engineering",
            "#059669",
            "soon",
            "Enroll Now",
            "https://www.pmkvyofficial.org",
            category="employment",
        )

    # ─────────────────────────────────────────────────────────────────────────
    # 7. PRIORITY SORT: urgent → soon → upcoming → informational
    # ─────────────────────────────────────────────────────────────────────────
    _priority_order = {"urgent": 0, "soon": 1, "upcoming": 2, "informational": 3}
    milestones.sort(key=lambda m: (_priority_order.get(m["priority"], 9), m.get("months_away", 0)))

    return {
        "milestones": milestones,
        "total": len(milestones),
        "citizen": {
            "age": age,
            "occupation": profile.occupation,
            "state": profile.state,
            "gender": profile.gender,
            "social_category": profile.social_category,
            "annual_income": profile.annual_income,
        },
    }


# ── Notifications API ────────────────────────────────────────────────────────

@app.get("/notifications")
def get_user_notifications(
    email: Optional[str] = Query(None),
    clerk_user_id: Optional[str] = Query(None),
    state: Optional[str] = Query(None),
    current_user: Optional[ClerkUser] = Depends(get_optional_clerk_user),
):
    """
    Generate dynamic citizen notifications combining:
    1. Critical document alerts (Voter ID, PAN, Aadhaar, Income certificate)
    2. Newly launched government schemes for their state/national level
    3. Milestone alerts (scholarship windows, insurance enrollment)
    """
    resolved_uid = (current_user.clerk_user_id if current_user else None) or clerk_user_id
    resolved_email = (current_user.email if current_user else None) or email

    profile = _build_citizen_profile(clerk_user_id=resolved_uid, email=resolved_email)
    citizen_state = state or profile.state or "Madhya Pradesh"

    notifications: List[Dict[str, Any]] = []

    # 1. Fetch upcoming milestones and convert to notification items
    milestones_resp = get_upcoming_milestones(email=resolved_email, clerk_user_id=resolved_uid, current_user=None)
    milestones_list = milestones_resp.get("milestones", [])

    for m in milestones_list:
        is_urgent = m.get("priority") == "urgent"
        notifications.append({
            "id": f"notif_{m.get('id')}",
            "type": "alert" if is_urgent else "reminder",
            "title": m.get("title"),
            "message": m.get("subtitle"),
            "category": m.get("category", "General"),
            "timestamp": "Action Recommended",
            "is_read": False,
            "priority": m.get("priority"),
            "action_label": m.get("action_label"),
            "action_url": m.get("action_url"),
            "icon": m.get("icon"),
            "color": m.get("color"),
        })

    # 2. Add newest schemes as "New Scheme" notifications
    try:
        latest_resp = get_latest_schemes(state=citizen_state, limit=4)
        latest_schemes = latest_resp.get("schemes", [])
        for s in latest_schemes:
            name = s.get("name") or s.get("data", {}).get("title") or "New Government Scheme"
            desc = s.get("data", {}).get("description") or s.get("description") or "Check your eligibility and apply online."
            if len(desc) > 130:
                desc = desc[:127] + "..."
            notifications.append({
                "id": f"notif_scheme_{s.get('scheme_key', str(s.get('_id')))}",
                "type": "new_scheme",
                "title": f"New Scheme: {name}",
                "message": desc,
                "category": s.get("data", {}).get("categories", ["General"])[0] if isinstance(s.get("data", {}).get("categories"), list) and s.get("data", {}).get("categories") else "Government",
                "timestamp": "Recently Added",
                "is_read": False,
                "priority": "soon",
                "action_label": "View Scheme",
                "action_url": s.get("data", {}).get("url") or s.get("source_url"),
                "icon": "campaign",
                "color": "#16A34A",
            })
    except Exception:
        pass

    return {
        "notifications": notifications,
        "unread_count": len(notifications),
        "total": len(notifications),
    }


@app.get("/schemes/{scheme_key}/rules")
def get_scheme_rules(scheme_key: str):
    """
    Fetch structured eligibility conditions, original text, required documents,
    approval status, and verification auditing for a scheme.
    """
    try:
        doc = schemes_collection.find_one({"scheme_key": scheme_key})
        if not doc:
            raise HTTPException(status_code=404, detail="Scheme not found")

        rules = _get_scheme_rules_from_doc(doc, auto_approve_if_missing=False)
        return rules.model_dump(mode="json")
    except PyMongoError as e:
        raise HTTPException(status_code=500, detail=f"Database error: {e}")


@app.post("/admin/schemes/{scheme_key}/review")
def admin_review_scheme(scheme_key: str, body: AdminReviewRequest):
    """
    Admin verification endpoint:
    - Approve newly extracted rules to participate in public citizen matching
    - Reject or mark for further review
    - Set official verified expiry date and application status
    - Update rule details
    """
    try:
        now = datetime.now(timezone.utc)
        doc = schemes_collection.find_one({"scheme_key": scheme_key})
        if not doc:
            raise HTTPException(status_code=404, detail="Scheme not found")

        # Load existing full rules or synthesize initial structured rules
        existing_rules = _get_scheme_rules_from_doc(doc, auto_approve_if_missing=False)

        update_fields: Dict[str, Any] = {
            "last_verified_at": now,
        }

        action_norm = body.action.strip().lower()
        if action_norm == "approve":
            existing_rules.approval_status = ApprovalStatus.APPROVED
            existing_rules.approved_by = body.admin_name
            existing_rules.approved_at = now
            existing_rules.approval_notes = body.notes or "Approved by admin"
        elif action_norm == "reject":
            existing_rules.approval_status = ApprovalStatus.REJECTED
            existing_rules.approval_notes = body.notes
        elif action_norm == "needs_admin_review":
            existing_rules.approval_status = ApprovalStatus.NEEDS_ADMIN_REVIEW
            existing_rules.approval_notes = body.notes

        if body.official_expiry_date:
            existing_rules.official_expiry_date = body.official_expiry_date
            existing_rules.expiry_verified = True
            update_fields["official_expiry_date"] = body.official_expiry_date

        if body.application_status:
            try:
                existing_rules.application_status = ApplicationStatus(body.application_status)
            except Exception:
                pass
            update_fields["application_status"] = body.application_status

        if body.structured_rules:
            existing_rules = StructuredSchemeRules.model_validate(body.structured_rules)

        update_fields["structured_rules"] = existing_rules.model_dump(mode="json")
        update_fields["approval_status"] = existing_rules.approval_status.value

        schemes_collection.update_one(
            {"scheme_key": scheme_key},
            {"$set": update_fields},
        )

        return {
            "status": "success",
            "scheme_key": scheme_key,
            "action": action_norm,
            "updated_at": now.isoformat(),
        }
    except PyMongoError as e:
        raise HTTPException(status_code=500, detail=f"Database error: {e}")


@app.get("/admin/schemes/pending-review")
def list_pending_review_schemes(
    limit: int = Query(50, ge=1, le=500),
    skip: int = Query(0, ge=0),
):
    """
    List schemes that require admin review (unapproved rules, unclear conditions,
    or extraction warnings).
    """
    try:
        query = {
            "$or": [
                {"approval_status": {"$in": ["pending_review", "needs_admin_review"]}},
                {"structured_rules.approval_status": {"$in": ["pending_review", "needs_admin_review"]}},
            ]
        }
        cursor = (
            schemes_collection.find(
                query,
                {
                    "_id": 0,
                    "scheme_key": 1,
                    "name": 1,
                    "state": 1,
                    "approval_status": 1,
                    "structured_rules.approval_status": 1,
                    "structured_rules.extraction_metadata": 1,
                    "original_eligibility_text": 1,
                    "data.title": 1,
                },
            )
            .skip(skip)
            .limit(limit)
        )
        items = list(cursor)
        return {
            "total_pending": schemes_collection.count_documents(query),
            "schemes": items,
        }
    except PyMongoError as e:
        raise HTTPException(status_code=500, detail=f"Database error: {e}")


@app.post("/admin/schemes/seed-rules")
def seed_structured_rules(limit: int = Query(200, ge=1, le=2000), auto_approve: bool = Query(True)):
    """
    Batch extract and populate structured eligibility rules for schemes in MongoDB
    that do not yet have structured rules.
    """
    try:
        query = {"structured_rules": {"$exists": False}}
        cursor = schemes_collection.find(query).limit(limit)
        docs = list(cursor)

        updated_count = 0
        ops: List[UpdateOne] = []

        for doc in docs:
            rules = _get_scheme_rules_from_doc(doc, auto_approve_if_missing=auto_approve)
            ops.append(
                UpdateOne(
                    {"_id": doc["_id"]},
                    {
                        "$set": {
                            "structured_rules": rules.model_dump(mode="json"),
                            "original_eligibility_text": rules.original_eligibility_text,
                            "original_documents_text": rules.original_documents_text,
                            "approval_status": rules.approval_status.value,
                            "is_active": rules.is_active,
                            "application_status": rules.application_status.value,
                            "last_seen_at": datetime.now(timezone.utc),
                        }
                    },
                )
            )

        if ops:
            res = schemes_collection.bulk_write(ops, ordered=False)
            updated_count = res.modified_count

        return {
            "status": "success",
            "schemes_processed": len(docs),
            "schemes_updated": updated_count,
        }
    except PyMongoError as e:
        raise HTTPException(status_code=500, detail=f"Database error: {e}")
