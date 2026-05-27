# qm4il-cli

QM4IL persistent email API shell client.

A minimal shell client for the QM4IL persistent email API — a simple, terminal-based way to manage inboxes, receive, parse, and send messages programmatically using the QM4IL SaaS service.

QM4IL offers programmatic access to your inboxes through a simple API. It's ideal for automating flows that involve receiving or validating emails — from testing user signups to running production bots.

[API Reference](https://docs.qm4il.com)

## Features

- Complete inbox management (create, list, get details)
- Message operations (send, receive, read/unread status)
- Two polling strategies: exponential backoff and fixed interval
- Account information and configuration management
- Pure Bash using `curl` and `jq`
- Lightweight and dependency-free
- Legacy function name compatibility

## Requirements

- Bash
- curl
- jq

## Usage

Clone the repo and source the script in your shell:

```bash
git clone https://github.com/ql4biz/qm4il-cli.git
cd qm4il-cli
source qm4il-cli.sh
```

### Configuration

Initialize your configuration:

```bash
qm4il_init_config
# or legacy: Qm4ilInitConfig
```

This creates a `.qm4ilrc` file in your home directory with:
- API key
- Default inbox ID  
- Polling settings
- API endpoint

### Basic Usage

```bash
# Get help
qm4il_help

# List all functions
qm4il_list_functions

# Create an inbox
qm4il_create_inbox "test@mailmesh.cloud"

# List your inboxes
qm4il_inboxes

# Send a message
data='{"from":"sender@example.com","inboxID":"your-inbox-id","subject":"Test","text":"Hello!"}'
qm4il_send_message "$data"

# Wait for a message (exponential backoff)
qm4il_wait_for_unread_message

# Poll for a message (fixed interval)
qm4il_poll_for_unread_message "inbox-id" 10 60

# Send a random fortune
qm4il_send_fortune
```

## Function Reference

### Configuration
- `qm4il_init_config` - Initialize configuration file
- `qm4il_show_config` - Show current configuration

### Account
- `qm4il_account` / `qm4il_me` - Get account information

### Inboxes
- `qm4il_inboxes` - List all inboxes
- `qm4il_create_inbox [email|domain] [name]` - Create new inbox
- `qm4il_get_inbox [inbox_id]` - Get inbox details

### Messages
- `qm4il_fetch_messages [inbox_id] [limit]` - Fetch messages (default: 20)
- `qm4il_get_message <message_id>` - Get specific message
- `qm4il_receive_unread_message [inbox_id]` - Get latest unread message
- `qm4il_wait_for_unread_message [inbox_id]` - Wait with exponential backoff
- `qm4il_poll_for_unread_message [inbox_id] [interval] [max_attempts]` - Poll with fixed interval
- `qm4il_read_message <message_id>` - Mark message as read
- `qm4il_mark_unread <message_id>` - Mark message as unread
- `qm4il_send_message <json_data>` - Send message
- `qm4il_send_fortune [inbox_id] [from]` - Send random fortune

### Utilities
- `qm4il_help` - Show detailed help
- `qm4il_list_functions` - List all functions

## Configuration Variables

```bash
# ~/.qm4ilrc
Qm4ilApiKey="your-api-key"
Qm4ilDefaultInboxID="your-inbox-id"
Qm4ilBackofAttempts=5          # Exponential backoff attempts
Qm4ilBackoffTimeout=1          # Initial backoff timeout
Qm4ilPollInterval=10           # Fixed polling interval (seconds)
Qm4ilPollMaxAttempts=60        # Fixed polling max attempts
Qm4ilApiEndpoint="https://api.mailmesh.cloud"
```

## Polling Strategies

### Exponential Backoff (`qm4il_wait_for_unread_message`)
- **Pattern**: 1s, 2s, 4s, 8s (doubles each attempt)
- **Total time**: ~15 seconds (5 attempts)
- **Use case**: Quick response, API-friendly

### Fixed Interval (`qm4il_poll_for_unread_message`)
- **Pattern**: Fixed interval (default 10s)
- **Total time**: Configurable (default 10 minutes)
- **Use case**: Long-running, predictable timing

## Legacy Compatibility

All functions are available with CamelCase names:
- `QM4ilCreateInbox` → `qm4il_create_inbox`
- `QM4ilWaitForUnreadMessage` → `qm4il_wait_for_unread_message`
- etc.

## API Reference

For full API details and request structure, visit the [QM4IL API Reference](https://docs.qm4il.com/reference).

## License

MIT
