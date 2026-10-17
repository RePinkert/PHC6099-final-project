# scenario 9: 讲不通的输入会被指名拒绝（快照锁定用户可见报错文本）

    Code
      tryCatch(electricity_price(anchor_zip_fl), error = function(e) e)$message
    Output
      [1] "Provide either year (2023-2025 annual ZIP-level) or period = \"mom\" (state monthly series)."

