import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lottie/lottie.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/socket_service.dart';
import '../../../../core/platform/platform_providers.dart'
    hide socketServiceProvider;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/city_autocomplete_field.dart' show cityOptions;
import '../../data/booking_repository.dart';
import '../../../../shared/models/route_model.dart';
import '../../../../shared/models/booking_model.dart';
import '../../../../shared/utils/service_fee.dart';

const _stepLabels = ['Route', 'Agency', 'Schedule', 'Passengers', 'Payment'];

/// Duration for the snappy, smooth bottom-sheet enter/exit animation.
const _sheetAnimDuration = Duration(milliseconds: 220);

/// Journey-type scoped destination lists matching the web BookingWizard.
/// Intercity shows Rwanda districts; East African travel shows cross-border cities.
const _intercityDestinations = [
  'Kigali', 'Bugesera', 'Gatsibo', 'Kayonza',
  'Kirehe', 'Ngoma', 'Nyagatare', 'Rwamagana', 'Burera', 'Gakenke',
  'Gicumbi', 'Musanze', 'Rulindo', 'Gisagara', 'Huye', 'Kamonyi',
  'Muhanga', 'Nyamagabe', 'Nyanza', 'Nyaruguru', 'Ruhango', 'Karongi',
  'Ngororero', 'Nyabihu', 'Nyamasheke', 'Rubavu', 'Rusizi', 'Rutsiro',
];

const _eastAfricaDestinations = [
  'Nairobi', 'Mombasa', 'Kisumu', 'Nakuru', 'Eldoret',
  'Kampala', 'Entebbe', 'Jinja', 'Mbarara', 'Gulu', 'Fort Portal',
  'Dodoma', 'Dar es Salaam', 'Arusha', 'Mwanza', 'Mbeya', 'Zanzibar',
  'Juba', 'Bujumbura',
];

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

  // Step 0: Route
  String? _origin;
  String? _destination;
  String? _journeyType;

  // Step 1: Agency
  List<RouteModel> _routes = [];
  bool _searchingRoutes = false;
  String? _routeError;
  RouteModel? _selectedRoute;
  String? _selectedPickupPoint;
  List<Map<String, dynamic>> _agencyWorkingHours = [];

  // Auto-advance
  Timer? _autoAdvanceTimer;

  // Step 2: Schedule
  DateTime _selectedDate = DateTime.now();
  DateTime _calendarMonth = DateTime.now();
  String? _selectedTime;
  bool _showCalendar = true;

  // Step 3: Seats
  int _seatCount = 1;

  // Step 4: Payment
  String? _paymentMethod;
  String? _paymentChannel; // 'pawapay_online' (only option)

  // Payment modal state (matches web flow: summary -> green button ->
  // Pay Online modal)
  bool _isLoggedIn = false;
  String? _cachedUserName;

  static const Color _payGreen = Color(0xFF22C55E);
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
  Timer? _paymentAbandonTimer;

  late AnimationController _progressAnimController;
  late AnimationController _confirmAnimController;
  late AnimationController _blinkController;
  final _departureTimeKey = GlobalKey();
  StreamSubscription? _paymentSub;

  BookingRepository get _repo => ref.read(_bookingRepoProvider);

  static const _allPaymentMethods = [
    {'id': 'mom', 'name': 'MTN MoMo', 'icon': Icons.phone_android, 'color': Color(0xFFFFCC00), 'routes': ['intercity']},
    {'id': 'airtel', 'name': 'Airtel Money', 'icon': Icons.phone_android, 'color': Color(0xFFE40000), 'routes': ['intercity']},
    {'id': 'mpesa', 'name': 'M-Pesa', 'icon': Icons.phone_android, 'color': Color(0xFF00A651), 'routes': ['east_africa']},
  ];

  List<Map<String, dynamic>> get _paymentMethods {
    final routeType = _selectedRoute?.type ?? 'intercity';
    return _allPaymentMethods.where((m) {
      final routes = m['routes'] as List<String>;
      return routes.contains(routeType);
    }).toList();
  }

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
    });
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
      if (_journeyType == null) {
        _journeyType = _inferJourneyType(_destination);
      }
      _origin = 'Kigali';
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
      _journeyType = _selectedRoute!.type;
      _searchRoutes();
    }
    setState(() {});
  }

  String? _inferJourneyType(String? destination) {
    if (destination == null) return null;
    if (_intercityDestinations.contains(destination)) return 'intercity';
    if (_eastAfricaDestinations.contains(destination)) return 'east_africa';
    return null;
  }

  // ── Validation ──

  String? _stepError() {
    switch (_currentStep) {
      case 0:
        if (_journeyType == null) return 'Please select a journey type';
        if (_origin == null || _origin!.isEmpty) return 'Please select an origin city';
        if (_destination == null || _destination!.isEmpty) return 'Please select a destination city';
        if (_origin == _destination) return 'Origin and destination must be different';
        return null;
      case 1:
        if (_selectedRoute == null) return 'Please select a bus agency';
        return null;
      case 2:
        if (_selectedTime == null) return 'Please select a departure time';
        return null;
      case 3:
        if (_seatCount < 1) return 'At least 1 seat is required';
        return null;
      case 4:
        if (_paymentMethod == null) return 'Please select a payment method';
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
        setState(() {
          _agencyWorkingHours = hours.cast<Map<String, dynamic>>();
        });
      }
    } catch (_) {
      setState(() => _agencyWorkingHours = []);
    }
  }

  bool _isTimeSlotAvailable(String time) {
    final now = DateTime.now();
    final isToday = _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;

    final parts0 = time.split(':');
    final slotMinutes = int.parse(parts0[0]) * 60 + int.parse(parts0[1]);

    // Intercity curfew: buses do not operate between 21:30 and 04:00.
    const intercityCurfewStart = 21 * 60 + 30; // 21:30
    const intercityCurfewEnd = 4 * 60; // 04:00
    if (_journeyType == 'intercity' &&
        (slotMinutes >= intercityCurfewStart || slotMinutes < intercityCurfewEnd)) {
      return false;
    }

    // Enforce 3-hour advance booking for today (intercity same-day).
    if (isToday) {
      final nowMinutes = now.hour * 60 + now.minute;
      const minAdvanceMinutes = 3 * 60;
      if (slotMinutes < nowMinutes + minAdvanceMinutes) return false;
    }

    if (_agencyWorkingHours.isEmpty) return true;
    final dayOfWeek = _selectedDate.weekday % 7;
    final relevantHours = _agencyWorkingHours.where((h) => h['dayOfWeek'] == dayOfWeek).toList();
    if (relevantHours.isEmpty) return false;
    final parts = time.split(':');
    final timeMinutes = int.parse(parts[0]) * 60 + int.parse(parts[1]);
    for (final h in relevantHours) {
      final startParts = (h['start'] as String).split(':');
      final endParts = (h['end'] as String).split(':');
      final startMin = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
      final endMin = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
      if (timeMinutes >= startMin && timeMinutes < endMin) return true;
    }
    return false;
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
        // Mirror the web: filter client-side by journey type so only routes
        // matching the chosen type are offered.
        _routes = _journeyType == null
            ? routes
            : routes.where((r) => r.type == _journeyType).toList();
        _searchingRoutes = false;
      }),
    );
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
      return;
    }

    if (_currentStep < 4) {
      setState(() => _currentStep++);
      _progressAnimController
        ..reset()
        ..forward();
      _scrollToTop();
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
  void _syncBlink() {
    final shouldBlink = _currentStep == 2 && _selectedTime == null;
    if (shouldBlink && !_blinkController.isAnimating) {
      _blinkController.repeat(reverse: true);
    } else if (!shouldBlink && _blinkController.isAnimating) {
      _blinkController.stop();
      _blinkController.value = 1.0;
    }
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

  /// Pull-to-refresh: reset the whole wizard back to the first journey-type
  /// selection so the user can start a fresh booking flow.
  Future<void> _refreshWizard() async {
    _autoAdvanceTimer?.cancel();
    setState(() {
      _currentStep = 0;
      _formKey.currentState?.reset();

      _journeyType = null;
      _origin = null;
      _destination = null;

      _routes = [];
      _searchingRoutes = false;
      _routeError = null;
      _selectedRoute = null;
      _selectedPickupPoint = null;
      _agencyWorkingHours = [];

      _selectedDate = DateTime.now();
      _calendarMonth = DateTime.now();
      _selectedTime = null;
      _showCalendar = true;

      _seatCount = 1;

      _paymentMethod = null;
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
      _cancellingWaiting = false;
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
    if (_paymentMethod == null) {
      setState(() {
        _submitError = 'Please select a payment method';
      });
      return;
    }
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
      'journeyType': _selectedRoute!.type,
      'origin': _origin,
      'destination': _destination,
      'travelDate': _selectedDate.toIso8601String().substring(0, 10),
      'travelTime': _selectedTime,
      'seats': _seatCount,
      'paymentChannel': channel,
      'paymentMethod': _paymentMethod,
      'phone': _normalizePhone(_phoneController.text),
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
          });
          _confirmAnimController.forward();
          Timer(const Duration(seconds: 3), () {
            if (mounted) context.go('/my-bookings');
          });
        } else if (paymentStatus == 'failed' || status == 'cancelled') {
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
    // Mirror the web frontend: poll the public track endpoint by reference
    // code, which actively verifies the pawaPay collection server-side and
    // flips the booking to paid/failed. Polling by id would only read the
    // stored status and can stay "processing" forever.
    final reference = _paymentWaitingReference;
    if (reference == null || reference.isEmpty) return;
    final result = await _repo.trackBooking(reference);
    if (!mounted) return;
    result.fold(
      // A fetch/polling error is not a payment failure — keep waiting and let
      // the next poll + abandon timeout resolve the real outcome.
      (_) {},
      _handlePaymentOutcomeFromBooking,
    );
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
    } else if (booking.paymentStatus == 'failed' ||
        booking.status == 'cancelled') {
      _handlePaymentOutcome(
        paid: false,
        bookingId: bookingId,
        referenceCode: booking.referenceCode,
        reason: booking.rejectionReason,
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
  }) {
    if (_paymentFailed || _bookingConfirmed || !mounted) return;
    _stopPaymentPolling();
    _stopPaymentAbandonTimer();
    _paymentSub?.cancel();

    if (paid) {
      ref.read(soundServiceProvider).vibrate();
      _scheduleDepartureAlerts(bookingId);
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
      });
      _confirmAnimController.forward();
      Timer(const Duration(seconds: 3), () {
        if (mounted) context.go('/my-bookings');
      });
    } else {
      _recordFailureNotification(bookingId, referenceCode ?? '', reason);
      setState(() {
        _paymentWaiting = false;
        _bookingConfirmed = false;
        _paymentFailed = true;
        _paymentFailureReason = reason;
      });
    }
  }

  /// Polls the booking status while the payment is being awaited so the app
  /// reflects the real server outcome (paid or failed), matching the web
  /// frontend which polls every few seconds instead of relying on the socket.
  void _startPaymentPolling() {
    _paymentPollTimer?.cancel();
    _paymentPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _verifyPayment();
    });
  }

  void _stopPaymentPolling() {
    _paymentPollTimer?.cancel();
    _paymentPollTimer = null;
  }

  /// Mirrors the web's PaymentStatus: after 5 minutes with no resolution, do
  /// one final verification and, if the payment is still in flight, abandon the
  /// booking (releasing the held seat) and surface the failed screen.
  void _startPaymentAbandonTimer() {
    _paymentAbandonTimer?.cancel();
    _paymentAbandonTimer = Timer(const Duration(minutes: 5), () async {
      final reference = _paymentWaitingReference;
      final bookingId = _paymentWaitingBookingId;
      var terminal = false;
      if (reference != null && reference.isNotEmpty) {
        final result = await _repo.trackBooking(reference);
        if (result.isRight()) {
          final b = result.getOrElse(() => throw StateError('unreachable'));
          if (b.paymentStatus == 'paid') {
            _handlePaymentOutcome(
              paid: true,
              bookingId: b.id.isNotEmpty ? b.id : (bookingId ?? ''),
              referenceCode: b.referenceCode,
            );
            terminal = true;
          } else if (b.paymentStatus == 'failed' ||
              b.status == 'cancelled') {
            _handlePaymentOutcome(
              paid: false,
              bookingId: b.id.isNotEmpty ? b.id : (bookingId ?? ''),
              referenceCode: b.referenceCode,
              reason: b.rejectionReason,
            );
            terminal = true;
          }
        }
      }
      if (terminal || !mounted) return;
      // Still processing after 5 minutes — abandon to release the seat.
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
    _syncBlink();
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

    if (widget.embedded) {
      return SafeArea(child: content);
    }

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(child: content),
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
                  _stepLabels[_currentStep],
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

  List<String> get _scopedDestinations =>
      _journeyType == 'east_africa' ? _eastAfricaDestinations : _intercityDestinations;

  Widget _buildRouteStep() {
    final needsType = _journeyType == null;
    return Column(
      key: const ValueKey('step-route'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Text(
          needsType ? 'What kind of trip?' : 'Plan your trip',
          style: AppTypography.headlineLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          needsType
              ? 'Rwanda intercity or East African cross-border travel'
              : 'Choose your route and departure time',
          style: AppTypography.bodyMedium.copyWith(color: AppColors.textSub),
        ),
        if (needsType) ...[
          const SizedBox(height: AppSpacing.xl),
          _buildJourneyTypeCards(),
        ] else ...[
          const SizedBox(height: AppSpacing.xl),
          _buildLabel('ORIGIN'),
          const SizedBox(height: AppSpacing.xs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 20, color: AppColors.textMuted),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Kigali',
                    style: AppTypography.bodyMedium,
                  ),
                ),
                const Icon(Icons.lock_outline, size: 16, color: AppColors.textMuted),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildLabel('DESTINATION'),
          const SizedBox(height: AppSpacing.xs),
          _buildLocationSelector(
            label: 'destination city',
            icon: Icons.location_on_outlined,
            value: _destination,
            onTap: _openDestinationPicker,
          ),
        ],
      ],
    );
  }

  /// Two blue selection cards — Rwanda Intercity vs East African Travel.
  /// Matches the web BookingWizard journey-type picker styling.
  Widget _buildJourneyTypeCards() {
    return Column(
      children: [
        _buildJourneyTypeCard(
          icon: Icons.directions_bus,
          title: 'Rwanda Intercity',
          description:
              'Travel within Rwanda — Kigali to Musanze, Huye, Rubavu, Rusizi, Nyagatare and more',
          onTap: () => _selectJourneyType('intercity'),
        ),
        const SizedBox(height: AppSpacing.md),
        _buildJourneyTypeCard(
          icon: Icons.public,
          title: 'East African Travel',
          description:
              'Cross-border travel to Kenya, Uganda, Tanzania and beyond',
          onTap: () => _selectJourneyType('east_africa'),
        ),
      ],
    );
  }

  Widget _buildJourneyTypeCard({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.primaryDark],
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.primary, width: 2),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Icon(icon, size: 22, color: AppColors.white),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.titleMedium.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectJourneyType(String type) {
    ref.read(soundServiceProvider).vibrate();
    setState(() {
      _journeyType = type;
      _origin = 'Kigali';
      _destination = null;
    });
    // Automatically open the destination picker now that the journey type is chosen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openDestinationPicker();
    });
  }

  void _openDestinationPicker() {
    _showLocationPicker(
      title: 'Select destination city',
      currentValue: _destination,
      exclude: _origin,
      options: _scopedDestinations,
      onSelected: (v) {
        setState(() => _destination = v);
        _scheduleAutoAdvance();
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
    required String title,
    required ValueChanged<String> onSelected,
    String? exclude,
    String? currentValue,
    List<String>? options,
  }) async {
    final base = options ?? cityOptions;
    final filtered = exclude != null
        ? base.where((c) => c != exclude).toList()
        : List<String>.from(base);

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.85,
          expand: false,
          builder: (ctx, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Text(
                    title,
                    style: AppTypography.headlineMedium,
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _2) => const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (ctx, index) {
                      final city = filtered[index];
                      final isSelected = city == currentValue;
                      return ListTile(
                        dense: true,
                        selected: isSelected,
                        selectedTileColor: AppColors.primaryLight,
                        leading: Icon(
                          isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: isSelected ? AppColors.primary : AppColors.textMuted,
                          size: 20,
                        ),
                        title: Text(
                          city,
                          style: AppTypography.bodyLarge.copyWith(
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                        onTap: () => Navigator.pop(ctx, city),
                      );
                    },
                  ),
                ),
              ],
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
    return Column(
      key: const ValueKey('step-agency'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Select a bus agency',
          style: AppTypography.headlineLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '$_origin → $_destination',
          style: AppTypography.bodyMedium.copyWith(color: AppColors.textSub),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (_searchingRoutes)
          const Center(
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
                  Text('Searching available routes...'),
                ],
              ),
            ),
          )
        else if (_routeError != null)
          _buildRouteError()
        else if (_routes.isEmpty)
          _buildNoRoutes()
        else ...[
          if (_selectedRoute == null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                'Select an agency to continue',
                style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
                textAlign: TextAlign.center,
              ),
            ),
          _buildRouteList(),
          // Pickup points section
          if (_selectedRoute != null && _selectedRoute!.stops.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
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
                              color: isSelected ? AppColors.primaryLight : AppColors.white,
                              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                              border: Border.all(
                                color: isSelected ? AppColors.primary : AppColors.border,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.location_on_outlined,
                                  size: 18,
                                  color: isSelected ? AppColors.primary : AppColors.textMuted,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    stop.name,
                                    style: AppTypography.bodyMedium.copyWith(
                                      color: isSelected ? AppColors.primary : AppColors.text,
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Icons.check_circle, size: 18, color: AppColors.primary),
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
                                    fontWeight: _selectedPickupPoint == 'Bus Station'
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                              if (_selectedPickupPoint == 'Bus Station')
                                const Icon(Icons.check_circle, size: 18, color: AppColors.primary),
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
        ],
      ],
    );
  }

  Widget _buildRouteError() {
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
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoRoutes() {
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
              'Try different cities or check back later',
              style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteList() {
    return Column(
      children: _routes.map((route) {
        final isSelected = _selectedRoute?.id == route.id;
        final effectivePrice = route.effectivePrice ?? route.price;
        final serviceFee = systemFeeFor(route.type, effectivePrice, 1).round();

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedRoute = route;
                _selectedPickupPoint = null;
                _paymentMethod = null;
              });
              _fetchAgencyWorkingHours(route.agency.id);
              // If no stops to pick from, auto-advance
              final hasPickupStops = route.stops.any((s) =>
                  s.name.toLowerCase() != _origin!.toLowerCase() &&
                  s.name.toLowerCase() != _destination!.toLowerCase());
              if (!hasPickupStops) {
                _scheduleAutoAdvance();
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isSelected ? null : AppColors.white,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.border,
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.white.withValues(alpha: 0.2)
                              : AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                        ),
                        child: Center(
                          child: Text(
                            route.agency.name.isNotEmpty
                                ? route.agency.name[0].toUpperCase()
                                : '?',
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
                              route.agency.name,
                              style: AppTypography.titleSmall.copyWith(
                                color: isSelected ? AppColors.white : AppColors.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${route.origin} → ${route.destination}',
                              style: AppTypography.bodySmall.copyWith(
                                color: isSelected
                                    ? AppColors.white.withValues(alpha: 0.8)
                                    : AppColors.textSub,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Text(
                        '$effectivePrice RWF',
                        style: AppTypography.titleLarge.copyWith(
                          color: isSelected ? AppColors.white : AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (route.effectivePrice != null &&
                          route.effectivePrice != route.price) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          '${route.price} RWF',
                          style: AppTypography.bodySmall.copyWith(
                            color: isSelected
                                ? AppColors.white.withValues(alpha: 0.6)
                                : AppColors.textMuted,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (isSelected && route.estimatedDuration != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 14,
                              color: AppColors.white.withValues(alpha: 0.8),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              route.estimatedDuration!,
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        )
                      else if (!isSelected)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Select',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '+$serviceFee RWF service fee',
                    style: AppTypography.bodySmall.copyWith(
                      color: isSelected
                          ? AppColors.white.withValues(alpha: 0.85)
                          : AppColors.textSub,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Step 2: Schedule ──

  Widget _buildScheduleStep() {
    return Column(
      key: const ValueKey('step-schedule'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Text(
          'When do you travel?',
          style: AppTypography.headlineLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Pick a date and departure time',
          style: AppTypography.bodyMedium.copyWith(color: AppColors.textSub),
        ),
        const SizedBox(height: AppSpacing.xl),
        _buildLabel('TRAVEL DATE'),
        const SizedBox(height: AppSpacing.sm),
        if (_showCalendar)
          _buildCalendar()
        else
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: GestureDetector(
              onTap: () => setState(() => _showCalendar = true),
              child: Row(
                children: [
                  Text(
                    '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(Icons.edit, size: 14, color: AppColors.primary),
                ],
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.xl),
        Column(
          key: _departureTimeKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLabel('DEPARTURE TIME'),
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AnimatedBuilder(
                animation: _blinkController,
                builder: (context, _) {
                  final t = Curves.easeInOut.transform(_blinkController.value);
                  final color = Color.lerp(AppColors.primary, AppColors.textMuted, t)!;
                  return Text(
                    'select travel hour',
                    style: AppTypography.bodySmall.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  );
                },
              ),
            ),
            _buildTimeSlots(),
          ],
        ),
      ],
    );
  }

  Widget _buildCalendar() {
    final year = _calendarMonth.year;
    final month = _calendarMonth.month;
    final firstDay = DateTime(year, month, 1);
    final lastDay = DateTime(year, month + 1, 0);
    final startWeekday = firstDay.weekday % 7;
    final today = DateTime.now();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => setState(() {
                  _calendarMonth = DateTime(year, month - 1);
                }),
                icon: const Icon(Icons.chevron_left, size: 20),
                color: AppColors.textSub,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              Text(
                _monthName(month),
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
            children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
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
              // East African travel requires at least 2 days advance booking.
              final advanceDays = _journeyType == 'east_africa' ? 2 : 0;
              final minDate = DateTime(
                today.year, today.month, today.day + advanceDays);
              final isUnavailable = date.isBefore(minDate);
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
                    _selectedTime = null;
                    _showCalendar = false;
                  });
                  // Bring the departure-time selection into view after a date
                  // is picked.
                  _scrollToDepartureTime();
                },
                child: Center(
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary : null,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Center(
                      child: Text(
                        '$day',
                        style: AppTypography.bodyMedium.copyWith(
                          color: isSelected ? AppColors.white : AppColors.text,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w400,
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

  Widget _buildTimeSlots() {
    final morning = <String>[];
    final afternoon = <String>[];
    final night = <String>[];
    for (var h = 0; h < 24; h++) {
      for (var m = 0; m < 60; m += 30) {
        final slot = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
        if (h < 12) {
          morning.add(slot);
        } else if (h < 18) {
          afternoon.add(slot);
        } else {
          night.add(slot);
        }
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
              childAspectRatio: 2.5,
            ),
            itemCount: availableSlots.length,
            itemBuilder: (context, index) {
              final slot = availableSlots[index];
              final isSelected = _selectedTime == slot;
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedTime = slot);
                  _scheduleAutoAdvance();
                },
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : AppColors.white,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.border,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Text(
                    slot,
                    style: AppTypography.bodyMedium.copyWith(
                      color: isSelected ? AppColors.white : AppColors.text,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
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
        _buildSection(title: 'Morning', slots: morning),
        const SizedBox(height: AppSpacing.md),
        _buildSection(title: 'Afternoon', slots: afternoon),
        if (night.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _buildSection(title: 'Night', slots: night),
        ],
      ],
    );
  }

  // ── Step 3: Seats ──

  Widget _buildSeatsStep() {
    return Column(
      key: const ValueKey('step-seats'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Passenger details',
          style: AppTypography.headlineLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'How many seats do you need?',
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
                _seatCount == 1 ? '1 seat selected' : '$_seatCount seats selected',
                style: AppTypography.bodyMedium.copyWith(color: AppColors.textSub),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSeatButton({
    required IconData icon,
    VoidCallback? onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: onPressed != null ? AppColors.white : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: onPressed != null ? AppColors.border : AppColors.border.withValues(alpha: 0.5),
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

  Widget _buildPaymentStep() {
    final effectivePrice = _selectedRoute?.effectivePrice ?? _selectedRoute?.price ?? 0;
    final fareTotal = effectivePrice * _seatCount;
    final journeyType = _selectedRoute?.type;
    final serviceFee = systemFeeFor(journeyType, effectivePrice, _seatCount).round();
    final totalAmount = fareTotal + serviceFee;
    final onlineFee = pawapayFee(totalAmount, fareTotal);
    final onlineTotal = totalAmount + onlineFee;
    final isOnline = _paymentChannel == 'pawapay_online';
    final displayTotal = isOnline ? onlineTotal : totalAmount;

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
              'Payment & confirm',
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
                '$displayTotal RWF',
                style: AppTypography.headlineLarge.copyWith(
                  color: AppColors.primary,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '$_seatCount ${_seatCount == 1 ? 'seat' : 'seats'}  •  ${_selectedRoute?.origin ?? ''} → ${_selectedRoute?.destination ?? ''}',
                style: AppTypography.bodySmall.copyWith(color: AppColors.textSub),
                textAlign: TextAlign.center,
              ),
              const Divider(height: AppSpacing.xl),
              _buildSummaryRow('Fare', '$fareTotal RWF'),
              const SizedBox(height: AppSpacing.xs),
              _buildSummaryRow('Service Fee', '+$serviceFee RWF'),
              if (isOnline) ...[
                const SizedBox(height: AppSpacing.xs),
                _buildSummaryRow('Payment Fee', '+$onlineFee RWF'),
              ],
              const SizedBox(height: AppSpacing.xs),
              _buildSummaryRow('Total', '$displayTotal RWF', isBold: true),
            ],
          ),
        ),
      ],
    );
  }

  // Opens the Pay Online modal directly. The card channel (PawaPay online) is
  // the only payment option, so no payment-method selection sheet is shown.
  Future<void> _openOnlinePaymentModal() async {
    setState(() {
      _paymentChannel = 'pawapay_online';
      if (_paymentMethod == null ||
          !_paymentMethods.any((m) => m['id'] == _paymentMethod)) {
        _paymentMethod =
            _paymentMethods.isNotEmpty ? _paymentMethods.first['id'] as String : null;
      }
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

  void _showModal(Widget child) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: AppColors.white,
      sheetAnimationStyle: const AnimationStyle(
        duration: _sheetAnimDuration,
        reverseDuration: _sheetAnimDuration,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => child,
    );
  }

  // Pay Online modal (matches web PaymentModal): payment method + phone +
  // guest name + green Pay button.
  Widget _buildOnlinePaymentModal() {
    final effectivePrice = _selectedRoute?.effectivePrice ?? _selectedRoute?.price ?? 0;
    final fareTotal = effectivePrice * _seatCount;
    final serviceFee = systemFeeFor(_selectedRoute?.type, effectivePrice, _seatCount).round();
    final totalAmount = fareTotal + serviceFee;
    final onlineFee = pawapayFee(totalAmount, fareTotal);
    final onlineTotal = totalAmount + onlineFee;

    String nameError = '';
    String phoneError = '';

    return StatefulBuilder(
      builder: (context, setModalState) {
        return Container(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pay Online',
                    style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Fast confirmation · Additional payment fee applies',
                    style: AppTypography.bodySmall.copyWith(color: AppColors.textSub),
                  ),
                  const SizedBox(height: AppSpacing.lg),

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
                        _buildSummaryRow('Fare', '$fareTotal RWF'),
                        const SizedBox(height: AppSpacing.xs),
                        _buildSummaryRow('Service Fee', '+$serviceFee RWF'),
                        const SizedBox(height: AppSpacing.xs),
                        _buildSummaryRow('Payment Fee', '+$onlineFee RWF'),
                        const Divider(height: AppSpacing.md),
                        _buildSummaryRow('Total', '$onlineTotal RWF', isBold: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  if (!_isLoggedIn) ...[
                    _buildLabel('YOUR NAME'),
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

                  _buildLabel('PAYMENT PHONE NUMBER'),
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
                    'Your account will be created automatically',
                    style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: AppSpacing.lg),

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
                                    nameOk ? '' : 'Please enter your name';
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
                        backgroundColor: _payGreen,
                        foregroundColor: AppColors.white,
                        disabledBackgroundColor: AppColors.textMuted,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
                        elevation: 0,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white),
                            )
                          : Text(
                              'Pay ${onlineTotal} RWF',
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
          ),
        );
      },
    );
  }

  // ── NAVIGATION ──

  Widget _buildNavigationButtons() {
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
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('Back'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.text,
                  side: const BorderSide(color: AppColors.border, width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
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
                backgroundColor: _currentStep == 4 ? _payGreen : AppColors.primary,
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
                          _currentStep == 4 ? 'Pay Now' : 'Continue',
                          style: AppTypography.buttonSmall,
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
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 0,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        children: [
          _buildFooterItem(
            Icons.block,
            'Cancellations are not permitted',
          ),
          const SizedBox(height: 6),
          _buildFooterItem(
            Icons.phone_android,
            'Secure mobile money payment',
          ),
          const SizedBox(height: 6),
          _buildFooterItem(
            Icons.info_outline,
            'Need help? Contact support via the guide',
          ),
        ],
      ),
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

  Widget _buildConfirmedView() {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ScaleTransition(
                  scale: CurvedAnimation(
                    parent: _confirmAnimController,
                    curve: Curves.elasticOut,
                  ),
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
                  'Booking Confirmed!',
                  style: AppTypography.headlineLarge.copyWith(
                    color: const Color(0xFF16A34A),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Redirecting to your booking...',
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
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
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
    );
  }

  // ── PAYMENT FAILED VIEW ──

  // Matches the web frontend's failed state (`PaymentStatus.tsx`): a red
  // status with a clear reason and a retry action. The user is told the
  // payment failed (mostly due to insufficient funds) and shown how to retry.
  Widget _buildPaymentFailedView() {
    final reason = (_paymentFailureReason != null &&
            _paymentFailureReason!.isNotEmpty)
        ? _paymentFailureReason!
        : 'The payment could not be completed because there are not enough '
            'funds in your mobile money account to cover this amount.';

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
                  const Text(
                    'Booking failed',
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
                    'No money was deducted and your seat has been released.',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.white.withValues(alpha: 0.9),
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Retry: blue button, small radius, white text — returns the
                  // user to the destination selection to start a fresh trip.
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _retryFromFailed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Retry',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // Done: go home
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => context.go('/home'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.white,
                        side: const BorderSide(
                          color: AppColors.white,
                          width: 1.5,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                        ),
                      ),
                      child: const Text(
                        'Done',
                        style: TextStyle(
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
    final effectivePrice =
        _selectedRoute?.effectivePrice ?? _selectedRoute?.price ?? 0;
    final fareTotal = effectivePrice * _seatCount;
    final serviceFee =
        systemFeeFor(_selectedRoute?.type, effectivePrice, _seatCount).round();
    final totalAmount = fareTotal + serviceFee;

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
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
                    'Confirm the payment on your phone',
                    style: AppTypography.titleLarge.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs + 2),

                  Text(
                    'A payment prompt has been sent to your phone. '
                    'Please confirm the payment there.',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSub,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  Text(
                    'Reference Code: ${_paymentWaitingReference ?? '-'}',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textMuted,
                      fontFamily: 'monospace',
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),

                  Text(
                    'Amount: ${_formatAmount(totalAmount)} RWF',
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

                  // Green "Cancel payment" CTA
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: _cancellingWaiting ? null : _cancelFromPaymentWaiting,
                      icon: _cancellingWaiting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _waitGreenInk,
                              ),
                            )
                          : const Icon(Icons.close, size: 16),
                      label: Text(
                        _cancellingWaiting ? 'Cancelling...' : 'Cancel payment',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _waitGreenInk,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _waitGreenCta,
                        foregroundColor: _waitGreenInk,
                        disabledBackgroundColor: _waitGreenCta,
                        disabledForegroundColor: _waitGreenInk,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
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

  static const Color _waitGreenCta = Color(0xFF74E24C);
  static const Color _waitGreenInk = Color(0xFF0B3D0B);

  // ── HELPERS ──

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: AppTypography.labelLarge.copyWith(
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
    const names = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return names[month];
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
