import 'package:flutter/material.dart';

import '../auth/auth.dart';
import '../citizen_form/app_preferences.dart';
import '../citizen_form/form_service.dart';
import '../schemes/scheme_service.dart';
import '../schemes/schemes_page.dart';

// ---------------------------------------------------------------------------
// SchemeSathi Profile Page (faithfully translated from code.html & DESIGN.md)
// ---------------------------------------------------------------------------

class SchemeSathiProfilePage extends StatelessWidget {
  final String? userName;
  final VoidCallback? onBack;

  const SchemeSathiProfilePage({
    super.key,
    this.userName,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ProfileDesignTokens.surface,
      appBar: Navigator.canPop(context) || onBack != null
          ? AppBar(
              backgroundColor: ProfileDesignTokens.surface,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: ProfileDesignTokens.onSurface),
                onPressed: onBack ?? () => Navigator.of(context).pop(),
              ),
              title: const Text(
                'My Profile',
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: ProfileDesignTokens.onSurface,
                ),
              ),
              centerTitle: false,
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: ProfileContentView(userName: userName),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile Content View (can be embedded directly inside tab or full screen)
// ---------------------------------------------------------------------------
class ProfileContentView extends StatefulWidget {
  final String? userName;
  final VoidCallback? onOpenReminders;
  final VoidCallback? onOpenMySchemes;
  final ValueChanged<String>? onStateChanged;
  final ValueChanged<String>? onLanguageChanged;

  const ProfileContentView({
    super.key,
    this.userName,
    this.onOpenReminders,
    this.onOpenMySchemes,
    this.onStateChanged,
    this.onLanguageChanged,
  });

  @override
  State<ProfileContentView> createState() => _ProfileContentViewState();
}

class _ProfileContentViewState extends State<ProfileContentView> {
  String _selectedState = AppPreferences.instance.currentState;
  String _selectedLanguage = AppPreferences.instance.currentLanguage;
  Map<String, dynamic>? _citizenProfile;
  List<Map<String, dynamic>> _milestones = [];

  @override
  void initState() {
    super.initState();
    AppPreferences.instance.addListener(_onPreferencesChanged);
    _fetchProfileData();
    _fetchReminders();
  }

  @override
  void dispose() {
    AppPreferences.instance.removeListener(_onPreferencesChanged);
    super.dispose();
  }

  void _onPreferencesChanged() {
    if (mounted) {
      setState(() {
        _selectedState = AppPreferences.instance.currentState;
        _selectedLanguage = AppPreferences.instance.currentLanguage;
      });
    }
  }

  Future<void> _fetchReminders() async {
    final auth = ClerkAuthService.instance;
    final email = auth.userEmail;
    final clerkUid = auth.clerkUserId;
    try {
      final list = await SchemeService.instance.fetchUpcomingMilestones(
        email: email,
        clerkUserId: clerkUid,
      );
      if (mounted) {
        setState(() {
          _milestones = list;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchProfileData() async {
    final auth = ClerkAuthService.instance;
    final email = auth.userEmail;
    final clerkUid = auth.clerkUserId;
    if ((email != null && email.isNotEmpty) || (clerkUid != null && clerkUid.isNotEmpty)) {
      try {
        final profile = await FormService.instance.fetchFullProfile(
          clerkUserId: clerkUid,
          email: email,
        );
        if (mounted && profile != null) {
          setState(() {
            _citizenProfile = profile;
            if (profile['state'] != null && profile['state'].toString().isNotEmpty) {
              _selectedState = profile['state'].toString();
            }
          });
        }
      } catch (e) {
        debugPrint('[ProfileContentView] _fetchProfileData error: $e');
      }
    }
  }

  int _calculateCompletionPercentage() {
    if (_citizenProfile == null) return 30; // base registered
    int filled = 0;
    const keyFields = [
      'full_name',
      'dob',
      'gender',
      'state',
      'district',
      'occupation',
      'study_level',
      'social_category',
      'caste_certificate_status',
      'income_certificate_status',
    ];
    for (final k in keyFields) {
      final val = _citizenProfile![k];
      if (val != null && val.toString().trim().isNotEmpty) {
        filled++;
      }
    }
    final docs = _citizenProfile!['documents'];
    if (docs is List && docs.isNotEmpty) {
      filled += 2;
    }
    final total = keyFields.length + 2;
    final pct = ((filled / total) * 100).round();
    return pct.clamp(10, 100);
  }

  void _navigateToForm() async {
    final auth = ClerkAuthService.instance;
    await Navigator.of(context).pushNamed('/form', arguments: auth.userEmail);
    // Refresh profile on return
    _fetchProfileData();
  }

  void _showStatePicker() {
    final states = AppPreferences.supportedStates;

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
                  'Select State',
                  style: TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: ProfileDesignTokens.onSurface,
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: states.length,
                  itemBuilder: (ctx, i) {
                    final s = states[i];
                    final isSel = s == _selectedState;
                    return ListTile(
                      title: Text(
                        s,
                        style: TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                          color: isSel ? ProfileDesignTokens.primary : ProfileDesignTokens.onSurface,
                        ),
                      ),
                      trailing: isSel
                          ? const Icon(Icons.check_circle_rounded, color: ProfileDesignTokens.primary)
                          : null,
                      onTap: () async {
                        setState(() => _selectedState = s);
                        Navigator.pop(ctx);

                        final auth = ClerkAuthService.instance;
                        await AppPreferences.instance.setStateName(
                          s,
                          email: auth.userEmail,
                          clerkUserId: auth.clerkUserId,
                        );

                        if (widget.onStateChanged != null) {
                          widget.onStateChanged!(s);
                        }

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('✓ State updated to $s across all pages'),
                              backgroundColor: ProfileDesignTokens.primary,
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 2),
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

  void _showLanguagePicker() {
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
                  'Select Language',
                  style: TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: ProfileDesignTokens.onSurface,
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
                          color: isSel ? ProfileDesignTokens.primary : ProfileDesignTokens.onSurface,
                        ),
                      ),
                      trailing: isSel
                          ? const Icon(Icons.check_circle_rounded, color: ProfileDesignTokens.primary)
                          : null,
                      onTap: () async {
                        setState(() => _selectedLanguage = l);
                        Navigator.pop(ctx);

                        final auth = ClerkAuthService.instance;
                        await AppPreferences.instance.setLanguage(
                          l,
                          email: auth.userEmail,
                          clerkUserId: auth.clerkUserId,
                        );

                        if (widget.onLanguageChanged != null) {
                          widget.onLanguageChanged!(l);
                        }

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('✓ Language updated to $l'),
                              backgroundColor: ProfileDesignTokens.primary,
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 2),
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

  void _showRemindersModal() {
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
                width: 44,
                height: 4,
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
                          Text(
                            'My Reminders & Milestones',
                            style: TextStyle(
                              fontFamily: 'Plus Jakarta Sans',
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Upcoming documents & schemes based on your profile',
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
                child: _milestones.isEmpty
                    ? const Center(
                        child: Text(
                          'No pending reminders! Everything is up to date.',
                          style: TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontSize: 13,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                        itemCount: _milestones.length,
                        itemBuilder: (_, i) {
                          final m = _milestones[i];
                          final title = m['title']?.toString() ?? '';
                          final subtitle = m['subtitle']?.toString() ?? '';
                          final actionLabel = m['action_label']?.toString() ?? 'Learn More';
                          final actionUrl = m['action_url']?.toString();
                          final priority = m['priority']?.toString() ?? 'soon';

                          final isUrgent = priority == 'urgent';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isUrgent ? const Color(0xFFFECACA) : const Color(0xFFF1F5F9),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isUrgent ? const Color(0xFFFEE2E2) : const Color(0xFFEFF6FF),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        isUrgent ? 'Action Needed' : 'Upcoming',
                                        style: TextStyle(
                                          fontFamily: 'Plus Jakarta Sans',
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: isUrgent ? const Color(0xFFDC2626) : const Color(0xFF2563EB),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontFamily: 'Plus Jakarta Sans',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  subtitle,
                                  style: const TextStyle(
                                    fontFamily: 'Plus Jakarta Sans',
                                    fontSize: 11.5,
                                    color: Color(0xFF64748B),
                                    height: 1.4,
                                  ),
                                ),
                                if (actionUrl != null && actionUrl.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  InkWell(
                                    onTap: () {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Opening: $actionUrl'),
                                          backgroundColor: const Color(0xFF131B2E),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    },
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          actionLabel,
                                          style: const TextStyle(
                                            fontFamily: 'Plus Jakarta Sans',
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF2563EB),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.arrow_forward_rounded,
                                          size: 14,
                                          color: Color(0xFF2563EB),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
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

  void _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Confirm Logout',
          style: TextStyle(
            fontFamily: 'Plus Jakarta Sans',
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'Are you sure you want to log out of SchemeSathi?',
          style: TextStyle(fontFamily: 'Plus Jakarta Sans'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ProfileDesignTokens.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await ClerkAuthService.instance.signOut(context);
      } catch (e) {
        debugPrint('[Profile] Logout error: $e');
      }
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authName = ClerkAuthService.instance.userName;
    final profileName = _citizenProfile?['full_name']?.toString().trim();
    final effectiveName = (profileName != null && profileName.isNotEmpty)
        ? profileName
        : (widget.userName?.isNotEmpty == true
            ? widget.userName!
            : (authName.isNotEmpty && authName != 'Citizen' ? authName : 'Citizen'));
    final completionPct = _calculateCompletionPercentage();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header: Title and Settings Button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'My Profile',
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: ProfileDesignTokens.onSurface,
                letterSpacing: -0.5,
              ),
            ),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: ProfileDesignTokens.surfaceContainerLowest,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(
                  Icons.settings_outlined,
                  size: 22,
                  color: ProfileDesignTokens.onSurface,
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Settings opened'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // User Profile Summary Header
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ProfileDesignTokens.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Avatar with verified badge
              Stack(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4F46E5), Color(0xFF3525CD)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: ProfileDesignTokens.surfaceContainerHighest,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        effectiveName.isNotEmpty ? effectiveName[0].toUpperCase() : 'C',
                        style: const TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: ProfileDesignTokens.tertiaryFixedDim,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: ProfileDesignTokens.surfaceContainerLowest,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              // Name and "View & edit profile" link
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      effectiveName,
                      style: const TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: ProfileDesignTokens.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: _navigateToForm,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'View & edit profile',
                            style: TextStyle(
                              fontFamily: 'Plus Jakarta Sans',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: ProfileDesignTokens.primary,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: ProfileDesignTokens.primary,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.chevron_right_rounded,
                  color: ProfileDesignTokens.onSurfaceVariant,
                  size: 24,
                ),
                onPressed: _navigateToForm,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Profile Completion Card
        GestureDetector(
          onTap: _navigateToForm,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ProfileDesignTokens.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: ProfileDesignTokens.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.verified_user_rounded,
                              size: 16,
                              color: ProfileDesignTokens.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Profile Completion',
                              style: TextStyle(
                                fontFamily: 'Plus Jakarta Sans',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: ProfileDesignTokens.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$completionPct%',
                          style: const TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: ProfileDesignTokens.tertiary,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: ProfileDesignTokens.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Dual-tone progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 10,
                    width: double.infinity,
                    color: ProfileDesignTokens.surfaceContainerHighest,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: completionPct / 100.0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: ProfileDesignTokens.tertiaryFixedDim,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Add more details to get better recommendations',
                  style: TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: ProfileDesignTokens.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Menu Group 1: Documents & Schemes
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: ProfileDesignTokens.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildMenuItem(
                icon: Icons.description_outlined,
                iconBg: ProfileDesignTokens.surfaceContainerHigh,
                iconColor: ProfileDesignTokens.tertiary,
                title: 'My Documents',
                subtitle: 'Track your document readiness',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Opening My Documents...'), duration: Duration(seconds: 1)),
                  );
                },
              ),
              _buildDivider(),
              _buildMenuItem(
                icon: Icons.assignment_turned_in_outlined,
                iconBg: ProfileDesignTokens.surfaceContainerHigh,
                iconColor: ProfileDesignTokens.tertiary,
                title: 'My Schemes',
                subtitle: 'View applied & eligible schemes',
                trailingBadge: 'Eligible',
                onTap: () {
                  if (widget.onOpenMySchemes != null) {
                    widget.onOpenMySchemes!();
                  } else {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SchemeSathiSchemesPage(initialFilterIndex: 1),
                      ),
                    );
                  }
                },
              ),
              _buildDivider(),
              _buildMenuItem(
                icon: Icons.notifications_active_outlined,
                iconBg: ProfileDesignTokens.surfaceContainerHigh,
                iconColor: ProfileDesignTokens.secondary,
                title: 'My Reminders',
                subtitle: _milestones.isNotEmpty
                    ? '${_milestones.length} pending actions & milestones'
                    : 'Upcoming documents & milestones',
                trailingBadge: _milestones.isNotEmpty ? '${_milestones.length}' : null,
                trailingColor: ProfileDesignTokens.secondary,
                onTap: () {
                  if (widget.onOpenReminders != null) {
                    widget.onOpenReminders!();
                  } else {
                    _showRemindersModal();
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Menu Group 2: Preferences & Localization
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: ProfileDesignTokens.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildMenuItem(
                icon: Icons.location_on_outlined,
                iconBg: ProfileDesignTokens.surfaceContainerHigh,
                iconColor: ProfileDesignTokens.primary,
                title: 'My State',
                trailingBadge: _selectedState,
                onTap: _showStatePicker,
              ),
              _buildDivider(),
              _buildMenuItem(
                icon: Icons.translate_rounded,
                iconBg: ProfileDesignTokens.surfaceContainerHigh,
                iconColor: ProfileDesignTokens.primary,
                title: 'Language',
                trailingBadge: _selectedLanguage,
                onTap: _showLanguagePicker,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Menu Group 3: Support, About, and Session
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: ProfileDesignTokens.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildMenuItem(
                icon: Icons.help_outline_rounded,
                iconBg: ProfileDesignTokens.surfaceContainerHigh,
                iconColor: ProfileDesignTokens.onSurfaceVariant,
                title: 'Help & Support',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Opening Help & Support...'), duration: Duration(seconds: 1)),
                  );
                },
              ),
              _buildDivider(),
              _buildMenuItem(
                icon: Icons.info_outline_rounded,
                iconBg: ProfileDesignTokens.surfaceContainerHigh,
                iconColor: ProfileDesignTokens.onSurfaceVariant,
                title: 'About Us',
                onTap: () {
                  showAboutDialog(
                    context: context,
                    applicationName: 'SchemeSathi',
                    applicationVersion: '2.4.0',
                    applicationLegalese: 'Made with ♥ for Indian Citizens',
                  );
                },
              ),
              _buildDivider(),
              _buildMenuItem(
                icon: Icons.logout_rounded,
                iconBg: ProfileDesignTokens.errorContainer,
                iconColor: ProfileDesignTokens.error,
                title: 'Logout',
                titleColor: ProfileDesignTokens.error,
                trailingColor: ProfileDesignTokens.error,
                onTap: _handleLogout,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Version & Attribution Footer
        Center(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: RichText(
              textAlign: TextAlign.center,
              text: const TextSpan(
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: 12,
                  color: ProfileDesignTokens.onSurfaceVariant,
                ),
                children: [
                  TextSpan(text: 'SchemeSathi v2.4.0 • Made with '),
                  TextSpan(
                    text: '♥',
                    style: TextStyle(color: ProfileDesignTokens.error),
                  ),
                  TextSpan(text: ' for Indian Citizens'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 1,
      color: ProfileDesignTokens.surfaceContainerHighest.withValues(alpha: 0.6),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    String? subtitle,
    String? trailingBadge,
    Color? titleColor,
    Color? trailingColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: titleColor ?? ProfileDesignTokens.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: ProfileDesignTokens.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailingBadge != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: ProfileDesignTokens.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  trailingBadge,
                  style: const TextStyle(
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: ProfileDesignTokens.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: trailingColor ?? ProfileDesignTokens.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Design Tokens from DESIGN.md
// ---------------------------------------------------------------------------
class ProfileDesignTokens {
  static const Color surface = Color(0xFFFAF8FF);
  static const Color surfaceDim = Color(0xFFD2D9F4);
  static const Color surfaceBright = Color(0xFFFAF8FF);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFF2F3FF);
  static const Color surfaceContainer = Color(0xFFEAEDFF);
  static const Color surfaceContainerHigh = Color(0xFFE2E7FF);
  static const Color surfaceContainerHighest = Color(0xFFDAE2FD);
  static const Color onSurface = Color(0xFF131B2E);
  static const Color onSurfaceVariant = Color(0xFF464555);
  static const Color outline = Color(0xFF777587);
  static const Color primary = Color(0xFF3525CD);
  static const Color primaryContainer = Color(0xFF4F46E5);
  static const Color secondary = Color(0xFF006591);
  static const Color tertiary = Color(0xFF005338);
  static const Color tertiaryFixedDim = Color(0xFF4EDEA3);
  static const Color error = Color(0xFFBA1A1A);
  static const Color errorContainer = Color(0xFFFFDAD6);
}
