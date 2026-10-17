# scenario 1: 查现在的电价（observed，账单未填）

    Code
      print(r[, c("zip", "state", "period", "price", "unit", "regime", "provisional")])
    Output
          zip state  period price      unit   regime provisional
      1 32601    FL 2026-07 15.03 cents/kWh observed        TRUE

# scenario 2: 查下个月的电价（predicted regime）

    Code
      print(r[, c("zip", "period", "price", "price_sd", "regime", "fit_as_of")])
    Output
          zip  period   price price_sd    regime fit_as_of
      1 32601 2026-12 14.9938 1.370023 predicted   2026-07

# scenario 9: 讲不通的输入会被指名拒绝（快照锁定用户可见报错文本）

    Code
      tryCatch(expected_life_loss("99999", "2026-07"), error = function(e) e)$message
    Output
      [1] "No electric utility record for zip 99999 (OpenEI 2024 mapping)."

---

    Code
      tryCatch(expected_life_loss(anchor_zip_fl, "2026-93"), error = function(e) e)$
        message
    Output
      [1] "Invalid month: 2026-93."

---

    Code
      tryCatch(expected_life_loss(anchor_zip_fl, "2026-12", bill = -3), error = function(
        e) e)$message
    Output
      [1] "bill must be a positive number (USD/month)."

---

    Code
      tryCatch(life_expectancy(anchor_zip_fl, quarter = "2024-06"), error = function(
        e) e)$message
    Output
      [1] "Invalid quarter: 2024-06 (expects YYYY-Qn)."

---

    Code
      tryCatch(electricity_price(anchor_zip_fl), error = function(e) e)$message
    Output
      [1] "Provide either year (2023-2025 annual ZIP-level) or period = \"mom\" (state monthly series)."

