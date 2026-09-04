/// Localized strings for Français.
///
/// Translations mirror the web `locales/fr/translation.json` where available;
/// app-specific keys are translated consistently with the same tone.
class AppFr {
  static const Map<String, String> strings = {
    // ── General ────────────────────────────────
    'app_name': 'Katisha',
    'loading': 'Chargement...',
    'retry': 'Réessayer',
    'cancel': 'Annuler',
    'confirm': 'Confirmer',
    'save': 'Enregistrer',
    'delete': 'Supprimer',
    'search': 'Rechercher',
    'filter': 'Filtrer',
    'no_data': 'Aucune donnée disponible',
    'error_generic': 'Une erreur est survenue. Veuillez réessayer.',
    'offline': 'Aucune connexion internet.',

    // ── Auth ───────────────────────────────────
    'login': 'Se connecter',
    'register': "S'inscrire",
    'phone': 'Numéro de téléphone',
    'password': 'Mot de passe',
    'name': 'Nom complet',
    'forgot_password': 'Mot de passe oublié?',
    'no_account': "Vous n'avez pas de compte?",
    'has_account': 'Vous avez déjà un compte?',
    'login_subtitle': 'Connectez-vous pour réserver votre prochain voyage',
    'register_subtitle': 'Créez un compte pour commencer',
    'phone_hint': '+250 7XX XXX XXX',
    'password_hint': 'Entrez votre mot de passe',
    'name_hint': 'Entrez votre nom complet',
    'login_button': 'Se connecter',
    'register_button': 'Créer un compte',
    'choose_language': 'Choisissez votre langue',
    'select_preferred_language': 'Sélectionnez votre langue préférée pour continuer',
    'role_not_supported': "Ce rôle de compte n'est pas pris en charge sur mobile.",
    'welcome_to_katisha': 'Bienvenue sur Katisha',
    'welcome_subtitle': 'Accédez à votre compte ou créez-en un nouveau pour gérer vos voyages.',
    'create_account': 'Créer un compte',
    'log_in': 'Se connecter',
    'or': 'ou',
    'continue_with_google': 'Continuer avec Google',
    'complete_profile': 'Compléter le profil',
    'enter_phone_to_continue': 'Entrez votre numéro de téléphone pour continuer à utiliser Katisha',

    // ── Home / Search ──────────────────────────
    'book_now': 'Réserver',
    'home_title': 'Réserver un voyage',
    'passengers': 'Passagers',
    'search_routes': 'Rechercher des itinéraires',
    'no_routes_found': 'Aucun itinéraire trouvé pour cette recherche.',
    'select_date': 'Sélectionnez la date de voyage',

    // ── Routes ─────────────────────────────────
    'route_price': 'Prix',
    'per_person': 'par personne',
    'agency': 'Agence',
    'duration': 'Durée',
    'select_pickup': 'Sélectionnez le point de ramassage',
    'pickup_point': 'Point de ramassage',

    // ── Booking ────────────────────────────────
    'seats': 'Places',
    'passenger_details': 'Détails du passager',
    'payment': 'Paiement',
    'booking_summary': 'Résumé de la réservation',
    'total_amount': 'Montant total',
    'system_fee': 'Frais de service',
    'booking_reference': 'Référence de réservation',
    'view_ticket': 'Voir le billet',
    'check_your_phone': 'Vérifiez votre téléphone',
    'payment_instructions': 'Effectuez le paiement sur votre téléphone',
    'seat_available': 'Disponible',
    'seat_selected': 'Sélectionné',
    'seat_taken': 'Pris',

    // ── Payment Methods ────────────────────────
    'select_payment': 'Sélectionnez le mode de paiement',
    'enter_phone_payment': 'Téléphone pour le paiement',

    // ── My Bookings ────────────────────────────
    'my_bookings': 'Mes billets',
    'make_booking': 'Faire une réservation',
    'active_bookings': 'Actif',
    'past_bookings': 'Passé',
    'no_bookings': 'Aucun billet pour le moment',
    'no_tickets_subtitle': 'Réservez votre premier voyage et vos billets apparaîtront ici',
    'book_your_ticket': 'Réserver un billet',
    'track_booking': 'Suivre la réservation',
    'reference_code': 'Référence',
    'booking_status': 'Statut',
    'cancel_booking': 'Annuler la réservation',
    'cancel_confirm': 'Voulez-vous vraiment annuler cette réservation?',
    'cancelled_successfully': 'Réservation annulée avec succès.',

    // ── Ticket ─────────────────────────────────
    'download_ticket': 'Télécharger le billet',
    'share_ticket': 'Partager le billet',

    // ── Departure Management ───────────────────
    'departure_management': 'Gestion des départs',
    'blocked': 'Bloqué',
    'open': 'Ouvert',
    'block_departure': 'Bloquer le départ',
    'unblock_departure': 'Débloquer le départ',
    'bookings_count': 'réservations',
    'all_routes': 'Tous les itinéraires',

    // ── Pickup List ────────────────────────────
    'pickup_list': 'Liste de ramassage',
    'download_pickup_list': 'Télécharger la liste de ramassage',
    'print_pickup_list': 'Imprimer la liste de ramassage',
    'pickup_manifest': 'Manifeste de ramassage',

    // ── Notifications ──────────────────────────
    'notifications': 'Notifications',
    'no_notifications': 'Aucune notification pour le moment.',
    'mark_all_read': 'Marquer tout comme lu',
    'journey_alert': 'Alerte de voyage',
    'journey_starts_soon': 'Votre voyage commence dans 20 minutes',
    'snooze': 'Rappeler dans 5 min',
    'snooze_remaining': '{count} rappel(s) restant(s)',
    'no_more_snoozes': 'Plus de rappels disponibles',
    'unread_notification': 'notification non lue',
    'unread_notifications': 'notifications non lues',
    'no_notifications_subtitle': 'Réservez un voyage et vous verrez les mises à jour de votre trajet ici.',

    // ── Profile ────────────────────────────────
    'profile': 'Profil',
    'settings': 'Paramètres',
    'language': 'Langue',
    'logout': 'Se déconnecter',
    'logout_confirm': 'Voulez-vous vraiment vous déconnecter?',
    'loyalty_points': 'Points de fidélité',
    'free_tickets': 'Billets gratuits',
    'total_bookings': 'Total des réservations',

    // ── Errors ─────────────────────────────────
    'error_network': 'Aucune connexion internet. Veuillez vérifier votre réseau.',
    'error_server': 'Erreur du serveur. Veuillez réessayer plus tard.',
    'error_auth': 'Session expirée. Veuillez vous reconnecter.',
    'error_timeout': 'Délai de requête dépassé. Veuillez réessayer.',
    'permission_denied': 'Permission refusée.',
    'notification_permission': 'La permission de notification est requise pour les alertes de voyage.',
    'alarm_permission': 'La permission d’alarme est requise pour les alertes de voyage.',
    'open_settings': 'Ouvrir les paramètres',

    // ── Journey Type Selection ─────────────────────
    'select_journey_type': 'Sélectionnez un type de voyage',
    'what_kind_of_trip': 'Quel type de voyage ?',
    'plan_your_trip': 'Planifiez votre voyage',
    'choose_journey_type_desc': 'Voyage interurbain au Rwanda, ou voyage en Afrique de l\'Est',
    'choose_route_and_time': 'Choisissez votre itinéraire et l\'heure de départ',
    'intercity': 'Voyage interurbain',
    'intercity_desc': 'Voyagez au Rwanda — Kigali vers Musanze, Huye, Rubavu, Rusizi, Nyagatare et plus encore',
    'east_africa': 'Voyage en Afrique de l\'Est',
    'east_africa_desc': 'Voyage au Kenya, en Ouganda, en Tanzanie et au-delà',

    // ── Booking Wizard Steps ─────────────────────
    'booking_title': 'Réserver un billet de bus',
    'booking_subtitle': 'Remplissez vos détails de voyage ci-dessous pour réserver votre place.',
    'step_route': 'Itinéraire',
    'step_agency': 'Agence',
    'step_schedule': 'Horaire',
    'step_passengers': 'Passagers',
    'step_payment': 'Paiement',
    'title_route': 'Où allez-vous?',
    'title_agency': 'Sélectionnez une agence de bus',
    'title_schedule': 'Quand voyagez-vous?',
    'title_passengers': 'Détails du passager',
    'title_payment': 'Paiement & confirmation',
    'desc_route': 'Choisissez votre origine et destination',
    'desc_agency': 'Choisissez parmi les agences de bus disponibles',
    'desc_schedule': 'Choisissez votre date et heure de voyage',
    'desc_passengers': 'Entrez les informations du passager',
    'desc_payment': 'Vérifiez et complétez votre réservation',

    // ── Booking Fields ───────────────────────────
    'origin': 'Origine',
    'destination': 'Destination',
    'search_location': 'Rechercher un lieu...',
    'select_origin': 'Sélectionnez le lieu de départ',
    'select_destination': "Sélectionnez le lieu d'arrivée",
    'select_destination_picker': 'Sélectionnez la ville de destination',
    'dest_diff_origin': 'La destination doit être différente de l’origine',
    'travel_date': 'Date de voyage',
    'departure_time': 'Heure de départ',
    'num_seats': 'Nombre de places',
    'select_seats': 'Sélectionnez les places',
    'seats_selected': 'sélectionné(s)',
    'seat': 'Place',

    // ── Route/Agency ───────────────────────────────
    'searching_routes': 'Loading...',
    'select_agency_continue': 'Sélectionnez une agence pour continuer',
    'no_routes_subtitle': 'Essayez d\'autres villes ou revenez plus tard',
    'select_button': 'Sélectionner',
    'service_fee_label': 'frais de service',

    // ── Schedule ───────────────────────────────────
    'pick_date_time': 'Choisissez une date et heure de départ',
    'select_travel_hour': 'sélectionnez l\'heure de voyage',
    'morning': 'Matin',
    'afternoon': 'Après-midi',
    'night': 'Nuit',

    // ── Seats ──────────────────────────────────────
    'seats_needed': 'Combien de places vous faut-il ?',
    '1_seat_selected': '1 place sélectionnée',
    'n_seats_selected': '%d places sélectionnées',

    // ── Booking Actions ──────────────────────────
    'continue_btn': 'Continuer',
    'pay_now': 'Payer maintenant',
    'back': 'Retour',
    'booking_loading': 'Réservation...',
    'change': 'Modifier',
    'currency': 'RWF',

    // ── Booking Status ───────────────────────────
    'booking_confirmed': 'Réservation confirmée!',
    'redirecting': 'Redirection vers votre réservation...',
    'keep_waiting': 'Continuer à attendre',
    'check_phone': 'Vérifiez votre téléphone',
    'check_phone_desc': 'Une demande de paiement a été envoyée à votre téléphone. Veuillez l’approuver pour compléter la réservation.',
    'verify_payment': 'Vérifier le paiement',
    'verifying': 'Vérification...',
    'view_booking': 'Voir la réservation',
    'payment_desc': 'Choisissez votre mode de paiement ci-dessous pour compléter votre réservation.',
    'amount': 'Montant',
    'ref_code': 'Code de référence',
    'payment_prompt_sent': 'Confirmez le paiement sur votre téléphone',
    'payment_prompt_desc': 'Une demande de paiement a été envoyée à votre téléphone. Veuillez confirmer le paiement. ',
    'payment_cancel': 'Annuler le paiement',
    'payment_cancelling': 'Annulation...',

    // ── Booking Validation ───────────────────────
    'select_origin_error': 'Sélectionnez le lieu de départ',
    'select_destination_error': "Sélectionnez le lieu d'arrivée",
    'select_route': 'Sélectionnez un itinéraire',
    'select_pickup_point': 'Sélectionnez un point de ramassage',
    'select_travel_date': 'Sélectionnez la date de voyage',
    'select_departure_time': "Sélectionnez l'heure de départ",
    'at_least_one_seat': 'Au moins 1 place',
    'select_payment_method': 'Sélectionnez le mode de paiement',
    'phone_required': 'Numéro de téléphone requis',
    'no_routes': 'Aucun itinéraire trouvé pour cette sélection',

    // ── Booking Footer ───────────────────────────
    'cancel_policy': 'Annulez jusqu’à 24h avant le départ. En retard? Le tarif est perdu.',
    'pay_methods': 'Payez avec MTN MoMo, Airtel Money ou M-Pesa.',
    'guide_link': 'Voir le guide complet et la politique d’annulation',

    // ── Booking Payment ─────────────────────────────
    'fare': 'Tarif',
    'payment_fee': 'Frais de paiement',
    'total': 'Total',
    'pay_online': 'Payer en ligne',
    'pay_online_desc': 'Confirmation rapide · Des frais de paiement supplémentaires s\'appliquent',
    'your_name': 'VOTRE NOM',
    'payment_phone_label': 'NUMÉRO DE TÉLÉPHONE DE PAIEMENT',
    'account_auto_created': 'Votre compte sera créé automatiquement',
    'please_enter_name': 'Veuillez entrer votre nom',
    'cancellation_not_permitted': 'Les annulations ne sont pas autorisées',
    'secure_payment': 'Paiement mobile money sécurisé',
    'need_help': 'Besoin d\'aide ? Contactez l\'assistance via le guide',

    // ── Booking Payment Methods ──────────────────
    'mtn_momo': 'MTN Mobile Money',
    'airtel_money': 'Airtel Money',
    'mpesa': 'M-Pesa',
    'mobile_money': 'Mobile Money',
    'phone_prefix': '+250',
    'phone_placeholder': '7XX XXX XXX',

    // ── Booking Pickup ───────────────────────────
    'pickup_timeline': 'Points de ramassage sur l’itinéraire',
    'choose_pickup': 'Choisissez votre point de ramassage',
    'unknown_agency': 'Agence inconnue',

    // ── My Bookings (additional) ─────────────────
    'my_trips': 'Mes voyages',
    'manage_trips': 'Consultez vos billets et l’historique des voyages',
    'no_upcoming': 'Aucun voyage à venir',
    'date': 'Date',
    'time': 'Heure',
    'book_first': 'Réservez votre premier voyage pour commencer',
    'book_a_trip': 'Réserver un voyage',
    'loading_trips': 'Chargement de vos voyages...',
    'login_to_view': 'Veuillez vous connecter pour voir vos voyages.',
    'show_ticket': 'Veuillez présenter ce billet à l’agent d’embarquement lors de la montée.',
    'login_required': 'Connexion requise',
    'login_to_see': 'Veuillez vous connecter pour voir vos voyages.',

    // ── Ticket View ──────────────────────────────
    'my_ticket': 'Mon billet',
    'digital_travel_pass': 'Pass de voyage numérique',
    'electronic_ticket': 'BILLET ÉLECTRONIQUE',
    'ticket_number': 'Numéro de billet',
    'try_again': 'Réessayer',
    'reference': 'Référence',

    // ── Free Ticket ──────────────────────────────
    'use_free_ticket': 'Utiliser un billet gratuit',
    'available': 'disponible(s)',
    'free_booking_info': 'Votre réservation sera gratuite. Aucun paiement nécessaire.',

    // ── Payment Result ─────────────────────────────
    'insufficient_funds': 'Fonds insuffisants',
    'payment_failed_message': 'Le paiement n\'a pas pu être effectué car il n\'y a pas assez de fonds sur votre compte mobile money pour couvrir ce montant.',
    'no_money_deducted': 'Aucun montant n\'a été débité et votre place a été libérée.',
    'done': 'Terminé',
    'payment_confirmed_msg': 'Paiement confirmé !',
    'payment_failed_title': 'Paiement échoué',

    // ── Calendar Months ────────────────────────────
    'month_jan': 'Janvier',
    'month_feb': 'Février',
    'month_mar': 'Mars',
    'month_apr': 'Avril',
    'month_may': 'Mai',
    'month_jun': 'Juin',
    'month_jul': 'Juillet',
    'month_aug': 'Août',
    'month_sep': 'Septembre',
    'month_oct': 'Octobre',
    'month_nov': 'Novembre',
    'month_dec': 'Décembre',

    // ── Navigation ─────────────────────────────────
    'nav_home': 'Accueil',
    'nav_my_tickets': 'Mes billets',
    'nav_alerts': 'Notifications',
  };
}
