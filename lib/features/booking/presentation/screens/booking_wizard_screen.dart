import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lottie/lottie.dart';
import '../../../../core/auth/session.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/socket_service.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/platform/badge_counts.dart';
import '../../../../core/platform/platform_providers.dart';
import '../../../../core/platform/location_service.dart';
import '../../../../core/platform/ticket_sync_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/cloth_texture.dart';
import '../../../../core/widgets/city_autocomplete_field.dart' show cityOptions;
import '../../../../core/widgets/cloth_button.dart';
import '../../../../core/widgets/katisha_modal.dart';
import '../../data/booking_repository.dart';
import '../../../../shared/models/route_model.dart';
import '../../../../shared/models/booking_model.dart';
import '../../../../shared/models/payment_options_model.dart';
import '../../../../shared/utils/service_fee.dart';
import '../../../../l10n/app_localizations.dart';

/// Step titles, cached per language code. The header is rebuilt on every
/// wizard `setState`, and this used to run five map lookups plus a fresh list
/// allocation each time just to read one element.
String? _stepLabelsLocale;
List<String>? _stepLabelsCache;

List<String> _stepLabels(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  final code = l10n.languageCode;
  final cached = _stepLabelsCache;
  if (cached != null && _stepLabelsLocale == code) return cached;
  return _stepLabelsCache = [
    l10n.translate('step_route'),
    l10n.translate('step_agency'),
    l10n.translate('step_schedule'),
    l10n.translate('step_passengers'),
    l10n.translate('step_payment'),
  ];
}

/// A row in the grouped city picker: either a country header (`header` set) or
/// a selectable city (`city` set).
class _GroupedRow {
  const _GroupedRow.header(this.header) : city = null;
  const _GroupedRow.city(this.city) : header = null;

  final String? header;
  final String? city;
}

/// Flattens the grouped picker into a header/city row list so it can be fed to
/// a lazy `ListView.builder`. Building it eagerly with nested `for` loops in
/// `ListView.children` laid out every group and every city up front.
List<_GroupedRow> _flattenGroupedRows(
  List<MapEntry<String, List<String>>> groups,
) {
  final rows = <_GroupedRow>[];
  for (final entry in groups) {
    rows.add(_GroupedRow.header(entry.key));
    for (final city in entry.value) {
      rows.add(_GroupedRow.city(city));
    }
  }
  return rows;
}

/// Duration for the snappy, smooth bottom-sheet enter/exit animation.
const _sheetAnimDuration = Duration(milliseconds: 160);

/// East-African destination groups mirroring the web BookingWizard's route
/// catalogue (Kigali origin + cross-border cities). Booking is East Africa
/// only — there is no Rwanda-intercity journey type anymore. Groups are keyed
/// by destination country (same labels the web picker uses), with cities
/// sorted alphabetically. 'Rwanda' only holds Kigali and is hidden from the
/// destination picker, exactly like the web (origin stays fixed to Kigali).
const _eastAfricaByCountry = <String, List<String>>{
  'DR Congo': ['Kasumbalesa', 'Lubumbashi'],
  'Kenya': ['Busia', 'Kisumu', 'Nairobi', 'Nakuru'],
  'Malawi': ['Kasumuru Border', 'Lilongwe'],
  'Mozambique': ['Nampula'],
  'South Africa': ['Johannesburg'],
  'Tanzania': [
    'Arusha',
    'Bukoba',
    'Dar es Salaam',
    'Dodoma',
    'Iringa',
    'Kabanga',
    'Kahama',
    'Kigoma',
    'Manyoni',
    'Mbeya',
    'Morogoro',
    'Moshi',
    'Mwanza',
    'Nzega',
    'Shinyanga',
    'Singida',
    'Sumbawanga',
    'Tabora',
    'Tunduma',
  ],
  'Uganda': ['Busia', 'Jinja', 'Kampala', 'Mbarara', 'Ntugamo'],
  'Zambia': ['Lusaka', 'Mutambashwala'],
  'Zimbabwe': ['Bulawayo', 'Harare'],
  'Rwanda': ['Kigali'],
};

final _bookingRepoProvider = Provider<BookingRepository>((ref) {
  return BookingRepository(ref.read(apiClientProvider));
});

class BookingWizardScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? extra;
  final bool embedded;
  const BookingWizardScreen({super.key, this.extra, this.embedded = false});

  @override
  ConsumerState<BookingWizardScreen> createState() =>
      _BookingWizardScreenState();
}

class _BookingWizardScreenState extends ConsumerState<BookingWizardScreen>
    with TickerProviderStateMixin {
  int _currentStep = 0;
  final _formKey = GlobalKey<FormState>();

  // Step 0: Route (East African cross-border travel only)
  String? _origin = 'Kigali';
  String? _destination;
  bool _destinationPickerAutoOpened = false;

  /// Country inferred from the device location, used to preselect the currency
  /// and mobile-money prices on the payment step. Null until permission is
  /// granted (or when the fix is outside the region Katisha serves).
  DeviceLocation? _deviceLocation;

  // Step 1: Agency
  List<RouteModel> _routes = [];
  bool _searchingRoutes = false;
  String? _routeError;
  RouteModel? _selectedRoute;
  String? _selectedPickupPoint;
  List<Map<String, dynamic>> _agencyWorkingHours = [];

  /// Notified when [_searchingRoutes] flips to false, so the auto-opened agency
  /// sheet can wait for the route search instead of rendering empty.
  final List<VoidCallback> _routeSearchListeners = [];

  // Auto-advance
  Timer? _autoAdvanceTimer;

  // Step 2: Schedule
  DateTime _selectedDate = DateTime.now();
  DateTime _calendarMonth = DateTime.now();
  bool _datePicked = false;
  String? _selectedTime;

  // Step 3: Seats
  int _seatCount = 1;

  // Step 4: Payment (online via PawaPay is the only option; 'mom' is the
  // default mobile-money provider recorded on the booking, matching the web's
  // PAYMENT_METHODS default)
  String _paymentMethod = 'mom';
  String? _paymentChannel; // 'pawapay_online' (only option)

  // Country-aware payment options (pawaPay active configuration).
  PaymentOptions? _paymentOptions;
  PaymentCountryOption? _paymentCountry;
  PaymentProviderOption? _paymentProvider;
  bool _loadingPaymentOptions = false;
  String? _paymentOptionsError;

  /// Set once the traveller picks a country by hand, so a late GPS fix cannot
  /// silently change the country they chose.
  bool _paymentCountryTouched = false;

  // Payment modal state (matches web flow: summary -> green button ->
  // Pay Online modal)
  bool _isLoggedIn = false;
  String? _cachedUserName;

  final _phoneController = TextEditingController();
  final _guestNameController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSubmitting = false;
  String? _submitError;

  // Confirmation / Waiting states
  bool _bookingConfirmed = false;
  bool _paymentWaiting = false;
  String? _confirmedReferenceCode;
  String? _confirmedTicketImage;
  String? _paymentWaitingBookingId;
  String? _paymentWaitingReference;
  String? _paymentError;
  bool _cancellingWaiting = false;
  bool _paymentFailed = false;
  String? _paymentFailureReason;
  Timer? _paymentPollTimer;
  Timer? _paymentTimeoutTimer;
  Timer? _postConfirmTimer;
  bool _paymentVerifyInFlight = false;
  int _paymentPollIntervalMs = _minPaymentPollMs;

  bool _paymentBookingFound = false;
  bool _paymentSlow = false;

  static const int _minPaymentPollMs = 1000;
  static const int _maxPaymentPollMs = 4000;
  static const int _slowPaymentPollMs = 10000;
  static const Duration _bookingLookupGrace = Duration(seconds: 90);
  static const String _referenceAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  late AnimationController _progressAnimController;
  late AnimationController _confirmAnimController;
  late final Animation<double> _confirmScale;
  late AnimationController _blinkController;
  bool _blinkSyncScheduled = false;
  final _departureTimeKey = GlobalKey();
  StreamSubscription? _paymentSub;

  BookingRepository get _repo => ref.read(_bookingRepoProvider);

  @override
  void initState() {
    super.initState();
    _progressAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _confirmAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    // Created once: a CurvedAnimation built in build() registers a status
    // listener on the controller every rebuild and is never disposed.
    _confirmScale = CurvedAnimation(
      parent: _confirmAnimController,
      curve: Curves.elasticOut,
    );
    _progressAnimController.forward();

    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializeFirstStep());
    });
  }

  /// Location comes first: the destination picker auto-opens as soon as the
  /// first step is visible, so request access before that sheet is pushed.
  Future<void> _initializeFirstStep() async {
    _applyExtraParams();
    await _requestLocation();
    if (!mounted) return;
    // Warm the payment catalogue now, in the background. The traveller then
    // spends the route/date/seat steps loading it, so the payment modal opens
    // with the options already in memory instead of showing a spinner.
    unawaited(_loadPaymentOptions());
    _autoOpenDestinationPicker();
  }

  /// Asks the OS for location access immediately when the booking screen
  /// opens. There is no extra in-app explanation step: Android/iOS show their
  /// own permission dialog, and an already-granted permission is reused.
  ///
  /// Only the permission round-trip is awaited (it is instant once granted).
  /// The GPS fix is resolved in the background, so the destination picker the
  /// traveller is waiting for is never held up by a slow satellite lock.
  Future<void> _requestLocation() async {
    final service = ref.read(locationServiceProvider);
    final access = await service.ensureAccess();
    if (!mounted) return;

    if (access == LocationAccess.granted) {
      unawaited(_resolveLocation(service));
      return;
    }

    // Only guide the traveller when the OS can no longer ask (blocked
    // permission or location services switched off). A plain "deny" is left
    // alone so the app never nags.
    if (access == LocationAccess.denied) return;

    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          access == LocationAccess.serviceDisabled
              ? l10n.translate('location_service_disabled')
              : l10n.translate('location_permission_denied'),
        ),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: l10n.translate('location_permission_settings'),
          onPressed: () {
            if (access == LocationAccess.serviceDisabled) {
              unawaited(service.openLocationSettings());
            } else {
              unawaited(service.openAppSettings());
            }
          },
        ),
      ),
    );
  }

  /// Fills in the device country once the GPS fix lands. Nobody is blocked on
  /// this: the picker is already open and the prices simply refine when the
  /// location arrives.
  Future<void> _resolveLocation(LocationService service) async {
    final location = await service.currentLocation();
    if (location == null || !mounted) return;

    setState(() {
      _deviceLocation = location;
      // Refine the paying country from the actual fix, but never override a
      // choice the traveller made by hand.
      if (!_paymentCountryTouched) {
        final match = _paymentOptions?.countryByCode(location.countryIso2);
        if (match != null && match.code != _paymentCountry?.code) {
          _paymentCountry = match;
          _paymentProvider = match.providers.isNotEmpty
              ? match.providers.first
              : null;
          _paymentMethod = _paymentProvider?.method ?? 'mom';
        }
      }
    });
  }

  /// Opens the destination picker automatically when the wizard starts on the
  /// route step with no destination chosen yet (origin already defaults to
  /// Kigali and the city groups are local constants, so nothing is fetched).
  void _autoOpenDestinationPicker() {
    if (_destinationPickerAutoOpened) return;
    if (_currentStep != 0) return;
    final hasDestination = _destination != null && _destination!.isNotEmpty;
    if (hasDestination) return;
    _destinationPickerAutoOpened = true;
    _openDestinationPicker();
  }

  @override
  void dispose() {
    _progressAnimController.dispose();
    _confirmAnimController.dispose();
    _blinkController.dispose();
    _phoneController.dispose();
    _guestNameController.dispose();
    _scrollController.dispose();
    _paymentSub?.cancel();
    _paymentPollTimer?.cancel();
    _paymentTimeoutTimer?.cancel();
    _postConfirmTimer?.cancel();
    _autoAdvanceTimer?.cancel();
    super.dispose();
  }

  void _applyExtraParams() {
    final extra = widget.extra;
    if (extra == null) return;
    if (extra['origin'] != null) {
      _origin = extra['origin'] as String;
    }
    if (extra['destination'] != null) {
      _destination = extra['destination'] as String;
      _origin ??= 'Kigali';
    }
    if (extra['date'] != null) {
      final d = DateTime.tryParse(extra['date'] as String);
      if (d != null) {
        _selectedDate = d;
        _calendarMonth = DateTime(d.year, d.month);
      }
    }
    if (extra['route'] is RouteModel) {
      _selectedRoute = extra['route'] as RouteModel;
      _origin = _selectedRoute!.origin;
      _destination = _selectedRoute!.destination;
      _searchRoutes();
    }
    setState(() {});
  }

  // ── Validation ──

  String? _stepError() {
    switch (_currentStep) {
      case 0:
        if (_origin == null || _origin!.isEmpty)
          return 'Please select an origin city';
        if (_destination == null || _destination!.isEmpty)
          return AppLocalizations.of(context).translate('select_destination');
        if (_origin == _destination)
          return 'Origin and destination must be different';
        return null;
      case 1:
        if (_selectedRoute == null)
          return AppLocalizations.of(
            context,
          ).translate('select_agency_continue');
        return null;
      case 2:
        if (!_datePicked)
          return AppLocalizations.of(context).translate('select_travel_date');
        if (_selectedTime == null)
          return AppLocalizations.of(
            context,
          ).translate('select_departure_time');
        return null;
      case 3:
        if (_seatCount < 1) return 'At least 1 seat is required';
        return null;
      case 4:
        if (_phoneController.text.replaceAll(RegExp(r'[^0-9]'), '').length < 9)
          return 'Please enter a valid phone number';
        return null;
      default:
        return null;
    }
  }

  // ── Auto-advance & agency helpers ──

  void _scheduleAutoAdvance() {
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      _goNext();
    });
  }

  Future<void> _fetchAgencyWorkingHours(String agencyId) async {
    try {
      final response = await ref
          .read(apiClientProvider)
          .get('/agencies/public/$agencyId');
      final data = response.data;
      final agency = data is Map<String, dynamic>
          ? (data['agency'] as Map<String, dynamic>?)
          : null;
      final hours = agency?['workingHours'];
      if (hours is List) {
        if (!mounted) return;
        setState(() {
          _agencyWorkingHours = hours.cast<Map<String, dynamic>>();
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _agencyWorkingHours = []);
    }
  }

  /// Today's availability windows as `(startMinute, endMinute)` pairs, or null
  /// when the agency publishes no hours (every slot is then available).
  ///
  /// Memoised because `_isTimeSlotAvailable` runs once per slot — up to 48 —
  /// on every rebuild of the schedule step. Previously each of those calls
  /// re-filtered `_agencyWorkingHours` and re-parsed four `HH:mm` strings per
  /// window; now the parse happens once per (date, hours) pair.
  List<(int, int)>? _availabilityWindows;
  int? _availabilityWindowsDay;
  int _availabilityWindowsStamp = -1;

  List<(int, int)>? _resolveAvailabilityWindows() {
    if (_agencyWorkingHours.isEmpty) return null;
    final dayOfWeek = _selectedDate.weekday % 7;
    final stamp = identityHashCode(_agencyWorkingHours);
    if (_availabilityWindowsDay == dayOfWeek &&
        _availabilityWindowsStamp == stamp) {
      return _availabilityWindows;
    }
    final windows = <(int, int)>[];
    for (final h in _agencyWorkingHours) {
      if (h['dayOfWeek'] != dayOfWeek) continue;
      final start = _parseHhMm(h['start'] as String?);
      final end = _parseHhMm(h['end'] as String?);
      if (start == null || end == null) continue;
      windows.add((start, end));
    }
    _availabilityWindows = windows;
    _availabilityWindowsDay = dayOfWeek;
    _availabilityWindowsStamp = stamp;
    return windows;
  }

  /// Parses `HH:mm` into minutes-since-midnight, or null if malformed.
  static int? _parseHhMm(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  bool _isTimeSlotAvailable(String time) {
    final minutes = _parseHhMm(time);
    if (minutes == null) return false;

    // Match the web: on a same-day trip only departures that are still ahead
    // are offered, so the last bookable departure can never be in the past.
    final now = DateTime.now();
    if (_isSameDay(_selectedDate, now)) {
      final nowMinutes = now.hour * 60 + now.minute;
      if (minutes <= nowMinutes) return false;
    }

    final windows = _resolveAvailabilityWindows();
    if (windows == null) return true;
    if (windows.isEmpty) return false;
    for (final w in windows) {
      if (minutes >= w.$1 && minutes < w.$2) return true;
    }
    return false;
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // ── Route search ──

  Future<void> _searchRoutes() async {
    if (_origin == null || _destination == null) return;
    setState(() {
      _searchingRoutes = true;
      _routeError = null;
      _routes = [];
      _selectedRoute = null;
      _selectedPickupPoint = null;
      _agencyWorkingHours = [];
    });

    final result = await _repo.searchRoutes(_origin!, _destination!);
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _routeError = failure.message;
        _searchingRoutes = false;
      }),
      (routes) => setState(() {
        // Mirror the web normalizeAgencyRoutes: only East African routes are
        // bookable.
        _routes = routes.where((r) => r.type == 'east_africa').toList();
        _searchingRoutes = false;
      }),
    );

    // Release anyone waiting for the sheet to have rows to show.
    for (final listener in [..._routeSearchListeners]) {
      listener();
    }
  }

  // ── Navigation ──

  void _goBack() {
    _autoAdvanceTimer?.cancel();
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _progressAnimController
        ..reset()
        ..forward();
    }
  }

  void _goNext() {
    final error = _stepError();
    if (error != null) {
      setState(() => _submitError = error);
      return;
    }
    setState(() => _submitError = null);

    // Default pickup point to Bus Station if route has stops but none selected
    if (_currentStep == 1 &&
        _selectedRoute != null &&
        _selectedRoute!.stops.any(
          (s) =>
              s.name.toLowerCase() != _origin!.toLowerCase() &&
              s.name.toLowerCase() != _destination!.toLowerCase(),
        ) &&
        _selectedPickupPoint == null) {
      setState(() => _selectedPickupPoint = 'Bus Station');
    }

    if (_currentStep == 0) {
      _searchRoutes();
      setState(() => _currentStep++);
      _progressAnimController
        ..reset()
        ..forward();
      _scrollToTop();
      // The agency picker opens on its own once the step is showing: the user
      // already committed to this leg of the trip by tapping Continue, so
      // making them tap a collapsed selector first is a wasted step.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openAgencyModal();
      });
      return;
    }

    if (_currentStep < 4) {
      setState(() => _currentStep++);
      _progressAnimController
        ..reset()
        ..forward();
      _scrollToTop();
      // Load the country-aware payment options as the payment step opens, so
      // the amounts are already shown in the traveller's currency.
      if (_currentStep == 4) {
        unawaited(_loadPaymentOptions());
      }
      // Auto-open the schedule pickers when the schedule step is reached,
      // mirroring how the destination picker auto-opens.
      if (_currentStep == 2) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!_datePicked) {
            _openDatePickerModal();
          } else {
            _openTimePickerModal();
          }
        });
      }
    } else {
      _submitBooking();
    }
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /// Drives the pulsing "select travel hour" hint on the schedule step. It
  /// blinks while the user still needs to pick a departure time and stops as
  /// soon as one is chosen (or when leaving the step).
  ///
  /// Called from [build] through [_scheduleBlinkSync] rather than directly:
  /// [repeat]/[stop] drive a [Ticker], which marks the widget dirty and can
  /// re-enter the build phase from inside the current one.
  void _syncBlink() {
    final shouldBlink = _currentStep == 2 && _selectedTime == null;
    if (shouldBlink && !_blinkController.isAnimating) {
      _blinkController.repeat(reverse: true);
    } else if (!shouldBlink && _blinkController.isAnimating) {
      _blinkController.stop();
      _blinkController.value = 1.0;
    }
  }

  /// Defers [_syncBlink] to after the current frame, coalescing repeat calls
  /// into a single post-frame callback.
  void _scheduleBlinkSync() {
    if (_blinkSyncScheduled) return;
    _blinkSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _blinkSyncScheduled = false;
      if (!mounted) return;
      _syncBlink();
    });
  }

  /// Scrolls the schedule step so the departure-time selection is centred.
  void _scrollToDepartureTime() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _departureTimeKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.0,
      );
    });
  }

  /// Pull-to-refresh: reset the whole wizard back to the first route-selection
  /// step so the user can start a fresh booking flow.
  Future<void> _refreshWizard() async {
    _autoAdvanceTimer?.cancel();
    setState(() {
      _currentStep = 0;
      _formKey.currentState?.reset();

      _origin = 'Kigali';
      _destination = null;

      _routes = [];
      _searchingRoutes = false;
      _routeError = null;
      _selectedRoute = null;
      _selectedPickupPoint = null;
      _agencyWorkingHours = [];

      _selectedDate = DateTime.now();
      _calendarMonth = DateTime.now();
      _datePicked = false;
      _selectedTime = null;

      _seatCount = 1;

      _paymentChannel = null;

      _phoneController.clear();
      _guestNameController.clear();
      _submitError = null;
      _bookingConfirmed = false;
      _paymentWaiting = false;
      _confirmedReferenceCode = null;
      _confirmedTicketImage = null;
      _paymentWaitingBookingId = null;
      _paymentWaitingReference = null;
      _paymentError = null;
      _paymentFailed = false;
      _paymentFailureReason = null;
      _paymentBookingFound = false;
      _paymentSlow = false;
      _cancellingWaiting = false;
      _paymentPollTimer?.cancel();
      _paymentPollTimer = null;
      _paymentTimeoutTimer?.cancel();
      _paymentTimeoutTimer = null;
    });
    _progressAnimController
      ..reset()
      ..forward();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _scrollToTop();
  }

  // ── Submit booking ──

  Future<void> _submitBooking() async {
    final channel = _paymentChannel ?? 'pawapay_online';
    final digits = _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 9) {
      setState(() {
        _submitError = 'Please enter a valid payment phone number';
      });
      return;
    }

    // Created before the request: if the create call times out or returns 500
    // *after* pawaPay has pushed the payment prompt, this reference lets the
    // polling code find the booking and keep it in "processing" rather than
    // wrongly declaring the payment failed.
    final referenceCode = _generateBookingReference();
    setState(() {
      _isSubmitting = true;
      _submitError = null;
      _paymentBookingFound = false;
      _paymentSlow = false;
    });

    final data = <String, dynamic>{
      'referenceCode': referenceCode,
      'routeId': _selectedRoute!.id,
      'agencyId': _selectedRoute!.agency.id,
      'origin': _origin,
      'destination': _destination,
      'travelDate': _selectedDate.toIso8601String().substring(0, 10),
      'travelTime': _selectedTime,
      'seats': _seatCount,
      'paymentChannel': channel,
      'paymentMethod': _paymentMethod,
      'phone': _normalizePhone(_phoneController.text),
      'paymentCountry': _paymentCountry?.code,
      'paymentCurrency': _paymentCurrency,
      if (_paymentProvider != null)
        'paymentProvider': _paymentProvider!.provider,
    };

    if (_selectedPickupPoint != null) {
      data['pickupPoint'] = _selectedPickupPoint;
    }

    // When logged in the name field is hidden and pre-filled from the account,
    // so fall back to the cached account name if the controller is empty.
    var guestName = _guestNameController.text.trim();
    if (guestName.isEmpty && _isLoggedIn) {
      guestName = _cachedUserName ?? '';
    }
    if (guestName.isEmpty) {
      setState(() {
        _isSubmitting = false;
        _submitError = 'Please enter your name';
      });
      return;
    }
    data['guestName'] = guestName;
    data['isGuest'] = true;

    final result = await _repo.createGuestBooking(data);
    if (!mounted) return;

    result.fold(
      (failure) {
        // A 4xx validation error means the booking was never created — show it
        // on the form. Timeouts, network errors and 5xx are ambiguous: the
        // booking may exist and the pawaPay prompt may already be on the
        // customer's phone, so keep polling our reference before deciding.
        if (_isAmbiguousCreateFailure(failure)) {
          _enterWaitingForUnconfirmedBooking(referenceCode, failure.message);
          return;
        }
        setState(() {
          _isSubmitting = false;
          _bookingConfirmed = false;
          _paymentWaiting = false;
          _submitError = failure.message;
          _paymentFailed = false;
        });
      },
      (bookingData) {
        // Guest booking auto-creates an account and returns tokens,
        // matching the web frontend's register-on-purchase flow.
        final accessToken = bookingData['accessToken'] as String?;
        final refreshToken = bookingData['refreshToken'] as String?;
        if (accessToken != null && refreshToken != null) {
          ref
              .read(apiClientProvider)
              .setTokens(accessToken: accessToken, refreshToken: refreshToken);
          // The user is now logged in — sync their tickets to local storage so
          // they can be viewed offline.
          startBackgroundTicketSync(ref);
        }

        // Extract booking details from either flat response or nested booking object
        Map<String, dynamic> bookingObj;
        if (bookingData['booking'] is Map) {
          bookingObj = bookingData['booking'] as Map<String, dynamic>;
        } else {
          bookingObj = bookingData;
        }
        final bookingId =
            bookingObj['_id'] as String? ?? bookingObj['id'] as String? ?? '';
        final refCode =
            bookingObj['referenceCode'] as String? ??
            bookingData['referenceCode'] as String? ??
            '';
        final ticketImg =
            bookingObj['ticketImage'] as String? ??
            bookingData['ticketImage'] as String?;
        final paymentStatus =
            bookingObj['paymentStatus'] as String? ??
            bookingData['paymentStatus'] as String? ??
            'pending';
        final status =
            bookingObj['status'] as String? ??
            bookingData['status'] as String? ??
            'pending';
        final rejectionReason =
            bookingObj['rejectionReason'] as String? ??
            bookingData['rejectionReason'] as String?;

        // Persist the booking locally right away so it is always available
        // offline once purchased (internet is guaranteed at this moment).
        _cacheTicketLocally(bookingId, bookingObj);

        // A booking is only truly paid (and the user's ticket ready) once
        // `paymentStatus` is 'paid'. A `status` of 'confirmed' only means the
        // booking was *accepted*, not that the payment went through.
        if (paymentStatus == 'paid') {
          ref.read(soundServiceProvider).vibrate();
          _scheduleDepartureAlerts(bookingId);
          ref
              .read(localNotificationStoreProvider)
              .add(
                title: 'Booking Confirmed',
                message:
                    'Your booking ${refCode.isEmpty ? 'was' : refCode} confirmed.',
                type: 'booking',
                entityId: bookingId,
              );
          setState(() {
            _isSubmitting = false;
            _bookingConfirmed = true;
            _confirmedReferenceCode = refCode;
            _confirmedTicketImage = ticketImg;
          });
          _confirmAnimController.forward();
          _postConfirmTimer?.cancel();
          _postConfirmTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) context.go('/my-bookings');
          });
        } else if (status == 'cancelled') {
          // User cancelled the payment — return home without showing
          // the "insufficient funds" failure screen.
          setState(() {
            _isSubmitting = false;
            _paymentWaiting = false;
            _paymentWaitingBookingId = bookingId;
            _paymentWaitingReference = refCode;
          });
          if (mounted) context.go('/home');
        } else if (paymentStatus == 'failed') {
          setState(() {
            _isSubmitting = false;
            _bookingConfirmed = false;
            _paymentWaiting = false;
            _paymentFailed = true;
            _paymentFailureReason = rejectionReason;
            _paymentWaitingBookingId = bookingId;
            _paymentWaitingReference = refCode;
          });
          _recordFailureNotification(bookingId, refCode, rejectionReason);
        } else {
          setState(() {
            _isSubmitting = false;
            _paymentWaiting = true;
            _paymentWaitingBookingId = bookingId;
            _paymentWaitingReference = refCode;
            _paymentBookingFound = true;
          });
          _listenForPayment(bookingId);
          _startPaymentPolling();
          _startPaymentVerificationTimer();
        }
      },
    );
  }

  /// Client-side booking reference, accepted by the server. Used to keep
  /// tracking the booking when the create response is lost after pawaPay has
  /// already pushed the "to pay" prompt.
  String _generateBookingReference() {
    final random = Random.secure();
    String block(int length) => List.generate(
          length,
          (_) => _referenceAlphabet[random.nextInt(_referenceAlphabet.length)],
        ).join();
    return 'BOK-${block(4)}-${block(8)}';
  }

  bool _isAmbiguousCreateFailure(Failure failure) {
    if (failure is TimeoutFailure ||
        failure is NetworkFailure ||
        failure is UnknownFailure) {
      return true;
    }
    if (failure is ServerFailure) {
      final code = failure.statusCode;
      // 4xx (except a gateway-style 408/429) means the request was rejected
      // before a booking could be created. Everything else may have reached
      // the server and pawaPay, so verify before telling the user it failed.
      return code == 408 ||
          code == 429 ||
          code == null ||
          code >= 500;
    }
    return false;
  }

  /// Enters the waiting view for a booking whose create response was lost.
  /// No failure screen is shown until tracking proves the outcome.
  void _enterWaitingForUnconfirmedBooking(
    String reference,
    String? createFailureMessage,
  ) {
    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _bookingConfirmed = false;
      _paymentFailed = false;
      _paymentWaiting = true;
      _paymentWaitingReference = reference;
      _paymentWaitingBookingId = null;
      _paymentFailureReason = null;
      _paymentError = null;
      _paymentBookingFound = false;
      _paymentSlow = false;
    });
    // Do not surface the raw create error as a failure: a 500/timeout here is
    // exactly the ambiguous case this flow is designed to resolve by polling.
    debugPrint('[Booking] create response ambiguous ($createFailureMessage); '
        'tracking $reference');
    _listenForPayment(reference);
    _startPaymentPolling();
    _startPaymentVerificationTimer();
  }

  void _scheduleDepartureAlerts(String bookingId) {
    final routeName =
        '${_selectedRoute?.origin ?? ''} → ${_selectedRoute?.destination ?? ''}';

    DateTime? departure;
    final selectedDate = _selectedDate;
    if (_selectedTime != null) {
      final parts = _selectedTime!.split(':');
      if (parts.length == 2) {
        departure = DateTime(
          selectedDate.year,
          selectedDate.month,
          selectedDate.day,
          int.tryParse(parts[0]) ?? 0,
          int.tryParse(parts[1]) ?? 0,
        );
      }
    }

    if (bookingId.isEmpty || departure == null) return;
    if (departure.isBefore(DateTime.now())) return;

    ref
        .read(notificationServiceProvider)
        .scheduleJourneyAlerts(
          bookingId: bookingId,
          routeName: routeName,
          departureTime: departure,
        );
  }

  /// Immediately persists a freshly-created booking (JSON + private ticket
  /// image) to the device. Called while the user is online during purchase so
  /// the issued ticket is always available to view offline afterwards. When
  /// [bookingObj] is empty (late payment confirmation) the existing cached
  /// booking is patched with [patch] fields (e.g. paymentStatus: 'paid')
  /// instead of being overwritten.
  Future<void> _cacheTicketLocally(
    String bookingId,
    Map<String, dynamic> bookingObj, [
    String? ticketImage,
    Map<String, dynamic>? patch,
  ]) async {
    if (bookingId.isEmpty) return;
    final store = ref.read(localTicketStoreProvider);
    if (bookingObj.isNotEmpty) {
      try {
        await store.cacheBooking(bookingId, bookingObj);
      } catch (_) {}
    } else if (patch != null && patch.isNotEmpty) {
      try {
        final existing = await store.getBooking(bookingId);
        if (existing != null) {
          existing.addAll(patch);
          await store.cacheBooking(bookingId, existing);
        }
      } catch (_) {}
    }
    final ticketImg = ticketImage ?? (bookingObj['ticketImage'] as String?);
    if (ticketImg == null || ticketImg.isEmpty) return;
    if (await store.getTicketImagePath(bookingId) != null) return;
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.downloadBytes(ticketImg);
      final bytes = response.data;
      if (bytes is List<int>) {
        await store.saveTicketImage(bookingId, Uint8List.fromList(bytes));
      }
    } catch (_) {}
  }

  void _listenForPayment(String bookingId) {
    try {
      final socketService = ref.read(socketServiceProvider);
      _paymentSub = socketService.onPaymentConfirmed.listen((data) {
        if (!mounted) return;
        final dataBookingId =
            data['bookingId'] as String? ?? data['_id'] as String? ?? '';
        if (dataBookingId == bookingId ||
            data['referenceCode'] == _paymentWaitingReference) {
          _handlePaymentOutcome(
            paid: true,
            bookingId: dataBookingId.isNotEmpty
                ? dataBookingId
                : (_paymentWaitingBookingId ?? ''),
            referenceCode: _paymentWaitingReference,
            ticketImage: data['ticketImage'] as String?,
          );
        }
      });
    } catch (_) {}
  }

  Future<void> _verifyPayment() async {
    // Never stack polls: if a slow request is still in flight when the next
    // 1s tick fires, skip it so we don't open many parallel requests.
    if (_paymentVerifyInFlight) return;
    _paymentVerifyInFlight = true;
    try {
      // Mirror the web frontend: poll the public track endpoint by reference
      // code, which actively verifies the pawaPay collection server-side and
      // flips the booking to paid/failed. Polling by id would only read the
      // stored status and can stay "processing" forever.
      final reference = _paymentWaitingReference;
      if (reference == null || reference.isEmpty) return;
      final result = await _repo.trackBooking(reference);
      if (!mounted) return;
      result.fold(
        // Tracking errors are NOT payment failures. A 404 just means the
        // create request is still committing (or never committed); 5xx/network
        // errors are transient. Only a successful track response with
        // paymentStatus 'failed' is an authoritative failure.
        (failure) {
          // Some deployed servers reject every hyphenated reference in their
          // route middleware (HTTP 400 "Invalid reference code format"), so
          // the public track endpoint can never resolve a real booking. When
          // we know the booking id from the create response, fall back to the
          // authenticated booking endpoint, which has no such restriction.
          if (failure is ServerFailure &&
              (failure.statusCode == 400 || failure.statusCode == 404)) {
            final bookingId = _paymentWaitingBookingId;
            if (bookingId != null && bookingId.isNotEmpty) {
              unawaited(_verifyByBookingId());
            } else if (mounted) {
              setState(() => _paymentError = null);
            }
          }
        },
        (booking) {
          if (mounted && !_paymentBookingFound) {
            setState(() => _paymentBookingFound = true);
          }
          _handlePaymentOutcomeFromBooking(booking);
        },
      );
    } finally {
      _paymentVerifyInFlight = false;
    }
  }

  /// Fallback status check used when the public track endpoint cannot accept
  /// our reference (e.g. an older server that rejects hyphenated codes).
  /// Reads the stored payment status by booking id; webhooks/sweeper keep that
  /// status authoritative, so a terminal result can still resolve the screen.
  Future<void> _verifyByBookingId() async {
    final bookingId = _paymentWaitingBookingId;
    if (bookingId == null || bookingId.isEmpty) return;
    final result = await _repo.getBooking(bookingId);
    if (!mounted || !_paymentWaiting) return;
    result.fold(
      (_) {},
      (booking) {
        if (!_paymentBookingFound) {
          setState(() => _paymentBookingFound = true);
        }
        _handlePaymentOutcomeFromBooking(booking);
      },
    );
  }

  /// Routes a fetched [Booking] to its correct terminal state (paid or failed).
  /// A booking is only "paid" when `paymentStatus` is 'paid' — a `status` of
  /// 'confirmed' merely means it was accepted, not that the money went through.
  void _handlePaymentOutcomeFromBooking(Booking booking) {
    // trackBooking returns a PII-limited booking without _id, so fall back to
    // the id held from the original create response where needed.
    final bookingId = booking.id.isNotEmpty
        ? booking.id
        : (_paymentWaitingBookingId ?? '');
    if (booking.paymentStatus == 'paid') {
      _handlePaymentOutcome(
        paid: true,
        bookingId: bookingId,
        referenceCode: booking.referenceCode,
        ticketImage: booking.ticketImage,
      );
    } else if (booking.paymentStatus == 'failed') {
      _handlePaymentOutcome(
        paid: false,
        bookingId: bookingId,
        referenceCode: booking.referenceCode,
        reason: booking.rejectionReason,
      );
    } else if (booking.status == 'cancelled') {
      _handlePaymentOutcome(
        paid: false,
        bookingId: bookingId,
        referenceCode: booking.referenceCode,
        cancelled: true,
      );
    } else {
      // Still processing/pending — keep the waiting UI and let the next poll
      // (or the verification timer) resolve it. No error is surfaced here
      // because being "pending" is a normal in-flight state, not a failure.
    }
  }

  void _handlePaymentOutcome({
    required bool paid,
    required String bookingId,
    String? referenceCode,
    String? ticketImage,
    String? reason,
    bool cancelled = false,
  }) {
    if (_paymentFailed || _bookingConfirmed || !mounted) return;
    _stopPaymentPolling();
    _stopPaymentVerificationTimer();
    _paymentSub?.cancel();

    if (paid) {
      ref.read(soundServiceProvider).vibrate();
      _scheduleDepartureAlerts(bookingId);
      // Keep the (now paid) ticket fully available offline — the booking JSON
      // was cached at creation, so mark it paid and save the image while we
      // still have internet.
      // Patch the cached booking even when the image is not ready yet: the
      // badge derives from paymentStatus, so it must become 'paid' as soon as
      // the server confirms the payment rather than waiting for an image.
      unawaited(
        _cacheTicketLocally(
          bookingId,
          const <String, dynamic>{},
          ticketImage,
          const {'paymentStatus': 'paid'},
        ),
      );
      unawaited(
        ref.read(badgeCountsProvider.notifier).refresh(),
      );
      ref
          .read(localNotificationStoreProvider)
          .add(
            title: 'Payment Confirmed!',
            message: 'Your booking ${referenceCode ?? ''} has been confirmed.',
            type: 'payment',
            entityId: bookingId,
          );
      setState(() {
        _paymentWaiting = false;
        _bookingConfirmed = true;
        _confirmedReferenceCode = referenceCode ?? _paymentWaitingReference;
        _confirmedTicketImage = ticketImage;
      });
      _confirmAnimController.forward();
      _postConfirmTimer?.cancel();
      _postConfirmTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) context.go('/my-bookings');
      });
    } else {
      // User cancelled — go home without showing the failure screen.
      if (cancelled) {
        setState(() {
          _paymentWaiting = false;
          _paymentWaitingBookingId = bookingId;
          _paymentWaitingReference = referenceCode ?? _paymentWaitingReference;
        });
        if (mounted) context.go('/home');
        return;
      }
      // A failed/cancelled booking must never contribute to the bottom-nav
      // ticket badge. Drop any local checkout cache for it as well.
      if (bookingId.isNotEmpty) {
        unawaited(ref.read(localTicketStoreProvider).removeTicket(bookingId));
        unawaited(ref.read(badgeCountsProvider.notifier).refresh());
      }
      _recordFailureNotification(bookingId, referenceCode ?? '', reason);
      setState(() {
        _paymentWaiting = false;
        _bookingConfirmed = false;
        _paymentFailed = true;
        _paymentFailureReason = reason;
      });
    }
  }

  /// Polls the booking status while the payment is being awaited, so the app
  /// reflects the real server outcome (paid or failed) that the system admin
  /// sees. Uses the public track endpoint by reference code, which reads the
  /// authoritative booking status the pawaPay webhook / sweeper updates.
  ///
  /// The interval backs off from [_minPaymentPollMs] up to [_maxPaymentPollMs]
  /// while the payment stays pending. A flat 1s `Timer.periodic` hammered the
  /// endpoint with the same answer for the whole window; the authoritative
  /// outcome still arrives promptly because the socket pushes
  /// `payment:confirmed` and the verification timer does a final check at 90s.
  void _startPaymentPolling() {
    _paymentPollIntervalMs = _minPaymentPollMs;
    _scheduleNextPaymentPoll();
  }

  void _scheduleNextPaymentPoll() {
    _paymentPollTimer?.cancel();
    _paymentPollTimer = Timer(
      Duration(milliseconds: _paymentPollIntervalMs),
      () async {
        if (!mounted) return;
        await _verifyPayment();
        if (!mounted) return;
        // Keep polling only while we're still waiting on a terminal outcome.
        if (!_paymentWaiting) return;
        final upperBound =
            _paymentSlow ? _slowPaymentPollMs : _maxPaymentPollMs;
        _paymentPollIntervalMs = (_paymentPollIntervalMs * 2).clamp(
          _minPaymentPollMs,
          upperBound,
        );
        _scheduleNextPaymentPoll();
      },
    );
  }

  void _stopPaymentPolling() {
    _paymentPollTimer?.cancel();
    _paymentPollTimer = null;
  }

  /// After the lookup grace period, decide between "still processing" and
  /// "never created". A booking that exists but is still processing is kept in
  /// the waiting state with slower polling — pawaPay prompts can stay pending
  /// for a long time, and abandoning here could release a seat for a payment
  /// that is about to complete. Only a booking that never appears is failed.
  void _startPaymentVerificationTimer() {
    _paymentTimeoutTimer?.cancel();
    _paymentTimeoutTimer = Timer(_bookingLookupGrace, () async {
      if (!mounted) return;
      final reference = _paymentWaitingReference;
      final bookingId = _paymentWaitingBookingId;
      var resolved = false;

      if (reference != null && reference.isNotEmpty) {
        final result = await _repo.trackBooking(reference);
        if (!mounted) return;
        result.fold(
          (failure) {
            // A transient tracking error is not a payment outcome. If the
            // booking was already seen, keep waiting; otherwise fall through
            // to the "never created" decision below.
          },
          (b) {
            if (mounted) {
              setState(() => _paymentBookingFound = true);
            }
            if (b.paymentStatus == 'paid') {
              _handlePaymentOutcome(
                paid: true,
                bookingId: b.id.isNotEmpty ? b.id : (bookingId ?? ''),
                referenceCode: b.referenceCode,
              );
              resolved = true;
            } else if (b.paymentStatus == 'failed') {
              _handlePaymentOutcome(
                paid: false,
                bookingId: b.id.isNotEmpty ? b.id : (bookingId ?? ''),
                referenceCode: b.referenceCode,
                reason: b.rejectionReason,
              );
              resolved = true;
            } else if (b.status == 'cancelled') {
              _handlePaymentOutcome(
                paid: false,
                bookingId: b.id.isNotEmpty ? b.id : (bookingId ?? ''),
                referenceCode: b.referenceCode,
                cancelled: true,
              );
              resolved = true;
            }
          },
        );
      }

      if (resolved || !mounted) return;

      if (_paymentBookingFound) {
        // Processing is not failure. Slow the polls and keep the waiting UI up
        // until pawaPay reports a terminal status (or the user cancels).
        setState(() {
          _paymentSlow = true;
          _paymentError = null;
          _paymentPollIntervalMs = _maxPaymentPollMs;
        });
        return;
      }

      // No booking ever appeared under our reference: the create request did
      // not commit. Report a neutral failure — never assume insufficient funds.
      _handlePaymentOutcome(
        paid: false,
        bookingId: bookingId ?? '',
        referenceCode: reference ?? '',
      );
    });
  }

  void _stopPaymentVerificationTimer() {
    _paymentTimeoutTimer?.cancel();
    _paymentTimeoutTimer = null;
  }

  void _recordFailureNotification(
    String bookingId,
    String referenceCode,
    String? reason,
  ) {
    final message = (reason != null && reason.isNotEmpty)
        ? 'Your payment for $referenceCode failed. $reason'
        : 'Your payment for $referenceCode failed. Please check your mobile money balance and try again.';
    ref
        .read(localNotificationStoreProvider)
        .add(
          title: 'Payment Failed',
          message: message,
          type: 'booking_rejected',
          entityId: bookingId,
        );
  }

  /// Returns the user to the route/destination selection after a failed
  /// booking so they can start a fresh trip.
  void _retryFromFailed() {
    _refreshWizard();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleBlinkSync();
    if (_paymentFailed) return _buildPaymentFailedView();
    if (_bookingConfirmed) return _buildConfirmedView();
    if (_paymentWaiting) return _buildPaymentWaitingView();

    final content = Column(
      children: [
        _buildHeader(),
        _buildProgressBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshWizard,
            color: AppColors.primary,
            backgroundColor: AppColors.white,
            strokeWidth: 2.5,
            displacement: 0,
            edgeOffset: 8,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildStepContent(),
                    const SizedBox(height: AppSpacing.lg),
                    if (_submitError != null) ...[
                      _buildErrorBanner(_submitError!),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    _buildNavigationButtons(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );

    // The booking page is white, so the status-bar icons (clock, battery,
    // signal) must be dark. No AppBar provides an overlay style here, and a
    // dark screen elsewhere in the stack can otherwise leave light icons
    // behind, so set it explicitly.
    const overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    );

    if (widget.embedded) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyle,
        child: SafeArea(child: content),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.white,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyle,
        child: SafeArea(child: content),
      ),
    );
  }

  // ── Header with step indicators ──

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!widget.embedded) ...[
                IconButton(
                  onPressed: () => context.go('/home'),
                  icon: const Icon(Icons.arrow_back_ios, size: 20),
                  color: AppColors.text,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Text(
                  _stepLabels(context)[_currentStep],
                  style: AppTypography.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _buildProfileChip(),
            ],
          ),
        ],
      ),
    );
  }

  /// Profile chip shown in place of the old booking-step icons.
  ///
  /// Guests who have just booked receive tokens but may not have a populated
  /// [sessionProvider] yet, so both sources are considered when deciding
  /// whether to offer "Log out".
  Widget _buildProfileChip() {
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(sessionProvider);
    final isLoggedIn = session != null ||
        _isLoggedIn ||
        ref.read(apiClientProvider).isAuthenticated;

    final name = session?.name.trim() ?? '';
    final username = session?.username.trim() ?? '';
    final cachedName = _cachedUserName?.trim() ?? '';
    final displayName = name.isNotEmpty
        ? name
        : username.isNotEmpty
        ? username
        : cachedName.isNotEmpty
        ? cachedName
        : l10n.translate('profile');

    return PopupMenuButton<String>(
      onSelected: (value) {
        switch (value) {
          case 'logout':
            unawaited(_confirmLogout());
            break;
          case 'language':
            _openLanguageSelection();
            break;
        }
      },
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      color: AppColors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      constraints: const BoxConstraints(minWidth: 190),
      itemBuilder: (_) => [
        if (isLoggedIn)
          PopupMenuItem<String>(
            value: 'logout',
            child: Row(
              children: [
                const Icon(
                  Icons.logout_rounded,
                  size: 18,
                  color: AppColors.textSub,
                ),
                const SizedBox(width: AppSpacing.sm + 4),
                Text(
                  l10n.translate('logout'),
                  style: AppTypography.bodyMedium,
                ),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'language',
          child: Row(
            children: [
              const Icon(
                Icons.language_rounded,
                size: 18,
                color: AppColors.textSub,
              ),
              const SizedBox(width: AppSpacing.sm + 4),
              Text(
                l10n.translate('change_language'),
                style: AppTypography.bodyMedium,
              ),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 2,
          vertical: AppSpacing.xs + 2,
        ),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: AppColors.primaryLight,
              child: const Icon(
                Icons.person_rounded,
                size: 16,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                displayName,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.text,
                ),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        title: Text(
          l10n.translate('logout'),
          style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
        ),
        content: Text(
          l10n.translate('logout_confirm'),
          style: AppTypography.bodySmall.copyWith(color: AppColors.textSub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              l10n.translate('cancel'),
              style: AppTypography.labelLarge.copyWith(
                color: AppColors.textSub,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              textStyle: AppTypography.buttonMedium,
            ),
            child: Text(l10n.translate('logout')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(sessionProvider.notifier).logout();
    if (!mounted) return;
    context.go('/login');
  }

  void _openLanguageSelection() {
    context.go('/onboarding');
  }

  // ── Progress bar ──

  Widget _buildProgressBar() {
    final progress = (_currentStep + 1) / 5;
    return AnimatedBuilder(
      animation: _progressAnimController,
      builder: (context, _) {
        final animatedProgress = _progressAnimController.value * progress;
        return Container(
          height: 2,
          width: double.infinity,
          color: AppColors.border,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: animatedProgress.clamp(0.0, 1.0),
              child: Container(height: 2, color: AppColors.primary),
            ),
          ),
        );
      },
    );
  }

  // ── STEP CONTENT ──

  Widget _buildStepContent() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: switch (_currentStep) {
        0 => _buildRouteStep(),
        1 => _buildAgencyStep(),
        2 => _buildScheduleStep(),
        3 => _buildSeatsStep(),
        4 => _buildPaymentStep(),
        _ => const SizedBox.shrink(),
      },
    );
  }

  // ── Step 0: Route ──

  Widget _buildRouteStep() {
    final l10n = AppLocalizations.of(context);
    return Column(
      key: const ValueKey('step-route'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Text(
          l10n.translate('plan_your_trip'),
          style: AppTypography.headlineLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.translate('choose_route_and_time'),
          style: AppTypography.bodyMedium.copyWith(color: AppColors.textSub),
        ),
        const SizedBox(height: AppSpacing.xl),
        _buildLabel(l10n.translate('origin').toUpperCase()),
        const SizedBox(height: AppSpacing.xs),
        _buildLocationSelector(
          label: l10n.translate('origin'),
          icon: Icons.location_on_outlined,
          value: _origin,
          onTap: _openOriginPicker,
        ),
        const SizedBox(height: AppSpacing.lg),
        _buildLabel(l10n.translate('destination').toUpperCase()),
        const SizedBox(height: AppSpacing.xs),
        _buildLocationSelector(
          label: l10n.translate('destination'),
          icon: Icons.location_on_outlined,
          value: _destination,
          onTap: _openDestinationPicker,
        ),
      ],
    );
  }

  void _openDestinationPicker() {
    _showLocationPicker(
      titleKey: 'select_destination_picker',
      currentValue: _destination,
      exclude: _origin,
      groups: _eastAfricaByCountry,
      showSearch: true,
      onSelected: (v) {
        setState(() => _destination = v);
        _scheduleAutoAdvance();
      },
    );
  }

  void _openOriginPicker() {
    _showLocationPicker(
      titleKey: 'select_origin',
      currentValue: _origin,
      exclude: _destination,
      groups: _eastAfricaByCountry,
      originCountry: true,
      showSearch: true,
      onSelected: (v) {
        setState(() => _origin = v);
      },
    );
  }

  Widget _buildLocationSelector({
    required String label,
    required IconData icon,
    required String? value,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
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
            Icon(icon, size: 20, color: AppColors.textMuted),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                value ?? 'Select $label',
                style: AppTypography.bodyMedium.copyWith(
                  color: value != null ? AppColors.text : AppColors.textMuted,
                ),
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down,
              size: 20,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLocationPicker({
    required String titleKey,
    required ValueChanged<String> onSelected,
    String? exclude,
    String? currentValue,
    List<String>? options,
    Map<String, List<String>>? groups,
    bool originCountry = false,
    bool showSearch = false,
  }) async {
    final base = options ?? cityOptions;
    final baseFiltered = exclude != null
        ? base.where((c) => c != exclude).toList()
        : List<String>.from(base);
    final hasGroups = groups != null;

    final result = await showKatishaModal<String>(
      context: context,
      builder: (ctx) {
        var query = '';
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            // Resolve localizations from the modal's own context on every
            // build so the sheet follows live language changes, and always
            // uses the locale that was active when it was opened.
            final l10n = AppLocalizations.of(ctx);
            final q = query.trim().toLowerCase();
            final filtered = q.isEmpty
                ? baseFiltered
                : baseFiltered
                      .where((c) => c.toLowerCase().contains(q))
                      .toList();
            final filteredGroups = <MapEntry<String, List<String>>>[];
            if (groups != null) {
              for (final entry in groups.entries) {
                if (!originCountry && entry.key.toLowerCase() == 'rwanda')
                  continue;
                final cities = entry.value
                    .where(
                      (c) =>
                          c != exclude &&
                          (q.isEmpty || c.toLowerCase().contains(q)),
                    )
                    .toList();
                if (cities.isEmpty) continue;
                filteredGroups.add(MapEntry(entry.key, cities));
              }
            }
            // Flat header/city rows so the list can build lazily.
            final rows = hasGroups
                ? _flattenGroupedRows(filteredGroups)
                : const <_GroupedRow>[];

            return KatishaModal(
              title: l10n.translate(titleKey),
              closeLabel: l10n.translate('close'),
              bodyScrollable: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showSearch)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: TextField(
                        onChanged: (v) => setSheetState(() => query = v),
                        textInputAction: TextInputAction.search,
                        style: AppTypography.bodyMedium,
                        decoration: InputDecoration(
                          hintText: l10n.translate('search_location'),
                          hintStyle: AppTypography.bodyMedium.copyWith(
                            color: AppColors.textMuted,
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            size: 20,
                            color: AppColors.primary,
                          ),
                          isDense: true,
                          filled: true,
                          fillColor: AppColors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusSm,
                            ),
                            borderSide: const BorderSide(
                              color: AppColors.primary,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusSm,
                            ),
                            borderSide: const BorderSide(
                              color: AppColors.primary,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusSm,
                            ),
                            borderSide: const BorderSide(
                              color: AppColors.primary,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child:
                        (hasGroups ? filteredGroups.isEmpty : filtered.isEmpty)
                        ? Center(
                            child: Text(
                              l10n.translate('no_locations_found'),
                              style: AppTypography.bodyMedium.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                          )
                        : hasGroups
                        ? ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.xs,
                            ),
                            itemCount: rows.length,
                            itemBuilder: (ctx, index) {
                              final row = rows[index];
                              if (row.header != null) {
                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    14,
                                    16,
                                    4,
                                  ),
                                  child: Text(
                                    row.header!,
                                    style: AppTypography.labelSmall.copyWith(
                                      color: AppColors.textMuted,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                );
                              }
                              final city = row.city!;
                              final isSelected = city == currentValue;
                              return ListTile(
                                dense: true,
                                selected: isSelected,
                                selectedTileColor: AppColors.primaryLight,
                                leading: Icon(
                                  isSelected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.textMuted,
                                  size: 20,
                                ),
                                title: Text(
                                  city,
                                  style: AppTypography.bodyLarge.copyWith(
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                                onTap: () => Navigator.pop(ctx, city),
                              );
                            },
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.xs,
                            ),
                            itemCount: filtered.length,
                            separatorBuilder: (_, _2) => const Divider(
                              height: 1,
                              indent: 16,
                              endIndent: 16,
                            ),
                            itemBuilder: (ctx, index) {
                              final city = filtered[index];
                              final isSelected = city == currentValue;
                              return ListTile(
                                dense: true,
                                selected: isSelected,
                                selectedTileColor: AppColors.primaryLight,
                                leading: Icon(
                                  isSelected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.textMuted,
                                  size: 20,
                                ),
                                title: Text(
                                  city,
                                  style: AppTypography.bodyLarge.copyWith(
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                                onTap: () => Navigator.pop(ctx, city),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result != null) {
      onSelected(result);
    }
  }

  // ── Step 1: Agency ──

  Widget _buildAgencyStep() {
    final l10n = AppLocalizations.of(context);
    return Column(
      key: const ValueKey('step-agency'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Text(
          l10n.translate('title_agency'),
          style: AppTypography.headlineLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '$_origin → $_destination',
          style: AppTypography.bodyMedium.copyWith(color: AppColors.textSub),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (_searchingRoutes)
          Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                children: [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  SizedBox(height: AppSpacing.md),
                  Text(l10n.translate('searching_routes')),
                ],
              ),
            ),
          )
        else if (_routeError != null)
          _buildRouteError()
        else if (_routes.isEmpty)
          _buildNoRoutes()
        else ...[
          // The agency and pickup point are chosen in the shared Katisha modal
          // so this step matches the destination, date and hour steps.
          _buildLocationSelector(
            label: l10n.translate('title_agency'),
            icon: Icons.directions_bus_outlined,
            value:
                _selectedRoute?.agency.name ??
                l10n.translate('select_agency_continue'),
            onTap: _openAgencyModal,
          ),
          // Once an agency is picked, its pickup points stay on the step so the
          // choice is visible without reopening the modal.
          if (_selectedRoute != null && _selectedRoute!.stops.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _buildPickupPoints(),
          ],
        ],
      ],
    );
  }

  // Opens the agency picker in the shared Katisha modal: a bottom sheet fixed at
  // 89% of the screen height, laid out exactly like the destination picker — a
  // search field over a flat selectable list — so the two feel identical.
  Future<void> _openAgencyModal() async {
    final l10n = AppLocalizations.of(context);

    // Nothing to pick from yet: wait for the route search instead of flashing
    // an empty sheet.
    if (_searchingRoutes) {
      await _waitForRouteSearch();
      if (!mounted) return;
    }
    if (_routes.isEmpty) return;

    await showKatishaModal<void>(
      context: context,
      transitionDuration: _sheetAnimDuration,
      builder: (ctx) {
        var query = '';
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final q = query.trim().toLowerCase();
            final filtered = q.isEmpty
                ? _routes
                : _routes.where((r) {
                    final haystack =
                        '${r.agency.name} ${r.origin} ${r.destination}'
                            .toLowerCase();
                    return haystack.contains(q);
                  }).toList();

            return KatishaModal(
              title: l10n.translate('title_agency'),
              subtitle: '$_origin → $_destination',
              closeLabel: l10n.translate('close'),
              bodyScrollable: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: TextField(
                      onChanged: (v) => setSheetState(() => query = v),
                      textInputAction: TextInputAction.search,
                      style: AppTypography.bodyMedium,
                      decoration: InputDecoration(
                        hintText: l10n.translate('search_location'),
                        hintStyle: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textMuted,
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          size: 20,
                          color: AppColors.primary,
                        ),
                        isDense: true,
                        filled: true,
                        fillColor: AppColors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusSm,
                          ),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusSm,
                          ),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusSm,
                          ),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              l10n.translate('no_routes_found'),
                              style: AppTypography.bodyMedium.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.sm,
                            ),
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) => Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                              ),
                              child: const Divider(
                                height: AppSpacing.sm,
                                color: AppColors.border,
                              ),
                            ),
                            itemBuilder: (context, index) => _buildAgencyRow(
                              filtered[index],
                              ctx,
                              setSheetState,
                            ),
                          ),
                  ),
                  if (_selectedRoute != null &&
                      _selectedRoute!.stops.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _buildPickupPoints(),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  // A single agency row, styled like a destination row: circular avatar, name,
  // supporting line and the total price on the trailing edge.
  Widget _buildAgencyRow(
    dynamic route,
    BuildContext sheetCtx,
    StateSetter setSheetState,
  ) {
    final l10n = AppLocalizations.of(context);
    final isSelected = _selectedRoute?.id == route.id;
    final routePrice = route.routePrice as int;
    final total = _quoteTotal(routePrice);
    final hasPromo = route.hasPromotion == true;
    final originalPrice = (route.originalPrice as int?) ?? routePrice;
    final originalTotal = originalPrice > 0
        ? _quoteTotal(originalPrice)
        : total;
    final name = route.agency.name;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedRoute = route;
          _selectedPickupPoint = null;
        });
        _fetchAgencyWorkingHours(route.agency.id);
        // No intermediate pickup points to choose: move straight on.
        final hasPickupStops = route.stops.any(
          (s) =>
              s.name.toLowerCase() != _origin!.toLowerCase() &&
              s.name.toLowerCase() != _destination!.toLowerCase(),
        );
        if (hasPickupStops) {
          setSheetState(() {});
        } else {
          Navigator.pop(sheetCtx);
          _scheduleAutoAdvance();
        }
      },
      child: Container(
        color: isSelected ? AppColors.primaryLight : null,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : AppColors.primaryLight,
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              ),
              child: Center(
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: AppTypography.titleMedium.copyWith(
                    color: isSelected ? AppColors.white : AppColors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: AppTypography.bodyLarge.copyWith(
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasPromo) ...[
                        const SizedBox(width: 4),
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.star,
                            size: 13,
                            color: Color(0xFFF59E0B),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${route.origin} → ${route.destination}'
                    '${route.estimatedDuration != null ? ' · ${route.estimatedDuration}' : ''}',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSub,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (hasPromo) ...[
                  Text(
                    '${_formatAmount(originalTotal)} RWF',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textMuted,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  Text(
                    '${_formatAmount(total)} RWF',
                    style: AppTypography.titleSmall.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    l10n.translate('on_promotion'),
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ] else
                  Text(
                    '${_formatAmount(total)} RWF',
                    style: AppTypography.titleSmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            if (isSelected) ...[
              const SizedBox(width: AppSpacing.sm),
              const Icon(
                Icons.check_circle,
                size: 20,
                color: AppColors.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Waits for the in-flight route search so the auto-opened sheet has rows.
  Future<void> _waitForRouteSearch() async {
    final completer = Completer<void>();
    void listener() {
      if (!_searchingRoutes && !completer.isCompleted) completer.complete();
    }

    _routeSearchListeners.add(listener);
    // Re-check immediately in case the search already finished.
    listener();
    if (completer.isCompleted) {
      _routeSearchListeners.remove(listener);
      return;
    }

    await completer.future;
    _routeSearchListeners.remove(listener);
  }

  // Pickup-point chips for the selected agency.
  Widget _buildPickupPoints() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('PICKUP POINT'),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Choose your pickup point',
          style: AppTypography.bodySmall.copyWith(color: AppColors.textSub),
        ),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = (constraints.maxWidth - AppSpacing.sm) / 2;
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                ..._selectedRoute!.stops
                    .where(
                      (s) =>
                          s.name.toLowerCase() != _origin!.toLowerCase() &&
                          s.name.toLowerCase() != _destination!.toLowerCase(),
                    )
                    .map((stop) {
                      final isSelected = _selectedPickupPoint == stop.name;
                      return SizedBox(
                        width: itemWidth,
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _selectedPickupPoint = stop.name);
                            _scheduleAutoAdvance();
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primaryLight
                                  : AppColors.white,
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusMd,
                              ),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.border,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.location_on_outlined,
                                  size: 18,
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.textMuted,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    stop.name,
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
                                    Icons.check_circle,
                                    size: 18,
                                    color: AppColors.primary,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                SizedBox(
                  width: itemWidth,
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _selectedPickupPoint = 'Bus Station');
                      _scheduleAutoAdvance();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: _selectedPickupPoint == 'Bus Station'
                            ? AppColors.primaryLight
                            : AppColors.white,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                        border: Border.all(
                          color: _selectedPickupPoint == 'Bus Station'
                              ? AppColors.primary
                              : AppColors.border,
                          width: _selectedPickupPoint == 'Bus Station' ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.business,
                            size: 18,
                            color: _selectedPickupPoint == 'Bus Station'
                                ? AppColors.primary
                                : AppColors.textMuted,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              'Bus Station',
                              style: AppTypography.bodyMedium.copyWith(
                                color: _selectedPickupPoint == 'Bus Station'
                                    ? AppColors.primary
                                    : AppColors.text,
                                fontWeight:
                                    _selectedPickupPoint == 'Bus Station'
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (_selectedPickupPoint == 'Bus Station')
                            const Icon(
                              Icons.check_circle,
                              size: 18,
                              color: AppColors.primary,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildRouteError() {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            Text(
              _routeError!,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSub,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: _searchRoutes,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.translate('retry')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoRoutes() {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          children: [
            Icon(Icons.search_off, size: 64, color: AppColors.textMuted),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No routes found',
              style: AppTypography.bodyLarge.copyWith(color: AppColors.textSub),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.translate('no_routes_subtitle'),
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 2: Schedule ──

  Widget _buildScheduleStep() {
    final l10n = AppLocalizations.of(context);
    return Column(
      key: const ValueKey('step-schedule'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Text(
          l10n.translate('title_schedule'),
          style: AppTypography.headlineLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.translate('pick_date_time'),
          style: AppTypography.bodyMedium.copyWith(color: AppColors.textSub),
        ),
        const SizedBox(height: AppSpacing.xl),
        _buildLocationSelector(
          label: l10n.translate('travel_date'),
          icon: Icons.calendar_today_outlined,
          value: _datePicked
              ? '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}'
              : l10n.translate('select_travel_date'),
          onTap: _openDatePickerModal,
        ),
        const SizedBox(height: AppSpacing.lg),
        Column(
          key: _departureTimeKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLocationSelector(
              label: l10n.translate('departure_time'),
              icon: Icons.access_time,
              value: _selectedTime ?? l10n.translate('select_travel_hour'),
              onTap: _openTimePickerModal,
            ),
          ],
        ),
      ],
    );
  }

  /// Slots the selected route can actually depart on. Falls back to the
  /// half-hour grid when the route has no explicit departure times.
  List<String> _baseSlotsForAvailability() {
    final routeTimes =
        (_selectedRoute?.departureTimes ?? const <String>[])
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return routeTimes.isNotEmpty ? routeTimes : _allHalfHourSlots();
  }

  bool _hasBookableSlotToday() {
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    return _baseSlotsForAvailability().any((slot) {
      final minutes = _parseHhMm(slot);
      return minutes != null && minutes > nowMinutes;
    });
  }

  /// First date the wizard lets the user book: today while a departure still
  /// remains, otherwise tomorrow. Mirrors the website's `earliestBookableDate`.
  DateTime get _minSelectableDate {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _hasBookableSlotToday() ? today : today.add(const Duration(days: 1));
  }

  /// Month containing [_minSelectableDate]; earlier months have no bookable
  /// dates at all.
  DateTime get _minSelectableMonth {
    final min = _minSelectableDate;
    return DateTime(min.year, min.month);
  }

  // Opens the travel-date calendar in the shared Katisha modal: a centred
  // panel fixed at 89% of the screen height, same as the destination picker.
  Future<void> _openDatePickerModal() async {
    final l10n = AppLocalizations.of(context);
    // Never open on a month that has no bookable dates (late in the month the
    // 2-day notice pushes every date into the next month).
    if (_calendarMonth.isBefore(_minSelectableMonth)) {
      _calendarMonth = _minSelectableMonth;
    }
    await showKatishaModal<void>(
      context: context,
      builder: (ctx) {
        return KatishaModal(
          title: l10n.translate('travel_date'),
          closeLabel: l10n.translate('close'),
          bodyScrollable: false,
          child: _buildCalendar(
            onDatePicked: () {
              Navigator.pop(ctx);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _openTimePickerModal();
              });
            },
          ),
        );
      },
    );
  }

  // Opens the departure-time picker in the shared Katisha modal. The slot grid
  // can be taller than the panel on small screens, so the body scrolls.
  Future<void> _openTimePickerModal() async {
    final l10n = AppLocalizations.of(context);
    if (!_datePicked) {
      await _openDatePickerModal();
      return;
    }
    await showKatishaModal<void>(
      context: context,
      builder: (ctx) {
        return KatishaModal(
          title: l10n.translate('choose_available_hour'),
          closeLabel: l10n.translate('close'),
          child: _buildTimeSlots(onTimePicked: () => Navigator.pop(ctx)),
        );
      },
    );
  }

  Widget _buildCalendar({VoidCallback? onDatePicked}) {
    final l10n = AppLocalizations.of(context);
    final year = _calendarMonth.year;
    final month = _calendarMonth.month;
    final firstDay = DateTime(year, month, 1);
    final lastDay = DateTime(year, month + 1, 0);
    final startWeekday = firstDay.weekday % 7;
    final today = DateTime.now();
    final minDate = _minSelectableDate;
    final monthStart = DateTime(year, month);

    // Where the bookable part of this month starts. Everything before it is
    // not rendered at all: drawing 20+ blank cells at the top of the grid used
    // to push the few remaining dates to the bottom of the panel.
    final int firstAvailableDay;
    if (monthStart.isBefore(_minSelectableMonth)) {
      firstAvailableDay = lastDay.day + 1; // nothing bookable this month
    } else if (monthStart.isAtSameMomentAs(_minSelectableMonth)) {
      firstAvailableDay = minDate.day;
    } else {
      firstAvailableDay = 1;
    }
    final availableCount = lastDay.day - firstAvailableDay + 1;
    // Keep the weekday columns aligned even though leading days are skipped.
    final leadingBlanks = availableCount > 0
        ? (startWeekday + firstAvailableDay - 1) % 7
        : 0;
    final canGoBack = monthStart.isAfter(_minSelectableMonth);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: canGoBack
                    ? () => setState(() {
                        _calendarMonth = DateTime(year, month - 1);
                      })
                    : null,
                icon: const Icon(Icons.chevron_left, size: 20),
                color: AppColors.textSub,
                disabledColor: AppColors.textMuted.withValues(alpha: 0.35),
                tooltip: canGoBack
                    ? null
                    : l10n.translate('no_dates_available'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              Text(_monthName(month), style: AppTypography.titleMedium),
              IconButton(
                onPressed: () => setState(() {
                  _calendarMonth = DateTime(year, month + 1);
                }),
                icon: const Icon(Icons.chevron_right, size: 20),
                color: AppColors.textSub,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (availableCount <= 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Text(
                l10n.translate('no_dates_available'),
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSub,
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                // Minimal calendar: dates are plain text. Only the selected day
                // gets a filled blue circle — no outlines or borders on the
                // other cells, which kept the old grid looking like a wall of
                // buttons.
                final diameter = (constraints.maxWidth / 7 - 2).clamp(
                  32.0,
                  38.0,
                );

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisExtent: 44,
                    mainAxisSpacing: 2,
                    crossAxisSpacing: 0,
                  ),
                  itemCount: leadingBlanks + availableCount,
                  itemBuilder: (context, index) {
                    // The grid starts at the first bookable day, so the
                    // remaining dates sit at the top of the panel instead of
                    // under a block of empty rows.
                    if (index < leadingBlanks) return const SizedBox.shrink();
                    final day = firstAvailableDay + index - leadingBlanks;
                    final date = DateTime(year, month, day);
                    final isSelected =
                        date.year == _selectedDate.year &&
                        date.month == _selectedDate.month &&
                        date.day == _selectedDate.day;
                    final isToday =
                        date.year == today.year &&
                        date.month == today.month &&
                        date.day == today.day;

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setState(() {
                          _selectedDate = date;
                          _datePicked = true;
                          _selectedTime = null;
                        });
                        // Bring the departure-time selection into view after a
                        // date is picked.
                        _scrollToDepartureTime();
                        onDatePicked?.call();
                      },
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          width: diameter,
                          height: diameter,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary
                                : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$day',
                                style: AppTypography.bodyMedium.copyWith(
                                  fontSize: 14,
                                  height: 1,
                                  color: isSelected
                                      ? AppColors.white
                                      : isToday
                                      ? AppColors.primary
                                      : AppColors.text,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                              if (isToday && !isSelected)
                                Container(
                                  width: 3,
                                  height: 3,
                                  margin: const EdgeInsets.only(top: 3),
                                  decoration: const BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }

  List<String> _allHalfHourSlots() {
    final slots = <String>[];
    for (var h = 0; h < 24; h++) {
      for (var m = 0; m < 60; m += 30) {
        slots.add(
          '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}',
        );
      }
    }
    return slots;
  }

  Widget _buildTimeSlots({VoidCallback? onTimePicked}) {
    final l10n = AppLocalizations.of(context);
    // Show only the selected route's real departure times (matching the web:
    // departureTimes when configured, otherwise the 30-minute slot grid).
    final routeTimes = (_selectedRoute?.departureTimes ?? const <String>[])
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final List<String> baseSlots;
    if (routeTimes.isNotEmpty) {
      baseSlots = routeTimes.toSet().toList()..sort();
    } else {
      baseSlots = _allHalfHourSlots();
    }
    final morning = <String>[];
    final afternoon = <String>[];
    final night = <String>[];
    for (final slot in baseSlots) {
      final h = int.parse(slot.split(':')[0]);
      if (h < 12) {
        morning.add(slot);
      } else if (h < 18) {
        afternoon.add(slot);
      } else {
        night.add(slot);
      }
    }

    Widget _buildSection({required String title, required List<String> slots}) {
      final availableSlots = slots.where(_isTimeSlotAvailable).toList();
      if (availableSlots.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  title,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textSub,
                  ),
                ),
              ],
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              // Three roomy columns: the slot labels are short, so each cell
              // gets both extra width and extra height, making the buttons
              // larger and easier to tap.
              crossAxisCount: 3,
              crossAxisSpacing: AppSpacing.sm,
              mainAxisSpacing: AppSpacing.sm,
              mainAxisExtent: 64,
            ),
            itemCount: availableSlots.length,
            itemBuilder: (context, index) {
              final slot = availableSlots[index];
              final isSelected = _selectedTime == slot;
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedTime = slot);
                  _scheduleAutoAdvance();
                  onTimePicked?.call();
                },
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Text(
                    slot,
                    style: AppTypography.labelLarge.copyWith(
                      fontSize: 17,
                      color: isSelected
                          ? AppColors.white
                          : AppColors.primaryDark,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      );
    }

    return Column(
      children: [
        _buildSection(title: l10n.translate('morning'), slots: morning),
        const SizedBox(height: AppSpacing.md),
        _buildSection(title: l10n.translate('afternoon'), slots: afternoon),
        if (night.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _buildSection(title: l10n.translate('night'), slots: night),
        ],
      ],
    );
  }

  // ── Step 3: Seats ──

  Widget _buildSeatsStep() {
    final l10n = AppLocalizations.of(context);
    return Column(
      key: const ValueKey('step-seats'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Text(
          l10n.translate('title_passengers'),
          style: AppTypography.headlineLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.translate('seats_needed'),
          style: AppTypography.bodyMedium.copyWith(color: AppColors.textSub),
        ),
        const SizedBox(height: AppSpacing.xxl),
        Center(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xxl,
                  vertical: AppSpacing.lg,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildSeatButton(
                      icon: Icons.remove,
                      onPressed: _seatCount > 1
                          ? () => setState(() => _seatCount--)
                          : null,
                    ),
                    const SizedBox(width: AppSpacing.xl),
                    Text(
                      '$_seatCount',
                      style: AppTypography.headlineLarge.copyWith(
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xl),
                    _buildSeatButton(
                      icon: Icons.add,
                      onPressed: _seatCount < 10
                          ? () => setState(() => _seatCount++)
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                _seatCount == 1
                    ? l10n.translate('1_seat_selected')
                    : l10n
                          .translate('n_seats_selected')
                          .replaceAll('%d', '$_seatCount'),
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSub,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSeatButton({required IconData icon, VoidCallback? onPressed}) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: onPressed != null ? AppColors.white : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: onPressed != null
                ? AppColors.border
                : AppColors.border.withValues(alpha: 0.5),
            width: 2,
          ),
        ),
        child: Icon(
          icon,
          size: 20,
          color: onPressed != null ? AppColors.text : AppColors.textMuted,
        ),
      ),
    );
  }

  // ── Step 4: Payment ──

  /// Loads pawaPay's active countries/providers and preselects the traveller's
  /// country: their profile phone first, then the phone's region, then the
  /// server's fallback (Rwanda). Users can change the country in the sheet.
  Future<void> _loadPaymentOptions() async {
    if (_loadingPaymentOptions) return;
    if (_paymentOptions != null && _paymentCountry != null) return;

    setState(() {
      _loadingPaymentOptions = true;
      _paymentOptionsError = null;
    });

    final result = await _repo.getPaymentOptions(
      phone: ref.read(sessionProvider)?.phone,
      country: _deviceLocation?.countryIso2 ?? _deviceCountryIso2(),
    );
    if (!mounted) return;

    result.fold(
      (failure) => setState(() {
        _loadingPaymentOptions = false;
        _paymentOptionsError = failure.message;
      }),
      (options) {
        final country =
            options.countryByCode(options.detectedCountry) ??
            options.defaultCountry;
        setState(() {
          _paymentOptions = options;
          _loadingPaymentOptions = false;
          _paymentOptionsError = null;
          _paymentCountry = country;
          _paymentProvider = country != null && country.providers.isNotEmpty
              ? country.providers.first
              : null;
          _paymentMethod = _paymentProvider?.method ?? 'mom';
        });
      },
    );
  }

  /// Region part of the device locale (e.g. `en_RW` → `RW`).
  String? _deviceCountryIso2() {
    try {
      final match = RegExp(
        r'[_-]([A-Za-z]{2})$',
      ).firstMatch(Platform.localeName);
      return match?.group(1)?.toUpperCase();
    } catch (_) {
      return null;
    }
  }

  void _selectPaymentCountry(PaymentCountryOption country) {
    setState(() {
      _paymentCountryTouched = true;
      _paymentCountry = country;
      _paymentProvider = country.providers.isNotEmpty
          ? country.providers.first
          : null;
      _paymentMethod = _paymentProvider?.method ?? 'mom';
      // The old number belongs to the previous country's prefix.
      _phoneController.clear();
    });
  }

  void _selectPaymentProvider(PaymentProviderOption provider) {
    setState(() {
      _paymentProvider = provider;
      _paymentMethod = provider.method;
    });
  }

  String get _paymentCurrency =>
      _paymentProvider?.currency ?? _paymentCountry?.currency ?? 'RWF';

  /// The RWF total converted to the selected provider's currency, using the
  /// same rates the server charges with.
  int _localAmount(int amountRwf) {
    final options = _paymentOptions;
    if (options == null) return amountRwf;
    return options.convert(amountRwf, _paymentCurrency);
  }

  /// The deterministic all-in RWF price for [fareTotal], mirroring the web's
  /// `ticketQuote` (ticket + 3.5% service fee + processing fee, grossed up for
  /// the deposit fee). The payout network is always MTN, matching the web.
  int _quoteTotal(int fareTotal) {
    if (fareTotal <= 0) return 0;
    return ticketQuote(
      ticketPrice: fareTotal,
      depositMno: _paymentMethod,
      payoutMno: 'MTN',
    ).totalPrice;
  }

  Widget _buildPaymentStep() {
    final l10n = AppLocalizations.of(context);
    final effectivePrice =
        _selectedRoute?.effectivePrice ?? _selectedRoute?.price ?? 0;
    final fareTotal = effectivePrice * _seatCount;
    final onlineTotal = _quoteTotal(fareTotal);
    final currency = _paymentCurrency;
    final localTotal = _localAmount(onlineTotal);

    return Column(
      key: const ValueKey('step-payment'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              ),
              child: const Icon(
                Icons.credit_card_outlined,
                color: AppColors.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              l10n.translate('title_payment'),
              style: AppTypography.headlineLarge,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxl),

        // Amount display
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Text(
                '${_formatAmount(localTotal)} $currency',
                style: AppTypography.headlineLarge.copyWith(
                  color: AppColors.primary,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '$_seatCount ${_seatCount == 1 ? 'seat' : 'seats'}  •  ${_selectedRoute?.origin ?? ''} → ${_selectedRoute?.destination ?? ''}',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSub,
                ),
                textAlign: TextAlign.center,
              ),
              if (currency != 'RWF')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '≈ ${_formatAmount(onlineTotal)} RWF',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              if (_paymentCountry != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${_paymentCountry!.flagEmoji}  ${_paymentCountry!.name}',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textSub,
                    ),
                  ),
                ),
              if (_loadingPaymentOptions)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Checking payment options…',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              if (_paymentOptionsError != null && !_loadingPaymentOptions)
                TextButton(
                  onPressed: _loadPaymentOptions,
                  child: Text(
                    'Payment options unavailable — retry',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              const Divider(height: AppSpacing.xl),
              if (currency != 'RWF') ...[
                _buildSummaryRow(
                  '${l10n.translate('total')} (RWF)',
                  '${_formatAmount(onlineTotal)} RWF',
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              _buildSummaryRow(
                l10n.translate('total'),
                '${_formatAmount(localTotal)} $currency',
                isBold: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Opens the Pay Online modal directly. Online payment via PawaPay is the
  // only option — no payment-method selection sheet is shown ('mom' is the
  // default provider matching the web PAYMENT_METHODS order).
  Future<void> _openOnlinePaymentModal() async {
    // The sheet needs pawaPay's countries/providers to show the options first.
    await _loadPaymentOptions();
    if (!mounted) return;
    if (_paymentOptions == null) {
      setState(() {
        _submitError =
            _paymentOptionsError ??
            'Could not load the payment options. Please check your connection and try again.';
      });
      return;
    }

    setState(() {
      _paymentChannel = 'pawapay_online';
      _paymentMethod = _paymentProvider?.method ?? 'mom';
    });
    // If the user is logged in, reuse their account name instead of asking
    // again in the payment modal. Fetch this in the background so it never
    // blocks the modal from opening instantly (the name field is hidden for
    // logged-in users; only the submitted guestName needs the prefilled value).
    _prefillLoggedInName();
    if (!mounted) return;
    setState(() {});
    _showModal(_buildOnlinePaymentModal());
  }

  // Fetches and caches the logged-in user's name from the server profile and
  // pre-fills the guest-name field so it isn't asked again.
  Future<void> _prefillLoggedInName() async {
    final api = ref.read(apiClientProvider);
    if (!api.isAuthenticated) {
      _isLoggedIn = false;
      _cachedUserName = null;
      return;
    }
    _isLoggedIn = true;
    if (_cachedUserName == null || _cachedUserName!.isEmpty) {
      // The session already fetched this profile at startup; reuse it instead
      // of issuing another /auth/profile round-trip.
      final sessionName = ref.read(sessionProvider)?.name?.trim() ?? '';
      if (sessionName.isNotEmpty) _cachedUserName = sessionName;
    }
    if (_cachedUserName != null && _cachedUserName!.isNotEmpty) {
      if (_guestNameController.text.isEmpty) {
        _guestNameController.text = _cachedUserName!;
      }
      return;
    }
    try {
      final res = await api.get('/auth/profile');
      final data = ApiClient.payload(res);
      final user = data['user'] is Map<String, dynamic>
          ? data['user'] as Map<String, dynamic>
          : null;
      final name = (user?['name'] as String?)?.trim() ?? '';
      _cachedUserName = name.isEmpty ? null : name;
      if (_guestNameController.text.isEmpty && name.isNotEmpty) {
        _guestNameController.text = name;
      }
    } catch (_) {
      // If the profile fetch fails, keep whatever the user may have typed.
    }
  }

  // Hosts the Pay Online dialog in the shared Katisha modal: a centred panel
  // fixed at 89% of the screen height, matching the destination, date and hour
  // pickers.
  void _showModal(Widget child) {
    showKatishaModal<void>(
      context: context,
      transitionDuration: _sheetAnimDuration,
      builder: (_) => child,
    );
  }

  // Pay Online modal (matches web PaymentModal): pricing breakdown + phone +
  // guest name + Pay button. The Pay button sits directly under the last input
  // instead of in the sheet footer, so it travels with the form rather than
  // being stranded at the bottom of the tall panel on a long screen.
  Widget _buildOnlinePaymentModal() {
    final l10n = AppLocalizations.of(context);
    final effectivePrice =
        _selectedRoute?.effectivePrice ?? _selectedRoute?.price ?? 0;
    final fareTotal = effectivePrice * _seatCount;
    final onlineTotal = _quoteTotal(fareTotal);

    String nameError = '';
    String phoneError = '';
    int step = 0; // 0 = choose the payment option, 1 = enter the number

    return StatefulBuilder(
      builder: (context, setModalState) {
        final country = _paymentCountry;
        final provider = _paymentProvider;

        if (_paymentOptions == null || country == null) {
          return KatishaModal(
            title: l10n.translate('pay_online'),
            subtitle: l10n.translate('pay_online_desc'),
            closeLabel: l10n.translate('close'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_loadingPaymentOptions)
                    const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: AppColors.primary,
                      ),
                    )
                  else
                    const Icon(
                      Icons.wifi_off_rounded,
                      size: 32,
                      color: AppColors.textMuted,
                    ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _paymentOptionsError ?? 'Loading payment options…',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSub,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final currency = provider?.currency ?? country.currency;
        final localTotal = _localAmount(onlineTotal);
        final prefix = country.prefix.isEmpty ? '250' : country.prefix;

        void goToStep(int next) {
          setModalState(() {
            nameError = '';
            phoneError = '';
            step = next;
          });
        }

        return KatishaModal(
          title: step == 0
              ? 'Payment method'
              : l10n.translate('pay_online'),
          closeLabel: l10n.translate('close'),
          bodyScrollable: false,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.lg),
                if (step == 0) ...[
                  _buildLabel('Country'),
                  const SizedBox(height: AppSpacing.sm),
                  _buildCountrySelector(
                    country: country,
                    onTap: () => _pickPaymentCountry(context),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _buildLabel('Payment option'),
                  const SizedBox(height: AppSpacing.sm),
                  if (country.providers.isEmpty)
                    Text(
                      'No payment option available in ${country.name}.',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSub,
                      ),
                    )
                  else
                    for (final option in country.providers)
                      _buildProviderTile(
                        option,
                        selected: provider?.provider == option.provider,
                        onTap: () {
                          _selectPaymentProvider(option);
                          setModalState(() {});
                        },
                      ),
                  const SizedBox(height: AppSpacing.lg),
                  ClothButton(
                    onPressed: provider == null
                        ? null
                        : () {
                            ref.read(soundServiceProvider).vibrate();
                            goToStep(1);
                          },
                    textureStyle: ClothTextureStyle.felt,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Continue',
                          style: AppTypography.titleMedium.copyWith(
                            color: AppColors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        const Icon(
                          Icons.arrow_forward,
                          size: 16,
                          color: AppColors.white,
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  _buildSelectedPaymentOption(
                    country: country,
                    provider: provider,
                    onChange: () => goToStep(0),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (!_isLoggedIn) ...[
                    _buildLabel(l10n.translate('your_name')),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      controller: _guestNameController,
                      style: AppTypography.bodyLarge,
                      decoration: _paymentInputDecoration(
                        hint: 'Enter your full name',
                        prefixIcon: const Icon(Icons.person_outline, size: 20),
                        errorText: nameError,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  _buildLabel(l10n.translate('payment_phone_label')),
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    maxLength: 15,
                    style: AppTypography.bodyLarge,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _paymentInputDecoration(
                      // The country code is prefilled from the selected country,
                      // so the field only asks for the local number.
                      prefixText: '+$prefix ',
                      prefixStyle: AppTypography.bodyLarge.copyWith(
                        color: AppColors.textSub,
                      ),
                      prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                      errorText: phoneError,
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.translate('account_auto_created'),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  ClothButton(
                    onPressed: _isSubmitting
                        ? null
                        : () {
                            final nameOk =
                                _guestNameController.text.trim().isNotEmpty ||
                                _isLoggedIn;
                            final digits = _phoneController.text.replaceAll(
                              RegExp(r'[^0-9]'),
                              '',
                            );
                            final localDigits = digits.startsWith(prefix)
                                ? digits.substring(prefix.length)
                                : digits;
                            setModalState(() {
                              nameError = nameOk
                                  ? ''
                                  : l10n.translate('please_enter_name');
                              phoneError = localDigits.length >= 8
                                  ? ''
                                  : 'Please enter a valid payment phone number';
                            });
                            if (nameOk && localDigits.length >= 8) {
                              ref.read(soundServiceProvider).vibrate();
                              Navigator.of(context).pop();
                              _submitBooking();
                            }
                          },
                    color: AppColors.paymentAction,
                    textureStyle: ClothTextureStyle.canvas,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.white,
                            ),
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Pay ${_formatAmount(localTotal)} $currency',
                                style: AppTypography.titleMedium.copyWith(
                                  color: AppColors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (currency != 'RWF')
                                Text(
                                  '≈ ${_formatAmount(onlineTotal)} RWF',
                                  style: AppTypography.labelSmall.copyWith(
                                    color: Colors.white70,
                                  ),
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCountrySelector({
    required PaymentCountryOption country,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Row(
            children: [
              Text(country.flagEmoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      country.name,
                      style: AppTypography.labelLarge.copyWith(
                        color: AppColors.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      country.currency,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.expand_more_rounded,
                size: 20,
                color: AppColors.textSub,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProviderTile(
    PaymentProviderOption option, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final logo = option.logo;
    final fallback = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(9),
      ),
      child: const Icon(
        Icons.phone_android_rounded,
        size: 18,
        color: AppColors.primary,
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: selected ? AppColors.surfaceVariant : AppColors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color: selected ? AppColors.textMuted : AppColors.border,
                width: selected ? 1.2 : 1,
              ),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: logo == null
                      ? fallback
                      : CachedNetworkImage(
                          imageUrl: logo,
                          width: 36,
                          height: 36,
                          fit: BoxFit.contain,
                          memCacheWidth: 120,
                          placeholder: (_, _) => fallback,
                          errorWidget: (_, _, _) => fallback,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.name,
                        style: AppTypography.labelLarge.copyWith(
                          color: AppColors.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _paymentMethodLabel(option.method),
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 22,
                  color: selected ? AppColors.text : AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedPaymentOption({
    required PaymentCountryOption country,
    required PaymentProviderOption? provider,
    required VoidCallback onChange,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          Text(country.flagEmoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider?.name ?? 'Payment option',
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  country.name,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onChange,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 36),
            ),
            child: Text(
              'Change',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Changes the paying country.
  ///
  /// The country list is a plain sheet on the root navigator, while the payment
  /// modal is a full-height dialog route. Showing the sheet on top of a dialog
  /// made it appear *behind* the payment panel, so the payment modal is closed
  /// first and reopened once a country is picked (or the sheet is dismissed).
  Future<void> _pickPaymentCountry(BuildContext modalContext) async {
    if (_paymentOptions == null) return;

    Navigator.of(modalContext, rootNavigator: true).pop();
    // Let the close animation finish so the two sheets never overlap.
    await Future<void>.delayed(_sheetAnimDuration);
    if (!mounted) return;

    final selected = await _showPaymentCountrySheet();
    if (!mounted) return;

    if (selected != null) _selectPaymentCountry(selected);
    if (!mounted) return;
    // Back to the option list: the newly selected provider is highlighted.
    _showModal(_buildOnlinePaymentModal());
  }

  Future<PaymentCountryOption?> _showPaymentCountrySheet() {
    final options = _paymentOptions;
    if (options == null) return Future.value();

    return showModalBottomSheet<PaymentCountryOption>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXl),
        ),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.72,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Country',
                          style: AppTypography.titleMedium.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    // Only a dozen countries ship here, so building them all is
                    // cheap and lets the sheet size to its content instead of
                    // always occupying the full 72% height.
                    shrinkWrap: true,
                    itemCount: options.countries.length,
                    itemBuilder: (_, index) {
                      final country = options.countries[index];
                      final active = country.code == _paymentCountry?.code;
                      return ListTile(
                        leading: Text(
                          country.flagEmoji,
                          style: const TextStyle(fontSize: 22),
                        ),
                        title: Text(
                          country.name,
                          style: AppTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          country.currency,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                        trailing: active
                            ? const Icon(
                                Icons.check_circle_rounded,
                                color: AppColors.primary,
                                size: 20,
                              )
                            : null,
                        onTap: () => Navigator.pop(ctx, country),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _paymentMethodLabel(String method) {
    return switch (method) {
      'mom' => 'MTN Mobile Money',
      'airtel' => 'Airtel Money',
      'mpesa' => 'M-PESA',
      'orange' => 'Orange Money',
      'moov' => 'Moov Money',
      'vodacom' => 'Vodacom M-PESA',
      'tigo' => 'Mixx by Yas',
      'halotel' => 'Halotel',
      'zamtel' => 'Zamtel',
      'tnm' => 'TNM Mpamba',
      'vodafone' => 'Telecel Cash',
      'free' => 'Free Money',
      'wave' => 'Wave',
      _ => 'Mobile money',
    };
  }

  InputDecoration _paymentInputDecoration({
    String? hint,
    Icon? prefixIcon,
    String? prefixText,
    TextStyle? prefixStyle,
    String? errorText,
    String? counterText,
  }) {
    final hasError = errorText != null && errorText.isNotEmpty;
    OutlineInputBorder border(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      hintText: (hint == null || hint.isEmpty) ? null : hint,
      hintStyle: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
      prefixIcon: prefixIcon,
      prefixText: prefixText,
      prefixStyle: prefixStyle,
      filled: true,
      fillColor: AppColors.white,
      errorText: hasError ? errorText : null,
      errorMaxLines: 2,
      counterText: counterText,
      border: border(hasError ? AppColors.error : AppColors.border),
      enabledBorder: border(hasError ? AppColors.error : AppColors.border),
      focusedBorder: border(AppColors.primary, 2),
    );
  }

  // ── NAVIGATION ──

  Widget _buildNavigationButtons() {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 0,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              flex: 1,
              child: ClothButton(
                onPressed: _isSubmitting ? null : _goBack,
                color: AppColors.surface,
                side: const BorderSide(color: AppColors.border, width: 2),
                textureStyle: ClothTextureStyle.canvas,
                height: 48,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.arrow_back,
                      size: 14,
                      color: AppColors.text,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.translate('back'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: _currentStep > 0 ? 2 : 1,
            child: ClothButton(
              onPressed: _isSubmitting
                  ? null
                  : _currentStep == 4
                  ? () {
                      ref.read(soundServiceProvider).vibrate();
                      _openOnlinePaymentModal();
                    }
                  : _goNext,
              textureStyle: ClothTextureStyle.felt,
              height: 48,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _currentStep == 4
                              ? l10n.translate('pay_now')
                              : l10n.translate('continue_btn'),
                          style: AppTypography.buttonMedium,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        const Icon(
                          Icons.arrow_forward,
                          size: 16,
                          color: AppColors.white,
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Error banner ──

  Widget _buildErrorBanner(String message) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: 0,
        vertical: AppSpacing.xs,
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.errorBg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.errorBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySmall.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  // ── BOOKING CONFIRMED VIEW ──

  Widget _buildConfirmedView() {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.white,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ScaleTransition(
                    scale: _confirmScale,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: const BoxDecoration(
                        color: Color(0xFF16A34A),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: AppColors.white,
                        size: 40,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    l10n.translate('booking_confirmed'),
                    style: AppTypography.headlineLarge.copyWith(
                      color: const Color(0xFF16A34A),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.translate('redirecting'),
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSub,
                    ),
                  ),
                  if (_confirmedReferenceCode != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        'Ref: $_confirmedReferenceCode',
                        style: AppTypography.titleSmall.copyWith(
                          color: AppColors.primary,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                  if (_confirmedTicketImage != null &&
                      _confirmedTicketImage!.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xl),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                      child: CachedNetworkImage(
                        imageUrl: _confirmedTicketImage!,
                        height: 300,
                        width: double.infinity,
                        fit: BoxFit.fitWidth,
                        memCacheWidth:
                            (MediaQuery.of(context).size.width *
                                    MediaQuery.of(context).devicePixelRatio)
                                .round(),
                        placeholder: (_, __) => const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        errorWidget: (_, __, ___) => const Icon(
                          Icons.receipt_long,
                          size: 64,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── PAYMENT FAILED VIEW ──

  // Matches the web frontend's failed state (`PaymentStatus.tsx`): a red
  // status with the server's actual reason (if any) and a retry action. Never
  // hard-code a cause — "processing" is not the same as "insufficient funds".
  Widget _buildPaymentFailedView() {
    final l10n = AppLocalizations.of(context);
    final reason =
        (_paymentFailureReason != null && _paymentFailureReason!.isNotEmpty)
        ? _paymentFailureReason!
        : l10n.translate('payment_failed_message');

    return Scaffold(
      backgroundColor: AppColors.error,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xxl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.error_outline_rounded,
                      size: 32,
                      color: AppColors.white,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    l10n.translate('payment_failed_title'),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    reason,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.white,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    l10n.translate('no_money_deducted'),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.white.withValues(alpha: 0.9),
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Retry: white button, blue text, small radius — returns the
                  // user to the destination selection to start a fresh trip.
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _retryFromFailed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.white,
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusSm,
                          ),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        l10n.translate('retry'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // Done: behaves the same as Retry — return to destination
                  // selection to start a fresh trip.
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _retryFromFailed,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.white,
                        side: const BorderSide(
                          color: AppColors.white,
                          width: 1.5,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusSm,
                          ),
                        ),
                      ),
                      child: Text(
                        l10n.translate('done'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── PAYMENT WAITING VIEW ──

  // Matches the web frontend's payment waiting overlay (`PaymentStatus.tsx`):
  // a white full-screen centred column with the same Lottie animation, the
  // same copy and a single green "Cancel payment" CTA.
  Widget _buildPaymentWaitingView() {
    final l10n = AppLocalizations.of(context);
    final effectivePrice =
        _selectedRoute?.effectivePrice ?? _selectedRoute?.price ?? 0;
    final fareTotal = effectivePrice * _seatCount;
    final totalAmount = _quoteTotal(fareTotal);

    return Scaffold(
      backgroundColor: AppColors.white,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xxl,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Lottie payment animation
                    Lottie.asset(
                      'assets/lottie/payment.json',
                      width: 190,
                      height: 190,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: AppSpacing.sm),

                    Text(
                      l10n.translate('payment_prompt_sent'),
                      style: AppTypography.titleLarge.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xs + 2),

                    Text(
                      l10n.translate('payment_prompt_desc'),
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSub,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (_paymentSlow) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        l10n.translate('payment_still_processing'),
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textSub,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),

                    Text(
                      '${l10n.translate('ref_code')}: ${_paymentWaitingReference ?? '-'}',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textMuted,
                        fontFamily: 'monospace',
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xs),

                    Text(
                      '${l10n.translate('amount')}: '
                      '${_formatAmount(_localAmount(totalAmount))} '
                      '$_paymentCurrency'
                      '${_paymentCurrency != 'RWF' ? ' (${_formatAmount(totalAmount)} RWF)' : ''}',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textMuted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    if (_paymentError != null) ...[
                      _buildErrorBanner(_paymentError!),
                      const SizedBox(height: AppSpacing.lg),
                    ],

                    // Cloth-textured "Cancel payment" CTA
                    ClothButton(
                      onPressed: _cancellingWaiting
                          ? null
                          : _cancelFromPaymentWaiting,
                      textureStyle: ClothTextureStyle.felt,
                      height: 40,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_cancellingWaiting)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.white,
                              ),
                            )
                          else
                            const Icon(Icons.close, size: 16, color: AppColors.white),
                          const SizedBox(width: 6),
                          Text(
                            _cancellingWaiting
                                ? l10n.translate('payment_cancelling')
                                : l10n.translate('payment_cancel'),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _cancelFromPaymentWaiting() async {
    if (_cancellingWaiting) return;
    setState(() {
      _cancellingWaiting = true;
      _paymentError = null;
    });
    final bookingId = _paymentWaitingBookingId;
    if (bookingId != null && bookingId.isNotEmpty) {
      await _repo.abandonBooking(bookingId);
    }
    if (!mounted) return;
    _paymentSub?.cancel();
    _stopPaymentPolling();
    setState(() {
      _paymentWaiting = false;
      _cancellingWaiting = false;
      _paymentWaitingBookingId = null;
      _paymentWaitingReference = null;
    });
    context.go('/home');
  }

  String _formatAmount(int amount) {
    final digits = amount.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  // ── HELPERS ──

  Widget _buildLabel(String text, {TextStyle? style}) {
    return Text(
      text,
      style:
          style ??
          AppTypography.labelLarge.copyWith(
            color: AppColors.textSub,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.12,
          ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSub,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        Text(
          value,
          style: AppTypography.bodySmall.copyWith(
            color: isBold ? AppColors.primary : AppColors.text,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ],
    );
  }

  String _monthName(int month) {
    const keys = [
      '',
      'month_jan',
      'month_feb',
      'month_mar',
      'month_apr',
      'month_may',
      'month_jun',
      'month_jul',
      'month_aug',
      'month_sep',
      'month_oct',
      'month_nov',
      'month_dec',
    ];
    final l10n = AppLocalizations.of(context);
    return l10n.translate(keys[month]);
  }

  String _normalizePhone(String input) {
    final prefix = _paymentCountry?.prefix.isNotEmpty == true
        ? _paymentCountry!.prefix
        : '250';
    var digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith(prefix)) return '+$digits';
    if (digits.startsWith('0')) digits = digits.substring(1);
    return '+$prefix$digits';
  }
}
