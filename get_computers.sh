#!/bin/bash

#===================================================================================
# Script Name: get_computers.sh
# Description: Retrieves and manages Mac device information from Jamf Pro using
#              Advanced Computer Search groups. Supports various operations including
#              viewing device status, OS distribution, and scheduling updates.
# Author: Mat Griffin
# Version: 1.0
#===================================================================================

#-------------------
# Color Definitions
#-------------------
GREEN='\033[0;32m'
PINK='\033[0;35m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BLUEBOLD='\033[1;34m'
BOLD='\033[1m'
RESET='\033[0m'
VERSION="1.0"
RED='\033[0;31m'
PURPLE='\033[0;34m'

#----------------------
# Global Variables
#----------------------
DEBUG_MODE=false
SEARCH_ID="113"  # Default search ID if none specified
response_global=""  # Stores the main API response
groups_response_global=""  # Stores the groups API response

#----------------------
# Help & Usage Functions
#----------------------
show_help() {
    echo ""
    echo -e "${PURPLE}$(tput bold)Description:$(tput sgr0)${RESET}"
    echo "    This script connects to Jamf Pro and retrieves device information"
    echo "    of Advanced Computer Search group. The default search ID is 113,"
    echo "    but you can specify any valid Jamf Pro Advanced Computer Search ID."
    echo ""
    echo -e "${PURPLE}$(tput bold)Connection Details:$(tput sgr0)${RESET}"
    echo "    On first run or if the connection details are missing or incorrect you"
    echo "    will be required to enter your Jamf Pro URL, API Client ID and Client Secret."
    echo "    The Jamf API Role must have the following privileges:"
    echo "    • Read Advanced Computer Searches"
    echo "    • Read Computers"
    echo "    • Send Computer Remote Command to Download and Install OS X Update"
    echo "    • Read Managed Software Updates"
    echo "    • Create Managed Software Updates"
    echo ""
    echo -e "${PURPLE}$(tput bold)Usage:$(tput sgr0)${RESET}"
    echo "    $(basename "$0") [-d] [-i search_id] [-h]"
    echo ""
    echo -e "${PURPLE}$(tput bold)Options:$(tput sgr0)${RESET}"
    echo "    -d            Enable debug mode for detailed logging"
    echo "    -i search_id  Specify Jamf Pro Advanced Computer Search ID"
    echo "                 (default: 113, example: 276)"
    echo "    -h            Show this help message"
    echo ""
    echo -e "${PURPLE}$(tput bold)Examples:$(tput sgr0)${RESET}"
    echo "    $(basename "$0")             # Run with default search ID 113"
    echo "    $(basename "$0") -d          # Run in debug mode"
    echo "    $(basename "$0") -i 276      # Run with different search ID"
    echo "    $(basename "$0") -d -i 276   # Run in debug mode with custom search ID"

    # Only show prompt if not called from command line
    if [[ "$1" != "cli" ]]; then
        read -p "Press Enter to return to menu..."
    fi
}

usage() {
    show_help "cli"
    exit 0
}

#----------------------
# Command Line Options
#----------------------
# Process command line options first
while getopts "dhi:" opt; do
    case $opt in
        d) DEBUG_MODE=true ;;
        h) usage ;;
        i) SEARCH_ID="$OPTARG" ;;  # Command line argument takes precedence
        \?) usage ;;
    esac
done

#----------------------
# Configuration Files
#----------------------
CREDS_FILE="$(dirname "$0")/.jamf_credentials"  # Stores API credentials and defaults

#----------------------
# Early Function Definitions
#----------------------
debug_log() {
    if [ "$DEBUG_MODE" = true ]; then
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo -e "${RED}🐞 DEBUG: [$timestamp]: $1${RESET}"
    fi
}

GetCredentialsFromUser() {
    echo -e "\n${YELLOW}Please enter your Jamf Pro connection details:${RESET}"
    read -p "Enter Jamf Pro URL (e.g. https://company.jamfcloud.com): " new_url
    read -p "Enter Jamf Pro API Client ID: " new_client_id
    read -p "Enter Jamf Pro API Client Secret: " new_client_secret
    echo ""
    
    # Use existing URL if none provided
    [[ -z "$new_url" ]] && new_url="$jamfpro_url"
    
    # Update global variables
    jamfpro_url="$new_url"
    jamfpro_api_client_id="$new_client_id"
    jamfpro_api_client_secret="$new_client_secret"
    
    # Ask for default search ID if not provided
    if [[ -z "$DEFAULT_SEARCH_ID" ]]; then
        echo -e "\n${YELLOW}No Advanced Computer Search ID is set, if not set this will default to 113.${RESET}"
        read -p "Enter your preferred default Advanced Computer Search ID (e.g. 276): " new_search_id
        DEFAULT_SEARCH_ID="${new_search_id:-113}"
    fi
    
    SEARCH_ID="$DEFAULT_SEARCH_ID"  # Update current session's search ID
    
    # Save new credentials including search ID
    cat > "$CREDS_FILE" << EOF
JAMF_URL="$jamfpro_url"
JAMF_CLIENT_ID="$jamfpro_api_client_id"
JAMF_CLIENT_SECRET="$jamfpro_api_client_secret"
DEFAULT_SEARCH_ID="$DEFAULT_SEARCH_ID"
EOF
    chmod 600 "$CREDS_FILE"
    
    return 0
}

#----------------------
# Validation Functions
#----------------------
ValidateCredentials() {
    if [ "$DEBUG_MODE" = true ]; then
        debug_log "Checking credentials - URL: ${jamfpro_url:+set}, ID: ${jamfpro_api_client_id:+set}, Secret: ${jamfpro_api_client_secret:+set}"
    fi
    
    # Check if any required credential is missing
    if [ -z "$jamfpro_url" ] || [ -z "$jamfpro_api_client_id" ] || [ -z "$jamfpro_api_client_secret" ]; then
        return 1
    fi
    
    return 0
}

#----------------------
# Configuration Loading
#----------------------
# Load and validate credentials
InitializeCredentials() {
    local credentials_valid=false

    if [[ -f "$CREDS_FILE" ]]; then
        source "$CREDS_FILE"
        jamfpro_url="$JAMF_URL"
        jamfpro_api_client_id="$JAMF_CLIENT_ID"
        jamfpro_api_client_secret="$JAMF_CLIENT_SECRET"
        
        # Set default search ID from credentials if available
        if [[ -n "$DEFAULT_SEARCH_ID" ]]; then
            SEARCH_ID="$DEFAULT_SEARCH_ID"
            if [ "$DEBUG_MODE" = true ]; then
                debug_log "Using DEFAULT_SEARCH_ID from credentials: $SEARCH_ID"
            fi
        fi
    fi

    # Validate credentials and prompt if needed
    while ! $credentials_valid; do
        if ValidateCredentials; then
            # Test API connection
            local test_response
            test_response=$(/usr/bin/curl -s -w "\nHTTP_CODE:%{http_code}" \
                --request GET \
                --header "Accept: application/json" \
                "${jamfpro_url}/api/v1/auth/current" || echo "HTTP_CODE:000")
            
            local http_code=$(echo "$test_response" | grep "HTTP_CODE:" | cut -d: -f2)
            
            if [[ "$http_code" == "401" || "$http_code" == "200" ]]; then
                credentials_valid=true
                break
            fi
        fi

        # If we get here, credentials are invalid or connection failed
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                                                                  ║"
    echo "║           💻 Jamf Pro - Get Mac Info Tool                        ║"
    echo "║                                                                  ║"
    echo "║              Version: $VERSION                                        ║"
    echo "║                                                                  ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
        echo -e "${BLUEBOLD}Welcome to the Jamf Pro Get Device Info Tool."
        echo -e "${BLUE}This tool displays Mac info from Jamf Pro Advanced Computer Search Group.\n"
        echo -e "${YELLOW}The connection details required are either not set yet or not valid.${RESET}"
        echo -e "You will need your Jamf Pro URL, a Client ID and Client Secret and an Advanced Computer Search ID."
        echo -e "For more information run with the -h flag."
        echo -e "To force close the tool press control+z anytme."
        
        if ! GetCredentialsFromUser; then
            echo -e "${RED}Failed to get valid credentials. Exiting...${RESET}"
            exit 1
        fi
        
        echo -e "${GREEN}Configuration saved successfully.${RESET}"
    done
}

# Initialize credentials before proceeding
InitializeCredentials

#----------------------
# Command Line Options
#----------------------
usage() {
    echo "Usage: $0 [-d] [-i search_id]"
    echo "  -d: Enable debug mode"
    echo "  -i: Specify custom search ID (default: 113)"
    exit 1
}

# Add argument parsing - this will override SEARCH_ID if -i is used
while getopts "di:" opt; do
    case $opt in
        d) DEBUG_MODE=true ;;
        i)
            SEARCH_ID="$OPTARG"  # Command line argument takes precedence
            if [ "$DEBUG_MODE" = true ]; then
                echo -e "${RED}🐞 DEBUG: Overriding SEARCH_ID from command line: $SEARCH_ID${RESET}"
            fi
            ;;
        \?) usage ;;
    esac
done

#===================================================================================
# Core Functions
#===================================================================================

#----------------------
# UI Helper Functions
#----------------------
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='/-\|'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        # Show only the first character of spinstr
        echo -ne "\r${YELLOW} [${spinstr:0:1}] ${2}${RESET}"
        local spinstr=$temp${spinstr:0:1}
        sleep $delay
    done
    echo -ne "\r"
}

print_header() {
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                                                                  ║"
    echo "║           💻 Jamf Pro - Get Mac Info Tool                        ║"
    echo "║              Advanced Computer Search ID: $SEARCH_ID                    ║"
    echo "║              Version: $VERSION                                        ║"
    echo "║                                                                  ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
      if [ "$DEBUG_MODE" = true ]; then
        echo -e "${RED}🐞 DEBUG: MODE${RESET}"
    fi
    echo -e "${BLUEBOLD}Welcome to the Jamf Pro Get Device Info Tool."
    echo -e "${BLUE}This tool displays Mac info from Jamf Pro Advanced Computer Search Group.\n"
  
    echo ""
}

ShowMenu() {
    echo ""
    echo -e "${PURPLE}Available Actions:${RESET}"
    echo "1. Show OS Version Distribution"
    echo "2. List Outdated Systems (< $FULL_VERSION)"
    echo "3. Show Inactive Machines (No check-in > 30 days)"
    echo "4. Export to CSV"
    echo "5. Search by Username/Email"
    echo "6. Show Table Again"
    echo "7. Select Different Advanced Computer Search Group (Experimental)"
    echo "8. Change Default Search ID (currently $DEFAULT_SEARCH_ID)"
    echo "h. Help"
    echo "q. Quit"
    echo ""
    read -p "Select an option: " choice
    
    # Convert to lowercase
    choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
    
    case $choice in
        [1-3]) return "$choice" ;;
        4) return 5 ;;  # Search is now option 4
        5) return 4 ;;  # Export is now option 5
        [6-8]) return "$choice" ;;
        h|H) return 9 ;;  # Help is now 9
        q|Q)
            InvalidateToken
            echo ""
            echo "Exiting..."
            exit 0
            ;;
        *) echo "Invalid option. Please try again."; return 0 ;;
    esac
}

PrintTableHeader() {
    local width=140  # Adjusted total width for all columns and separators
    printf '%*s\n' "$width" '' | tr ' ' -
    echo -ne "${GREEN}"
    printf "%-8s  %-15s  %-35s  %-8s  %-15s  %-20s  %-25s\n" \
        "ID" "Serial No." "Email Address" "macOS" "Status" "Last Check-in" "Model"
    echo -ne "${RESET}"
    printf '%*s\n' "$width" '' | tr ' ' -
}

#----------------------
# API Functions
#----------------------
GetJamfProAPIToken() {
    # Validate credentials before attempting to get token
    if ! ValidateCredentials; then
        echo -e "${RED}Error: Missing or invalid credentials${RESET}"
        return 1
    fi
    
    # This function uses the API client ID and client ID secret to get a new bearer token for API authentication.
    local token_response
    token_response=$(/usr/bin/curl -s -w "\nHTTP_CODE:%{http_code}" -X POST \
        "$jamfpro_url/api/oauth/token" \
        --header 'Content-Type: application/x-www-form-urlencoded' \
        --data-urlencode "client_id=$jamfpro_api_client_id" \
        --data-urlencode 'grant_type=client_credentials' \
        --data-urlencode "client_secret=$jamfpro_api_client_secret")
    
    local http_code=$(echo "$token_response" | grep "HTTP_CODE:" | cut -d: -f2)
    local response=$(echo "$token_response" | grep -v "HTTP_CODE:")
    
    case "$http_code" in
        200)
            if [[ $(/usr/bin/sw_vers -productVersion | awk -F . '{print $1}') -lt 12 ]]; then
                api_token=$(echo "$response" | python -c 'import sys, json; print json.load(sys.stdin)["access_token"]')
            else
                api_token=$(echo "$response" | plutil -extract access_token raw -)
            fi
            return 0
            ;;
        401)
            echo -e "${RED}Error: Could not authenticate to Jamf Pro.${RESET}"
            return 1
            ;;
        429)
            echo -e "${RED}Error: Too many requests - rate limit exceeded${RESET}"
            echo -e "${YELLOW}Please wait a few minutes before trying again${RESET}"
            return 1
            ;;
        000)
            echo -e "${RED}Error: Could not authenticate to Jamf Pro."
            echo -e "${YELLOW}Either the connection details are missing or incorrect.${RESET}"
            return 1
            ;;
        *)
            echo -e "${RED}Error: Could not authenticate to Jamf Pro."
            echo -e "${YELLOW}Either the connection details are missing or incorrect.${RESET}"
            return 1
            ;;
    esac
}

APITokenValidCheck() {
    # Verify that API authentication is using a valid token by running an API command
    # which displays the authorization details associated with the current API user.
    # The API call will only return the HTTP status code.

    api_authentication_check=$(/usr/bin/curl --write-out %{http_code} --silent --output /dev/null "${jamfpro_url}/api/v1/auth" --request GET --header "Authorization: Bearer ${api_token}")
}

#----------------------
# Data Processing Functions
#----------------------
get_latest_macos() {
    local latest_version
    local url="https://sofafeed.macadmins.io/v1/macos_data_feed.json"
    local debug_dir="$HOME/jamf_debug"
    
    # Fetch JSON data first
    local json_data
    json_data=$(curl -s "$url")
    
    # Get version first and store it
    latest_version=$(echo "$json_data" | jq -r '.OSVersions[0].Latest.ProductVersion')
    
    if [[ -z "$latest_version" ]]; then
        echo "ERROR: Failed to parse version from JSON" >&2
        latest_version="15.3.0"  # Fallback version
    fi
    
    # Handle debug output without redirecting to file
    if [ "$DEBUG_MODE" = true ]; then
        mkdir -p "$debug_dir"
        echo "$json_data" > "$debug_dir/macos_feed.json"
        local size=$(wc -c < "$debug_dir/macos_feed.json")
        local build=$(echo "$json_data" | jq -r '.OSVersions[0].Latest.Build')
        local date=$(echo "$json_data" | jq -r '.OSVersions[0].Latest.PostingDate')
        
        # Save debug info to log file but also display it
        {
            echo -e "${RED}🐞 DEBUG: Saved JSON response to $debug_dir/macos_feed.json${RESET}"
            echo -e "${RED}🐞 DEBUG: Response size: $size bytes${RESET}"
            echo -e "${RED}🐞 DEBUG: Latest macOS: $latest_version (Build: $build)${RESET}"
            echo -e "${RED}🐞 DEBUG: Released: $date${RESET}"
        } | tee -a "$debug_dir/debug.log" >&2
    fi
    
    # Return only the version number
    echo "$latest_version"
}

ValidateResponse() {
    local resp="$1"
    if [[ -n "$resp" ]] && echo "$resp" | jq -e '.advanced_computer_search.computers' >/dev/null 2>&1; then
        return 0
    else
        if [ "$DEBUG_MODE" = true ]; then
            echo -e "${RED}🐞 DEBUG: Invalid response detected${RESET}"
            echo -e "${RED}🐞 DEBUG: Response: $resp${RESET}"
        fi
        return 1
    fi
}

#----------------------
# Main Feature Functions
#----------------------
GetAdvancedSearchGroup() {
    local search_id="$SEARCH_ID"
    local temp_response
    local width=140
    
    echo "     Fetching Advanced Search Group $search_id..."
    
    if [ "$DEBUG_MODE" = true ]; then
        debug_log "Starting Advanced Search Group fetch for ID: $search_id"
        local start=$SECONDS
        
        # Store raw response with debug info
        local raw_response
        raw_response=$(/usr/bin/curl -s -w "\nHTTP_CODE:%{http_code}\nTIME:%{time_total}\nSIZE:%{size_download}\n" \
            --request GET \
            --header "Authorization: Bearer ${api_token}" \
            --header "Accept: application/json" \
            "${jamfpro_url}/JSSResource/advancedcomputersearches/id/${search_id}")
        
        # Extract debug info
        local http_code=$(echo "$raw_response" | grep "HTTP_CODE:" | cut -d: -f2)
        local time_total=$(echo "$raw_response" | grep "TIME:" | cut -d: -f2)
        local size=$(echo "$raw_response" | grep "SIZE:" | cut -d: -f2)
        
        # Extract just the JSON response
        temp_response=$(echo "$raw_response" | grep -v "HTTP_CODE:" | grep -v "TIME:" | grep -v "SIZE:")
        
        local duration=$((SECONDS - start))
        debug_log "Operation took ${duration} seconds"
        log_api_call "$jamfpro_url" "GET" "$http_code" "$size" "$time_total" "$temp_response"
    else
        # Non-debug mode remains unchanged
        if temp_response=$(get_cached_data "search_$search_id"); then
            echo "     Using cached data..."
        else
            echo "     Fetching new data..."
            temp_response=$(/usr/bin/curl -s \
                --request GET \
                --header "Authorization: Bearer ${api_token}" \
                --header "Accept: application/json" \
                "${jamfpro_url}/JSSResource/advancedcomputersearches/id/${search_id}")
                
            if echo "$temp_response" | jq -e '.advanced_computer_search.computers' >/dev/null 2>&1; then
                cache_data "search_$search_id" "$temp_response"
            fi
        fi
    fi
    
    if ValidateResponse "$temp_response"; then
        response="$temp_response"
        response_global="$temp_response"
        
        echo "     Success! Processing data into table format..."
        echo ""
        # Add title before table
        echo -e "${PURPLE}Advanced Computer Search Results (ID: $search_id)${RESET}"
        PrintTableHeader
        
        # Restore original table output without colors
        echo "$response" | jq -r '.advanced_computer_search.computers[] | [
            .id,
            .Serial_Number,
            .Email_Address,
            .Operating_System_Version,
            .Last_Check_in,
            .Model
        ] | @tsv' | while IFS=$'\t' read -r id serial email os_version last_checkin model; do
            status="Active"
            
            # Convert date string to epoch for comparison
            checkin_epoch=$(date -j -f "%Y-%m-%d %H:%M:%S" "${last_checkin}" "+%s" 2>/dev/null)
            current_time=$(date +%s)
            
            if [[ -n "$checkin_epoch" ]]; then
                if (( current_time - checkin_epoch > 2592000 )); then
                    status="Inactive"
                fi
            else
                status="Unknown"
            fi
            
            # Truncate long strings as before...
            
            printf "%-8s | %-15s | %-35s | %-8s | %-15s | %-20s | %-25s\n" \
                "$id" \
                "$serial" \
                "$email" \
                "$os_version" \
                "$status" \
                "$last_checkin" \
                "$model"
        done | sort -n    # Sort by ID
        
        # Add footer line with explicit width value
        printf '%*s\n' "140" '' | tr ' ' -
        
        # Simplified summary section with purple text
        total_count=$(echo "$response" | jq '.advanced_computer_search.computers | length')
        
       # echo -e "${PURPLE}Summary:${RESET}"
       # echo -e "${PURPLE}--------${RESET}"
        echo -e "${PURPLE}Total Devices: $total_count${RESET}"
        
        # Store response globally for other functions to use
        response_global="$response"
        
        # Menu loop
        while true; do
            ShowMenu
            choice=$?
            case $choice in
                1) ShowOSDistribution ;;
                2) ListOutdatedSystems ;;
                3) ShowInactiveMachines ;;
                4) SearchByUser ;;
                5) ExportToCSV ;;
                6) GetAdvancedSearchGroup ;;
                7) ListAdvancedSearchGroups ;;
                8) ChangeDefaultSearchID ;;
                9) show_help ;;  # Help menu option
                *) echo "Invalid option. Please try again." ;;
            esac
        done
    else
        echo "Error: Failed to get Advanced Computer Search Group data. Retrying..."
        sleep 1
        GetJamfProAPIToken  # Refresh token
        APITokenValidCheck
        if [[ "$api_authentication_check" == "200" ]]; then
            GetAdvancedSearchGroup  # Retry once
        else
            echo "Error: API authentication failed during retry"
            exit 1
        fi
    fi
}

ListAdvancedSearchGroups() {
    echo "Fetching available Advanced Computer Search Groups..."

    # Validate token first
    APITokenValidCheck
    if [[ "$api_authentication_check" != "200" ]]; then
        if [ "$DEBUG_MODE" = true ]; then
            debug_log "Token expired, refreshing..."
        fi
        GetJamfProAPIToken
        APITokenValidCheck
        if [[ "$api_authentication_check" != "200" ]]; then
            echo "Error: Failed to refresh API token"
            return 1
        fi
    fi

    # Always fetch fresh data for groups list
    groups_response_global=$(/usr/bin/curl -s -w "\nHTTP_CODE:%{http_code}" \
        --request GET \
        --header "Authorization: Bearer ${api_token}" \
        --header "Accept: application/json" \
        "${jamfpro_url}/JSSResource/advancedcomputersearches")

    local http_code=$(echo "$groups_response_global" | grep "HTTP_CODE:" | cut -d: -f2)
    groups_response_global=$(echo "$groups_response_global" | grep -v "HTTP_CODE:")

    if [[ "$http_code" == "200" ]] && [[ -n "$groups_response_global" ]] && echo "$groups_response_global" | jq -e . >/dev/null 2>&1; then
        if [ "$DEBUG_MODE" = true ]; then
            debug_log "Groups fetch successful (HTTP:$http_code)"
        fi
        
        # Store groups data for reuse
        local groups_list
        groups_list=$(echo "$groups_response_global" | jq -r '.advanced_computer_searches[] | "\(.id): \(.name)"' | sort -n)
        
        if [[ -n "$groups_list" ]]; then
            echo -e "\n${PURPLE}Available Advanced Computer Search Groups:${RESET}"
            echo "-----------------------------------------"
            echo "$groups_list"
            echo ""
            
            read -p "Enter the ID of the group you want to view: " selected_id
            if [[ -n "$selected_id" ]]; then
                SEARCH_ID="$selected_id"
                echo "Switching to Advanced Search Group $SEARCH_ID..."
                response=""
                response_global=""
                GetAdvancedSearchGroup
            fi
        else
            echo "No Advanced Search Groups found."
        fi
    else
        echo "Error: Failed to fetch Advanced Computer Search Groups (HTTP:$http_code)"
        if [ "$DEBUG_MODE" = true ]; then
            debug_log "Failed response: $groups_response_global"
        fi
        groups_response_global=""
        return 1
    fi
}

ShowOSDistribution() {
    if ! ValidateResponse "$response"; then
        echo "Error: Invalid data, refreshing..."
        GetAdvancedSearchGroup
        return
    fi
    echo ""
    echo -e "${PURPLE}macOS Version Distribution:${RESET}"
    echo "-------------------------"
    echo "$response" | jq -r '.advanced_computer_search.computers[] | .Operating_System_Version' | sort | uniq -c | sort -rn |
    while read -r count version; do
        printf "%-10s: %s devices\n" "macOS $version" "$count"
    done
}

ListOutdatedSystems() {
    if ! ValidateResponse "$response"; then
        echo "Error: Invalid data, refreshing..."
        GetAdvancedSearchGroup
        return
    fi
    # Create array to store outdated device IDs
    local outdated_ids=()
    
    echo ""
    echo -e "${PURPLE}Outdated Systems (< $FULL_VERSION):${RESET}"
    PrintTableHeader
    
    while IFS=$'\t' read -r id serial email version last_checkin model; do
        if [ -n "$id" ]; then
            outdated_ids+=("$id")
            status="Outdated"
            
            # Truncate long strings as before
            if [ ${#model} -gt 25 ]; then
                model="${model:0:22}..."
            fi
            if [ ${#email} -gt 35 ]; then
                email="${email:0:32}..."
            fi
            
            printf "%-8s | %-15s | %-35s | %-8s | %-15s | %-20s | %-25s\n" \
                "$id" \
                "$serial" \
                "$email" \
                "$version" \
                "$status" \
                "$last_checkin" \
                "$model"
        fi
    done < <(echo "$response" | jq -r --arg version "$FULL_VERSION" '
        .advanced_computer_search.computers[] | 
        select(
            (.Operating_System_Version | split(".") | map(tonumber)) as $current |
            ($version | split(".") | map(tonumber)) as $latest |
            ($current | if length == 2 then . + [0] else . end) as $normalized |
            ($normalized[0] < $latest[0]) or
            ($normalized[0] == $latest[0] and $normalized[1] < $latest[1]) or
            ($normalized[0] == $latest[0] and $normalized[1] == $latest[1] and ($normalized[2] // 0) < $latest[2])
        ) | [.id, .Serial_Number, .Email_Address, .Operating_System_Version, .Last_Check_in, .Model] | @tsv
    ' | sort -n)
    
    # Add footer line
    printf '%*s\n' "$width" '' | tr ' ' -
    
    # If we found outdated devices, offer to update them
    if [ ${#outdated_ids[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}Found ${#outdated_ids[@]} outdated device(s)${RESET}"
        echo -e "Would you like to send DDM update commands to these devices?"
        read -p "Send updates? (y/n): " should_update
        
        if [[ $should_update =~ ^[Yy]$ ]]; then
            SendDDMUpdate "${outdated_ids[@]}"
        fi
    else
        echo -e "\n${GREEN}No outdated devices found.${RESET}"
    fi
}

ShowInactiveMachines() {
    if ! ValidateResponse "$response"; then
        echo "Error: Invalid data, refreshing..."
        GetAdvancedSearchGroup
        return
    fi
    echo ""
    echo -e "${PURPLE}Inactive Machines (No check-in > 30 days):${RESET}"
    PrintTableHeader
    
    current_time=$(date +%s)
    echo "$response" | jq -r '.advanced_computer_search.computers[] | 
        select(.Last_Check_in) | 
        [.id, .Serial_Number, .Email_Address, .Operating_System_Version, .Last_Check_in, .Model] | @tsv' |
    while IFS=$'\t' read -r id serial email version last_checkin model; do
        checkin_epoch=$(date -j -f "%Y-%m-%d %H:%M:%S" "${last_checkin}" "+%s" 2>/dev/null)
        if [[ -n "$checkin_epoch" && $(( current_time - checkin_epoch )) -gt 2592000 ]]; then
            status="Inactive"
            
            # Truncate long model names and emails as in main table
            if [ ${#model} -gt 25 ]; then
                model="${model:0:22}..."
            fi
            if [ ${#email} -gt 35 ]; then
                email="${email:0:32}..."
            fi
            
            printf "%-8s | %-15s | %-35s | %-8s | %-15s | %-20s | %-25s\n" \
                "$id" \
                "$serial" \
                "$email" \
                "$version" \
                "$status" \
                "$last_checkin" \
                "$model"
        fi
    done | sort -n
    
    # Add footer line
    printf '%*s\n' "$width" '' | tr ' ' -
}

ExportToCSV() {
    # Get user's Downloads folder
    downloads_dir="$HOME/Downloads"
    local csv_file="$downloads_dir/jamf_inventory_$(date +%Y%m%d_%H%M%S).csv"
    
    echo "ID,Serial Number,Email Address,macOS Version,Status,Last Check-in,Model" > "$csv_file"
    echo "$response" | jq -r '.advanced_computer_search.computers[] | [.id, .Serial_Number, .Email_Address, .Operating_System_Version, "Active", .Last_Check_in, .Model] | @csv' >> "$csv_file"
    echo "Exported to $csv_file"
}

SearchByUser() {
    echo ""
    read -p "Enter username or email to search: " search_term
    echo ""
    echo -e "${PURPLE}Search Results for:${RESET} ${BOLD}$search_term${RESET}"
    PrintTableHeader
    
    echo "$response" | jq -r --arg search "$search_term" '.advanced_computer_search.computers[] | select(.Email_Address | ascii_downcase | contains($search | ascii_downcase)) | [.id, .Serial_Number, .Email_Address, .Operating_System_Version, .Last_Check_in, .Model] | @tsv' |
    while IFS=$'\t' read -r id serial email version last_checkin model; do
        # Set status based on last check-in
        status="Active"
        checkin_epoch=$(date -j -f "%Y-%m-%d %H:%M:%S" "${last_checkin}" "+%s" 2>/dev/null)
        current_time=$(date +%s)
        if [[ -n "$checkin_epoch" && $(( current_time - checkin_epoch )) -gt 2592000 ]]; then
            status="Inactive"
        fi
        
        # Truncate long strings
        if [ ${#model} -gt 25 ]; then
            model="${model:0:22}..."
        fi
        if [ ${#email} -gt 35 ]; then
            email="${email:0:32}..."
        fi
        
        printf "%-8s | %-15s | %-35s | %-8s | %-15s | %-20s | %-25s\n" \
            "$id" \
            "$serial" \
            "$email" \
            "$version" \
            "$status" \
            "$last_checkin" \
            "$model"
    done
    
    # Add footer line with same width as main table
    printf '%*s\n' "140" '' | tr ' ' -
}

#----------------------
# Update Management
#----------------------
SendDDMUpdate() {
    local device_ids=("$@")
    local total=${#device_ids[@]}
    local success_count=0
    local fail_count=0
    local delay=5  # Base delay in seconds between devices
    local retry_delay=30  # Delay when hitting rate limit
    local max_retries=3  # Maximum retries per device
    
    if [ ${#device_ids[@]} -eq 0 ]; then
        echo "No devices selected for update."
        return 1
    fi

    # Get scheduled time from user
    local schedule_time
    while true; do
        echo -e "\n${YELLOW}Enter scheduled date and time for the update (format: YYYY-MM-DD HH:MM)${RESET}"
        echo -e "${YELLOW}Example: 2025-02-14 03:30 for February 13th, 20252 at 03:30 AM${RESET}"
        read -p "Schedule: " user_datetime
        
        # Validate and convert the date format
        if [[ $user_datetime =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}$ ]]; then
            schedule_time="${user_datetime}:00"  # Add seconds
            # Validate the date is valid using date command
            if date -j -f "%Y-%m-%d %H:%M:%S" "$schedule_time" >/dev/null 2>&1; then
                schedule_time=$(date -j -f "%Y-%m-%d %H:%M:%S" "$schedule_time" "+%Y-%m-%dT%H:%M:%S")
                break
            fi
        fi
        echo -e "${RED}Invalid date format. Please use YYYY-MM-DD HH:MM${RESET}"
    done

    echo -e "\n${PURPLE}Sending DDM update commands to $total devices...${RESET}"
    echo -e "${YELLOW}Update scheduled for: $schedule_time${RESET}"
    
    # Validate token first
    APITokenValidCheck
    if [[ "$api_authentication_check" != "200" ]]; then
        if [ "$DEBUG_MODE" = true ]; then
            debug_log "Token expired, refreshing..."
        fi
        GetJamfProAPIToken
        APITokenValidCheck
        if [[ "$api_authentication_check" != "200" ]]; then
            echo -e "${RED}Failed to refresh API token${RESET}"
            return 1
        fi
    fi
    
    for id in "${device_ids[@]}"; do
        local retry_count=0
        local success=false
        
        while [[ $retry_count -lt $max_retries && $success == false ]]; do
            echo -ne "\rProcessing device ID: $id (Attempt $((retry_count + 1))/${max_retries})..."
            
            # Prepare the JSON payload - without specificVersion field
            local payload="{\"devices\":[{\"objectType\":\"COMPUTER\",\"deviceId\":\"${id}\"}],\"config\":{\"updateAction\":\"DOWNLOAD_INSTALL_SCHEDULE\",\"versionType\":\"LATEST_ANY\",\"forceInstallLocalDateTime\":\"${schedule_time}\"}}"
            
            if [ "$DEBUG_MODE" = true ]; then
                echo -e "\n${RED}🐞 DEBUG: Sending DDM update for device $id${RESET}"
                echo -e "${RED}🐞 DEBUG: API URL: ${jamfpro_url}/api/v1/managed-software-updates/plans${RESET}"
                echo -e "${RED}🐞 DEBUG: Payload:${RESET}"
                echo "$payload" | jq '.'
            fi
            
            # Send the DDM command
            local response
            response=$(/usr/bin/curl -s -w "\nHTTP_CODE:%{http_code}" \
                --request POST \
                --url "${jamfpro_url}/api/v1/managed-software-updates/plans" \
                --header "Authorization: Bearer ${api_token}" \
                --header "accept: application/json" \
                --header "content-type: application/json" \
                --data "$payload" \
                2>&1)
            
            local http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d: -f2)
            response=$(echo "$response" | grep -v "HTTP_CODE:")
            
            if [ "$DEBUG_MODE" = true ]; then
                echo -e "${RED}🐞 DEBUG: HTTP Response Code: $http_code${RESET}"
                echo -e "${RED}🐞 DEBUG: Response Body:${RESET}"
                if [[ -n "$response" ]]; then
                    echo "$response" | jq '.' 2>/dev/null || echo "$response"
                fi
            fi
            
            if [[ "$http_code" == "201" || "$http_code" == "200" ]]; then
                success=true
                ((success_count++))
                if [ "$DEBUG_MODE" = true ]; then
                    echo -e "${RED}🐞 DEBUG: Successfully sent update command${RESET}"
                fi
            elif [[ "$http_code" == "429" ]]; then
                echo -e "\n${YELLOW}Rate limit hit, waiting ${retry_delay}s before retry...${RESET}"
                sleep $retry_delay
                ((retry_count++))
            else
                if [[ "$http_code" == "401" ]]; then
                    echo -e "\n${YELLOW}Token expired, refreshing...${RESET}"
                    GetJamfProAPIToken
                    ((retry_count++))
                else
                    success=false
                    break
                fi
            fi
        done
        
        if [[ $success == false ]]; then
            ((fail_count++))
            echo -e "\n${RED}Failed to send update command to device $id after $max_retries attempts${RESET}"
        fi
        
        # Add base delay between devices to prevent rate limiting
        if [ $((success_count + fail_count)) -lt $total ]; then
            echo -e "\n${YELLOW}Waiting ${delay}s before next device...${RESET}"
            sleep $delay
        fi
    done
    
    echo -e "\n\n${GREEN}Update Command Results:${RESET}"
    echo "Successfully sent: $success_count"
    echo "Failed: $fail_count"
    echo "Total processed: $total"
}

ChangeDefaultSearchID() {
    echo -e "\n${PURPLE}Change Default Search ID${RESET}"
    echo -e "Current default Search ID: ${YELLOW}${DEFAULT_SEARCH_ID:-113}${RESET}"
    read -p "Enter new default Search ID: " new_default_id
    
    if [[ -n "$new_default_id" && "$new_default_id" =~ ^[0-9]+$ ]]; then
        if [[ -f "$CREDS_FILE" ]]; then
            # Create backup
            cp "$CREDS_FILE" "${CREDS_FILE}.backup"
            
            # Check if DEFAULT_SEARCH_ID line exists
            if grep -q "^DEFAULT_SEARCH_ID=" "$CREDS_FILE"; then
                # Update existing line
                sed -i '' "s/^DEFAULT_SEARCH_ID=.*$/DEFAULT_SEARCH_ID=\"$new_default_id\"/" "$CREDS_FILE"
            else
                # Add new line if it doesn't exist
                echo "DEFAULT_SEARCH_ID=\"$new_default_id\"" >> "$CREDS_FILE"
            fi
            
            # Update current session
            DEFAULT_SEARCH_ID="$new_default_id"
            echo -e "${GREEN}Default Search ID updated successfully to: $new_default_id${RESET}"
        else
            # Create new credentials file with all required fields
            cat > "$CREDS_FILE" << EOF
JAMF_URL="$jamfpro_url"
JAMF_CLIENT_ID="$jamfpro_api_client_id"
JAMF_CLIENT_SECRET="$jamfpro_api_client_secret"
DEFAULT_SEARCH_ID="$new_default_id"
EOF
            chmod 600 "$CREDS_FILE"
            DEFAULT_SEARCH_ID="$new_default_id"
            echo -e "${GREEN}Default Search ID set to: $new_default_id${RESET}"
        fi
        
        # Ask if user wants to switch to the new default now
        read -p "Would you like to switch to this Search ID now? (y/n): " should_switch
        if [[ $should_switch =~ ^[Yy]$ ]]; then
            SEARCH_ID="$new_default_id"
            response=""
            response_global=""
            GetAdvancedSearchGroup
        fi
    else
        echo -e "${RED}Error: Invalid Search ID. Please enter a valid number.${RESET}"
    fi
}

#----------------------
# Utility Functions
#----------------------
measure_time() {
    local start=$SECONDS
    "$@"
    local duration=$((SECONDS - start))
    debug_log "Operation took ${duration} seconds"
}

log_api_call() {
    if [ "$DEBUG_MODE" = true ]; then
        local debug_dir="$HOME/jamf_debug"
        mkdir -p "$debug_dir"
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local log_file="$debug_dir/api_${timestamp}.log"
        {
            echo "URL: $1"
            echo "Method: $2"
            echo "Response Code: $3"
            echo "Response Size: $4"
            echo "Response Time: $5"
            echo "Response Body:"
            echo "$6"
        } > "$log_file"
        debug_log "API call logged to $log_file"
    fi
}

cache_data() {
    local cache_dir="$HOME/.jamf_cache"
    mkdir -p "$cache_dir"
    echo "$2" > "$cache_dir/$1.cache"
}

get_cached_data() {
    local cache_dir="$HOME/.jamf_cache"
    local cache_file="$cache_dir/$1.cache"
    if [[ -f "$cache_file" && $(($(date +%s) - $(stat -f %m "$cache_file"))) -lt 300 ]]; then
        # Validate cached data before returning it
        local cached_content
        cached_content=$(cat "$cache_file")
        if echo "$cached_content" | jq -e '.advanced_computer_search.computers' >/dev/null 2>&1; then
            echo "$cached_content"
            return 0
        else
            # Invalid cache data - remove it
            rm -f "$cache_file"
            return 1
        fi
    fi
    return 1
}

#----------------------
# Credential Management
#----------------------
InvalidateToken() {
    # First clear any existing output
    echo -ne "\033[2K\r"
    
    # Show spinner without message
    (sleep 0.5) &
    local pid=$!
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        for s in "/" "-" "\\" "|"; do
            echo -ne "\r${YELLOW} [$s] Invalidating token${RESET}"
            sleep 0.1
        done
    done
    
    # Make the API call and capture response status
    local response
    local http_code
    response=$(/usr/bin/curl -s -w "\nHTTP_CODE:%{http_code}" \
        -X POST \
        "${jamfpro_url}/api/v1/auth/invalidate-token" \
        --header "Authorization: Bearer ${api_token}")
    
    http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d: -f2)
    response=$(echo "$response" | grep -v "HTTP_CODE:")
    
    # Clear spinner line and show final message
    echo -ne "\033[2K\r"
    echo -n "API token invalidated"
    
    # Add debug output on new line if needed
    if [ "$DEBUG_MODE" = true ]; then
        echo ""  # New line before debug output
        debug_log "Token invalidation response:(HTTP:$http_code)"
    fi
}

# Add the show_help function
show_help() {
    echo ""
    echo -e "${PURPLE}$(tput bold)Description:$(tput sgr0)${RESET}"
    echo "    This script connects to Jamf Pro and retrieves device information"
    echo "    of Advanced Computer Search group. The default search ID is 113,"
    echo "    but you can specify any valid Jamf Pro Advanced Computer Search ID."
    echo ""
     echo -e "${PURPLE}$(tput bold)Connection Details:$(tput sgr0)${RESET}"
    echo "    On first run or if the connection details are missing or incorrect you"
    echo "    will be required to enter your Jamf Pro URL, API Client ID and Client Secret."
    echo "    The Jamf API Role must have the following privileges:"
    echo "    • Read Advanced Computer Searches"
    echo "    • Read Computers"
    echo "    • Send Computer Remote Command to Download and Install OS X Update"
    echo "    • Read Managed Software Updates"
    echo "    • Create Managed Software Updates"
    echo ""
    echo -e "${PURPLE}$(tput bold)Usage:$(tput sgr0)${RESET}"
    echo "    $(basename "$0") [-d] [-i search_id] [-h]"
    echo ""
    echo -e "${PURPLE}$(tput bold)Options:$(tput sgr0)${RESET}"
    echo "    -d            Enable debug mode for detailed logging"
    echo "    -i search_id  Specify Jamf Pro Advanced Computer Search ID"
    echo "                 (default: 113, example: 276)"
    echo "    -h            Show this help message"
    echo ""
    echo -e "${PURPLE}$(tput bold)Examples:$(tput sgr0)${RESET}"
    echo "    $(basename "$0")             # Run with default search ID 113"
    echo "    $(basename "$0") -d          # Run in debug mode"
    echo "    $(basename "$0") -i 276      # Run with different search ID"
    echo "    $(basename "$0") -d -i 276   # Run in debug mode with custom search ID"
    echo ""
    read -p "Press Enter to return to menu..."
}

#===================================================================================
# Main Script Execution
#===================================================================================
# Load credentials
if [[ -f "$CREDS_FILE" ]]; then
    source "$CREDS_FILE"
    jamfpro_url="$JAMF_URL"
    jamfpro_api_client_id="$JAMF_CLIENT_ID"
    jamfpro_api_client_secret="$JAMF_CLIENT_SECRET"
    # Only override SEARCH_ID if it wasn't specified via command line
    if [[ -n "$DEFAULT_SEARCH_ID" && -z "$SEARCH_ID" ]]; then
        SEARCH_ID="$DEFAULT_SEARCH_ID"
    fi
fi

# If SEARCH_ID is still empty, set default
[[ -z "$SEARCH_ID" ]] && SEARCH_ID="113"

# Initialize script
clear
print_header

# Show initializing with spinner for 2 seconds
(sleep 1.5) & spinner $! "Initializing"
spinner $! ""  # Pass the PID to spinner
echo "     Initialization complete"
echo ""

# Continue with rest of script - Fix the duplicate if block
(sleep 1) &  # Background process that will run for 1 second
spinner $! ""  # Pass the PID to spinner
echo " [/] Checking latest macOS version....."
LATEST_MACOS_VERSION=$(get_latest_macos)
if [ -n "$LATEST_MACOS_VERSION" ]; then
    echo -e "     ${BLUE}Latest macOS public release:${NC} ${BLUEBOLD}${LATEST_MACOS_VERSION}${NC}"
    # Store full version for comparison
    FULL_VERSION="$LATEST_MACOS_VERSION"
    MAJOR_VERSION=$(echo "$LATEST_MACOS_VERSION" | cut -d. -f1)
    MINOR_VERSION=$(echo "$LATEST_MACOS_VERSION" | cut -d. -f2)
    PATCH_VERSION=$(echo "$LATEST_MACOS_VERSION" | cut -d. -f3)
else
    echo "     Error fetching macOS version, using fallback version 15.3.1"
    FULL_VERSION="15.3.1"
    MAJOR_VERSION=15
    MINOR_VERSION=3
    PATCH_VERSION=1
fi

# Handle authentication
(sleep 1) &  # Background process that will run for 1 second
spinner $! ""  # Pass the PID to spinner
echo " [|] Connecting to Jamf Pro..."

# Define Jamf Pro credentials
# Moved to .jamf_credentials file
#jamfpro_url=""
#jamfpro_api_client_id=""
#jamfpro_api_client_secret=""

# Remove trailing slash from URL
jamfpro_url=${jamfpro_url%%/}

echo " [/] Acquiring API token..."
if ! GetJamfProAPIToken; then
    while true; do
        read -p "Would you like to enter new connection details? (y/n): " should_retry
        if [[ $should_retry =~ ^[Yy]$ ]]; then
            if GetCredentialsFromUser; then
                (sleep 2) &
                spinner $! ""
                echo " [|] Getting list of computers from Jamf Pro..."
                echo ""
                GetAdvancedSearchGroup
                break
            fi
        else
            echo "Exiting..."
            exit 1
        fi
    done
else
    echo "     Jamf Pro API token acquired successfully"
    if [ "$DEBUG_MODE" = true ]; then
        echo -e "${RED}🐞 DEBUG: API Token: ${api_token}${RESET}"
    fi
    (sleep 2) &
    spinner $! ""
    echo " [|] Getting list of computers from Jamf Pro..."
    echo ""
    GetAdvancedSearchGroup
fi

