import 'package:flutter/material.dart';

class CategoryDetailItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final String query;
  final List<String> keywords;

  const CategoryDetailItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.query,
    required this.keywords,
  });
}

class CategoriesDirectoryPage extends StatefulWidget {
  final VoidCallback? onBack;
  final String? userName;
  final String? userState;
  final void Function(String categoryQuery)? onSelectCategory;

  const CategoriesDirectoryPage({
    super.key,
    this.onBack,
    this.userName,
    this.userState,
    this.onSelectCategory,
  });

  @override
  State<CategoriesDirectoryPage> createState() => _CategoriesDirectoryPageState();
}

class _CategoriesDirectoryPageState extends State<CategoriesDirectoryPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearchVisible = true;

  // Design Tokens strictly following DESIGN.md
  static const Color _bg = Color(0xFFF8F9FF);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _primary = Color(0xFF00152E);
  static const Color _onSurfaceVariant = Color(0xFF43474E);
  static const Color _secondary = Color(0xFF005DB7);
  static const Color _surfaceContainer = Color(0xFFE5EEFF);
  static const Color _surfaceContainerLow = Color(0xFFEFF4FF);
  static const Color _surfaceContainerHigh = Color(0xFFDCE9FF);
  static const Color _outline = Color(0xFF74777F);
  static const Color _border = Color(0xFFE2E8F0);

  // Exact 15 government entitlement sectors from code.html
  static const List<CategoryDetailItem> _allCategories = [
    CategoryDetailItem(
      title: 'Agriculture, Rural & Environment',
      subtitle:
          'Agriculture, farmers, rural development, irrigation, livestock, environment and natural resources.',
      icon: Icons.eco_outlined,
      query: 'Agriculture',
      keywords: [
        'agriculture',
        'rural',
        'environment',
        'farmers',
        'farming',
        'irrigation',
        'livestock',
        'natural resources',
        'kisan',
        'krishi'
      ],
    ),
    CategoryDetailItem(
      title: 'Banking, Financial Services and Insurance',
      subtitle:
          'Banking, financial inclusion, insurance, pensions, savings and financial assistance.',
      icon: Icons.account_balance_outlined,
      query: 'Banking',
      keywords: [
        'banking',
        'financial',
        'insurance',
        'pensions',
        'savings',
        'assistance',
        'inclusion',
        'loan',
        'bima',
        'pension'
      ],
    ),
    CategoryDetailItem(
      title: 'Business & Entrepreneurship',
      subtitle:
          'MSME, startups, self-employment, business loans and entrepreneurship support.',
      icon: Icons.business_center_outlined,
      query: 'Business',
      keywords: [
        'business',
        'entrepreneurship',
        'msme',
        'startups',
        'self employment',
        'loans',
        'funding',
        'enterprise',
        'mudra',
        'udyog'
      ],
    ),
    CategoryDetailItem(
      title: 'Education & Learning',
      subtitle:
          'Scholarships, school education, higher education, fellowships and student assistance.',
      icon: Icons.school_outlined,
      query: 'Education',
      keywords: [
        'education',
        'learning',
        'scholarships',
        'school',
        'higher education',
        'fellowships',
        'student',
        'coaching',
        'college',
        'shiksha'
      ],
    ),
    CategoryDetailItem(
      title: 'Health & Wellness',
      subtitle:
          'Healthcare, medical assistance, health insurance, maternity care and wellness.',
      icon: Icons.favorite_border_rounded,
      query: 'Health',
      keywords: [
        'health',
        'wellness',
        'healthcare',
        'medical assistance',
        'insurance',
        'maternity care',
        'hospital',
        'clinic',
        'ayushman',
        'aarogya'
      ],
    ),
    CategoryDetailItem(
      title: 'Housing & Shelter',
      subtitle:
          'Affordable housing, housing subsidies, home construction and shelter assistance.',
      icon: Icons.home_outlined,
      query: 'Housing',
      keywords: [
        'housing',
        'shelter',
        'affordable housing',
        'subsidies',
        'home construction',
        'pmay',
        'awas',
        'ghar'
      ],
    ),
    CategoryDetailItem(
      title: 'Public Safety, Law & Justice',
      subtitle:
          'Public safety, legal assistance, justice-related support and protection schemes.',
      icon: Icons.verified_user_outlined,
      query: 'Public Safety',
      keywords: [
        'public safety',
        'law',
        'justice',
        'legal assistance',
        'support',
        'protection',
        'police',
        'court',
        'nyay',
        'rights'
      ],
    ),
    CategoryDetailItem(
      title: 'Science, IT & Communications',
      subtitle:
          'Science, technology, innovation, IT, research and digital communication.',
      icon: Icons.devices_outlined,
      query: 'Science',
      keywords: [
        'science',
        'it',
        'communications',
        'technology',
        'innovation',
        'research',
        'digital',
        'internet',
        'telecom',
        'computer'
      ],
    ),
    CategoryDetailItem(
      title: 'Skills & Employment',
      subtitle:
          'Skill development, vocational training, employment, apprenticeships and job assistance.',
      icon: Icons.settings_outlined,
      query: 'Skills & Employment',
      keywords: [
        'skills',
        'employment',
        'skill development',
        'vocational training',
        'apprenticeships',
        'job',
        'rozgar',
        'work',
        'kaushal'
      ],
    ),
    CategoryDetailItem(
      title: 'Social Welfare & Empowerment',
      subtitle:
          'SC/ST/OBC welfare, senior citizens, persons with disabilities, pensions and social assistance.',
      icon: Icons.diversity_3_outlined,
      query: 'Social welfare',
      keywords: [
        'social welfare',
        'empowerment',
        'sc',
        'st',
        'obc',
        'senior citizens',
        'disabilities',
        'pensions',
        'assistance',
        'kalyan'
      ],
    ),
    CategoryDetailItem(
      title: 'Sports & Culture',
      subtitle:
          'Sports scholarships, athlete support, cultural activities and arts promotion.',
      icon: Icons.emoji_events_outlined,
      query: 'Sports',
      keywords: [
        'sports',
        'culture',
        'athletic',
        'athlete',
        'tournament',
        'art promotion',
        'heritage',
        'khel'
      ],
    ),
    CategoryDetailItem(
      title: 'Transport & Infrastructure',
      subtitle:
          'Transport facilities, infrastructure development and mobility-related assistance.',
      icon: Icons.directions_bus_outlined,
      query: 'Transport',
      keywords: [
        'transport',
        'infrastructure',
        'mobility',
        'roads',
        'vehicles',
        'driving licence',
        'bus',
        'railway',
        'transit'
      ],
    ),
    CategoryDetailItem(
      title: 'Travel & Tourism',
      subtitle:
          'Tourism promotion, travel assistance and tourism-related development schemes.',
      icon: Icons.explore_outlined,
      query: 'Travel & Tourism',
      keywords: [
        'travel',
        'tourism',
        'promotion',
        'travel assistance',
        'tourist development',
        'heritage',
        'yatra'
      ],
    ),
    CategoryDetailItem(
      title: 'Utility & Sanitation',
      subtitle:
          'Water supply, sanitation, electricity, essential utilities and cleanliness.',
      icon: Icons.bolt_outlined,
      query: 'Utility & Sanitation',
      keywords: [
        'utility',
        'sanitation',
        'water supply',
        'electricity',
        'power',
        'cleanliness',
        'essential utilities',
        'swachh',
        'jal'
      ],
    ),
    CategoryDetailItem(
      title: 'Women and Child',
      subtitle:
          'Women empowerment, maternity benefits, child nutrition, childcare and girl-child welfare.',
      icon: Icons.child_care_outlined,
      query: 'Women and Child',
      keywords: [
        'women',
        'child',
        'women and child',
        'maternity benefits',
        'child nutrition',
        'childcare',
        'girl welfare',
        'poshan',
        'mahila',
        'balika'
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  List<CategoryDetailItem> get _filteredCategories {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _allCategories;

    return _allCategories.where((c) {
      if (c.title.toLowerCase().contains(query)) return true;
      if (c.subtitle.toLowerCase().contains(query)) return true;
      return c.keywords.any((k) => k.toLowerCase().contains(query));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredCategories;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header: Back button + Title + Actions ──
              _buildHeaderRow(),
              const SizedBox(height: 12),

              // ── Quick Filter Bar ──
              if (_isSearchVisible) ...[
                _buildQuickFilterBar(filtered.length),
                const SizedBox(height: 14),
              ],

              // ── Category List or Empty State ──
              if (filtered.isEmpty)
                _buildEmptyState()
              else
                ListView.separated(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return _buildCategoryCard(item);
                  },
                ),

              const SizedBox(height: 16),

              // ── Bottom Helper Civic Banner ──
              _buildCivicBanner(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: widget.onBack ?? () => Navigator.of(context).pop(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  size: 20,
                  color: _primary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'All Categories',
                  style: TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _primary,
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  '15 government entitlement sectors',
                  style: TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 11.5,
                    color: _onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        Row(
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  _isSearchVisible = !_isSearchVisible;
                  if (_isSearchVisible) {
                    _searchFocusNode.requestFocus();
                  } else {
                    _searchController.clear();
                  }
                });
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  _isSearchVisible ? Icons.search_rounded : Icons.search_off_rounded,
                  size: 20,
                  color: _primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                _searchController.clear();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Showing all 15 sectors'),
                    duration: Duration(milliseconds: 900),
                  ),
                );
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  size: 20,
                  color: _primary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickFilterBar(int matchCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.filter_list_rounded, size: 20, color: _outline),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              style: const TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 13,
                color: _primary,
              ),
              decoration: const InputDecoration(
                hintText: 'Quick filter by sector, keyword...',
                hintStyle: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: 12.5,
                  color: _outline,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            GestureDetector(
              onTap: () => _searchController.clear(),
              child: const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.clear_rounded, size: 16, color: _outline),
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _surfaceContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$matchCount total',
              style: const TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: _onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(CategoryDetailItem item) {
    return GestureDetector(
      onTap: () {
        if (widget.onSelectCategory != null) {
          widget.onSelectCategory!(item.query);
        } else {
          Navigator.of(context).pop(item.query);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _surfaceContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                item.icon,
                size: 22,
                color: const Color(0xFF334155),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: _primary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 11,
                      color: _onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: _outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      alignment: Alignment.center,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _surfaceContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.search_off_rounded,
              size: 28,
              color: _outline,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'No matching category',
            style: TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _primary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            "Try searching for 'Agriculture', 'Scholarship', 'Pension' or 'PMAY'.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 12,
              color: _onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            onPressed: () => _searchController.clear(),
            child: const Text(
              'Clear Search',
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCivicBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD6E3FF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              size: 18,
              color: _secondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Need personalized matching?',
                  style: TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _primary,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Answer 4 simple questions to check eligibility across all 15 categories at once.',
                  style: TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 11,
                    color: _onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () {
                    // Navigate to form setup or eligible view
                    if (widget.onSelectCategory != null) {
                      widget.onSelectCategory!('Eligible');
                    } else {
                      Navigator.of(context).pop('Eligible');
                    }
                  },
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Launch Eligibility Finder',
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _secondary,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: _secondary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
