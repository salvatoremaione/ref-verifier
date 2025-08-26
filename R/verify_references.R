# ===============================
# Packages
# ===============================
library(dplyr)
library(purrr)
library(tibble)
library(readr)
library(stringi)
library(stringdist)
library(httr)
library(jsonlite)
library(stringr)
library(gt)

# ===============================
# Config and helpers
# ===============================
CFG <- list(
  ua        = user_agent("RefVerifier/2.0 (mailto:your-email@example.com)"),
  jw_strict = 0.92,
  jw_loose  = 0.85,
  api_cr    = "https://api.crossref.org/works",
  api_cr_j  = "https://api.crossref.org/journals",
  api_oa    = "https://api.openalex.org/works"
)

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a)) a else b

normalize_title <- function(x) {
  y <- stri_trans_general(x, "Latin-ASCII")
  y <- tolower(y)
  y <- gsub("[[:punct:]]", " ", y)
  y <- gsub("\\s+", " ", y)
  trimws(y)
}

jw_score <- function(a, b) 1 - stringdist(a, b, method = "jw", p = 0.1)

lastname_overlap <- function(a_str, b_str) {
  tok <- function(s) {
    if (is.null(s) || is.na(s) || !nzchar(s)) return(character(0))
    parts <- unlist(strsplit(s, "\\band\\b|&|;|,"))
    parts <- trimws(parts[nzchar(parts)])
    tolower(unique(parts))
  }
  a <- tok(a_str); b <- tok(b_str)
  if (length(a) == 0 || length(b) == 0) return(0)
  length(intersect(a, b)) / length(unique(c(a, b)))
}

safe_year <- function(x) suppressWarnings(as.integer(gsub("[^0-9]", "", as.character(x))))

# ===============================
# 1) Multi‑style plain‑text parser
# ===============================
parse_plain_references <- function(path) {
  raw <- read_lines(path)
  raw <- raw[nzchar(trimws(raw))]

  parse_line <- function(line) {
    line <- gsub("\\s+", " ", line)

    year <- str_extract(line, "(?<=\\()[1-2][0-9]{3}(?=\\))")
    if (is.na(year)) {
      year <- str_extract(line, ",\\s*(1[0-9]{3}|20[0-9]{2})")
      year <- gsub(",", "", year)
    }

    doi  <- str_extract(line, "10\\.\\d{4,9}/[-._;()/:A-Za-z0-9\\s]+")
    doi  <- gsub("\\s+", "", doi %||% "")

    url  <- str_extract(line, "https?://[^ ]+")

    author <- str_trim(
      if (!is.na(year)) sub(paste0("\\(", year, "\\).*"), "", line) else sub("\\\".*", "", line)
    )

    title <- str_match(line, "\\)\\.\\s+(.+?)\\.\\s+[A-Z]")[, 2]
    if (is.na(title)) title <- str_match(line, "\\\"(.+?)\\\"")[, 2]

    journal <- if (!is.na(title)) str_match(line, paste0(title, "\\.\\s+([^,\\d]+)"))[, 2] else NA

    tibble(
      id      = NA_integer_,
      title   = title %||% "",
      author  = author %||% "",
      year    = year %||% NA_character_,
      journal = journal %||% "",
      doi     = doi %||% "",
      url     = url %||% ""
    )
  }

  map_dfr(raw, parse_line) %>% mutate(id = row_number())
}

# ===============================
# 2) API calls (Crossref, OpenAlex, journal metadata)
# ===============================
check_doi <- function(doi) tryCatch({
  if (is.null(doi) || !nzchar(doi)) return(NULL)
  resp <- GET(paste0(CFG$api_cr, "/", URLencode(doi, TRUE)), CFG$ua, timeout(10))
  if (status_code(resp) >= 400) return(NULL)
  m <- fromJSON(content(resp, "text", encoding = "UTF-8"))$message
  tibble(
    source    = "crossref",
    title     = m$title[[1]] %||% NA_character_,
    author    = if (!is.null(m$author)) paste0(na.omit(paste(m$author$given, m$author$family)), collapse = ", ") else NA_character_,
    year      = tryCatch(m$issued$`date-parts`[[1]][1], error = function(e) NA_integer_),
    doi       = tolower(m$DOI %||% doi),
    url       = m$URL %||% NA_character_,
    publisher = m$publisher %||% NA_character_,
    issn      = if (!is.null(m$ISSN)) paste(m$ISSN, collapse = ", ") else NA_character_
  )
}, error = function(e) NULL)

get_journal_metadata <- function(name) tryCatch({
  if (is.null(name) || !nzchar(name)) return(NULL)
  resp <- GET(CFG$api_cr_j, CFG$ua, query = list(query = name), timeout(10))
  if (status_code(resp) >= 400) return(NULL)
  items <- fromJSON(content(resp, "text", encoding = "UTF-8"))$message$items
  if (is.null(items) || !length(items)) return(NULL)
  best <- items[[1]]
  list(
    title     = best$title %||% NA_character_,
    publisher = best$publisher %||% NA_character_,
    issn      = if (!is.null(best$ISSN)) paste(best$ISSN, collapse = ", ") else NA_character_
  )
}, error = function(e) NULL)

check_publisher_host <- function(url, publisher_name) {
  if (is.null(url) || !nzchar(url) || is.null(publisher_name) || !nzchar(publisher_name)) return(NA)
  host <- tryCatch(parse_url(url)$hostname, error = function(e) NA_character_)
  if (is.na(host)) return(NA)
  grepl(tolower(gsub("\\s+", "", publisher_name)),
        tolower(gsub("\\s+", "", host)),
        fixed = TRUE)
}

search_crossref <- function(q) tryCatch({
  if (is.null(q) || !nzchar(q)) return(tibble())
  resp <- GET(CFG$api_cr, CFG$ua, query = list(query.bibliographic = q, rows = 5), timeout(10))
  if (status_code(resp) >= 400) return(tibble())
  items <- fromJSON(content(resp, "text", encoding = "UTF-8"))$message$items
  if (is.null(items)) return(tibble())
  tibble(
    source    = "crossref",
    title     = map_chr(items$title, ~ .x[[1]] %||% NA_character_),
    author    = map_chr(items$author, ~ if (is.null(.x)) NA_character_ else paste(na.omit(paste(.x$given, .x$family)), collapse = ", ")),
    year      = map_int(items$issued, ~ tryCatch(.x$`date-parts`[[1]][1], error = function(e) NA_integer_)),
    doi       = tolower(items$DOI %||% NA_character_),
    url       = items$URL %||% NA_character_,
    publisher = items$publisher %||% NA_character_,
    issn      = map_chr(items$ISSN, ~ if (is.null(.x)) NA_character_ else paste(.x, collapse = ", "))
  )
}, error = function(e) tibble())

search_openalex <- function(q) tryCatch({
  if (is.null(q) || !nzchar(q)) return(tibble())
  resp <- GET(CFG$api_oa, CFG$ua, query = list(search = q, per_page = 5), timeout(10))
  if (status_code(resp) >= 400) return(tibble())
  res <- fromJSON(content(resp, "text", encoding = "UTF-8"))$results
  if (is.null(res)) return(tibble())
  tibble(
    source    = "openalex",
    title     = res$title %||% NA_character_,
    author    = map_chr(res$authorships, ~ if (is.null(.x)) NA_character_ else paste(map_chr(.x$author$display_name, tolower), collapse = ", ")),
    year      = res$publication_year %||% NA_integer_,
    doi       = tolower(gsub("^https?://doi.org/", "", res$doi %||% "")),
    url       = res$primary_location$landing_page_url %||% NA_character_,
    publisher = NA_character_,
    issn      = NA_character_
  )
}, error = function(e) tibble())

# ===============================
# 3) Verification routines
# ===============================
verify_by_doi <- function(ref, jm) {
  hit <- check_doi(ref$doi)
  if (is.null(hit)) return(NULL)

  host_ok <- check_publisher_host(hit$url, hit$publisher %||% jm$publisher)

  tibble(
    id                = ref$id,
    input_title       = ref$title,
    source            = "crossref",
    status            = ifelse(isTRUE(host_ok), "verified_doi_publisher_ok", "verified_doi_publisher_mismatch"),
    match_score       = 1.00,
    matched_title     = hit$title,
    matched_year      = hit$year,
    matched_doi       = hit$doi,
    matched_url       = hit$url,
    matched_publisher = hit$publisher,
    matched_issn      = hit$issn,
    claimed_publisher = jm$publisher %||% NA_character_,
    claimed_issn      = jm$issn %||% NA_character_,
    year_match        = if (!is.na(ref$year)) hit$year == safe_year(ref$year) else NA,
    issn_match        = if (!is.null(jm$issn) && nzchar(jm$issn) && nzchar(hit$issn)) grepl(jm$issn, hit$issn, fixed = TRUE) else NA,
    publisher_match   = host_ok
  )
}

verify_by_title <- function(ref, jm) {
  queries <- unique(c(
    ref$title,
    paste(ref$title, ref$author),
    paste(head(strsplit(ref$title, " ")[[1]], 6), collapse = " ")
  ))

  results <- bind_rows(map(queries, search_crossref),
                       map(queries, search_openalex)) %>%
    distinct(title, .keep_all = TRUE)

  if (!nrow(results)) return(NULL)

  scored <- results %>%
    mutate(
      tscore = jw_score(normalize_title(ref$title), normalize_title(title)),
      ascore = map_dbl(author, ~ lastname_overlap(ref$author, .x)),
      ygap   = abs(year - safe_year(ref$year)),
      score  = pmin(1, pmax(0, 0.75 * tscore + 0.20 * ascore - 0.05 * pmin(5, ifelse(is.na(ygap), 0, ygap))))
    ) %>%
    arrange(desc(score))

  best <- scored[1, ]

  status <- ifelse(best$score >= CFG$jw_strict, "verified_title_high_conf",
            ifelse(best$score >= CFG$jw_loose,  "verified_title_plausible", "weak_title_match"))

  # Publisher host check only if we have a DOI landing URL and some publisher hint
  pub_hint <- best$publisher %||% jm$publisher
  host_ok  <- if (!is.na(best$doi) && nzchar(best$doi) && !is.na(best$url) && nzchar(best$url) && nzchar(pub_hint)) {
    check_publisher_host(best$url, pub_hint)
  } else NA

  tibble(
    id                = ref$id,
    input_title       = ref$title,
    source            = best$source %||% NA_character_,
    status            = status,
    match_score       = as.numeric(best$score),
    matched_title     = best$title,
    matched_year      = best$year,
    matched_doi       = best$doi,
    matched_url       = best$url,
    matched_publisher = best$publisher,
    matched_issn      = best$issn,
    claimed_publisher = jm$publisher %||% NA_character_,
    claimed_issn      = jm$issn %||% NA_character_,
    year_match        = if (!is.na(ref$year) && !is.na(best$year)) best$year == safe_year(ref$year) else NA,
    issn_match        = if (!is.null(jm$issn) && nzchar(jm$issn) && !is.na(best$issn) && nzchar(best$issn)) grepl(jm$issn, best$issn, fixed = TRUE) else NA,
    publisher_match   = host_ok
  )
}

verify_reference <- function(ref) {
  jm <- get_journal_metadata(ref$journal)

  # Try DOI route first
  if (!is.null(ref$doi) && nzchar(ref$doi)) {
    by_doi <- verify_by_doi(ref, jm)
    if (!is.null(by_doi)) return(by_doi)
  }

  # Fallback to title route
  by_title <- verify_by_title(ref, jm)
  if (!is.null(by_title)) return(by_title)

  # Nothing found
  tibble(
    id                = ref$id,
    input_title       = ref$title,
    source            = NA_character_,
    status            = "no_evidence_found",
    match_score       = NA_real_,
    matched_title     = NA_character_,
    matched_year      = NA_integer_,
    matched_doi       = NA_character_,
    matched_url       = NA_character_,
    matched_publisher = NA_character_,
    matched_issn      = NA_character_,
    claimed_publisher = jm$publisher %||% NA_character_,
    claimed_issn      = jm$issn %||% NA_character_,
    year_match        = NA,
    issn_match        = NA,
    publisher_match   = NA
  )
}

verify_all <- function(refs) {
  map_dfr(seq_len(nrow(refs)), ~ verify_reference(refs[.x, ]))
}

# ===============================
# 4) Reporting: gt table with highlights
# ===============================
build_verification_gt <- function(results) {
  res <- results %>%
    mutate(
      severity = case_when(
        grepl("no_evidence|mismatch|weak", status) ~ "bad",
        grepl("plausible", status)                 ~ "warn",
        grepl("verified_doi_publisher_ok|verified_title_high_conf", status) ~ "ok",
        TRUE ~ "warn"
      )
    )

  gt_tbl <- res %>%
    select(
      id, input_title, source, status, match_score,
      matched_title, matched_year, matched_doi, matched_url,
      year_match, issn_match, publisher_match,
      claimed_issn, matched_issn, claimed_publisher, matched_publisher
    ) %>%
    gt() %>%
    tab_header(
      title = "Reference verification report",
      subtitle = "DOI checks, title fallback, ISSN and publisher host verification"
    ) %>%
    fmt_number(columns = match_score, decimals = 2) %>%
    cols_width(
      input_title ~ px(300),
      matched_title ~ px(300),
      matched_url ~ px(260)
    ) %>%
    tab_style(
      style = list(cell_fill(color = "#27ae60"), cell_text(color = "white")),
      locations = cells_body(columns = status, rows = grepl("verified_doi_publisher_ok|verified_title_high_conf", status))
    ) %>%
    tab_style(
      style = list(cell_fill(color = "#f39c12"), cell_text(color = "white")),
      locations = cells_body(columns = status, rows = grepl("plausible", status))
    ) %>%
    tab_style(
      style = list(cell_fill(color = "#e74c3c"), cell_text(color = "white")),
      locations = cells_body(columns = status, rows = grepl("no_evidence|mismatch|weak", status))
    ) %>%
    # Booleans: green true, red false, grey NA
    tab_style(
      style = cell_fill(color = "#27ae60"),
      locations = cells_body(columns = c(year_match, issn_match, publisher_match), rows = year_match == TRUE | issn_match == TRUE | publisher_match == TRUE)
    ) %>%
    tab_style(
      style = cell_fill(color = "#e74c3c"),
      locations = cells_body(columns = c(year_match, issn_match, publisher_match), rows = year_match == FALSE | issn_match == FALSE | publisher_match == FALSE)
    ) %>%
    tab_style(
      style = cell_fill(color = "#ecf0f1"),
      locations = cells_body(columns = c(year_match, issn_match, publisher_match), rows = is.na(year_match) | is.na(issn_match) | is.na(publisher_match))
    ) %>%
    tab_options(table.font.size = px(13))

  gt_tbl
}

# ===============================
# 5) Example run
# ===============================
# 1) Save your references in a plain text file, one per line, e.g. "refs.txt"
# 2) Then run:
# refs <- parse_plain_references("refs.txt")
# results <- verify_all(refs)
# print(results, n = Inf)  # raw results
# build_verification_gt(results)  # nice highlighted table

# Optional: save the table to HTML (requires gt >= 0.9)
# gtsave(build_verification_gt(results), "verification_report.html")
