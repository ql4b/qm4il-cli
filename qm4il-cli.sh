#!/bin/bash

[ -f "$HOME/.qm4ilrc" ] && source "$HOME/.qm4ilrc"

# Helper functions
_qm4il_request() {
    local resource="$1"
    shift
    
    if [ -z "$Qm4ilApiKey" ]; then
        echo "Missing API key. Please set 'Qm4ilApiKey' in ~/.qm4ilrc or export it." >&2
        return 1
    fi
    
    if [ -z "$resource" ]; then
        echo "Path is required" >&2
        return 1
    fi
    
    local -a curl_args=(
        "--silent"
        "--location"
        "$Qm4ilApiEndpoint/$resource"
    )
    
    # Add headers
    if [ -n "$Qm4ilApiKey" ]; then
        curl_args+=("--header" "X-Api-Key: $Qm4ilApiKey")
    fi
    
    # Add additional arguments
    curl_args+=("$@")
    
    curl "${curl_args[@]}" | jq
}

qm4il_inboxes() {
    _qm4il_request "inboxes" "$@"
}

qm4il_account() {
    _qm4il_request "me" "$@"
}

qm4il_me() {
    qm4il_account "$@"
}

qm4il_create_inbox() {
    local arg1="${1:-}"
    local inbox_name="${2:-}"
    local fqdn=""
    
    # If first argument is an email, split into user and domain
    if [[ "$arg1" =~ ^[^@]+@[^@]+$ ]]; then
        inbox_name="${arg1%@*}"
        fqdn="${arg1#*@}"
    else
        fqdn="$arg1"
    fi
    
    local -a jq_args=()
    [ -n "$fqdn" ] && jq_args+=("--arg" "fqdn" "$fqdn")
    [ -n "$inbox_name" ] && jq_args+=("--arg" "inboxName" "$inbox_name")
    
    local body=""
    if [ -n "$fqdn" ] && [ -n "$inbox_name" ]; then
        body=$(jq -n "${jq_args[@]}" '{fqdn: $fqdn, inboxName: $inboxName}')
    elif [ -n "$fqdn" ]; then
        body=$(jq -n "${jq_args[@]}" '{fqdn: $fqdn}')
    elif [ -n "$inbox_name" ]; then
        body=$(jq -n "${jq_args[@]}" '{inboxName: $inboxName}')
    fi
    
    local -a request_args=("inboxes" "--request" "POST")
    
    if [ -n "$body" ]; then
        request_args+=("--header" "Content-Type: application/json" "--data" "$body")
    fi
    
    _qm4il_request "${request_args[@]}"
}

qm4il_get_inbox() {
    local inbox_id="${1:-$Qm4ilDefaultInboxID}"
    
    if [ -z "$inbox_id" ]; then
        echo "Missing inbox ID. Provide one or set Qm4ilDefaultInboxID in ~/.qm4ilrc." >&2
        return 1
    fi
    
    _qm4il_request "inboxes/$inbox_id"
}

qm4il_send_message() {
    local data="$1"
    
    if [ -z "$data" ]; then
        echo "Message data is required" >&2
        return 1
    fi
    
    _qm4il_request "emails" \
        "--request" "POST" \
        "--header" "Content-Type: application/json" \
        "--data" "$data"
}

qm4il_receive_unread_message() {
    local inbox_id="${1:-$Qm4ilDefaultInboxID}"
    shift
    
    if [ -z "$inbox_id" ]; then
        echo "Missing inbox ID. Provide one or set Qm4ilDefaultInboxID in ~/.qm4ilrc." >&2
        return 1
    fi
    
    local response
    response=$(_qm4il_request "emails/unread/$inbox_id/latest" "$@" 2>/dev/null)
    
    # Normalize and check for 404
    local normalized_response
    normalized_response=$(echo "$response" | tr -d '\000-\037')
    
    if echo "$normalized_response" | jq -e '.statusCode == 404' > /dev/null 2>&1; then
        echo "$normalized_response" | jq >&2
        return 1
    fi
    
    # Success
    echo "$normalized_response" | jq
}

qm4il_wait_for_unread_message() {
    local inbox_id="${1:-$Qm4ilDefaultInboxID}"
    
    if [ -z "$inbox_id" ]; then
        echo "Missing inbox ID. Provide one or set Qm4ilDefaultInboxID in ~/.qm4ilrc." >&2
        return 1
    fi
    
    _with_backoff qm4il_receive_unread_message "$inbox_id"
}

qm4il_poll_for_unread_message() {
    local inbox_id="${1:-$Qm4ilDefaultInboxID}"
    local interval="${2:-${Qm4ilPollInterval:-10}}"
    local max_attempts="${3:-${Qm4ilPollMaxAttempts:-60}}"
    
    if [ -z "$inbox_id" ]; then
        echo "Missing inbox ID. Provide one or set Qm4ilDefaultInboxID in ~/.qm4ilrc." >&2
        return 1
    fi
    
    _with_smart_polling qm4il_receive_unread_message "$inbox_id" "4" "5" "$max_attempts"
}

qm4il_send_fortune() {
    if ! command -v fortune > /dev/null 2>&1; then
        echo "Please install fortune" >&2
        return 1
    fi
    
    local inbox_id="${1:-$Qm4ilDefaultInboxID}"
    local from="${2:-$Qm4ilDefaultInboxID@mailmesh.cloud}"
    
    if [ -z "$inbox_id" ]; then
        echo "Missing inbox ID. Provide one or set Qm4ilDefaultInboxID in ~/.qm4ilrc." >&2
        return 1
    fi
    
    local text subject data
    text=$(fortune | sed 's/[\x00-\x1F]/ /g')
    subject=$(fortune -s -n 50 | sed 's/[\x00-\x1F]/ /g')
    
    data=$(jq -n -c \
        --arg from "$from" \
        --arg inboxID "$inbox_id" \
        --arg text "$text" \
        --arg subject "$subject" '
        {
            from: $from,
            inboxID: $inboxID,
            text: $text,
            subject: $subject
        }'
    )
    
    qm4il_send_message "$data"
}

qm4il_fetch_messages() {
    local inbox_id="${1:-$Qm4ilDefaultInboxID}"
    local limit="${2:-20}"
    
    if [ -z "$inbox_id" ]; then
        echo "Missing inbox ID. Provide one or set Qm4ilDefaultInboxID in ~/.qm4ilrc." >&2
        return 1
    fi
    
    _qm4il_request "emails?inboxID=${inbox_id}&limit=${limit}"
}

qm4il_get_message() {
    local message_id="$1"
    
    if [ -z "$message_id" ]; then
        echo "Message ID is required" >&2
        return 1
    fi
    
    _qm4il_request "emails/$message_id"
}

qm4il_read_message() {
    local message_id="$1"
    
    if [ -z "$message_id" ]; then
        echo "Message ID is required" >&2
        return 1
    fi
    
    _qm4il_request "emails/$message_id/read" "--request" "PATCH"
}

qm4il_mark_unread() {
    local message_id="$1"
    
    if [ -z "$message_id" ]; then
        echo "Message ID is required" >&2
        return 1
    fi
    
    _qm4il_request "emails/$message_id/unread" "--request" "PATCH"
}

qm4il_init_config() {
    local rcfile="$HOME/.qm4ilrc"
    
    if [ -f "$rcfile" ]; then
        echo "$rcfile already exists. Edit it manually if needed." >&2
        return 1
    fi
    
    echo "Initializing QM4IL config..."
    echo -n "Enter your QM4IL API key: "
    read -r api_key
    echo -n "Enter your default inbox ID: "
    read -r default_inbox_id
    
    cat > "$rcfile" <<EOF
# QM4IL CLI config
Qm4ilApiKey="$api_key"
Qm4ilDefaultInboxID="$default_inbox_id"
Qm4ilBackofAttempts=5
Qm4ilBackoffTimeout=1
Qm4ilPollInterval=10
Qm4ilPollMaxAttempts=60
Qm4ilApiEndpoint="https://api.mailmesh.cloud"
EOF
    
    # shellcheck source=/dev/null
    source "$rcfile"
    echo "Created $rcfile with provided values."
}

qm4il_show_config() {
    local rcfile="$HOME/.qm4ilrc"
    
    if [ ! -f "$rcfile" ]; then
        echo "Config file not found at $rcfile" >&2
        return 1
    fi
    
    echo -e "\nCurrent QM4IL configuration:\n"
    grep -v '^#' "$rcfile"
    echo -e "\n"
}

qm4il_help() {
    cat <<'EOF'
QM4IL CLI - Persistent Email API Client

USAGE:
  source qm4il-cli.sh
  qm4il_<function> [arguments]

CONFIGURATION:
  qm4il_init_config              Initialize configuration file
  qm4il_show_config              Show current configuration

ACCOUNT:
  qm4il_account                  Get account information
  qm4il_me                       Alias for qm4il_account

INBOXES:
  qm4il_inboxes                  List all inboxes
  qm4il_create_inbox [email|domain] [name]  Create new inbox
  qm4il_get_inbox [inbox_id]     Get inbox details

MESSAGES:
  qm4il_fetch_messages [inbox_id] [limit]   Fetch messages (default: 20)
  qm4il_get_message <message_id>            Get specific message
  qm4il_receive_unread_message [inbox_id]   Get latest unread message
  qm4il_wait_for_unread_message [inbox_id]  Wait for unread message with backoff
  qm4il_poll_for_unread_message [inbox_id] [interval] [max_attempts]  Poll with fixed interval
  qm4il_read_message <message_id>           Mark message as read
  qm4il_mark_unread <message_id>            Mark message as unread
  qm4il_send_message <json_data>            Send message
  qm4il_send_fortune [inbox_id] [from]      Send random fortune message

EXAMPLES:
  qm4il_create_inbox "test@mailmesh.cloud"
  qm4il_fetch_messages
  qm4il_wait_for_unread_message
  qm4il_send_fortune

LEGACY FUNCTIONS:
  All functions are also available with CamelCase names (e.g., QM4ilCreateInbox)

For more information, visit: https://docs.qm4il.com
EOF
}

qm4il_list_functions() {
    echo "QM4IL CLI Functions:"
    echo
    echo "Configuration:"
    echo "  qm4il_init_config"
    echo "  qm4il_show_config"
    echo
    echo "Account:"
    echo "  qm4il_account"
    echo "  qm4il_me"
    echo
    echo "Inboxes:"
    echo "  qm4il_inboxes"
    echo "  qm4il_create_inbox"
    echo "  qm4il_get_inbox"
    echo
    echo "Messages:"
    echo "  qm4il_fetch_messages"
    echo "  qm4il_get_message"
    echo "  qm4il_receive_unread_message"
    echo "  qm4il_wait_for_unread_message"
    echo "  qm4il_poll_for_unread_message"
    echo "  qm4il_read_message"
    echo "  qm4il_mark_unread"
    echo "  qm4il_send_message"
    echo "  qm4il_send_fortune"
    echo
    echo "Utilities:"
    echo "  qm4il_help"
    echo "  qm4il_list_functions"
    echo
    echo "Use 'qm4il_help' for detailed usage information."
}

_with_smart_polling() {
    local func="$1"
    local inbox_id="$2"
    local initial_delay="${3:-4}"
    local poll_interval="${4:-5}"
    local max_attempts="${5:-60}"
    
    # Immediate attempt
    if "$func" "$inbox_id"; then
        return 0
    fi
    
    # Second attempt after initial delay
    echo "No message yet, waiting ${initial_delay}s..." >&2
    sleep "$initial_delay"
    if "$func" "$inbox_id"; then
        return 0
    fi
    
    # Linear polling
    local attempt=3
    while (( attempt <= max_attempts )); do
        echo "Attempt $attempt: waiting ${poll_interval}s..." >&2
        sleep "$poll_interval"
        if "$func" "$inbox_id"; then
            return 0
        fi
        attempt=$(( attempt + 1 ))
    done
    
    echo "No message received after $max_attempts attempts" >&2
    return 1
}

_with_linear_polling() {
    local func="$1"
    local inbox_id="$2"
    local interval="$3"
    local max_attempts="$4"
    local attempt=1
    
    echo "Polling for messages every $interval seconds (max $max_attempts attempts)..." >&2
    
    while (( attempt <= max_attempts )); do
        if "$func" "$inbox_id"; then
            return 0
        else
            if (( attempt == max_attempts )); then
                echo "No message received after $max_attempts attempts ($(( max_attempts * interval )) seconds total)" >&2
                return 1
            else
                echo "Attempt $attempt: No message yet, waiting $interval seconds..." >&2
                sleep "$interval"
                attempt=$(( attempt + 1 ))
            fi
        fi
    done
}

_with_backoff() {
    local max_attempts="${Qm4ilBackofAttempts:-5}"
    local timeout="${Qm4ilBackoffTimeout:-1}"
    local attempt=1
    
    while true; do
        if "$@"; then
            break
        else
            if (( attempt == max_attempts )); then
                echo "Attempt $attempt failed and there are no more attempts left!" >&2
                return 1
            else
                echo "Attempt $attempt failed! Trying again in $timeout seconds..." >&2
                sleep "$timeout"
                attempt=$(( attempt + 1 ))
                timeout=$(( timeout * 2 ))
            fi
        fi
    done
}

# =============================================================================
# Legacy function names for backward compatibility
# =============================================================================

Qm4ilRequest() { _qm4il_request "$@"; }
Qm4ilInboxes() { qm4il_inboxes "$@"; }
Qm4ilAccount() { qm4il_account "$@"; }
Qm4ilMe() { qm4il_me "$@"; }
Qm4ilCreateInbox() { qm4il_create_inbox "$@"; }
Qm4ilGetInbox() { qm4il_get_inbox "$@"; }
Qm4ilSendMessage() { qm4il_send_message "$@"; }
Qm4ilReceiveUnreadMessage() { qm4il_receive_unread_message "$@"; }
Qm4ilWaitForUnreadMessage() { qm4il_wait_for_unread_message "$@"; }
Qm4ilPollForUnreadMessage() { qm4il_poll_for_unread_message "$@"; }
Qm4ilSendFortune() { qm4il_send_fortune "$@"; }
Qm4ilFetchMessages() { qm4il_fetch_messages "$@"; }
Qm4ilGetMessage() { qm4il_get_message "$@"; }
Qm4ilReadMessage() { qm4il_read_message "$@"; }
Qm4ilMarkUnread() { qm4il_mark_unread "$@"; }
Qm4ilInitConfig() { qm4il_init_config "$@"; }
Qm4ilShowConfig() { qm4il_show_config "$@"; }
Qm4ilHelp() { qm4il_help "$@"; }
Qm4ilListFunctions() { qm4il_list_functions "$@"; }
with_backoff() { _with_backoff "$@"; }

