"""
Unit tests verifying the SchemeSathi Eligibility Rules Engine.
"""

from datetime import date, timedelta
from eligibility_engine import (
    ApprovalStatus,
    ApplicationStatus,
    CitizenProfile,
    ConditionGroup,
    ConditionType,
    Criterion,
    DocumentRequirement,
    EligibilityEngine,
    EvaluationStatus,
    RuleOperator,
    StructuredSchemeRules,
    StructuredRuleExtractor,
)


def create_vedavyasa_scheme(approved: bool = True) -> StructuredSchemeRules:
    """
    Creates the Veda Vyasa Scheme as specified in user requirements:
    - State/residence: Andhra Pradesh
    - Community: Brahmin
    - Age: 8–19
    - Education: Full-time Vedic course
    - Institution: Approved Veda Pathasala
    """
    conditions = [
        Criterion(
            rule_id="vv_state",
            condition_type=ConditionType.STATE,
            field_name="state",
            description="Must be resident of Andhra Pradesh",
            allowed_values=["Andhra Pradesh"],
            question="Are you a resident of Andhra Pradesh?",
        ),
        Criterion(
            rule_id="vv_community",
            condition_type=ConditionType.COMMUNITY,
            field_name="community",
            description="Must belong to the Brahmin community",
            allowed_values=["Brahmin"],
            question="Do you belong to the Brahmin community?",
        ),
        Criterion(
            rule_id="vv_age",
            condition_type=ConditionType.AGE,
            field_name="dob",
            description="Age must be between 8 and 19 years",
            min_value=8,
            max_value=19,
            question="What is your date of birth or age?",
        ),
        Criterion(
            rule_id="vv_edu",
            condition_type=ConditionType.EDUCATION,
            field_name="education_course",
            description="Must be enrolled in a Full-time Vedic course",
            allowed_values=["Full-time Vedic course", "Veda Study", "Vedic"],
            question="Are you pursuing a full-time Vedic course?",
        ),
        Criterion(
            rule_id="vv_inst",
            condition_type=ConditionType.EDUCATION,
            field_name="institution",
            description="Must study at an Approved Veda Pathasala",
            allowed_values=["Approved Veda Pathasala", "Veda Pathasala"],
            question="Is your institution an Approved Veda Pathasala?",
        ),
    ]

    return StructuredSchemeRules(
        scheme_key="veda_vyasa_scheme",
        rule_version=1,
        approval_status=ApprovalStatus.APPROVED if approved else ApprovalStatus.PENDING_REVIEW,
        root_group=ConditionGroup(operator=RuleOperator.AND, conditions=conditions),
        required_documents=[
            DocumentRequirement(doc_name="Aadhaar Card", mandatory_at_application=False),
            DocumentRequirement(doc_name="Veda Pathasala Bonafide Certificate", mandatory_at_application=True),
        ],
        original_eligibility_text="Applicants must be residing in Andhra Pradesh belonging to Brahmin community, aged 8-19, pursuing full-time Vedic studies in an approved Veda Pathasala.",
        original_documents_text="Aadhaar card. Mandatory Veda Pathasala Bonafide Certificate at the time of application.",
        source_url="https://andhrabrahmin.ap.gov.in/schemes/vedavyasa.aspx",
        is_active=True,
        application_status=ApplicationStatus.OPEN,
    )


def test_vedavyasa_fully_eligible():
    engine = EligibilityEngine()
    scheme = create_vedavyasa_scheme(approved=True)

    citizen = CitizenProfile(
        full_name="Raghav Sharma",
        dob="2012-04-10",  # Age ~14
        state="Andhra Pradesh",
        community="Brahmin",
        education_course="Full-time Vedic course",
        school_or_college_name="Approved Veda Pathasala",
        documents=["Aadhaar Card", "Veda Pathasala Bonafide Certificate"],
    )

    result = engine.evaluate(scheme, citizen)
    assert result.status == EvaluationStatus.ELIGIBLE, f"Expected ELIGIBLE, got {result.status}"
    assert result.match_percentage >= 85
    assert len(result.passed_conditions) >= 5
    assert len(result.failed_conditions) == 0
    print("[PASS] test_vedavyasa_fully_eligible")


def test_missing_information_returns_needs_more_info():
    """Missing citizen information should return needs_more_information, not ineligible."""
    engine = EligibilityEngine()
    scheme = create_vedavyasa_scheme(approved=True)

    # Citizen is in AP and Brahmin, but age and institution not yet answered
    citizen = CitizenProfile(
        full_name="Karthik",
        state="Andhra Pradesh",
        community="Brahmin",
        documents=["Aadhaar Card", "Veda Pathasala Bonafide Certificate"],
    )

    result = engine.evaluate(scheme, citizen)
    assert result.status == EvaluationStatus.NEEDS_MORE_INFORMATION, f"Expected NEEDS_MORE_INFORMATION, got {result.status}"
    assert len(result.missing_information) > 0
    missing_fields = [m.field_name for m in result.missing_information]
    assert "dob" in missing_fields
    assert "education_course" in missing_fields
    print("[PASS] test_missing_information_returns_needs_more_info")


def test_age_out_of_range_ineligible():
    engine = EligibilityEngine()
    scheme = create_vedavyasa_scheme(approved=True)

    # Citizen age 25 (born 2001) -> out of 8-19 range
    citizen = CitizenProfile(
        full_name="Suresh",
        dob="2001-01-01",
        state="Andhra Pradesh",
        community="Brahmin",
        education_course="Full-time Vedic course",
        school_or_college_name="Approved Veda Pathasala",
        documents=["Aadhaar Card", "Veda Pathasala Bonafide Certificate"],
    )

    result = engine.evaluate(scheme, citizen)
    assert result.status == EvaluationStatus.INELIGIBLE
    assert any("Age" in f for f in result.failed_conditions)
    print("[PASS] test_age_out_of_range_ineligible")


def test_or_conditions_evaluation():
    """OR conditions: passing one is sufficient."""
    engine = EligibilityEngine()

    or_group = ConditionGroup(
        operator=RuleOperator.OR,
        conditions=[
            Criterion(
                rule_id="crit_student",
                condition_type=ConditionType.OCCUPATION,
                field_name="occupation",
                description="Student",
                allowed_values=["Student"],
            ),
            Criterion(
                rule_id="crit_farmer",
                condition_type=ConditionType.OCCUPATION,
                field_name="occupation",
                description="Farmer",
                allowed_values=["Farmer"],
            ),
        ],
    )

    scheme = StructuredSchemeRules(
        scheme_key="student_or_farmer_aid",
        rule_version=1,
        approval_status=ApprovalStatus.APPROVED,
        root_group=or_group,
        is_active=True,
    )

    # Citizen is Farmer (passes the second condition of OR group)
    citizen = CitizenProfile(occupation="Farmer")
    result = engine.evaluate(scheme, citizen)
    assert result.status == EvaluationStatus.ELIGIBLE
    print("[PASS] test_or_conditions_evaluation")


def test_missing_documents_non_mandatory_stays_eligible():
    """
    Documents missing: Don't automatically classify someone as ineligible.
    Show the missing documents separately unless the scheme explicitly requires
    possession at the time of application.
    """
    engine = EligibilityEngine()

    scheme = StructuredSchemeRules(
        scheme_key="ration_card_scheme",
        approval_status=ApprovalStatus.APPROVED,
        root_group=ConditionGroup(
            operator=RuleOperator.AND,
            conditions=[
                Criterion(
                    rule_id="inc",
                    condition_type=ConditionType.INCOME,
                    field_name="annual_income",
                    description="Income under 2 Lakh",
                    max_value=200000,
                )
            ],
        ),
        required_documents=[
            DocumentRequirement(doc_name="Electricity Bill", mandatory_at_application=False),
            DocumentRequirement(doc_name="Passport Photo", mandatory_at_application=False),
        ],
        is_active=True,
    )

    citizen = CitizenProfile(annual_income="1.5 Lakh", documents=[])
    result = engine.evaluate(scheme, citizen)

    # Citizen is still eligible, but missing documents are tracked
    assert result.status == EvaluationStatus.ELIGIBLE
    assert "Electricity Bill" in result.missing_documents
    assert "Passport Photo" in result.missing_documents
    assert len(result.mandatory_documents_missing) == 0
    print("[PASS] test_missing_documents_non_mandatory_stays_eligible")


def test_mandatory_document_at_application_missing_causes_ineligibility():
    engine = EligibilityEngine()

    scheme = StructuredSchemeRules(
        scheme_key="special_grant",
        approval_status=ApprovalStatus.APPROVED,
        root_group=ConditionGroup(operator=RuleOperator.AND, conditions=[]),
        required_documents=[
            DocumentRequirement(
                doc_name="Caste Certificate",
                mandatory_at_application=True,
                description="Mandatory at time of application",
            )
        ],
        is_active=True,
    )

    citizen = CitizenProfile(documents=["Aadhaar Card"])
    result = engine.evaluate(scheme, citizen)
    assert result.status == EvaluationStatus.INELIGIBLE
    assert "Caste Certificate" in result.mandatory_documents_missing
    print("[PASS] test_mandatory_document_at_application_missing_causes_ineligibility")


def test_expired_or_inactive_schemes_never_recommended():
    """Expired or inactive schemes: Never recommend them as currently active."""
    engine = EligibilityEngine()

    # Expired scheme
    yesterday = (date.today() - timedelta(days=1)).isoformat()
    scheme_expired = StructuredSchemeRules(
        scheme_key="past_scheme",
        approval_status=ApprovalStatus.APPROVED,
        root_group=ConditionGroup(operator=RuleOperator.AND, conditions=[]),
        is_active=True,
        official_expiry_date=yesterday,
        expiry_verified=True,
    )

    citizen = CitizenProfile()
    result = engine.evaluate(scheme_expired, citizen)
    assert result.status == EvaluationStatus.INELIGIBLE
    assert result.is_active is False
    assert result.is_application_open is False
    print("[PASS] test_expired_or_inactive_schemes_never_recommended")


def test_active_scheme_with_closed_application_window():
    """
    Distinction between a scheme being active and its application being open.
    Ongoing scheme, but application window is closed.
    """
    engine = EligibilityEngine()

    yesterday = (date.today() - timedelta(days=2)).isoformat()
    scheme = StructuredSchemeRules(
        scheme_key="annual_scholarship",
        approval_status=ApprovalStatus.APPROVED,
        root_group=ConditionGroup(operator=RuleOperator.AND, conditions=[]),
        is_active=True,
        application_status=ApplicationStatus.CLOSED,
        application_end_date=yesterday,
    )

    citizen = CitizenProfile()
    result = engine.evaluate(scheme, citizen)
    assert result.status == EvaluationStatus.ELIGIBLE  # Citizen qualifies
    assert result.is_active is True                    # Scheme is active policy
    assert result.is_application_open is False         # But application is CLOSED
    assert result.application_status == ApplicationStatus.CLOSED
    assert "CLOSED" in result.explanation
    print("[PASS] test_active_scheme_with_closed_application_window")


def test_unapproved_rules_cannot_participate_in_matching():
    """Don't allow unapproved rules to participate in eligibility matching."""
    engine = EligibilityEngine()
    scheme = create_vedavyasa_scheme(approved=False)  # pending review

    citizen = CitizenProfile(
        dob="2012-04-10",
        state="Andhra Pradesh",
        community="Brahmin",
        education_course="Full-time Vedic course",
        school_or_college_name="Approved Veda Pathasala",
    )

    result = engine.evaluate(scheme, citizen, allow_unapproved=False)
    assert result.status == EvaluationStatus.NEEDS_ADMIN_REVIEW
    assert any("not yet been approved" in r for r in result.admin_review_reasons)
    print("[PASS] test_unapproved_rules_cannot_participate_in_matching")


def test_structured_rule_extractor_preserves_text_and_audit():
    rules = StructuredRuleExtractor.extract_from_scheme(
        scheme_key="test_scheme_123",
        name="State Merit Scholarship for Girls",
        state="Karnataka",
        raw_eligibility="Open for female students between age 14 and 20 years residing in Karnataka with family income below 2.5 Lakh.",
        raw_documents="Aadhaar Card, Income Certificate, Previous Year Marksheet.",
        source_url="https://scholarships.gov.in/test",
    )

    assert rules.scheme_key == "test_scheme_123"
    assert rules.original_eligibility_text.startswith("Open for female")
    assert rules.original_documents_text.startswith("Aadhaar Card")
    assert rules.source_url == "https://scholarships.gov.in/test"
    assert rules.extraction_metadata is not None
    assert rules.extraction_metadata.llm_model is not None
    assert rules.approval_status == ApprovalStatus.PENDING_REVIEW

    # Check extracted criteria types
    types = [c.condition_type for c in rules.root_group.conditions]
    assert ConditionType.STATE in types
    assert ConditionType.AGE in types
    assert ConditionType.GENDER in types
    assert ConditionType.INCOME in types
    assert ConditionType.OCCUPATION in types

    # Check age extracted correctly: min 14, max 20
    age_rule = next(c for c in rules.root_group.conditions if c.condition_type == ConditionType.AGE)
    assert age_rule.min_value == 14.0
    assert age_rule.max_value == 20.0

    # Check income extracted: 2.5 Lakh = 250,000
    income_rule = next(c for c in rules.root_group.conditions if c.condition_type == ConditionType.INCOME)
    assert income_rule.max_value == 250000.0

    print("[PASS] test_structured_rule_extractor_preserves_text_and_audit")


if __name__ == "__main__":
    test_vedavyasa_fully_eligible()
    test_missing_information_returns_needs_more_info()
    test_age_out_of_range_ineligible()
    test_or_conditions_evaluation()
    test_missing_documents_non_mandatory_stays_eligible()
    test_mandatory_document_at_application_missing_causes_ineligibility()
    test_expired_or_inactive_schemes_never_recommended()
    test_active_scheme_with_closed_application_window()
    test_unapproved_rules_cannot_participate_in_matching()
    test_structured_rule_extractor_preserves_text_and_audit()
    print("\nALL 10 ELIGIBILITY ENGINE TESTS PASSED!")
