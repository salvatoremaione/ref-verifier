# Reference Verifier in R

This tool parses scientific references from plain text and checks their authenticity using:

- **DOI verification** via Crossref
- **Publisher & ISSN cross-checks**
- **Multi-query title fallback** via Crossref & OpenAlex
- **Weighted match scoring**
- **Interactive reporting** with a color-coded `gt` table

## 📦 Requirements

```r
install.packages(c(
  "dplyr", "purrr", "tibble", "readr", "stringi", "stringdist",
  "httr", "jsonlite", "stringr", "gt"
))
