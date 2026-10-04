# kartdata 0.1.0

Første offentlige utgivelse av kartdata, en R-klient for Kartverkets
topografiske N-serier. Pakken distribuerer ingen kartdata.

## Funksjoner

- Oppdag N50, N100, N250, N500, N1000, N2000 og N5000 via Geonorges ATOM-feeder.
- Finn publiserte områder med `n_areas()`, og velg område med navn eller kode.
- List kartlag med `n_layers()` og les enkeltlag som `sf`-objekter med `n_get()`.
- Bruk FGDB som førstevalg, med GML som alternativ ved manglende
  tilgjengelighet eller lokal driverstøtte.
- Gjenbruk originalarkiver fra lokal diskcache og innleste lag fra en
  begrenset minnecache. Kontroller og tøm cache med `n_cache_info()` og
  `n_cache_clear()`.
- Vis valgfri framdrift for nedlasting, lagoppdagelse og innlesing.
- Les tre medfølgende vignetter og en koropletartikkel på nettstedet.

## Kjente begrensninger

- Første bruk laster ned hele det valgte arkivet. Detaljerte serier kan
  kreve betydelig diskplass og tid.
- Kartlag, attributter og tilgjengelige områder bestemmes av datakilden.
  Pakken reparerer ikke geometri eller reprojiserer data automatisk.
- Samtidig lesing og tømming av samme diskcache fra flere R-prosesser
  støttes ikke.
- Metadataoppslag er kontrollert for alle sju serier; full kartinnlesing
  er ikke verifisert for alle serier.
