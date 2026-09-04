import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/city_autocomplete_field.dart';
import '../../../../core/widgets/katisha_app_bar.dart';
import '../../../../features/notifications/data/notifications_repository.dart';
import '../../../../l10n/app_localizations.dart';

class UserHomeScreen extends ConsumerStatefulWidget {
  const UserHomeScreen({super.key});

  @override
  ConsumerState<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends ConsumerState<UserHomeScreen> {
  String? _origin;
  String? _destination;
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  int _unreadCount = 0;

  bool get _canSearch => _origin != null && _destination != null;

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
  }

  Future<void> _loadUnreadCount() async {
    final api = ref.read(apiClientProvider);
    final repo = NotificationsRepository(api);
    final result = await repo.getNotifications(1, 50);
    result.fold((_) {}, (paginated) {
      if (mounted) {
        setState(() {
          _unreadCount = paginated.notifications.where((n) => !n.read).length;
        });
      }
    });
  }

  void _swapLocations() {
    setState(() {
      final temp = _origin;
      _origin = _destination;
      _destination = temp;
    });
  }

  void _searchRoutes() {
    if (!_canSearch) return;
    context.push(
      '/book',
      extra: {
        'origin': _origin,
        'destination': _destination,
        'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
      },
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: KatishaAppBar(
        title: l10n.translate('home_title'),
        titleColor: AppColors.primary,
        unreadCount: _unreadCount,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xl),
              _buildHeroSection(l10n),
              const SizedBox(height: AppSpacing.xxl),
              _buildSearchCard(l10n),
              const SizedBox(height: AppSpacing.lg),
              _buildSearchButton(l10n),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate('booking_title'),
          style: AppTypography.headlineLarge.copyWith(
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.translate('booking_subtitle'),
          style: AppTypography.bodyLarge.copyWith(
            color: AppColors.textSub,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchCard(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.text.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFieldLabel(l10n.translate('origin')),
          const SizedBox(height: AppSpacing.sm),
          CityAutocompleteField(
            label: '',
            icon: Icons.place_outlined,
            value: _origin,
            hint: l10n.translate('search_location'),
            onChanged: (v) => setState(() => _origin = v),
          ),
          const SizedBox(height: AppSpacing.md),
          _buildSwapButton(),
          const SizedBox(height: AppSpacing.md),
          _buildFieldLabel(l10n.translate('destination')),
          const SizedBox(height: AppSpacing.sm),
          CityAutocompleteField(
            label: '',
            icon: Icons.location_on_outlined,
            value: _destination,
            hint: l10n.translate('search_location'),
            onChanged: (v) => setState(() => _destination = v),
          ),
          const SizedBox(height: AppSpacing.xl),
          _buildFieldLabel(l10n.translate('travel_date')),
          const SizedBox(height: AppSpacing.sm),
          _buildDatePickerField(l10n),
        ],
      ),
    );
  }

  Widget _buildFieldLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: AppTypography.labelSmall.copyWith(
        color: AppColors.textSub,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildSwapButton() {
    return Center(
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: AppColors.primaryLight,
          shape: BoxShape.circle,
        ),
        child: IconButton(
          onPressed: _swapLocations,
          padding: EdgeInsets.zero,
          icon: const Icon(
            Icons.swap_vert,
            color: AppColors.primary,
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildDatePickerField(AppLocalizations l10n) {
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today,
              size: 18,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              DateFormat('EEE, MMM d, yyyy').format(_selectedDate),
              style: AppTypography.bodyLarge.copyWith(
                color: AppColors.text,
              ),
            ),
            const Spacer(),
            Text(
              l10n.translate('change'),
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchButton(AppLocalizations l10n) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: _canSearch ? _searchRoutes : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          disabledBackgroundColor: AppColors.textMuted,
          disabledForegroundColor: AppColors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
        ),
        child: Text(
          l10n.translate('search_routes'),
          style: AppTypography.buttonLarge,
        ),
      ),
    );
  }
}
