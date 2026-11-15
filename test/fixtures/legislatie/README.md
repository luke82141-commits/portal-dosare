# Fixture-uri legislatie.just.ro

Răspunsuri reale ale portalului legislativ, salvate pentru testele de parsare
(forma consolidată a unui act și lista „Acțiuni suferite”). Fiecare fișier
este comprimat cu gzip; după decomprimare conținutul este exact octeții primiți
de la server (UTF-8, fără BOM).

Data descărcării: **15.11.2026** (fișierele sursă salvate în jur de 23:30–23:38,
ora României; cererile au fost reverificate live în aceeași seară, vezi mai jos).

| Fișier | Sursă | Act | Octeți (decomprimat) | SHA-256 (decomprimat) |
|---|---|---|---|---|
| `307_consolidat.html.gz` | `GET https://legislatie.just.ro/Public/DetaliiDocument/73657` | Legea 307/2006 (forma consolidată, `id_act` = 309352) | 605162 | `7c6adc2a8e782d51bb1c38656bdbbb068af5bc7268119b84f43c725ac4ffe1d1` |
| `hg273_consolidat.html.gz` | `GET https://legislatie.just.ro/Public/DetaliiDocument/4822` | HG 273/1994 (forma consolidată, `id_act` = 188976) | 55654 | `f9d99fd18edd86e3d512951e1e4c5d648454808a77d1633808a7ed132aed91e7` |
| `actiuni_73657.json.gz` | `POST https://legislatie.just.ro/Public/actiuniSuferite`, `contor=73657` | Legea 307/2006 | 30976 | `3bab3a8679795e7177450e8d2eddd63587864a22bffda4576434b5dcd7aba399` |
| `actiuni_39374.json.gz` | `POST https://legislatie.just.ro/Public/actiuniSuferite`, `contor=39374` | Codul de procedură civilă (1865, republicat) — titlul paginii: „COD PR. CIVILA (R) 24/02/1948” | 243570 | `af407a6645ab691022160035e786e2bec88f71dc1b25fa549f1c54f3680adc98` |
| `actiuni_4822.json.gz` | `POST https://legislatie.just.ro/Public/actiuniSuferite`, `contor=4822` | HG 273/1994 | 8932 | `58c6f2e0c3b5eb1014cce68081bdafe514407b695592f9d8fc6b4d4592b76883` |

## Cererea pentru DetaliiDocument (pagina actului)

```
GET /Public/DetaliiDocument/<id_act_de_baza> HTTP/1.1
Host: legislatie.just.ro
```

- Fără antete speciale, fără cookie-uri, fără autentificare.
- **Fără redirect**: răspunsul vine direct `200` (verificat cu redirecționările
  dezactivate). Serverul nu trimite `Set-Cookie`.
- Pentru ID-ul actului de bază (73657, 4822) serverul întoarce direct **ultima
  formă consolidată**; ID-ul formei consolidate apare în pagină în
  `<input id="id_act" name="id_act" value="…">`.
- Răspuns: `Content-Type: text/html; charset=utf-8`, fără BOM.
- Pagina conține un token generat la fiecare cerere în linkul „Forma printabilă”
  (`/Public/FormaPrintabila/<token>`); o descărcare nouă diferă doar prin acel token.

## Cererea pentru actiuniSuferite

Aceasta este cererea pe care o face chiar pagina (jQuery, din `ArataFisaAct`):
`$.post("/Public/actiuniSuferite", { contor: … })`.

```
POST /Public/actiuniSuferite HTTP/1.1
Host: legislatie.just.ro
Content-Type: application/x-www-form-urlencoded; charset=UTF-8
X-Requested-With: XMLHttpRequest   (opțional — vezi mai jos)

contor=73657
```

- Metodă: `POST`, corp form-urlencoded cu un singur câmp, `contor`.
- `contor` = **ID-ul actului de bază** (cel din URL-ul `DetaliiDocument`, ex.
  73657), **nu** `id_act` al formei consolidate. Cu `contor=309352` (`id_act`-ul
  consolidat al Legii 307) serverul întoarce un răspuns aproape gol
  (565 octeți, „Nu există…”).
- `X-Requested-With: XMLHttpRequest` nu este necesar: același răspuns, octet cu
  octet, și fără el. Nu e nevoie de cookie-uri, `Referer` sau token.
- Fără redirect (`200` direct).
- Răspuns: `Content-Type: application/json; charset=utf-8`, fără BOM.
  Corpul este `{"acte":"<html…>"}`, iar HTML-ul tabelului „Acțiuni suferite de
  acest act” este escapat JSON (`<`, `'` etc.).

## Verificare

Pe 15.11.2026 am refăcut cererile de mai sus:
- `actiuni_4822`, `actiuni_73657`, `actiuni_39374`: identice octet cu octet cu
  răspunsul live;
- `307_consolidat`: identic, cu excepția tokenului „Forma printabilă” (24 de octeți).

Observație: copiile locale inițiale ale fișierelor `307_consolidat.html`,
`actiuni_73657.json` și `actiuni_39374.json` aveau un BOM UTF-8 (`EF BB BF`)
adăugat la salvarea pe disc, nu trimis de server. Am eliminat BOM-ul înainte
de comprimare, ca fixture-urile să conțină exact octeții primiți.

Nu sunt incluse aici: pagina Codului de procedură civilă și XML-ul de căutare SOAP.
