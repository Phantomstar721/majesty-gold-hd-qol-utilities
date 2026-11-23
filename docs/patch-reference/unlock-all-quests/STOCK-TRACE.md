# Stock trace and build profiles

This utility supports the Steam Default Public executable (1.5.2.24, pristine
SHA-256 `AA9BE61DC095773CCC5C08B9E5729A30EE856258249371C5189CE52FB675DB00`)
and the beta2 Steam Multiplayer Support executable (1.5.2.28, pristine SHA-256
`99848B5DB16CC3EA540D7E909CB24966AD9F3CD15D302CDE47AAB3BA81E3167E`).

Profile selection strictly matches the untouched entry bytes of the stock
quest-map rebuild routine. Each owned hook, immediate, cave, and UI string is
then validated separately, so recognized non-overlapping QoL edits can coexist.

## Construction and visibility

The modern stock `APdb` quest menu constructs text control `0x29A` (decimal
666), named `Cheat All Quests`, through the ordinary menu-object virtual call.
Stock immediately passes a false visibility argument:

| Stage | Default Public | beta2 |
| --- | --- | --- |
| Visibility immediate (file / VA) | `0x79AED / 0x0047A6ED` | `0x7829D / 0x00478E9D` |
| Construct/rebuild routine (file / VA) | `0x795D0 / 0x0047A1D0` | `0x77D80 / 0x00478980` |

The patch changes only that boolean immediate from zero to one. It does not add,
clone, remove, or take ownership of a UI record. The CAM edit changes the stock
string `Cheat All Quests` to `Unlock All Quests`; archive entry offsets and the
one string-table size are adjusted in the stock archive structure.

## Click dispatch and map rebuild

The stock quest-menu callback dispatches control IDs synchronously on the menu
thread. The patch checks `0x29A` immediately before the existing comparison with
`0x138A`. A nonmatching ID executes the displaced comparison and rejoins the
stock branch unchanged. A match sets the session byte, preserves registers,
passes the same argument shape (`push 0`, `ecx = edi`), and calls the stock
quest-map rebuild:

| Stage | Default Public | beta2 |
| --- | --- | --- |
| Dispatch hook (file / VA) | `0x7A0EE / 0x0047ACEE` | `0x789C9 / 0x004795C9` |
| Stock passthrough continuation | `0x0047ACF4` | `0x004795CF` |
| Stock handled/input-loop target | `0x0047AB75` | `0x00479339` |
| Stock rebuild | `0x0047A1D0` | `0x00478980` |

The rebuild owns the normal quest controls and lock-cloud refresh. During that
same synchronous call it invokes the stock quest-eligibility predicate twice
while constructing/updating the map:

| Stage | Default Public | beta2 |
| --- | --- | --- |
| Eligibility hook (file / VA) | `0x11BC40 / 0x0051C840` | `0x12C190 / 0x0052CD90` |
| Calls from rebuild | `0x0047A23F`, `0x0047A410` | `0x004789EF`, `0x00478BC0` |
| Stock continuation after displaced SEH prologue | `0x0051C847` | `0x0052CD97` |

When the session byte is zero, the displaced `push -1` and stock exception
handler operand execute before the exact stock continuation. When it is nonzero,
the predicate returns true with the original `ret 4` calling convention. No
victory data, quest record, or persistent save state is fabricated.

## Reset, cancellation, cleanup, and UI refresh

The stock Reset Quests confirmation owns its dialog and cancellation decision.
If the player cancels, control never reaches this utility's reset hook and the
session unlock remains unchanged. If confirmed, stock clears the victory state,
updates its manager, and calls the same quest-map rebuild first:

| Stage | Default Public | beta2 |
| --- | --- | --- |
| Stock confirmed-path rebuild call | `0x0047AE70` | `0x0047974C` |
| Reset continuation hook (file / VA) | `0x7A278 / 0x0047AE78` | `0x78B54 / 0x00479754` |
| Displaced stack comparison | `[esp+0xB4]` | `[esp+0xB8]` |
| Stock continuation | `0x0047AE81` | `0x0047975D` |

Because the first stock rebuild occurs while the session override is still set,
the continuation clears the byte and immediately makes a second call to that
same stock rebuild with the same `ecx`, argument, register preservation, and
cleanup order. The stock routine therefore restores quest locks and cloud
overlays immediately; the patch does not implement a parallel refresh loop.

The flag is process-local loader-zeroed state: public `0x007C25F4`, beta2
`0x007E1164`. beta2's byte lies beyond initialized `.data` (which ends at VA
`0x007DF200`), inside the verified direct-reference gap
`0x007E1040..0x007E20E8`, and has no direct pristine-text reference. Reset owns
explicit cleanup; process exit supplies final cleanup. No timer, thread,
registered callback, or heap allocation exists.

## Cave ownership proof

The public `.text` zero tail is file range `0x33427D..0x3343FF`; the beta2 zero
tail is `0x34C60D..0x34C7FF`. The adjacent reservations are:

| Profile | Quest Map Drag | Unlock All Quests |
| --- | --- | --- |
| Public | `0x334280..0x334329` | `0x33432A..0x3343FF` (`0xD6`) |
| beta2 | `0x34C610..0x34C6BC` | `0x34C6BD..0x34C792` (`0xD6`) |

The installer accepts only an all-stock or an all-owned executable state. The
uninstaller clears the cave only when the entire `0xD6` payload and every hook
match exactly, and it restores only this utility's bytes and string replacement.
