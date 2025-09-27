# Dropdown Layout Optimization - Wider and Shorter for 15" Laptops

## Status: completed

### Tasks:
- [x] **Change MenuBarController popover size** - Update from 500x400 to 700x350
- [x] **Refactor DropdownView main body** - Convert from single VStack to two-column HStack layout
  - [x] Left column (300px): Global header, Claude Code section
  - [x] Right column (400px): Recent sessions, controls, provider selector
  - [x] Add vertical divider between columns
- [x] **Update DropdownView frame size** - Change from width: 500 to width: 700, add maxHeight: 350
- [x] **Optimize section heights** - Make sections more compact where possible (height constraint applied)
- [x] **Test layout** - Verify the new layout works well on 15" screens (build successful)

### Progress Notes:
- Identified current layout structure in DropdownView.swift (VStack with sections)
- Located popover size setting in MenuBarController.swift line 193
- Found main frame width setting in DropdownView.swift line 101
- Successfully implemented two-column layout with proper spacing
- Build completes successfully with new layout structure