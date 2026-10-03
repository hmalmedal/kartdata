# Analyse og arkitektur

Undersøkt 28. september 2026. Kilder: de lokale N1000-, N2000- og
N5000-repositoriene, byggeskriptene på GitHub (verifisert identiske med lokale
kopier), Geonorges aktive ATOM-feeder og N1000-data i FGDB og GML.

## De eksisterende pakkene

De tre `data-raw/data.R` er identiske etter erstatning av produktnavnet.
De importerer tidyverse, desc, fs, glue, lubridate, sf og usethis, laster ned
en hardkodet landsdekkende GML-ZIP, pakker ut, finner alle lag, leser alle
geometrier, vasker alle lag, skriver RDA og genererer utskriftsbasert
lagdokumentasjon. Til slutt settes pakkeversjon og Date til byggedato.

| Egenskap i eksisterende lokale pakker | N1000 | N2000 | N5000 |
|---|---:|---:|---:|
| RDA-filer | 43 | 35 | 26 |
| Samlet RDA-størrelse, byte | 20 368 282 | 4 295 500 | 1 112 432 |
| Oppgitt pakkeversjon | 25.1.1 | 25.1.1 | 25.1.1 |

Forskjellene er i dataenes generalisering, geometri, attributter og tilgjengelige
objekttyper, ikke i klientlogikken. N2000 mangler blant annet Bygning, Dam,
Gruve, LuftledningLH, Industriområde, InnsjøElvSperre og skytefeltlag fra N1000.
N5000 har ytterligere færre objekttyper, blant annet ingen høydekurvelag, Myr
eller Navigasjonsinstallasjon. Lagregister må derfor oppdages fra filene.
De gamle datasnapshottene skal heller ikke brukes som fasit for dagens lag.
N1000-testen fant nå også PresentasjonTekst.

Kopieringsfeil: N1000s pakkedokumentasjon ligger i `R/N5000-package.R`;
`man/N1000-package.Rd` henviser også til dette filnavnet. Metadata-lenken inne
i filen er korrekt for N1000. README-kall, DESCRIPTION-URL-er og de øvrige
pakkefilene undersøkt hadde riktige serienavn. Den gamle felles tittelen
«Kartdata» er lite beskrivende. Lisensen CC BY 4.0 og Kartverket som
rettighetshaver var knyttet til distribuerte data; dette skal ikke ukritisk
overføres til den nye rene kodepakken.

Fjernes fra den nye arbeidsflyten: hele RDA-byggingen, LazyData, `use_data`,
datadokumentasjon basert på utskrift av sf-objekter, kalenderbasert pakkeversjon,
translittererte globale R-objekter og alle hjelpeavhengighetene fra byggeskriptet.
`set_names(str_c)` gjør i praksis ingen nyttig navneendring.
Historikkomskriving og force-push har ingen rolle i den nye pakken.
De separate gamle repositoriene er analysert, men ikke slettet eller omskrevet.

## Datavask: bevar data

| Gammel behandling | Vurdering og valg |
|---|---|
| Fjern `gml_id` | Ikke nødvendig. Identifikatorer kan være nyttige; behold dem. |
| `1000-01-01` til NA | Kan være en nyttig forenkling der verdien er dokumentert som ukjent, men ingen generell regel er verifisert for alle serier/formater. Behold verdien. |
| Alle navn som slutter med `dato` til Date | Unødvendig når GDAL allerede gir en datotype, og kan kaste tidspunkt fra FGDB. Behold GDALs type. |
| Nullutfyll alle felter som inneholder `kommunenummer` | Bare nødvendig hvis innleseren faktisk mistet nuller. FGDB-prøven og syntetisk test bevarer tekstkoder. Ingen bred endring av originaldata. |
| ASCII-translitterer objektnavn | Var praktisk for RDA-objektnavn; unødvendig for tekstargumenter. Behold norske navn. |

Teknisk normalisering begrenses til serienavn (`1000`/`n1000` til `N1000`),
HTTPS for offisielle lenker og intern håndtering av format/lagnavn. Ingen
geometrireparasjon, reprojisering eller verdikonvertering skjer automatisk.

## Offisielle grensesnitt

1. [ATOM-veiledningen](https://www.geonorge.no/verktoy/APIer-og-grensesnitt/atom-feeds/)
   peker på den daglig oppdaterte tjenestefeeden. Klienten finner produktfeed
   etter metadata-ID i `describedby`, og følger publiserte `application/atom+xml`-lenker.
   De sju ID-ene er verifisert mot den aktive tjenestefeeden.
2. [Download API](https://www.geonorge.no/verktoy/APIer-og-grensesnitt/nedlastingsapiet/)
   er undersøkt, inkludert live `/api/capabilities/{N1000-id}`. Det støtter
   format, projeksjon, område og polygonvalg. Bestillingslogikk gir ingen
   fordel for ferdigproduserte filer i denne versjonen og er ikke implementert.
3. [Kartkatalogens API](https://www.geonorge.no/verktoy/APIer-og-grensesnitt/apier-for-kartkatalogen/)
   er egnet for metadatasøk. Et minimalt verifisert ID-register gjør søk ved
   hvert datakall unødvendig. Katalogsøk brukes ikke i kjøretid.

Ingen komplette kartnedlastingsadresser ligger i pakkens produktregister.
Format tas fra produktfeedens tittel: den virkelige FGDB-feeden merker
nedlastingslenker feilaktig som `application/gml+xml`. EPSG kommer fra ATOM
category; områdekode identifiseres i det publiserte filnavnet fordi feeden
ikke har en entydig strukturert kode for alle områder. Filnavnet brukes kun
til å velge en eksisterende lenke. Et endret navneskjema gir en tydelig feil.
Klienten aksepterer kun nedlastingsverten `nedlasting.geonorge.no`.

Filentryens `updated` brukes som ugjennomsiktig versjonsverdi sammen med URL.
Noen verdier mangler tidssone. Likhetskontroll unngår å anta en tidssone eller
feilaktig bruke feedens publiseringstid som datasettversjon. Endring i en av
verdiene gir oppdatering; force er tilgjengelig ved uendret metadata.

## FGDB proof of concept

Lokal sf/GDAL 3.12.1 støtter OpenFileGDB og GML. N1000-FGDB-ZIP var
21 924 000 byte ved undersøkelsen. Den har 16 fysiske lag etter tema/geometri.
For eksempel deler Veglenke, Bane og AnnenBåtrute et samferdselslag.
Dette løses uten vedlikeholdt oversettelsestabell: GDAL henter unike `objtype`
uten geometrikolonner; ønsket objekttype leses med `WHERE objtype = ...`.
SQL-identifikatorer og tekstverdier siteres separat. Fysiske lag er også
tilgjengelige, og tvetydige objekttypenavn gir forslag til fysiske lag.

Dermed beholdes FGDB som førstevalg. GML er automatisk alternativ hvis
tilgjengelighet eller lokal driver utelukker FGDB, og kan alltid velges eksplisitt.
En ødelagt fil eller uventet FGDB-skjema skjules ikke som en formatendring;
feilmeldingen beskriver reparasjon eller eksplisitt GML-valg.
Attributter, navneform og typer er formatavhengige; det loves ikke identiske
skjemaer mellom GML og FGDB. Begge ga 14 467 Veglenke-objekter i live-testen.

## Implementasjon og begrensninger

- `products.R`: statisk produktregister og inputvalidering.
- `areas.R`: publiserte områdenavn, koder og EPSG/format-kombinasjoner fra ATOM.
- `discovery.R`: HTTP, namespace-bevisst XML-lesing, produkt-/filvalg og drivere.
- `cache.R`: cache per serie/område/EPSG/format, original ZIP, utpakking,
  DCF-metadata, tekstlig filinventar, sjekk og tømming.
- `read.R`: lagoppdagelse og selektiv lesing av originaldata.
- `memory.R`: begrenset minnecache for lagindekser og innleste sf-objekter.
- `progress.R`: valgfri interaktiv framdrift uten nye avhengigheter.

Framdrift aktiveres med `options(kartdata.progress = TRUE)` og er ellers på
bare i interaktive økter. httr2 håndterer nedlastingsindikatoren; metadata-
oppslag viser kun en statusmelding. FGDB-lagoppdagelse teller ferdig undersøkte
fysiske lag med base Rs tekstindikator, som lukkes også ved feil. Lag har ulik
størrelse, så telleren er ikke et tidsestimat. Utpakking, sjekksum og GDAL-lesing
er blokkerende operasjoner uten prosentindikator; de viser operasjonsnavn.
Et vellykket lesekall viser antall objekter. Minnecachetreff omgår disse
meldingene sammen med arbeidet. Deaktivering påvirker ikke feil og advarsler.

Gjentatt innlesing caches i samme R-økt. I målingen av allerede nedlastet
N1000 brukte lagoppdagelsen omtrent 1,9 sekunder av 2,8 sekunder for `n_get`.
Både indeks og sf-resultat gjenbrukes derfor, innenfor en delt standardgrense
på 128 MiB målt med `object.size`. Minst nylig brukte oppføring fjernes først;
objekter over grensen beholdes ikke. Dette begrenser beholdt cache, ikke total
RAM under lesing eller objekter brukeren selv har referanser til.
Cacheidentiteten inkluderer absolutt kildebane, metadata og filstatistikk for
arkiv og manifest. Vellykket erstatning av diskcachen fjerner alltid tilsvarende
minneoppføringer, selv ved force med identiske data. Eksisterende validering av
originalfiler og eksplisitte nettverkssjekker utføres før minnecacheoppslag.
Ingen avledede kartfiler lagres på disk. En vedvarende innlesingscache er utsatt:
den ville gi mer diskbruk og kreve versjonering av serialiserte sf-objekter.
Brukeren kan omgå minnecachen per `n_get`-kall, endre minnegrensen eller tømme
bare minnecachen. Første kall i en ny R-økt må fortsatt lese fra originalfilene.
Etter implementasjon tok gjentatt `n_get("Veglenke", 1000)` omtrent 0,15 sekunder
med minnecache mot 2,83 sekunder med `memory_cache = FALSE` på testmaskinen.
Første kall i prosessen tok 3,45 sekunder. Resultatene var identiske, og laget
med indeks opptok omtrent 13,5 MB i minnecachen. Tallene er enkeltmålinger,
ikke garantier for andre maskiner eller datasett.

Avhengigheter i kjøretid: sf, httr2 og xml2. Base R brukes til øvrig arbeid.
Områdenavn slås opp eksakt (uten hensyn til store/små bokstaver) i en liten
UTF-8-tabell under brukerens cache. `n_areas()` oppdager fylke-/kommunenavn fra
ATOM category-label og områdekode fra publisert filnavn. Hele oversikten for
serien brukes til å oppdage tvetydige navn, ikke bare tidligere nedlastede områder.
EPSG velges fortsatt eksplisitt. Tabellen kan oppdateres med `refresh = TRUE`
og gjenbrukes uten nett; navnebaserte kall med check/force oppdaterer den også.
Navn og tallkoder normaliseres til eksisterende tegnkode før cacheoppslag.
Dermed deles både fil- og minnecache mellom for eksempel Oslo, "03" og 3.
Tall under 100 tolkes som tosifrede koder, øvrige som firesifrede; 0 betyr Norge.
Eksplisitte tegnkoder bevarer ledende nuller. Områdetabellen slettes sammen med
seriens cache, men ikke ved tømming av bare minne. Ingen kartarkiver må lastes
ned for å vise listen. Områdeoppdagelse ble prøvd mot alle sju aktive serier
3. oktober 2026: N50–N250 hadde 373 områdekoder, N500–N2000 hadde 16,
og N5000 hadde bare landsdekkende filer. Tilgjengeligheten kan endres.
Cacheoppdatering bygges i egen midlertidig mappe. ZIP-medlemsstier valideres
før utpakking, størrelser kontrolleres og GDAL må kunne liste lag før mappen
erstatter gammel cache. En låsemappe hindrer samtidige skrivere til samme
oppføring. Vanlig avbrudd rydder opp; etter prosesskrasj kan låsen måtte fjernes
manuelt etter at brukeren har sjekket at ingen nedlasting kjører. Samtidig
lesing/tømming mellom prosesser er ikke støttet.

Første bruk krever hele det valgte originalarkivet på disk, men ikke hele
datasettet i R-minnet. `st_layers(do_count = FALSE)` unngår unødvendig telling.
FGDB-lagoppdagelse kan skanne attributter på disk. Det opprettes ingen
forhåndsbygde sf-lag. GML-leseren kan trenge å skanne XML for å finne skjema,
selv om bare ett lag materialiseres som sf.

Automatiske tester bruker genererte små FGDB-/GML-filer, mockede HTTP-svar og
midlertidig cache. Nettverkstest for alle sju produktfeeder og N1000-lesing er
eksplisitt opt-in. Ingen N50-nedlasting skjer i vanlig testing. Full innlesing
av alle serier er ikke verifisert, bare generisk kode, alle feedoppslag og N1000
med begge formater. Kartdata ligger utenfor Git; pakkeversjonen følger kode,
mens cachemetadata følger dataversjonen.
