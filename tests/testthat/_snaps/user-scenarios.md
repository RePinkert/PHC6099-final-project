# scenario 1: 查现在的电价（observed，账单未填）

    Code
      print(r[, c("state", "period", "price", "unit", "regime", "provisional")])
    Output
        state  period price      unit   regime provisional
      1    FL 2026-07 15.03 cents/kWh observed        TRUE

# scenario 2: 查下个月的电价（predicted regime）

    Code
      print(r[, c("state", "period", "price", "price_sd", "regime", "fit_as_of")])
    Output
        state  period    price price_sd    regime fit_as_of
      1    FL 2026-12 15.15084 1.167262 predicted   2026-07

# scenario 9: 讲不通的输入会被指名拒绝（快照锁定用户可见报错文本）

    Code
      tryCatch(expected_life_loss(anchor_zip_fl, "2026-07"), error = function(e) e)$
        message
    Output
      [1] "'32601' looks like a ZIP code. This function takes a US state, because its data are state-level. Use a two-letter USPS code such as 'FL' (or a full state name). For ZCTA-level health data use health_measure()."

---

    Code
      tryCatch(expected_life_loss(anchor_state_fl, "2026-93"), error = function(e) e)$
        message
    Output
      [1] "Invalid month: 2026-93."

---

    Code
      tryCatch(expected_life_loss(anchor_state_fl, "2026-12", bill = -3), error = function(
        e) e)$message
    Output
      [1] "bill must be a positive number (USD/month)."

---

    Code
      tryCatch(life_expectancy(anchor_state_fl, quarter = "2024-06"), error = function(
        e) e)$message
    Output
      [1] "Invalid quarter: 2024-06 (expects a quarter such as '2024Q4'; '2024-Q4' is also accepted)."

---

    Code
      tryCatch(electricity_price(anchor_state_fl), error = function(e) e)$message
    Output
      [1] "Provide either year (2023-2025 annual, state-level) or period = \"mom\" (state monthly series)."

# scenario 11: 健康侧查糖尿病与高血压（ZCTA 原生，带 95% CI）

    Code
      print(r[, c("zip", "measure_id", "measure", "value", "low_ci", "high_ci")])
    Output
          zip measure_id             measure value low_ci high_ci
      1 32601     BPHIGH High Blood Pressure  24.0   21.4    26.9
      2 32601   DIABETES            Diabetes   7.7    6.8     8.7

# scenario 13: 抑制项与拼错 ID 报同一个错，坏 ZIP 各自指名

    Code
      tryCatch(health_measure("abcde"), error = function(e) e)$message
    Output
      [1] "Invalid zip 'abcde': expected 5 digits (leading zeros required, e.g. '01002') or ZIP+4."

---

    Code
      tryCatch(health_measure("99999"), error = function(e) e)$message
    Output
      [1] "No CDC PLACES estimates for ZIP 99999 (it may not be a ZCTA, or its population is too small)."

