import 'package:flutter/material.dart';

import 'scheme_model.dart';
import 'scheme_service.dart';

// ---------------------------------------------------------------------------
// Schemes Page - Faithfully matching code.html & visual design
// Designed to be dynamic and easily connected to backend APIs
// ---------------------------------------------------------------------------

class SchemeSathiSchemesPage extends StatelessWidget {
  final VoidCallback? onBack;
  final String? initialCategory;
  final String? initialState;

  const SchemeSathiSchemesPage({
    super.key,
    this.onBack,
    this.initialCategory,
    this.initialState,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: SafeArea(
        child: SchemesContentView(
          onBack: onBack ?? (Navigator.canPop(context) ? () => Navigator.pop(context) : null),
          initialCategory: initialCategory,
          initialState: initialState,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Schemes Content View (Embeddable in Tab or Full Screen)
// ---------------------------------------------------------------------------
class SchemesContentView extends StatefulWidget {
  final VoidCallback? onBack;
  final List<SchemeItem>? dynamicSchemes; // Allows passing schemes from an API / Riverpod / Bloc later
  final String? initialCategory;
  final String? initialState;

  const SchemesContentView({
    super.key,
    this.onBack,
    this.dynamicSchemes,
    this.initialCategory,
    this.initialState,
  });

  @override
  State<SchemesContentView> createState() => _SchemesContentViewState();
}

class _SchemesContentViewState extends State<SchemesContentView> {
  late List<SchemeItem> _allSchemes;
  final TextEditingController _searchController = TextEditingController();

  int _selectedFilterIndex = 0;
  String _selectedCategory = 'All';
  bool _sortByRelevance = true; // true = relevance, false = name
  bool _isLoading = false;
  int? _totalCount;

  // State filter
  late String _selectedState;
  List<String> _availableStates = ['All States'];

  // Top Eligibility & Level Filters
  static const List<String> _filters = [
    'All',
    '✨ Eligible for Me',
    'Central',
    'State',
  ];

  // All 15 Government Entitlement Sectors from code.html & DB
  static const List<String> _categories = [
    'All',
    'Agriculture, Rural & Environment',
    'Banking, Financial Services and Insurance',
    'Business & Entrepreneurship',
    'Education & Learning',
    'Health & Wellness',
    'Housing & Shelter',
    'Public Safety, Law & Justice',
    'Science, IT & Communications',
    'Skills & Employment',
    'Social Welfare & Empowerment',
    'Sports & Culture',
    'Transport & Infrastructure',
    'Travel & Tourism',
    'Utility & Sanitation',
    'Women and Child',
  ];

  @override
  void initState() {
    super.initState();
    _selectedState = widget.initialState ?? 'All States';
    _allSchemes = widget.dynamicSchemes ?? SchemeItem.getDefaultSchemes();

    // Check if initialCategory was passed (e.g., from Home Explore by Category or All Categories directory)
    if (widget.initialCategory != null && widget.initialCategory!.isNotEmpty) {
      final passed = widget.initialCategory!.trim();
      final catMatch = _categories.firstWhere(
        (c) =>
            c.toLowerCase() == passed.toLowerCase() ||
            c.toLowerCase().contains(passed.toLowerCase()) ||
            passed.toLowerCase().contains(c.toLowerCase()),
        orElse: () => '',
      );
      if (catMatch.isNotEmpty && catMatch != 'All') {
        _selectedCategory = catMatch;
      } else {
        final filterIdx = _filters.indexWhere((f) =>
            f.toLowerCase() == passed.toLowerCase() ||
            passed.toLowerCase().contains(f.toLowerCase()));
        if (filterIdx >= 0) {
          _selectedFilterIndex = filterIdx;
        } else {
          _searchController.text = passed;
        }
      }
    }

    _searchController.addListener(() => setState(() {}));
    if (widget.dynamicSchemes == null) {
      _loadStates();
      _loadSchemesFromDb(state: _selectedState != 'All States' ? _selectedState : null);
    }
  }

  Future<void> _loadStates() async {
    try {
      final states = await SchemeService.instance.fetchStates();
      if (mounted && states.isNotEmpty) {
        setState(() {
          final all = ['All States', ...states];
          if (_selectedState != 'All States' && !all.contains(_selectedState)) {
            all.add(_selectedState);
          }
          _availableStates = all;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadSchemesFromDb({String? state}) async {
    setState(() => _isLoading = true);
    try {
      final String? stateParam =
          (state != null && state != 'All States') ? state : null;
      // Fast responsive batch size (200 schemes for All, up to 500 when state selected)
      final int batchLimit = stateParam != null ? 500 : 200;
      final results = await SchemeService.instance.fetchSchemes(
        state: stateParam,
        limit: batchLimit,
      );
      final count = await SchemeService.instance.fetchSchemeCount(
        state: stateParam,
      );
      if (mounted) {
        setState(() {
          _allSchemes = results;
          _totalCount = count ?? results.length;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void didUpdateWidget(covariant SchemesContentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.dynamicSchemes != null && widget.dynamicSchemes != oldWidget.dynamicSchemes) {
      setState(() {
        _allSchemes = widget.dynamicSchemes!;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SchemeItem> get _filteredSchemes {
    final query = _searchController.text.trim().toLowerCase();
    final filter = _filters[_selectedFilterIndex];

    var list = _allSchemes.where((scheme) {
      // 1. Level & Eligibility filter
      if (filter == '✨ Eligible for Me') {
        if (!scheme.isEligible) return false;
      } else if (filter == 'Central' || filter == 'State') {
        if (scheme.level.toLowerCase() != filter.toLowerCase()) return false;
      }

      // 2. Specific Sector / Category Filter (from All Categories)
      if (_selectedCategory != 'All') {
        final catClean = _selectedCategory.toLowerCase();
        final schemeCat = scheme.category.toLowerCase();
        final catMatch = schemeCat.contains(catClean) ||
            catClean.contains(schemeCat) ||
            scheme.tags.any((t) =>
                catClean.contains(t.toLowerCase()) ||
                t.toLowerCase().contains(catClean));
        if (!catMatch) return false;
      }

      // 3. Search query filter
      if (query.isNotEmpty) {
        final inTitle = scheme.title.toLowerCase().contains(query);
        final inDesc = scheme.description.toLowerCase().contains(query);
        final inCat = scheme.category.toLowerCase().contains(query);
        final inTags = scheme.tags.any((t) => t.toLowerCase().contains(query));
        if (!inTitle && !inDesc && !inCat && !inTags) return false;
      }

      return true;
    }).toList();

    // 3. Sorting
    if (_sortByRelevance) {
      list.sort((a, b) => b.matchPercentage.compareTo(a.matchPercentage));
    } else {
      list.sort((a, b) => a.title.compareTo(b.title));
    }

    return list;
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
                            color: Color(0xFF464555),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    scheme.title,
                    style: const TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF131B2E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    scheme.description,
                    style: const TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 15,
                      color: Color(0xFF464555),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F3FF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Benefit Value',
                              style: TextStyle(
                                fontFamily: 'Plus Jakarta Sans',
                                fontSize: 12,
                                color: Color(0xFF777587),
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Direct DBT / Subsidy',
                              style: TextStyle(
                                fontFamily: 'Plus Jakarta Sans',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF131B2E),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          scheme.benefitAmount,
                          style: const TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF3525CD),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3525CD),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 2,
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Starting application for ${scheme.title}...'),
                            backgroundColor: const Color(0xFF3525CD),
                          ),
                        );
                      },
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.assignment_turned_in_rounded, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Apply for Scheme',
                            style: TextStyle(
                              fontFamily: 'Plus Jakarta Sans',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
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

  void _showAIAssistant() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Colors.white,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3525CD),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sathi AI Scheme Advisor',
                          style: TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF131B2E),
                          ),
                        ),
                        Text(
                          'Personalized match across 3,200+ schemes',
                          style: TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontSize: 12,
                            color: Color(0xFF777587),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F3FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Based on your citizen profile, you are eligible for 14 central and state government benefits. Top recommendation is Ayushman Bharat PM-JAY and PM Kisan Samman Nidhi.',
                  style: TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 13.5,
                    height: 1.45,
                    color: Color(0xFF131B2E),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3525CD),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _selectedFilterIndex = 1; // Filter to Eligible for Me
                    });
                  },
                  child: const Text(
                    'View My Eligible Schemes',
                    style: TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final schemes = _filteredSchemes;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: Explore Schemes & Meta Controls ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (widget.onBack != null) ...[
                    GestureDetector(
                      onTap: widget.onBack,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.arrow_back_rounded,
                          size: 20,
                          color: Color(0xFF131B2E),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Explore Schemes',
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF131B2E),
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        _totalCount != null && _totalCount! > 0
                            ? '$_totalCount+ verified state & central benefits'
                            : '540+ verified state & central benefits',
                        style: const TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 12,
                          color: Color(0xFF777587),
                          fontWeight: FontWeight.w400,
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
                        _selectedFilterIndex = (_selectedFilterIndex + 1) % _filters.length;
                      });
                    },
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.tune_rounded,
                        size: 20,
                        color: Color(0xFF464555),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _sortByRelevance = !_sortByRelevance;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            _sortByRelevance ? 'Sorted by Relevance' : 'Sorted by Name (A-Z)',
                          ),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.swap_vert_rounded,
                        size: 20,
                        color: Color(0xFF464555),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Search Input Box ──
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 14,
                color: Color(0xFF131B2E),
              ),
              decoration: InputDecoration(
                hintText: 'Search 500+ government schemes...',
                hintStyle: const TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: 13.5,
                  color: Color(0xFF777587),
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF777587),
                  size: 20,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18, color: Color(0xFF777587)),
                        onPressed: () => _searchController.clear(),
                      )
                    : const Icon(
                        Icons.mic_none_rounded,
                        color: Color(0xFF777587),
                        size: 20,
                      ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // ── State Filter Dropdown ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on_rounded, size: 18, color: Color(0xFF3525CD)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedState,
                      isExpanded: true,
                      style: const TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF131B2E),
                      ),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF777587), size: 20),
                      items: _availableStates.map((s) {
                        return DropdownMenuItem<String>(
                          value: s,
                          child: Text(
                            s,
                            style: const TextStyle(
                              fontFamily: 'Plus Jakarta Sans',
                              fontSize: 13.5,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null && val != _selectedState) {
                          setState(() {
                            _selectedState = val;
                            _selectedFilterIndex = 0;
                          });
                          _loadSchemesFromDb(state: val);
                        }
                      },
                    ),
                  ),
                ),
                if (_selectedState != 'All States')
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedState = 'All States';
                        _selectedFilterIndex = 0;
                      });
                      _loadSchemesFromDb();
                    },
                    child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF777587)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Filter Chips: Level & Eligibility ──
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _filters.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final isSelected = i == _selectedFilterIndex;
                return GestureDetector(
                  onTap: () => setState(() => _selectedFilterIndex = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF3525CD) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        _filters[i],
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 12.5,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? Colors.white : const Color(0xFF464555),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),

          // ── Category / Sector Filter Chips (All 15 Sectors) ──
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final categoryName = _categories[i];
                final isSelected = categoryName == _selectedCategory;
                return GestureDetector(
                  onTap: () => setState(() => _selectedCategory = categoryName),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF0F1D36) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF0F1D36)
                            : const Color(0xFFE2E8F0),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 5,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelected && categoryName != 'All') ...[
                          const Icon(Icons.check_circle_rounded,
                              size: 14, color: Colors.white),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          categoryName,
                          style: TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontSize: 12,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_selectedCategory != 'All') ...[
            const SizedBox(height: 10),
            // ── Active Category Indicator Badge ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF4FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFD6E3FF)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.category_rounded, size: 16, color: Color(0xFF005DB7)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 12,
                          color: Color(0xFF00152E),
                        ),
                        children: [
                          const TextSpan(text: 'Filtered by sector: '),
                          TextSpan(
                            text: _selectedCategory,
                            style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF005DB7)),
                          ),
                        ],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _selectedCategory = 'All'),
                    child: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF43474E)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),

          // ── Section Title Row ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _selectedState != 'All States'
                      ? '${_selectedState.toUpperCase()} SCHEMES'
                      : 'ALL SCHEMES',
                  style: const TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF777587),
                    letterSpacing: 0.6,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _sortByRelevance = !_sortByRelevance;
                  });
                },
                child: Text(
                  _sortByRelevance ? 'Sorted by Relevance' : 'Sorted by Name',
                  style: const TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3525CD),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Scheme Cards List ──
          if (_isLoading)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40),
              alignment: Alignment.center,
              child: const Column(
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3525CD)),
                  ),
                  SizedBox(height: 14),
                  Text(
                    'Loading schemes from database...',
                    style: TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 13.5,
                      color: Color(0xFF777587),
                    ),
                  ),
                ],
              ),
            )
          else if (schemes.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40),
              alignment: Alignment.center,
              child: Column(
                children: [
                  const Icon(Icons.search_off_rounded, size: 48, color: Color(0xFF777587)),
                  const SizedBox(height: 12),
                  const Text(
                    'No schemes found',
                    style: TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF131B2E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Try another keyword or filter',
                    style: TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 13,
                      color: Color(0xFF777587),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3525CD),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _selectedFilterIndex = 0;
                        _selectedCategory = 'All';
                        _selectedState = 'All States';
                      });
                      _loadSchemesFromDb();
                    },
                    child: const Text('Reset Filters'),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: schemes.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final scheme = schemes[index];
                return _buildSchemeCard(scheme);
              },
            ),
          const SizedBox(height: 18),

          // ── Ask Sathi AI Card ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F3FF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3525CD),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3525CD).withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.smart_toy_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Not sure which to apply?',
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF131B2E),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Ask Sathi AI for instant eligibility match',
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 12,
                          color: Color(0xFF464555),
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3525CD),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 1,
                  ),
                  onPressed: _showAIAssistant,
                  child: const Text(
                    'Ask AI',
                    style: TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildSchemeCard(SchemeItem scheme) {
    return GestureDetector(
      onTap: () => _showSchemeDetails(scheme),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Thumbnail image or icon fallback
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 56,
                height: 56,
                color: scheme.iconBg,
                child: scheme.imageUrl != null
                    ? Image.network(
                        scheme.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          scheme.iconFallback,
                          color: scheme.iconColor,
                          size: 26,
                        ),
                      )
                    : Icon(
                        scheme.iconFallback,
                        color: scheme.iconColor,
                        size: 26,
                      ),
              ),
            ),
            const SizedBox(width: 14),

            // Scheme details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badges Row
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: scheme.matchBadgeBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          scheme.matchBadge,
                          style: TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: scheme.matchBadgeTextColor,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F3FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          scheme.level,
                          style: const TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF464555),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2E7FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          scheme.category,
                          style: const TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF3525CD),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Title
                  Text(
                    scheme.title,
                    style: const TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF131B2E),
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),

                  // Description
                  Text(
                    scheme.description,
                    style: const TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 12,
                      color: Color(0xFF464555),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Trailing Chevron
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                color: Color(0xFFF2F3FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: Color(0xFF777587),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
