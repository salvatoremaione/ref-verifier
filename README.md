# 🕵️‍♂️ Reference Verifier in R

**Parse, verify, and highlight questionable academic references** — catch fabricated or erroneous citations before they catch you.

## 📖 Overview
This R tool validates bibliographic references by:
- Parsing plain‑text references (APA, MLA, Chicago).
- Verifying DOIs via the [Crossref API](https://api.crossref.org/).
- Cross‑checking publisher & ISSN metadata.
- Falling back to multi‑query title searches via Crossref & [OpenAlex](https://openalex.org/).
- Scoring matches using title similarity, author surname overlap, and year proximity.
- Generating a color‑coded [`gt`](https://gt.rstudio.com/) table for quick review.

## ✨ Features
- Handles DOIs with typos or stray spaces.
- Works even when DOIs are missing (via title fallback).
- Flags mismatches in year, ISSN, and publisher.
- Clear traffic‑light color coding for match confidence.

## 📦 Requirements
Install R packages:
```r
install.packages(c(
  "dplyr", "purrr", "tibble", "readr", "stringi", "stringdist",
  "httr", "jsonlite", "stringr", "gt"
))
