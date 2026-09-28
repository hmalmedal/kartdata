# kartdata

Én R-klient for Kartverkets topografiske N-serie: N50, N100, N250, N500,
N1000, N2000 og N5000. Pakken distribuerer ingen kartdata. Originalfilene
lastes direkte fra Kartverket/Geonorge og caches lokalt hos brukeren.

Installer kildepakken med `R CMD INSTALL .` når `sf`, `httr2` og `xml2` er installert.

```r
library(kartdata)

n_products()
n_layers("N1000")
veg <- n_get("Veglenke", "N1000")  # series = 1000 fungerer også
plot(sf::st_geometry(veg))
```

Første kall laster ned og pakker ut arkivet. Standardvalget er landsdekkende
data i EPSG:25833. Særlig N50 kan kreve betydelig diskplass og nedlastingstid.
Bare det valgte laget leses til et `sf`-objekt. Velg eventuelt et mindre
publisert område, for eksempel `area = "03", epsg = 25832` for Oslo.
Områdekoder må gis som tekst med ledende nuller. Tilgjengelighet av område,
format og koordinatsystem bestemmes av Geonorge. `epsg` velger kildefilen;
bruk `sf::st_transform()` hvis du trenger en annen projeksjon etter innlesing.

## Format og lag

`format = "auto"` foretrekker FGDB hvis både Geonorge og lokal GDAL støtter
det, ellers GML. Du kan velge `format = "GML"` eksplisitt.

I FGDB ligger objekttyper som Veglenke og Bane i felles temalag. Klienten
finner objekttypene med `SELECT DISTINCT objtype` uten å lese geometriene til R,
og leser ønsket objekttype med et SQL-filter i GDAL. `n_layers()` viser både
disse navnene og de originale fysiske FGDB-lagene. Hvis en objekttype finnes i
flere lag, ber feilmeldingen deg velge et fysisk lag. GML har egne lag per
objekttype. Attributtnavn og datatyper kan derfor variere mellom formatene.
Hvis et fremtidig FGDB-skjema ikke har `objtype`, velg GML eksplisitt.

Ingen automatisk sletting av `gml_id`, datovask, nullutfylling eller
ASCII-translitterering utføres. Originale verdier og GDALs datatyper beholdes.
Se [analyse og begrunnelse](docs/architecture.md).

## Cache og oppdatering

```r
n_cache_info()                       # innhold, diskbruk og integritet
n_cache_info(check = TRUE)           # sjekk versjoner via ATOM, ingen kartnedlasting
n_cache_info(verify = TRUE)          # kontroller også ZIP-sjekksum
veg <- n_get("Veglenke", 1000, refresh = "check")
veg <- n_get("Veglenke", 1000, refresh = "force")
n_cache_clear("N1000")               # fjern bare denne serien
n_cache_clear()                      # fjern alle kartdata-cacheoppføringer
```

Standardplasseringen er `tools::R_user_dir("kartdata", "cache")`, utenfor
prosjektet og Git. Original ZIP, utpakkede originalfiler og små tekstbaserte
cachemetadata beholdes. Ingen kartdata konverteres til RDA, RDS eller Parquet.

Standard `refresh = "never"` gjenbruker cache uten nettverk. Manglende cache
lastes ned. `"check"` sammenligner filens URL og ATOM-verdien `updated`;
enhver endring utløser ny nedlasting. Dette er et versjonssignal fra Geonorge,
ikke en garanti for at data aldri endres under samme tidsstempel. Bruk
`"force"` ved behov. Feil under en oppdatering gir en feilmelding og lar gammel
cache ligge. Bruk deretter `refresh = "never"` for å arbeide videre med den.

Integritetskontroll ved gjenbruk sjekker filenes tilstedeværelse og størrelse.
`verify = TRUE` kontrollerer også originalarkivets MD5 mot verdien lagret ved
nedlasting. En korrupt cache kan repareres med `refresh = "force"`.
Et annet cacheområde kan velges med `cache_dir`; velg et område utenfor Git.
Ikke kjør tømming og lesing samtidig fra forskjellige R-prosesser.

## Kreditering og lisens

Pakkekoden er GPL (>= 3). Kartverkets data har en separat lisens:
[Creative Commons Navngivelse 4.0](https://creativecommons.org/licenses/by/4.0/),
verifisert mot [Kartverkets bruksvilkår](https://www.kartverket.no/api-og-data/vilkar-for-bruk)
28. september 2026. Ved publisering: krediter **© Kartverket**, lenk til lisensen,
oppgi produkt og gjerne dataversjon, og opplys om egne endringer.
Klienten gir ingen garanti for datakvalitet eller løpende tjenestetilgjengelighet.

## Utvikling og tester

```r
testthat::test_local()  # små syntetiske FGDB/GML-filer, mockede HTTP-svar

# Frivillig: bare metadata fra Geonorge, alle sju serier
Sys.setenv(KARTDATA_INTEGRATION = "true")
testthat::test_local(filter = "integration")

# Frivillig: N1000-nedlasting til standard brukercache
Sys.setenv(KARTDATA_DOWNLOAD_TEST = "true")
testthat::test_local(filter = "integration")
```

Vanlig `R CMD check` laster ikke ned kartdata eller kontakter Geonorge.
De gamle pakkene erstattes i brukerens kode ved å endre for eksempel
`N1000::Veglenke` til `kartdata::n_get("Veglenke", "N1000")`.
Ingen databygging, dataversjonscommitter eller force-push er nødvendig.
