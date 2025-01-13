# Internal Overhaul Patch

This patch contains a significant overhaul of Cybersyn's internal systems, particularly focusing on combinators, train stops, and layout detection/automatic allowlist.

The patch is significantly larger than I intended it to be. Every time I pulled on a thread three more would unravel, and I ultimately ended up rewriting a significant portion of the mod. Unfortunately these systems were pretty spaghettified and if we want to overhaul it there is no good smaller patch. We just have to rip the band aid off all at once.

This patch is intended to not break userspace. Once everything is tested and complete, users who are using Cybersyn as described in the documentation should not have their saves break. However, that being said, two important things to note:

1) This patch fixes numerous bugs and nondeterministic situations that existed in previous versions of Cybersyn. It may be the case that some users were building stations that actually relied on these bugs or happened to work in spite of them. Any such station is likely to break.

2) **WARNING: THIS PATCH CONTAINS IRREVERSIBLE DATA MIGRATIONS.** Internal saved state has been considerably reworked. Once these migrations have been applied to a save file, it is impossible to use that save file with older versions of Cybersyn. **When testing this patch, back up and duplicate your save file, and only run this patch on forked save files!**

## User-facing changes

- Combinators: Fixed issue where saving with an open combinator UI would make it impossible to open a combinator UI after reloading. (Migration will fix this for existing saves by force-closing all UIs.)
- Combinators: UI has been redesigned; options may appear in slightly different positions than in prior versions. (The functionality of the options has not changed.)
- Layout engine: The stretch of rail behind the train stop that is considered part of the layout must now consist of only non-elevated straight rails. This fixes various issues with strange allow lists near elevated rails, diagonals, and curves.
- Layout engine: Finding a stop from a rail now uses the same algorithm as the rest of the layout engine. This fixes various issues where changing equipment beside a rail wouldn't update the allow list properly.
- Layout engine: When associating combinators far from a station (e.g. wagon control) the combinators will prefer to associate with the station along the rail their output end is pointing towards. (This only applies when the combinators are ambiguously sandwiched between rails.)
- Layout engine: Fixed multiple stations along a single rail line having overlapping allow lists.
- Added a new map setting, "Enable debug overlay" - when enabled, overlays will be rendered over various Cybersyn objects showing information about their internal state.

## Remote interface changes

Due to the size of this PR, I avoided making updates to the remote interface, which can be done separately. Generally speaking, I tried not to break the existing remote interface, however in some cases it is simply inevitable.

- Due to major changes in internal data layout, consumers of `interface.read_global` and `write_global` will need to check their code. (See `global.lua` and `types.lua`)
- The remote event `on_combinator_changed` is obsolete and has been removed. This will be replaced with exposed versions of the new internal combinator events at a later time.
- `interface.get_id_from_comb`, `interface.combinator_update`, `interface.update_stop_from_rail` removed.

## Internal changes

### Internal event system
Cybersyn now has an internal event backplane, implemented in `events.lua`. The changes to combinators and train stops take advantage of this new system. There is still much work to be done on the mod's other systems, but I hope to eventually have all of the mod's major systems running on an event driven model This will make it much easier to extend the mod in the long term.

### Combinator abstraction
- Combinators are now treated as abstract state objects distinct from the game world entities representing them.
- Rather than a single combinator entity, a list of game entities (given in `combinators/base.lua`) can now be provided, all of which will be treated as combinators.
- Distinguish between "settings" of a combinator (data that must be stored in blueprints/present on ghosts) and "state" of a combinator (information only present on real combinators in live gameplay)
- Introduces an ephemeral combinator abstraction, which is a combinator that has settings but does not necessarily have state. (e.g. a ghost)
- Introduce APIs for creating, reading from, and writing to the settings and state of a combinator.
- Combinator UI now uses a totally isolated UI state vector and no longer pollutes the main state vector.
- The modal section of the combinator UI is now generated dynamically based on the combinator mode, rather than through showing/hiding of static elements.

### Train stop abstraction
- Train stops are now treated as abstract state objects. The abstraction unifies over depots, refuelers, and stations.
- All Cybersyn train stops now have stop layout. (Depots do not use the generated allow-list, but technically they now have one internally.)
- Stop layout computation algorithm has been rewritten for correctness and determinism.
- Stop equipment detection now uses caching to avoid rebuilding the entire stop layout every time a piece of equipment is built.
- Loading equipment layout is stored in the stop state on a per-tile basis.
- Stop loading equipment patterns no longer contain `nil` entries. `0` is used to represent a car with no equipment alongside it.


### Layout engine rewrite
- Rules of Combinator Association:
  - S is the set of all train stops in the yellow radius of the combinator. R is the set of all straight rails in the yellow radius of the combinator.
  - If S is nonempty, the stop in S that is closest to the front of the combinator (output side) is the associated stop.
  - If S is empty but R is nonempty, the rails in R are checked, beginning from the rail closest to the front of the combinator (output side) and moving towards more distant rails. The first such rail that is in the railset of a stop, that stop is the associated stop.
  - If no stop can be found according to these rules, the combinator is orphaned.
  - Events That Trigger These Rules:
    - If a new combinator is built, it is re-associated.
    - If a new stop is built, all combinators for which the new stop would be inside the yellow radius are re-associated.
    - When new rails are built, it's checked if the rail would affect the layout of a stop; if so, the stop's layout is recomputed.
    - When the layout of a stop is recomputed, all combinators within the bounding box, as well as all previously associated combinators, are re-associated.
    - When a stop is destroyed, all formerly associated combinators are re-associated.
    - When a combinator is rotated, it is re-associated.

