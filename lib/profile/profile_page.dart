import 'package:flutter/material.dart';

import '../auth/auth.dart';

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

  const ProfileContentView({
    super.key,
    this.userName,
  });

  @override
  State<ProfileContentView> createState() => _ProfileContentViewState();
}

class _ProfileContentViewState extends State<ProfileContentView> {
  String _selectedState = 'Madhya Pradesh';
  String _selectedLanguage = 'English';

  void _showStatePicker() {
    final states = [
      'Madhya Pradesh',
      'Maharashtra',
      'Uttar Pradesh',
      'Rajasthan',
      'Gujarat',
      'Bihar',
      'Karnataka',
      'Tamil Nadu',
      'Delhi',
      'West Bengal',
    ];

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
                      onTap: () {
                        setState(() => _selectedState = s);
                        Navigator.pop(ctx);
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
    final langs = ['English', 'हिन्दी', 'मराठी', 'বাংলা', 'ગુજરાતી', 'தமிழ்'];

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
                      onTap: () {
                        setState(() => _selectedLanguage = l);
                        Navigator.pop(ctx);
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
    final displayName = widget.userName?.isNotEmpty == true
        ? widget.userName!
        : (authName.isNotEmpty && authName != 'Citizen' ? authName : 'Jiyanshu Jain');

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
                        displayName.isNotEmpty ? displayName[0].toUpperCase() : 'J',
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
                      displayName,
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
                      onTap: () {
                        Navigator.of(context).pushNamed('/form');
                      },
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
                onPressed: () {
                  Navigator.of(context).pushNamed('/form');
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Profile Completion Card
        GestureDetector(
          onTap: () {
            Navigator.of(context).pushNamed('/form');
          },
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
                    Row(
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
                        const Text(
                          'Profile Completion',
                          style: TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: ProfileDesignTokens.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const Row(
                      children: [
                        Text(
                          '70%',
                          style: TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: ProfileDesignTokens.tertiary,
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(
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
                      widthFactor: 0.70,
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
                subtitle: 'View applied & saved schemes',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Opening My Schemes...'), duration: Duration(seconds: 1)),
                  );
                },
              ),
              _buildDivider(),
              _buildMenuItem(
                icon: Icons.notifications_active_outlined,
                iconBg: ProfileDesignTokens.surfaceContainerHigh,
                iconColor: ProfileDesignTokens.secondary,
                title: 'My Reminders',
                subtitle: 'Upcoming documents & schemes',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Opening My Reminders...'), duration: Duration(seconds: 1)),
                  );
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
