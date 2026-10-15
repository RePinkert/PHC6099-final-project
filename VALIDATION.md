# MVP validation

Validated locally with R 4.6.1.

- All 58 FLHealthCHARTS rows match 58 Census 2020 GEOIDs one-to-one.
- The 22.10 / 22.1 tract-label case is checked explicitly.
- Two zero-death tracts are retained in the data and flagged as small counts.
- The example address query selects 29 tract internal points within 10 km.
- Unit checks cover a known great-circle distance, zero radius, empty results,
  invalid coordinates and IDs, noninteger counts, mixed-period rejection,
  missing outcomes, small-count exclusion, export integrity and overwrite protection.
- All 32 test expectations passed.
- `R CMD build` completed with the vignette built.
- `R CMD check --no-manual lifewatt_0.1.0.tar.gz` completed with **Status: OK**;
  no errors, warnings or notes. Examples, tests, documentation and vignette
  rebuilding were checked. PDF manual generation was not requested.
- Both map and distance-plot PNGs were visually inspected.
- The self-contained Chinese HTML report was opened in a browser; both embedded
  figures loaded and the displayed 58/29 counts and tables matched R output.

These checks validate the software workflow and snapshot join. They do not
validate a causal research design or demonstrate a health effect of an AI facility.
