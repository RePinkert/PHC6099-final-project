# Source and interpretation record

Snapshot assembled for the local MVP on 2026-10-14 (user's America/New_York date).

## Tract geometry and population

Source: U.S. Census Bureau TIGERweb, **Census2020/tigerWMS_Census2020, layer 6**.

https://tigerweb.geo.census.gov/arcgis/rest/services/Census2020/tigerWMS_Census2020/MapServer/6

Query: `STATE='12' AND COUNTY='001'`; `outSR=4326`; selected fields:
`GEOID,NAME,BASENAME,CENTLAT,CENTLON,INTPTLAT,INTPTLON,POP100`.
Snapshot: 58 features; January 1, 2020 boundary vintage. Query distance uses
`INTPTLON` / `INTPTLAT` rather than the geometric centroid. `POP100` is 2020
Census population, displayed only as background; it is not the denominator
used to reconstruct 2020-2024 health rates.

## Community health

Florida Department of Health, FLHealthCHARTS Community Dashboard:

https://www.flhealthcharts.gov/ChartsDashboards/rdPage.aspx?rdReport=ChartsMaps.ChartsMapper

Selected filters: Chronic Disease > Alachua > Total Deaths > 2020-2024 >
Death From All Causes. The rate table and count table were independently
read from the rendered official data table. Numeric commas were removed.
All 58 rates and counts are preserved in `data-raw/input/alachua-health-2020-2024.csv`.

Data dictionary (all-causes definition on page 5):

https://www.flhealthcharts.gov/ChartsDashboards/_SupportFiles/CommunityMapDataDictionary.pdf

These are resident death counts and crude rates per 100,000 total population.
The official reported five-year-period rates are retained without recalculation.
The website warns about instability with fewer than five events or a population
denominator below 20. The MVP identifies the count-based criterion only, because
the exact health-rate denominator was not included in the captured table.
Zero reported rates remain zero in the snapshot; zero-count tracts are excluded
from default summaries, not promoted to evidence of low health risk.

For 2016-2020 and subsequent windows, the website uses 2020 tract boundaries.
Earlier windows can use 2010 boundaries. This version includes one window only.

## AI facility identity, period and approximate location

UF's system history identifies HiPerGator AI (2021):

https://news.ufl.edu/2025/05/the-fourth-generation-model-of-ufs-hipergator/

UF describes the East Campus power/cooling changes and shared data-center use:

https://explore.research.ufl.edu/power-upgrade-underway-at-uf-data-center.html

UF's public Computer Operator I posting identifies the East Campus Data Center
at **2060 NE Waldo Road, Gainesville, FL 32609**:

https://explore.jobs.ufl.edu/en-us/job/541158/computer-operator-i

The Census Geocoder matched that address using `Public_AR_Current`:

https://geocoding.geo.census.gov/geocoder/locations/onelineaddress?address=2060%20NE%20Waldo%20Road%2C%20Gainesville%2C%20FL%2032609&benchmark=Public_AR_Current&format=json

Returned point: longitude -82.298544905125, latitude 29.671465784631.
This is **street-address interpolation**, not a verified building centroid,
emissions outlet, or personal residence. The current address-point benchmark
and 2020 tract boundaries serve different purposes and are explicitly labelled.

## County life expectancy background

https://www.flhealthcharts.gov/ChartsDashboards/rdPage.aspx?rdReport=ChartsMaps.LifeExpectancyReport

Selected view: County 3-year estimates > 2022-2024 > Alachua.
Total: 78.9 years; reported 95% CI 78.5-79.2. Kept separately from tract rows.
County life expectancy must not be interpreted as the outcome inside a radius.

## Development limits

No age adjustment, causal analysis, pollution or noise measurement, historical
facility-exposure reconstruction, electricity-price calculation, monthly
life-expectancy estimation, nationwide facility inventory, or live API refresh
is implemented. The Census ACS endpoint tested during preparation required an
API key; no income or age estimates were substituted or fabricated. Those are
future extensions if the team secures and validates appropriate data.
