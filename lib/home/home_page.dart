import 'package:flutter/material.dart';

import '../citizen_form/form_service.dart';
import '../profile/profile_page.dart';
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
  int _selectedLanguage = 0; // 0=English 1=Hindi 2=Marathi 3=Bengali
  int _selectedFilter = 0;   // 0=All 1=Likely Eligible 2=Action Needed 3=New
  String? _selectedCategoryFilter;
  String _userState = 'Madhya Pradesh';

  @override
  void initState() {
    super.initState();
    _resolveUserState();
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
      }
    } catch (_) {}
  }

  void _openCategory(String category) {
    setState(() {
      _selectedCategoryFilter = category;
      _selectedTab = 1;
    });
  }

  static const _languages = ['English', 'हिन्दी', 'मराठी', 'বাংলা'];
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
                      key: ValueKey('schemes_${_userState}_$_selectedCategoryFilter'),
                      onBack: () => setState(() {
                        _selectedCategoryFilter = null;
                        _selectedTab = 0;
                      }),
                      initialCategory: _selectedCategoryFilter,
                      initialState: _userState,
                    )
                  : _selectedTab == 4
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          child: ProfileContentView(userName: widget.userName),
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
                          Text(
                            'Namaste, $name',
                            style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A), fontFamily: 'Plus Jakarta Sans',
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
              Container(
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
            ],
          ),
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
                const Expanded(
                  child: TextField(
                    style: TextStyle(fontSize: 13, fontFamily: 'Plus Jakarta Sans'),
                    decoration: InputDecoration(
                      hintText: 'Search schemes, documents...',
                      hintStyle: TextStyle(fontSize: 13, color: _muted),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 13),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Icon(Icons.mic_none_rounded, size: 18, color: _muted),
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
                  return Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Icon(Icons.more_horiz, size: 16, color: _muted),
                  );
                }
                final selected = i == _selectedLanguage;
                return GestureDetector(
                  onTap: () => setState(() => _selectedLanguage = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected ? _dark : Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: selected ? _dark : const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      _languages[i],
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
                  onPressed: () {},
                  icon: const Text('', style: TextStyle(fontSize: 0)),
                  label: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Check My Eligibility', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                      SizedBox(width: 6),
                      Icon(Icons.arrow_forward_rounded, size: 14),
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
    return Container(
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
                    Text('70%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _emerald)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: 0.7, minHeight: 6,
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
            const Text('Explore by Category',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _dark, fontFamily: 'Plus Jakarta Sans')),
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
          crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.82,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Recommended for You',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _dark, fontFamily: 'Plus Jakarta Sans')),
            TextButton(onPressed: () {},
              child: const Text('View All', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF2563EB)))),
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

        // PM Kisan Card
        _buildSchemeCard(
          badge: 'Likely Eligible',
          badgeColor: _emeraldLight,
          badgeTextColor: const Color(0xFF065F46),
          badgeDot: null,
          title: 'PM Kisan Samman Nidhi',
          subtitle: '₹6,000 per year to eligible farmers',
          tags: [
            _TagItem('Central Scheme', const Color(0xFFFFF7ED), const Color(0xFF92400E)),
            _TagItem('Agriculture', _emeraldLight, const Color(0xFF065F46)),
          ],
          imageIcon: Icons.agriculture_rounded,
          imageColor: const Color(0xFFFEF3C7),
          buttonLabel: 'View Details →',
        ),
        const SizedBox(height: 12),

        // Voter ID Card
        _buildSchemeCard(
          badge: 'Action Needed',
          badgeColor: const Color(0xFFFFFBEB),
          badgeTextColor: const Color(0xFF92400E),
          badgeDot: const Color(0xFFD97706),
          title: 'Voter ID Card',
          subtitle: "You'll be 18 soon! Get ready to apply.",
          tags: [
            _TagItem('Age Based', const Color(0xFFDBEAFE), const Color(0xFF1D4ED8)),
            _TagItem('Document', const Color(0xFFF1F5F9), const Color(0xFF475569)),
          ],
          imageIcon: Icons.how_to_vote_rounded,
          imageColor: const Color(0xFFE0F2FE),
          buttonLabel: 'Know How to Apply →',
          showDots: true,
        ),
      ],
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
              onPressed: () {},
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
    final items = [
      _UpcomingItem('Turn 18 in 3 months', 'Apply for Voter ID, PAN Card, Driving Licence',
        Icons.calendar_month_rounded, const Color(0xFFFFF7ED), const Color(0xFFD97706)),
      _UpcomingItem('Complete Education', 'Check scholarship schemes',
        Icons.school_rounded, const Color(0xFFCFFAFE), const Color(0xFF0891B2)),
      _UpcomingItem('Health Coverage', 'Check Ayushman Bharat eligibility',
        Icons.favorite_rounded, const Color(0xFFFEE2E2), const Color(0xFFEF4444)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Upcoming for You',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _dark, fontFamily: 'Plus Jakarta Sans')),
            TextButton(onPressed: () {},
              child: const Text('View All', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF2563EB)))),
          ],
        ),
        const SizedBox(height: 4),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6)],
            ),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: item.iconBg, borderRadius: BorderRadius.circular(12)),
                  child: Icon(item.icon, color: item.iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: _dark, fontFamily: 'Plus Jakarta Sans')),
                      const SizedBox(height: 2),
                      Text(item.subtitle, style: const TextStyle(fontSize: 10.5, color: _muted, fontFamily: 'Plus Jakarta Sans')),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: _muted, size: 20),
              ],
            ),
          ),
        )),
      ],
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
          crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 2.8,
          children: actions.map((a) => GestureDetector(
            onTap: () {},
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
    final schemes = [
      _LatestScheme(
        'PM Surya Ghar Muft Bijli Yojana',
        'Solar rooftop subsidy for households',
        [_TagItem('Central', const Color(0xFFFFF7ED), const Color(0xFF92400E)), _TagItem('Housing', const Color(0xFFCFFAFE), const Color(0xFF0891B2))],
        Icons.wb_sunny_rounded, const Color(0xFFFEF3C7),
      ),
      _LatestScheme(
        'PM Vishwakarma Yojana',
        'Support for artisans and craftsmen',
        [_TagItem('Central', const Color(0xFFFFF7ED), const Color(0xFF92400E)), _TagItem('Skill Development', const Color(0xFFF3E8FF), const Color(0xFF7C3AED))],
        Icons.hardware_rounded, const Color(0xFFD1FAE5),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Latest Schemes',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _dark, fontFamily: 'Plus Jakarta Sans')),
            TextButton(onPressed: () {},
              child: const Text('View All >', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF2563EB)))),
          ],
        ),
        const SizedBox(height: 4),
        ...schemes.map((s) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Row(
              children: [
                Container(
                  width: 54, height: 54,
                  decoration: BoxDecoration(color: s.iconBg, borderRadius: BorderRadius.circular(14)),
                  child: Icon(s.icon, size: 28, color: s.iconBg == const Color(0xFFFEF3C7) ? const Color(0xFFD97706) : _emerald),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.title, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: _dark, fontFamily: 'Plus Jakarta Sans'), overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(s.subtitle, style: const TextStyle(fontSize: 10.5, color: _muted, fontFamily: 'Plus Jakarta Sans'), overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 6),
                      Wrap(spacing: 4, children: s.tags.map((t) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(4)),
                        child: Text(t.label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: t.text, fontFamily: 'Plus Jakarta Sans')),
                      )).toList()),
                    ],
                  ),
                ),
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), shape: BoxShape.circle),
                  child: const Icon(Icons.chevron_right_rounded, size: 18, color: _muted),
                ),
              ],
            ),
          ),
        )),
      ],
    );
  }

  // ── Bottom Nav ────────────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    final tabs = [
      _NavTab('Home', Icons.home_rounded),
      _NavTab('Schemes', Icons.grid_view_rounded),
      _NavTab('Documents', Icons.description_outlined),
      _NavTab('Alerts', Icons.notifications_outlined, badge: '3'),
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

class _UpcomingItem {
  final String title, subtitle;
  final IconData icon;
  final Color iconBg, iconColor;
  _UpcomingItem(this.title, this.subtitle, this.icon, this.iconBg, this.iconColor);
}

class _QuickAction {
  final String label;
  final IconData icon;
  final Color iconBg, iconColor;
  _QuickAction(this.label, this.icon, this.iconBg, this.iconColor);
}

class _LatestScheme {
  final String title, subtitle;
  final List<_TagItem> tags;
  final IconData icon;
  final Color iconBg;
  _LatestScheme(this.title, this.subtitle, this.tags, this.icon, this.iconBg);
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
