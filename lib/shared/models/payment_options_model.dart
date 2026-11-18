import 'dart:math' as math;

/// One mobile-money option offered by pawaPay in a country.
class PaymentProviderOption {
  final String provider;
  final String name;
  final String? logo;
  final String method;
  final String currency;
  final int decimals;
  final String? status;

  const PaymentProviderOption({
    required this.provider,
    required this.name,
    required this.method,
    required this.currency,
    this.logo,
    this.decimals = 0,
    this.status,
  });

  factory PaymentProviderOption.fromJson(Map<String, dynamic> json) {
    return PaymentProviderOption(
      provider: json['provider'] as String? ?? '',
      name: json['name'] as String? ?? '',
      logo: (json['logo'] as String?)?.trim().isEmpty == true
          ? null
          : json['logo'] as String?,
      method: json['method'] as String? ?? 'mom',
      currency: json['currency'] as String? ?? 'RWF',
      decimals: (json['decimals'] as num?)?.toInt() ?? 0,
      status: json['status'] as String?,
    );
  }
}

/// A country the traveller can pay from, with the providers pawaPay enables.
class PaymentCountryOption {
  final String code;
  final String iso2;
  final String name;
  final String prefix;
  final String currency;
  final List<PaymentProviderOption> providers;

  const PaymentCountryOption({
    required this.code,
    required this.iso2,
    required this.name,
    required this.prefix,
    required this.currency,
    required this.providers,
  });

  factory PaymentCountryOption.fromJson(Map<String, dynamic> json) {
    final providers = (json['providers'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PaymentProviderOption.fromJson)
        .toList();
    return PaymentCountryOption(
      code: json['code'] as String? ?? '',
      iso2: json['iso2'] as String? ?? '',
      name: json['name'] as String? ?? '',
      prefix: json['prefix'] as String? ?? '',
      currency: json['currency'] as String? ?? 'RWF',
      providers: providers,
    );
  }

  /// Unicode flag derived from the ISO2 code (offline, no image needed).
  String get flagEmoji {
    if (iso2.length != 2) return '\u{1F30D}';
    const base = 0x1F1E6;
    return String.fromCharCodes(
      iso2.toUpperCase().codeUnits.map((unit) => base + (unit - 65)),
    );
  }
}

/// Answer of `GET /bookings/payment-options`.
class PaymentOptions {
  final String detectedCountry;
  final List<PaymentCountryOption> countries;

  /// RWF value of one unit of each currency.
  final Map<String, double> rwfPerUnit;

  const PaymentOptions({
    required this.detectedCountry,
    required this.countries,
    required this.rwfPerUnit,
  });

  factory PaymentOptions.fromJson(Map<String, dynamic> json) {
    final countries = (json['countries'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PaymentCountryOption.fromJson)
        .where((country) => country.providers.isNotEmpty)
        .toList();
    final rates = <String, double>{'RWF': 1};
    final rawRates = json['rates'];
    if (rawRates is Map) {
      rawRates.forEach((key, value) {
        final rate = (value as num?)?.toDouble();
        if (rate != null && rate > 0) rates[key.toString()] = rate;
      });
    }
    return PaymentOptions(
      detectedCountry: json['detectedCountry'] as String? ??
          (countries.isNotEmpty ? countries.first.code : 'RWA'),
      countries: countries,
      rwfPerUnit: rates,
    );
  }

  PaymentCountryOption? countryByCode(String? code) {
    if (code == null || code.isEmpty) return null;
    final wanted = code.toUpperCase();
    for (final country in countries) {
      if (country.code.toUpperCase() == wanted ||
          country.iso2.toUpperCase() == wanted) {
        return country;
      }
    }
    return null;
  }

  PaymentCountryOption? get defaultCountry =>
      countryByCode(detectedCountry) ??
      (countries.isNotEmpty ? countries.first : null);

  /// RWF value of one unit of [currency].
  double rateFor(String? currency) {
    if (currency == null || currency.isEmpty) return 1;
    return rwfPerUnit[currency.toUpperCase()] ?? 1;
  }

  /// Converts an RWF amount to [currency] exactly like the server does.
  int convert(int amountRwf, String? currency) {
    if (currency == null || currency.isEmpty || currency == 'RWF') {
      return amountRwf;
    }
    final rate = rateFor(currency);
    if (rate <= 0) return amountRwf;
    return math.max(1, (amountRwf / rate).round());
  }
}
