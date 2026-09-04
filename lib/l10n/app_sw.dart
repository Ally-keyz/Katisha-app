/// Localized strings for Kiswahili.
///
/// Translations mirror the web `locales/sw/translation.json` where available;
/// app-specific keys are translated consistently with the same tone.
class AppSw {
  static const Map<String, String> strings = {
    // ── General ────────────────────────────────
    'app_name': 'Katisha',
    'loading': 'Inapakia...',
    'retry': 'Jaribu tena',
    'cancel': 'Ghairi',
    'confirm': 'Thibitisha',
    'save': 'Hifadhi',
    'delete': 'Futa',
    'search': 'Tafuta',
    'filter': 'Chuja',
    'no_data': 'Hakuna data iliyopatikana',
    'error_generic': 'Hitilafu imetokea. Tafadhali jaribu tena.',
    'offline': 'Hakuna muunganisho wa intaneti.',

    // ── Auth ───────────────────────────────────
    'login': 'Ingia',
    'register': 'Jisajili',
    'phone': 'Nambari ya simu',
    'password': 'Nywila',
    'name': 'Jina kamili',
    'forgot_password': 'Umesahau nywila?',
    'no_account': 'Huna akaunti?',
    'has_account': 'Tayari una akaunti?',
    'login_subtitle': 'Ingia kuhifadhi safari yako ijayo',
    'register_subtitle': 'Unda akaunti kuanza',
    'phone_hint': '+250 7XX XXX XXX',
    'password_hint': 'Weka nywila yako',
    'name_hint': 'Weka jina lako kamili',
    'login_button': 'Ingia',
    'register_button': 'Unda Akaunti',
    'choose_language': 'Chagua lugha yako',
    'select_preferred_language': 'Chagua lugha unayopendelea kuendelea',
    'role_not_supported': 'Jukumu hili la akaunti halitumiki kwenye simu.',
    'welcome_to_katisha': 'Karibu kwenye Katisha',
    'welcome_subtitle': 'Endelea kwenye akaunti yako au unda mpya kusimamia safari zako.',
    'create_account': 'Unda Akaunti',
    'log_in': 'Ingia',
    'or': 'au',
    'continue_with_google': 'Endelea na Google',
    'complete_profile': 'Kamilisha Wasifu',
    'enter_phone_to_continue': 'Weka nambari yako ya simu kuendelea kutumia Katisha',

    // ── Home / Search ──────────────────────────
    'book_now': 'Nunua Tiketi',
    'home_title': 'Nunua Tiketi ya Basi',
    'passengers': 'Abiria',
    'search_routes': 'Tafuta Njia',
    'no_routes_found': 'Hakuna njia zilizopatikana kwa utafutaji huu.',
    'select_date': 'Chagua tarehe ya safari',

    // ── Routes ─────────────────────────────────
    'route_price': 'Bei',
    'per_person': 'kwa kila mtu',
    'agency': 'Shirika',
    'duration': 'Muda',
    'select_pickup': 'Chagua Sehemu ya Kupanda',
    'pickup_point': 'Sehemu ya Kupanda',

    // ── Booking ────────────────────────────────
    'seats': 'Viti',
    'passenger_details': 'Maelezo ya Abiria',
    'payment': 'Malipo',
    'booking_summary': 'Muhtasari wa Uhifadhi',
    'total_amount': 'Jumla ya Kiasi',
    'system_fee': 'Ada ya Huduma',
    'booking_reference': 'Nambari ya Kumbukumbu',
    'check_your_phone': 'Angalia Simu Yako',
    'payment_instructions': 'Kamilisha malipo kwenye simu yako',
    'seat_available': 'Inapatikana',
    'seat_selected': 'Imechaguliwa',
    'seat_taken': 'Imechukuliwa',

    // ── Payment Methods ────────────────────────
    'select_payment': 'Chagua Njia ya Malipo',
    'enter_phone_payment': 'Nambari ya simu ya malipo',

    // ── My Bookings ────────────────────────────
    'my_bookings': 'Uhifadhi Wangu',
    'make_booking': 'Fanya Hifadhi',
    'active_bookings': 'Amilifu',
    'past_bookings': 'Zilizopita',
    'no_bookings': 'Bado hakuna uhifadhi.',
    'track_booking': 'Fuatilia Uhifadhi',
    'reference_code': 'Nambari ya Kumbukumbu',
    'booking_status': 'Hali',
    'cancel_booking': 'Ghairi Uhifadhi',
    'cancel_confirm': 'Una uhakika unataka kughairi uhifadhi huu?',
    'cancelled_successfully': 'Uhifadhi umeghairiwa kwa mafanikio.',

    // ── Ticket ─────────────────────────────────
    'download_ticket': 'Pakua Tiketi',
    'share_ticket': 'Shiriki Tiketi',

    // ── Agent ──────────────────────────────────
    'agent_dashboard': 'Dashibodi',
    'todays_bookings': 'Uhifadhi wa Leo',
    'pending_tickets': 'Tiketi Zinazosubiri',
    'assigned_routes': 'Njia Zilizopewa',
    'confirm_booking': 'Thibitisha Uhifadhi',
    'reject_booking': 'Kataa Uhifadhi',
    'rejection_reason': 'Sababu ya Kukataliwa',
    'mark_issued': 'Weka kama Imetolewa',
    'unmark_issued': 'Ondoa Alama ya Utoaji',
    'issued': 'Imetolewa',
    'all_bookings': 'Uhifadhi Wote',
    'booking_requests': 'Maombi ya Uhifadhi',
    'quick_access': 'Ufikiaji wa Haraka',

    // ── Departure Management ───────────────────
    'departure_management': 'Usimamizi wa Kuondoka',
    'blocked': 'Imefungwa',
    'open': 'Wazi',
    'block_departure': 'Funga Kuondoka',
    'unblock_departure': 'Fungua Kuondoka',
    'bookings_count': 'uhifadhi',
    'all_routes': 'Njia Zote',

    // ── Pickup List ────────────────────────────
    'pickup_list': 'Orodha ya Kuokota',
    'download_pickup_list': 'Pakua Orodha ya Kuokota',
    'print_pickup_list': 'Chapisha Orodha ya Kuokota',
    'pickup_manifest': 'Orodha ya Kuokota',

    // ── Notifications ──────────────────────────
    'notifications': 'Arifa',
    'no_notifications': 'Bado hakuna arifa.',
    'mark_all_read': 'Weka Zote Zimesomwa',
    'journey_alert': 'Arifa ya Safari',
    'journey_starts_soon': 'Safari yako inaanza baada ya dakika 20',
    'snooze': 'Lala dakika 5',
    'snooze_remaining': '{count} zimesalia za kuahirisha',
    'no_more_snoozes': 'Hakuna uwezekano zaidi wa kuahirisha',

    // ── Profile ────────────────────────────────
    'profile': 'Wasifu',
    'settings': 'Mipangilio',
    'language': 'Lugha',
    'logout': 'Toka',
    'logout_confirm': 'Una uhakika unataka kutoka?',
    'loyalty_points': 'Pointi za Uaminifu',
    'free_tickets': 'Tiketi Bure',
    'total_bookings': 'Jumla ya Uhifadhi',

    // ── Errors ─────────────────────────────────
    'error_network': 'Hakuna muunganisho wa intaneti. Tafadhali angalia mtandao wako.',
    'error_server': 'Hitilafu ya seva. Tafadhali jaribu tena baadaye.',
    'error_auth': 'Kipindi kimeisha. Tafadhali ingia tena.',
    'error_timeout': 'Ombi limepita muda. Tafadhali jaribu tena.',
    'permission_denied': 'Ruhusa imekataliwa.',
    'notification_permission': 'Ruhusa ya arifa inahitajika kwa tahadhari za safari.',
    'alarm_permission': 'Ruhusa ya kengele inahitajika kwa tahadhari za safari.',
    'open_settings': 'Fungua Mipangilio',

    // ── Booking Wizard Steps ─────────────────────
    'booking_title': 'Nunua Tiketi ya Basi',
    'booking_subtitle': 'Jaza maelezo yako ya safari hapa chini kuhifadhi nafasi yako.',
    'step_route': 'Njia',
    'step_agency': 'Shirika',
    'step_schedule': 'Ratiba',
    'step_passengers': 'Abiria',
    'step_payment': 'Malipo',
    'title_route': 'Unaenda wapi?',
    'title_agency': 'Chagua shirika la basi',
    'title_schedule': 'Unasafiri lini?',
    'title_passengers': 'Maelezo ya abiria',
    'title_payment': 'Malipo na kuthibitisha',
    'desc_route': 'Chagua mahali pa kuanzia na kwenda',
    'desc_agency': 'Chagua kati ya mashirika ya basi yanayopatikana',
    'desc_schedule': 'Chagua tarehe na muda wa safari yako',
    'desc_passengers': 'Weka maelezo ya abiria',
    'desc_payment': 'Kagua na ukamilishe uhifadhi wako',

    // ── Booking Fields ───────────────────────────
    'origin': 'Mahali pa kuanzia',
    'destination': 'Mahali pa kwenda',
    'search_location': 'Tafuta eneo...',
    'select_origin': 'Chagua mahali pa kuanzia',
    'select_destination': 'Chagua mahali pa kwenda',
    'dest_diff_origin': 'Mahali pa kwenda lazima yawe tofauti na mahali pa kuanzia',
    'travel_date': 'Tarehe ya Safari',
    'departure_time': 'Muda wa Kuondoka',
    'num_seats': 'Idadi ya viti',
    'select_seats': 'Chagua Viti',
    'seats_selected': 'zimechaguliwa',
    'seat': 'Kiti',

    // ── Booking Actions ──────────────────────────
    'continue_btn': 'Endelea',
    'pay_now': 'Lipa Sasa',
    'back': 'Rudi',
    'booking_loading': 'Inawekwa nafasi...',
    'change': 'Badilisha',
    'currency': 'RWF',

    // ── Booking Status ───────────────────────────
    'booking_confirmed': 'Uhifadhi Umehakikiwa!',
    'redirecting': 'Tunaelekeza kwenye uhifadhi wako...',
    'keep_waiting': 'Endelea Kusubiri',
    'check_phone': 'Angalia simu yako',
    'check_phone_desc': 'Ombi la malipo limetumwa kwa simu yako. Tafadhali lidhibitishe ili kukamilisha uhifadhi.',
    'verify_payment': 'Thibitisha Malipo',
    'verifying': 'Inathibitisha...',
    'view_booking': 'Tazama Uhifadhi',
    'payment_desc': 'Chagua njia yako ya malipo hapa chini kukamilisha uhifadhi wako.',
    'amount': 'Kiasi',
    'ref_code': 'Nambari ya Kumbukumbu',
    'payment_prompt_sent': 'Thibitisha malipo kwenye simu yako',
    'payment_prompt_desc': 'Ombi la malipo limetumwa kwenye simu yako. Tafadhali thibitisha malipo hapo.',
    'payment_cancel': 'Ghairi malipo',
    'payment_cancelling': 'Inaghairi...',

    // ── Booking Validation ───────────────────────
    'select_origin_error': 'Chagua mahali pa kuanzia',
    'select_destination_error': 'Chagua mahali pa kwenda',
    'select_route': 'Chagua njia',
    'select_pickup_point': 'Chagua sehemu ya kupanda',
    'select_travel_date': 'Chagua tarehe ya safari',
    'select_departure_time': 'Chagua muda wa kuondoka',
    'at_least_one_seat': 'Angalau kiti 1',
    'select_payment_method': 'Chagua njia ya malipo',
    'phone_required': 'Nambari ya simu inahitajika',
    'no_routes': 'Hakuna njia zilizopatikana kwa chaguo hili',

    // ── Booking Footer ───────────────────────────
    'cancel_policy': 'Ghairi hadi saa 24 kabla ya kuondoka. Umechelewa? Bei hupotea.',
    'pay_methods': 'Lipa kwa MTN MoMo, Airtel Money au M-Pesa.',
    'guide_link': 'Tazama Mwongozo Kamili wa Uhifadhi na Sera ya Kughairi',

    // ── Booking Payment Methods ──────────────────
    'mtn_momo': 'MTN Mobile Money',
    'airtel_money': 'Airtel Money',
    'mpesa': 'M-Pesa',
    'mobile_money': 'Mobile Money',
    'phone_prefix': '+250',
    'phone_placeholder': '7XX XXX XXX',

    // ── Booking Pickup ───────────────────────────
    'pickup_timeline': 'Sehemu za Kupanda Njiani',
    'choose_pickup': 'Chagua sehemu yako ya kupanda',
    'unknown_agency': 'Shirika Lisilojulikana',

    // ── My Bookings (additional) ─────────────────
    'my_trips': 'Safari Zangu',
    'manage_trips': 'Tazama tiketi na historia ya safari zako',
    'no_upcoming': 'Hakuna safari zinazokuja',
    'book_first': 'Hifadhi safari yako ya kwanza kuanza',
    'book_a_trip': 'Nunua Safari',
    'loading_trips': 'Inapakia safari zako...',
    'login_to_view': 'Tafadhali ingia kutazama safari zako.',
    'show_ticket': 'Tafadhali onyesha tiketi hii kwa afisa wa kuingia wakati wa kupanda.',
    'login_required': 'Kuingia Kunahitajika',
    'login_to_see': 'Tafadhali ingia kutazama safari zako.',

    // ── Ticket View ──────────────────────────────
    'my_ticket': 'Tiketi Yangu',
    'digital_travel_pass': 'Kadi ya Kielektroniki ya Usafiri',
    'electronic_ticket': 'TIKETI YA KIELEKTRONIKI',
    'ticket_number': 'Nambari ya Tiketi',
    'try_again': 'Jaribu Tena',
    'reference': 'Kumbukumbu',

    // ── Free Ticket ──────────────────────────────
    'use_free_ticket': 'Tumia tiketi bure',
    'available': 'inapatikana',
    'free_booking_info': 'Uhifadhi wako utakuwa bure. Hakuna malipo yanayohitajika.',
  };
}
