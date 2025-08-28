# Reference Verifier in R

Parse, verify, and highlight questionable academic references — catch fabricated or erroneous citations before they catch you.

---

## 🛡️ Badges

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![R](https://img.shields.io/badge/R-4.3.1-blue?logo=r)
![CRAN Status](https://www.r-pkg.org/badges/version-last-release/gt)
![Dependencies](https://img.shields.io/badge/dependencies-10-lightgrey)
![API: Crossref](https://img.shields.io/badge/API-Crossref-blue)
![API: OpenAlex](https://img.shields.io/badge/API-OpenAlex-green)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.16980612.svg)](https://doi.org/10.5281/zenodo.16980612)

![GitHub Repo stars](https://img.shields.io/github/stars/salvatoremaione/ref-verifier?style=social)
![GitHub forks](https://img.shields.io/github/forks/salvatoremaione/ref-verifier?style=social)
![GitHub issues](https://img.shields.io/github/issues/salvatoremaione/ref-verifier)
![GitHub pull requests](https://img.shields.io/github/issues-pr/salvatoremaione/ref-verifier)
![Last Commit](https://img.shields.io/github/last-commit/salvatoremaione/ref-verifier)

---

## 📑 Table of Contents
- [Overview](#-overview)
- [Features](#-features)
- [Usage](#-usage)
- [Example Session](#-example-session)
- [Installation](#-installation)
- [How It Works](#-how-it-works)
- [Limitations](#-limitations)
- [License](#-license)

---

## 📚 Overview

`ref-verifier` is an R-based utility that validates bibliographic references by:

- Parsing plain-text references (APA, MLA, Chicago)
- Verifying DOIs via the [Crossref API](https://api.crossref.org)
- Cross-checking publisher and ISSN metadata
- Running title searches via Crossref and [OpenAlex](https://docs.openalex.org/api) if DOI is missing or invalid
- Scoring matches using title similarity, author surname overlap, and year proximity
- Producing a color-coded [`gt`](https://gt.rstudio.com/) table for quick review

**Ideal for:**
- Journal editors verifying manuscript references
- Peer reviewers checking citation accuracy
- Researchers cleaning up bibliographies

---

## ✨ Features

- ✅ Supports APA, MLA, and Chicago formats  
- 🔍 DOI and title-based verification  
- 🧠 Intelligent scoring system for match confidence  
- 🎨 Interactive, color-coded output via `gt`  
- 🌐 Integrates with Crossref and OpenAlex APIs  

---

## 🛠 Usage

### Step 1 — Prepare your references file
Create a plain-text file (e.g., `references.txt`) with **one reference per line**.  
DOIs may be included or omitted.

Example:
```
Smith, J. (2020). Example Article. Journal of Examples, 12(3), 45–56. https://doi.org/10.1234/example
Doe, A. (2019). Another Study. Example Journal, 5(2), 100–110.
```

### Step 2 — Run the verifier
```r
source("R/ref-verifier.R")
results <- verify_references("references.txt")
```

### Step 3 — Review the output
View in RStudio’s Viewer pane or export to HTML:
```r
gt::gtsave(results, "verification_report.html")
```

**Color codes:**
- 🟢 Green — high confidence match
- 🟡 Yellow — partial match or minor discrepancies
- 🔴 Red — likely incorrect or fabricated

---

## 📂 Example Session

```r
# Load the script
source("R/ref-verifier.R")

# Verify references from file
results <- verify_references("my_refs.txt")

# Save the report
gt::gtsave(results, "my_report.html")
```
Open `my_report.html` in your browser to view the results.

---

## 🚀 Installation

1. **Clone the repository**
    ```bash
    git clone https://github.com/salvatoremaione/ref-verifier.git
    cd ref-verifier
    ```

2. **Install required R packages**
    ```r
    install.packages(c(
      "dplyr", "purrr", "tibble", "readr", "stringi",
      "stringdist", "httr", "jsonlite", "stringr", "gt"
    ))
    ```

3. **Open the project**  
   Use R or RStudio in the cloned project directory.

---

## 🧠 How It Works

```mermaid
flowchart TD
    A([Start]) --> B[Read references file]
    B --> C{DOI present?}
    C -- Yes --> D[[Clean DOI & Query Crossref]]
    C -- No --> E[[Search by Title via Crossref & OpenAlex]]
    D --> F[Retrieve metadata]
    E --> F
    F --> G[Compare with reference data]
    G --> H[Calculate match score]
    H --> I[Assign color code]
    I --> J[[Generate GT table output]]
    J --> K([End])

    click D href "https://api.crossref.org" "Open Crossref API documentation"
    click E href "https://docs.openalex.org/api" "Open OpenAlex API documentation"
    click J href "https://gt.rstudio.com/" "Open GT package documentation"
```

**Step breakdown:**
1. **DOI Check** — Cleans DOI (if present) and queries [Crossref](https://api.crossref.org) for metadata.
2. **Metadata Match** — Compares publisher, ISSN, year, and title for mismatches.
3. **Fallback Search** — Uses [Crossref](https://api.crossref.org) and [OpenAlex](https://docs.openalex.org/api) title search if DOI fails or is missing.
4. **Scoring** — Combines:
   - Title similarity (string distance)
   - Author surname overlap
   - Year proximity
5. **Color Coding** — Assigns traffic-light colors for quick match confidence review.
6. **Output** — Generates a [`gt`](https://gt.rstudio.com/) table for easy inspection.

---

## ⚠️ Limitations

- Requires internet access for API queries
- Accuracy depends on metadata quality in Crossref/OpenAlex
- Non-English references may have lower match accuracy

---

## 📜 License

MIT License — see [LICENSE](LICENSE) for details.
