# Q-Status CLI Monitor Implementation Plan

## Overview
Implementation of a standalone terminal dashboard application that monitors Amazon Q token usage in real-time, providing visibility into consumption, costs, and usage patterns without interfering with Q's operation.

## Current State Analysis
Based on research, the current state reveals:
- Q's SQLite database location: `~/Library/Application Support/amazon-q/data.sqlite3` (macOS)
- Token tracking via `context_message_length` field in conversations table (JSON format)
- No existing monitoring tools or project infrastructure
- Directory-based conversation tracking (each working directory has its own conversation)

### Key Discoveries:
- Database schema uses JSON storage in conversations table
- No dedicated token_usage table - must parse conversation JSON
- Session tracking via `session_id` in history table
- File watching possible for real-time updates using PRAGMA data_version

## Desired End State
A functional terminal-based monitoring dashboard that:
- Displays real-time token usage with visual progress bars
- Shows cost analysis (session/daily/monthly)
- Provides usage graphs over time
- Supports keyboard navigation and interaction
- Runs independently in separate terminal window/pane
- Updates automatically as Q consumes tokens

## What We're NOT Doing
- Modifying Q's operation or database
- Creating a GUI application 
- Building a menu bar app (that's Approach A)
- Implementing Q command interception
- Storing message content or sensitive data
- Creating a web-based dashboard

## Implementation Approach
Using Python with Textual framework for rich terminal UI capabilities, implementing a hybrid monitoring strategy (file watching + periodic polling) for real-time updates.

## Phase 1: Project Setup & Core Infrastructure

### Overview
Initialize the Python project structure, set up dependencies, and establish basic database connectivity.

### Changes Required:

#### 1. Project Structure
**Files to create**:
```
q-status-cli/
├── pyproject.toml
├── README.md
├── src/
│   └── q_status_monitor/
│       ├── __init__.py
│       ├── __main__.py
│       ├── config.py
│       ├── database.py
│       └── constants.py
├── tests/
│   ├── __init__.py
│   └── test_database.py
└── .gitignore
```

#### 2. Dependencies Configuration
**File**: `pyproject.toml`
```toml
[build-system]
requires = ["setuptools>=61.0", "wheel"]
build-backend = "setuptools.build_meta"

[project]
name = "q-status-monitor"
version = "0.1.0"
description = "Real-time token usage monitor for Amazon Q CLI"
requires-python = ">=3.8"
dependencies = [
    "textual>=0.41.0",
    "plotext>=5.2.0",
    "watchdog>=3.0.0",
    "pyyaml>=6.0",
    "python-dateutil>=2.8.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=7.0",
    "pytest-asyncio>=0.21.0",
    "black>=23.0",
    "ruff>=0.1.0",
]

[project.scripts]
q-status = "q_status_monitor.__main__:main"
```

#### 3. Database Connection Module
**File**: `src/q_status_monitor/database.py`
```python
# ABOUTME: Handles all database connections and queries to Q's SQLite database
# Provides abstraction layer for accessing conversation and token data

import sqlite3
import json
import os
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from datetime import datetime

class QDatabaseReader:
    """Read-only interface to Amazon Q's SQLite database."""
    
    def __init__(self):
        self.db_path = self._find_database()
        self._connection: Optional[sqlite3.Connection] = None
        
    def _find_database(self) -> Path:
        """Locate Q's database across different platforms."""
        possible_paths = [
            Path.home() / "Library" / "Application Support" / "amazon-q" / "data.sqlite3",  # macOS
            Path.home() / ".local" / "share" / "amazon-q" / "data.sqlite3",  # Linux
            Path.home() / ".aws" / "q" / "db" / "q.db",  # Legacy location
        ]
        
        for path in possible_paths:
            if path.exists():
                return path
                
        raise FileNotFoundError("Could not find Amazon Q database")
    
    def connect(self):
        """Establish read-only connection to database."""
        if not self._connection:
            self._connection = sqlite3.connect(
                f"file:{self.db_path}?mode=ro",
                uri=True,
                check_same_thread=False
            )
            self._connection.row_factory = sqlite3.Row
    
    def get_current_conversation(self, cwd: Optional[str] = None) -> Dict:
        """Retrieve current conversation data for working directory."""
        if not cwd:
            cwd = os.getcwd()
            
        cursor = self._connection.cursor()
        cursor.execute(
            "SELECT value FROM conversations WHERE key = ?",
            (cwd,)
        )
        row = cursor.fetchone()
        
        if row:
            return json.loads(row["value"])
        return {}
    
    def get_token_usage(self, conversation: Dict) -> Tuple[int, int]:
        """Extract token usage from conversation data."""
        context_length = conversation.get("context_message_length", 0)
        # Estimate total based on message history
        history = conversation.get("history", [])
        estimated_total = len(history) * 1000  # Rough estimate
        
        return context_length, estimated_total
    
    def get_data_version(self) -> int:
        """Get database version for change detection."""
        cursor = self._connection.cursor()
        cursor.execute("PRAGMA data_version")
        return cursor.fetchone()[0]
```

### Success Criteria:

#### Automated Verification:
- [ ] Project structure created successfully
- [ ] Dependencies install: `pip install -e .`
- [ ] Database connection test passes: `pytest tests/test_database.py`
- [ ] Import verification: `python -c "from q_status_monitor import database"`

#### Manual Verification:
- [ ] Can locate Q's database on the system
- [ ] Read-only connection established successfully
- [ ] No permission errors when accessing database

---

## Phase 2: Data Layer & Monitoring Engine

### Overview
Implement the core monitoring logic with efficient database polling and change detection.

### Changes Required:

#### 1. Monitoring Engine
**File**: `src/q_status_monitor/monitor.py`
```python
# ABOUTME: Core monitoring engine that tracks Q's token usage
# Implements hybrid file watching and polling for real-time updates

import asyncio
from pathlib import Path
from typing import Callable, Optional
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
from datetime import datetime, timedelta

from .database import QDatabaseReader

class DatabaseWatcher(FileSystemEventHandler):
    """Watch Q's database file for changes."""
    
    def __init__(self, callback: Callable):
        self.callback = callback
        self.last_version = None
        self.db_reader = QDatabaseReader()
        
    def on_modified(self, event):
        if event.src_path.endswith(('.sqlite3', '.db')):
            try:
                self.db_reader.connect()
                current_version = self.db_reader.get_data_version()
                
                if current_version != self.last_version:
                    self.callback()
                    self.last_version = current_version
            except Exception as e:
                # Log error but don't crash
                pass

class TokenMonitor:
    """Main monitoring engine for token usage."""
    
    def __init__(self):
        self.db_reader = QDatabaseReader()
        self.current_tokens = 0
        self.token_limit = 44000  # Q's default limit
        self.rate_calculator = RateCalculator()
        self.cost_calculator = CostCalculator()
        self._observers = []
        
    async def start(self):
        """Start monitoring with hybrid approach."""
        self.db_reader.connect()
        
        # Set up file watching
        observer = Observer()
        handler = DatabaseWatcher(self._on_database_change)
        observer.schedule(
            handler,
            str(self.db_reader.db_path.parent),
            recursive=False
        )
        observer.start()
        
        # Fallback polling loop
        while True:
            await self.update_stats()
            await asyncio.sleep(5)  # Poll every 5 seconds
    
    async def update_stats(self):
        """Update token usage statistics."""
        conversation = self.db_reader.get_current_conversation()
        tokens, total = self.db_reader.get_token_usage(conversation)
        
        self.current_tokens = tokens
        self.rate_calculator.add_sample(tokens)
        
        # Notify observers
        for observer in self._observers:
            observer(self.get_stats())
    
    def get_stats(self) -> dict:
        """Get current statistics."""
        return {
            "tokens_used": self.current_tokens,
            "tokens_limit": self.token_limit,
            "usage_percent": (self.current_tokens / self.token_limit) * 100,
            "tokens_remaining": self.token_limit - self.current_tokens,
            "rate": self.rate_calculator.get_rate(),
            "time_remaining": self.rate_calculator.estimate_time_remaining(
                self.tokens_limit - self.current_tokens
            ),
            "cost": self.cost_calculator.calculate_cost(self.current_tokens),
        }
    
    def subscribe(self, callback: Callable):
        """Subscribe to stat updates."""
        self._observers.append(callback)

class RateCalculator:
    """Calculate token consumption rate."""
    
    def __init__(self, window_size: int = 60):
        self.samples = []
        self.window_size = window_size
        
    def add_sample(self, tokens: int):
        """Add a token count sample."""
        now = datetime.now()
        self.samples.append((now, tokens))
        
        # Keep only recent samples
        cutoff = now - timedelta(seconds=self.window_size)
        self.samples = [(t, v) for t, v in self.samples if t > cutoff]
    
    def get_rate(self) -> float:
        """Calculate tokens per minute."""
        if len(self.samples) < 2:
            return 0.0
            
        time_diff = (self.samples[-1][0] - self.samples[0][0]).total_seconds()
        if time_diff == 0:
            return 0.0
            
        token_diff = self.samples[-1][1] - self.samples[0][1]
        return (token_diff / time_diff) * 60  # tokens per minute
```

#### 2. Cost Calculator
**File**: `src/q_status_monitor/cost.py`
```python
# ABOUTME: Calculates estimated costs based on token usage
# Uses approximate pricing models for Q's token consumption

from datetime import datetime, timedelta
from typing import Dict, List

class CostCalculator:
    """Calculate estimated costs for Q usage."""
    
    # Approximate cost per 1000 tokens (adjust based on actual Q pricing)
    COST_PER_1K_TOKENS = 0.01  
    
    def __init__(self):
        self.session_start = datetime.now()
        self.daily_usage: Dict[str, int] = {}
        self.monthly_usage: Dict[str, int] = {}
        
    def calculate_cost(self, tokens: int) -> float:
        """Calculate cost for given token count."""
        return (tokens / 1000) * self.COST_PER_1K_TOKENS
    
    def get_session_cost(self, tokens: int) -> float:
        """Get cost for current session."""
        return self.calculate_cost(tokens)
    
    def get_daily_cost(self) -> float:
        """Get today's total cost."""
        today = datetime.now().strftime("%Y-%m-%d")
        return self.calculate_cost(self.daily_usage.get(today, 0))
    
    def get_monthly_cost(self) -> float:
        """Get current month's total cost."""
        month = datetime.now().strftime("%Y-%m")
        return self.calculate_cost(self.monthly_usage.get(month, 0))
    
    def update_usage(self, tokens: int):
        """Update usage tracking."""
        today = datetime.now().strftime("%Y-%m-%d")
        month = datetime.now().strftime("%Y-%m")
        
        self.daily_usage[today] = self.daily_usage.get(today, 0) + tokens
        self.monthly_usage[month] = self.monthly_usage.get(month, 0) + tokens
```

### Success Criteria:

#### Automated Verification:
- [ ] Monitor engine tests pass: `pytest tests/test_monitor.py`
- [ ] Rate calculation tests pass: `pytest tests/test_cost.py`
- [ ] File watching detects database changes
- [ ] Polling fallback works when file watching fails

#### Manual Verification:
- [ ] Token usage updates when Q is used
- [ ] Rate calculation shows reasonable values
- [ ] Cost estimates align with expectations

---

## Phase 3: Terminal UI Dashboard

### Overview
Build the interactive terminal dashboard using Textual framework.

### Changes Required:

#### 1. Main Dashboard Application
**File**: `src/q_status_monitor/ui.py`
```python
# ABOUTME: Terminal UI dashboard for Q token monitoring
# Built with Textual framework for rich interactive experience

from textual.app import App, ComposeResult
from textual.widgets import Header, Footer, Static, ProgressBar, DataTable
from textual.containers import Horizontal, Vertical, ScrollableContainer
from textual.reactive import reactive
from textual.timer import Timer
import plotext as plt
from datetime import datetime
from typing import Optional

from .monitor import TokenMonitor
from .cost import CostCalculator

class QStatusDashboard(App):
    """Main dashboard application."""
    
    CSS = """
    #header_box {
        height: 3;
        border: solid $primary;
        content-align: center middle;
    }
    
    #usage_panel {
        height: 8;
        border: solid $success;
        padding: 1;
    }
    
    #cost_panel {
        height: 5;
        border: solid $warning;
        padding: 1;
    }
    
    #graph_panel {
        height: 12;
        border: solid $primary;
        padding: 1;
    }
    
    #history_panel {
        height: 10;
        border: solid $secondary;
    }
    
    .usage_bar {
        margin: 1 2;
    }
    
    .stat_text {
        margin: 0 2;
    }
    """
    
    BINDINGS = [
        ("r", "refresh", "Refresh"),
        ("s", "settings", "Settings"),
        ("h", "history", "History"),
        ("e", "export", "Export"),
        ("q", "quit", "Quit"),
    ]
    
    tokens_used = reactive(0)
    tokens_limit = reactive(44000)
    usage_percent = reactive(0.0)
    rate = reactive(0.0)
    time_remaining = reactive("--")
    session_cost = reactive(0.0)
    daily_cost = reactive(0.0)
    monthly_cost = reactive(0.0)
    
    def __init__(self):
        super().__init__()
        self.monitor = TokenMonitor()
        self.monitor.subscribe(self.on_stats_update)
        self.history_data = []
        self.graph_data = []
        
    def compose(self) -> ComposeResult:
        """Build the UI layout."""
        yield Header()
        
        with Vertical():
            # Title
            yield Static(
                "Q Token Monitor v1.0.0  [Connected]",
                id="header_box"
            )
            
            # Current Session Panel
            with Vertical(id="usage_panel"):
                yield Static("Current Session", classes="panel_title")
                yield ProgressBar(
                    total=self.tokens_limit,
                    show_percentage=True,
                    id="usage_bar",
                    classes="usage_bar"
                )
                yield Static(
                    f"Tokens: {self.tokens_used:,} / {self.tokens_limit:,}",
                    id="token_text",
                    classes="stat_text"
                )
                yield Static(
                    f"Rate: {self.rate:.0f} tokens/min",
                    id="rate_text",
                    classes="stat_text"  
                )
                yield Static(
                    f"Est. Time Remaining: {self.time_remaining}",
                    id="time_text",
                    classes="stat_text"
                )
            
            # Cost Analysis Panel
            with Vertical(id="cost_panel"):
                yield Static("Cost Analysis", classes="panel_title")
                yield Static(
                    f"Session: ${self.session_cost:.2f} | "
                    f"Today: ${self.daily_cost:.2f} | "
                    f"Month: ${self.monthly_cost:.2f}",
                    id="cost_text",
                    classes="stat_text"
                )
            
            # Usage Graph Panel
            with Vertical(id="graph_panel"):
                yield Static("Usage Graph (Last Hour)", classes="panel_title")
                yield Static(
                    self.generate_graph(),
                    id="graph_display"
                )
            
        yield Footer()
    
    def generate_graph(self) -> str:
        """Generate terminal graph of usage."""
        if len(self.graph_data) < 2:
            return "Collecting data..."
            
        plt.clear_data()
        plt.theme("dark")
        
        times = [d[0] for d in self.graph_data[-60:]]  # Last 60 samples
        values = [d[1] for d in self.graph_data[-60:]]
        
        plt.plot(times, values)
        plt.title("Token Usage Over Time")
        plt.xlabel("Time")
        plt.ylabel("Tokens")
        
        return plt.build()
    
    def on_stats_update(self, stats: dict):
        """Handle stats updates from monitor."""
        self.tokens_used = stats["tokens_used"]
        self.usage_percent = stats["usage_percent"]
        self.rate = stats["rate"]
        self.time_remaining = self.format_time(stats["time_remaining"])
        self.session_cost = stats["cost"]
        
        # Update graph data
        self.graph_data.append((datetime.now(), stats["tokens_used"]))
        
        # Trigger UI updates
        self.update_display()
    
    def update_display(self):
        """Update all display elements."""
        # Update progress bar
        progress_bar = self.query_one("#usage_bar", ProgressBar)
        progress_bar.update(progress=self.tokens_used)
        
        # Update text displays
        self.query_one("#token_text", Static).update(
            f"Tokens: {self.tokens_used:,} / {self.tokens_limit:,}"
        )
        self.query_one("#rate_text", Static).update(
            f"Rate: {self.rate:.0f} tokens/min"
        )
        self.query_one("#time_text", Static).update(
            f"Est. Time Remaining: {self.time_remaining}"
        )
        self.query_one("#cost_text", Static).update(
            f"Session: ${self.session_cost:.2f} | "
            f"Today: ${self.daily_cost:.2f} | "
            f"Month: ${self.monthly_cost:.2f}"
        )
        
        # Update graph
        self.query_one("#graph_display", Static).update(
            self.generate_graph()
        )
        
        # Update header color based on usage
        if self.usage_percent > 90:
            self.query_one("#header_box").add_class("alert")
        elif self.usage_percent > 70:
            self.query_one("#header_box").add_class("warning")
    
    def format_time(self, seconds: Optional[float]) -> str:
        """Format seconds into readable time."""
        if not seconds or seconds < 0:
            return "--"
            
        hours = int(seconds // 3600)
        minutes = int((seconds % 3600) // 60)
        
        if hours > 0:
            return f"{hours}h {minutes}m"
        return f"{minutes} minutes"
    
    async def on_mount(self):
        """Start monitoring when app mounts."""
        self.run_worker(self.monitor.start())
        self.set_interval(2.0, self.refresh_data)
    
    async def refresh_data(self):
        """Periodic refresh of data."""
        await self.monitor.update_stats()
    
    def action_refresh(self):
        """Handle refresh action."""
        self.run_worker(self.monitor.update_stats())
    
    def action_history(self):
        """Show history view."""
        # TODO: Implement history view
        self.notify("History view coming soon!")
    
    def action_settings(self):
        """Show settings dialog."""
        # TODO: Implement settings
        self.notify("Settings coming soon!")
    
    def action_export(self):
        """Export data to CSV."""
        # TODO: Implement export
        self.notify("Export feature coming soon!")
```

#### 2. Main Entry Point
**File**: `src/q_status_monitor/__main__.py`
```python
# ABOUTME: Entry point for Q Status Monitor application
# Handles CLI arguments and launches the dashboard

import sys
import argparse
from pathlib import Path

from .ui import QStatusDashboard

def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Real-time token usage monitor for Amazon Q CLI"
    )
    parser.add_argument(
        "--config",
        type=Path,
        help="Path to configuration file"
    )
    parser.add_argument(
        "--refresh-rate",
        type=int,
        default=2,
        help="Refresh rate in seconds (default: 2)"
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Enable debug mode"
    )
    
    args = parser.parse_args()
    
    try:
        app = QStatusDashboard()
        app.run()
    except KeyboardInterrupt:
        sys.exit(0)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
```

### Success Criteria:

#### Automated Verification:
- [ ] UI components render without errors: `python -m q_status_monitor`
- [ ] Keyboard bindings work correctly
- [ ] Progress bar updates with token usage
- [ ] Graph renders properly with plotext

#### Manual Verification:
- [ ] Dashboard displays in terminal correctly
- [ ] Real-time updates visible when Q is used
- [ ] Keyboard shortcuts (R, S, H, Q) respond correctly
- [ ] Color coding changes based on usage thresholds
- [ ] Terminal resize handled gracefully

---

## Phase 4: Analytics & Advanced Features

### Overview
Add historical tracking, advanced analytics, and data export capabilities.

### Changes Required:

#### 1. History Storage
**File**: `src/q_status_monitor/history.py`
```python
# ABOUTME: Manages historical data storage and retrieval
# Stores usage patterns for analysis and reporting

import json
import sqlite3
from pathlib import Path
from datetime import datetime, timedelta
from typing import List, Dict, Optional

class HistoryManager:
    """Manage historical usage data."""
    
    def __init__(self):
        self.db_path = self._get_history_db_path()
        self._init_database()
        
    def _get_history_db_path(self) -> Path:
        """Get path for history database."""
        data_dir = Path.home() / ".config" / "q-status"
        data_dir.mkdir(parents=True, exist_ok=True)
        return data_dir / "history.db"
    
    def _init_database(self):
        """Initialize history database."""
        conn = sqlite3.connect(self.db_path)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS usage_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                tokens_used INTEGER,
                rate REAL,
                session_id TEXT,
                working_directory TEXT,
                cost REAL
            )
        """)
        conn.execute("""
            CREATE INDEX IF NOT EXISTS idx_timestamp 
            ON usage_history(timestamp)
        """)
        conn.commit()
        conn.close()
    
    def record_usage(self, data: Dict):
        """Record usage data point."""
        conn = sqlite3.connect(self.db_path)
        conn.execute("""
            INSERT INTO usage_history 
            (tokens_used, rate, session_id, working_directory, cost)
            VALUES (?, ?, ?, ?, ?)
        """, (
            data["tokens_used"],
            data["rate"],
            data.get("session_id", ""),
            data.get("working_directory", ""),
            data["cost"]
        ))
        conn.commit()
        conn.close()
    
    def get_history(self, hours: int = 24) -> List[Dict]:
        """Get usage history for specified hours."""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        
        cutoff = datetime.now() - timedelta(hours=hours)
        cursor = conn.execute("""
            SELECT * FROM usage_history
            WHERE timestamp > ?
            ORDER BY timestamp DESC
        """, (cutoff,))
        
        results = [dict(row) for row in cursor.fetchall()]
        conn.close()
        return results
    
    def get_statistics(self) -> Dict:
        """Get usage statistics."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.execute("""
            SELECT 
                COUNT(*) as total_samples,
                SUM(tokens_used) as total_tokens,
                AVG(rate) as avg_rate,
                MAX(rate) as max_rate,
                SUM(cost) as total_cost
            FROM usage_history
            WHERE timestamp > datetime('now', '-30 days')
        """)
        
        row = cursor.fetchone()
        conn.close()
        
        return {
            "total_samples": row[0],
            "total_tokens": row[1] or 0,
            "average_rate": row[2] or 0,
            "max_rate": row[3] or 0,
            "total_cost": row[4] or 0
        }
```

#### 2. Data Export
**File**: `src/q_status_monitor/export.py`
```python
# ABOUTME: Handles data export to various formats
# Supports CSV, JSON, and summary report generation

import csv
import json
from pathlib import Path
from datetime import datetime
from typing import List, Dict

class DataExporter:
    """Export usage data to various formats."""
    
    def __init__(self, history_manager):
        self.history_manager = history_manager
        
    def export_csv(self, output_path: Path, hours: int = 24):
        """Export data to CSV format."""
        data = self.history_manager.get_history(hours)
        
        with open(output_path, 'w', newline='') as csvfile:
            if not data:
                return
                
            fieldnames = data[0].keys()
            writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
            
            writer.writeheader()
            writer.writerows(data)
    
    def export_json(self, output_path: Path, hours: int = 24):
        """Export data to JSON format."""
        data = self.history_manager.get_history(hours)
        
        with open(output_path, 'w') as jsonfile:
            json.dump(data, jsonfile, indent=2, default=str)
    
    def generate_report(self) -> str:
        """Generate summary report."""
        stats = self.history_manager.get_statistics()
        
        report = f"""
Q TOKEN USAGE REPORT
Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
{'=' * 50}

30-Day Summary:
- Total Tokens Used: {stats['total_tokens']:,}
- Average Rate: {stats['average_rate']:.1f} tokens/min
- Peak Rate: {stats['max_rate']:.1f} tokens/min
- Total Cost: ${stats['total_cost']:.2f}

Daily Average: {stats['total_tokens'] / 30:,.0f} tokens
Projected Monthly Cost: ${stats['total_cost'] * 30 / 30:.2f}
"""
        return report
```

### Success Criteria:

#### Automated Verification:
- [ ] History database created successfully
- [ ] Data recording works: `pytest tests/test_history.py`
- [ ] Export functions produce valid files
- [ ] Statistics calculation accurate

#### Manual Verification:
- [ ] Historical data persists between sessions
- [ ] Export produces readable CSV/JSON files
- [ ] Statistics reflect actual usage patterns

---

## Phase 5: Testing & Polish

### Overview
Comprehensive testing, performance optimization, and distribution preparation.

### Changes Required:

#### 1. Test Suite
**File**: `tests/test_integration.py`
```python
import pytest
import asyncio
from unittest.mock import Mock, patch
from q_status_monitor.monitor import TokenMonitor
from q_status_monitor.database import QDatabaseReader

@pytest.mark.asyncio
async def test_monitor_updates():
    """Test that monitor updates stats correctly."""
    monitor = TokenMonitor()
    
    # Mock database reader
    with patch.object(monitor.db_reader, 'get_current_conversation') as mock_conv:
        mock_conv.return_value = {"context_message_length": 1000}
        
        await monitor.update_stats()
        stats = monitor.get_stats()
        
        assert stats["tokens_used"] == 1000
        assert stats["usage_percent"] == pytest.approx(2.27, 0.1)

def test_rate_calculation():
    """Test token rate calculation."""
    from q_status_monitor.monitor import RateCalculator
    
    calc = RateCalculator()
    calc.add_sample(1000)
    time.sleep(1)
    calc.add_sample(1100)
    
    rate = calc.get_rate()
    assert rate == pytest.approx(6000, 100)  # ~100 tokens/min
```

#### 2. Configuration
**File**: `src/q_status_monitor/config.py`
```python
# ABOUTME: Configuration management for Q Status Monitor
# Handles user preferences and settings persistence

import yaml
from pathlib import Path
from typing import Dict, Any

class Config:
    """Application configuration."""
    
    DEFAULT_CONFIG = {
        "refresh_rate": 2,
        "token_limit": 44000,
        "cost_per_1k": 0.01,
        "warning_threshold": 70,
        "critical_threshold": 90,
        "history_retention_days": 30,
        "export_format": "csv",
        "theme": "dark",
    }
    
    def __init__(self):
        self.config_path = Path.home() / ".config" / "q-status" / "config.yaml"
        self.config = self.load()
    
    def load(self) -> Dict[str, Any]:
        """Load configuration from file."""
        if self.config_path.exists():
            with open(self.config_path) as f:
                user_config = yaml.safe_load(f)
                return {**self.DEFAULT_CONFIG, **user_config}
        return self.DEFAULT_CONFIG.copy()
    
    def save(self):
        """Save configuration to file."""
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        with open(self.config_path, 'w') as f:
            yaml.dump(self.config, f)
    
    def get(self, key: str, default=None):
        """Get configuration value."""
        return self.config.get(key, default)
    
    def set(self, key: str, value: Any):
        """Set configuration value."""
        self.config[key] = value
        self.save()
```

### Success Criteria:

#### Automated Verification:
- [ ] All tests pass: `pytest`
- [ ] Type checking passes: `mypy src/`
- [ ] Linting passes: `ruff check src/`
- [ ] Coverage > 80%: `pytest --cov=q_status_monitor`

#### Manual Verification:
- [ ] Application runs smoothly for extended periods
- [ ] Memory usage stays under 50MB
- [ ] CPU usage < 5% during updates
- [ ] Installation works via pip

---

## Testing Strategy

### Unit Tests:
- Database connection and queries
- Token usage calculation
- Rate calculation
- Cost calculation
- History storage

### Integration Tests:
- End-to-end monitoring flow
- UI updates with real data
- File watching detection
- Export functionality

### Manual Testing Steps:
1. Start Q Status Monitor: `q-status`
2. Use Amazon Q in another terminal
3. Verify token usage updates in real-time
4. Test all keyboard shortcuts
5. Export data and verify output
6. Resize terminal and check layout
7. Kill and restart to verify history persistence

## Performance Considerations
- Use connection pooling for SQLite access
- Implement efficient change detection via PRAGMA data_version
- Batch UI updates to prevent flicker
- Limit graph data points to last 60 samples
- Use async operations for non-blocking updates

## Migration Notes
- First version - no migration needed
- Future versions should check history database schema version
- Configuration changes should preserve user settings

## Distribution Strategy

### Installation Methods:
1. **pip/pipx**: `pipx install q-status-monitor`
2. **Homebrew**: `brew install q-status-monitor`
3. **Direct**: `python -m q_status_monitor`

### Packaging:
- Use setuptools for Python packaging
- Create standalone executables with PyInstaller for easy distribution
- Include man page and shell completions

## References
- Original requirements: `q-status-requirements.md`
- Q database location: `~/Library/Application Support/amazon-q/data.sqlite3`
- Textual documentation: https://textual.textualize.io/
- Plotext documentation: https://github.com/piccolomo/plotext