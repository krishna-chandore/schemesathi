import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../auth/auth.dart';
import '../citizen_form/app_preferences.dart';
import '../citizen_form/form_service.dart';
import '../profile/profile_page.dart';
import '../schemes/scheme_model.dart';
import '../schemes/scheme_service.dart';
import '../schemes/schemes_page.dart';
import 'categories_directory_page.dart';

// ---------------------------------------------------------------------------
// SchemeSathi Home Dashboard
// Displayed after citizen profile form is submitted
// ---------------------------------------------------------------------------
class SchemeSathiHomePage extends StatefulWidget {
  final String? userName;
  const SchemeSathiHomePage({super.key, this.userName});

  @override
  State<SchemeSathiHomePage> createState() => _SchemeSathiHomePageState();
}

class _SchemeSathiHomePageState extends State<SchemeSathiHomePage> {
  int _selectedTab = 0;
  String _selectedLanguage = AppPreferences.instance.currentLanguage;
  int _selectedFilter = 0;   // 0=All 1=Likely Eligible 2=Action Needed 3=New
  String? _selectedCategoryFilter;
  int? _schemesInitialFilterIndex;
  String _userState = AppPreferences.instance.currentState;
  String? _schemesInitialSearchQuery; // For unified search bar

  // Search controller for top bar
  final TextEditingController _topSearchController = TextEditingController();

  // Personalized Eligibility & Recommendations state
  List<SchemeItem> _recommendedSchemes = [];
  bool _isLoadingRecommendations = false;
  int _eligibleCount = 0;
  int _profileCompletionPct = 70;

  // Upcoming Milestones state
  List<Map<String, dynamic>> _upcomingMilestones = [];
  bool _isLoadingMilestones = false;

  // Latest Schemes state
  List<SchemeItem> _latestSchemes = [];
  bool _isLoadingLatestSchemes = false;

  // Notifications state
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoadingNotifications = false;
  int _unreadNotificationsCount = 0;
  String _notificationsFilter = 'All'; // 'All', 'Action Needed', 'New Schemes'

  @override
  void initState() {
    super.initState();
    AppPreferences.instance.addListener(_onPreferencesChanged);
    _resolveUserState();
    _loadPersonalizedEligibility();
    _loadUpcomingMilestones();
    _loadLatestSchemes();
    _loadNotifications();
  }

  @override
  void dispose() {
    AppPreferences.instance.removeListener(_onPreferencesChanged);
    _topSearchController.dispose();
    super.dispose();
  }

  void _onPreferencesChanged() {
    if (!mounted) return;
    final newState = AppPreferences.instance.currentState;
    final newLang = AppPreferences.instance.currentLanguage;
    final stateChanged = newState != _userState;
    setState(() {
      _userState = newState;
      _selectedLanguage = newLang;
    });
    if (stateChanged) {
      _loadPersonalizedEligibility();
      _loadLatestSchemes();
      _loadNotifications();
    }
  }

  Future<void> _loadNotifications() async {
    if (mounted) setState(() => _isLoadingNotifications = true);
    try {
      final auth = ClerkAuthService.instance;
      final res = await SchemeService.instance.fetchNotifications(
        email: auth.userEmail,
        clerkUserId: auth.clerkUserId,
        state: _userState,
      );
      if (mounted) {
        final list = (res['notifications'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final unread = (res['unread_count'] as int?) ?? list.length;
        setState(() {
          _notifications = list;
          _unreadNotificationsCount = unread;
          _isLoadingNotifications = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('[HomePage] Error loading notifications: $e');
    }
    if (mounted) setState(() => _isLoadingNotifications = false);
  }

  Future<void> _loadLatestSchemes() async {
    if (mounted) setState(() => _isLoadingLatestSchemes = true);
    try {
      final list = await SchemeService.instance.fetchLatestSchemes(
        state: _userState,
        limit: 8,
      );
      if (mounted) {
        setState(() {
          _latestSchemes = list;
          _isLoadingLatestSchemes = false;
          // If recommendations are still showing static defaults (no real data),
          // upgrade them now that we have real backend schemes with full details
          final isShowingDefaults = _recommendedSchemes.isNotEmpty &&
              _recommendedSchemes.every((s) =>
                  s.eligibility == null &&
                  s.passedConditions.isEmpty &&
                  s.documentsRequired == null);
          if (!_isLoadingRecommendations && isShowingDefaults && list.isNotEmpty) {
            _recommendedSchemes = list;
          }
        });
        return;
      }
    } catch (e) {
      debugPrint('[HomePage] Error loading latest schemes: $e');
    }
    if (mounted) setState(() => _isLoadingLatestSchemes = false);
  }

  Future<void> _resolveUserState() async {
    // 1. Check in-memory cache from form submission
    if (FormService.cachedUserState != null && FormService.cachedUserState!.isNotEmpty) {
      if (mounted) setState(() => _userState = FormService.cachedUserState!);
      return;
    }
    // 2. Fetch from backend profile
    try {
      final state = await FormService.instance.fetchUserProfileState(name: widget.userName);
      if (mounted && state != null && state.isNotEmpty) {
        setState(() => _userState = state);
        _loadLatestSchemes();
        _loadNotifications();
      }
    } catch (_) {}
  }

  Future<void> _loadPersonalizedEligibility() async {
    if (mounted) setState(() => _isLoadingRecommendations = true);
    final auth = ClerkAuthService.instance;
    final email = auth.userEmail;
    final uid = auth.clerkUserId;
    final token = auth.sessionToken;

    try {
      // 1. Fetch user completion percentage if available
      if ((email != null && email.isNotEmpty) || (uid != null && uid.isNotEmpty)) {
        final profile = await FormService.instance.fetchFullProfile(
          clerkUserId: uid,
          email: email,
        );
        if (profile != null && profile['profile_completion_percentage'] != null) {
          final pct = profile['profile_completion_percentage'];
          if (pct is num && mounted) {
            setState(() => _profileCompletionPct = pct.toInt());
          }
        }
      }

      // 2. Fetch personalized recommendations from Eligibility Engine
      final recsMap = await SchemeService.instance.fetchPersonalizedRecommendations(
        clerkUserId: uid,
        sessionToken: token,
        email: email,
        state: _userState,
        limit: 50,
      );

      final eligible = recsMap['eligible'] ?? [];
      final needsMore = recsMap['needs_more_information'] ?? [];
      final appClosed = recsMap['application_closed'] ?? [];

      final combined = [...eligible, ...needsMore, ...appClosed];
      if (mounted) {
        setState(() {
          if (combined.isNotEmpty) {
            _recommendedSchemes = combined;
          } else {
            // Fall back to latest schemes from backend (which have full details)
            // _latestSchemes is already loading concurrently; if available use them,
            // otherwise keep empty until they load (or fall back to defaults)
            _recommendedSchemes = _latestSchemes.isNotEmpty
                ? _latestSchemes
                : SchemeItem.getDefaultSchemes();
          }
          _eligibleCount = eligible.isNotEmpty ? eligible.length : 14;
          _isLoadingRecommendations = false;
        });
      }
    } catch (e) {
      debugPrint('[HomePage] Error loading personalized eligibility: $e');
      if (mounted) {
        setState(() {
          _recommendedSchemes = _latestSchemes.isNotEmpty
              ? _latestSchemes
              : SchemeItem.getDefaultSchemes();
          _isLoadingRecommendations = false;
        });
      }
    }
  }

  Future<void> _loadUpcomingMilestones() async {
    if (mounted) setState(() => _isLoadingMilestones = true);
    try {
      final auth = ClerkAuthService.instance;
      final email = auth.userEmail;
      final uid = auth.clerkUserId;

      final queryParams = <String, String>{};
      if (email != null && email.isNotEmpty) queryParams['email'] = email;
      if (uid != null && uid.isNotEmpty) queryParams['clerk_user_id'] = uid;

      final uri = Uri.parse('${SchemeService.baseUrl}/upcoming-milestones')
          .replace(queryParameters: queryParams);

      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final raw = data['milestones'];
        if (raw is List) {
          setState(() {
            _upcomingMilestones = raw.cast<Map<String, dynamic>>();
            _isLoadingMilestones = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('[HomePage] Error loading upcoming milestones: $e');
    }
    if (mounted) setState(() => _isLoadingMilestones = false);
  }

  void _navigateToEligibleSchemes() {
    setState(() {
      _selectedCategoryFilter = null;
      _schemesInitialFilterIndex = 1; // Tab 1: '✨ Eligible for Me'
      _selectedTab = 1;               // Switch to Schemes Page
    });
  }

  void _openCategory(String category) {
    setState(() {
      _selectedCategoryFilter = category;
      _schemesInitialFilterIndex = null;
      _selectedTab = 1;
    });
  }

  void _showLanguageSelectionDialog() {
    final langs = AppPreferences.supportedLanguages;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder: (ctx) {
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
                    color: Color(0xFF0F172A),
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
                    final isSel = l == _selectedLanguage;
                    return ListTile(
                      title: Text(
                        l,
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                          color: isSel ? _emerald : const Color(0xFF0F172A),
                        ),
                      ),
                      trailing: isSel
                          ? const Icon(Icons.check_circle_rounded, color: _emerald)
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
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('✓ Language set to $l'),
                              backgroundColor: _emerald,
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

  static const _languages = ['English', 'हिन्दी', 'मराठी', 'বাংলা', 'ગુજરાતી', 'தமிழ்'];
  static const _filters   = ['All', 'Likely Eligible', 'Action Needed', 'New'];

  // Design tokens
  static const _dark    = Color(0xFF0F172A);
  static const _navy    = Color(0xFF12263F);
  static const _muted   = Color(0xFF64748B);
  static const _border  = Color(0xFFF1F5F9);
  static const _bg      = Color(0xFFF7F9FA);
  static const _emerald = Color(0xFF22A06B);
  static const _emeraldLight = Color(0xFFECFDF5);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: _selectedTab == 1
                  ? SchemesContentView(
                      key: ValueKey('schemes_${_userState}_${_selectedCategoryFilter}_$_schemesInitialFilterIndex${_schemesInitialSearchQuery ?? ''}'),
                      onBack: () => setState(() {
                        _selectedCategoryFilter = null;
                        _schemesInitialFilterIndex = null;
                        _schemesInitialSearchQuery = null;
                        _topSearchController.clear();
                        _selectedTab = 0;
                      }),
                      initialCategory: _selectedCategoryFilter,
                      initialState: _userState,
                      initialFilterIndex: _schemesInitialFilterIndex,
                      initialSearchQuery: _schemesInitialSearchQuery,
                    )
                  : _selectedTab == 3
                      ? _buildNotificationsTabView()
                      : _selectedTab == 4
                          ? SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              child: ProfileContentView(
                                userName: widget.userName,
                                onOpenReminders: _showAllMilestonesSheet,
                                onOpenMySchemes: _navigateToEligibleSchemes,
                                onStateChanged: (newState) {
                                  setState(() => _userState = newState);
                                  _loadPersonalizedEligibility();
                                  _loadLatestSchemes();
                                  _loadNotifications();
                                },
                                onLanguageChanged: (newLang) {
                                  setState(() => _selectedLanguage = newLang);
                                },
                              ),
                            )
                          : SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildHeroBanner(),
                              const SizedBox(height: 12),
                              _buildProfileCompletion(),
                              const SizedBox(height: 16),
                              _buildExploreCategories(),
                              const SizedBox(height: 16),
                              _buildRecommendedSection(),
                              const SizedBox(height: 16),
                              _buildUpcomingSection(),
                              const SizedBox(height: 16),
                              _buildQuickActions(),
                              const SizedBox(height: 16),
                              _buildLatestSchemes(),
                              const SizedBox(height: 80),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ── Top Bar ──────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    final name = widget.userName ?? 'Citizen';
    return Container(
      color: _bg,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        children: [
          // Greeting row
          Row(
            children: [
              // Avatar (tap to open profile)
              GestureDetector(
                onTap: () => setState(() => _selectedTab = 4),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF4F46E5),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6)],
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'C',
                      style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedTab = 4),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Namaste, $name',
                              style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A), fontFamily: 'Plus Jakarta Sans',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text('👋', style: TextStyle(fontSize: 15)),
                        ],
                      ),
                      const Text(
                        "Let's build a better tomorrow",
                        style: TextStyle(
                          fontSize: 11.5, color: _muted,
                          fontWeight: FontWeight.w500, fontFamily: 'Plus Jakarta Sans',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Notification bell
              GestureDetector(
                onTap: () => setState(() => _selectedTab = 3),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle,
                    border: Border.all(color: _border),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
                  ),
                  child: Stack(
                    children: [
                      const Center(
                        child: Icon(Icons.notifications_outlined, size: 20, color: Color(0xFF475569)),
                      ),
                      if (_unreadNotificationsCount > 0)
                        Positioned(
                          top: 8, right: 8,
                          child: Container(
                            width: 8, height: 8,
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_selectedTab == 0) ...[
            const SizedBox(height: 12),

            // Search bar
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
            ),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 14),
                  child: Icon(Icons.search_rounded, size: 18, color: _muted),
                ),
                Expanded(
                  child: TextField(
                    controller: _topSearchController,
                    style: const TextStyle(fontSize: 13, fontFamily: 'Plus Jakarta Sans'),
                    decoration: const InputDecoration(
                      hintText: 'Search schemes, documents...',
                      hintStyle: TextStyle(fontSize: 13, color: _muted),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 13),
                    ),
                    onSubmitted: (query) {
                      if (query.trim().isNotEmpty) {
                        setState(() {
                          _schemesInitialSearchQuery = query.trim();
                          _selectedCategoryFilter = null;
                          _schemesInitialFilterIndex = 0;
                          _selectedTab = 1;
                        });
                      }
                    },
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _topSearchController,
                  builder: (context, value, _) {
                    if (value.text.isNotEmpty) {
                      return IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18, color: _muted),
                        onPressed: () => _topSearchController.clear(),
                        padding: const EdgeInsets.only(right: 4),
                        constraints: const BoxConstraints(),
                      );
                    }
                    return const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: Icon(Icons.mic_none_rounded, size: 18, color: _muted),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Language chips
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _languages.length + 1,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                if (i == _languages.length) {
                  return GestureDetector(
                    onTap: () {
                      _showLanguageSelectionDialog();
                    },
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Icon(Icons.more_horiz, size: 16, color: _muted),
                    ),
                  );
                }
                final lang = _languages[i];
                final selected = lang == _selectedLanguage;
                return GestureDetector(
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final auth = ClerkAuthService.instance;
                    await AppPreferences.instance.setLanguage(
                      lang,
                      email: auth.userEmail,
                      clerkUserId: auth.clerkUserId,
                    );
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('✓ Language switched to $lang'),
                          backgroundColor: _dark,
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected ? _dark : Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: selected ? _dark : const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      lang,
                      style: TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : _muted,
                        fontFamily: 'Plus Jakarta Sans',
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    ),
  );
  }

  // ── Hero Banner ───────────────────────────────────────────────────────────
  Widget _buildHeroBanner() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF7ED), Color(0xFFFEFCE8), Color(0xFFF0FDF4)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFDE68A).withValues(alpha: 0.6)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Stack(
        children: [
          // Ambient glow
          Positioned(
            top: -30, right: -20,
            child: Container(
              width: 120, height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFFFBBF24).withValues(alpha: 0.25),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Government Schemes\nMade Simple for Everyone',
                            style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A), height: 1.3,
                              fontFamily: 'Plus Jakarta Sans',
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Find schemes, check eligibility, know required documents and get official links — all in one place.',
                            style: TextStyle(
                              fontSize: 11.5, color: Color(0xFF475569),
                              height: 1.5, fontFamily: 'Plus Jakarta Sans',
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Parliament SVG placeholder
                    const SizedBox(width: 12),
                    CustomPaint(
                      size: const Size(80, 64),
                      painter: _ParliamentPainter(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _navigateToEligibleSchemes,
                  icon: const Text('', style: TextStyle(fontSize: 0)),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _eligibleCount > 0
                            ? 'Check My Eligibility ($_eligibleCount Eligible)'
                            : 'Check My Eligibility',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_forward_rounded, size: 14),
                    ],
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _dark, foregroundColor: Colors.white,
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  ),
                ),
                const SizedBox(height: 14),
                // Dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (i) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: i == 0 ? 8 : 6, height: i == 0 ? 8 : 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == 0 ? _dark : const Color(0xFFCBD5E1),
                    ),
                  )),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Profile Completion ────────────────────────────────────────────────────
  Widget _buildProfileCompletion() {
    final pct = _profileCompletionPct.clamp(10, 100);
    return GestureDetector(
      onTap: () {
        Navigator.of(context).pushNamed('/form', arguments: ClerkAuthService.instance.userEmail);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFF4F46E5), Color(0xFFEC4899)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: const Color(0xFF4F46E5).withValues(alpha: 0.3), blurRadius: 8)],
              ),
              child: const Icon(Icons.task_alt_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Complete Your Profile',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _dark, fontFamily: 'Plus Jakarta Sans')),
                      Text('$pct%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _emerald)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: pct / 100.0, minHeight: 6,
                      backgroundColor: const Color(0xFFF1F5F9),
                      valueColor: AlwaysStoppedAnimation<Color>(_emerald),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('Get more accurate scheme recommendations',
                    style: TextStyle(fontSize: 10.5, color: _muted, fontFamily: 'Plus Jakarta Sans'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: _muted, size: 20),
          ],
        ),
      ),
    );
  }

  // ── Explore Categories ────────────────────────────────────────────────────
  Widget _buildExploreCategories() {
    final categories = [
      _CategoryItem('Agriculture\n& Farmers', Icons.eco_rounded, const Color(0xFFD1FAE5), const Color(0xFF059669), 'Agriculture'),
      _CategoryItem('Students\n& Education', Icons.school_rounded, const Color(0xFFE0F2FE), const Color(0xFF0284C7), 'Education'),
      _CategoryItem('Women &\nChild Welfare', Icons.diversity_1_rounded, const Color(0xFFFCE7F3), const Color(0xFFDB2777), 'Women and Child'),
      _CategoryItem('Senior\nCitizens', Icons.elderly_rounded, const Color(0xFFFEF3C7), const Color(0xFFD97706), 'Social welfare'),
      _CategoryItem('Health &\nInsurance', Icons.favorite_rounded, const Color(0xFFFEE2E2), const Color(0xFFEF4444), 'Health'),
      _CategoryItem('Employment\n& Skills', Icons.work_rounded, const Color(0xFFF3E8FF), const Color(0xFF7C3AED), 'Skills & Employment'),
      _CategoryItem('Housing &\nUrban Dev.', Icons.home_work_rounded, const Color(0xFFCFFAFE), const Color(0xFF0891B2), 'Housing'),
      _CategoryItem('Business\n& Startups', Icons.trending_up_rounded, const Color(0xFFE0E7FF), const Color(0xFF4338CA), 'Business'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'Explore by Category',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _dark,
                  fontFamily: 'Plus Jakarta Sans',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => CategoriesDirectoryPage(
                      userName: widget.userName,
                      userState: _userState,
                      onSelectCategory: (query) {
                        Navigator.of(context).pop();
                        _openCategory(query);
                      },
                    ),
                  ),
                );
              },
              child: const Text('See All →',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF2563EB))),
            ),
          ],
        ),
        const SizedBox(height: 2),
        GridView.count(
          crossAxisCount: 4, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.72,
          children: categories.map((c) => _buildCategoryCard(c)).toList(),
        ),
      ],
    );
  }

  Widget _buildCategoryCard(_CategoryItem c) {
    return GestureDetector(
      onTap: () => _openCategory(c.categoryQuery),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6)],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(color: c.bgColor, borderRadius: BorderRadius.circular(12)),
              child: Icon(c.icon, color: c.iconColor, size: 22),
            ),
            const SizedBox(height: 6),
            Text(c.label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: _dark, height: 1.3, fontFamily: 'Plus Jakarta Sans'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Recommended Section ───────────────────────────────────────────────────
  Widget _buildRecommendedSection() {
    List<SchemeItem> schemesToShow = _recommendedSchemes;
    if (_selectedFilter == 1) {
      schemesToShow = schemesToShow.where((s) => s.isEligible || s.matchPercentage >= 85).toList();
    } else if (_selectedFilter == 2) {
      schemesToShow = schemesToShow.where((s) => s.missingDocuments.isNotEmpty || s.failedConditions.isNotEmpty).toList();
    }

    if (schemesToShow.isEmpty && _recommendedSchemes.isNotEmpty) {
      schemesToShow = _recommendedSchemes;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  const Text(
                    'Recommended for You',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _dark,
                      fontFamily: 'Plus Jakarta Sans',
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_eligibleCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _emeraldLight,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '$_eligibleCount Eligible',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF065F46),
                          fontFamily: 'Plus Jakarta Sans',
                        ),
                      ),
                    ),
                ],
              ),
            ),
            TextButton(
              onPressed: _navigateToEligibleSchemes,
              child: const Text(
                'View All',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2563EB),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Filter chips
        SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _filters.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final sel = i == _selectedFilter;
              return GestureDetector(
                onTap: () => setState(() => _selectedFilter = i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? _dark : (i == 1 ? const Color(0xFFDBEAFE) : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(_filters[i],
                    style: TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : (i == 1 ? const Color(0xFF1D4ED8) : const Color(0xFF475569)),
                      fontFamily: 'Plus Jakarta Sans',
                    )),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),

        if (_isLoadingRecommendations)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: CircularProgressIndicator(color: _emerald),
            ),
          )
        else ...[
          for (int idx = 0; idx < schemesToShow.take(3).length; idx++) ...[
            _buildSchemeCardFromItem(schemesToShow[idx]),
            if (idx < schemesToShow.take(3).length - 1) const SizedBox(height: 12),
          ],
        ],
      ],
    );
  }

  Widget _buildSchemeCardFromItem(SchemeItem scheme) {
    final badge = scheme.matchBadge.isNotEmpty ? scheme.matchBadge : 'Likely Eligible';
    final badgeColor = scheme.matchBadgeBg;
    final badgeTextColor = scheme.matchBadgeTextColor;

    final tags = <_TagItem>[];
    tags.add(_TagItem(
      scheme.level.isNotEmpty ? '${scheme.level} Scheme' : 'Central Scheme',
      const Color(0xFFFFF7ED),
      const Color(0xFF92400E),
    ));
    if (scheme.category.isNotEmpty && scheme.category != 'General') {
      tags.add(_TagItem(
        scheme.category,
        _emeraldLight,
        const Color(0xFF065F46),
      ));
    }
    if (scheme.benefitAmount.isNotEmpty) {
      tags.add(_TagItem(
        scheme.benefitAmount,
        const Color(0xFFDBEAFE),
        const Color(0xFF1D4ED8),
      ));
    }

    return _buildSchemeCard(
      badge: badge,
      badgeColor: badgeColor,
      badgeTextColor: badgeTextColor,
      badgeDot: scheme.failedConditions.isNotEmpty ? const Color(0xFFD97706) : null,
      title: scheme.title,
      subtitle: scheme.description,
      tags: tags,
      imageIcon: scheme.iconFallback,
      imageColor: scheme.iconBg,
      buttonLabel: 'View Details →',
      onTap: () => _showSchemeDetails(scheme),
    );
  }

  void _showSchemeDetails(SchemeItem scheme) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: scheme.matchBadgeBg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          scheme.matchBadge,
                          style: TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: scheme.matchBadgeTextColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F3FF),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          scheme.level,
                          style: const TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF3525CD),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    scheme.title,
                    style: const TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF131B2E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    scheme.description,
                    style: const TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 14,
                      color: Color(0xFF464555),
                      height: 1.5,
                    ),
                  ),
                  if (scheme.benefitAmount.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.currency_rupee_rounded, color: Color(0xFF15803D), size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Benefit: ${scheme.benefitAmount}',
                              style: const TextStyle(
                                fontFamily: 'Plus Jakarta Sans',
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF15803D),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  // Eligibility Details (raw text fallback or bullet points)
                  if (scheme.passedConditions.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text(
                      'Eligibility Details',
                      style: TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF131B2E),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...scheme.passedConditions.map(
                      (c) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                c,
                                style: const TextStyle(
                                  fontFamily: 'Plus Jakarta Sans',
                                  fontSize: 13,
                                  color: Color(0xFF464555),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else if (scheme.eligibility != null && scheme.eligibility!.trim().isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text(
                      'Eligibility Details',
                      style: TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF131B2E),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        scheme.eligibility!.replaceAll('&amp;', '&').replaceAll('&quot;', '"').replaceAll('<br>', '\n').trim(),
                        style: const TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 13,
                          height: 1.5,
                          color: Color(0xFF334155),
                        ),
                      ),
                    ),
                  ],

                  if (scheme.missingDocuments.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text(
                      'Documents to Prepare',
                      style: TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF131B2E),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...scheme.missingDocuments.map(
                      (doc) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.description_outlined, color: Color(0xFFD97706), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                doc,
                                style: const TextStyle(
                                  fontFamily: 'Plus Jakarta Sans',
                                  fontSize: 13,
                                  color: Color(0xFF464555),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else if (scheme.documentsRequired != null && scheme.documentsRequired!.trim().isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text(
                      'Documents Required',
                      style: TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF131B2E),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        scheme.documentsRequired!.replaceAll('&amp;', '&').replaceAll('&quot;', '"').replaceAll('<br>', '\n').trim(),
                        style: const TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 13,
                          height: 1.5,
                          color: Color(0xFF334155),
                        ),
                      ),
                    ),
                  ],
                  if (scheme.failedConditions.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text(
                      'Unmet Criteria',
                      style: TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...scheme.failedConditions.map(
                      (f) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.cancel_rounded, color: Color(0xFFDC2626), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                f,
                                style: const TextStyle(
                                  fontFamily: 'Plus Jakarta Sans',
                                  fontSize: 13,
                                  color: Color(0xFF7F1D1D),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // Application Process Steps
                  if (scheme.applicationProcess != null && scheme.applicationProcess!.trim().isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Row(
                      children: [
                        Icon(Icons.directions_walk_rounded, color: Color(0xFF3525CD), size: 20),
                        SizedBox(width: 8),
                        Text(
                          'How to Apply (Process)',
                          style: TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF131B2E),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        scheme.applicationProcess!,
                        style: const TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 13,
                          height: 1.5,
                          color: Color(0xFF334155),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  Row(
                    children: [
                      if (scheme.officialLink != null && scheme.officialLink!.isNotEmpty) ...[
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF3525CD),
                                side: const BorderSide(color: Color(0xFF3525CD)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Portal: ${scheme.officialLink}'),
                                    backgroundColor: const Color(0xFF131B2E),
                                  ),
                                );
                              },
                              child: const Text(
                                'Portal Link',
                                style: TextStyle(
                                  fontFamily: 'Plus Jakarta Sans',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: scheme.isApplicationOpen
                                  ? const Color(0xFF3525CD)
                                  : const Color(0xFF9CA3AF),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 2,
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              final targetLink = scheme.applyLink ?? scheme.officialLink;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(scheme.isApplicationOpen
                                      ? (targetLink != null && targetLink.isNotEmpty
                                          ? 'Opening apply portal: $targetLink'
                                          : 'Starting application for ${scheme.title}...')
                                      : 'Applications are currently closed for this scheme.'),
                                  backgroundColor: scheme.isApplicationOpen
                                      ? const Color(0xFF3525CD)
                                      : const Color(0xFFDC2626),
                                ),
                              );
                            },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(scheme.isApplicationOpen
                                    ? Icons.assignment_turned_in_rounded
                                    : Icons.lock_clock_rounded, size: 18),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    scheme.isApplicationOpen ? 'Apply Now' : 'Closed',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: 'Plus Jakarta Sans',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSchemeCard({
    required String badge,
    required Color badgeColor,
    required Color badgeTextColor,
    Color? badgeDot,
    required String title,
    required String subtitle,
    required List<_TagItem> tags,
    required IconData imageIcon,
    required Color imageColor,
    required String buttonLabel,
    VoidCallback? onTap,
    bool showDots = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: badgeDot != null ? const Color(0xFFFDE68A) : _emeraldLight)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (badgeDot != null) ...[
                      Container(width: 6, height: 6, decoration: BoxDecoration(color: badgeDot, shape: BoxShape.circle)),
                      const SizedBox(width: 5),
                    ] else ...[
                      Icon(Icons.check_rounded, size: 12, color: badgeTextColor),
                      const SizedBox(width: 5),
                    ],
                    Text(badge, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: badgeTextColor, fontFamily: 'Plus Jakarta Sans')),
                  ],
                ),
              ),
              const Icon(Icons.favorite_border_rounded, size: 20, color: _muted),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _dark, fontFamily: 'Plus Jakarta Sans')),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(fontSize: 11, color: _muted, fontFamily: 'Plus Jakarta Sans')),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6, runSpacing: 6,
                      children: tags.map((t) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: t.bg)),
                        child: Text(t.label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: t.text, fontFamily: 'Plus Jakarta Sans')),
                      )).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 76, height: 76,
                decoration: BoxDecoration(color: imageColor, borderRadius: BorderRadius.circular(16)),
                child: Icon(imageIcon, size: 36, color: imageColor == const Color(0xFFFEF3C7) ? const Color(0xFFD97706) : const Color(0xFF0284C7)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onTap ?? _navigateToEligibleSchemes,
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy, foregroundColor: Colors.white,
                elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(buttonLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, fontFamily: 'Plus Jakarta Sans')),
            ),
          ),
          if (showDots) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: i == 1 ? 8 : 6, height: i == 1 ? 8 : 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, color: i == 1 ? _dark : const Color(0xFFCBD5E1),
                ),
              )),
            ),
          ],
        ],
      ),
    );
  }

  // ── Upcoming Section ──────────────────────────────────────────────────────
  Widget _buildUpcomingSection() {
    // Show at most 4 items in the collapsed view
    final visibleMilestones = _upcomingMilestones.take(4).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'Upcoming for You',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _dark,
                  fontFamily: 'Plus Jakarta Sans',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_upcomingMilestones.isNotEmpty)
              TextButton(
                onPressed: () => _showAllMilestonesSheet(),
                child: Text(
                  'View All (${_upcomingMilestones.length})',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2563EB),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),

        // Loading skeleton
        if (_isLoadingMilestones) ...[
          for (int i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _border),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(height: 11, width: 160, decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            )),
                            const SizedBox(height: 6),
                            Container(height: 9, width: 110, decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            )),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ]

        // Empty state: no milestones (profile complete, everything in order)
        else if (visibleMilestones.isEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF6EE7B7)),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 32),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'You\'re All Caught Up! 🎉',
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF064E3B),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'No pending milestones right now. Keep your documents updated.',
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 11.5,
                          color: Color(0xFF047857),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ]

        // Milestone cards
        else ...[
          ...visibleMilestones.map((m) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _MilestoneTile(milestone: m),
          )),
          if (_upcomingMilestones.length > 4)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: GestureDetector(
                onTap: _showAllMilestonesSheet,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F9FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFBAE6FD)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.expand_more_rounded, color: Color(0xFF0284C7), size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'See ${_upcomingMilestones.length - 4} More Milestone${_upcomingMilestones.length - 4 != 1 ? 's' : ''}',
                        style: const TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0284C7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  void _showAllMilestonesSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44, height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Upcoming for You',
                            style: TextStyle(
                              fontFamily: 'Plus Jakarta Sans',
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Personalised milestones based on your profile',
                            style: TextStyle(
                              fontFamily: 'Plus Jakarta Sans',
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF64748B)),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  itemCount: _upcomingMilestones.length,
                  itemBuilder: (_, i) {
                    final m = _upcomingMilestones[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _MilestoneTile(milestone: m, expanded: true),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationsTabView() {
    // Filter notifications based on selected tab filter
    final filtered = _notifications.where((n) {
      if (_notificationsFilter == 'Action Needed') {
        final cat = (n['category'] as String? ?? '').toLowerCase();
        final prio = (n['priority'] as String? ?? '').toLowerCase();
        return cat == 'urgent' || cat == 'document' || prio == 'urgent' || prio == 'high';
      } else if (_notificationsFilter == 'New Schemes') {
        final cat = (n['category'] as String? ?? '').toLowerCase();
        return cat == 'new_scheme' || cat == 'event';
      }
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadNotifications,
      color: _emerald,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: _dark),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() => _selectedTab = 0),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Notifications',
                            style: TextStyle(
                              fontFamily: 'Plus Jakarta Sans',
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: _dark,
                            ),
                          ),
                          if (_unreadNotificationsCount > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$_unreadNotificationsCount NEW',
                                style: const TextStyle(
                                  fontFamily: 'Plus Jakarta Sans',
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Updates, critical document alerts & newly launched schemes',
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 12,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_unreadNotificationsCount > 0)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _unreadNotificationsCount = 0;
                        for (final n in _notifications) {
                          n['is_read'] = true;
                        }
                      });
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Mark all read',
                      style: TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _emerald,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // Notification category pills
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['All', 'Action Needed', 'New Schemes'].map((label) {
                  final active = _notificationsFilter == label;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _notificationsFilter = label),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: active ? _emerald : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: active ? _emerald : const Color(0xFFE2E8F0),
                          ),
                          boxShadow: active
                              ? [BoxShadow(color: _emerald.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 2))]
                              : null,
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontSize: 12,
                            fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                            color: active ? Colors.white : const Color(0xFF475569),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 16),

            if (_isLoadingNotifications) ...[
              for (int i = 0; i < 4; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    height: 85,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _border),
                    ),
                  ),
                ),
            ] else if (filtered.isEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF6EE7B7)),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.mark_email_read_rounded, color: Color(0xFF059669), size: 48),
                    SizedBox(height: 12),
                    Text(
                      'All Caught Up!',
                      style: TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF064E3B),
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'No new notifications right now. Check back when updates or schemes release.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 13,
                        color: Color(0xFF047857),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              ...filtered.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _NotificationCard(
                  notification: item,
                  onSchemeTap: (slug, name) {
                    _navigateToEligibleSchemes();
                  },
                ),
              )),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ── Quick Actions ─────────────────────────────────────────────────────────
  Widget _buildQuickActions() {
    final actions = [
      _QuickAction('Check My\nEligibility', Icons.verified_rounded, const Color(0xFFD1FAE5), _emerald),
      _QuickAction('Track My\nDocuments', Icons.description_outlined, const Color(0xFFE0F2FE), const Color(0xFF0284C7)),
      _QuickAction('Upcoming\nReminders', Icons.notifications_none_rounded, const Color(0xFFFCE7F3), const Color(0xFFDB2777)),
      _QuickAction('Ask AI\nAssistant', Icons.computer_rounded, const Color(0xFFFFF7ED), const Color(0xFFD97706)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Quick Actions',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _dark, fontFamily: 'Plus Jakarta Sans')),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 2.3,
          children: actions.map((a) => GestureDetector(
            onTap: () {
              if (a.label.contains('Eligibility')) {
                _navigateToEligibleSchemes();
              } else if (a.label.contains('Documents')) {
                _showAllMilestonesSheet();
              } else if (a.label.contains('Reminders')) {
                _showAllMilestonesSheet();
              } else {
                _navigateToEligibleSchemes();
              }
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _border),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6)],
              ),
              child: Row(
                children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(color: a.iconBg, borderRadius: BorderRadius.circular(10)),
                    child: Icon(a.icon, color: a.iconColor, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(a.label,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _dark, height: 1.35, fontFamily: 'Plus Jakarta Sans')),
                  ),
                ],
              ),
            ),
          )).toList(),
        ),
        const SizedBox(height: 12),
        // Updates banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFECFDF5), Color(0xFFF0FDFA), Color(0xFFE0F2FE)]),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFD1FAE5)),
          ),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: _emerald, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.campaign_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('New Schemes & Updates',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: _dark, fontFamily: 'Plus Jakarta Sans')),
                  SizedBox(height: 2),
                  Text('3 new updates this month',
                    style: TextStyle(fontSize: 10.5, color: _muted, fontFamily: 'Plus Jakarta Sans')),
                ]),
              ),
              ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: _dark, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 2,
                ),
                child: const Text('View', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, fontFamily: 'Plus Jakarta Sans')),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Latest Schemes ────────────────────────────────────────────────────────
  Widget _buildLatestSchemes() {
    final schemes = _latestSchemes.isNotEmpty
        ? _latestSchemes.take(4).toList()
        : [
            SchemeItem(
              id: 'pm-surya-ghar',
              title: 'PM Surya Ghar Muft Bijli Yojana',
              description: 'Solar rooftop subsidy for households up to 300 units free electricity',
              category: 'Housing',
              level: 'Central',
              matchBadge: 'NEW',
              matchBadgeBg: const Color(0xFFFEF3C7),
              matchBadgeTextColor: const Color(0xFFD97706),
              iconFallback: Icons.wb_sunny_rounded,
              iconBg: const Color(0xFFFEF3C7),
              iconColor: const Color(0xFFD97706),
              benefitAmount: '₹78,000 Subsidy',
              tags: const ['Central', 'Housing', 'Subsidy'],
            ),
            SchemeItem(
              id: 'pm-vishwakarma',
              title: 'PM Vishwakarma Yojana',
              description: 'Holistic support for artisans and craftspeople across 18 trades',
              category: 'Employment',
              level: 'Central',
              matchBadge: 'NEW',
              matchBadgeBg: const Color(0xFFD1FAE5),
              matchBadgeTextColor: const Color(0xFF059669),
              iconFallback: Icons.hardware_rounded,
              iconBg: const Color(0xFFD1FAE5),
              iconColor: const Color(0xFF059669),
              benefitAmount: '₹3 Lakh Loan at 5%',
              tags: const ['Central', 'Skill Development', 'Collateral-free'],
            ),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'Latest Schemes',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _dark,
                  fontFamily: 'Plus Jakarta Sans',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _selectedCategoryFilter = null;
                  _schemesInitialFilterIndex = 0; // Tab 0: All Schemes (ordered by database)
                  _selectedTab = 1;
                });
              },
              child: const Text(
                'View All >',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2563EB),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (_isLoadingLatestSchemes) ...[
          for (int i = 0; i < 2; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _border),
                ),
              ),
            ),
        ] else ...[
          ...schemes.map((s) {
            final tags = <_TagItem>[];
            tags.add(_TagItem(
              s.level.isNotEmpty ? '${s.level} Scheme' : 'Government',
              const Color(0xFFFFF7ED),
              const Color(0xFF92400E),
            ));
            if (s.category.isNotEmpty && s.category != 'General') {
              tags.add(_TagItem(
                s.category,
                _emeraldLight,
                const Color(0xFF065F46),
              ));
            }
            if (s.benefitAmount.isNotEmpty) {
              tags.add(_TagItem(
                s.benefitAmount,
                const Color(0xFFDBEAFE),
                const Color(0xFF1D4ED8),
              ));
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                onTap: () => _showSchemeDetails(s),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: s.iconBg,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          s.iconFallback,
                          size: 26,
                          color: s.iconColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    s.title,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: _dark,
                                      fontFamily: 'Plus Jakarta Sans',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDCFCE7),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'NEW',
                                    style: TextStyle(
                                      fontFamily: 'Plus Jakarta Sans',
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF15803D),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              s.description,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: _muted,
                                fontFamily: 'Plus Jakarta Sans',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: tags.map((t) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: t.bg,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  t.label,
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: t.text,
                                    fontFamily: 'Plus Jakarta Sans',
                                  ),
                                ),
                              )).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF1F5F9),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  // ── Bottom Nav ────────────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    final tabs = [
      _NavTab('Home', Icons.home_rounded),
      _NavTab('Schemes', Icons.grid_view_rounded),
      _NavTab('Documents', Icons.description_outlined),
      _NavTab('Notifications', Icons.notifications_outlined, badge: _unreadNotificationsCount > 0 ? '$_unreadNotificationsCount' : null),
      _NavTab('Profile', Icons.person_outline_rounded),
    ];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: const Color(0xFFE2E8F0).withValues(alpha: 0.8))),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(tabs.length, (i) {
              final active = i == _selectedTab;
              return GestureDetector(
                onTap: () => setState(() => _selectedTab = i),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        children: [
                          Icon(tabs[i].icon,
                            size: 22,
                            color: active ? _emerald : const Color(0xFF94A3B8)),
                          if (tabs[i].badge != null) Positioned(
                            top: -2, right: -4,
                            child: Container(
                              width: 15, height: 15,
                              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                              child: Center(
                                child: Text(tabs[i].badge!, style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(tabs[i].label,
                        style: TextStyle(
                          fontSize: 10, fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                          color: active ? _emerald : const Color(0xFF94A3B8),
                          fontFamily: 'Plus Jakarta Sans',
                        )),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _NotificationCard – renders a rich notification card (Milestone or New Scheme)
// ---------------------------------------------------------------------------
class _NotificationCard extends StatelessWidget {
  final Map<String, dynamic> notification;
  final void Function(String slug, String schemeName) onSchemeTap;

  const _NotificationCard({
    required this.notification,
    required this.onSchemeTap,
  });

  static IconData _resolveIcon(String? name) {
    switch (name) {
      case 'new_releases':        return Icons.auto_awesome_rounded;
      case 'celebration':         return Icons.celebration_rounded;
      case 'cake':                return Icons.cake_rounded;
      case 'how_to_vote':         return Icons.how_to_vote_rounded;
      case 'credit_card':         return Icons.credit_card_rounded;
      case 'directions_car':      return Icons.directions_car_rounded;
      case 'local_shipping':      return Icons.local_shipping_rounded;
      case 'elderly':             return Icons.elderly_rounded;
      case 'fingerprint':         return Icons.fingerprint_rounded;
      case 'home_work':           return Icons.home_work_rounded;
      case 'family_restroom':     return Icons.family_restroom_rounded;
      case 'verified_user':       return Icons.verified_user_rounded;
      case 'receipt_long':        return Icons.receipt_long_rounded;
      case 'account_balance':     return Icons.account_balance_rounded;
      case 'cloud_done':          return Icons.cloud_done_rounded;
      case 'school':              return Icons.school_rounded;
      case 'menu_book':           return Icons.menu_book_rounded;
      case 'workspace_premium':   return Icons.workspace_premium_rounded;
      case 'local_hospital':      return Icons.local_hospital_rounded;
      case 'shield':              return Icons.shield_rounded;
      case 'local_fire_department': return Icons.local_fire_department_rounded;
      case 'favorite':            return Icons.favorite_rounded;
      case 'work':                return Icons.work_rounded;
      case 'engineering':         return Icons.engineering_rounded;
      default:                    return Icons.notifications_active_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = notification['title'] as String? ?? '';
    final message = notification['message'] as String? ?? '';
    final timestamp = notification['timestamp'] as String? ?? 'Recently';
    final actionLabel = notification['action_label'] as String? ?? 'View Details';
    final actionUrl = notification['action_url'] as String? ?? '';
    final schemeSlug = notification['scheme_slug'] as String? ?? '';
    final category = notification['category'] as String? ?? '';
    final priority = notification['priority'] as String? ?? 'medium';
    final isRead = notification['is_read'] as bool? ?? false;

    // Visual styles based on category & priority
    Color accentColor;
    Color iconBg;
    Color badgeBg;
    Color badgeTextColor;
    String badgeLabel;

    if (category == 'new_scheme') {
      accentColor = const Color(0xFF0284C7); // Sky / Blue
      iconBg = const Color(0xFFE0F2FE);
      badgeBg = const Color(0xFFEFF6FF);
      badgeTextColor = const Color(0xFF1D4ED8);
      badgeLabel = 'New Scheme';
    } else if (priority == 'urgent' || priority == 'high') {
      accentColor = const Color(0xFFDC2626); // Red
      iconBg = const Color(0xFFFEE2E2);
      badgeBg = const Color(0xFFFEF2F2);
      badgeTextColor = const Color(0xFFDC2626);
      badgeLabel = 'Action Needed';
    } else if (priority == 'soon') {
      accentColor = const Color(0xFFD97706); // Amber
      iconBg = const Color(0xFFFEF3C7);
      badgeBg = const Color(0xFFFFFBEB);
      badgeTextColor = const Color(0xFFB45309);
      badgeLabel = 'Milestone';
    } else {
      accentColor = const Color(0xFF22A06B); // Emerald
      iconBg = const Color(0xFFECFDF5);
      badgeBg = const Color(0xFFF0FDF4);
      badgeTextColor = const Color(0xFF15803D);
      badgeLabel = 'Update';
    }

    final icon = _resolveIcon(notification['icon'] as String?);

    return Container(
      decoration: BoxDecoration(
        color: isRead ? Colors.white : const Color(0xFFFAFCFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isRead ? const Color(0xFFF1F5F9) : const Color(0xFFDBEAFE),
          width: isRead ? 1 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: accentColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontFamily: 'Plus Jakarta Sans',
                                fontSize: 13,
                                fontWeight: isRead ? FontWeight.w700 : FontWeight.w800,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: badgeBg,
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(color: badgeTextColor.withValues(alpha: 0.2)),
                            ),
                            child: Text(
                              badgeLabel,
                              style: TextStyle(
                                fontFamily: 'Plus Jakarta Sans',
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: badgeTextColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        message,
                        style: const TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 11.5,
                          color: Color(0xFF64748B),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.schedule_rounded, size: 12, color: const Color(0xFF94A3B8)),
                          const SizedBox(width: 4),
                          Text(
                            timestamp,
                            style: const TextStyle(
                              fontFamily: 'Plus Jakarta Sans',
                              fontSize: 10.5,
                              color: Color(0xFF94A3B8),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 14, endIndent: 14, color: Color(0xFFF1F5F9)),
          InkWell(
            onTap: () {
              if (schemeSlug.isNotEmpty) {
                onSchemeTap(schemeSlug, title);
              } else if (actionUrl.isNotEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Opening portal: $actionUrl'),
                    backgroundColor: const Color(0xFF131B2E),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } else {
                onSchemeTap('', title);
              }
            },
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    actionLabel,
                    style: TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    schemeSlug.isNotEmpty ? Icons.arrow_forward_rounded : Icons.open_in_new_rounded,
                    size: 14,
                    color: accentColor,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Data models ───────────────────────────────────────────────────────────────
class _CategoryItem {
  final String label;
  final IconData icon;
  final Color bgColor;
  final Color iconColor;
  final String categoryQuery;
  _CategoryItem(this.label, this.icon, this.bgColor, this.iconColor, this.categoryQuery);
}

class _TagItem {
  final String label;
  final Color bg;
  final Color text;
  _TagItem(this.label, this.bg, this.text);
}

// ---------------------------------------------------------------------------
// _MilestoneTile – renders a single upcoming milestone card
// ---------------------------------------------------------------------------
class _MilestoneTile extends StatelessWidget {
  final Map<String, dynamic> milestone;
  final bool expanded;
  const _MilestoneTile({required this.milestone, this.expanded = false});

  static const _priorityMeta = {
    'urgent':        {'label': 'Action Needed', 'bg': Color(0xFFFEF2F2), 'text': Color(0xFFDC2626), 'dot': Color(0xFFDC2626)},
    'soon':          {'label': 'Coming Soon',   'bg': Color(0xFFFFFBEB), 'text': Color(0xFFD97706), 'dot': Color(0xFFD97706)},
    'upcoming':      {'label': 'Upcoming',      'bg': Color(0xFFEFF6FF), 'text': Color(0xFF2563EB), 'dot': Color(0xFF2563EB)},
    'informational': {'label': 'Know More',     'bg': Color(0xFFF5F3FF), 'text': Color(0xFF7C3AED), 'dot': Color(0xFF7C3AED)},
  };

  static IconData _resolveIcon(String? name) {
    switch (name) {
      case 'cake':                return Icons.cake_rounded;
      case 'how_to_vote':         return Icons.how_to_vote_rounded;
      case 'credit_card':         return Icons.credit_card_rounded;
      case 'directions_car':      return Icons.directions_car_rounded;
      case 'local_shipping':      return Icons.local_shipping_rounded;
      case 'elderly':             return Icons.elderly_rounded;
      case 'fingerprint':         return Icons.fingerprint_rounded;
      case 'home_work':           return Icons.home_work_rounded;
      case 'family_restroom':     return Icons.family_restroom_rounded;
      case 'verified_user':       return Icons.verified_user_rounded;
      case 'receipt_long':        return Icons.receipt_long_rounded;
      case 'account_balance':     return Icons.account_balance_rounded;
      case 'cloud_done':          return Icons.cloud_done_rounded;
      case 'school':              return Icons.school_rounded;
      case 'menu_book':           return Icons.menu_book_rounded;
      case 'workspace_premium':   return Icons.workspace_premium_rounded;
      case 'local_hospital':      return Icons.local_hospital_rounded;
      case 'shield':              return Icons.shield_rounded;
      case 'local_fire_department': return Icons.local_fire_department_rounded;
      case 'favorite':            return Icons.favorite_rounded;
      case 'work':                return Icons.work_rounded;
      case 'engineering':         return Icons.engineering_rounded;
      default:                    return Icons.notifications_rounded;
    }
  }

  static Color _hexColor(String? hex, Color fallback) {
    if (hex == null || hex.isEmpty) return fallback;
    try {
      final clean = hex.replaceAll('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    final priority = milestone['priority'] as String? ?? 'informational';
    final meta = _priorityMeta[priority] ?? _priorityMeta['informational']!;
    final accentColor = _hexColor(milestone['color'] as String?, meta['dot'] as Color);
    final iconBg = Color.lerp(accentColor, Colors.white, 0.82) ?? const Color(0xFFF1F5F9);
    final icon = _resolveIcon(milestone['icon'] as String?);
    final title = milestone['title'] as String? ?? '';
    final subtitle = milestone['subtitle'] as String? ?? '';
    final actionLabel = milestone['action_label'] as String? ?? 'Learn More';
    final actionUrl = milestone['action_url'] as String?;
    final priorityLabel = meta['label'] as String;
    final priorityBg = meta['bg'] as Color;
    final priorityText = meta['text'] as Color;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(14, 14, 14, expanded ? 10 : 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon box
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(13)),
                  child: Icon(icon, color: accentColor, size: 22),
                ),
                const SizedBox(width: 12),
                // Text + badge
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontFamily: 'Plus Jakarta Sans',
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: priorityBg,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 5, height: 5,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: priorityText,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  priorityLabel,
                                  style: TextStyle(
                                    fontFamily: 'Plus Jakarta Sans',
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: priorityText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 11,
                          color: Color(0xFF64748B),
                          height: 1.4,
                        ),
                        maxLines: expanded ? 5 : 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (expanded && actionUrl != null && actionUrl.isNotEmpty) ...[
            const Divider(height: 1, indent: 14, endIndent: 14, color: Color(0xFFF1F5F9)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: SizedBox(
                width: double.infinity,
                height: 38,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Opening: $actionUrl'),
                        backgroundColor: const Color(0xFF131B2E),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 15),
                  label: Text(
                    actionLabel,
                    style: const TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ] else if (!expanded) ...[
            const Divider(height: 1, indent: 14, endIndent: 14, color: Color(0xFFF1F5F9)),
            InkWell(
              onTap: () {
                if (actionUrl != null && actionUrl.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Opening: $actionUrl'),
                      backgroundColor: const Color(0xFF131B2E),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      actionLabel,
                      style: TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(Icons.arrow_forward_rounded, size: 14, color: accentColor),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickAction {
  final String label;
  final IconData icon;
  final Color iconBg, iconColor;
  _QuickAction(this.label, this.icon, this.iconBg, this.iconColor);
}

class _NavTab {
  final String label;
  final IconData icon;
  final String? badge;
  _NavTab(this.label, this.icon, {this.badge});
}

// ── Parliament Painter (decorative vector) ────────────────────────────────────
class _ParliamentPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Base platform
    paint.color = const Color(0xFFDFC09F);
    canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(5, size.height * 0.70, size.width - 10, size.height * 0.25), const Radius.circular(3)), paint);

    // Body
    paint.color = const Color(0xFFEDD6BD);
    canvas.drawRect(Rect.fromLTWH(9, size.height * 0.48, size.width - 18, size.height * 0.22), paint);

    // Pillars
    paint.color = const Color(0xFFB08B5E);
    for (int i = 0; i < 6; i++) {
      final x = 12.0 + i * 10.0;
      canvas.drawRect(Rect.fromLTWH(x, size.height * 0.52, 3, size.height * 0.18), paint);
    }

    // Dome
    paint.color = const Color(0xFFCFA375);
    final domePath = Path()
      ..moveTo(size.width * 0.25, size.height * 0.48)
      ..quadraticBezierTo(size.width * 0.5, size.height * 0.2, size.width * 0.75, size.height * 0.48)
      ..close();
    canvas.drawPath(domePath, paint);

    // Flag mast
    final mastPaint = Paint()
      ..color = const Color(0xFF475569)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(size.width / 2, size.height * 0.22), Offset(size.width / 2, size.height * 0.04), mastPaint);

    // Saffron flag
    paint.color = const Color(0xFFFF9933);
    canvas.drawPath(Path()
      ..moveTo(size.width / 2, size.height * 0.04)
      ..lineTo(size.width / 2 + 14, size.height * 0.06)
      ..lineTo(size.width / 2 + 14, size.height * 0.1)
      ..lineTo(size.width / 2, size.height * 0.12)
      ..close(), paint);

    // Green flag
    paint.color = const Color(0xFF138808);
    canvas.drawPath(Path()
      ..moveTo(size.width / 2, size.height * 0.10)
      ..lineTo(size.width / 2 + 14, size.height * 0.10)
      ..lineTo(size.width / 2 + 14, size.height * 0.15)
      ..lineTo(size.width / 2, size.height * 0.15)
      ..close(), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
