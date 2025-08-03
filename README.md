# Web Crawler Script (`crawler.sh`)

A simple and robust Bash web crawler that:
- Recursively crawls a website up to a specified depth
- Extracts and follows links found in rendered HTML (supports JavaScript-heavy sites using a headless browser)
- Calls an API for each discovered URL and exports results to CSV
- Provides detailed logging to a file

---

## Requirements

- **bash** (version 4+ recommended)
- **curl** (for API calls)
- **pup** (for HTML parsing: [https://github.com/ericchiang/pup](https://github.com/ericchiang/pup))
- **Headless browser:**  
  One of `google-chrome`, `chromium`, or `chromium-browser` (used for JavaScript rendering)

Install missing dependencies using your system package manager.

Of course. Here is the corrected and improved version of your markdown.

-----

## Getting Started

This guide will walk you through setting up and running the web crawler script.

### System Requirements

  * **Operating System**: Linux (Ubuntu, Debian, CentOS, etc.)
  * **Bash**: Version 4.0 or higher. You can check your version with `bash --version`.

### Dependency Installation

You'll need to install a few command-line tools for the script to work correctly.

#### 1\. Curl

Most systems have `curl` pre-installed. If not, you can install it using your package manager.

  * **Ubuntu/Debian**
    ```bash
    sudo apt-get update && sudo apt-get install curl
    ```

#### 2\. Pup (HTML Parser)

You can install `pup` using one of the following methods.

  * **Option A: Using Go**

    ```bash
    go get github.com/ericchiang/pup
    ```

  * **Option B: Manual Installation**

    ```bash
    wget https://github.com/ericchiang/pup/releases/download/v0.4.0/pup_v0.4.0_linux_amd64.zip
    unzip pup_v0.4.0_linux_amd64.zip
    sudo mv pup /usr/local/bin/
    ```

#### 3\. Headless Chrome/Chromium

A headless browser is required for JavaScript rendering.

  * **Ubuntu/Debian**
    ```bash
    sudo apt-get install chromium-browser
    ```

### Script Installation

1.  **Clone the repository** (or download the script).

    ```bash
    git clone https://your-repository-url/crawler.git
    cd crawler
    ```

2.  **Make the script executable**.

    ```bash
    chmod +x crawler.sh
    ```
    
### Usage and Verification

1.  **Verify the installation** by checking the help menu. This confirms that the script and its dependencies are recognized.

    ```bash
    ./crawler.sh --help
    ```

2.  **Run a test crawl** to ensure everything is working.

    ```bash
    ./crawler.sh https://example.com 1
    ```
---

## Usage

```bash
./crawler.sh <starting_url> [max_depth]
```

- `<starting_url>`: The full URL to start crawling from (e.g. `https://www.webmd.com`)
- `[max_depth]`: Maximum crawl depth

**Example:**
```bash
./crawler.sh https://www.webmd.com 2
```

---

## Output

- **CSV File**: `crawl_results.csv`
  - Columns:
    - `Friendly url`: The original URL crawled
    - `Microservice url`: The service URL returned by the API
    - `Is k8s enabled?`: Whether Kubernetes is enabled for this URL
- **Log File**: `crawler.log`
  - All progress and errors are logged here

---

## Features

- **Depth-limited crawling:** Specify how deep the crawler should go.
- **Breadth-first strategy:** All links at level N are processed before N+1.
- **JavaScript rendering:** Uses a headless browser for full DOM extraction.
- **Duplicate avoidance:** Does not revisit URLs already processed.
- **API integration:** Calls a specified API for every discovered URL.
- **Graceful error handling:** Supports missing dependencies and network issues.

---

## Help Menu

Run:
```bash
./crawler.sh --help
```

**or**

```bash
./crawler.sh -h
```

### Help Output Example

```
Web Crawler Script by snegi

Usage:
  ./crawler.sh <starting_url> [max_depth]

Arguments:
  <starting_url>   The URL to begin crawling (must start with http:// or https://)
  [max_depth]      Maximum crawl depth (default: 5)

Options:
  -h, --help       Show this help message and exit

Features:
  - Crawls the target website up to the specified depth, extracting all reachable links.
  - Handles modern JavaScript sites using a headless Chrome or Chromium browser.
  - Calls a microservice API for every discovered URL and stores the results into a CSV file.
  - Avoids duplicate URL processing and logs all actions in crawler.log.

Example:
  ./crawler.sh https://www.webmd.com 3

Output:
  - Results are saved to crawl_results.csv
  - All logs are saved to crawler.log

Dependencies:
  - bash (v4+), curl, pup, google-chrome or chromium

For questions or issues, please review the script and logs.
```