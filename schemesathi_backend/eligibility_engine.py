"""
Eligibility Engine for SchemeSathi.

Implements structured scheme eligibility rules, Citizen Profile evaluation,
AND/OR condition trees, missing information prompting, document handling,
active vs application-open distinctions, rule verification, and LLM extraction auditing.
"""

from __future__ import annotations

import re
from datetime import date, datetime, timezone
from enum import Enum
from typing import Any, Dict, List, Optional, Sequence, Set, Tuple, Union
from pydantic import BaseModel, Field


# --------------------------------------------------------------------------- #
# Enums
# --------------------------------------------------------------------------- #
class ConditionType(str, Enum):
    AGE = "age"
    GENDER = "gender"
    STATE = "state"
    OCCUPATION = "occupation"
    EDUCATION = "education"
    INCOME = "income"
    CATEGORY = "category"
    COMMUNITY = "community"
    DISABILITY = "disability"
    DOCUMENTS = "documents"
    CUSTOM = "custom"


class RuleOperator(str, Enum):
    AND = "AND"
    OR = "OR"


class EvaluationStatus(str, Enum):
    ELIGIBLE = "eligible"
    INELIGIBLE = "ineligible"
    NEEDS_MORE_INFORMATION = "needs_more_information"
    NEEDS_ADMIN_REVIEW = "needs_admin_review"


class ApplicationStatus(str, Enum):
    OPEN = "open"
    CLOSED = "closed"
    UPCOMING = "upcoming"
    ALWAYS_OPEN = "always_open"


class ApprovalStatus(str, Enum):
    APPROVED = "approved"
    PENDING_REVIEW = "pending_review"
    REJECTED = "rejected"
    NEEDS_ADMIN_REVIEW = "needs_admin_review"


# --------------------------------------------------------------------------- #
# Condition & Rule Models
# --------------------------------------------------------------------------- #
class Criterion(BaseModel):
    rule_id: str = Field(description="Unique identifier for this criterion")
    condition_type: ConditionType
    field_name: str = Field(description="Target citizen field name, e.g. 'dob', 'state', 'annual_income'")
    description: str = Field(description="Human-readable description of this eligibility rule")
    
    # Value constraints
    min_value: Optional[float] = None
    max_value: Optional[float] = None
    allowed_values: Optional[List[str]] = None
    excluded_values: Optional[List[str]] = None
    exact_value: Optional[Any] = None
    
    # Flags & Behavior
    is_mandatory: bool = True
    mandatory_at_application: bool = False  # If True, lacking document causes ineligibility
    question: Optional[str] = Field(
        default=None,
        description="Scheme-specific question to ask citizen if this profile field is missing"
    )
    is_clear: bool = Field(default=True, description="False if LLM or scraper flagged unclear condition")
    unclear_reason: Optional[str] = None


class ConditionGroup(BaseModel):
    operator: RuleOperator = RuleOperator.AND
    conditions: List[Criterion] = Field(default_factory=list)
    subgroups: List[ConditionGroup] = Field(default_factory=list)


class DocumentRequirement(BaseModel):
    doc_name: str
    mandatory_at_application: bool = False
    description: Optional[str] = None


class ExtractionMetadata(BaseModel):
    llm_model: Optional[str] = "gemini-1.5-pro"
    llm_version: Optional[str] = "2026-v1"
    extracted_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    confidence_score: float = 1.0  # 0.0 to 1.0
    warnings: List[str] = Field(default_factory=list)
    raw_response: Optional[str] = None


class StructuredSchemeRules(BaseModel):
    scheme_key: str
    rule_version: int = 1
    approval_status: ApprovalStatus = ApprovalStatus.PENDING_REVIEW
    approved_by: Optional[str] = None
    approved_at: Optional[datetime] = None
    approval_notes: Optional[str] = None
    
    root_group: ConditionGroup
    required_documents: List[DocumentRequirement] = Field(default_factory=list)
    
    # Audit & Verifiability: Preserve original text alongside structured rules
    original_eligibility_text: Optional[str] = ""
    original_documents_text: Optional[str] = ""
    source_url: Optional[str] = None
    
    # Scraper & Timestamps
    content_hash: Optional[str] = None
    last_seen_at: Optional[datetime] = None
    last_verified_at: Optional[datetime] = None
    consecutive_fetch_failures: int = 0
    
    # Lifecycle & Application Windows
    is_active: bool = True
    application_status: ApplicationStatus = ApplicationStatus.OPEN
    application_start_date: Optional[str] = None  # YYYY-MM-DD
    application_end_date: Optional[str] = None    # YYYY-MM-DD
    official_expiry_date: Optional[str] = None    # YYYY-MM-DD (verified only)
    expiry_verified: bool = False
    
    extraction_metadata: Optional[ExtractionMetadata] = None


# --------------------------------------------------------------------------- #
# Citizen Profile Model
# --------------------------------------------------------------------------- #
class CitizenProfile(BaseModel):
    full_name: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None
    
    # Core demographic & location
    dob: Optional[str] = None  # YYYY-MM-DD or DD/MM/YYYY or DD-MM-YYYY
    age: Optional[int] = None
    gender: Optional[str] = None
    marital_status: Optional[str] = None
    
    state: Optional[str] = None
    district: Optional[str] = None
    tehsil: Optional[str] = None
    area_type: Optional[str] = None  # rural / urban
    domicile_status: Optional[str] = None  # yes / in_progress / no
    
    # Occupation & Education
    occupation: Optional[str] = None
    study_level: Optional[str] = None
    education_course: Optional[str] = None
    institution_type: Optional[str] = None
    school_or_college_name: Optional[str] = None
    
    # Financial & Social
    annual_income: Optional[Union[float, int, str]] = None
    social_category: Optional[str] = None  # General / OBC / SC / ST / EWS
    community: Optional[str] = None        # Brahmin, minority groups, etc.
    pwd_status: Optional[Union[bool, str]] = None
    disability_percentage: Optional[float] = None
    minority_status: Optional[Union[bool, str]] = None
    
    # Documents in citizen possession
    documents: List[str] = Field(default_factory=list)
    
    # Scheme-specific answered questions: { question_or_rule_id: answer }
    scheme_answers: Dict[str, Any] = Field(default_factory=dict)

    def calculate_age(self) -> Optional[int]:
        """Calculate age from dob or direct age field."""
        if self.age is not None and self.age >= 0:
            return int(self.age)
        
        if not self.dob:
            return None
        
        dob_str = str(self.dob).strip()
        # Clean any whitespace around slashes/hyphens (e.g. '25 / 07 / 2004' -> '25/07/2004')
        dob_str = re.sub(r"\s*([/\-\.])\s*", r"\1", dob_str)
        # Try various date formats
        for fmt in ("%Y-%m-%d", "%d/%m/%Y", "%d-%m-%Y", "%Y/%m/%d", "%d.%m.%Y"):
            try:
                dt = datetime.strptime(dob_str, fmt).date()
                today = date.today()
                age = today.year - dt.year - ((today.month, today.day) < (dt.month, dt.day))
                return max(0, age)
            except ValueError:
                continue
        
        # If pure integer was passed as dob
        try:
            return int(dob_str)
        except ValueError:
            return None

    def get_parsed_income(self) -> Optional[float]:
        """Extract numeric annual income from number or string like '₹2,50,000' or '2.5 Lakh'."""
        if self.annual_income is None:
            return None
        if isinstance(self.annual_income, (int, float)):
            return float(self.annual_income)
        
        raw = str(self.annual_income).strip().lower()
        if not raw:
            return None
        
        # Check Lakh / Cr notations
        lakh_match = re.search(r"([\d\.]+)\s*(?:lakh|lac|l)", raw)
        if lakh_match:
            try:
                return float(lakh_match.group(1)) * 100000.0
            except ValueError:
                pass
        
        cr_match = re.search(r"([\d\.]+)\s*(?:crore|cr)", raw)
        if cr_match:
            try:
                return float(cr_match.group(1)) * 10000000.0
            except ValueError:
                pass
        
        # Strip currency symbols and commas
        clean = re.sub(r"[^\d\.]", "", raw)
        try:
            return float(clean)
        except ValueError:
            return None


# --------------------------------------------------------------------------- #
# Evaluation Results
# --------------------------------------------------------------------------- #
class MissingInfoItem(BaseModel):
    rule_id: str
    field_name: str
    question: str
    description: str


class EvaluationResult(BaseModel):
    scheme_key: str
    scheme_title: str = ""
    status: EvaluationStatus
    match_percentage: int
    is_active: bool
    is_application_open: bool
    application_status: ApplicationStatus
    official_expiry_date: Optional[str] = None
    
    # Diagnostics & Explanation
    passed_conditions: List[str] = Field(default_factory=list)
    failed_conditions: List[str] = Field(default_factory=list)
    missing_information: List[MissingInfoItem] = Field(default_factory=list)
    
    # Document tracking
    available_documents: List[str] = Field(default_factory=list)
    missing_documents: List[str] = Field(default_factory=list)
    mandatory_documents_missing: List[str] = Field(default_factory=list)
    
    # Admin review tracking
    admin_review_reasons: List[str] = Field(default_factory=list)
    
    # Audit & citizen links
    source_url: Optional[str] = None
    original_eligibility_text: Optional[str] = None
    explanation: str = ""


# --------------------------------------------------------------------------- #
# Helpers for Matching Conditions
# --------------------------------------------------------------------------- #
def _norm(text: Any) -> str:
    if text is None:
        return ""
    return re.sub(r"\s+", " ", str(text)).strip().casefold()


def _is_doc_present(doc_name: str, citizen_docs: Sequence[str]) -> bool:
    """Check if citizen has a required document using fuzzy substring matching."""
    norm_req = _norm(doc_name)
    for cd in citizen_docs:
        norm_cd = _norm(cd)
        if norm_req in norm_cd or norm_cd in norm_req:
            return True
        # Common synonyms
        if "aadhaar" in norm_req and "aadhaar" in norm_cd:
            return True
        if "income" in norm_req and "income" in norm_cd:
            return True
        if "caste" in norm_req and "caste" in norm_cd:
            return True
        if "domicile" in norm_req and ("domicile" in norm_cd or "residence" in norm_cd):
            return True
        if "marksheet" in norm_req and ("marksheet" in norm_cd or "certificate" in norm_cd):
            return True
    return False


# --------------------------------------------------------------------------- #
# Eligibility Evaluator Engine
# --------------------------------------------------------------------------- #
class EligibilityEngine:
    """
    Evaluates citizen profiles against structured scheme rules.
    Respects AND / OR logic, missing fields, document nuances,
    unclear conditions, expiry, and open/closed application windows.
    """

    def evaluate(
        self,
        scheme: StructuredSchemeRules,
        profile: CitizenProfile,
        allow_unapproved: bool = False,
    ) -> EvaluationResult:
        scheme_key = scheme.scheme_key
        passed_conditions: List[str] = []
        failed_conditions: List[str] = []
        missing_info: List[MissingInfoItem] = []
        admin_review_reasons: List[str] = []

        # ------------------------------------------------------------------- #
        # Rule 1: Expiry & Inactivity Check
        # "Expired or inactive schemes: Never recommend them as currently active."
        # ------------------------------------------------------------------- #
        now_date_str = date.today().isoformat()
        is_expired = False
        if scheme.official_expiry_date and scheme.expiry_verified:
            if scheme.official_expiry_date < now_date_str:
                is_expired = True

        if not scheme.is_active or is_expired:
            reason = "Scheme is officially inactive or expired."
            return EvaluationResult(
                scheme_key=scheme_key,
                status=EvaluationStatus.INELIGIBLE,
                match_percentage=0,
                is_active=False,
                is_application_open=False,
                application_status=ApplicationStatus.CLOSED,
                official_expiry_date=scheme.official_expiry_date,
                failed_conditions=[reason],
                source_url=scheme.source_url,
                original_eligibility_text=scheme.original_eligibility_text,
                explanation=f"This scheme is currently inactive or expired (expired on: {scheme.official_expiry_date or 'N/A'}). It cannot be applied for.",
            )

        # ------------------------------------------------------------------- #
        # Rule 2: Approval Status Check
        # "Don't allow unapproved rules to participate in eligibility matching."
        # ------------------------------------------------------------------- #
        if scheme.approval_status != ApprovalStatus.APPROVED and not allow_unapproved:
            admin_review_reasons.append(
                f"Rules have not yet been approved by admin (current status: {scheme.approval_status.value})."
            )
            return EvaluationResult(
                scheme_key=scheme_key,
                status=EvaluationStatus.NEEDS_ADMIN_REVIEW,
                match_percentage=50,
                is_active=scheme.is_active,
                is_application_open=False,
                application_status=scheme.application_status,
                official_expiry_date=scheme.official_expiry_date,
                admin_review_reasons=admin_review_reasons,
                source_url=scheme.source_url,
                original_eligibility_text=scheme.original_eligibility_text,
                explanation="This scheme has newly extracted rules awaiting administrator review and approval.",
            )

        # ------------------------------------------------------------------- #
        # Rule 3: Application Status (Active Scheme vs Application Open)
        # "Distinction between a scheme being active and its application being open."
        # ------------------------------------------------------------------- #
        is_app_open = True
        app_status = scheme.application_status
        if scheme.application_end_date and scheme.application_end_date < now_date_str:
            is_app_open = False
            app_status = ApplicationStatus.CLOSED
        elif scheme.application_start_date and scheme.application_start_date > now_date_str:
            is_app_open = False
            app_status = ApplicationStatus.UPCOMING
        elif app_status == ApplicationStatus.CLOSED:
            is_app_open = False

        # ------------------------------------------------------------------- #
        # Rule 4: Evaluate Condition Groups (AND / OR Tree)
        # ------------------------------------------------------------------- #
        tree_status, group_passed, group_failed, group_missing, group_unclear = (
            self._evaluate_group(scheme.root_group, profile)
        )
        passed_conditions.extend(group_passed)
        failed_conditions.extend(group_failed)
        missing_info.extend(group_missing)
        admin_review_reasons.extend(group_unclear)

        # ------------------------------------------------------------------- #
        # Rule 5: Documents Evaluation
        # "Documents missing: Don't automatically classify someone as ineligible.
        #  Show the missing documents separately unless the scheme explicitly requires
        #  possession at the time of application."
        # ------------------------------------------------------------------- #
        available_docs: List[str] = []
        missing_docs: List[str] = []
        mandatory_missing: List[str] = []

        for req_doc in scheme.required_documents:
            doc_name = req_doc.doc_name
            if _is_doc_present(doc_name, profile.documents):
                available_docs.append(doc_name)
            else:
                missing_docs.append(doc_name)
                if req_doc.mandatory_at_application:
                    mandatory_missing.append(doc_name)
                    failed_conditions.append(
                        f"Mandatory document required at application missing: '{doc_name}'"
                    )

        # ------------------------------------------------------------------- #
        # Overall Status Determination
        # ------------------------------------------------------------------- #
        if admin_review_reasons:
            final_status = EvaluationStatus.NEEDS_ADMIN_REVIEW
        elif failed_conditions or mandatory_missing:
            final_status = EvaluationStatus.INELIGIBLE
        elif missing_info:
            final_status = EvaluationStatus.NEEDS_MORE_INFORMATION
        else:
            final_status = EvaluationStatus.ELIGIBLE

        # Calculate match percentage
        total_eval_points = len(passed_conditions) + len(failed_conditions) + len(missing_info)
        if total_eval_points == 0:
            match_percentage = 90
        else:
            passed_weight = len(passed_conditions) * 100.0
            partial_weight = len(missing_info) * 40.0
            match_percentage = int((passed_weight + partial_weight) / total_eval_points)
            if final_status == EvaluationStatus.ELIGIBLE:
                match_percentage = max(85, match_percentage)
            elif final_status == EvaluationStatus.INELIGIBLE:
                match_percentage = min(40, match_percentage)

        # Construct citizen-friendly explanation
        explanation = self._build_explanation(
            final_status,
            passed_conditions,
            failed_conditions,
            missing_info,
            missing_docs,
            is_app_open,
            app_status,
        )

        return EvaluationResult(
            scheme_key=scheme_key,
            status=final_status,
            match_percentage=match_percentage,
            is_active=scheme.is_active,
            is_application_open=is_app_open,
            application_status=app_status,
            official_expiry_date=scheme.official_expiry_date,
            passed_conditions=passed_conditions,
            failed_conditions=failed_conditions,
            missing_information=missing_info,
            available_documents=available_docs,
            missing_documents=missing_docs,
            mandatory_documents_missing=mandatory_missing,
            admin_review_reasons=admin_review_reasons,
            source_url=scheme.source_url,
            original_eligibility_text=scheme.original_eligibility_text,
            explanation=explanation,
        )

    # ----------------------------------------------------------------------- #
    # Condition Group Evaluation (Recursive)
    # ----------------------------------------------------------------------- #
    def _evaluate_group(
        self,
        group: ConditionGroup,
        profile: CitizenProfile,
    ) -> Tuple[EvaluationStatus, List[str], List[str], List[MissingInfoItem], List[str]]:
        passed: List[str] = []
        failed: List[str] = []
        missing: List[MissingInfoItem] = []
        unclear: List[str] = []

        # Evaluate direct criteria
        for crit in group.conditions:
            c_status, c_msg, c_miss, c_unc = self._evaluate_criterion(crit, profile)
            if c_status == EvaluationStatus.ELIGIBLE:
                passed.append(c_msg)
            elif c_status == EvaluationStatus.INELIGIBLE:
                failed.append(c_msg)
            elif c_status == EvaluationStatus.NEEDS_MORE_INFORMATION:
                if c_miss:
                    missing.append(c_miss)
            elif c_status == EvaluationStatus.NEEDS_ADMIN_REVIEW:
                if c_unc:
                    unclear.append(c_unc)

        # Evaluate subgroups recursively
        for sub in group.subgroups:
            s_status, s_pass, s_fail, s_miss, s_unc = self._evaluate_group(sub, profile)
            passed.extend(s_pass)
            failed.extend(s_fail)
            missing.extend(s_miss)
            unclear.extend(s_unc)

        # Apply Group Operator
        if group.operator == RuleOperator.AND:
            if unclear:
                return EvaluationStatus.NEEDS_ADMIN_REVIEW, passed, failed, missing, unclear
            if failed:
                return EvaluationStatus.INELIGIBLE, passed, failed, missing, unclear
            if missing:
                return EvaluationStatus.NEEDS_MORE_INFORMATION, passed, failed, missing, unclear
            return EvaluationStatus.ELIGIBLE, passed, failed, missing, unclear

        else:  # RuleOperator.OR
            # In an OR condition, if any alternative passes, the group passes!
            if passed:
                return EvaluationStatus.ELIGIBLE, passed, [], [], unclear
            if missing:
                return EvaluationStatus.NEEDS_MORE_INFORMATION, [], failed, missing, unclear
            if unclear:
                return EvaluationStatus.NEEDS_ADMIN_REVIEW, [], failed, missing, unclear
            return EvaluationStatus.INELIGIBLE, [], failed, [], unclear

    # ----------------------------------------------------------------------- #
    # Single Criterion Evaluation
    # ----------------------------------------------------------------------- #
    def _evaluate_criterion(
        self,
        c: Criterion,
        p: CitizenProfile,
    ) -> Tuple[EvaluationStatus, str, Optional[MissingInfoItem], Optional[str]]:
        # Unclear condition flag
        if not c.is_clear:
            reason = c.unclear_reason or f"Ambiguous condition for rule '{c.rule_id}': {c.description}"
            return EvaluationStatus.NEEDS_ADMIN_REVIEW, "", None, reason

        t = c.condition_type

        # 1. AGE
        if t == ConditionType.AGE:
            age = p.calculate_age()
            if age is None:
                q = c.question or "Please enter your date of birth or age."
                item = MissingInfoItem(
                    rule_id=c.rule_id, field_name="dob", question=q, description=c.description
                )
                return EvaluationStatus.NEEDS_MORE_INFORMATION, "", item, None
            
            if c.min_value is not None and age < c.min_value:
                return (
                    EvaluationStatus.INELIGIBLE,
                    f"Age {age} is below minimum requirement of {int(c.min_value)} years ({c.description})",
                    None,
                    None,
                )
            if c.max_value is not None and age > c.max_value:
                return (
                    EvaluationStatus.INELIGIBLE,
                    f"Age {age} exceeds maximum limit of {int(c.max_value)} years ({c.description})",
                    None,
                    None,
                )
            return (
                EvaluationStatus.ELIGIBLE,
                f"Age {age} meets requirement ({c.description})",
                None,
                None,
            )

        # 2. GENDER
        if t == ConditionType.GENDER:
            # "Match only when the scheme specifies a restriction"
            if not c.allowed_values or any(_norm(v) in ("all", "any", "both") for v in c.allowed_values):
                return EvaluationStatus.ELIGIBLE, "No gender restriction", None, None
            
            if not p.gender:
                q = c.question or "Please specify your gender."
                item = MissingInfoItem(
                    rule_id=c.rule_id, field_name="gender", question=q, description=c.description
                )
                return EvaluationStatus.NEEDS_MORE_INFORMATION, "", item, None
            
            p_gen = _norm(p.gender)
            allowed = [_norm(x) for x in c.allowed_values]
            if p_gen in allowed or (p_gen == "female" and "women" in allowed):
                return EvaluationStatus.ELIGIBLE, f"Gender ({p.gender}) satisfies {c.description}", None, None
            else:
                return (
                    EvaluationStatus.INELIGIBLE,
                    f"Gender '{p.gender}' does not match allowed criteria: {', '.join(c.allowed_values)}",
                    None,
                    None,
                )

        # 3. STATE & RESIDENCE
        if t == ConditionType.STATE:
            allowed = [_norm(s) for s in (c.allowed_values or [])]
            if not allowed or any(a in ("all india", "india", "central", "national", "all") for a in allowed):
                return EvaluationStatus.ELIGIBLE, "Open to all Indian residents", None, None
            
            if not p.state:
                q = c.question or "Please select your state of residence."
                item = MissingInfoItem(
                    rule_id=c.rule_id, field_name="state", question=q, description=c.description
                )
                return EvaluationStatus.NEEDS_MORE_INFORMATION, "", item, None
            
            p_state = _norm(p.state)
            if p_state in allowed:
                return EvaluationStatus.ELIGIBLE, f"Resident of {p.state} ({c.description})", None, None
            else:
                return (
                    EvaluationStatus.INELIGIBLE,
                    f"Scheme is restricted to {', '.join(c.allowed_values)}, but profile state is '{p.state}'",
                    None,
                    None,
                )

        # 4. INCOME
        if t == ConditionType.INCOME:
            income = p.get_parsed_income()
            if income is None:
                q = c.question or "What is your annual family income?"
                item = MissingInfoItem(
                    rule_id=c.rule_id, field_name="annual_income", question=q, description=c.description
                )
                return EvaluationStatus.NEEDS_MORE_INFORMATION, "", item, None
            
            if c.max_value is not None and income > c.max_value:
                return (
                    EvaluationStatus.INELIGIBLE,
                    f"Annual income (₹{int(income):,}) exceeds maximum threshold of ₹{int(c.max_value):,} ({c.description})",
                    None,
                    None,
                )
            if c.min_value is not None and income < c.min_value:
                return (
                    EvaluationStatus.INELIGIBLE,
                    f"Annual income (₹{int(income):,}) is below required minimum of ₹{int(c.min_value):,}",
                    None,
                    None,
                )
            return (
                EvaluationStatus.ELIGIBLE,
                f"Annual income (₹{int(income):,}) meets limit (₹{int(c.max_value or 0):,})",
                None,
                None,
            )

        # 5. OCCUPATION
        if t == ConditionType.OCCUPATION:
            allowed = [_norm(x) for x in (c.allowed_values or [])]
            if not allowed or "any" in allowed or "all" in allowed:
                return EvaluationStatus.ELIGIBLE, "Open to all occupations", None, None
            
            if not p.occupation:
                q = c.question or "What is your current occupation (e.g. Student, Farmer, Self-employed)?"
                item = MissingInfoItem(
                    rule_id=c.rule_id, field_name="occupation", question=q, description=c.description
                )
                return EvaluationStatus.NEEDS_MORE_INFORMATION, "", item, None
            
            p_occ = _norm(p.occupation)
            if any(a in p_occ or p_occ in a for a in allowed):
                return EvaluationStatus.ELIGIBLE, f"Occupation '{p.occupation}' matches requirement", None, None
            return (
                EvaluationStatus.INELIGIBLE,
                f"Occupation '{p.occupation}' does not match scheme requirement ({', '.join(c.allowed_values)})",
                None,
                None,
            )

        # 6. EDUCATION & INSTITUTION
        if t == ConditionType.EDUCATION:
            # Check custom scheme answers first (e.g. specialized course/institution question)
            ans = p.scheme_answers.get(c.rule_id) or p.scheme_answers.get(c.field_name)
            allowed = [_norm(x) for x in (c.allowed_values or [])]
            
            if c.field_name == "institution":
                inst = ans or p.school_or_college_name or p.institution_type
                if not inst:
                    q = c.question or f"Are you enrolled in an approved institution matching: {c.description}?"
                    item = MissingInfoItem(
                        rule_id=c.rule_id, field_name="institution", question=q, description=c.description
                    )
                    return EvaluationStatus.NEEDS_MORE_INFORMATION, "", item, None
                norm_inst = _norm(inst)
                if any(a in norm_inst or norm_inst in a for a in allowed) or ans in (True, "yes", "true", "1"):
                    return EvaluationStatus.ELIGIBLE, f"Institution requirement met: {inst}", None, None
                return EvaluationStatus.INELIGIBLE, f"Institution '{inst}' does not meet requirement: {c.description}", None, None
            
            # General course / study level
            val = ans or p.education_course or p.study_level
            if not val:
                q = c.question or f"What course or education qualification are you currently enrolled in?"
                item = MissingInfoItem(
                    rule_id=c.rule_id, field_name="education_course", question=q, description=c.description
                )
                return EvaluationStatus.NEEDS_MORE_INFORMATION, "", item, None
            
            norm_val = _norm(val)
            if any(a in norm_val or norm_val in a for a in allowed) or ans in (True, "yes", "true", "1"):
                return EvaluationStatus.ELIGIBLE, f"Education qualification '{val}' matches requirement", None, None
            return (
                EvaluationStatus.INELIGIBLE,
                f"Education qualification '{val}' does not match required: {', '.join(c.allowed_values or [c.description])}",
                None,
                None,
            )

        # 7. CATEGORY (Social Category: SC/ST/OBC/EWS/General)
        if t == ConditionType.CATEGORY:
            allowed = [_norm(x) for x in (c.allowed_values or [])]
            if not allowed or "all" in allowed or "any" in allowed or "general" in allowed:
                return EvaluationStatus.ELIGIBLE, "Open to all social categories", None, None
            
            if not p.social_category:
                q = c.question or "Which social category do you belong to (General, OBC, SC, ST, EWS)?"
                item = MissingInfoItem(
                    rule_id=c.rule_id, field_name="social_category", question=q, description=c.description
                )
                return EvaluationStatus.NEEDS_MORE_INFORMATION, "", item, None
            
            p_cat = _norm(p.social_category)
            if any(a == p_cat or a in p_cat or p_cat in a for a in allowed):
                return EvaluationStatus.ELIGIBLE, f"Social category ({p.social_category}) matches scheme", None, None
            return (
                EvaluationStatus.INELIGIBLE,
                f"Category '{p.social_category}' does not match scheme target ({', '.join(c.allowed_values)})",
                None,
                None,
            )

        # 8. COMMUNITY
        if t == ConditionType.COMMUNITY:
            allowed = [_norm(x) for x in (c.allowed_values or [])]
            ans = p.scheme_answers.get(c.rule_id) or p.scheme_answers.get("community") or p.community
            if not ans:
                q = c.question or f"Do you belong to the {', '.join(c.allowed_values or ['specified community'])} community?"
                item = MissingInfoItem(
                    rule_id=c.rule_id, field_name="community", question=q, description=c.description
                )
                return EvaluationStatus.NEEDS_MORE_INFORMATION, "", item, None
            
            norm_comm = _norm(ans)
            if any(a in norm_comm or norm_comm in a for a in allowed) or ans in (True, "yes", "true", "1"):
                return EvaluationStatus.ELIGIBLE, f"Community criteria satisfied: {ans}", None, None
            return (
                EvaluationStatus.INELIGIBLE,
                f"Community '{ans}' does not match required community: {', '.join(c.allowed_values or [])}",
                None,
                None,
            )

        # 9. DISABILITY (PwD)
        if t == ConditionType.DISABILITY:
            is_pwd = p.pwd_status in (True, "yes", "true", "1", "pwd")
            if not is_pwd and p.pwd_status is None:
                q = c.question or "Do you have a Person with Disability (PwD) certificate?"
                item = MissingInfoItem(
                    rule_id=c.rule_id, field_name="pwd_status", question=q, description=c.description
                )
                return EvaluationStatus.NEEDS_MORE_INFORMATION, "", item, None
            
            if not is_pwd:
                return EvaluationStatus.INELIGIBLE, "Scheme is restricted to Persons with Disabilities (PwD)", None, None
            
            if c.min_value is not None:
                pct = p.disability_percentage
                if pct is None:
                    q = c.question or f"What is your certified disability percentage?"
                    item = MissingInfoItem(
                        rule_id=c.rule_id, field_name="disability_percentage", question=q, description=c.description
                    )
                    return EvaluationStatus.NEEDS_MORE_INFORMATION, "", item, None
                if pct < c.min_value:
                    return EvaluationStatus.INELIGIBLE, f"Disability percentage ({pct}%) is below minimum required {c.min_value}%", None, None
            
            return EvaluationStatus.ELIGIBLE, "Disability requirement met", None, None

        # 10. CUSTOM / BESPOKE QUESTIONS
        if t == ConditionType.CUSTOM:
            ans = p.scheme_answers.get(c.rule_id) or p.scheme_answers.get(c.field_name)
            if ans is None:
                q = c.question or c.description
                item = MissingInfoItem(
                    rule_id=c.rule_id, field_name=c.field_name, question=q, description=c.description
                )
                return EvaluationStatus.NEEDS_MORE_INFORMATION, "", item, None
            
            if c.allowed_values:
                norm_ans = _norm(ans)
                if any(_norm(a) == norm_ans for a in c.allowed_values) or ans in (True, "yes", "true", "1"):
                    return EvaluationStatus.ELIGIBLE, f"Condition satisfied: {c.description}", None, None
                return EvaluationStatus.INELIGIBLE, f"Requirement not met: {c.description}", None, None
            
            if ans in (True, "yes", "true", "1"):
                return EvaluationStatus.ELIGIBLE, f"Condition confirmed: {c.description}", None, None
            return EvaluationStatus.INELIGIBLE, f"Citizen answered no to: {c.description}", None, None

        # Fallback for unhandled type
        return EvaluationStatus.ELIGIBLE, f"Rule passed: {c.description}", None, None

    # ----------------------------------------------------------------------- #
    # Citizen Explanation Formatter
    # ----------------------------------------------------------------------- #
    def _build_explanation(
        self,
        status: EvaluationStatus,
        passed: List[str],
        failed: List[str],
        missing: List[MissingInfoItem],
        missing_docs: List[str],
        is_app_open: bool,
        app_status: ApplicationStatus,
    ) -> str:
        lines: List[str] = []

        if not is_app_open:
            if app_status == ApplicationStatus.CLOSED:
                lines.append("Note: The application window for this scheme is currently CLOSED.")
            elif app_status == ApplicationStatus.UPCOMING:
                lines.append("Note: The application window for this scheme is UPCOMING.")

        if status == EvaluationStatus.ELIGIBLE:
            lines.append("You appear eligible for this scheme!")
            if passed:
                lines.append(f"Criteria met: {'; '.join(passed[:3])}")
            if missing_docs:
                lines.append(
                    f"Required documents to prepare before applying: {', '.join(missing_docs)}"
                )
        elif status == EvaluationStatus.NEEDS_MORE_INFORMATION:
            lines.append("We need a few more details to confirm your eligibility:")
            for m in missing[:3]:
                lines.append(f"- {m.question}")
        elif status == EvaluationStatus.NEEDS_ADMIN_REVIEW:
            lines.append("This scheme's criteria are currently undergoing verification by administrators.")
        elif status == EvaluationStatus.INELIGIBLE:
            lines.append("You do not currently meet the eligibility criteria for this scheme:")
            for f in failed[:3]:
                lines.append(f"- {f}")

        return "\n".join(lines)


# --------------------------------------------------------------------------- #
# Rule Builder / Extractor with Validation & Verification Auditing
# --------------------------------------------------------------------------- #
class StructuredRuleExtractor:
    """
    Extracts structured eligibility conditions and documents from raw texts,
    validates criteria logic, and populates audit metadata.
    """

    @classmethod
    def extract_from_scheme(
        cls,
        scheme_key: str,
        name: str,
        state: Optional[str],
        raw_eligibility: str,
        raw_documents: str,
        source_url: Optional[str] = None,
        auto_approve: bool = False,
    ) -> StructuredSchemeRules:
        elig_text = (raw_eligibility or "").strip()
        docs_text = (raw_documents or "").strip()

        conditions: List[Criterion] = []
        warnings: List[str] = []
        rule_counter = 1

        # 1. State condition
        if state and _norm(state) not in ("all india", "national", "central", "all"):
            conditions.append(
                Criterion(
                    rule_id=f"{scheme_key}_state_{rule_counter}",
                    condition_type=ConditionType.STATE,
                    field_name="state",
                    description=f"Must be a resident of {state}",
                    allowed_values=[state],
                    question=f"Are you a permanent resident of {state}?",
                    is_clear=True,
                )
            )
            rule_counter += 1

        # 2. Heuristic extraction of Age range (e.g. "between 18 and 35 years", "above 18 years", "more than 60 years", "8-19")
        age_between = re.search(r"(?:between|age(?:d)?)\s*(\d{1,2})\s*(?:and|to|-)\s*(\d{1,2})\s*(?:years|yrs)?", elig_text, re.I)
        if age_between:
            min_a, max_a = float(age_between.group(1)), float(age_between.group(2))
            if min_a <= max_a:
                conditions.append(
                    Criterion(
                        rule_id=f"{scheme_key}_age_{rule_counter}",
                        condition_type=ConditionType.AGE,
                        field_name="dob",
                        description=f"Age between {int(min_a)} and {int(max_a)} years",
                        min_value=min_a,
                        max_value=max_a,
                        question=f"Is your age between {int(min_a)} and {int(max_a)}?",
                        is_clear=True,
                    )
                )
                rule_counter += 1
            else:
                warnings.append(f"Inconsistent age range found: {min_a} > {max_a}")
        else:
            above_age = re.search(r"(?:above|more\s*than|minimum|at least|age\s*is|age\s*should\s*be\s*more\s*than)\s*(\d{1,2})\s*(?:years|yrs)?", elig_text, re.I)
            if above_age:
                min_a = float(above_age.group(1))
                conditions.append(
                    Criterion(
                        rule_id=f"{scheme_key}_age_{rule_counter}",
                        condition_type=ConditionType.AGE,
                        field_name="dob",
                        description=f"Minimum age {int(min_a)} years",
                        min_value=min_a,
                        question="What is your date of birth or age?",
                        is_clear=True,
                    )
                )
                rule_counter += 1

        # 2b. Senior citizen / Old age / Pension age heuristic
        if re.search(r"\b(vridhavastha|vridh|senior\s*citizen|old\s*age\s*pension)\b", elig_text + " " + name, re.I) and not any(c.condition_type == ConditionType.AGE for c in conditions):
            conditions.append(
                Criterion(
                    rule_id=f"{scheme_key}_age_{rule_counter}",
                    condition_type=ConditionType.AGE,
                    field_name="dob",
                    description="Age must be 60 years or above (Senior Citizen / Old Age)",
                    min_value=60.0,
                    question="Are you 60 years of age or older?",
                    is_clear=True,
                )
            )
            rule_counter += 1

        # 3. Gender restriction heuristic
        if re.search(r"\b(women|female|girl|widow|kanya|kalyani)\b", elig_text + " " + name, re.I) and not re.search(r"\bmen and women\b", elig_text, re.I):
            conditions.append(
                Criterion(
                    rule_id=f"{scheme_key}_gender_{rule_counter}",
                    condition_type=ConditionType.GENDER,
                    field_name="gender",
                    description="Exclusively for Women / Girls",
                    allowed_values=["Female"],
                    question="What is your gender?",
                    is_clear=True,
                )
            )
            rule_counter += 1

        # 4. Income limit heuristic (e.g. "income does not exceed 2.5 lakh" or "income less than 2,00,000")
        inc_match = re.search(r"income\s*(?:not\s*exceed(?:ing)?|less\s*than|below|up\s*to)\s*(?:rs\.?|inr|₹)?\s*([\d\.,]+)\s*(lakh|lac)?", elig_text, re.I)
        if inc_match:
            raw_amt = inc_match.group(1).replace(",", "")
            is_lakh = bool(inc_match.group(2))
            try:
                limit = float(raw_amt) * (100000.0 if is_lakh else 1.0)
                conditions.append(
                    Criterion(
                        rule_id=f"{scheme_key}_income_{rule_counter}",
                        condition_type=ConditionType.INCOME,
                        field_name="annual_income",
                        description=f"Annual family income up to ₹{int(limit):,}",
                        max_value=limit,
                        question=f"Is your annual family income below ₹{int(limit):,}?",
                        is_clear=True,
                    )
                )
                rule_counter += 1
            except ValueError:
                warnings.append(f"Failed to parse income limit: {inc_match.group(0)}")

        # 5. Social Category (SC / ST / OBC / Minority)
        if re.search(r"\b(sc\s*/\s*st|scheduled\s*caste|scheduled\s*tribe)\b", elig_text, re.I):
            conditions.append(
                Criterion(
                    rule_id=f"{scheme_key}_cat_{rule_counter}",
                    condition_type=ConditionType.CATEGORY,
                    field_name="social_category",
                    description="Belong to SC or ST category",
                    allowed_values=["SC", "ST"],
                    question="Do you belong to SC or ST category?",
                    is_clear=True,
                )
            )
            rule_counter += 1
        elif re.search(r"\bobc\b", elig_text, re.I):
            conditions.append(
                Criterion(
                    rule_id=f"{scheme_key}_cat_{rule_counter}",
                    condition_type=ConditionType.CATEGORY,
                    field_name="social_category",
                    description="Belong to OBC category",
                    allowed_values=["OBC"],
                    question="Do you belong to OBC category?",
                    is_clear=True,
                )
            )
            rule_counter += 1

        # 6. Community (e.g. Brahmin, Minority, etc.)
        if re.search(r"\bbrahmin\b", elig_text, re.I):
            conditions.append(
                Criterion(
                    rule_id=f"{scheme_key}_comm_{rule_counter}",
                    condition_type=ConditionType.COMMUNITY,
                    field_name="community",
                    description="Belong to Brahmin community",
                    allowed_values=["Brahmin"],
                    question="Do you belong to the Brahmin community?",
                    is_clear=True,
                )
            )
            rule_counter += 1
        elif re.search(r"\b(minority|alpasankhyak|alpsankhyak)\b", elig_text + " " + name, re.I):
            conditions.append(
                Criterion(
                    rule_id=f"{scheme_key}_minority_{rule_counter}",
                    condition_type=ConditionType.CUSTOM,
                    field_name="minority_status",
                    description="Belong to a recognized Minority Community",
                    allowed_values=["Yes", "yes"],
                    question="Do you belong to a recognized minority community?",
                    is_clear=True,
                )
            )
            rule_counter += 1

        # 7. Occupation heuristic (Student, Farmer, Artisan, Worker, etc.)
        if re.search(r"\b(student|scholarship|vidyarthi|shiksha|chhatravritti)\b", elig_text + " " + name, re.I):
            conditions.append(
                Criterion(
                    rule_id=f"{scheme_key}_occ_{rule_counter}",
                    condition_type=ConditionType.OCCUPATION,
                    field_name="occupation",
                    description="Must be a student enrolled in school/college/course",
                    allowed_values=["Student"],
                    question="Are you currently a student?",
                    is_clear=True,
                )
            )
            rule_counter += 1
        elif re.search(r"\b(farmer|cultivator|kisan|krishak)\b", elig_text + " " + name, re.I):
            conditions.append(
                Criterion(
                    rule_id=f"{scheme_key}_occ_{rule_counter}",
                    condition_type=ConditionType.OCCUPATION,
                    field_name="occupation",
                    description="Must be a farmer or agriculturalist",
                    allowed_values=["Farmer"],
                    question="Are you a farmer or cultivator?",
                    is_clear=True,
                )
            )
            rule_counter += 1
        elif re.search(r"\b(construction\s*worker|shramik|karmakaar|labor\s*department|labour\s*department|unorganized\s*worker)\b", elig_text + " " + name, re.I):
            conditions.append(
                Criterion(
                    rule_id=f"{scheme_key}_occ_{rule_counter}",
                    condition_type=ConditionType.OCCUPATION,
                    field_name="occupation",
                    description="Must be a registered construction/labour/unorganized worker",
                    allowed_values=["Daily Wage / Construction", "Labor", "Worker", "Unorganized Worker"],
                    question="Are you or your parent a registered labour/construction worker?",
                    is_clear=True,
                )
            )
            rule_counter += 1

        # 7b. Disability condition (Divyang)
        if re.search(r"\b(disabled|disability|divyang|handicapped|nisaktjan|visually\s*challenged|orthopedic)\b", elig_text + " " + name, re.I):
            conditions.append(
                Criterion(
                    rule_id=f"{scheme_key}_pwd_{rule_counter}",
                    condition_type=ConditionType.DISABILITY,
                    field_name="pwd_status",
                    description="Must have a disability (PwD)",
                    allowed_values=["Yes", "yes"],
                    question="Do you have a person with disability (PwD) certificate?",
                    is_clear=True,
                )
            )
            rule_counter += 1

        # 7c. Death / Funeral / Ex-gratia specific condition
        if re.search(r"\b(antim\s*sanskar|antyeshti|funeral|cremat|death\s*certificate|deceased)\b", elig_text + " " + name, re.I):
            conditions.append(
                Criterion(
                    rule_id=f"{scheme_key}_event_{rule_counter}",
                    condition_type=ConditionType.CUSTOM,
                    field_name="family_bereavement_status",
                    description="Requires unfortunate death/bereavement of registered family member",
                    allowed_values=["Yes", "deceased"],
                    question="Has there been an unfortunate death of an eligible registered worker in the family?",
                    is_mandatory=True,
                    is_clear=True,
                )
            )
            rule_counter += 1

        # 8. Check for ambiguity/unclear condition
        has_unclear = False
        if len(elig_text) > 30 and not conditions:
            # Complex text where heuristic couldn't safely extract structured rules
            conditions.append(
                Criterion(
                    rule_id=f"{scheme_key}_custom_{rule_counter}",
                    condition_type=ConditionType.CUSTOM,
                    field_name="general_eligibility",
                    description=elig_text[:200] + ("..." if len(elig_text) > 200 else ""),
                    is_clear=False,
                    unclear_reason="Text contains descriptive conditions requiring manual admin rule formulation.",
                )
            )
            has_unclear = True
            warnings.append("Eligibility text contains unstructured rules marked for admin review.")

        # Parse required documents
        required_docs: List[DocumentRequirement] = []
        if docs_text:
            # Split by line breaks, bullets or numbered items
            raw_doc_items = re.split(r"[\n\r•\-\d\.]+\s*", docs_text)
            for item in raw_doc_items:
                clean_item = item.strip(" .,-()").strip()
                if len(clean_item) > 3:
                    # Detect if mandatory at application
                    mandatory = bool(re.search(r"mandatory|essential|must possess|at the time of application", clean_item, re.I))
                    required_docs.append(
                        DocumentRequirement(
                            doc_name=clean_item,
                            mandatory_at_application=mandatory,
                            description=clean_item,
                        )
                    )

        # Build StructuredSchemeRules
        approval_status = ApprovalStatus.APPROVED if auto_approve and not has_unclear else (
            ApprovalStatus.NEEDS_ADMIN_REVIEW if has_unclear else ApprovalStatus.PENDING_REVIEW
        )

        metadata = ExtractionMetadata(
            llm_model="rule-heuristic-extractor-v1",
            llm_version="1.0.0",
            extracted_at=datetime.now(timezone.utc),
            confidence_score=0.95 if not has_unclear else 0.40,
            warnings=warnings,
        )

        root_group = ConditionGroup(
            operator=RuleOperator.AND,
            conditions=conditions,
        )

        return StructuredSchemeRules(
            scheme_key=scheme_key,
            rule_version=1,
            approval_status=approval_status,
            root_group=root_group,
            required_documents=required_docs,
            original_eligibility_text=raw_eligibility,
            original_documents_text=raw_documents,
            source_url=source_url,
            is_active=True,
            application_status=ApplicationStatus.OPEN,
            last_seen_at=datetime.now(timezone.utc),
            last_verified_at=datetime.now(timezone.utc) if auto_approve else None,
            extraction_metadata=metadata,
        )
