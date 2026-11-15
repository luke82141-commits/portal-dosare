/// Linkurile de navigare către o instanță. Fără punct de plecare, ambele
/// aplicații pornesc ruta din locația curentă a telefonului.
library;

String _destinatie(String instanta) => '$instanta, România';

/// Google Maps: indicații de orientare cu mașina.
Uri rutaGoogleMaps(String instanta) => Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': _destinatie(instanta),
      'travelmode': 'driving',
    });

/// Waze: caută instanța și pornește navigarea.
Uri rutaWaze(String instanta) => Uri.https('waze.com', '/ul', {
      'q': _destinatie(instanta),
      'navigate': 'yes',
    });
