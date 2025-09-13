# QStatus v1.0.0 Release

## 🎉 Initial Release

QStatus provides real-time monitoring for your Q (Claude) usage with a native macOS menubar app and CLI dashboard.

### ✨ Features

#### 📊 Real-time Monitoring
- **Token Usage**: Track context window consumption across all sessions
- **Cost Tracking**: Monitor spending by day, week, and month
- **Burn Rate**: See your token consumption rate in real-time
- **Message Quota**: Track your monthly message allowance

#### 🎯 Dual Interface
- **macOS Menubar App**: Always-visible usage indicator with detailed dropdown
- **CLI Dashboard**: Full-featured terminal UI for power users

#### 🔥 Smart Analytics
- **Session Tracking**: Individual conversation monitoring with folder organization
- **Visual Indicators**: Color-coded usage bars (green/yellow/red)
- **Top Sessions**: Sort by tokens, usage percentage, or cost
- **Group by Folder**: Organize sessions by project directory

### 📦 Installation

#### Quick Install
```bash
# Download and run the installer
curl -sSL https://github.com/yourusername/qstatus/releases/latest/download/install.sh | bash
```

#### DMG Installation
1. Download `QStatus.dmg`
2. Open and drag Q Status to Applications
3. Launch from Applications or Spotlight

#### CLI Only
```bash
# Download and extract
curl -L https://github.com/yourusername/qstatus/releases/latest/download/qstatus-cli-macos.tar.gz | tar xz
# Move to PATH
sudo mv q-status /usr/local/bin/qstatus
```

### 🖥️ Usage

#### Menubar App
- Launch **Q Status** from Applications
- Click menubar icon for detailed statistics
- Visual progress bars show usage at a glance
- Sort sessions by different metrics

#### CLI Dashboard
```bash
# Run interactive dashboard
qstatus -i

# Quick status check
qstatus

# JSON output for scripts
qstatus --json
```

### 📝 Download Assets

- `QStatus.dmg` - Main installer for macOS (recommended)
- `QStatus.app.zip` - Direct app download
- `qstatus-cli-macos.tar.gz` - CLI binary only

### 🔧 Requirements

- macOS 11.0+
- Q (Claude) desktop app installed
- Database at `~/Library/Application Support/Claude/claude_desktop_storage.db`

### 🐛 Known Issues

- Menubar app may require accessibility permissions on first launch
- CLI requires `/usr/local/bin` in PATH

### 🙏 Acknowledgments

Built for the Q (Claude) community to provide better usage visibility and cost tracking.

---

Made with ❤️ for developers using Q (Claude)