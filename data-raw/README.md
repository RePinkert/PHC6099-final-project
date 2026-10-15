# Rebuild the snapshot

From the package directory run:

```r
install.packages("jsonlite")  # Only if absent; needed for rebuilding, not normal use
source("data-raw/prepare_snapshot.R")
```

The included inputs preserve the original Census JSON responses and a CSV
capture of both official FLHealthCHARTS tables. Rebuilding uses no network.
The preparation script checks a one-to-one 58/58 GEOID match and preserves
official rates; it does not calculate rates from the separate 2020 population.

To refresh health values, open the official dashboard linked in
`inst/extdata/SOURCES.md`, apply the recorded filters, and capture both Count
and Rate tables. Verify the heading of each loaded table: a selected dropdown
alone is insufficient while the embedded table is loading. Keep tract labels
as text. `22.1` maps to tract `22.10`, GEOID `12001002210`.

Use the recorded Census layer and geocoder URLs to refresh other source files.
Recheck vintage, record counts, health definitions and the address match before
replacing the installed snapshot. `source_manifest.json` records source hashes.
