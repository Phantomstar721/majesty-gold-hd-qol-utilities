# Stock tracking-window trace

This patch follows Majesty's existing tracking-camera mechanism literally.
The upper and lower mini-cameras are tracking-manager slots 1 and 2, not
separate camera systems.

## UI identities

| Role | Upper / slot 1 | Lower / slot 2 |
| --- | ---: | ---: |
| Viewport | `0x07D2` | `0x238C` |
| Frame | `0x1172` | `0x2397` |
| Name | `0x1173` | `0x2398` |
| Reward flags | `0x03F7` | `0x2399` |
| Heroes | `0x03F5` | `0x239A` |
| Henchmen | `0x03FD` | `0x239B` |
| Buildings | `0x03F6` | `0x239C` |
| Previous | `0x03F4` | `0x239D` |
| Autoscan | `0x03F8` | `0x239E` |
| Next | `0x03F1` | `0x239F` |
| Zoom main map | `0x0410` | `0x23A0` |

The executable constructs four stock slots: `0x07D2`, `0x238C`, `0x238D`, and
`0x238E`, passing slot numbers 1 through 4 to the same constructor. Modern
APMK layouts expose at least the first two. Taller layouts also expose slot 3.

The visible dialog Track button is repeated in 75 stock SMNU panel resources,
but every copy uses action ID `0x1F41`. Their common action branch gets the
current dialog target and calls the tracking-manager assignment routine with
slot number 1.

## Executable profiles

| Mechanism | Default 1.5.2.24 | beta2 1.5.2.28 |
| --- | ---: | ---: |
| Tracking-manager global | `0x7C12F0` | `0x7DFDA8` |
| Construct all slots | `0x4551B0` | `0x4561E0` |
| Construct one slot | `0x454FD0` | `0x456000` |
| Main state / selected-object owner | `0x425D00` / `+0x48` | `0x426CD0` / `+0x48` |
| Assign target to slot | `0x454DC0` | `0x455DF0` |
| Assignment implementation | `0x4584C0` | `0x4594F0` |
| Controller-ID table | `0x7B5218` | `0x7D3218` |
| ID-to-action inverse | `0x4693A0` | `0x46A5E0` |
| MainFrame event handler | `0x469C90` | `0x46AED0` |
| Tracking tooltip dispatch | `0x46A600` | `0x46B840` |
| Stock tooltip string copy | `0x628350` | `0x63AAF0` |
| Common dialog Track branch | `0x4AF23C` | `0x4AFB2C` |

## Lifecycle

1. The main interface constructs four tracking controllers.
2. Each controller owns its current target identity and miniature-camera state.
3. A controller action resolves the row and converts it to stock slot number
   `row + 1`.
4. Assignment unregisters the old target, stores and registers the new target
   identity, refreshes the slot name/controller state, and requests redraw.
5. The normal update path resolves that identity and follows its world
   position.
6. A missing or invalid target clears the slot and viewport through the stock
   cleanup path.
7. Controller unlink and manager destruction release the observer state.

The patch reuses the lower controller's existing Autoscan control `0x239E`.
Its APMK record remains in its stock layer and keeps its complete native
control shape. Its ID is privatized to `0x7F01` to bypass the stock Autoscan
dispatcher, and its `INTG` animation-set value changes from Autoscan `0x03F2`
to the stock Track frame `0x03E8`. This avoids inventing an unsupported sibling
over the live viewport surface while preventing the original Autoscan action
and tooltip route from claiming the replacement control.

For private ID `0x7F01`, the tooltip hook uses the tracking controller's exact
stock tooltip-copy lifecycle. The destination object is the third dispatcher
argument. The source is Majesty's native 12-byte narrow-string shape: text
pointer, capacity/flags, then length. A focused beta2 live trace of an ordinary
stock tooltip confirmed equal capacity and length (`0x24`) and a clear high
flag byte. The patch embeds that same immutable source-object shape and passes
it to the stock string-copy routine; all other IDs continue through the seven
displaced stock prologue bytes.

The handler copies the stock Control-click assignment path at
`0x469D1B`/`0x46AF5B`: obtain the MainFrame state, read its selected object at
`+0x48`, and call the tracking manager with the selected object and slot `2`.
A null selection is a no-op. The original upper-window dialog Track action and
all other lower controller buttons remain unchanged; this patch intentionally
replaces lower-slot Autoscan.
