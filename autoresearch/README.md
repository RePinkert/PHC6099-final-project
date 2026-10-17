# autoresearch/ — model development records

Nothing in this directory ships with the package: `.Rbuildignore` excludes the
whole folder, and every package function reads `inst/extdata/` instead. It is the
working record of how the forecast model and the indicator layers were built.

| file | role |
| --- | --- |
| `program.md` | the experiment charter: what counts as an admissible step, what the advance rule is |
| `prepare.R` | training-data assembly and the MASE / coverage evaluation harness |
| `train.R` | the model family itself, including the `predict_fn` the package replicates internally |
| `fit_price_forecast.R` | fits the shipped artifact and checks the phase-B gate |
| `bootstrap_ci.R` | block-bootstrap CI for the reported MASE point estimate |
| `HANDOVER.md` | the running ledger: rounds, experiments, real-call records, leftovers |
| `results.tsv` | the frozen MASE ledger (see below) |

## results.tsv is an append-only historical ledger

`results.tsv` records the forecast experiment trail: one row per attempted
variant, with the MASE and bad-coverage figures and a `keep` / `discard` verdict.
Two properties are deliberate and should not be undone:

1. **It is frozen in time.** The rows stop at the end of the phase-A/B forecast
   work. Phase C added indicator layers, not forecast experiments, so there are no
   phase-C rows and none should be invented to make the file look current.
2. **It is append-only, and only at the end.** A genuinely new forecast
   experiment may add rows; an existing row's numbers, verdict or description is
   a historical record and must never be rewritten, reordered or deleted --
   including to "fix" a number that looks wrong. If a row is wrong, add a new row
   that supersedes it and says so.

The package never reads this file. Nothing under `inst/extdata/` is derived from
it, no test asserts against it, and no exported function can be affected by it.
Treat it as evidence of the tuning process, not as a configuration input.