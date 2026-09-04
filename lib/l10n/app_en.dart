/// Localized strings for English.
class AppEn {
  static const Map<String, String> strings = {
    // ── General ────────────────────────────────
    'app_name': 'Katisha',
    'loading': 'Loading...',
    'retry': 'Retry',
    'cancel': 'Cancel',
    'confirm': 'Confirm',
    'save': 'Save',
    'delete': 'Delete',
    'search': 'Search',
    'filter': 'Filter',
    'no_data': 'No data available',
    'error_generic': 'Something went wrong. Please try again.',
    'offline': 'No internet connection.',

    // ── Auth ───────────────────────────────────
    'login': 'Log In',
    'register': 'Register',
    'phone': 'Phone Number',
    'password': 'Password',
    'name': 'Full Name',
    'forgot_password': 'Forgot Password?',
    'no_account': "Don't have an account?",
    'has_account': 'Already have an account?',
    'login_subtitle': 'Sign in to book your next trip',
    'register_subtitle': 'Create an account to get started',
    'phone_hint': '+250 7XX XXX XXX',
    'password_hint': 'Enter your password',
    'name_hint': 'Enter your full name',
    'login_button': 'Sign In',
    'register_button': 'Create Account',
    'choose_language': 'Choose your language',
    'select_preferred_language': 'Select your preferred language to continue',
    'role_not_supported': 'This account role is not supported on mobile.',
    'welcome_to_katisha': 'Welcome to Katisha',
    'welcome_subtitle': 'Continue to your account or create a new one to manage your trips.',
    'create_account': 'Create Account',
    'log_in': 'Log In',
    'or': 'or',
    'continue_with_google': 'Continue with Google',
    'complete_profile': 'Complete Profile',
    'enter_phone_to_continue': 'Enter your phone number to continue using Katisha',

    // ── Home / Search ──────────────────────────
    'book_now': 'Book Now',
    'home_title': 'Book a Trip',
    'passengers': 'Passengers',
    'search_routes': 'Search Routes',
    'no_routes_found': 'No routes found for this search.',
    'select_date': 'Select travel date',

    // ── Routes ─────────────────────────────────
    'route_price': 'Price',
    'per_person': 'per person',
    'agency': 'Agency',
    'duration': 'Duration',
    'select_pickup': 'Select Pickup Point',
    'pickup_point': 'Pickup Point',

    // ── Booking ────────────────────────────────
    'seats': 'Seats',
    'passenger_details': 'Passenger Details',
    'payment': 'Payment',
    'booking_summary': 'Booking Summary',
    'total_amount': 'Total Amount',
    'system_fee': 'Service Fee',
    'booking_reference': 'Booking Reference',
    'check_your_phone': 'Check Your Phone',
    'payment_instructions': 'Complete the payment on your phone',
    'seat_available': 'Available',
    'seat_selected': 'Selected',
    'seat_taken': 'Taken',

    // ── Payment Methods ────────────────────────
    'select_payment': 'Select Payment Method',
    'enter_phone_payment': 'Phone for payment',

    // ── My Bookings ────────────────────────────
    'my_bookings': 'My Tickets',
    'make_booking': 'Make a Booking',
    'active_bookings': 'Active',
    'past_bookings': 'Past',
    'no_bookings': 'No bookings yet.',
    'track_booking': 'Track Booking',
    'reference_code': 'Reference',
    'booking_status': 'Status',
    'cancel_booking': 'Cancel Booking',
    'cancel_confirm': 'Are you sure you want to cancel this booking?',
    'cancelled_successfully': 'Booking cancelled successfully.',

    // ── Ticket ─────────────────────────────────
    'download_ticket': 'Download Ticket',
    'share_ticket': 'Share Ticket',

    // ── Agent ──────────────────────────────────
    'agent_dashboard': 'Dashboard',
    'todays_bookings': "Today's Bookings",
    'pending_tickets': 'Pending Tickets',
    'assigned_routes': 'Assigned Routes',
    'confirm_booking': 'Confirm Booking',
    'reject_booking': 'Reject Booking',
    'rejection_reason': 'Rejection Reason',
    'mark_issued': 'Mark as Issued',
    'unmark_issued': 'Remove Issued Mark',
    'issued': 'Issued',
    'all_bookings': 'All Bookings',
    'booking_requests': 'Booking Requests',
    'quick_access': 'Quick Access',

    // ── Departure Management ───────────────────
    'departure_management': 'Departure Management',
    'blocked': 'Blocked',
    'open': 'Open',
    'block_departure': 'Block Departure',
    'unblock_departure': 'Unblock Departure',
    'bookings_count': 'bookings',
    'all_routes': 'All Routes',

    // ── Pickup List ────────────────────────────
    'pickup_list': 'Pickup List',
    'download_pickup_list': 'Download Pickup List',
    'print_pickup_list': 'Print Pickup List',
    'pickup_manifest': 'Pickup Manifest',

    // ── Notifications ──────────────────────────
    'notifications': 'Notifications',
    'no_notifications': 'No notifications yet.',
    'mark_all_read': 'Mark All as Read',
    'journey_alert': 'Journey Alert',
    'journey_starts_soon': 'Your journey starts in 20 minutes',
    'snooze': 'Snooze 5 min',
    'snooze_remaining': '{count} snooze(s) remaining',
    'no_more_snoozes': 'No more snoozes available',
    'unread_notification': 'unread notification',
    'unread_notifications': 'unread notifications',
    'no_notifications_subtitle': 'Book a trip and you will see updates about your journey here.',

    // ── Profile ────────────────────────────────
    'profile': 'Profile',
    'settings': 'Settings',
    'language': 'Language',
    'logout': 'Log Out',
    'logout_confirm': 'Are you sure you want to log out?',
    'loyalty_points': 'Loyalty Points',
    'free_tickets': 'Free Tickets',
    'total_bookings': 'Total Bookings',

    // ── Errors ─────────────────────────────────
    'error_network': 'No internet connection. Please check your network.',
    'error_server': 'Server error. Please try again later.',
    'error_auth': 'Session expired. Please log in again.',
    'error_timeout': 'Request timed out. Please try again.',
    'permission_denied': 'Permission denied.',
    'notification_permission': 'Notification permission is required for journey alerts.',
    'alarm_permission': 'Alarm permission is required for journey alerts.',
    'open_settings': 'Open Settings',

    // ── Journey Type Selection ─────────────────────
    'select_journey_type': 'Please select a journey type',
    'what_kind_of_trip': 'What kind of trip?',
    'plan_your_trip': 'Plan your trip',
    'choose_journey_type_desc': 'Rwanda intercity or East African cross-border travel',
    'choose_route_and_time': 'Choose your route and departure time',
    'intercity': 'Rwanda Intercity',
    'intercity_desc': 'Travel within Rwanda — Kigali to Musanze, Huye, Rubavu, Rusizi, Nyagatare and more',
    'east_africa': 'East African Travel',
    'east_africa_desc': 'Cross-border travel to Kenya, Uganda, Tanzania and beyond',

    // ── Booking Wizard Steps ─────────────────────
    'booking_title': 'Book a Bus Ticket',
    'booking_subtitle': 'Fill in your travel details below to book your seat.',
    'step_route': 'Route',
    'step_agency': 'Agency',
    'step_schedule': 'Schedule',
    'step_passengers': 'Passengers',
    'step_payment': 'Payment',
    'title_route': 'Where are you going?',
    'title_agency': 'Select a bus agency',
    'title_schedule': 'When do you travel?',
    'title_passengers': 'Passenger details',
    'title_payment': 'Payment & confirm',
    'desc_route': 'Pick your origin and destination',
    'desc_agency': 'Choose from available bus agencies',
    'desc_schedule': 'Choose your travel date and time',
    'desc_passengers': 'Enter passenger information',
    'desc_payment': 'Review and complete your booking',

    // ── Booking Fields ───────────────────────────
    'origin': 'Origin',
    'destination': 'Destination',
    'search_location': 'Search location...',
    'select_origin': 'Select departure location',
    'select_destination': 'Select arrival location',
    'select_destination_picker': 'Select destination city',
    'dest_diff_origin': 'Destination must differ from origin',
    'travel_date': 'Travel Date',
    'departure_time': 'Departure Time',
    'num_seats': 'Number of seats',
    'select_seats': 'Select Seats',
    'seats_selected': 'selected',
    'seat': 'Seat',

    // ── Route/Agency ───────────────────────────────
    'searching_routes': 'Loading...',
    'select_agency_continue': 'Select an agency to continue',
    'no_routes_subtitle': 'Try different cities or check back later',
    'select_button': 'Select',
    'service_fee_label': 'service fee',

    // ── Schedule ───────────────────────────────────
    'pick_date_time': 'Pick a date and departure time',
    'select_travel_hour': 'select travel hour',
    'morning': 'Morning',
    'afternoon': 'Afternoon',
    'night': 'Night',

    // ── Seats ──────────────────────────────────────
    'seats_needed': 'How many seats do you need?',
    '1_seat_selected': '1 seat selected',
    'n_seats_selected': '%d seats selected',

    // ── Booking Actions ──────────────────────────
    'continue_btn': 'Continue',
    'pay_now': 'Pay Now',
    'back': 'Back',
    'booking_loading': 'Booking...',
    'change': 'Change',
    'currency': 'RWF',

    // ── Booking Status ───────────────────────────
    'booking_confirmed': 'Booking Confirmed!',
    'redirecting': 'Redirecting to your booking...',
    'keep_waiting': 'Keep Waiting',
    'check_phone': 'Check your phone',
    'check_phone_desc': 'A payment request has been sent to your phone. Please approve it to complete the booking.',
    'verify_payment': 'Verify Payment',
    'verifying': 'Verifying...',
    'view_booking': 'View Booking',
    'payment_desc': 'Choose your payment method below to complete your booking.',
    'amount': 'Amount',
    'ref_code': 'Reference Code',
    'payment_prompt_sent': 'Confirm the payment on your phone',
    'payment_prompt_desc': 'A payment prompt has been sent to your phone. Please confirm the payment there.',
    'payment_cancel': 'Cancel payment',
    'payment_cancelling': 'Cancelling...',

    // ── Booking Validation ───────────────────────
    'select_origin_error': 'Select departure location',
    'select_destination_error': 'Select arrival location',
    'select_route': 'Select a route',
    'select_pickup_point': 'Select a pickup point',
    'select_travel_date': 'Select travel date',
    'select_departure_time': 'Select departure time',
    'at_least_one_seat': 'At least 1 seat',
    'select_payment_method': 'Select payment method',
    'phone_required': 'Phone number required',
    'no_routes': 'No routes found for this selection',

    // ── Booking Payment ─────────────────────────────
    'fare': 'Fare',
    'payment_fee': 'Payment Fee',
    'total': 'Total',
    'pay_online': 'Pay Online',
    'pay_online_desc': 'Fast confirmation · Additional payment fee applies',
    'your_name': 'YOUR NAME',
    'payment_phone_label': 'PAYMENT PHONE NUMBER',
    'account_auto_created': 'Your account will be created automatically',
    'please_enter_name': 'Please enter your name',

    // ── Booking Footer ───────────────────────────
    'cancel_policy': 'Cancel up to 24h before departure. Late? Fare is forfeited.',
    'pay_methods': 'Pay with MTN MoMo, Airtel Money or M-Pesa.',
    'guide_link': 'See full Booking Guide & Cancellation Policy',
    'cancellation_not_permitted': 'Cancellations are not permitted',
    'secure_payment': 'Secure mobile money payment',
    'need_help': 'Need help? Contact support via the guide',

    // ── Booking Payment Methods ──────────────────
    'mtn_momo': 'MTN Mobile Money',
    'airtel_money': 'Airtel Money',
    'mpesa': 'M-Pesa',
    'mobile_money': 'Mobile Money',
    'phone_prefix': '+250',
    'phone_placeholder': '7XX XXX XXX',

    // ── Booking Pickup ───────────────────────────
    'pickup_timeline': 'Pickup Points Along Route',
    'choose_pickup': 'Choose your pickup point',
    'unknown_agency': 'Unknown Agency',

    // ── My Bookings (additional) ─────────────────
    'my_trips': 'My Trips',
    'manage_trips': 'View your tickets and trip history',
    'no_upcoming': 'No upcoming trips',
    'book_first': 'Book your first trip to get started',
    'book_a_trip': 'Book a Trip',
    'loading_trips': 'Loading your trips...',
    'login_to_view': 'Please log in to view your trips.',
    'show_ticket': 'Please show this ticket to the boarding officer when boarding.',
    'login_required': 'Login Required',
    'login_to_see': 'Please log in to view your trips.',

    // ── Ticket View ──────────────────────────────
    'my_ticket': 'My Ticket',
    'digital_travel_pass': 'Digital Travel Pass',
    'electronic_ticket': 'ELECTRONIC TICKET',
    'ticket_number': 'Ticket Number',
    'try_again': 'Try Again',
    'reference': 'Reference',
    'date': 'Date',
    'time': 'Time',

    // ── Free Ticket ──────────────────────────────
    'use_free_ticket': 'Use free ticket',
    'available': 'available',
    'free_booking_info': 'Your booking will be free. No payment needed.',

    // ── Payment Result ─────────────────────────────
    'insufficient_funds': 'Insufficient funds',
    'payment_failed_message': 'The payment could not be completed because there are not enough funds in your mobile money account to cover this amount.',
    'no_money_deducted': 'No money was deducted and your seat has been released.',
    'done': 'Done',
    'payment_confirmed_msg': 'Payment Confirmed!',
    'payment_failed_title': 'Payment Failed',

    // ── Calendar Months ────────────────────────────
    'month_jan': 'January',
    'month_feb': 'February',
    'month_mar': 'March',
    'month_apr': 'April',
    'month_may': 'May',
    'month_jun': 'June',
    'month_jul': 'July',
    'month_aug': 'August',
    'month_sep': 'September',
    'month_oct': 'October',
    'month_nov': 'November',
    'month_dec': 'December',

    // ── Navigation ─────────────────────────────────
    'nav_home': 'Home',
    'nav_my_tickets': 'My Tickets',
    'nav_alerts': 'Notifications',
  };
}
