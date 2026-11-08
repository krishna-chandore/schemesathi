import 'package:flutter/material.dart';
import '../auth/auth.dart';
import 'app_preferences.dart';
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
  bool _isLoadingProfile = true;

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
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  String _selectedGender = 'Male';
  String _selectedMaritalStatus = 'Never Married';

  // STEP 2 STATE
  String _selectedState = AppPreferences.instance.currentState;
  String _selectedDistrict = 'Bhopal';
  final TextEditingController _otherDistrictController = TextEditingController();
  final TextEditingController _tehsilController = TextEditingController();
  String _selectedAreaType = 'rural'; // rural, urban, peri_urban
  String _selectedDomicileStatus = 'yes'; // yes, in_progress, no
  bool _localResidenceOutside = false;
  final TextEditingController _familyIdController = TextEditingController();
  bool _hasFamilyId = false;

  // STEP 3 STATE
  String _selectedOccupation = 'Student';
  String _studyLevel = 'College / University';
  String _selectedCourse = 'B.Tech / B.E (Engineering)';
  String _institutionType = 'Government';
  final TextEditingController _schoolCollegeController = TextEditingController();
  String _selectedAnnualIncome = '₹1,50,001 - ₹2,50,000 (Low Income / BPL Border)';

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

  static const Map<String, List<String>> _stateDistrictsMap = {
    'Andhra Pradesh': ['Anantapur', 'Chittoor', 'East Godavari', 'Guntur', 'Krishna', 'Kurnool', 'Prakasam', 'Srikakulam', 'Sri Potti Sriramulu Nellore', 'Visakhapatnam', 'Vizianagaram', 'West Godavari', 'YSR Kadapa', 'Other'],
    'Arunachal Pradesh': ['Tawang', 'West Kameng', 'East Kameng', 'Papum Pare', 'Lower Subansiri', 'Upper Subansiri', 'West Siang', 'East Siang', 'Upper Siang', 'Changlang', 'Tirap', 'Other'],
    'Assam': ['Baksa', 'Barpeta', 'Biswanath', 'Bongaigaon', 'Cachar', 'Charaideo', 'Chirang', 'Darrang', 'Dhemaji', 'Dhubri', 'Dibrugarh', 'Goalpara', 'Golaghat', 'Guwahati / Kamrup', 'Jorhat', 'Nagaon', 'Silchar', 'Sonitpur', 'Tinsukia', 'Other'],
    'Bihar': ['Araria', 'Arwal', 'Aurangabad', 'Banka', 'Begusarai', 'Bhagalpur', 'Bhojpur', 'Buxar', 'Darbhanga', 'East Champaran', 'Gaya', 'Gopalganj', 'Jamui', 'Jehanabad', 'Katihar', 'Khagaria', 'Kishanganj', 'Lakhisarai', 'Madhepura', 'Madhubani', 'Munger', 'Muzaffarpur', 'Nalanda', 'Nawada', 'Patna', 'Purnia', 'Rohtas', 'Saharsa', 'Samastipur', 'Saran', 'Sheikhpura', 'Sheohar', 'Sitamarhi', 'Siwan', 'Supaul', 'Vaishali', 'West Champaran', 'Other'],
    'Chhattisgarh': ['Balod', 'Baloda Bazar', 'Balrampur', 'Bastar', 'Bemetara', 'Bijapur', 'Bilaspur', 'Dantewada', 'Dhamtari', 'Durg', 'Gariaband', 'Janjgir-Champa', 'Jashpur', 'Kabirdham', 'Kanker', 'Kondagaon', 'Korba', 'Koriya', 'Mahasamund', 'Mungeli', 'Narayanpur', 'Raigarh', 'Raipur', 'Rajnandgaon', 'Sukma', 'Surajpur', 'Surguja', 'Other'],
    'Goa': ['North Goa', 'South Goa', 'Panaji', 'Margao', 'Vasco da Gama', 'Mapusa', 'Ponda', 'Other'],
    'Gujarat': ['Ahmedabad', 'Amreli', 'Anand', 'Aravalli', 'Banaskantha', 'Bharuch', 'Bhavnagar', 'Botad', 'Chhota Udaipur', 'Dahod', 'Dang', 'Devbhoomi Dwarka', 'Gandhinagar', 'Gir Somnath', 'Jamnagar', 'Junagadh', 'Kheda', 'Kutch', 'Mahisagar', 'Mehsana', 'Morbi', 'Narmada', 'Navsari', 'Panchmahal', 'Patan', 'Porbandar', 'Rajkot', 'Sabarkantha', 'Surat', 'Surendranagar', 'Tapi', 'Vadodara', 'Valsad', 'Other'],
    'Haryana': ['Ambala', 'Bhiwani', 'Charkhi Dadri', 'Faridabad', 'Fatehabad', 'Gurugram', 'Hisar', 'Jhajjar', 'Jind', 'Kaithal', 'Karnal', 'Kurukshetra', 'Mahendragarh', 'Nuh', 'Palwal', 'Panchkula', 'Panipat', 'Rewari', 'Rohtak', 'Sirsa', 'Sonipat', 'Yamunanagar', 'Other'],
    'Himachal Pradesh': ['Bilaspur', 'Chamba', 'Hamirpur', 'Kangra', 'Kinnaur', 'Kullu', 'Lahaul and Spiti', 'Mandi', 'Shimla', 'Sirmaur', 'Solan', 'Una', 'Other'],
    'Jharkhand': ['Bokaro', 'Chatra', 'Deoghar', 'Dhanbad', 'Dumka', 'East Singhbhum (Jamshedpur)', 'Garhwa', 'Giridih', 'Godda', 'Gumla', 'Hazaribagh', 'Jamtara', 'Khunti', 'Koderma', 'Latehar', 'Lohardaga', 'Pakur', 'Palamu', 'Ramgarh', 'Ranchi', 'Sahibganj', 'Seraikela Kharsawan', 'Simdega', 'West Singhbhum', 'Other'],
    'Karnataka': ['Bagalkot', 'Ballari', 'Belagavi', 'Bengaluru Rural', 'Bengaluru Urban', 'Bidar', 'Chamarajanagar', 'Chikkaballapura', 'Chikkamagaluru', 'Chitradurga', 'Dakshina Kannada (Mangaluru)', 'Davanagere', 'Dharwad (Hubballi)', 'Gadag', 'Hassan', 'Haveri', 'Kalaburagi', 'Kodagu', 'Kolar', 'Koppal', 'Mandya', 'Mysuru', 'Raichur', 'Ramanagara', 'Shivamogga', 'Tumakuru', 'Udupi', 'Uttara Kannada', 'Vijayapura', 'Yadgir', 'Other'],
    'Kerala': ['Alappuzha', 'Ernakulam (Kochi)', 'Idukki', 'Kannur', 'Kasaragod', 'Kollam', 'Kottayam', 'Kozhikode', 'Malappuram', 'Palakkad', 'Pathanamthitta', 'Thiruvananthapuram', 'Thrissur', 'Wayanad', 'Other'],
    'Madhya Pradesh': ['Agar Malwa', 'Alirajpur', 'Anuppur', 'Ashoknagar', 'Balaghat', 'Barwani', 'Betul', 'Bhind', 'Bhopal', 'Burhanpur', 'Chhatarpur', 'Chhindwara', 'Damoh', 'Datia', 'Dewas', 'Dhar', 'Dindori', 'Guna', 'Gwalior', 'Harda', 'Hoshangabad (Narmadapuram)', 'Indore', 'Jabalpur', 'Jhabua', 'Katni', 'Khandwa', 'Khargone', 'Mandla', 'Mandsaur', 'Morena', 'Narsinghpur', 'Neemuch', 'Panna', 'Raisen', 'Rajgarh', 'Ratlam', 'Rewa', 'Sagar', 'Satna', 'Sehore', 'Seoni', 'Shahdol', 'Shajapur', 'Sheopur', 'Shivpuri', 'Sidhi', 'Singrauli', 'Tikamgarh', 'Ujjain', 'Umaria', 'Vidisha', 'Other'],
    'Maharashtra': ['Ahmednagar', 'Akola', 'Amravati', 'Aurangabad (Chhatrapati Sambhajinagar)', 'Beed', 'Bhandara', 'Buldhana', 'Chandrapur', 'Dhule', 'Gadchiroli', 'Gondia', 'Hingoli', 'Jalgaon', 'Jalna', 'Kolhapur', 'Latur', 'Mumbai City', 'Mumbai Suburban', 'Nagpur', 'Nanded', 'Nandurbar', 'Nashik', 'Osmanabad (Dharashiv)', 'Palghar', 'Parbhani', 'Pune', 'Raigad', 'Ratnagiri', 'Sangli', 'Satara', 'Sindhudurg', 'Solapur', 'Thane', 'Wardha', 'Washim', 'Yavatmal', 'Other'],
    'Manipur': ['Bishnupur', 'Chandel', 'Churachandpur', 'Imphal East', 'Imphal West', 'Jiribam', 'Kakching', 'Kamjong', 'Kangpokpi', 'Noney', 'Pherzawl', 'Senapati', 'Tamenglong', 'Tengnoupal', 'Thoubal', 'Ukhrul', 'Other'],
    'Meghalaya': ['East Garo Hills', 'East Jaintia Hills', 'East Khasi Hills (Shillong)', 'North Garo Hills', 'Ri Bhoi', 'South Garo Hills', 'South West Garo Hills', 'South West Khasi Hills', 'West Garo Hills', 'West Jaintia Hills', 'West Khasi Hills', 'Other'],
    'Mizoram': ['Aizawl', 'Champhai', 'Hnahthial', 'Khawzawl', 'Kolasib', 'Lawngtlai', 'Lunglei', 'Mamit', 'Saiha', 'Saitual', 'Serchhip', 'Other'],
    'Nagaland': ['Chumoukedima', 'Dimapur', 'Kiphire', 'Kohima', 'Longleng', 'Mokokchung', 'Mon', 'Niuland', 'Noklak', 'Peren', 'Phek', 'Shamator', 'Tseminyu', 'Tuensang', 'Wokha', 'Zunheboto', 'Other'],
    'Odisha': ['Angul', 'Balangir', 'Balasore', 'Bargarh', 'Bhadrak', 'Boudh', 'Cuttack', 'Deogarh', 'Dhenkanal', 'Gajapati', 'Ganjam', 'Jagatsinghpur', 'Jajpur', 'Jharsuguda', 'Kalahandi', 'Kandhamal', 'Kendrapara', 'Kendujhar (Keonjhar)', 'Khordha (Bhubaneswar)', 'Koraput', 'Malkangiri', 'Mayurbhanj', 'Nabarangpur', 'Nayagarh', 'Nuapada', 'Puri', 'Rayagada', 'Sambalpur', 'Subarnapur (Sonepur)', 'Sundargarh', 'Other'],
    'Punjab': ['Amritsar', 'Barnala', 'Bathinda', 'Faridkot', 'Fatehgarh Sahib', 'Fazilka', 'Ferozepur', 'Gurdaspur', 'Hoshiarpur', 'Jalandhar', 'Kapurthala', 'Ludhiana', 'Malerkotla', 'Mansa', 'Moga', 'Muktsar', 'Pathankot', 'Patiala', 'Rupnagar', 'Sahibzada Ajit Singh Nagar (Mohali)', 'Sangrur', 'Shahid Bhagat Singh Nagar (Nawanshahr)', 'Tarn Taran', 'Other'],
    'Rajasthan': ['Ajmer', 'Alwar', 'Banswara', 'Baran', 'Barmer', 'Bharatpur', 'Bhilwara', 'Bikaner', 'Bundi', 'Chittorgarh', 'Churu', 'Dausa', 'Dholpur', 'Dungarpur', 'Hanumangarh', 'Jaipur', 'Jaisalmer', 'Jalore', 'Jhalawar', 'Jhunjhunu', 'Jodhpur', 'Karauli', 'Kota', 'Nagaur', 'Pali', 'Pratapgarh', 'Rajsamand', 'Sawai Madhopur', 'Sikar', 'Sirohi', 'Sri Ganganagar', 'Tonk', 'Udaipur', 'Other'],
    'Sikkim': ['Gangtok', 'Mangan', 'Namchi', 'Gyalshing', 'Pakyong', 'Soreng', 'Other'],
    'Tamil Nadu': ['Ariyalur', 'Chengalpattu', 'Chennai', 'Coimbatore', 'Cuddalore', 'Dharmapuri', 'Dindigul', 'Erode', 'Kallakurichi', 'Kanchipuram', 'Kanyakumari', 'Karur', 'Krishnagiri', 'Madurai', 'Mayiladuthurai', 'Nagapattinam', 'Namakkal', 'Nilgiris', 'Perambalur', 'Pudukkottai', 'Ramanathapuram', 'Ranipet', 'Salem', 'Sivaganga', 'Tenkasi', 'Thanjavur', 'Theni', 'Thoothukudi', 'Tiruchirappalli', 'Tirunelveli', 'Tirupathur', 'Tiruppur', 'Tiruvallur', 'Tiruvannamalai', 'Tiruvarur', 'Vellore', 'Viluppuram', 'Virudhunagar', 'Other'],
    'Telangana': ['Adilabad', 'Bhadradri Kothagudem', 'Hyderabad', 'Jagtial', 'Jangaon', 'Jayashankar Bhupalpally', 'Jogulamba Gadwal', 'Kamareddy', 'Karimnagar', 'Khammam', 'Komaram Bheem Asifabad', 'Mahabubabad', 'Mahbubnagar', 'Mancherial', 'Medak', 'Medchal-Malkajgiri', 'Mulugu', 'Nagarkurnool', 'Nalgonda', 'Narayanpet', 'Nirmal', 'Nizamabad', 'Peddapalli', 'Rajanna Sircilla', 'Rangareddy', 'Sangareddy', 'Siddipet', 'Suryapet', 'Vikarabad', 'Wanaparthy', 'Warangal', 'Hanamkonda', 'Yadadri Bhuvanagiri', 'Other'],
    'Tripura': ['Dhalai', 'Gomati', 'Khowai', 'North Tripura', 'Sepahijala', 'South Tripura', 'Unakoti', 'West Tripura (Agartala)', 'Other'],
    'Uttar Pradesh': ['Agra', 'Aligarh', 'Ambedkar Nagar', 'Amethi', 'Amroha', 'Auraiya', 'Ayodhya (Faizabad)', 'Azamgarh', 'Baghpat', 'Bahraich', 'Ballia', 'Balrampur', 'Banda', 'Barabanki', 'Bareilly', 'Basti', 'Bhadohi', 'Bijnor', 'Budaun', 'Bulandshahr', 'Chandauli', 'Chitrakoot', 'Deoria', 'Etah', 'Etawah', 'Farrukhabad', 'Fatehpur', 'Firozabad', 'Gautam Buddha Nagar (Noida)', 'Ghaziabad', 'Ghazipur', 'Gonda', 'Gorakhpur', 'Hamirpur', 'Hapur', 'Hardoi', 'Hathras', 'Jalaun', 'Jaunpur', 'Jhansi', 'Kannauj', 'Kanpur Dehat', 'Kanpur Nagar', 'Kasganj', 'Kaushambi', 'Kushinagar', 'Lakhimpur Kheri', 'Lalitpur', 'Lucknow', 'Maharajganj', 'Mahoba', 'Mainpuri', 'Mathura', 'Mau', 'Meerut', 'Mirzapur', 'Moradabad', 'Muzaffarnagar', 'Pilibhit', 'Pratapgarh', 'Prayagraj (Allahabad)', 'Raebareli', 'Rampur', 'Saharanpur', 'Sambhal', 'Sant Kabir Nagar', 'Shahjahanpur', 'Shamli', 'Shravasti', 'Siddharthnagar', 'Sitapur', 'Sonbhadra', 'Sultanpur', 'Unnao', 'Varanasi', 'Other'],
    'Uttarakhand': ['Almora', 'Bageshwar', 'Chamoli', 'Champawat', 'Dehradun', 'Haridwar', 'Nainital', 'Pauri Garhwal', 'Pithoragarh', 'Rudraprayag', 'Tehri Garhwal', 'Udham Singh Nagar', 'Uttarkashi', 'Other'],
    'West Bengal': ['Alipurduar', 'Bankura', 'Birbhum', 'Cooch Behar', 'Dakshin Dinajpur', 'Darjeeling', 'Hooghly', 'Howrah', 'Jalpaiguri', 'Jhargram', 'Kalimpong', 'Kolkata', 'Malda', 'Murshidabad', 'Nadia', 'North 24 Parganas', 'Paschim Bardhaman', 'Paschim Medinipur', 'Purba Bardhaman', 'Purba Medinipur', 'Purulia', 'South 24 Parganas', 'Uttar Dinajpur', 'Other'],
    'Delhi (NCT)': ['Central Delhi', 'East Delhi', 'New Delhi', 'North Delhi', 'North East Delhi', 'North West Delhi', 'Shahdara', 'South Delhi', 'South East Delhi', 'South West Delhi', 'West Delhi', 'Other'],
    'Jammu and Kashmir': ['Anantnag', 'Bandipora', 'Baramulla', 'Budgam', 'Doda', 'Ganderbal', 'Jammu', 'Kathua', 'Kishtwar', 'Kulgam', 'Kupwara', 'Poonch', 'Pulwama', 'Rajouri', 'Ramban', 'Reasi', 'Samba', 'Shopian', 'Srinagar', 'Udhampur', 'Other'],
    'Ladakh': ['Leh', 'Kargil', 'Other'],
  };

  List<String> get _currentDistricts {
    return _stateDistrictsMap[_selectedState] ?? ['Other'];
  }

  static const Map<String, List<String>> _levelToCoursesMap = {
    'School': [
      'Primary School (Class 1st to 5th)',
      'Upper Primary / Middle School (Class 6th to 8th)',
      'Class 9th (Secondary School)',
      'Class 10th (Matriculation)',
      'Class 11th - Science (PCM / PCB)',
      'Class 11th - Commerce',
      'Class 11th - Arts / Humanities',
      'Class 12th - Science (PCM / PCB)',
      'Class 12th - Commerce',
      'Class 12th - Arts / Humanities',
    ],
    'College / University': [
      'B.Tech / B.E (Engineering)',
      'B.Sc (Bachelor of Science)',
      'B.A (Bachelor of Arts)',
      'B.Com (Bachelor of Commerce)',
      'BBA / BMS (Management)',
      'BCA (Computer Applications)',
      'MBBS / BDS / AYUSH (Medical / Dental)',
      'B.Pharm (Pharmacy)',
      'LLB / Integrated Law',
      'B.Ed / D.El.Ed (Education)',
      'M.Tech / M.E',
      'M.Sc (Master of Science)',
      'M.A (Master of Arts)',
      'M.Com (Master of Commerce)',
      'MBA / PGDM (Management)',
      'MCA (Computer Applications)',
      'MD / MS / MDS (Medical Postgrad)',
      'Doctoral Scholar / PhD Research',
      'Other Degree Course',
    ],
    'ITI / Polytechnic': [
      'Polytechnic Diploma (Engineering & Tech)',
      'Polytechnic Diploma (Non-Engineering)',
      'ITI Trade - Electrician',
      'ITI Trade - Fitter / Turner / Machinist',
      'ITI Trade - Welder / Plumber',
      'ITI Trade - Computer Operator (COPA)',
      'ITI Trade - Diesel Mechanic / Motor Vehicle',
      'Vocational / Skill Development Certificate',
      'Other Technical Diploma',
    ],
  };

  List<String> get _currentCourses {
    return _levelToCoursesMap[_studyLevel] ?? [
      'Class 10th (Matriculation)',
      'Class 12th (Higher Secondary)',
      'Undergraduate Degree',
      'Postgraduate Degree',
      'Other Course',
    ];
  }

  static const List<String> _incomeBrackets = [
    'Up to ₹1,00,000 (Antyodaya / BPL Priority)',
    '₹1,00,001 - ₹1,50,000 (Low Income)',
    '₹1,50,001 - ₹2,50,000 (Low Income / BPL Border)',
    '₹2,50,001 - ₹5,00,000 (Middle Income / Non-Creamy)',
    '₹5,00,001 - ₹8,00,000 (EWS / State Quota Cap)',
    'Above ₹8,00,000 (General / Non-Affirmative)',
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
  void initState() {
    super.initState();
    _loadExistingProfile();
  }

  /// Loads the citizen's single persistent profile from backend MongoDB
  Future<void> _loadExistingProfile() async {
    final auth = ClerkAuthService.instance;
    final email = widget.initialEmail ?? auth.userEmail;
    final clerkUid = auth.clerkUserId;

    if ((email != null && email.isNotEmpty) || (clerkUid != null && clerkUid.isNotEmpty)) {
      try {
        final profile = await FormService.instance.fetchFullProfile(
          clerkUserId: clerkUid,
          email: email,
        );

        if (profile != null && mounted) {
          setState(() {
            if (profile['full_name'] != null && profile['full_name'].toString().trim().isNotEmpty) {
              _fullNameController.text = profile['full_name'].toString().trim();
            } else if (auth.userName.isNotEmpty && auth.userName != 'Citizen') {
              _fullNameController.text = auth.userName;
            }

            if (profile['dob'] != null && profile['dob'].toString().trim().isNotEmpty) {
              _dobController.text = profile['dob'].toString().trim();
            }

            if (profile['gender'] != null) {
              _selectedGender = profile['gender'].toString();
            }

            if (profile['marital_status'] != null) {
              _selectedMaritalStatus = profile['marital_status'].toString();
            }

            if (profile['state'] != null && _statesList.contains(profile['state'])) {
              _selectedState = profile['state'].toString();
              AppPreferences.instance.setStateName(
                _selectedState,
                email: email,
                clerkUserId: clerkUid,
              );
            }

            if (profile['district'] != null) {
              final dist = profile['district'].toString();
              if (_currentDistricts.contains(dist)) {
                _selectedDistrict = dist;
              } else {
                _selectedDistrict = 'Other';
                _otherDistrictController.text = dist;
              }
            }

            if (profile['tehsil'] != null) {
              _tehsilController.text = profile['tehsil'].toString();
            }

            if (profile['area_type'] != null) {
              _selectedAreaType = profile['area_type'].toString();
            }

            if (profile['domicile_status'] != null) {
              _selectedDomicileStatus = profile['domicile_status'].toString();
            }

            if (profile['local_residence_outside'] != null) {
              _localResidenceOutside = profile['local_residence_outside'] == true;
            }

            if (profile['family_id'] != null && profile['family_id'].toString().trim().isNotEmpty) {
              _familyIdController.text = profile['family_id'].toString().trim();
              _hasFamilyId = true;
            }

            if (profile['occupation'] != null) {
              _selectedOccupation = profile['occupation'].toString();
            }

            if (profile['study_level'] != null) {
              _studyLevel = profile['study_level'].toString();
            }

            if (profile['education_course'] != null) {
              final c = profile['education_course'].toString();
              if (_currentCourses.contains(c)) {
                _selectedCourse = c;
              } else if (_currentCourses.isNotEmpty) {
                _selectedCourse = _currentCourses.first;
              }
            }

            if (profile['annual_income'] != null && _incomeBrackets.contains(profile['annual_income'].toString())) {
              _selectedAnnualIncome = profile['annual_income'].toString();
            }

            if (profile['institution_type'] != null) {
              _institutionType = profile['institution_type'].toString();
            }

            if (profile['school_or_college_name'] != null) {
              _schoolCollegeController.text = profile['school_or_college_name'].toString();
            }

            if (profile['social_category'] != null && _categoriesList.contains(profile['social_category'])) {
              _socialCategory = profile['social_category'].toString();
            }

            if (profile['caste_certificate_status'] != null) {
              _casteCertStatus = profile['caste_certificate_status'].toString();
            }

            if (profile['pwd_status'] != null) {
              _pwdStatus = profile['pwd_status'].toString();
            }

            if (profile['minority_status'] != null) {
              _minorityStatus = profile['minority_status'].toString();
            }

            if (profile['income_certificate_status'] != null) {
              _incomeCertStatus = profile['income_certificate_status'].toString();
            }

            if (profile['documents'] is List) {
              _selectedDocuments.clear();
              for (var doc in profile['documents']) {
                if (doc is String && doc.isNotEmpty) {
                  _selectedDocuments.add(doc);
                }
              }
            }
          });
        }
      } catch (e) {
        debugPrint('[CitizenProfileSetupPage] _loadExistingProfile error: $e');
      }
    } else {
      // If guest or no previous info, default full name from Clerk if available
      if (auth.userName.isNotEmpty && auth.userName != 'Citizen') {
        _fullNameController.text = auth.userName;
      }
    }

    if (mounted) {
      setState(() => _isLoadingProfile = false);
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _dobController.dispose();
    _otherDistrictController.dispose();
    _tehsilController.dispose();
    _familyIdController.dispose();
    _schoolCollegeController.dispose();
    super.dispose();
  }

  Future<void> _selectDateOfBirth(BuildContext context) async {
    DateTime initialDate = DateTime(2000, 1, 1);
    final text = _dobController.text.trim();
    if (text.isNotEmpty) {
      try {
        final parts = text.replaceAll('-', '/').replaceAll(' ', '').split('/');
        if (parts.length == 3) {
          int d = int.parse(parts[0]);
          int m = int.parse(parts[1]);
          int y = int.parse(parts[2]);
          initialDate = DateTime(y, m, d);
        }
      } catch (_) {}
    }

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
      helpText: 'SELECT YOUR DATE OF BIRTH',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: primaryNavy,
              onPrimary: Colors.white,
              onSurface: textMain,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: primaryNavy),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final day = picked.day.toString().padLeft(2, '0');
      final month = picked.month.toString().padLeft(2, '0');
      final year = picked.year.toString();
      setState(() {
        _dobController.text = '$day / $month / $year';
      });
    }
  }

  void _nextStep() {
    if (_currentStep == 1) {
      if (_fullNameController.text.trim().isEmpty) {
        _showError('Please enter your full legal name as per ID');
        return;
      }
      if (_dobController.text.trim().isEmpty) {
        _showError('Please select or enter your Date of Birth');
        return;
      }
    } else if (_currentStep == 2) {
      if (_selectedDistrict == 'Other' && _otherDistrictController.text.trim().isEmpty) {
        _showError('Please enter your specific District / City name');
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
      final effectiveDistrict = _selectedDistrict == 'Other'
          ? (_otherDistrictController.text.trim().isNotEmpty
              ? _otherDistrictController.text.trim()
              : 'Other')
          : _selectedDistrict;

      final auth = ClerkAuthService.instance;
      final effectiveEmail = widget.initialEmail ?? auth.userEmail;
      final clerkUid = auth.clerkUserId;

      final formData = CitizenFormData(
        fullName: _fullNameController.text.trim(),
        dob: _dobController.text.trim(),
        gender: _selectedGender,
        maritalStatus: _selectedMaritalStatus,
        state: _selectedState,
        district: effectiveDistrict,
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
        annualIncome: _selectedAnnualIncome,
        documents: _selectedDocuments.toList(),
        email: effectiveEmail,
        clerkUserId: clerkUid,
      );

      // Cache user selected state locally for quick access
      FormService.cachedUserState = _selectedState;
      await AppPreferences.instance.setStateName(
        _selectedState,
        email: effectiveEmail,
        clerkUserId: clerkUid,
      );
      await FormService.instance.markProfileCompletedLocally(
        email: effectiveEmail,
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
    if (_isLoadingProfile) {
      return Scaffold(
        backgroundColor: neutralBg,
        appBar: _buildHeader(),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: primaryNavy),
              SizedBox(height: 16),
              Text(
                'Loading your profile...',
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

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

  void _showFormLanguageDialog() {
    final langs = AppPreferences.supportedLanguages;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder: (ctx) {
        final currentLang = AppPreferences.instance.currentLanguage;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Select Language / भाषा चुनें',
                  style: TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: primaryNavyDark,
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: langs.length,
                  itemBuilder: (ctx, i) {
                    final l = langs[i];
                    final isSel = l == currentLang;
                    return ListTile(
                      title: Text(
                        l,
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                          color: isSel ? primaryNavy : textMain,
                        ),
                      ),
                      trailing: isSel
                          ? const Icon(Icons.check_circle_rounded, color: primaryNavy)
                          : null,
                      onTap: () async {
                        Navigator.pop(ctx);
                        final auth = ClerkAuthService.instance;
                        await AppPreferences.instance.setLanguage(
                          l,
                          email: auth.userEmail,
                          clerkUserId: auth.clerkUserId,
                        );
                        if (mounted) {
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('✓ Language set to $l'),
                              backgroundColor: primaryNavy,
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // APP BAR
  PreferredSizeWidget _buildHeader() {
    final curLang = AppPreferences.instance.currentLanguage;
    final langLabel = curLang == 'English' ? 'EN | हिं' : curLang;

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
        GestureDetector(
          onTap: _showFormLanguageDialog,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: slateBorder),
              borderRadius: BorderRadius.circular(6),
              color: Colors.white,
            ),
            child: Center(
              child: Text(
                langLabel,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: textMain,
                ),
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
        InkWell(
          onTap: () => _selectDateOfBirth(context),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: slateBorder),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_month_rounded, color: primaryNavy, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _dobController.text.trim().isNotEmpty
                        ? _dobController.text.trim()
                        : 'Select Date of Birth (DD / MM / YYYY)',
                    style: TextStyle(
                      fontSize: 14,
                      color: _dobController.text.trim().isNotEmpty ? textMain : textSoft,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: primaryNavy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Pick Date',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: primaryNavy,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
                if (val != null) {
                  setState(() {
                    _selectedState = val;
                    final districts = _currentDistricts;
                    if (!districts.contains(_selectedDistrict)) {
                      _selectedDistrict = districts.first;
                    }
                  });
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 20),

        // District Dropdown
        _buildFieldLabel('District / City * (Filtered by State)', required: true),
        const SizedBox(height: 4),
        Text(
          'Select from verified districts in $_selectedState, or choose "Other" to enter manually.',
          style: const TextStyle(fontSize: 12, color: textSoft),
        ),
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
              value: _currentDistricts.contains(_selectedDistrict)
                  ? _selectedDistrict
                  : 'Other',
              items: _currentDistricts
                  .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedDistrict = val);
              },
            ),
          ),
        ),

        // If "Other" is chosen, reveal custom District / City text input
        if (_selectedDistrict == 'Other') ...[
          const SizedBox(height: 12),
          _buildFieldLabel('Enter District / City Name *', required: true),
          const SizedBox(height: 6),
          _buildTextField(
            controller: _otherDistrictController,
            hint: 'e.g., Your District or Municipal City in $_selectedState',
            prefixIcon: Icons.location_on_outlined,
          ),
        ],
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    'School',
                    'College / University',
                    'ITI / Polytechnic'
                  ].map((lvl) {
                    final isSel = _studyLevel == lvl;
                    return ChoiceChip(
                      label: Text(lvl),
                      selected: isSel,
                      onSelected: (val) {
                        if (val) {
                          setState(() {
                            _studyLevel = lvl;
                            final courses = _currentCourses;
                            if (!courses.contains(_selectedCourse)) {
                              _selectedCourse = courses.first;
                            }
                          });
                        }
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
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                _buildFieldLabel('Current Class / Course (Filtered by Education Level)'),
                const SizedBox(height: 4),
                Text(
                  'Showing eligible courses for $_studyLevel.',
                  style: const TextStyle(fontSize: 12, color: textSoft),
                ),
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
                      value: _currentCourses.contains(_selectedCourse)
                          ? _selectedCourse
                          : _currentCourses.first,
                      items: _currentCourses
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    'Government',
                    'Government-aided',
                    'Private',
                  ].map((inst) {
                    final isSel = _institutionType == inst;
                    return ChoiceChip(
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

        // Annual Household Income Field
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
                  Icon(Icons.currency_rupee_rounded, color: primaryNavy, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Annual Family / Household Income',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: primaryNavyDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Required to verify income ceiling caps for scholarships, free fee remissions, and subsidized grants.',
                style: TextStyle(fontSize: 12, color: textSoft),
              ),
              const SizedBox(height: 12),
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
                    value: _selectedAnnualIncome,
                    items: _incomeBrackets
                        .map((inc) => DropdownMenuItem(
                              value: inc,
                              child: Text(inc, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedAnnualIncome = val);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

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
                  'Tip: Ensure your income range aligns with your official Tehsildar Income Certificate (Niwas/Aay Praman Patra) for verification.',
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

        // Caste Certificate Status (Conditional on Affirmative Category)
        if (_socialCategory != 'General (Unreserved)' && _socialCategory != 'Not Sure / General / Unspecified') ...[
          _buildFieldLabel('Caste / Category Certificate Status*', required: true),
          const SizedBox(height: 4),
          Text(
            'State-issued physical or digital certificate required for $_socialCategory quota / fee exemptions.',
            style: const TextStyle(fontSize: 12, color: textSoft),
          ),
          const SizedBox(height: 10),
          _buildRadioCard(
            title: 'Yes (Available)',
            desc: 'Verified certificate document with registration / barcode number',
            icon: Icons.check_circle_outline,
            value: 'Yes (Available)',
            groupValue: _casteCertStatus,
            onChanged: (v) => setState(() => _casteCertStatus = v!),
          ),
          _buildRadioCard(
            title: 'No',
            desc: 'Do not possess an official certificate document',
            icon: Icons.cancel_outlined,
            value: 'No',
            groupValue: _casteCertStatus,
            onChanged: (v) => setState(() => _casteCertStatus = v!),
          ),
          _buildRadioCard(
            title: 'Not Sure / In Progress / Don\'t Know',
            desc: 'Application in progress at Tehsil or CSC center',
            icon: Icons.pending_actions_outlined,
            value: 'Not Sure / In Progress / Don\'t Know',
            groupValue: _casteCertStatus,
            onChanged: (v) => setState(() => _casteCertStatus = v!),
          ),
          const SizedBox(height: 20),
        ],

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
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
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
              mainAxisSize: MainAxisSize.min,
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
              // ignore: deprecated_member_use
              Radio<String>(
                value: value,
                // ignore: deprecated_member_use
                groupValue: groupValue,
                activeColor: primaryNavy,
                // ignore: deprecated_member_use
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
