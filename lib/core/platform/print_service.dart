import 'dart:typed_data';

/// Abstract interface for printing capabilities.
///
/// On Android: prints to handheld built-in printers or via system print dialog.
/// On iOS: uses AirPrint via the system print dialog.
abstract class PrintService {
  /// Prints a pickup list as a formatted document.
  Future<void> printPickupList(PickupListData data);

  /// Generates a PDF of the pickup list and returns the bytes.
  Future<Uint8List> generatePickupListPdf(PickupListData data);
}

/// Data model for a pickup list to be printed.
class PickupListData {
  final String routeName;
  final String date;
  final List<PickupPassenger> passengers;
  final int totalSeats;

  const PickupListData({
    required this.routeName,
    required this.date,
    required this.passengers,
    required this.totalSeats,
  });
}

/// A single passenger entry in a pickup list.
class PickupPassenger {
  final String referenceCode;
  final String passengerName;
  final String phone;
  final String pickupPoint;
  final int seats;
  final String travelTime;

  const PickupPassenger({
    required this.referenceCode,
    required this.passengerName,
    required this.phone,
    required this.pickupPoint,
    required this.seats,
    required this.travelTime,
  });
}
