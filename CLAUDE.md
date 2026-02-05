This is **FCar**, a Godot 4 flying car game set in a procedurally generated vertical cyberpunk city.

## Core Architecture

**Main Scene:** `city/city_test.tscn` - the primary test environment

**Player Vehicle:** `fcar/FCar.gd` - a physics-based flying car with:
- Wheel-based thrust system (4 wheels with individual thrust vectors)
- Control locking system (F + key to toggle, double-tap X for handbrake lock)
- Passenger/fare system for taxi gameplay
- Height lock, boost, handbrake, pitch/roll/yaw controls

**City Generation:** Procedural modular building system
- `city/BuildingGenerator.gd` - four-pass generation (structural → functional → decoration → spawn zones)
- `city/BuildingBlock.gd` - base class for modular pieces
- `city/ConnectionPoint.gd` - Marker3D-based plug/socket system with type flags (SEED, STRUCTURAL, JUNCTION, CAP) and size flags (SMALL, MEDIUM, LARGE)
- Blocks connect via direction matching (UP↔DOWN, horizontal via yaw alignment)

**People System:** Object-pooled NPCs
- `systems/PeopleManager.gd` - spawning, pooling, fare generation, zone loading
- `systems/Person.gd` - individual NPC with states (WALKING, WAITING, HAILING, BOARDING, RIDING, etc.)
- `systems/SpawnZone.gd` - circular areas where people can spawn
- People use a single shared ShaderMaterial with instance uniforms for per-person color/LOD

**UI System:**
- `ui/ControlDisplayWindow.gd` + `ui/ControlDisplayKey.gd` - visual keyboard showing pressed/locked controls
- `ui/DestinationMarker.gd` - HUD marker for fare destinations
- Various debug windows

## Key Patterns

- **Autoloads:** `CityGrid` is a central registry/autoload for shared references
- **LOD:** People switch to pixel dots at 350m, hide at 500m; use `Person.lod_camera` static reference
- **Pooling:** People are pre-instantiated and recycled via `_acquire_from_pool()` / `_return_to_pool()`
- **Instance Shader Params:** `set_instance_shader_parameter()` on Sprite3D for per-node variation with shared material

## File Locations

- `/fcar/` - vehicle code and components
- `/city/` - city generation, building blocks
- `/systems/` - people, spawning, game systems
- `/ui/` - HUD and debug UI
- `/mats/` - shaders and materials
