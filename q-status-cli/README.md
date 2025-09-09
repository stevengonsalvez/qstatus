# Q-Status Monitor

High-performance terminal dashboard for real-time Amazon Q token monitoring.

## Features

- Real-time token usage tracking
- Cost analysis (session/daily/monthly)
- Usage graphs and visualizations
- Minimal resource usage (<15MB RAM, <2% CPU)
- Single binary distribution (~2-3MB)
- Cross-platform support (macOS, Linux, Windows)

## Installation

### From source
```bash
cargo install --path .
```

### Pre-built binaries
Download from [releases page](https://github.com/yourusername/q-status-cli/releases)

## Usage

```bash
q-status
```

### Keyboard shortcuts
- `R` - Refresh data
- `H` - View history
- `S` - Settings
- `E` - Export data
- `?` - Help
- `Q` - Quit

## Configuration

Configuration file location: `~/.config/q-status/config.toml`

## Development

### Building
```bash
cargo build --release
```

### Testing
```bash
cargo test
```

### Performance
- Memory usage: <15MB
- CPU usage: <2% idle, <5% active
- Binary size: ~2-3MB (stripped)

## License

MIT