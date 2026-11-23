# Generic visitor-list patch research

## Target builds

| Steam branch | Version | COFF timestamp | Stock SHA-1 | Stock size |
| --- | --- | --- | --- | ---: |
| Default Public Version | 1.5.2.24 | `0x5897B72F` | `D3EE878D6B6532D8E20CC2B8BDE3A4F6753208A4` | 3,933,696 |
| beta2 / Steam Multiplayer Support | 1.5.2.28 | `0x5A8A11D5` | `950D47593F4C5C833432AFD3BBF2E28FE908A2EB` | 4,056,064 |

Both are 32-bit PE images based at `0x00400000`. The installer selects a build
only when its timestamp and the name, virtual size, RVA, raw size, raw offset,
and characteristics of all four stock sections agree. Appended QoL sections do
not affect that identity. Every changed site is then guarded by its selected
build's exact expected bytes, together with the stock resolver, classifier, and
attribute-getter signatures.

The detailed lifecycle addresses below use the public build. Static comparison
and disassembly of beta2 confirmed the same construction, category dispatch,
descriptor ownership, draw ordering, and cleanup. Its exact port is:

| Role | Public VA / file | beta2 VA / file |
| --- | --- | --- |
| category gate | `0x004985D5` / `0x000979D5` | `0x00498C05` / `0x00098005` |
| icon dispatch | `0x00498418` / `0x00097818` | `0x00498A48` / `0x00097E48` |
| level/threat call | `0x004986D1` / `0x00097AD1` | `0x00498D01` / `0x00098101` |
| display classifier | `0x00508510` / `0x00107910` | `0x0050A6E0` / `0x00109AE0` |
| monster resolver | `0x004BB0A0` / `0x000BA4A0` | `0x004BBAE0` / `0x000BAEE0` |
| attribute getter | `0x005B9FD0` / `0x001B93D0` | `0x005CEF70` / `0x001CE370` |
| hero-icon resume | `0x00498421` | `0x00498A51` |
| monster-icon resume | `0x0049847D` | `0x00498AAD` |

The beta2 category gate retains the same stock displacement to cleanup and the
same patched displacement into its category-1 renderer. Its icon site also has
the identical nine displaced stock bytes. The beta2 level call originally
targets its own `0x005CEF70` attribute getter; the profile preserves that exact
tail rather than reusing a public-build address.

## Complete stock row lifecycle

The building Visitors command opens the stock visitor controller. Its refresh
routine at `0x00497E20`:

1. clears the stock list control `0x1388`;
2. iterates the selected building's occupant agents;
3. formats each agent through stock formatter `0x004422F0`;
4. inserts one row;
5. assigns the formatted text through property `0x60`;
6. assigns the agent ID through property `0x25`;
7. restores selection and refreshes the stock panel.

That lifecycle is already generic. Live inspection verified that monster rows
contain the correct text and unit ID, remain selectable, and open the correct
monster primary panel.

During painting, the visitor controller resolves the row's agent and calls
`0x00508510`, Majesty's stock display-category classifier. At
`0x004985C9-0x004985DB` it dispatches category 1 to the stock hero row,
category 2 to the existing alternate row, and every other category directly to
cleanup at `0x00498A91`.

The category-1 block at `0x004986A5-0x00498819` is itself unit-generic. It uses
stock attributes and helpers to draw level, name, current action, and current /
maximum hit points. A live Harpy, Medusa, and Troll test confirmed that the
block renders all four fields without fabricated per-monster data.

The level lookup at `0x004986C2-0x004986D6` passes
`ATTRIB_ExperienceLevel` (`0x0B565041`) to the stock attribute getter at
`0x005B9FD0`. Hero births initialize that attribute to at least 1. Ordinary
monsters do not, which is why the generic renderer originally showed 0.

Stock character XML maps a monster's `<Experience>` value to
`ATTRIB_LevelXP` (`0x0A565041`). The monster branch of stock combat reads that
attribute in `mx_make_attack.gpl` and awards it to the attacker. It is therefore
the closest stock-authored, unit-generic scalar for designer-perceived monster
strength. It is not a stock monster level.

Before category dispatch, stock constructs a row image descriptor from the
occupant's image ID and interface set `1002` (`Interface-02`). Heroes normally
carry that icon directly in their unit image record. Stock monsters instead
use consolidated interface resources `IX92` and `IX94`.

Stock function `0x004BB0A0` initializes the same descriptor class used by the
visitor painter, loads `IX92`, searches its embedded type-ID mapping, falls
back to `IX94`, applies the stock `BVs1` to `BVn1` and `BVm1` to `BVA1`
aliases, selects the matching frame, and leaves ordinary descriptor drawing
and destruction to the caller.

## Patch

Stock at `0x004985D5`:

```text
0F 85 B6 04 00 00    jne 0x00498A91
```

Patched:

```text
0F 85 CA 00 00 00    jne 0x004986A5
```

Category 1 still falls through to its original renderer. Category 2 still
falls through to its original alternate renderer. Only the categories that
stock would discard are redirected to the already-existing category-1 row.

At `0x00498418`, the icon patch redirects descriptor setup to a relocatable
58-byte dispatcher at `.mgvl+0x80`. Categories 1 and 2 replay the displaced
stock instructions and resume the untouched direct-image path at `0x00498421`.
Other categories pass the existing row image descriptor and occupant unit-type
descriptor to `0x004BB0A0`, then resume at `0x0049847D`. Row geometry, draw
order, selection, and descriptor cleanup remain stock.

At `0x004986D1`, the level attribute call is redirected to a converter in a
dedicated executable/readable `.mgvl` PE section. The installer calculates the
section's RVA and relative call targets from the executable's current last
section, so both routines remain private to this patch and do not occupy
another utility's section padding. The converter repeats the same stock
display-category classification already used by the row painter:

1. category 1 (hero) and category 2 take an exact tail call to the original
   `ATTRIB_ExperienceLevel` lookup;
2. other categories query `ATTRIB_LevelXP` through the same stock getter;
3. a non-positive result falls back to the original level lookup, preserving
   generic non-monster occupants without XP data;
4. a positive result is converted to Threat Rank 1-8 for the current paint
   operation and returned without modifying the unit.

The seven thresholds are `230, 400, 500, 900, 1500, 2000, 3500`. They split
the 48 positive-XP monster descriptions in stock `M_Characters.xml` and
`MX_Characters.xml` into approximately even groups. Exact equality at 1500
and 2000 keeps tied monster bounties in the same rank, so the resulting group
counts are `6, 6, 6, 6, 7, 7, 4, 6`.

The stock resolver assumes `IX92` and `IX94` are loaded. Its ordinary caller is
an expansion interface that satisfies that precondition. A first base-quest
test without the atlases faulted in the stock list accessor at `0x00668104`.
Loading literal `IX92`/`IX94` records and their full positional TILE table
through the consuming mod's interface CAM satisfied the stock precondition;
the same Deal with a Demon test then rendered Harpy and Troll icons correctly.

## Scope and tradeoffs

This is a display-only patch. It does not add occupants, change building
capacity, alter entry/exit behavior, or create a new UI controller.

Units without a meaningful hero level display whatever their stock Level
attribute contains unless they have a positive `LevelXP`, in which case the
level column displays the mod-authored Threat Rank. Their action and HP are
likewise read live from stock unit state.

Threat Rank is deliberately display-only. The bands are an invented
interpretation of a real stock value and do not claim to reconstruct a missing
stock monster-level system. Custom monsters participate generically by
supplying a positive `<Experience>` value; values outside the stock range are
capped at rank 8.

The installer can append `.mgvl` to either the stock four-section executable
or an executable carrying the other QoL patch sections. If `.mgvl` is the last
section, uninstall restores the original section count and image size and
truncates the appended raw data. If a later patch section depends on the PE
layout, uninstall restores all call sites and zeros `.mgvl` in place; a later
uninstall pass removes that inert section once it becomes last.
