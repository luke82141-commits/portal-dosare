class Parte {
  final String nume;
  final String calitate;

  const Parte({required this.nume, required this.calitate});
}

class Sedinta {
  final String complet;
  final String data;
  final String ora;
  final String solutie;
  final String solutieSumar;

  const Sedinta({
    required this.complet,
    required this.data,
    required this.ora,
    required this.solutie,
    required this.solutieSumar,
  });
}

class Dosar {
  final String numar;
  final String data;
  final String institutie;
  final String obiect;
  final String stadiuProcesual;
  final String sectie;
  final String categorie;
  final List<Parte> parti;
  final List<Sedinta> sedinte;

  const Dosar({
    required this.numar,
    required this.data,
    required this.institutie,
    required this.obiect,
    required this.stadiuProcesual,
    required this.sectie,
    required this.categorie,
    required this.parti,
    required this.sedinte,
  });
}
