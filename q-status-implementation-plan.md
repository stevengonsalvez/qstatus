# Q-Status Implementation Plan

## Overview

This document outlines the implementation strategy for two independent Q token monitoring solutions that avoid the architectural problems of PTY wrappers.

## Why Not PTY Wrapper?

After extensive testing, we discovered that PTY wrappers are fundamentally incompatible with Q's terminal REPL:

1. **Terminal Control Conflicts**: Q and the wrapper fight over cursor position, colors, and input modes
2. **Signal Handling Issues**: Complex signal forwarding causes timing problems
3. **I/O Buffering Problems**: Multiple buffering layers cause repeated output and garbled display
4. **Status Bar Impossibility**: Cannot reliably separate Q's output from status display

## New Architecture

Instead of wrapping Q, we'll observe it non-invasively:
- **Read Q's SQLite database** for token usage data
- **Display in separate UI** (menu bar or different terminal)
- **Zero interference** with Q's operation

## Implementation Tracks

### Track A: macOS Menu Bar Application

**Technology Decision**: Python with rumps (Ridiculously Uncomplicated macOS Python Statusbar apps)

**Why Python/rumps**:
- Rapid development and iteration
- Easy SQLite integration
- Simple distribution via pip/homebrew
- Good enough performance for polling every 2-5 seconds
- Can later rewrite in Swift if needed

**Implementation Steps**:
1. Set up Python project with rumps
2. Create SQLite reader for Q's database
3. Implement basic menu bar display
4. Add dropdown with detailed stats
5. Implement notifications
6. Package for distribution

### Track B: CLI Monitor

**Technology Decision**: Python with Rich/Textual

**Why Python/Rich**:
- Proven success (Claude Code Usage Monitor uses same stack)
- Beautiful terminal UIs out of the box
- Rich ecosystem for data visualization
- Cross-platform compatibility
- Familiar to Python developers

**Implementation Steps**:
1. Set up Python project with Textual
2. Create database monitoring module
3. Build dashboard layout
4. Implement real-time updates
5. Add interactive features
6. Package for pip distribution

## Development Timeline

### Week 1: Foundation
- Set up both project structures
- Implement basic database reading
- Create minimal UI prototypes

### Week 2: Core Features
- Real-time monitoring
- Data calculations
- Basic visualizations

### Week 3: Polish
- Error handling
- Configuration system
- Performance optimization

### Week 4: Release
- Testing and bug fixes
- Documentation
- Distribution setup

## Git Worktree Structure

Two independent branches for parallel development:

```bash
# Main repository
/Users/stevengonsalvez/d/git/qlips/

# Menu bar app worktree
/Users/stevengonsalvez/d/git/qlips-menubar/
└── feature/q-status-menubar branch

# CLI monitor worktree  
/Users/stevengonsalvez/d/git/qlips-cli/
└── feature/q-status-cli branch
```

## Next Steps

1. Create git worktrees for both approaches
2. Initialize Python projects in each worktree
3. Start separate Claude sessions for focused development
4. Implement MVP versions in parallel

## Success Metrics

- **Works reliably**: No crashes, handles edge cases
- **Zero Q interference**: Q operates exactly as before
- **Low resource usage**: < 50MB RAM, < 5% CPU
- **User satisfaction**: Intuitive, helpful, beautiful

## Lessons Learned

The PTY wrapper approach taught us:
- Don't fight with existing terminal applications
- Observe, don't intercept
- Separate concerns completely
- Simple solutions often work better

This new approach embraces these lessons by keeping the monitoring completely separate from Q's operation.