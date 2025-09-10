# Q-Status CLI Monitor - Usage Guide

## Overview

Q-Status CLI is a high-performance terminal-based monitor for Amazon Q token usage. It provides real-time insights into your Q CLI token consumption, costs, and usage patterns.

## Installation

### From Source

```bash
# Clone the repository
git clone <repository-url>
cd qlips-cli

# Build the release binary
cargo build --release

# The binary will be at target/release/q-status
```

### Binary Location

After building, the binary is located at:
```
target/release/q-status
```

You can copy it to your PATH for system-wide access:
```bash
sudo cp target/release/q-status /usr/local/bin/
```

## Usage

### Basic Usage

Run the monitor with default settings:
```bash
q-status
```

### Command-Line Options

```
q-status [OPTIONS]

Options:
  -r, --refresh-rate <SECONDS>  Refresh rate in seconds [default: 2]
  -c, --config <FILE>           Path to configuration file
  -d, --debug                   Enable debug logging
  -h, --help                    Print help
  -V, --version                 Print version
```

### Examples

```bash
# Run with faster refresh rate
q-status --refresh-rate 1

# Run with debug logging
q-status --debug

# Use custom configuration
q-status --config ~/my-q-config.toml
```

## Dashboard Features

### Main Display
- **Header**: Shows connection status and version
- **Token Gauge**: Visual representation of current token usage
- **Cost Panel**: Session, daily, and monthly cost estimates
- **Usage Statistics**: Token rate and time remaining estimates

### Keyboard Controls
- **R**: Force refresh of data
- **H**: View usage history (when implemented)
- **?**: Show help overlay
- **Q**: Quit the application

## Configuration

The monitor looks for Amazon Q's database in these locations:
1. `~/Library/Application Support/amazon-q/data.sqlite3` (macOS)
2. `~/.local/share/amazon-q/data.sqlite3` (Linux)
3. `~/.aws/q/db/q.db` (Legacy)

### Custom Configuration File

You can create a configuration file to customize behavior:

```toml
# q-status.toml
refresh_rate = 2
cost_per_1k_tokens = 0.02
token_limit = 1000000
debug = false
```

## Requirements

- Amazon Q CLI must be installed and have an active database
- Terminal with color support
- Minimum terminal size: 80x24

## Troubleshooting

### "Q database not found"
- Ensure Amazon Q CLI is installed and has been used at least once
- Check that the database exists at one of the expected locations

### "Device not configured"
- This error occurs when running without a proper terminal
- Ensure you're running in an interactive terminal session

### Performance Issues
- Try increasing the refresh rate: `q-status --refresh-rate 5`
- Enable debug mode to see detailed logs: `q-status --debug`

## Resource Usage

- **Memory**: ~15MB typical usage
- **CPU**: <2% when idle, <5% during updates
- **Binary Size**: ~3.1MB

## Architecture

The monitor uses:
- Read-only access to Q's SQLite database
- File watching for real-time updates
- Polling fallback for reliability
- Multi-threaded architecture for responsiveness

## Security

- Read-only database access (no modifications)
- No network connections
- No data persistence or logging of sensitive information
- Local execution only

## Development

### Running Tests
```bash
cargo test
```

### Building Debug Version
```bash
cargo build
```

### Code Structure
```
src/
├── main.rs           # Application entry point
├── app/
│   ├── mod.rs       # Application module
│   ├── config.rs    # Configuration handling
│   └── state.rs     # State management
├── data/
│   ├── mod.rs       # Data module
│   ├── collector.rs # Background data collection
│   └── database.rs  # SQLite interface
├── ui/
│   ├── mod.rs       # UI module
│   └── dashboard.rs # Terminal dashboard
└── utils/
    ├── mod.rs       # Utilities module
    └── error.rs     # Error handling
```

## License

[Your License Here]

## Support

For issues or questions, please open an issue on the GitHub repository.