# Bricklayer

Bricklayer is a first-person 3D sandbox game built in Godot where you mine, collect, and place voxel-like blocks in a procedurally generated world.

## Features

- First-person mining and block placement
- Infinite chunk-based procedural terrain
- Inventory hotbar with stack-based resources (wood and ground blocks)
- Dynamic tree generation
- Pause menu settings:
  - Resolution (1280x720 to 3840x2160)
  - FPS cap
  - Render distance
  - Graphics toggles (SDFGI, SSAO, SSIL, fog, shadows)
- Keyboard/mouse and gamepad support
- Chunk performance controls and telemetry for profiling

## Tech Stack

- Engine: Godot 4.6 (Forward Plus)
- Language: GDScript
- Physics: Jolt Physics (3D)

## Quick Start

### Prerequisites

- Godot 4.6 or newer

### Run Locally

1. Clone this repository.
2. Open the project in Godot.
3. Run the main scene (`res://main.tscn`) or press `F5`.

## Controls

### Keyboard and Mouse

- `W/A/S/D`: Move
- `Mouse`: Look
- `Space`: Jump
- `Left Click`: Mine/harvest
- `Right Click`: Place block
- `1-9`, `0`: Select hotbar slot
- `F1`: Toggle controls help
- `Esc`: Pause menu

### Gamepad

- `Left Stick`: Move
- `Right Stick`: Look
- `A`: Jump / menu select
- `LT`: Place block
- `RT`: Mine/harvest
- `LB / RB`: Cycle hotbar slot
- `Start`: Pause menu
- `B`: Back / close menu

## Platform Defaults

- Desktop default: 1920x1080 at 60 FPS
- Linux default: 1280x800 at 40 FPS
- Web default: 1280x720 at 30 FPS

## Export Targets

Configured in `export_presets.cfg`:

- macOS -> `Export/MacOS/Bricklayer.zip`
- Windows Desktop -> `Export/Win64/Bricklayer.exe`
- Web -> `Export/Web/index.html`
- Linux -> `Export/Linux/Bricklayer.x86_64`

## Performance Notes

- Chunk generation is staged and budgeted per frame to reduce frame spikes.
- Generation work is queued and processed by configurable limits.
- Optional telemetry can be enabled in `ground_generator.gd`.

Key tuning fields:

- `chunk_load_budget_ms`
- `max_chunks_loaded_per_frame`
- `perf_debug_enabled`
- `perf_spike_threshold_ms`
- `perf_frame_budget_target_ms`
- `perf_log_queue_age_stats`
- `perf_stage_log_threshold_ms`

## Roadmap

- Save/load support for chunk modifications
- Multiplayer-oriented networking for world edits

## License

MIT

## Credits

- Alexander Novash
