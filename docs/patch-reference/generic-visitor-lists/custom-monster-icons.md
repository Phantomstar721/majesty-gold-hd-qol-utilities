# Custom monster icon contract

Generic Visitor Lists delegates monster icon selection to Majesty's stock
`IX92` / `IX94` resolver. A mod that can place monsters in an occupant list
must satisfy the resolver's resource contract in every dataset where that can
happen.

## Required shared resources

The dataset must load both stock monster-icon IMAG records:

- `IX92monster icons`
- `IX94monstor icons n` (the misspelling is stock)

Their IMAG data uses positional TILE references. The CAM that exposes them must
therefore also contain the complete TILE table from the same
`DataMX/mx_interfacedata.cam` source, preserving entry order and the stock TILE
section padding. Copying only the IMAG records produces invalid references.

Base quests do not normally load these expansion interface resources. Put the
records and positional table in an interface-data CAM loaded by the mod's
`<Dataset base="Any">`, conventionally `Data/<mod>_interfacedata.cam`.
Restore Abandoned Zoo's `restore_zoo_interfacedata.cam` is the validated local
example.

## Adding a custom monster icon

A custom monster additionally needs:

1. A 25x25 indexed icon frame compatible with Majesty's interface palette and
   image format.
2. An entry in the loaded `IX92` or `IX94` record whose associated
   four-character type ID exactly matches the custom character's runtime unit
   description ID.
3. The new tile payload and an updated positional TILE table packaged with the
   augmented atlas record.

Map sprites, the primary-panel portrait, and `ImageIDBase` alone are not used
by the stock monster-atlas lookup.

## Compatibility warning

Majesty treats `IX92`, `IX94`, and their TILE table as complete resources; it
does not merge two mods' additions. An augmented record must preserve all stock
entries. Two independently augmented copies conflict by load order until a CAM
merge tool combines their deltas. Never ship a shortened atlas containing only
the custom frame, because it can remove the mappings for stock monsters.

## Threat Rank data

The generic visitor patch also uses a custom monster's ordinary character XML
experience bounty:

```xml
<Game version="1">
    <Experience value="800"/>
    <!-- the rest of the monster's stock-style game data -->
</Game>
```

At runtime this is `ATTRIB_LevelXP`, the same attribute stock combat awards to
the hero that defeats the monster. Any positive value automatically maps to
Threat Rank 1-8; no per-monster executable entry is required. Zero or missing
XP leaves the row's stock level value unchanged. See the README for the exact
rank bands.
