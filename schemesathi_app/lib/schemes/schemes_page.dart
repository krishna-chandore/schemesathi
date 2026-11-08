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
  final int? initialFilterIndex;

  const SchemeSathiSchemesPage({
    super.key,
    this.onBack,
    this.initialCategory,
    this.initialState,
    this.initialFilterIndex,
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
          initialFilterIndex: initialFilterIndex,
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
  final int? initialFilterIndex;
  final String? initialSearchQuery; // Pre-fills search bar (from home top bar)

  const SchemesContentView({
    super.key,
    this.onBack,
    this.dynamicSchemes,
    this.initialCategory,
    this.initialState,
    this.initialFilterIndex,
    this.initialSearchQuery,
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
    // Ensure _selectedState is always in _availableStates to avoid DropdownButton assertion error
    if (_selectedState != 'All States' && !_availableStates.contains(_selectedState)) {
      _availableStates = ['All States', _selectedState];
    }
    _allSchemes = widget.dynamicSchemes ?? SchemeItem.getDefaultSchemes();
    if (widget.initialFilterIndex != null) {
      _selectedFilterIndex = widget.initialFilterIndex!;
    }

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

    // Pre-fill search from home top bar if provided
    if (widget.initialSearchQuery != null && widget.initialSearchQuery!.trim().isNotEmpty) {
      _searchController.text = widget.initialSearchQuery!.trim();
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
          // Always ensure _selectedState is in the list to avoid DropdownButton crash
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
                  // Application window warning if closed
                  if (!scheme.isApplicationOpen) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Color(0xFFDC2626), size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              scheme.applicationStatus == 'upcoming'
                                  ? 'Application window is upcoming. Check back soon.'
                                  : 'Application window for this cycle is currently closed.',
                              style: const TextStyle(
                                fontFamily: 'Plus Jakarta Sans',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF991B1B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Benefit card
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

                  // Passed criteria checklist
                  if (scheme.passedConditions.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text(
                      'Verified Eligibility Criteria',
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

                  // Missing documents checklist
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

                  // Ineligibility reasons if any
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 10,
                    children: [
                      if (scheme.officialLink != null && scheme.officialLink!.isNotEmpty)
                        SizedBox(
                          height: 48,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF3525CD),
                              side: const BorderSide(color: Color(0xFF3525CD)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                            ),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Source Portal: ${scheme.officialLink}'),
                                  backgroundColor: const Color(0xFF131B2E),
                                ),
                              );
                            },
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.open_in_new_rounded, size: 18),
                                SizedBox(width: 6),
                                Text(
                                  'Portal Link',
                                  style: TextStyle(
                                    fontFamily: 'Plus Jakarta Sans',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      SizedBox(
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
                            padding: const EdgeInsets.symmetric(horizontal: 20),
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
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(scheme.isApplicationOpen
                                  ? Icons.assignment_turned_in_rounded
                                  : Icons.lock_clock_rounded, size: 20),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  scheme.isApplicationOpen ? 'Apply for Scheme' : 'Application Closed',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: 'Plus Jakarta Sans',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
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

  void _showFilterModal() {
    String tempState = _selectedState;
    int tempFilterIdx = _selectedFilterIndex;
    String tempCategory = _selectedCategory;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: DraggableScrollableSheet(
                initialChildSize: 0.75,
                minChildSize: 0.5,
                maxChildSize: 0.9,
                expand: false,
                builder: (context, scrollController) {
                  return SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Drag Handle
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
                        const SizedBox(height: 16),

                        // Title row with Reset button
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.tune_rounded, size: 22, color: Color(0xFF3525CD)),
                                SizedBox(width: 8),
                                Text(
                                  'Filter Schemes',
                                  style: TextStyle(
                                    fontFamily: 'Plus Jakarta Sans',
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF131B2E),
                                  ),
                                ),
                              ],
                            ),
                            TextButton(
                              onPressed: () {
                                setModalState(() {
                                  tempState = 'All States';
                                  tempFilterIdx = 0;
                                  tempCategory = 'All';
                                });
                              },
                              child: const Text(
                                'Reset All',
                                style: TextStyle(
                                  fontFamily: 'Plus Jakarta Sans',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFDC2626),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),

                        // 1. Eligibility & Level Filter
                        const Text(
                          'Scheme Level & Eligibility',
                          style: TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF131B2E),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(_filters.length, (i) {
                            final isSel = i == tempFilterIdx;
                            return ChoiceChip(
                              label: Text(_filters[i]),
                              selected: isSel,
                              selectedColor: const Color(0xFF3525CD),
                              backgroundColor: Colors.grey.shade100,
                              labelStyle: TextStyle(
                                fontFamily: 'Plus Jakarta Sans',
                                fontSize: 12.5,
                                fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                                color: isSel ? Colors.white : const Color(0xFF464555),
                              ),
                              onSelected: (_) {
                                setModalState(() => tempFilterIdx = i);
                              },
                            );
                          }),
                        ),
                        const SizedBox(height: 20),

                        // 2. State Filter Dropdown
                        const Text(
                          'State / Union Territory',
                          style: TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF131B2E),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: tempState,
                              isExpanded: true,
                              style: const TextStyle(
                                fontFamily: 'Plus Jakarta Sans',
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF131B2E),
                              ),
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
                                if (val != null) {
                                  setModalState(() => tempState = val);
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 3. Category / Sector Filter
                        const Text(
                          'Sector / Category',
                          style: TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF131B2E),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _categories.map((c) {
                            final isSel = c == tempCategory;
                            return ChoiceChip(
                              label: Text(c),
                              selected: isSel,
                              selectedColor: const Color(0xFF0F1D36),
                              backgroundColor: Colors.grey.shade100,
                              labelStyle: TextStyle(
                                fontFamily: 'Plus Jakarta Sans',
                                fontSize: 12,
                                fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                                color: isSel ? Colors.white : const Color(0xFF475569),
                              ),
                              onSelected: (_) {
                                setModalState(() => tempCategory = c);
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 28),

                        // Apply Button
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3525CD),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                            onPressed: () {
                              final stateChanged = tempState != _selectedState;
                              setState(() {
                                _selectedState = tempState;
                                _selectedFilterIndex = tempFilterIdx;
                                _selectedCategory = tempCategory;
                              });
                              Navigator.pop(ctx);
                              if (stateChanged) {
                                _loadSchemesFromDb(
                                  state: tempState != 'All States' ? tempState : null,
                                );
                              }
                            },
                            child: const Text(
                              'Apply Filters',
                              style: TextStyle(
                                fontFamily: 'Plus Jakarta Sans',
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
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
              Expanded(
                child: Row(
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
                    Expanded(
                      child: Column(
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
                            overflow: TextOverflow.ellipsis,
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
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: _showFilterModal,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: (_selectedFilterIndex != 0 || _selectedCategory != 'All' || _selectedState != 'All States')
                            ? const Color(0xFF3525CD)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.tune_rounded,
                            size: 18,
                            color: (_selectedFilterIndex != 0 || _selectedCategory != 'All' || _selectedState != 'All States')
                                ? Colors.white
                                : const Color(0xFF464555),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Filters',
                            style: TextStyle(
                              fontFamily: 'Plus Jakarta Sans',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: (_selectedFilterIndex != 0 || _selectedCategory != 'All' || _selectedState != 'All States')
                                  ? Colors.white
                                  : const Color(0xFF464555),
                            ),
                          ),
                          if (_selectedFilterIndex != 0 || _selectedCategory != 'All' || _selectedState != 'All States') ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${(_selectedFilterIndex != 0 ? 1 : 0) + (_selectedCategory != 'All' ? 1 : 0) + (_selectedState != 'All States' ? 1 : 0)}',
                                style: const TextStyle(
                                  fontFamily: 'Plus Jakarta Sans',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF3525CD),
                                ),
                              ),
                            ),
                          ],
                        ],
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

          // ── Active Filters Chips (Only displayed if filters are selected) ──
          if (_selectedFilterIndex != 0 || _selectedCategory != 'All' || _selectedState != 'All States') ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (_selectedFilterIndex != 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF4FF),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFD6E3FF)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _filters[_selectedFilterIndex],
                            style: const TextStyle(
                              fontFamily: 'Plus Jakarta Sans',
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF3525CD),
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => setState(() => _selectedFilterIndex = 0),
                            child: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF3525CD)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (_selectedState != 'All States') ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF4FF),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFD6E3FF)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.location_on_rounded, size: 12, color: Color(0xFF3525CD)),
                          const SizedBox(width: 2),
                          Text(
                            _selectedState,
                            style: const TextStyle(
                              fontFamily: 'Plus Jakarta Sans',
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF3525CD),
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () {
                              setState(() => _selectedState = 'All States');
                              _loadSchemesFromDb();
                            },
                            child: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF3525CD)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (_selectedCategory != 'All') ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF4FF),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFD6E3FF)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.category_rounded, size: 12, color: Color(0xFF0F1D36)),
                          const SizedBox(width: 4),
                          Text(
                            _selectedCategory,
                            style: const TextStyle(
                              fontFamily: 'Plus Jakarta Sans',
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F1D36),
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => setState(() => _selectedCategory = 'All'),
                            child: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF0F1D36)),
                          ),
                        ],
                      ),
                    ),
                  ],
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
