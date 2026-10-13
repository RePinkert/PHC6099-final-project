# lifewatt

<!-- badges: start -->
<!-- badges: end -->

`lifewatt` turns a US ZIP code into environmental justice indicators:
average residential electricity price and its year-over-year (YoY) and
month-over-month (MoM) trends, plus average life expectancy and its YoY and
MoM trends.

## Installation

You can install the development version from GitHub with:

```r
# install.packages("devtools")
devtools::install_github("RePinkert/PHC6099-final-project")
```

## Example

```r
library(lifewatt)

electricity_price("32601")
electricity_price_trend("32601", period = "yoy")

life_expectancy("32601")
life_expectancy_trend("32601", period = "mom")
```

> This is a placeholder skeleton; the functions are not implemented yet.
