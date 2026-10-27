import 'package:flutter/material.dart';
import 'form_service.dart';

/// 5-Step Citizen Profile Setup Form matching Stitch Civic Trust & Discovery design
class CitizenProfileSetupPage extends StatefulWidget {
  final String? initialEmail;

  const CitizenProfileSetupPage({super.key, this.initialEmail});

  @override
  State<CitizenProfileSetupPage> createState() =>
      _CitizenProfileSetupPageState();
}

class _CitizenProfileSetupPageState extends State<CitizenProfileSetupPage> {
  int _currentStep = 1; // 1 to 5
  bool _isSubmitting = false;

  // Design Theme Colors
  static const Color primaryNavy = Color(0xFF0D2A4A);
  static const Color primaryNavyDark = Color(0xFF071B30);
  static const Color slateBorder = Color(0xFFCBD5E1);
  static const Color neutralBg = Color(0xFFF8FAFC);
  static const Color textMain = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF475569);
  static const Color textSoft = Color(0xFF64748B);
  static const Color accentBlue = Color(0xFF005DB7);

  // STEP 1 CONTROLLERS & STATE
  final TextEditingController _fullNameController =
      TextEditingController(text: 'Rahul Sharma');
  final TextEditingController _dobController =
      TextEditingController(text: '14 / 08 / 1999');
  String _selectedGender = 'Male';
  String _selectedMaritalStatus = 'Never Married';

  // STEP 2 STATE
  String _selectedState = 'Madhya Pradesh';
  String _selectedDistrict = 'Bhopal';
  final TextEditingController _tehsilController = TextEditingController();
  String _selectedAreaType = 'rural'; // rural, urban, peri_urban
  String _selectedDomicileStatus = 'yes'; // yes, in_progress, no
  bool _localResidenceOutside = false;
  final TextEditingController _familyIdController = TextEditingController();
  bool _hasFamilyId = false;

  // STEP 3 STATE
  String _selectedOccupation = 'Student';
  String _studyLevel = 'College / University';
  String _selectedCourse = 'Undergraduate Year 2 (B.Tech / B.Sc / B.A / B.Com)';
  String _institutionType = 'Government';
  final TextEditingController _schoolCollegeController =
      TextEditingController();

  // STEP 4 STATE
  String _socialCategory = 'General (Unreserved)';
  String _casteCertStatus = 'Yes (Available)';
  String _pwdStatus = 'No';
  String _minorityStatus = 'No';
  String _incomeCertStatus = 'Yes (Available & Valid)';

  // STEP 5 STATE: Selected documents set
  final Set<String> _selectedDocuments = {
    'Aadhaar Card (UIDAI)',
    'Permanent Account Number (PAN) Card',
    'Samagra Family ID',
    'Aadhaar-Seeded Bank Account',
  };

  final List<String> _statesList = [
    'Andhra Pradesh',
    'Arunachal Pradesh',
    'Assam',
    'Bihar',
    'Chhattisgarh',
    'Goa',
    'Gujarat',
    'Haryana',
    'Himachal Pradesh',
    'Jharkhand',
    'Karnataka',
    'Kerala',
    'Madhya Pradesh',
    'Maharashtra',
    'Manipur',
    'Meghalaya',
    'Mizoram',
    'Nagaland',
    'Odisha',
    'Punjab',
    'Rajasthan',
    'Sikkim',
    'Tamil Nadu',
    'Telangana',
    'Tripura',
    'Uttar Pradesh',
    'Uttarakhand',
    'West Bengal',
    'Delhi (NCT)',
    'Jammu and Kashmir',
    'Ladakh',
  ];

  final List<String> _districtsList = [
    'Bhopal',
    'Indore',
    'Gwalior',
    'Jabalpur',
    'Ujjain',
    'Sehore',
    'Raisen',
    'Dewas',
    'Sagar',
    'Rewa',
    'Other'
  ];

  final List<String> _coursesList = [
    'Undergraduate Year 2 (B.Tech / B.Sc / B.A / B.Com)',
    'Class 9th (Secondary School)',
    'Class 10th (Matriculation)',
    'Class 11th (Higher Secondary 1st Year)',
    'Class 12th (Higher Secondary 2nd Year)',
    'Undergraduate Year 1',
    'Undergraduate Year 3 (Final Year)',
    'Postgraduate Year 1 (Master\'s)',
    'Postgraduate Year 2 (Final Year)',
    'Polytechnic / ITI Trade Course',
    'Doctoral Scholar / PhD Research',
  ];

  final List<String> _categoriesList = [
    'General (Unreserved)',
    'OBC (Other Backward Class)',
    'SC (Scheduled Caste)',
    'ST (Scheduled Tribe)',
    'EWS (Economically Weaker Section)',
    'Not Sure / General / Unspecified'
  ];

  @override
  void dispose() {
    _fullNameController.dispose();
    _dobController.dispose();
    _tehsilController.dispose();
    _familyIdController.dispose();
    _schoolCollegeController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep == 1) {
      if (_fullNameController.text.trim().isEmpty) {
        _showError('Please enter your full legal name as per ID');
        return;
      }
    }
    if (_currentStep < 5) {
      setState(() => _currentStep++);
    } else {
      _submitForm();
    }
  }

  void _prevStep() {
    if (_currentStep > 1) {
      setState(() => _currentStep--);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  Future<void> _submitForm() async {
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      final formData = CitizenFormData(
        fullName: _fullNameController.text.trim(),
        dob: _dobController.text.trim(),
        gender: _selectedGender,
        maritalStatus: _selectedMaritalStatus,
        state: _selectedState,
        district: _selectedDistrict,
        tehsil: _tehsilController.text.trim(),
        areaType: _selectedAreaType,
        domicileStatus: _selectedDomicileStatus,
        localResidenceOutside: _localResidenceOutside,
        familyId: _hasFamilyId ? _familyIdController.text.trim() : '',
        occupation: _selectedOccupation,
        studyLevel: _studyLevel,
        educationCourse: _selectedCourse,
        institutionType: _institutionType,
        schoolOrCollegeName: _schoolCollegeController.text.trim(),
        socialCategory: _socialCategory,
        casteCertificateStatus: _casteCertStatus,
        pwdStatus: _pwdStatus,
        minorityStatus: _minorityStatus,
        incomeCertificateStatus: _incomeCertStatus,
        documents: _selectedDocuments.toList(),
        email: widget.initialEmail,
      );

      // Cache user selected state locally for quick access
      FormService.cachedUserState = _selectedState;
      await FormService.instance.markProfileCompletedLocally(
        email: widget.initialEmail,
        state: _selectedState,
      );

      final result = await FormService.instance.submitCitizenProfile(formData);

      if (!mounted) return;

      final message = result['message'] ?? 'Profile Saved Successfully!';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ $message Searching matching schemes...'),
          backgroundColor: primaryNavy,
          duration: const Duration(seconds: 2),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 1000));
      if (!mounted) return;

      Navigator.of(context).pushReplacementNamed(
        '/home',
        arguments: _fullNameController.text.trim().isNotEmpty
            ? _fullNameController.text.trim()
            : null,
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Error saving profile: $e');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: neutralBg,
      appBar: _buildHeader(),
      body: SafeArea(
        child: Column(
          children: [
            _buildProgressBar(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_currentStep == 1) _buildStep1PersonalDetails(),
                    if (_currentStep == 2) _buildStep2ResidenceDetails(),
                    if (_currentStep == 3) _buildStep3OccupationStudy(),
                    if (_currentStep == 4) _buildStep4SpecialEligibility(),
                    if (_currentStep == 5) _buildStep5DocumentsReview(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            _buildBottomActionBar(),
          ],
        ),
      ),
    );
  }

  // APP BAR
  PreferredSizeWidget _buildHeader() {
    return AppBar(
      elevation: 0.5,
      backgroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: primaryNavyDark),
        onPressed: _prevStep,
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: primaryNavy.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.account_balance, size: 20, color: primaryNavy),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'SchemeSathi',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: primaryNavyDark,
                ),
              ),
              Text(
                'Step $_currentStep of 5',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: textSoft,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: slateBorder),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Center(
            child: Text(
              'EN | हिं',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: textMain,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // PROGRESS BAR
  Widget _buildProgressBar() {
    final double percent = _currentStep / 5.0;
    return Column(
      children: [
        LinearProgressIndicator(
          value: percent,
          minHeight: 4,
          backgroundColor: slateBorder.withValues(alpha: 0.4),
          valueColor: const AlwaysStoppedAnimation<Color>(primaryNavy),
        ),
      ],
    );
  }

  // BOTTOM NAVIGATION BAR
  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: slateBorder.withValues(alpha: 0.6))),
      ),
      child: Row(
        children: [
          if (_currentStep > 1) ...[
            Expanded(
              flex: 1,
              child: OutlinedButton(
                onPressed: _prevStep,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: slateBorder),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text(
                  'Back',
                  style: TextStyle(
                    color: textMain,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _nextStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryNavy,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      _currentStep == 5
                          ? 'Find Eligible Schemes'
                          : 'Proceed to Next Step',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // STEP 1: PERSONAL DETAILS
  // =========================================================================
  Widget _buildStep1PersonalDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          badge: 'Step 1 of 5: Personal Details',
          title: 'Basic Demographics',
          subtitle: 'Enter personal details for age and eligibility qualification.',
        ),
        const SizedBox(height: 20),

        // Full Legal Name
        _buildFieldLabel('Full Legal Name (as per ID)*', required: true),
        const SizedBox(height: 4),
        const Text(
          'Must match legal name printed on Aadhaar card or Voter ID card.',
          style: TextStyle(fontSize: 12, color: textSoft),
        ),
        const SizedBox(height: 8),
        _buildTextField(
          controller: _fullNameController,
          hint: 'e.g., Rahul Sharma',
          prefixIcon: Icons.person_outline,
        ),
        const SizedBox(height: 20),

        // Date of Birth
        _buildFieldLabel('Date of Birth*', required: true),
        const SizedBox(height: 4),
        const Text(
          'Used to determine age-specific scheme eligibility (e.g., youth, senior citizen programs).',
          style: TextStyle(fontSize: 12, color: textSoft),
        ),
        const SizedBox(height: 8),
        _buildTextField(
          controller: _dobController,
          hint: 'DD / MM / YYYY',
          prefixIcon: Icons.calendar_today_outlined,
        ),
        const SizedBox(height: 20),

        // Gender selection
        _buildFieldLabel('Gender*', required: true),
        const SizedBox(height: 4),
        const Text(
          'Select gender as recorded on your government-issued identity.',
          style: TextStyle(fontSize: 12, color: textSoft),
        ),
        const SizedBox(height: 10),
        Column(
          children: ['Male', 'Female', 'Transgender', 'Other'].map((gender) {
            final isSelected = _selectedGender == gender;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => setState(() => _selectedGender = gender),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? primaryNavy : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? primaryNavy : slateBorder,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        gender,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : textMain,
                        ),
                      ),
                      Icon(
                        isSelected ? Icons.check_circle : Icons.radio_button_off,
                        color: isSelected ? Colors.white : textSoft,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        // Marital Status
        _buildFieldLabel('Marital Status*', required: true),
        const SizedBox(height: 4),
        const Text(
          'Determines eligibility for dependent, family pension, and household benefits.',
          style: TextStyle(fontSize: 12, color: textSoft),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            'Never Married',
            'Married',
            'Widowed',
            'Divorced / Separated',
            'Prefer Not to Disclose',
          ].map((status) {
            final isSelected = _selectedMaritalStatus == status;
            return ChoiceChip(
              label: Text(status),
              selected: isSelected,
              onSelected: (val) {
                if (val) setState(() => _selectedMaritalStatus = status);
              },
              selectedColor: primaryNavy,
              backgroundColor: Colors.white,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : textMain,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: isSelected ? primaryNavy : slateBorder),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),

        _buildPrivacyNotice(),
      ],
    );
  }

  // =========================================================================
  // STEP 2: RESIDENCE DETAILS
  // =========================================================================
  Widget _buildStep2ResidenceDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          badge: 'Step 2 of 5: Residence Details',
          title: 'Citizen Entitlements',
          subtitle:
              'Enter location and residential status to determine regional entitlement criteria.',
        ),
        const SizedBox(height: 20),

        // State Dropdown
        _buildFieldLabel('State / Union Territory *', required: true),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: slateBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _selectedState,
              items: _statesList
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedState = val);
              },
            ),
          ),
        ),
        const SizedBox(height: 20),

        // District Dropdown
        _buildFieldLabel('District *(Filtered by State)', required: true),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: slateBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _selectedDistrict,
              items: _districtsList
                  .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedDistrict = val);
              },
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Tehsil
        _buildFieldLabel('Tehsil / Block / Sub-district (Optional)'),
        const SizedBox(height: 8),
        _buildTextField(
          controller: _tehsilController,
          hint: 'Leave blank if not sure',
          prefixIcon: Icons.location_city_outlined,
        ),
        const SizedBox(height: 20),

        // Area Type
        _buildFieldLabel('Area Type *', required: true),
        const SizedBox(height: 10),
        _buildRadioCard(
          title: 'Rural',
          desc: 'Village / Gram Panchayat',
          icon: Icons.landscape_outlined,
          value: 'rural',
          groupValue: _selectedAreaType,
          onChanged: (v) => setState(() => _selectedAreaType = v!),
        ),
        _buildRadioCard(
          title: 'Urban',
          desc: 'City / Town / Nagar Nigam / Palika',
          icon: Icons.location_city,
          value: 'urban',
          groupValue: _selectedAreaType,
          onChanged: (v) => setState(() => _selectedAreaType = v!),
        ),
        _buildRadioCard(
          title: 'Not Sure / Peri-Urban',
          desc: 'Suburban fringe, census town, or undetermined',
          icon: Icons.help_outline,
          value: 'peri_urban',
          groupValue: _selectedAreaType,
          onChanged: (v) => setState(() => _selectedAreaType = v!),
        ),
        const SizedBox(height: 20),

        // Domicile status
        _buildFieldLabel('State Domicile Certificate (Niwas Praman Patra)'),
        const SizedBox(height: 10),
        _buildRadioCard(
          title: 'Yes (Available)',
          desc: 'Certificate issued with verified serial number',
          icon: Icons.verified_outlined,
          value: 'yes',
          groupValue: _selectedDomicileStatus,
          onChanged: (v) => setState(() => _selectedDomicileStatus = v!),
        ),
        _buildRadioCard(
          title: 'Applied / In Progress',
          desc: 'Applied via Lok Seva Kendra or Tehsil office',
          icon: Icons.pending_actions_outlined,
          value: 'in_progress',
          groupValue: _selectedDomicileStatus,
          onChanged: (v) => setState(() => _selectedDomicileStatus = v!),
        ),
        _buildRadioCard(
          title: 'Do not have',
          desc: 'Will require provisional declaration during filing',
          icon: Icons.cancel_outlined,
          value: 'no',
          groupValue: _selectedDomicileStatus,
          onChanged: (v) => setState(() => _selectedDomicileStatus = v!),
        ),
        const SizedBox(height: 16),

        // Local Residence Checkbox
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _localResidenceOutside,
          activeColor: primaryNavy,
          onChanged: (val) =>
              setState(() => _localResidenceOutside = val ?? false),
          title: const Text(
            'Current Local Residence Certificate (if residing outside native state)',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textMain),
          ),
          subtitle: const Text(
            'Applicable if currently residing in a different state from your native domicile.',
            style: TextStyle(fontSize: 11, color: textSoft),
          ),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        const SizedBox(height: 16),

        // State Family Registry ID
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: slateBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'State Family Registry ID',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: primaryNavyDark,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'e.g. Samagra Family ID (Madhya Pradesh), PPP (Haryana), etc.',
                style: TextStyle(fontSize: 11, color: textSoft),
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _hasFamilyId,
                activeColor: primaryNavy,
                onChanged: (val) => setState(() => _hasFamilyId = val ?? false),
                title: const Text(
                  'Do you have this ID? (Check if available)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (_hasFamilyId) ...[
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _familyIdController,
                  hint: 'Enter 8-digit Family ID or 9-digit Member ID',
                  prefixIcon: Icons.badge_outlined,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // STEP 3: OCCUPATION & STUDY
  // =========================================================================
  Widget _buildStep3OccupationStudy() {
    final occupations = [
      {'title': 'Student', 'desc': 'Enrolled in school or higher ed', 'icon': Icons.school_outlined},
      {'title': 'Salaried Employee', 'desc': 'Formal or private payroll', 'icon': Icons.badge_outlined},
      {'title': 'Self-Employed', 'desc': 'Independent trade / freelance', 'icon': Icons.handyman_outlined},
      {'title': 'Business Owner', 'desc': 'MSME, shop, registered firm', 'icon': Icons.storefront_outlined},
      {'title': 'Farmer', 'desc': 'Cultivator or tenant farmer', 'icon': Icons.agriculture_outlined},
      {'title': 'Daily Wage / Labor', 'desc': 'Manual or casual worker', 'icon': Icons.engineering_outlined},
      {'title': 'Unemployed', 'desc': 'Seeking job or skilling', 'icon': Icons.search_outlined},
      {'title': 'Homemaker', 'desc': 'Household care provider', 'icon': Icons.home_outlined},
      {'title': 'Retired / Pensioner', 'desc': 'Senior / pension beneficiary', 'icon': Icons.elderly_outlined},
      {'title': 'Not Sure / Other', 'desc': 'Unlisted, uncertain, or mixed', 'icon': Icons.more_horiz_outlined},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          badge: 'Step 3 of 5: Occupation & Education',
          title: 'Current Occupation & Enrolment',
          subtitle:
              'Select your current occupation to reveal category-specific qualification questions.',
        ),
        const SizedBox(height: 20),

        _buildFieldLabel('Primary Occupation', required: true),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.45,
          ),
          itemCount: occupations.length,
          itemBuilder: (context, i) {
            final occ = occupations[i];
            final title = occ['title'] as String;
            final isSelected = _selectedOccupation == title;
            return InkWell(
              onTap: () => setState(() => _selectedOccupation = title),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isSelected ? primaryNavy : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isSelected ? primaryNavy : slateBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      occ['icon'] as IconData,
                      color: isSelected ? Colors.white : primaryNavy,
                      size: 22,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? Colors.white : textMain,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      occ['desc'] as String,
                      style: TextStyle(
                        fontSize: 10,
                        color: isSelected ? Colors.white70 : textSoft,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 24),

        // Conditional Student Fields
        if (_selectedOccupation == 'Student') ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: slateBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.school, color: primaryNavy, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Student & Education Details',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: primaryNavyDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                _buildFieldLabel('Where are you studying?'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    'School',
                    'College / University',
                    'ITI / Polytechnic'
                  ].map((lvl) {
                    final isSel = _studyLevel == lvl;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(lvl),
                        selected: isSel,
                        onSelected: (val) {
                          if (val) setState(() => _studyLevel = lvl);
                        },
                        selectedColor: primaryNavy,
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          color: isSel ? Colors.white : textMain,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                          side: BorderSide(
                              color: isSel ? primaryNavy : slateBorder),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                _buildFieldLabel('Current Class / Course'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: slateBorder),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _selectedCourse,
                      items: _coursesList
                          .map((c) =>
                              DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 12))))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedCourse = val);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                _buildFieldLabel('Institution Type'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    'Government',
                    'Government-aided',
                    'Private',
                  ].map((inst) {
                    final isSel = _institutionType == inst;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(inst),
                        selected: isSel,
                        onSelected: (val) {
                          if (val) setState(() => _institutionType = inst);
                        },
                        selectedColor: primaryNavy,
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          color: isSel ? Colors.white : textMain,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                          side: BorderSide(
                              color: isSel ? primaryNavy : slateBorder),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                _buildFieldLabel('School or College Name (Optional)'),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _schoolCollegeController,
                  hint: 'Enter institute name or leave blank',
                  prefixIcon: Icons.account_balance_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Sathi Insight note
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: accentBlue.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accentBlue.withValues(alpha: 0.2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Icon(Icons.info_outline, color: accentBlue, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Family income is not requested in this step. Income thresholds are verified only for specific schemes requiring income caps.',
                  style: TextStyle(fontSize: 12, color: primaryNavyDark),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // STEP 4: SPECIAL ELIGIBILITY
  // =========================================================================
  Widget _buildStep4SpecialEligibility() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          badge: 'Step 4 of 5: Special Eligibility',
          title: 'Eligibility Verification',
          subtitle:
              'Answer demographic criteria to verify eligibility for targeted welfare quotas and reservations.',
        ),
        const SizedBox(height: 20),

        // Social Category Dropdown
        _buildFieldLabel('Social Category*', required: true),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: slateBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _socialCategory,
              items: _categoriesList
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _socialCategory = val);
              },
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Caste Certificate Status
        _buildFieldLabel('Caste Certificate Status*', required: true),
        const SizedBox(height: 4),
        const Text(
          'State-issued physical or digital caste certificate. (Only applicable if selecting affirmative category e.g., SC/ST/OBC/EWS)',
          style: TextStyle(fontSize: 12, color: textSoft),
        ),
        const SizedBox(height: 10),
        _buildRadioCard(
          title: 'Yes (Available)',
          desc: 'Verified certificate document with registration number',
          icon: Icons.check_circle_outline,
          value: 'Yes (Available)',
          groupValue: _casteCertStatus,
          onChanged: (v) => setState(() => _casteCertStatus = v!),
        ),
        _buildRadioCard(
          title: 'No',
          desc: 'Do not possess an official caste certificate',
          icon: Icons.cancel_outlined,
          value: 'No',
          groupValue: _casteCertStatus,
          onChanged: (v) => setState(() => _casteCertStatus = v!),
        ),
        _buildRadioCard(
          title: 'Not Sure / In Progress / Don\'t Know',
          desc: 'Application in progress or uncertain',
          icon: Icons.pending_actions_outlined,
          value: 'Not Sure / In Progress / Don\'t Know',
          groupValue: _casteCertStatus,
          onChanged: (v) => setState(() => _casteCertStatus = v!),
        ),
        const SizedBox(height: 20),

        // Person with Disability (PwD)
        _buildFieldLabel('Person with Disability (PwD) (Optional)'),
        const SizedBox(height: 4),
        const Text(
          'Select \'Yes\' if applicable for accessible education aids, assistive equipment grants, or disability pension quotas.',
          style: TextStyle(fontSize: 12, color: textSoft),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            'Yes',
            'No',
            'Not Sure / Assessment Pending',
            'Prefer Not to Disclose'
          ].map((status) {
            final isSel = _pwdStatus == status;
            return ChoiceChip(
              label: Text(status),
              selected: isSel,
              onSelected: (val) {
                if (val) setState(() => _pwdStatus = status);
              },
              selectedColor: primaryNavy,
              backgroundColor: Colors.white,
              labelStyle: TextStyle(
                color: isSel ? Colors.white : textMain,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: isSel ? primaryNavy : slateBorder),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        // Minority Community Status
        _buildFieldLabel('Minority Community Status (Optional)'),
        const SizedBox(height: 4),
        const Text(
          'Select \'Yes\' if you belong to a recognized minority group for designated education and business schemes.',
          style: TextStyle(fontSize: 12, color: textSoft),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['Yes', 'No', 'Not Sure', 'Prefer Not to Disclose'].map((status) {
            final isSel = _minorityStatus == status;
            return ChoiceChip(
              label: Text(status),
              selected: isSel,
              onSelected: (val) {
                if (val) setState(() => _minorityStatus = status);
              },
              selectedColor: primaryNavy,
              backgroundColor: Colors.white,
              labelStyle: TextStyle(
                color: isSel ? Colors.white : textMain,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: isSel ? primaryNavy : slateBorder),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        // Income Certificate Status
        _buildFieldLabel('Income Certificate Status (Optional)'),
        const SizedBox(height: 10),
        _buildRadioCard(
          title: 'Yes (Available & Valid)',
          desc: 'Revenue officer or Tehsildar issued certificate',
          icon: Icons.check_circle_outline,
          value: 'Yes (Available & Valid)',
          groupValue: _incomeCertStatus,
          onChanged: (v) => setState(() => _incomeCertStatus = v!),
        ),
        _buildRadioCard(
          title: 'Application Pending',
          desc: 'Submitted application at portal or service center',
          icon: Icons.pending_actions_outlined,
          value: 'Application Pending',
          groupValue: _incomeCertStatus,
          onChanged: (v) => setState(() => _incomeCertStatus = v!),
        ),
        _buildRadioCard(
          title: 'Not Sure / Don\'t Have',
          desc: 'Will need guidance to apply if matched',
          icon: Icons.cancel_outlined,
          value: 'Not Sure / Don\'t Have',
          groupValue: _incomeCertStatus,
          onChanged: (v) => setState(() => _incomeCertStatus = v!),
        ),
      ],
    );
  }

  // =========================================================================
  // STEP 5: DOCUMENTS & REVIEW
  // =========================================================================
  Widget _buildStep5DocumentsReview() {
    final docGroups = [
      {
        'title': '1. Identity & Personal IDs',
        'subtitle': 'Aadhaar, PAN, Voter ID, Driving Licence',
        'items': [
          {
            'name': 'Aadhaar Card (UIDAI)',
            'tag': 'COMMON ID',
            'desc': 'Commonly used for identity verification and receiving DBT subsidies in bank accounts.',
          },
          {
            'name': 'Permanent Account Number (PAN) Card',
            'tag': 'TAX / BANKING',
            'desc': 'Used for higher-value educational stipends, commercial enterprise loans, and tax records.',
          },
          {
            'name': 'Voter ID Card (EPIC)',
            'tag': 'ELECTORAL',
            'desc': 'State and national electoral verification',
          },
          {
            'name': 'Driving Licence (DL)',
            'tag': 'TRANSPORT',
            'desc': 'Commercial vehicle driver welfare and transport subsidy schemes',
          },
        ]
      },
      {
        'title': '2. Residence & Household',
        'subtitle': 'Ration Card, Domicile, Samagra ID',
        'items': [
          {
            'name': 'Samagra Family ID',
            'tag': 'STATE ID',
            'desc': 'Helps match state-specific family entitlement lists in Madhya Pradesh (if applicable).',
          },
          {
            'name': 'State Domicile / Resident Certificate',
            'tag': 'RESIDENCE',
            'desc': 'Validates resident eligibility for state university quotas and local programs',
          },
          {
            'name': 'Ration Card (NFSA or State PDS)',
            'tag': 'FOOD SECURITY',
            'desc': 'Verifies family unit structure and food security eligibility',
          },
          {
            'name': 'Aadhaar-Seeded Bank Account',
            'tag': 'ACTIVE DBT',
            'desc': 'Active bank account linked with Aadhaar to receive Direct Benefit Transfer (DBT) disbursements.',
          },
        ]
      },
      {
        'title': '3. Income & Category Proofs',
        'subtitle': 'Income, BPL, Caste Certificates',
        'items': [
          {
            'name': 'Annual Income Certificate',
            'tag': 'INCOME',
            'desc': 'Tehsildar or revenue authority issued income certificate',
          },
          {
            'name': 'Below Poverty Line (BPL) Card',
            'tag': 'BPL',
            'desc': 'Antyodaya or priority household identification for fee exemptions',
          },
          {
            'name': 'Digital Caste Certificate (SC/ST/OBC)',
            'tag': 'CATEGORY',
            'desc': 'State revenue barcode-verified community record',
          },
          {
            'name': 'OBC Non-Creamy Layer (NCL) Certificate',
            'tag': 'OBC-NCL',
            'desc': 'Valid for central and state reservation benefits',
          },
        ]
      },
      {
        'title': '4. Academic & Special Records',
        'subtitle': 'Marksheets, Student ID, Disability, e-Shram',
        'items': [
          {
            'name': 'Class 10th or 12th Marksheet',
            'tag': 'EDUCATION',
            'desc': 'Verification of date of birth and scholarship qualifying marks',
          },
          {
            'name': 'College Bonafide / Enrolment Certificate',
            'tag': 'STUDENT',
            'desc': 'Issued by educational institution verifying regular student status',
          },
          {
            'name': 'APAAR / ABC Student ID',
            'tag': 'ONE NATION ID',
            'desc': 'One Nation One Student ID / Academic Bank of Credits',
          },
          {
            'name': 'Ayushman Bharat (PM-JAY) Card',
            'tag': 'HEALTH',
            'desc': 'Government health insurance card for cashless hospitalization',
          },
          {
            'name': 'Unique Disability ID (UDID) Card',
            'tag': 'DISABILITY',
            'desc': 'Required for disability entitlements, assistive devices, and quotas',
          },
          {
            'name': 'e-Shram Universal Account Number (UAN)',
            'tag': 'WORKER ID',
            'desc': 'National unorganized worker registration certificate',
          },
          {
            'name': 'MSME Udyam Registration',
            'tag': 'ENTERPRISE',
            'desc': 'Micro or small enterprise credit support and subsidies',
          },
          {
            'name': 'DigiLocker Verified Account',
            'tag': 'DIGITAL',
            'desc': 'Government-certified paperless verification platform access',
          },
        ]
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          badge: 'Step 5 of 5: Documents & Review',
          title: 'Available Documents & Records',
          subtitle:
              'Check the documents and digital records you possess to match verification requirements. No document files or sensitive scans are uploaded at this stage.',
        ),
        const SizedBox(height: 16),

        // Banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF4FF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFCBDDF8)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: accentBlue, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Mark the ones you know you have, and leave uncertain documents unchecked for provisional matching.',
                  style: TextStyle(fontSize: 12, color: primaryNavyDark),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Controls bar: count & select/clear all
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: primaryNavy.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Selected Documents: ${_selectedDocuments.length}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: primaryNavy,
                ),
              ),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      for (var g in docGroups) {
                        for (var item in g['items'] as List<Map<String, String>>) {
                          _selectedDocuments.add(item['name']!);
                        }
                      }
                    });
                  },
                  child: const Text('Select All', style: TextStyle(fontSize: 12)),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedDocuments.clear();
                    });
                  },
                  child: const Text('Clear All', style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Document Groups
        ...docGroups.map((group) {
          final items = group['items'] as List<Map<String, String>>;
          final int countSelected = items
              .where((it) => _selectedDocuments.contains(it['name']))
              .length;

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: slateBorder),
            ),
            child: ExpansionTile(
              initiallyExpanded: true,
              shape: const Border(),
              title: Text(
                group['title'] as String,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: primaryNavyDark,
                ),
              ),
              subtitle: Text(
                '${group['subtitle']} ($countSelected/${items.length} selected)',
                style: const TextStyle(fontSize: 11, color: textSoft),
              ),
              children: items.map((doc) {
                final isChecked = _selectedDocuments.contains(doc['name']);
                return CheckboxListTile(
                  value: isChecked,
                  activeColor: primaryNavy,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedDocuments.add(doc['name']!);
                      } else {
                        _selectedDocuments.remove(doc['name']!);
                      }
                    });
                  },
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          doc['name']!,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isChecked ? FontWeight.w700 : FontWeight.w600,
                            color: textMain,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          doc['tag']!,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: textSoft,
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      doc['desc']!,
                      style: const TextStyle(fontSize: 11, color: textSoft),
                    ),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                );
              }).toList(),
            ),
          );
        }),
      ],
    );
  }

  // =========================================================================
  // HELPER WIDGETS
  // =========================================================================
  Widget _buildStepHeader({
    required String badge,
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: primaryNavy.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            badge,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: primaryNavy,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: textMain,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 13, color: textMuted),
        ),
      ],
    );
  }

  Widget _buildFieldLabel(String label, {bool required = false}) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: textMain,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    IconData? prefixIcon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: slateBorder),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(fontSize: 14, color: textMain),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: InputBorder.none,
          hintText: hint,
          hintStyle: const TextStyle(color: textSoft, fontSize: 13),
          prefixIcon: prefixIcon != null
              ? Icon(prefixIcon, color: textSoft, size: 20)
              : null,
        ),
      ),
    );
  }

  Widget _buildRadioCard({
    required String title,
    required String desc,
    required IconData icon,
    required String value,
    required String groupValue,
    required ValueChanged<String?> onChanged,
  }) {
    final bool isSelected = value == groupValue;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFEFF4FF) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? primaryNavy : slateBorder,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Radio<String>(
                value: value,
                groupValue: groupValue,
                activeColor: primaryNavy,
                onChanged: onChanged,
              ),
              const SizedBox(width: 4),
              Icon(icon, color: isSelected ? primaryNavy : textSoft, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? primaryNavyDark : textMain,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      desc,
                      style: const TextStyle(fontSize: 11, color: textSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrivacyNotice() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: slateBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.shield_outlined, color: primaryNavy, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Your information is strictly used to match eligible welfare schemes and programs. Data is kept confidential and not shared with third parties.',
              style: TextStyle(fontSize: 11, color: textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
