import 'dart:async';

import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Full list of locations matching the web frontend's BookingWizard.tsx.
const cityOptions = [
  // Rwanda Districts
  'Kigali', 'Bugesera', 'Gatsibo', 'Kayonza',
  'Kirehe', 'Ngoma', 'Nyagatare', 'Rwamagana', 'Burera', 'Gakenke',
  'Gicumbi', 'Musanze', 'Rulindo', 'Gisagara', 'Huye', 'Kamonyi',
  'Muhanga', 'Nyamagabe', 'Nyanza', 'Nyaruguru', 'Ruhango', 'Karongi',
  'Ngororero', 'Nyabihu', 'Nyamasheke', 'Rubavu', 'Rusizi', 'Rutsiro',
  // East Africa Cities
  'Nairobi', 'Mombasa', 'Kisumu', 'Nakuru', 'Eldoret',
  'Kampala', 'Entebbe', 'Jinja', 'Mbarara', 'Gulu', 'Fort Portal',
  'Dodoma', 'Dar es Salaam', 'Arusha', 'Mwanza', 'Mbeya', 'Zanzibar',
  'Juba', 'Bujumbura',
];

/// A text field with autocomplete/type-ahead dropdown for city selection.
/// Matches the web frontend's search-within-options behavior exactly:
/// - White bg, border-gray-400, rounded-md, h-12
/// - MapPin icon on left
/// - Dropdown: white bg, border, shadow-lg, max-h-44, overflow-y-auto
/// - Selected: blue-light bg, blue text, bold
/// - Hover: zinc-50 bg
class CityAutocompleteField extends StatefulWidget {
  final String label;
  final IconData icon;
  final String? value;
  final String hint;
  final ValueChanged<String?> onChanged;
  final String? Function(String?)? validator;

  const CityAutocompleteField({
    super.key,
    required this.label,
    required this.icon,
    this.value,
    required this.hint,
    required this.onChanged,
    this.validator,
  });

  @override
  State<CityAutocompleteField> createState() => _CityAutocompleteFieldState();
}

class _CityAutocompleteFieldState extends State<CityAutocompleteField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  List<String> _filteredOptions = [];
  Timer? _blurTimer;

  /// Mirrors `_controller.text.isNotEmpty` so the suffix button can be shown
  /// from a plain field read instead of forcing a rebuild on every keystroke.
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    if (widget.value != null) {
      _controller.text = widget.value!;
      _hasText = widget.value!.isNotEmpty;
    }
    // Keeps the clear (suffix) button in sync with the field contents.
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(CityAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != null && widget.value != oldWidget.value) {
      _controller.text = widget.value!;
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  /// Only rebuilds when the clear button's visibility actually flips, so
  /// ordinary typing (which routes through [onChanged]) doesn't repaint.
  void _onTextChanged() {
    final hasText = _controller.text.isNotEmpty;
    if (hasText == _hasText) return;
    setState(() => _hasText = hasText);
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _filteredOptions = cityOptions;
      _showOverlay();
    } else {
      _blurTimer?.cancel();
      _blurTimer = Timer(const Duration(milliseconds: 200), () {
        if (!mounted || _focusNode.hasFocus) return;
        if (_controller.text.isNotEmpty && widget.value == null) {
          final match = _resolveBestMatch(_controller.text);
          if (match != null) {
            _controller.text = match;
            widget.onChanged(match);
          }
        }
        _removeOverlay();
      });
    }
  }

  String? _resolveBestMatch(String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return null;
    final exact = cityOptions.firstWhere(
      (o) => o.toLowerCase() == q,
      orElse: () => '',
    );
    if (exact.isNotEmpty) return exact;
    final startsWith = cityOptions.firstWhere(
      (o) => o.toLowerCase().startsWith(q),
      orElse: () => '',
    );
    if (startsWith.isNotEmpty) return startsWith;
    final includes = cityOptions.firstWhere(
      (o) => o.toLowerCase().contains(q),
      orElse: () => '',
    );
    return includes.isNotEmpty ? includes : null;
  }

  void _filterOptions(String query) {
    // Lower-case once: this runs on every keystroke and the list is scanned
    // per candidate.
    final q = query.toLowerCase();
    _filteredOptions = q.isEmpty
        ? cityOptions
        : cityOptions.where((o) => o.toLowerCase().contains(q)).toList();
    _refreshOverlay();
  }

  void _selectOption(String option) {
    _controller.text = option;
    widget.onChanged(option);
    _focusNode.unfocus();
    _removeOverlay();
  }

  void _showOverlay() {
    // Already mounted — just repaint with the new option list.
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }
    _overlayEntry = OverlayEntry(
      builder: _buildOverlayContent,
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  /// Repaints the dropdown in place. Removing and re-inserting the entry on
  /// every keystroke tore down and rebuilt the whole overlay subtree (and the
  /// `ListView` with it) for each character typed; marking it dirty re-runs
  /// only the entry's builder.
  void _refreshOverlay() {
    if (_overlayEntry == null) return;
    _overlayEntry!.markNeedsBuild();
  }

  Widget _buildOverlayContent(BuildContext overlayContext) {
    final options = _filteredOptions;
    return Positioned(
      width: MediaQuery.of(overlayContext).size.width - AppSpacing.lg * 2,
      child: CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        offset: const Offset(0, 52),
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 180),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: options.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(
                      AppLocalizations.of(overlayContext)
                          .translate('no_locations_found'),
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  )
                : ListView.builder(
                    key: ValueKey(options.length),
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options[index];
                      final isSelected = option == widget.value;
                      return InkWell(
                        onTap: () => _selectOption(option),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color:
                                isSelected ? AppColors.primaryLight : null,
                            border: Border(
                              bottom: index < options.length - 1
                                  ? const BorderSide(
                                      color: Color(0xFFF8FAFC),
                                      width: 0.5,
                                    )
                                  : BorderSide.none,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.place_outlined,
                                size: 15,
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.textMuted,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  option,
                                  style: AppTypography.bodyMedium.copyWith(
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.text,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                const Icon(
                                  Icons.check,
                                  size: 16,
                                  color: AppColors.primary,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }

  void _removeOverlay() {
    _blurTimer?.cancel();
    _blurTimer = null;
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextFormField(
        controller: _controller,
        focusNode: _focusNode,
        validator: widget.validator,
        textCapitalization: TextCapitalization.words,
        style: AppTypography.bodyMedium.copyWith(color: AppColors.text),
        decoration: InputDecoration(
          labelText: widget.label.isNotEmpty ? widget.label : null,
          hintText: widget.hint,
          hintStyle: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
          prefixIcon: Icon(widget.icon, size: 18, color: AppColors.textMuted),
          suffixIcon: _hasText
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged(null);
                    _filterOptions('');
                  },
                )
              : null,
          filled: true,
          fillColor: AppColors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            borderSide: const BorderSide(color: AppColors.error),
          ),
        ),
        onChanged: _filterOptions,
      ),
    );
  }
}
