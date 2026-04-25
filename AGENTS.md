# Bricklayer - Project Agents & Workflow Guide

## Project Overview

**Bricklayer** is a Godot 4.6 first-person 3D building game where players construct structures by placing and removing voxel-like bricks in real-time.

### Key Specs
- **Engine**: Godot 4.6 (Forward Plus rendering)
- **Language**: GDScript
- **Platform**: Windows (packaged executable available)
- **Resolution**: 1920×1080 default
- **Features**: First-person camera, brick placement/removal, color selection, particle effects, pause menu with settings

---

## Codebase Architecture

### Core Scripts

| File | Purpose |
|------|---------|
| [player.gd](player.gd) | FPS controller, brick placement/removal, camera, color selection, raycast logic |
| [pause_menu.gd](pause_menu.gd) | Settings UI (resolution, fullscreen, FPS cap), game pause state |
| [dust_cloud.gd](dust_cloud.gd) | Particle effect spawned on brick placement |

### Main Scenes

| File | Purpose |
|------|---------|
| [main.tscn](main.tscn) | Root scene: player, camera, UI, bricks container, preview brick |
| [brick.tscn](brick.tscn) | Individual brick prefab (MeshInstance3D with collision) |
| [dust_cloud.tscn](dust_cloud.tscn) | Particle system for placement feedback |

### Configuration

| File | Purpose |
|------|---------|
| [project.godot](project.godot) | Engine config (version, input map, window size) |
| [export_presets.cfg](export_presets.cfg) | Build presets for executable |

---

## Development Conventions

### Input Map
- **W/A/S/D** — Movement (move_forward, move_left, move_right, move_backward)
- **Space** — Jump
- **Left Click** — Place brick
- **Right Click** — Remove brick
- **Tab** — Cycle brick color (Red → Green → Blue → Yellow → Purple)
- **ESC** — Toggle pause menu

### Node Structure
- Unique names (@unique_name_in_owner) used extensively for quick lookups
- `@onready` variables for cached references (safer than `get_tree()` chains)
- Physics queries use `PhysicsRayQueryParameters3D` for raycasting

### Common Patterns
1. **Safety checks** on `@onready` variables before use
2. **Preloaded assets** (@onready) to avoid reload costs
3. **Signal connections** in `_ready()` for event handling
4. **Print statements** for debugging (can be extended to logging system)

### Recent Changes
- **FPS Cap Option**: Added `Max FPS` dropdown to settings page (30/60/90/120/240)
  - Uses `Engine.max_fps` property
  - Defaults to 60 FPS
  - Persists for the session

---

## Agent Specializations

### 1. **GDScript Code Review Agent**
**Best for**: Code optimization, bug fixes, refactoring

**Responsibilities**:
- Check for proper `@onready` initialization
- Validate physics query parameters
- Ensure signal connections are cleaned up
- Review performance-critical paths (raycasting, particle spawning)

**Files to monitor**: `player.gd`, `pause_menu.gd`, `dust_cloud.gd`

### 2. **Scene & UI Agent**
**Best for**: UI improvements, scene hierarchy, node management

**Responsibilities**:
- Add/modify UI elements in pause menu or HUD
- Organize scene hierarchy
- Configure CanvasLayer layers
- Manage OptionButton/CheckButton connections

**Files to monitor**: `main.tscn`, `pause_menu.gd`

### 3. **Gameplay Feature Agent**
**Best for**: New mechanics, input handling, player interactions

**Responsibilities**:
- Implement new building mechanics
- Add player feedback (sounds, particles, animations)
- Expand color system or brick types
- Enhance raycasting logic

**Files to monitor**: `player.gd`, `brick.tscn`

### 4. **Settings & Configuration Agent**
**Best for**: Options menus, performance tuning, project settings

**Responsibilities**:
- Add new settings (graphics, audio, gameplay)
- Wire settings to engine properties (`Engine.max_fps`, `DisplayServer.*`)
- Persist user preferences
- Balance performance vs quality

**Files to monitor**: `pause_menu.gd`, `project.godot`

---

## Quick Debugging Checklist

- [ ] Physics layers correctly configured for brick placement queries
- [ ] Camera sensitivity is reasonable (currently `0.002`)
- [ ] Brick preview updates smoothly (should run in `_physics_process`)
- [ ] Pause menu closes cleanly and returns mouse control
- [ ] FPS cap applies immediately on selection change
- [ ] No unused imports or orphaned nodes in scenes

---

## Build & Export

- **Main executable**: `Bricklayer.exe` (Windows)
- **Package**: `Bricklayer.pck` (game data)
- **Export preset**: Configured in `export_presets.cfg`
- **Icon**: `icon.svg`

---

## Future Enhancements

Potential agent tasks:
- Add sound effect controls to settings
- Implement undo/redo for placed bricks
- Add multiple terrain types
- Create brick shape variations
- Add multiplayer or server sync
- Optimize particle pooling
- Add on-screen FPS counter
- Implement save/load for creations

