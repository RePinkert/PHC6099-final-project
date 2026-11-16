# state-code.R —— 州代码解析（W0：价格/寿命层只接受州）
#
# 为什么需要它：ZIP 级电价来源不存在（见 docs/confidence-plan.md 的 D1），随包价格层
# 2026-11 起只答州级。收 ZIP 再悄悄降级到州，会让签名承诺一件它做不到的事；
# 所以 ZIP 的入口被收窄成一个查询：zip_to_state()。
#
# 这个函数承担三件事：
#   1) 归一化：'fl' / ' Florida ' / 'Florida' -> 'FL'；
#   2) 指名拒绝 ZIP 形状，并指路 zip_to_state()——这是最容易被误用的入口；
#   3) 拒绝 NA / 空 / 多值 / 未知码，错误文本给出可接受的形式。

.state_code <- function(x) {
  if (is.null(x) || is.list(x) || length(x) != 1L) {
    stop("state expects exactly one value (a two-letter USPS code or a full state name).",
         call. = FALSE)
  }
  if (is.na(x)) {
    stop("state is NA; a US state is required.", call. = FALSE)
  }
  s <- trimws(as.character(x))
  if (!nzchar(s)) {
    stop("state is empty; a US state is required.", call. = FALSE)
  }
  if (grepl("^[0-9]{9}$", s) || grepl("^[0-9]{5}(-[0-9]{4})?$", s)) {
    stop(sprintf(paste0(
      "'%s' looks like a ZIP code. This function takes a US state, because the price series ",
      "is state-level. Resolve the ZIP first: zip_to_state(\"%s\")$state. ",
      "For ZCTA-level health data use health_measure()."), s, substr(s, 1L, 5L)),
      call. = FALSE)
  }
  ab <- c(datasets::state.abb, "DC")
  nm <- c(datasets::state.name, "District of Columbia")
  if (grepl("^[A-Za-z]{2}$", s)) {
    up <- toupper(s)
    if (up %in% ab) return(up)
  }
  hit <- match(tolower(s), tolower(nm))
  if (!is.na(hit)) return(ab[hit])
  stop(sprintf(paste0(
    "Unknown state '%s'. Use a two-letter USPS code such as 'FL', or a full state name ",
    "such as 'Florida' (DC and 'District of Columbia' are accepted)."), s),
    call. = FALSE)
}
