# Bricklayer - Project Agents & Workflow Guide

## Project Overview

**Bricklayer** is a Godot 4.6 first-person 3D building game where players mine and build voxel-like terrain in a dynamically generated world.

### Key Specs
- **Engine**: Godot 4.6 (Forward Plus rendering)
- **Language**: GDScript
- **Platform**: Windows (packaged executable available)
- **Resolution**: 1920×1080 default
- **Features**: First-person camera, procedural ground generation, block mining (HP system), inventory management, dynamic physics occlusion, audio pooling, pause menu with settings

---

## Codebase Architecture

### Core Scripts

| File | Purpose |
|------|---------|
| [player.gd](player.gd) | FPS controller, block mining/placement, inventory management, shared raycasting, and audio pooling |
| [ground_generator.gd](ground_generator.gd) | Infinite Chunk Manager tracking player position to dynamically spawn and despawn `TerrainChunk` instances |
| [terrain_chunk.gd](terrain_chunk.gd) | Individual 16x16 chunk instances processing local 3D noise terrain, tree instantiation, and internal MultiMesh generation |
| [inventory_hud.gd](inventory_hud.gd) | Pre-allocates StyleBoxFlats and manages UI grid for the 10-slot inventory tracking |
| [pause_menu.gd](pause_menu.gd) | Settings UI (render distance slider, resolution, fullscreen, FPS cap), game pause state |
| [birch_tree.gd](birch_tree.gd) | Generates birch tree meshes dynamically above terrain |
| [dust_cloud.gd](dust_cloud.gd) | Particle effect spawned on block manipulation |

### Main Scenes

| File | Purpose |
|------|---------|
| [main.tscn](main.tscn) | Root scene: player, Chunk Manager, UI, block container |
| [terrain_chunk.tscn](terrain_chunk.tscn) | (Usually instantiated by script `terrain_chunk.gd`) |
| [brick.tscn](brick.tscn) | Standard player-placed brick prefab (Root: StaticBody3D with metadata) |
| [ground_block.tscn](ground_block.tscn) | Generated terrain block with shader material for grass/dirt mapping |
| [birch_tree.tscn](birch_tree.tscn) | Tree prefab with optimized mesh collision generation |

---

## Development Conventions

### Input Map
- **W/A/S/D** — Movement
- **Space** — Jump
- **Left Click** — Mine/Hit block (uses HP/damage tinting)
- **Right Click** — Place selected inventory block
- **1-9, 0** — Select inventory hotbar slots 0-9
- **Gamepad LB/RB** — Cycle inventory hotbar slots
- **ESC / Start** — Toggle pause menu

### Optimizations & Core Patterns
1. **Dynamic Terrain Physics (Culling)**: Unseen internal dirt blocks are generated exclusively as a MultiMeshInstance3D draw call. When a player breaks or places a block, on_block_removed() or on_block_placed() evaluates the 6 adjacent cell offsets. Occluded surface blocks revert to MultiMesh, while exposed MultiMesh blocks are instantiated dynamically into physical StaticBody3D blocks to save vast amounts of memory/physics processing.
2. **Audio Pooling**: player.gd uses a pre-allocated array of AudioStreamPlayer nodes cycled round-robin to eliminate initialization latency when rapidly digging or placing blocks.
3. **Single per-frame Raycasts**: Player physics queries are cached per _physics_process into _frame_ray to avoid duplicate intersections between the placement preview and mining functions. 
4. **Pre-allocated GUI Rendering**: Themes, style boxes, and materials are created iteratively in _ready() functions rather than inside _process() loops.
5. **Metadata Tagging**: All interactive bodies utilize .set_meta("hp") and .set_meta("block_type") logic embedded to dictate inventory interactions over class_name dependencies.

### Recent Changes
- **Infinite Chunk Management**: Replaced standard static global terrain mesh with an infinite dynamic chunk loading framework scaling radially according to the Pause Menu Render Distance slider.
- **Dynamic Tree Instantiation**: Refactored static `BirchTree` elements from the scene tree into procedural noise probabilities driven autonomously inside `terrain_chunk.gd`. Erased duplicated/overlapping prefab bug.
- **Occlusion/Fill Optimization**: Implemented run-time adjacent block checking. When blocks are grouped or sealed, they migrate from physics space to visual-only _fill_mmi. This logic is now efficiently localized inside individual `TerrainChunk` instances.
- **Inventory Integration**: Replaced basic color cycling with real resource picking (wood vs ground_block).
- **Physics Model Refactoring**: Rebuilt rick.tscn to ensure StaticBody3D acts as the root node to flawlessly catch pickaxe raycasts.
- **Audio Tuning**: Handled footprint interval and multi-pitch sampling logic to accompany hit_timer based digging rhythms.

---

## Agent Specializations

### 1. **Data Optimization Agent**
**Best for**: Rendering performance, chunk loading, MultiMesh scaling

**Responsibilities**:
- Monitor _rebuild_fill_multimesh array iterations.
- Prevent memory leaks from array resizing or physics body orphanages.
- Investigate Frustum culling patterns.
**Main Focus**: ground_generator.gd, player.gd

### 2. **Scene & UI Agent**
**Best for**: HUD expansions, CanvasLayers, accessibility menus

**Responsibilities**:
- Develop inventory icons, stack-size text rendering.
- Wire graphic toggles to native engine features (Engine.max_fps).
**Main Focus**: main.tscn, inventory_hud.gd, pause_menu.gd

### 3. **Gameplay Feature Agent**
**Best for**: Physics interactions, mining math, block state mutations

**Responsibilities**:
- Control HP damage curves, damage tint calculations (_apply_damage_tint).
- Govern placement raycast grid snapping (_snap_to_grid).
**Main Focus**: player.gd, rick.tscn

---

## Quick Debugging Checklist

- [ ] Ensure Raycast query.exclude successfully includes the player capsule.
- [ ] Physics Rooting: All newly designed blocks *must* have StaticBody3D as their outermost scene root node, otherwise .get_meta() validations will fail silently when struck. 
- [ ] Terrain holes check: Validating adjacent cell offsets must include (0, -1, 0), (0, 1, 0), (-1, 0, 0), (1, 0, 0), (0, 0, -1), (0, 0, 1) and appropriately trigger multimesh_needs_rebuild.

---

## Build & Export

- **Main executable**: Bricklayer.exe (Windows)
- **Package**: Bricklayer.pck (game data)
- **Export preset**: Configured in xport_presets.cfg

---

## Future Enhancements
- Save/Load mechanism for chunk modifications.
- Greedy Networking logic for multiplayer modifications.
