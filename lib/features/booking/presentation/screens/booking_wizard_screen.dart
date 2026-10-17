import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/socket_service.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/platform/platform_providers.dart';
import '../../../../core/platform/ticket_sync_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/city_autocomplete_field.dart' show cityOptions;
import '../../../../core/widgets/katisha_modal.dart';
import '../../data/booking_repository.dart';
import '../widgets/seat_selection_sheet.dart';
import '../../../../shared/models/route_model.dart';
import '../../../../shared/models/booking_model.dart';
import '../../../../shared/utils/service_fee.dart';
import '../../../../l10n/app_localizations.dart';

/// Step titles, cached per language code. The header is rebuilt on every
/// wizard `setState`, and this used to run five map lookups plus a fresh list
/// allocation each time just to read one element.
String? _stepLabelsLocale;
List<String>? _stepLabelsCache;

/// Katisha customer support WhatsApp group — mirrors the web
/// `WHATSAPP_GROUP` constant in `PaymentStatus.tsx`.
const String _whatsappSupportUrl =
    'https://chat.whatsapp.com/Kd41kMf8OIBFkgzaCM6vXf';

/// Visual tone for the payment result ticket-stub card (matches the web
/// `TicketCard tone="success" | "error"`).
enum _PaymentTone { success, error }

/// Paints a horizontal dashed rule — the perforated edge of the payment
/// result ticket-stub card.
class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    const dash = 4.0;
    const gap = 4.0;
    double x = 0;
    while (x < size.width) {
      final end = (x + dash).clamp(0.0, size.width).toDouble();
      canvas.drawLine(Offset(x, 0), Offset(end, 0), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

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
    List<MapEntry<String, List<String>>> groups) {
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
    'Arusha', 'Bukoba', 'Dar es Salaam', 'Dodoma', 'Iringa', 'Kabanga',
    'Kahama', 'Kigoma', 'Manyoni', 'Mbeya', 'Morogoro', 'Moshi', 'Mwanza',
    'Nzega', 'Shinyanga', 'Singida', 'Sumbawanga', 'Tabora', 'Tunduma',
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
  ConsumerState<BookingWizardScreen> createState() => _BookingWizardScreenState();
}

class _BookingWizardScreenState extends ConsumerState<BookingWizardScreen>
    with TickerProviderStateMixin {
  int _currentStep = 0;
  final _formKey = GlobalKey<FormState>();

  // Step 0: Route (East African cross-border travel only)
  String? _origin = 'Kigali';
  String? _destination;
  bool _destinationPickerAutoOpened = false;

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
  /// Live seat map selection (empty when the fallback count is used).
  List<String> _selectedSeatNumbers = [];
  String? _selectedSeatClientId;
  /// True once the interactive seat map has produced a selection.
  bool _seatMapActive = false;
  /// True once the rider has confirmed seats in the modal (map or fallback).
  bool _seatsConfirmed = false;

  // Step 4: Payment (online via PawaPay is the only option; 'mom' is the
  // default mobile-money provider recorded on the booking, matching the web's
  // PAYMENT_METHODS default)
  String _paymentMethod = 'mom';
  String? _paymentChannel; // 'pawapay_online' (only option)

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
  int? _confirmedAmount;
  String? _paymentWaitingBookingId;
  String? _paymentWaitingReference;

  /// The exact amount the customer is being asked to pay (server-quoted
  /// `pricing.customerTotal`, falling back to `totalAmount` — the same lookup
  /// the web PaymentStatus page does with `?amount=`). Null until the create
  /// response arrives.
  int? _paymentWaitingAmount;
  String? _paymentError;
  bool _cancellingWaiting = false;
  bool _paymentFailed = false;
  String? _paymentFailureReason;
  Timer? _paymentPollTimer;
  Timer? _paymentAbandonTimer;
  Timer? _postConfirmTimer;
  bool _paymentVerifyInFlight = false;
  int _paymentPollIntervalMs = _fastPollMs;
  int _paymentPollElapsedMs = 0;

  // Poll cadence mirrors the web PaymentStatus page: aggressive 1s polling for
  // the first 10 seconds (quick failures like insufficient funds resolve in
  // <10s), then a steady 2s interval.
  static const int _fastPollMs = 1000;
  static const int _slowPollMs = 2000;
  static const int _fastPollThresholdMs = 10000;

  /// Hard cap on how long the app waits for a payment before abandoning the
  /// booking — mirrors the web PaymentStatus 5-minute timeout.
  static const Duration _paymentAbandonTimeout = Duration(minutes: 5);

  late AnimationController _progressAnimController;
  late AnimationController _confirmAnimController;
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
    _progressAnimController.forward();

    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyExtraParams();
      _autoOpenDestinationPicker();
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
    _paymentAbandonTimer?.cancel();
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
    _resetSeatSelection();
    setState(() {});
  }

  // ── Validation ──

  String? _stepError() {
    switch (_currentStep) {
      case 0:
        if (_origin == null || _origin!.isEmpty) return 'Please select an origin city';
        if (_destination == null || _destination!.isEmpty) return AppLocalizations.of(context).translate('select_destination');
        if (_origin == _destination) return 'Origin and destination must be different';
        return null;
      case 1:
        if (_selectedRoute == null) return AppLocalizations.of(context).translate('select_agency_continue');
        return null;
      case 2:
        if (!_datePicked) return AppLocalizations.of(context).translate('select_travel_date');
        if (_selectedTime == null) return AppLocalizations.of(context).translate('select_departure_time');
        return null;
      case 3:
        if (!_seatsConfirmed) {
          return 'Please choose and confirm your seats.';
        }
        if (_seatMapActive && _selectedSeatNumbers.isEmpty) {
          return 'At least 1 seat is required';
        }
        if (!_seatMapActive && _seatCount < 1) {
          return 'At least 1 seat is required';
        }
        return null;
      case 4:
        if (_phoneController.text.replaceAll(RegExp(r'[^0-9]'), '').length < 9) return 'Please enter a valid phone number';
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
      final response = await ref.read(apiClientProvider).get('/agencies/public/$agencyId');
      final data = response.data;
      final agency = data is Map<String, dynamic> ? (data['agency'] as Map<String, dynamic>?) : null;
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

  List<(int, int)>? _resolveAvailabilityWindows(DateTime date) {
    if (_agencyWorkingHours.isEmpty) return null;
    final dayOfWeek = date.weekday % 7;
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

  /// Current wall-clock time as minutes since midnight.
  static int _nowMinutes() {
    final now = DateTime.now();
    return now.hour * 60 + now.minute;
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isTimeSlotAvailable(String time, [DateTime? forDate]) {
    final date = forDate ?? _selectedDate;
    final minutes = _parseHhMm(time);
    if (minutes == null) return false;
    // Past departures on the current day are never bookable (mirrors the web,
    // which disables any slot at or before the current Kigali time).
    if (_isSameDay(date, DateTime.now()) && minutes <= _nowMinutes()) {
      return false;
    }
    final windows = _resolveAvailabilityWindows(date);
    if (windows == null) return true;
    if (windows.isEmpty) return false;
    for (final w in windows) {
      if (minutes >= w.$1 && minutes < w.$2) return true;
    }
    return false;
  }

  /// The candidate departure slots for the selected route: its configured
  /// `departureTimes` when present, otherwise the 30-minute slot grid.
  List<String> _baseRouteSlots() {
    final routeTimes = (_selectedRoute?.departureTimes ?? const <String>[])
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (routeTimes.isNotEmpty) {
      return routeTimes.toSet().toList()..sort();
    }
    return _allHalfHourSlots();
  }

  /// Whether today still has at least one bookable departure ahead (mirrors the
  /// web `hasBookableTimeForDate`).
  bool _hasBookableDepartureToday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final slot in _baseRouteSlots()) {
      if (_isTimeSlotAvailable(slot, today)) return true;
    }
    return false;
  }

  /// Earliest date the user may pick: today while a departure remains, else
  /// tomorrow (mirrors the web `earliestBookableDateStr`).
  DateTime _earliestBookableDate() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _hasBookableDepartureToday()
        ? today
        : today.add(const Duration(days: 1));
  }

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
        _routes =
            routes.where((r) => r.type == 'east_africa').toList();
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
    if (_currentStep == 1 && _selectedRoute != null && _selectedRoute!.stops.any((s) =>
        s.name.toLowerCase() != _origin!.toLowerCase() &&
        s.name.toLowerCase() != _destination!.toLowerCase()) && _selectedPickupPoint == null) {
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
      // Auto-open the seat map once the passenger/seat step is reached, the
      // same way the schedule pickers open on their step.
      if (_currentStep == 3) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _openSeatModal();
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

      _resetSeatSelection();

      _paymentChannel = null;

      _phoneController.clear();
      _guestNameController.clear();
      _submitError = null;
      _bookingConfirmed = false;
      _paymentWaiting = false;
      _confirmedReferenceCode = null;
      _confirmedTicketImage = null;
      _confirmedAmount = null;
      _paymentWaitingBookingId = null;
      _paymentWaitingReference = null;
      _paymentWaitingAmount = null;
      _paymentError = null;
      _paymentFailed = false;
      _paymentFailureReason = null;
      _cancellingWaiting = false;
      _paymentPollIntervalMs = _fastPollMs;
      _paymentPollElapsedMs = 0;
      _paymentPollTimer?.cancel();
      _paymentPollTimer = null;
      _paymentAbandonTimer?.cancel();
      _paymentAbandonTimer = null;
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

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    final data = <String, dynamic>{
      'routeId': _selectedRoute!.id,
      'agencyId': _selectedRoute!.agency.id,
      'origin': _origin,
      'destination': _destination,
      'travelDate': _selectedDate.toIso8601String().substring(0, 10),
      'travelTime': _selectedTime,
      'seats': _effectiveSeatCount,
      'paymentChannel': channel,
      'paymentMethod': _paymentMethod,
      'phone': _normalizePhone(_phoneController.text),
    };

    // Live seat-map selection (locked in via the seat modal): send the exact
    // seats and the client id that owns their holds so the booking claims them.
    if (_selectedSeatNumbers.isNotEmpty) {
      data['seatNumbers'] = _selectedSeatNumbers;
      if (_selectedSeatClientId != null && _selectedSeatClientId!.isNotEmpty) {
        data['seatClientId'] = _selectedSeatClientId;
      }
    }

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
        setState(() {
          _isSubmitting = false;
          _bookingConfirmed = false;
          _paymentWaiting = false;
          _submitError = null;
          _paymentFailed = true;
          _paymentFailureReason = failure.message;
        });
      },
      (bookingData) {
        // Guest booking auto-creates an account and returns tokens,
        // matching the web frontend's register-on-purchase flow.
        final accessToken = bookingData['accessToken'] as String?;
        final refreshToken = bookingData['refreshToken'] as String?;
        if (accessToken != null && refreshToken != null) {
          ref.read(apiClientProvider).setTokens(
                accessToken: accessToken,
                refreshToken: refreshToken,
              );
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
        final bookingId = bookingObj['_id'] as String? ?? bookingObj['id'] as String? ?? '';
        final refCode = bookingObj['referenceCode'] as String? ?? bookingData['referenceCode'] as String? ?? '';
        final ticketImg = bookingObj['ticketImage'] as String? ?? bookingData['ticketImage'] as String?;
        final paymentStatus = bookingObj['paymentStatus'] as String? ?? bookingData['paymentStatus'] as String? ?? 'pending';
        final status = bookingObj['status'] as String? ?? bookingData['status'] as String? ?? 'pending';
        final rejectionReason = bookingObj['rejectionReason'] as String? ?? bookingData['rejectionReason'] as String?;

        // The exact customer total the server quoted — mirrors the web's
        // `booking.pricing?.customerTotal ?? booking.totalAmount` amount
        // lookup, so every screen shows what is actually charged.
        final pricingMap = bookingObj['pricing'] is Map
            ? bookingObj['pricing'] as Map
            : null;
        final serverAmount = ((pricingMap?['customerTotal'] ??
                    bookingObj['totalAmount'] ??
                    bookingData['totalAmount']) as num?)
                ?.toInt() ??
            _quoteTotal(effectiveFareTotal());

        // Persist the booking locally right away so it is always available
        // offline once purchased (internet is guaranteed at this moment).
        _cacheTicketLocally(bookingId, bookingObj);

        // A booking is only truly paid (and the user's ticket ready) once
        // `paymentStatus` is 'paid'. A `status` of 'confirmed' only means the
        // booking was *accepted*, not that the payment went through.
        if (paymentStatus == 'paid') {
          ref.read(soundServiceProvider).vibrate();
          _scheduleDepartureAlerts(bookingId);
          ref.read(localNotificationStoreProvider).add(
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
            _confirmedAmount = serverAmount;
          });
          _confirmAnimController.forward();
          _postConfirmTimer?.cancel();
          // Mirrors the web wizard: land on My Tickets with the ticket opened.
          _postConfirmTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) context.go('/my-bookings?ticket=$bookingId');
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
            _paymentWaitingAmount = serverAmount;
          });
          _recordFailureNotification(bookingId, refCode, rejectionReason);
        } else {
          setState(() {
            _isSubmitting = false;
            _paymentWaiting = true;
            _paymentWaitingBookingId = bookingId;
            _paymentWaitingReference = refCode;
            _paymentWaitingAmount = serverAmount;
          });
          _listenForPayment(bookingId);
          _startPaymentPolling();
          _startPaymentAbandonTimer();
        }
      },
    );
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

    ref.read(notificationServiceProvider).scheduleJourneyAlerts(
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
    final ticketImg =
        ticketImage ?? (bookingObj['ticketImage'] as String?);
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
            bookingId: dataBookingId.isNotEmpty ? dataBookingId : bookingId,
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
        // A 400 from the track endpoint is a terminal payment failure (e.g.
        // insufficient funds) — treat it like `paymentStatus: 'failed'` and go
        // straight to the failure screen instead of staying "pending". Any
        // other polling error is transient and we keep waiting.
        (failure) {
          if (failure is ServerFailure && failure.statusCode == 400) {
            _handlePaymentOutcome(
              paid: false,
              bookingId: _paymentWaitingBookingId ?? '',
              referenceCode: reference,
              reason: failure.message,
            );
          }
        },
        _handlePaymentOutcomeFromBooking,
      );
    } finally {
      _paymentVerifyInFlight = false;
    }
  }

  /// Routes a fetched [Booking] to its correct terminal state (paid or failed).
  /// A booking is only "paid" when `paymentStatus` is 'paid' — a `status` of
  /// 'confirmed' merely means it was accepted, not that the money went through.
  void _handlePaymentOutcomeFromBooking(Booking booking) {
    // trackBooking returns a PII-limited booking without _id, so fall back to
    // the id held from the original create response where needed.
    final bookingId =
        booking.id.isNotEmpty ? booking.id : (_paymentWaitingBookingId ?? '');
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
      // (or the abandon timeout) resolve it. No error is surfaced here because
      // being "pending" is a normal in-flight state, not a failure.
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
    _stopPaymentAbandonTimer();
    _paymentSub?.cancel();

    if (paid) {
      ref.read(soundServiceProvider).vibrate();
      _scheduleDepartureAlerts(bookingId);
      // Keep the (now paid) ticket fully available offline — the booking JSON
      // was cached at creation, so mark it paid and save the image while we
      // still have internet.
      if (ticketImage != null && ticketImage.isNotEmpty) {
        _cacheTicketLocally(
          bookingId,
          const <String, dynamic>{},
          ticketImage,
          const {'paymentStatus': 'paid'},
        );
      }
      ref.read(localNotificationStoreProvider).add(
            title: 'Payment Confirmed!',
            message:
                'Your booking ${referenceCode ?? ''} has been confirmed.',
            type: 'payment',
            entityId: bookingId,
          );
      setState(() {
        _paymentWaiting = false;
        _bookingConfirmed = true;
        _confirmedReferenceCode = referenceCode ?? _paymentWaitingReference;
        _confirmedTicketImage = ticketImage;
        _confirmedAmount = _paymentWaitingAmount ?? _quoteTotal(effectiveFareTotal());
      });
      _confirmAnimController.forward();
      _postConfirmTimer?.cancel();
      // Mirrors the web PaymentStatus success: a short confirmation, then
      // My Tickets with the ticket opened for download/save.
      _postConfirmTimer = Timer(const Duration(milliseconds: 1800), () {
        if (mounted) context.go('/my-bookings?ticket=$bookingId');
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
      _recordFailureNotification(bookingId, referenceCode ?? '', reason);
      setState(() {
        _paymentWaiting = false;
        _bookingConfirmed = false;
        _paymentFailed = true;
        _paymentFailureReason = reason;
        _paymentWaitingBookingId = bookingId;
        _paymentWaitingReference = referenceCode ?? _paymentWaitingReference;
      });
    }
  }

  /// Polls the booking status while the payment is being awaited, so the app
  /// reflects the real server outcome (paid or failed) that the system admin
  /// sees. Uses the public track endpoint by reference code, which reads the
  /// authoritative booking status the pawaPay webhook / sweeper updates.
  ///
  /// Cadence mirrors the web PaymentStatus page: 1s for the first 10 seconds
  /// (quick failures like insufficient funds resolve in <10s), then a steady
  /// 2s interval.
  void _startPaymentPolling() {
    _paymentPollIntervalMs = _fastPollMs;
    _paymentPollElapsedMs = 0;
    _scheduleNextPaymentPoll();
  }

  void _scheduleNextPaymentPoll() {
    _paymentPollTimer?.cancel();
    _paymentPollTimer =
        Timer(Duration(milliseconds: _paymentPollIntervalMs), () async {
      if (!mounted) return;
      await _verifyPayment();
      if (!mounted) return;
      // Keep polling only while we're still waiting on a terminal outcome.
      if (!_paymentWaiting) return;
      _paymentPollElapsedMs += _paymentPollIntervalMs;
      _paymentPollIntervalMs = _paymentPollElapsedMs >= _fastPollThresholdMs
          ? _slowPollMs
          : _fastPollMs;
      _scheduleNextPaymentPoll();
    });
  }

  void _stopPaymentPolling() {
    _paymentPollTimer?.cancel();
    _paymentPollTimer = null;
  }

  /// Hard cap on how long the waiting screen stays: never longer than
  /// [_paymentAbandonTimeout] (5 minutes, matching the web). Do one final
  /// verification and, if the payment still isn't confirmed as paid, abandon
  /// the booking (releasing the held seat) and surface the failed screen — so
  /// it never sits on "pending" forever.
  void _startPaymentAbandonTimer() {
    _paymentAbandonTimer?.cancel();
    _paymentAbandonTimer = Timer(_paymentAbandonTimeout, () async {
      final reference = _paymentWaitingReference;
      final bookingId = _paymentWaitingBookingId;
      var terminal = false;
      if (reference != null && reference.isNotEmpty) {
        final result = await _repo.trackBooking(reference);
        result.fold(
          // Same rule as the poller: 400 means the payment already failed
          // terminally (e.g. insufficient funds) — fail immediately.
          (failure) {
            if (failure is ServerFailure && failure.statusCode == 400) {
              _handlePaymentOutcome(
                paid: false,
                bookingId: bookingId ?? '',
                referenceCode: reference,
                reason: failure.message,
              );
              terminal = true;
            }
          },
          (b) {
            if (b.paymentStatus == 'paid') {
              _handlePaymentOutcome(
                paid: true,
                bookingId: b.id.isNotEmpty ? b.id : (bookingId ?? ''),
                referenceCode: b.referenceCode,
              );
              terminal = true;
            } else if (b.paymentStatus == 'failed') {
              _handlePaymentOutcome(
                paid: false,
                bookingId: b.id.isNotEmpty ? b.id : (bookingId ?? ''),
                referenceCode: b.referenceCode,
                reason: b.rejectionReason,
              );
              terminal = true;
            } else if (b.status == 'cancelled') {
              _handlePaymentOutcome(
                paid: false,
                bookingId: b.id.isNotEmpty ? b.id : (bookingId ?? ''),
                referenceCode: b.referenceCode,
                cancelled: true,
              );
              terminal = true;
            }
          },
        );
      }
      if (terminal || !mounted) return;
      // Still not paid after the timeout — abandon to release the seat and fail.
      if (bookingId != null && bookingId.isNotEmpty) {
        await _repo.abandonBooking(bookingId);
      }
      if (!mounted) return;
      _handlePaymentOutcome(
        paid: false,
        bookingId: bookingId ?? '',
        referenceCode: reference ?? '',
      );
    });
  }

  void _stopPaymentAbandonTimer() {
    _paymentAbandonTimer?.cancel();
    _paymentAbandonTimer = null;
  }

  void _recordFailureNotification(
    String bookingId,
    String referenceCode,
    String? reason,
  ) {
    final message = (reason != null && reason.isNotEmpty)
        ? 'Your payment for $referenceCode failed. $reason'
        : 'Your payment for $referenceCode failed. Please check your mobile money balance and try again.';
    ref.read(localNotificationStoreProvider).add(
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

  // ── Step icon data ──

  static const _stepIcons = [
    Icons.map_outlined,
    Icons.business_outlined,
    Icons.calendar_today_outlined,
    Icons.people_outline,
    Icons.credit_card_outlined,
  ];

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
                    const SizedBox(height: AppSpacing.sm),
                    _buildFooterInfo(),
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
              _buildStepIndicators(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicators() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final isDone = i < _currentStep;
        final isActive = i == _currentStep;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (i > 0)
              Container(
                width: 8,
                height: 2,
                color: isDone || isActive ? AppColors.primary : AppColors.border,
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.primary
                    : isDone
                        ? AppColors.primaryLight
                        : AppColors.white,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(
                  color: isActive || isDone ? AppColors.primary : AppColors.border,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  isDone
                      ? const Icon(Icons.check, size: 10, color: AppColors.primary)
                      : Icon(
                          _stepIcons[i],
                          size: 10,
                          color: isActive ? AppColors.white : AppColors.textMuted,
                        ),
                ],
              ),
            ),
          ],
        );
      }),
    );
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
              child: Container(
                height: 2,
                color: AppColors.primary,
              ),
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
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
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
            const Icon(Icons.keyboard_arrow_down, size: 20, color: AppColors.textMuted),
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
                if (!originCountry && entry.key.toLowerCase() == 'rwanda') continue;
                final cities = entry.value
                    .where((c) =>
                        c != exclude && (q.isEmpty || c.toLowerCase().contains(q)))
                    .toList();
                if (cities.isEmpty) continue;
                filteredGroups.add(MapEntry(entry.key, cities));
              }
            }
            // Flat header/city rows so the list can build lazily.
            final rows = hasGroups ? _flattenGroupedRows(filteredGroups) : const <_GroupedRow>[];

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
                          hintStyle:
                              AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
                          prefixIcon: const Icon(Icons.search,
                              size: 20, color: AppColors.primary),
                          isDense: true,
                          filled: true,
                          fillColor: AppColors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusSm),
                            borderSide:
                                const BorderSide(color: AppColors.primary),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusSm),
                            borderSide:
                                const BorderSide(color: AppColors.primary),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusSm),
                            borderSide: const BorderSide(
                                color: AppColors.primary, width: 2),
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: (hasGroups
                            ? filteredGroups.isEmpty
                            : filtered.isEmpty)
                        ? Center(
                            child: Text(
                              l10n.translate('no_locations_found'),
                              style: AppTypography.bodyMedium
                                  .copyWith(color: AppColors.textMuted),
                            ),
                          )
                        : hasGroups
                            ? ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                    vertical: AppSpacing.xs),
                                itemCount: rows.length,
                                itemBuilder: (ctx, index) {
                                  final row = rows[index];
                                  if (row.header != null) {
                                    return Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 14, 16, 4),
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
                                    vertical: AppSpacing.xs),
                                itemCount: filtered.length,
                                separatorBuilder: (_, _2) => const Divider(
                                    height: 1, indent: 16, endIndent: 16),
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
            value: _selectedRoute?.agency.name ??
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
                        '${r.agency.name} ${r.origin} ${r.destination}'.toLowerCase();
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
                        hintStyle: AppTypography.bodyMedium
                            .copyWith(color: AppColors.textMuted),
                        prefixIcon: const Icon(Icons.search,
                            size: 20, color: AppColors.primary),
                        isDense: true,
                        filled: true,
                        fillColor: AppColors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusSm),
                          borderSide:
                              const BorderSide(color: AppColors.primary),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusSm),
                          borderSide:
                              const BorderSide(color: AppColors.primary),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusSm),
                          borderSide: const BorderSide(
                              color: AppColors.primary, width: 2),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              l10n.translate('no_routes_found'),
                              style: AppTypography.bodyMedium
                                  .copyWith(color: AppColors.textMuted),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.sm),
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) => Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md),
                              child: const Divider(
                                height: AppSpacing.sm,
                                color: AppColors.border,
                              ),
                            ),
                            itemBuilder: (context, index) => _buildAgencyRow(
                                filtered[index], ctx, setSheetState),
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
    final isSelected = _selectedRoute?.id == route.id;
    final effectivePrice = route.effectivePrice ?? route.price;
    final total = _perSeatTotalFor(effectivePrice);
    final hasDiscount =
        route.effectivePrice != null && route.effectivePrice != route.price;
    final name = route.agency.name;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedRoute = route;
          _selectedPickupPoint = null;
          _resetSeatSelection();
        });
        _fetchAgencyWorkingHours(route.agency.id);
        // No intermediate pickup points to choose: move straight on.
        final hasPickupStops = route.stops.any((s) =>
            s.name.toLowerCase() != _origin!.toLowerCase() &&
            s.name.toLowerCase() != _destination!.toLowerCase());
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
            horizontal: AppSpacing.md, vertical: AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary
                    : AppColors.primaryLight,
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
                  Text(
                    name,
                    style: AppTypography.bodyLarge.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${route.origin} → ${route.destination}'
                    '${route.estimatedDuration != null ? ' · ${route.estimatedDuration}' : ''}',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSub),
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
                Text(
                  '${_formatAmount(total)} RWF',
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (hasDiscount) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${_formatAmount(route.price)} RWF',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textMuted,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(
              isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 20,
              color: isSelected ? AppColors.primary : AppColors.textMuted,
            ),
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
                    .where((s) =>
                        s.name.toLowerCase() != _origin!.toLowerCase() &&
                        s.name.toLowerCase() != _destination!.toLowerCase())
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
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusMd),
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
                              const Icon(Icons.check_circle,
                                  size: 18, color: AppColors.primary),
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
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
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
                            const Icon(Icons.check_circle,
                                size: 18, color: AppColors.primary),
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
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textSub),
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
              style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
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
              ? _formatTravelDate(_selectedDate)
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

  // Opens the travel-date calendar in the shared Katisha modal: a centred
  // panel fixed at 89% of the screen height, same as the destination picker.
  Future<void> _openDatePickerModal() async {
    final l10n = AppLocalizations.of(context);
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
          child: _buildTimeSlots(
            onTimePicked: () => Navigator.pop(ctx),
          ),
        );
      },
    );
  }

  Widget _buildCalendar({VoidCallback? onDatePicked}) {
    final year = _calendarMonth.year;
    final month = _calendarMonth.month;
    final firstDay = DateTime(year, month, 1);
    final lastDay = DateTime(year, month + 1, 0);
    // Monday-first grid, matching the web calendar ((getDay() + 6) % 7).
    final startWeekday = firstDay.weekday - 1;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final earliest = _earliestBookableDate();
    // The previous-month arrow is blocked once the displayed month is the
    // current month (mirrors the web calendar).
    final canGoPrev =
        year > today.year || (year == today.year && month > today.month);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: canGoPrev
                    ? () => setState(() {
                          _calendarMonth = DateTime(year, month - 1);
                        })
                    : null,
                icon: const Icon(Icons.chevron_left, size: 20),
                color: AppColors.textSub,
                disabledColor: AppColors.textMuted.withValues(alpha: 0.4),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              Text(
                '${_monthName(month)} $year',
                style: AppTypography.titleMedium,
              ),
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
            children: _weekdayNarrowLabels()
                .map((d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: AppSpacing.xs),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1,
            ),
            itemCount: startWeekday + lastDay.day,
            itemBuilder: (context, index) {
              if (index < startWeekday) return const SizedBox.shrink();
              final day = index - startWeekday + 1;
              final date = DateTime(year, month, day);
              final isUnavailable = date.isBefore(earliest);
              final isToday = _isSameDay(date, today);
              final isSelected = date.year == _selectedDate.year &&
                  date.month == _selectedDate.month &&
                  date.day == _selectedDate.day;

              if (isUnavailable) {
                return Center(
                  child: Text(
                    '$day',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textMuted.withValues(alpha: 0.4),
                    ),
                  ),
                );
              }

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedDate = date;
                    _datePicked = true;
                    _selectedTime = null;
                    _resetSeatSelection();
                  });
                  // Bring the departure-time selection into view after a date
                  // is picked.
                  _scrollToDepartureTime();
                  onDatePicked?.call();
                },
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary
                            : isToday
                                ? AppColors.primaryLight
                                : null,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusSm),
                      ),
                      child: Center(
                        child: Text(
                          '$day',
                          style: AppTypography.bodyMedium.copyWith(
                            color: isSelected
                                ? AppColors.white
                                : isToday
                                    ? AppColors.primary
                                    : AppColors.text,
                            fontWeight: isSelected || isToday
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
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
        slots.add('${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}');
      }
    }
    return slots;
  }

  Widget _buildTimeSlots({VoidCallback? onTimePicked}) {
    final l10n = AppLocalizations.of(context);
    // Show only the selected route's real departure times (matching the web:
    // departureTimes when configured, otherwise the 30-minute slot grid).
    final baseSlots = _baseRouteSlots();
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
      final availableSlots =
          slots.where((s) => _isTimeSlotAvailable(s)).toList();
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
                Text(title, style: AppTypography.labelMedium.copyWith(color: AppColors.textSub)),
              ],
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: AppSpacing.sm,
              mainAxisSpacing: AppSpacing.sm,
              childAspectRatio: 1.8,
            ),
            itemCount: availableSlots.length,
            itemBuilder: (context, index) {
              final slot = availableSlots[index];
              final isSelected = _selectedTime == slot;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedTime = slot;
                    _resetSeatSelection();
                  });
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
                    style: AppTypography.titleMedium.copyWith(
                      color: isSelected ? AppColors.white : AppColors.primary,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
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
    final effectivePrice =
        _selectedRoute?.effectivePrice ?? _selectedRoute?.price ?? 0;
    final total = effectivePrice * _effectiveSeatCount;
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
        const SizedBox(height: AppSpacing.xl),
        _buildLocationSelector(
          label: l10n.translate('seats'),
          icon: Icons.event_seat_outlined,
          value: _seatSelectionLabel(l10n),
          onTap: _openSeatModal,
        ),
        if (_selectedSeatNumbers.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final label in _selectedSeatNumbers)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: AppTypography.labelMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => setState(() =>
                            _selectedSeatNumbers = _selectedSeatNumbers
                                .where((l) => l != label)
                                .toList()),
                        child: const Icon(Icons.close,
                            size: 12, color: AppColors.primary),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '${l10n.translate('total')}: ${_formatAmount(total)} RWF',
            style: AppTypography.titleMedium.copyWith(color: AppColors.primary),
          ),
        ],
      ],
    );
  }

  /// Human label for the seat selector: the picked seats, their count, or a
  /// prompt to open the map.
  String _seatSelectionLabel(AppLocalizations l10n) {
    if (_seatMapActive && _selectedSeatNumbers.isNotEmpty) {
      return '${_selectedSeatNumbers.length} ${l10n.translate('seats')} — ${_selectedSeatNumbers.join(', ')}';
    }
    if (_seatMapActive) return l10n.translate('select_seats');
    return _seatCount == 1
        ? l10n.translate('1_seat_selected')
        : l10n.translate('n_seats_selected').replaceAll('%d', '$_seatCount');
  }

  /// Clears any seat choice and hold. Called whenever the departure tuple
  /// changes so a selection made for one trip is never carried to another
  /// (mirrors the web wizard's reset on departure change).
  void _resetSeatSelection() {
    _seatCount = 1;
    _selectedSeatNumbers = [];
    _selectedSeatClientId = null;
    _seatMapActive = false;
    _seatsConfirmed = false;
  }

  // Opens the interactive seat map in the shared Katisha modal. On confirm the
  // selection is stored and the wizard advances straight to payment, matching
  // the web wizard.
  Future<void> _openSeatModal() async {
    final route = _selectedRoute;
    if (route == null) return;
    final price = route.effectivePrice ?? route.price;
    final result = await showKatishaModal<SeatSelectionResult>(
      context: context,
      transitionDuration: _sheetAnimDuration,
      // Web seat modal is 98dvh on phones and 95dvh from the `sm` breakpoint
      // (640px), taller than the shared 0.89 selector-sheet factor.
      heightFactor: MediaQuery.sizeOf(context).width >= 640 ? 0.95 : 0.98,
      builder: (_) => SeatSelectionSheet(
        agencyId: route.agency.id,
        routeId: route.id,
        travelDate: _selectedDate.toIso8601String().substring(0, 10),
        travelTime: _selectedTime ?? '',
        price: price,
        currency: 'RWF',
        initialSeatNumbers: _selectedSeatNumbers,
        initialCount: _seatCount,
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _seatMapActive = result.active;
      _selectedSeatClientId = result.clientId;
      _selectedSeatNumbers = result.seatNumbers;
      _seatCount = result.count < 1 ? 1 : result.count;
      _seatsConfirmed = true;
      _submitError = null;
    });
    // Seats are confirmed (live map or fallback count); go straight to checkout
    // (payment step), matching the web wizard's handleSeatConfirm.
    if (_currentStep == 3) {
      setState(() => _currentStep = 4);
      _progressAnimController
        ..reset()
        ..forward();
      _scrollToTop();
    }
  }

  // ── Step 4: Payment ──

  Widget _buildPaymentStep() {
    final l10n = AppLocalizations.of(context);
    final onlineTotal = _quoteTotal(effectiveFareTotal());

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
        const SizedBox(height: AppSpacing.xl),

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
                '${_formatAmount(onlineTotal)} RWF',
                style: AppTypography.headlineLarge.copyWith(
                  color: AppColors.primary,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '$_effectiveSeatCount ${_effectiveSeatCount == 1 ? 'seat' : 'seats'}  •  ${_selectedRoute?.origin ?? ''} → ${_selectedRoute?.destination ?? ''}',
                style: AppTypography.bodySmall.copyWith(color: AppColors.textSub),
                textAlign: TextAlign.center,
              ),
              const Divider(height: AppSpacing.xl),
              _buildSummaryRow(l10n.translate('total'), '${_formatAmount(onlineTotal)} RWF', isBold: true),
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
    setState(() {
      _paymentChannel = 'pawapay_online';
      _paymentMethod = 'mom';
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
    final onlineTotal = _quoteTotal(effectiveFareTotal());

    String nameError = '';
    String phoneError = '';

    return StatefulBuilder(
      builder: (context, setModalState) {
        return KatishaModal(
          title: l10n.translate('pay_online'),
          subtitle: l10n.translate('pay_online_desc'),
          closeLabel: l10n.translate('close'),
          bodyScrollable: false,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Push the price card down a little from the modal header.
                const SizedBox(height: AppSpacing.md),
                // Pricing breakdown
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Column(
                    children: [
                      _buildSummaryRow(
                        l10n.translate('total'),
                        '${_formatAmount(onlineTotal)} RWF',
                        isBold: true,
                        labelSize: 15,
                        valueSize: 20,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                if (!_isLoggedIn) ...[
                  _buildLabel(l10n.translate('your_name')),
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    controller: _guestNameController,
                    style: AppTypography.bodyLarge,
                    decoration: InputDecoration(
                      hintText: 'Enter your full name',
                      hintStyle: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
                      prefixIcon: const Icon(Icons.person_outline, size: 20),
                      filled: true,
                      fillColor: AppColors.white,
                      errorText: nameError.isEmpty ? null : nameError,
                      errorMaxLines: 2,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                        borderSide: BorderSide(
                          color: nameError.isEmpty ? AppColors.border : AppColors.error,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                        borderSide: BorderSide(
                          color: nameError.isEmpty ? AppColors.border : AppColors.error,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                        borderSide: const BorderSide(color: AppColors.primary, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],

                _buildLabel(l10n.translate('payment_phone_label')),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  maxLength: 12,
                  style: AppTypography.bodyLarge,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    hintText: '07X XXX XXXX or 2507XXXXXXXX',
                    hintStyle: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
                    prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                    filled: true,
                    fillColor: AppColors.white,
                    errorText: phoneError.isEmpty ? null : phoneError,
                    errorMaxLines: 2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      borderSide: BorderSide(
                        color: phoneError.isEmpty ? AppColors.border : AppColors.error,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      borderSide: BorderSide(
                        color: phoneError.isEmpty ? AppColors.border : AppColors.error,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      borderSide: const BorderSide(color: AppColors.primary, width: 2),
                    ),
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.translate('account_auto_created'),
                  style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: AppSpacing.lg),
                // Pay button directly after the last input rather than pinned in
                // the sheet footer, so it stays next to the form on tall screens
                // and is never stranded at the bottom of the panel.
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSubmitting
                        ? null
                        : () {
                            final nameOk =
                                _guestNameController.text.trim().isNotEmpty ||
                                    _isLoggedIn;
                            final digits = _phoneController.text
                                .replaceAll(RegExp(r'[^0-9]'), '');
                            setModalState(() {
                              nameError =
                                  nameOk ? '' : l10n.translate('please_enter_name');
                              phoneError = digits.length >= 9
                                  ? ''
                                  : 'Please enter a valid payment phone number';
                            });
                            if (nameOk && digits.length >= 9) {
                              ref.read(soundServiceProvider).vibrate();
                              Navigator.of(context).pop();
                              _submitBooking();
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.white,
                      disabledBackgroundColor: AppColors.textMuted,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                      elevation: 0,
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.white,
                            ),
                          )
                        : Text(
                            'Pay ${_formatAmount(onlineTotal)} RWF',
                            style: AppTypography.titleMedium.copyWith(
                              color: AppColors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
              child: OutlinedButton.icon(
                onPressed: _isSubmitting ? null : _goBack,
                icon: const Icon(Icons.arrow_back, size: 14),
                label: Text(
                  l10n.translate('back'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.text,
                  side: const BorderSide(color: AppColors.border, width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                ),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: _currentStep > 0 ? 2 : 1,
            child: ElevatedButton(
              onPressed: _isSubmitting
                  ? null
                  : _currentStep == 4
                      ? () {
                          ref.read(soundServiceProvider).vibrate();
                          _openOnlinePaymentModal();
                        }
                      : _goNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
                disabledBackgroundColor: AppColors.textMuted,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                elevation: 0,
              ),
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
                          _currentStep == 4 ? l10n.translate('pay_now') : l10n.translate('continue_btn'),
                          style: AppTypography.buttonMedium,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        const Icon(Icons.arrow_forward, size: 16, color: AppColors.white),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Footer info ──

  Widget _buildFooterInfo() {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 0,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        children: [
          _buildContactItem(l10n),
          const SizedBox(height: 6),
          _buildFooterItem(
            Icons.phone_android,
            l10n.translate('pay_methods'),
          ),
        ],
      ),
    );
  }

  /// Contact row with the phone number emphasized (bold, blue, larger).
  Widget _buildContactItem(AppLocalizations l10n) {
    final text = l10n.translate('contact_us');
    const number = '0782005076';
    final parts = text.split(number);
    return Row(
      children: [
        const Icon(Icons.phone_rounded, size: 16, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSub,
                fontSize: 13,
              ),
              children: parts.length == 2
                  ? [
                      TextSpan(text: parts[0]),
                      TextSpan(
                        text: number,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      TextSpan(text: parts[1]),
                    ]
                  : [TextSpan(text: text)],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooterItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSub,
              fontSize: 13,
            ),
          ),
        ),
      ],
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

  // Mirrors the web `PaymentStatus.tsx` paid state: a success ticket-stub card
  // with the reference code and charged amount plus an "Opening your ticket"
  // spinner while the app redirects to the booking.
  Widget _buildConfirmedView() {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
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
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ScaleTransition(
                      scale: CurvedAnimation(
                        parent: _confirmAnimController,
                        curve: Curves.elasticOut,
                      ),
                      child: _paymentStatusCard(
                        tone: _PaymentTone.success,
                        icon: Icons.check_rounded,
                        eyebrow: l10n.translate('payment_confirmed_eyebrow'),
                        title: l10n.translate('booking_confirmed'),
                        subtitle: l10n.translate('redirecting'),
                        refLabel: l10n.translate('ref_code'),
                        amountLabel: l10n.translate('amount'),
                        referenceCode: _confirmedReferenceCode,
                        amount: _confirmedAmount,
                      ),
                    ),
                    if (_confirmedTicketImage != null &&
                        _confirmedTicketImage!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                        child: CachedNetworkImage(
                          imageUrl: _confirmedTicketImage!,
                          height: 300,
                          width: double.infinity,
                          fit: BoxFit.fitWidth,
                          memCacheWidth: (MediaQuery.of(context).size.width *
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
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          l10n.translate('opening_ticket'),
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textSub,
                          ),
                        ),
                      ],
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

  // ── PAYMENT RESULT CARD (shared by the confirmed + failed views) ──

  // Replicates the web `TicketCard` + `LedgerRow` in `PaymentStatus.tsx`: a
  // white ticket-stub card with a dashed perforated divider and a small ledger
  // listing the reference code and the charged amount.
  Widget _paymentStatusCard({
    required _PaymentTone tone,
    required IconData icon,
    required String eyebrow,
    required String title,
    required String subtitle,
    required String refLabel,
    required String amountLabel,
    String? referenceCode,
    int? amount,
  }) {
    final success = tone == _PaymentTone.success;
    final ink = success ? AppColors.success : AppColors.error;
    final fill = success ? AppColors.surfaceVariant : AppColors.errorBg;
    final line = success ? AppColors.border : AppColors.errorBorder;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg + 4,
              AppSpacing.xl,
              AppSpacing.lg + 4,
              AppSpacing.md,
            ),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: fill,
                    shape: BoxShape.circle,
                    border: Border.all(color: line),
                  ),
                  child: Icon(icon, size: 26, color: ink),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  eyebrow,
                  style: AppTypography.labelMedium.copyWith(
                    color: ink,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: AppTypography.headlineSmall.copyWith(
                    color: AppColors.text,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSub,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          _dashedDivider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg + 4,
              AppSpacing.sm,
              AppSpacing.lg + 4,
              AppSpacing.md,
            ),
            child: Column(
              children: [
                _ledgerRow(refLabel, referenceCode ?? '-'),
                if (amount != null && amount > 0) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _ledgerRow(amountLabel, '${_formatAmount(amount)} RWF'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ledgerRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(color: AppColors.textSub),
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.text,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashedDivider() {
    return SizedBox(
      height: 1,
      width: double.infinity,
      child: CustomPaint(
        painter: _DashedLinePainter(color: AppColors.border),
      ),
    );
  }

  // ── PAYMENT FAILED VIEW ──

  // Mirrors the web frontend's failed state (`PaymentStatus.tsx`): an error
  // ticket-stub card with the reason, a "What to do next" info box and two
  // actions — "Book again" (restart the wizard) and "Contact support" (open the
  // Katisha WhatsApp group). The user is told no money was deducted.
  Widget _buildPaymentFailedView() {
    final l10n = AppLocalizations.of(context);
    final reason = (_paymentFailureReason != null &&
            _paymentFailureReason!.isNotEmpty)
        ? _paymentFailureReason!
        : l10n.translate('payment_failed_message');

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xxl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _paymentStatusCard(
                    tone: _PaymentTone.error,
                    icon: Icons.error_outline_rounded,
                    eyebrow: l10n.translate('payment_failed_eyebrow'),
                    title: l10n.translate('payment_failed_title'),
                    subtitle: reason,
                    refLabel: l10n.translate('ref_code'),
                    amountLabel: l10n.translate('amount'),
                    referenceCode: _paymentWaitingReference,
                    amount: _paymentWaitingAmount,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // "What to do next" info box.
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n
                              .translate('payment_failed_next_title')
                              .toUpperCase(),
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.translate('payment_failed_next_desc'),
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.textSub,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: _retryFromFailed,
                            icon: const Icon(Icons.check, size: 16),
                            label: Text(
                              l10n.translate('book_again'),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppSpacing.radiusMd),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: OutlinedButton.icon(
                            onPressed: _contactSupport,
                            icon:
                                const Icon(Icons.chat_bubble_outline, size: 16),
                            label: Text(
                              l10n.translate('contact_support'),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.text,
                              backgroundColor: AppColors.surfaceVariant,
                              side: const BorderSide(color: AppColors.border),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppSpacing.radiusMd),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    l10n.translate('no_money_deducted'),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textMuted,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Opens the Katisha customer-support WhatsApp group, mirroring the web's
  // "Contact support" action.
  Future<void> _contactSupport() async {
    final uri = Uri.parse(_whatsappSupportUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Best-effort: ignore launch failures (e.g. no browser/WhatsApp).
    }
  }

  // ── PAYMENT WAITING VIEW ──

  // Matches the web frontend's payment waiting overlay (`PaymentStatus.tsx`):
  // a white full-screen centred column with the same Lottie animation, the
  // same copy and a single green "Cancel payment" CTA.
  Widget _buildPaymentWaitingView() {
    final l10n = AppLocalizations.of(context);
    // Prefer the server-quoted customer total (what is actually charged),
    // falling back to a local quote — mirrors the web's `?amount=` lookup.
    final totalAmount =
        _paymentWaitingAmount ?? _quoteTotal(effectiveFareTotal());

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
                    '${l10n.translate('amount')}: ${_formatAmount(totalAmount)} RWF',
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

                  // Green "Cancel payment" CTA (matches the web
                  // `--green-cta` / `--green-ink` button in `PaymentStatus.tsx`).
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed:
                          _cancellingWaiting ? null : _cancelFromPaymentWaiting,
                      icon: _cancellingWaiting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF0B3D0B),
                              ),
                            )
                          : const Icon(Icons.close, size: 16),
                      label: Text(
                        _cancellingWaiting
                            ? l10n.translate('payment_cancelling')
                            : l10n.translate('payment_cancel'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0B3D0B),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF74E24C),
                        foregroundColor: const Color(0xFF0B3D0B),
                        disabledBackgroundColor: const Color(0xFF74E24C),
                        disabledForegroundColor: const Color(0xFF0B3D0B),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
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

  /// Deposit network for the pricing quote — mirrors the web wizard's
  /// `mnoFromPaymentMethod(form.paymentMethod || 'mom')`.
  String get _depositMno =>
      mnoFromPaymentMethod(_paymentMethod).name;

  /// Seats actually being booked: the live map selection when present,
  /// otherwise the fallback stepper count. Mirrors the web
  /// `selectedSeatNumbers.length || form.seats`.
  int get _effectiveSeatCount =>
      _selectedSeatNumbers.isNotEmpty ? _selectedSeatNumbers.length : _seatCount;

  /// Total fare currently being paid (unit price × seats).
  num effectiveFareTotal() {
    final effectivePrice =
        _selectedRoute?.effectivePrice ?? _selectedRoute?.price ?? 0;
    return effectivePrice * _effectiveSeatCount;
  }

  /// Everything-included customer total for a fare — mirrors the web
  /// `ticketQuote({ticketPrice, depositMno, payoutMno: 'MTN'}).total_price`,
  /// which is exactly what the server charges (`pricing.customerTotal`).
  int _quoteTotal(num fare) {
    if (fare <= 0) return 0;
    return ticketQuote(
      ticketPrice: fare,
      depositMno: _depositMno,
      payoutMno: 'MTN',
    ).totalPrice;
  }

  /// Per-seat "everything included" price shown on agency rows — mirrors the
  /// web `perSeatTotalFor`: the all-in quote for the current seat count,
  /// divided back down to a single seat.
  int _perSeatTotalFor(num price) {
    final seats = _effectiveSeatCount > 1 ? _effectiveSeatCount : 1;
    final fare = price * seats;
    if (fare <= 0) return 0;
    return (_quoteTotal(fare) / seats).round();
  }

  // ── HELPERS ──

  Widget _buildLabel(String text, {TextStyle? style}) {
    return Text(
      text,
      style: style ??
          AppTypography.labelLarge.copyWith(
            color: AppColors.textSub,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.12,
          ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    bool isBold = false,
    double? labelSize,
    double? valueSize,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            fontSize: labelSize,
            color: AppColors.textSub,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        Text(
          value,
          style: AppTypography.bodySmall.copyWith(
            fontSize: valueSize,
            color: isBold ? AppColors.primary : AppColors.text,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ],
    );
  }

  String _monthName(int month) {
    const keys = [
      '', 'month_jan', 'month_feb', 'month_mar', 'month_apr', 'month_may', 'month_jun',
      'month_jul', 'month_aug', 'month_sep', 'month_oct', 'month_nov', 'month_dec',
    ];
    final l10n = AppLocalizations.of(context);
    return l10n.translate(keys[month]);
  }

  /// intl locale for date formatting, derived from the active app language.
  String get _dateLocale =>
      AppLocalizations.of(context).languageCode;

  /// Formats a travel date like the web does — `Mon, Mar 5, 2026` (short
  /// weekday + short month + day + year). Falls back to a fixed English pattern
  /// if the locale's date symbols aren't available.
  String _formatTravelDate(DateTime date) {
    try {
      return DateFormat.yMMMEd(_dateLocale).format(date);
    } catch (_) {
      return DateFormat('EEE, MMM d, y').format(date);
    }
  }

  /// Localized narrow weekday letters, Monday-first (matches the web grid).
  List<String> _weekdayNarrowLabels() {
    try {
      final fmt = DateFormat('EEEEE', _dateLocale);
      return List.generate(7, (i) => fmt.format(DateTime(2024, 1, 1 + i)));
    } catch (_) {
      return const ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    }
  }

  String _normalizePhone(String input) {
    var digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('250')) {
      digits = digits.substring(3);
    } else if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return '+250$digits';
  }
}
