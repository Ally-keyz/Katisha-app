/// Placeholder repository for city/location data used on the home screen.
/// This data comes from the backend's /data/districts and /data/east-africa-cities endpoints.
class HomeRepository {
  static const List<String> rwandaDistricts = [
    'Kigali',
    'Huye',
    'Musanze',
    'Rubavu',
    'Muhanga',
    'Byumba',
    'Kibuye',
    'Gisenyi',
    'Cyangugu',
    'Kibungo',
    'Nyanza',
    'Gitarama',
    'Kamonyi',
    'Ngoma',
    'Bugesera',
    'Gatsibo',
    'Nyagatare',
    'Gicumbi',
    'Rulindo',
    'Burera',
    'Nyaruguru',
    'Nyamagabe',
    'Nyaruzengwa',
    'Ruhango',
    'Musanze',
    'Nyabihu',
    'Ngororero',
    'Rusizi',
    'Karongi',
    'Nyamasheke',
  ];

  static const List<String> eastAfricaCities = [
    'Nairobi',
    'Mombasa',
    'Kampala',
    'Dar es Salaam',
    'Arusha',
    'Juba',
    'Bujumbura',
    'Kigali',
  ];

  static List<String> get allCities => [...rwandaDistricts, ...eastAfricaCities];
}
