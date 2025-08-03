#!/bin/bash

# Web Crawler Script
# Usage: ./crawler.sh <starting_url> <max_depth>
# Author: snegi
# Date: 2025-07-29

set -euo pipefail

# Configuration
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/108.0.0.0 Safari/537.36"
API_BASE_URL="https://routeapi.ma1.webmdhelios.com/pg/routebyurl?&key="
API_BASE_URL_DEVINT="https://routeapi.ma1.devint.webmdhelios.com/pg/routebyurl?&key="
CSV_OUTPUT="crawl_results.csv"
LOG_FILE="crawler.log"

# Global variables
declare -A to_visit_by_depth
declare -i current_depth=0
declare -i max_depth=5  # Default, will be overridden by user input

declare -A visited_urls
SEED_DOMAIN=""
PROCESSED_COUNT=0
FAILED_COUNT=0
HEADLESS_TIMEOUT=30

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Initialize CSV with headers
init_csv() {
    echo "Friendly url,Microservice url,Is k8s enabled?" > "$CSV_OUTPUT"
}

# Extract domain from URL
extract_domain() {
    local url="$1"
    echo "$url" | sed -E 's|^https?://([^/]+).*|\1|' | tr '[:upper:]' '[:lower:]'
}

# Add URL to queue
add_to_queue() {
    local url="$1"
    local depth="$2"
    
    # Skip if depth exceeds max
    if [[ $depth -gt $max_depth ]]; then
        log "Skipping $url - exceeds max depth $max_depth"
        return
    fi
   
    # Initialize array for this depth if it doesn't exist
    if [[ ! -v to_visit_by_depth[$depth] ]]; then
        to_visit_by_depth[$depth]=""
    fi
    
    # Append URL to this depth (space-separated)
    to_visit_by_depth[$depth]+="$url "
}

# Check if URL is visited
is_visited() {
    [[ -v visited_urls["$1"] ]]
}

# Mark URL as visited
mark_visited() {
    visited_urls["$1"]=1
}

# Resolve relative URL to absolute
resolve_url() {
    local base_url="$1"
    local href="$2"
    
    # If href is already absolute (has protocol)
    if [[ "$href" =~ ^https?:// ]]; then
        echo "$href"
        return
    fi
    
    # If href starts with //, add protocol
    if [[ "$href" =~ ^// ]]; then
        echo "https:$href"
        return
    fi
    
    # If href starts with /, it's absolute path
    if [[ "$href" =~ ^/ ]]; then
        local domain=$(echo "$base_url" | sed -E 's|(https?://[^/]+).*|\1|')
        echo "$domain$href"
        return
    fi
    
    # Relative path - resolve against current directory
    local base_dir=$(dirname "$base_url")
    echo "$base_dir/$href" | sed 's|/\./|/|g'
}

# Validate if link should be processed
is_valid_link() {
    local url="$1"
    local seed_domain="$2"
    
    # Skip fragments, mailto, tel, javascript, etc.
    if [[ "$url" =~ ^# ]] || \
       [[ "$url" =~ ^mailto: ]] || \
       [[ "$url" =~ ^tel: ]] || \
       [[ "$url" =~ ^javascript: ]] || \
       [[ "$url" =~ ^ftp: ]] || \
       [[ "$url" =~ ^data: ]]; then
        return 1
    fi
    
    # Extract domain and compare
    local link_domain=$(extract_domain "$url")
    if [[ "$link_domain" != "$seed_domain" ]]; then
        return 1
    fi
    
    # Skip certain file types
    if [[ "$url" =~ \.(pdf|jpg|jpeg|png|gif|css|js|ico|xml|zip|doc|docx|xls|xlsx|ppt|pptx)(\?.*)?$ ]]; then
        return 1
    fi
    
    return 0
}

# Make API call and add to CSV
process_api_call() {
    local url="$1"
    local clean_url=$(echo "$url" | sed 's|^https\?://||')

     # Determine which API base URL to use
    local api_url
    if [[ "$url" =~ devint ]]; then
        api_url="$API_BASE_URL_DEVINT"
        log "Using DEVINT API for: $clean_url"
    else
        api_url="$API_BASE_URL"
        log "Using production API for: $clean_url"
    fi
    
    log "Making API call for: $clean_url"
    
    local api_response=$(curl -s \
        --max-time 30 \
        --user-agent "$USER_AGENT" \
        "${api_url}${clean_url}")
    log "$api_response"
    if [[ $? -eq 0 && -n "$api_response" ]]; then
        # Parse JSON response
        local keyurl=$(echo "$api_response" | grep -o '"keyurl":"[^"]*"' | sed 's/"keyurl":"\([^"]*\)"/\1/' || echo "")
        local serviceurl=$(echo "$api_response" | grep -o '"serviceurl":"[^"]*"' | sed 's/"serviceurl":"\([^"]*\)"/\1/' || echo "")
        local k8sEnabled=$(echo "$api_response" | grep -o '"k8sEnabled":[^,}]*' | sed -e 's/"k8sEnabled"://' -e 's/"//g' || echo "")
        
        if [[ -n "$keyurl" && -n "$serviceurl" && -n "$k8sEnabled" ]]; then
            echo "\"$keyurl\",\"$serviceurl\",\"$k8sEnabled\"" >> "$CSV_OUTPUT"
            PROCESSED_COUNT=$((PROCESSED_COUNT + 1))
            log "Successfully processed: $keyurl"
        else
            log "WARNING: Incomplete API response for $clean_url"
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
    else
        log "ERROR: API call failed for $clean_url"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
}

# Process a single URL
process_url() {
    local current_url="$1"
    
    log "Processing: $current_url"
    
    # Fetch HTML content using headless Chrome
    log "Fetching HTML content with headless Chrome for: $current_url"
    
    local actual_content
    actual_content=$(timeout 60 "$CHROME_CMD" \
        --headless \
        --disable-gpu \
        --disable-software-rasterizer \
        --disable-dev-shm-usage \
        --no-sandbox \
        --disable-extensions \
        --disable-plugins \
        --disable-images \
        --virtual-time-budget=5000 \
        --user-agent="$USER_AGENT" \
        --dump-dom \
        "$current_url" 2>/dev/null)
    
    local chrome_exit_code=$?
    
    if [[ $chrome_exit_code -eq 0 && -n "$actual_content" ]]; then
        log "Successfully fetched HTML (${#actual_content} characters) with Chrome for: $current_url"
        
        # Create local dictionary to prevent duplicate processing within this page
        declare -A page_links_seen
        local links_found=0
        local links_added=0
        
        # Extract and process links
        while IFS= read -r href; do
            [[ -z "$href" ]] && continue
            links_found=$((links_found + 1))

            local absolute_url=$(resolve_url "$current_url" "$href")
            
            # Check if we've already seen this link in this page
            if [[ -v page_links_seen["$absolute_url"] ]]; then
                continue
            fi
            
            # Mark as seen in this page
            page_links_seen["$absolute_url"]=1
            
            # Check if valid and not globally visited
            if is_valid_link "$absolute_url" "$SEED_DOMAIN" && ! is_visited "$absolute_url"; then
                process_api_call "$absolute_url"
                sleep 1
                local next_depth=$((current_depth + 1))
                add_to_queue "$absolute_url" "$next_depth"

                links_added=$((links_added + 1))
                log "Added to queue: $absolute_url"
                declare -p to_visit_by_depth
                log ""
            fi
            
        done < <(echo "$actual_content" | pup 'a attr{href}' 2>/dev/null | grep -v '^$')

        log "Links found: $links_found, Added to queue: $links_added"
        
    else
        log "ERROR: Failed to fetch HTML for $current_url (HTTP: $http_code, curl exit: $curl_exit_code)"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
}

# Main crawler function
crawl() {
    local seed_url="$1"
    SEED_DOMAIN=$(extract_domain "$seed_url")
    
    log "Starting crawl of domain: $SEED_DOMAIN (max depth: $max_depth)"
    log "Seed URL: $seed_url"

    # Initialize with seed URL at depth 0
    process_api_call "$seed_url"
    add_to_queue "$seed_url" 0

    # Process each depth level
    while [[ $current_depth -le $max_depth ]]; do
        # Check if current depth has any URLs
        
        if [[ ! -v to_visit_by_depth[$current_depth] ]] || [[ -z "${to_visit_by_depth[$current_depth]}" ]]; then
            log "No URLs at depth $current_depth, crawling completed early"
            break 
        fi
        
        log "=== Processing depth $current_depth ==="
        
        # Convert space-separated string to array
        local -a urls_at_depth
        read -ra urls_at_depth <<< "${to_visit_by_depth[$current_depth]}"
        log "${urls_at_depth[@]}"
        for url in "${urls_at_depth[@]}"; do
            [[ -z "$url" ]] && continue
            
            # Skip if already visited
            if is_visited "$url"; then
                continue
            fi
            
            # Mark as visited and process
            mark_visited "$url"
            log "Processing depth $current_depth: $url"
            process_url "$url"
            
            sleep 1
        done
        
        # Clear this depth and move to next
        unset to_visit_by_depth[$current_depth]
        log "Completed depth $current_depth. URLs Visited: ${#visited_urls[@]}"
        current_depth=$((current_depth + 1))
    done
}

# Help menu
show_help() {
    cat <<EOF
Web Crawler Script by snegi

Usage:
  $0 <starting_url> [max_depth]

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
  $0 https://www.webmd.com 3

Output:
  - Results are saved to crawl_results.csv
  - All logs are saved to crawler.log

Dependencies:
  - bash (v4+), curl, pup, google-chrome or chromium

For questions or issues, please review the script and logs.
EOF
}

# Display final statistics
show_statistics() {
    echo
    echo "================== CRAWLING COMPLETED =================="
    echo "Domain crawled: $SEED_DOMAIN"
    echo "Total URLs visited: ${#visited_urls[@]}"
    echo "Successful API calls: $PROCESSED_COUNT"
    echo "Failed API calls: $FAILED_COUNT"
    echo
    echo "Max depth crawled: $((current_depth - 1))"
    echo
    echo "Output file: $CSV_OUTPUT"
    echo "The CSV contains the following columns:"
    echo "  - Friendly url: The original URL that was processed"
    echo "  - Microservice url: The service URL returned by the API"
    echo "  - Is k8s enabled?: Whether Kubernetes is enabled for this URL"
    echo
    echo "Log file: $LOG_FILE"
    echo "========================================================="
}

# Global variable to store the final command
CHROME_CMD=""

# Function to detect the available Chrome/Chromium command.
# It prints the command name on success and returns an error code on failure.
detect_chrome() {
    if command -v google-chrome >/dev/null 2>&1; then
        echo "google-chrome"
    elif command -v chromium >/dev/null 2>&1; then
        echo "chromium"
    elif command -v chromium-browser >/dev/null 2>&1; then
        echo "chromium-browser"
    else
        # Return a non-zero exit code to signal failure
        return 1
    fi
}

# Function to check all dependencies
check_dependencies() {
    local missing_deps=()
    
    # Check for curl
    if ! command -v curl >/dev/null 2>&1; then
        missing_deps+=("curl")
    fi
    
    # Check for pup
    if ! command -v pup >/dev/null 2>&1; then
        missing_deps+=("pup")
    fi
    
    # Check for chrome
    if ! CHROME_CMD=$(detect_chrome); then
        missing_deps+=("google-chrome or chromium")
    fi
    log "$CHROME_CMD"
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "ERROR: Missing required dependencies: ${missing_deps[*]}"
        echo "Please install them before running this script."
        exit 1
    fi
    
    echo "✅ All dependencies are satisfied."
    echo "Using browser command: $CHROME_CMD"
}

# Main execution
main() {
    # Help option
    if [[ $# -eq 0 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        show_help
        exit 0
    fi
    # Check arguments
    if [[ $# -lt 2 ]]; then
        echo "Usage: $0 <starting_url> [max_recursion_depth]"
        echo "Example: $0 https://www.webmd.com 3"
        exit 1
    fi
    
    local starting_url="$1"
    
    # Set max depth
    if [[ $# -ge 2 ]]; then
        max_depth="$2"
        if ! [[ "$max_depth" =~ ^[0-9]+$ ]] || [[ $max_depth -lt 0 ]]; then
            echo "ERROR: Max depth must be a non-negative integer"
            exit 1
        fi
    fi

    # Validate URL format
    if [[ ! "$starting_url" =~ ^https?:// ]]; then
        echo "ERROR: URL must start with http:// or https://"
        exit 1
    fi
    
    # Check dependencies
    check_dependencies
    
    # Initialize
    init_csv
    log "Crawler started by snegi at $(date)"
    log "Starting URL: $starting_url"
    
    # Start crawling
    crawl "$starting_url"
    
    # Show final statistics
    show_statistics
}

# Run main function with all arguments
main "$@"