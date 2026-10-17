library(jsonlite)
files <- list.files("data-raw/eia_json", pattern = "[.]json$", full.names = TRUE)
res <- lapply(files, function(f) {
  d <- fromJSON(f)$response$data
  data.frame(state = d$stateid, period = d$period, price = as.numeric(d$price),
             sector = d$sectorid)
})
df <- do.call(rbind, res)
df <- df[df$sector == "RES" & df$period >= "2023-01" & df$period <= "2026-07",
         c("state", "period", "price")]
write.csv(df, "data-raw/b1_monthly_cache.csv", row.names = FALSE)
cat(nrow(df), "rows,", length(unique(df$state)), "states,",
    nrow(df) / length(unique(df$state)), "months/state\n")
