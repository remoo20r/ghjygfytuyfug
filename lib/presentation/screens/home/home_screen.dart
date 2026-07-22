import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/download_support.dart';
import '../../../core/fullscreen.dart';
import '../../../core/theme/app_theme.dart';
import '../../../state/catalog_refresh.dart';
import '../../../state/live_providers.dart'
    show expiryDateProvider, liveCategoriesProvider;
import '../../../state/series_providers.dart' show seriesCategoriesProvider;
import '../../../state/vod_providers.dart' show vodCategoriesProvider;
import '../../common/app_dialogs.dart';
import '../../common/app_logo.dart';
import '../../common/support_contact_bar.dart';
import '../../common/tv_focusable.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Instantiate the refresher so its 24h auto-refresh timer runs.
    ref.watch(catalogRefreshProvider);
    // Warm the three catalogs in the background: on slow panels (tens of
    // seconds per call) the fetch starts now instead of on the first tap on
    // TV/Film/Serie. read(...) doesn't subscribe, and the FutureProviders
    // cache the in-flight future, so repeated builds are no-ops. Errors are
    // ignored here — the catalog screens surface them with a retry.
    ref.read(liveCategoriesProvider.future).ignore();
    ref.read(vodCategoriesProvider.future).ignore();
    ref.read(seriesCategoriesProvider.future).ignore();
    final isFullscreen = ref.watch(fullscreenProvider);

    // The home is the root route: a system Back here would kill the app cold.
    // Ask first (app-themed dialog, D-pad friendly) — mainly for TV remotes.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final exit = await showAppConfirmDialog(
          context,
          title: 'Exit BellaTV?',
          message: 'Do you want to close the app?',
          confirmLabel: 'Exit',
        );
        if (exit) SystemNavigator.pop();
      },
      child: Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLogo(size: 30),
            const SizedBox(width: 12),
            Text('BellaTV', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search'),
          ),
          // Offline downloads: phone (touch) mode on the APK only.
          if (downloadsSupported())
            IconButton(
              tooltip: 'Downloads',
              icon: const Icon(Icons.download_outlined),
              onPressed: () => context.push('/downloads'),
            ),
          // Windows only: on Android the app is permanently fullscreen.
          if (fullscreenToggleAvailable)
            IconButton(
              tooltip: isFullscreen ? 'Exit Fullscreen' : 'Fullscreen',
              icon: Icon(isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
              onPressed: () => ref.read(fullscreenProvider.notifier).toggle(),
            ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          // Center the three tiles as a group with a sensible max size, instead
          // of stretching them across the whole width. Each tile is capped so
          // it stays elegant on big TVs and compact on small phones.
          final gap = (w * 0.03).clamp(14.0, 36.0);
          final maxRowWidth = 900.0;
          final rowWidth = w.clamp(0.0, maxRowWidth);
          final horizontalPadding = ((w - rowWidth) / 2).clamp(16.0, w);
          final usableW = rowWidth - horizontalPadding.clamp(0, 40) * 0 - gap * 2 - 32;
          final tileW = (usableW / 3).clamp(90.0, 240.0);
          final tileH = (tileW * 1.32).clamp(140.0, h * 0.66);

          return Column(
            children: [
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _HomeTile(
                          label: 'Live TV',
                          icon: Icons.tv_rounded,
                          gradientColors: const [Color(0xFFE23744), Color(0xFF1A0608)],
                          glowColor: AppColors.red,
                          width: tileW,
                          height: tileH,
                          // D-pad: land on TV when the home opens.
                          autofocus: true,
                          onTap: () => context.push('/live'),
                        ),
                        SizedBox(width: gap),
                        _HomeTile(
                          label: 'Movies',
                          icon: Icons.movie_creation_rounded,
                          gradientColors: const [Color(0xFFC01F2E), Color(0xFF120406)],
                          glowColor: AppColors.gold,
                          width: tileW,
                          height: tileH,
                          onTap: () => context.push('/vod'),
                        ),
                        SizedBox(width: gap),
                        _HomeTile(
                          label: 'Series',
                          icon: Icons.video_library_rounded,
                          gradientColors: const [Color(0xFFE23744), Color(0xFF1A0608)],
                          glowColor: AppColors.goldDark,
                          width: tileW,
                          height: tileH,
                          onTap: () => context.push('/series'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const _ExpiryLine(),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _RefreshButton(),
              ),
              // Customer-service strip (number + Call + WhatsApp), width-capped
              // so it doesn't stretch across a wide TV screen.
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 16, left: 20, right: 20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: const SupportContactBar(compact: true),
                  ),
                ),
              ),
            ],
          );
        },
        ),
      ),
    );
  }
}

/// A premium, color-coded card for one of the three main sections. Each card
/// is a rounded tile with a rich diagonal gradient, a soft outer glow, a glossy
/// top sheen and a large content icon inside a frosted circle — red for Live,
/// gold for Movies, and a gold→red blend for Series, matching the app's
/// black/red/gold identity.
class _HomeTile extends StatelessWidget {
  const _HomeTile({
    required this.label,
    required this.icon,
    required this.gradientColors,
    required this.glowColor,
    required this.width,
    required this.height,
    required this.onTap,
    this.autofocus = false,
  });

  final String label;
  final IconData icon;
  final List<Color> gradientColors;
  final Color glowColor;
  final double width;
  final double height;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    // Circular tile: a glossy disc with a black→red gradient and a gold/silver
    // rim, the label sitting just below. No animation — the TvFocusable ring
    // (static red fill + silver outline) provides the "selected" cue.
    final circle = (width * 0.92).clamp(96.0, 200.0);
    final iconSize = (circle * 0.40).clamp(34.0, 84.0);
    final fontSize = (width * 0.12).clamp(15.0, 22.0);

    return SizedBox(
      width: width,
      height: height,
      child: TvFocusable(
        borderRadius: circle,
        autofocus: autofocus,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: circle,
              height: circle,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.3, -0.4),
                  radius: 1.0,
                  colors: gradientColors,
                ),
                boxShadow: [
                  // Colored outer glow for a premium "lit" look.
                  BoxShadow(
                    color: glowColor.withValues(alpha: 0.45),
                    blurRadius: 26,
                    spreadRadius: 1,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 12,
                    offset: const Offset(0, 8),
                  ),
                ],
                // Gold rim for that first-class metallic edge.
                border: Border.all(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.7),
                  width: 2,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Glossy top sheen (static).
                  Positioned(
                    top: circle * 0.10,
                    child: Container(
                      width: circle * 0.62,
                      height: circle * 0.34,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(circle),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.30),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Icon(icon, size: iconSize, color: Colors.white),
                ],
              ),
            ),
            SizedBox(height: height * 0.05),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String formatExpiry(DateTime d) {
  final local = d.toLocal();
  final dd = local.day.toString().padLeft(2, '0');
  final mm = local.month.toString().padLeft(2, '0');
  final hh = local.hour.toString().padLeft(2, '0');
  final mi = local.minute.toString().padLeft(2, '0');
  return '$dd/$mm/${local.year} $hh:$mi';
}

class _ExpiryLine extends ConsumerWidget {
  const _ExpiryLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expiry = ref.watch(expiryDateProvider);
    return expiry.maybeWhen(
      data: (date) {
        if (date == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Subscription valid until ${formatExpiry(date)}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _RefreshButton extends ConsumerStatefulWidget {
  @override
  ConsumerState<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends ConsumerState<_RefreshButton> {
  // Transient outcome shown inside the button itself (no snackbar).
  String? _result;
  bool _ok = true;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _doRefresh() async {
    final error = await ref.read(catalogRefreshProvider).refreshNow();
    if (!mounted) return;
    setState(() {
      _ok = error == null;
      _result = error == null ? 'List updated' : 'Update failed';
    });
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _result = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final refreshing = ref.watch(catalogRefreshingProvider);
    final label = refreshing ? 'Updating...' : (_result ?? 'Refresh list');
    final Widget icon;
    if (refreshing) {
      icon = const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
    } else if (_result != null) {
      icon = Icon(_ok ? Icons.check_circle_outline : Icons.error_outline);
    } else {
      icon = const Icon(Icons.refresh);
    }

    return TvFocusable(
      borderRadius: 14,
      onTap: refreshing ? () {} : _doRefresh,
      // The TvFocusable is the one D-pad node: the inner button must not be a
      // second focus stop (mouse clicks still reach it).
      child: ExcludeFocus(
        child: OutlinedButton.icon(
          onPressed: refreshing ? null : _doRefresh,
          icon: icon,
          label: Text(label),
        ),
      ),
    );
  }
}
