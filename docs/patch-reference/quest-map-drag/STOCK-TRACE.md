# Stock trace and build profiles

This utility supports the two Steam executables that ship for Majesty Gold HD:

| Profile | File version | SHA-256 of pristine reference executable |
| --- | --- | --- |
| Default Public | 1.5.2.24 | `AA9BE61DC095773CCC5C08B9E5729A30EE856258249371C5189CE52FB675DB00` |
| beta2 Steam Multiplayer Support | 1.5.2.28 | `99848B5DB16CC3EA540D7E909CB24966AD9F3CD15D302CDE47AAB3BA81E3167E` |

The installer does not require the whole-file hash because other utilities may
already have made recognized, non-overlapping edits. It selects the profile by
strictly matching the untouched entry bytes of the build's stock quest-map
rebuild routine, then validates the exact hook and cave bytes it owns.

## Stock lifecycle used by the patch

The closest stock mechanism is the quest-map input callback itself. Both builds
perform one synchronous input/update pass in the menu thread, calculate the map
rectangle and scroll coordinates, draw/update the map, and then dispatch the
clicked control. There is no worker thread, timer, watcher, or separately owned
UI object.

The hook is immediately after the stock coordinate-projection call:

| Stage | Default Public | beta2 |
| --- | --- | --- |
| Projection call | `0x0047ABB0 -> 0x0045ECC0` | `0x00479388 -> 0x0045FCF0` |
| Hook (file / VA) | `0x79FB5 / 0x0047ABB5` | `0x7878D / 0x0047938D` |
| Displaced scroll-coordinate loads | `[esp+0x40] -> eax`, `[esp+0x20] -> ecx` | `[esp+0x48] -> eax`, `[esp+0x24] -> edx` |
| Continuation | `0x0047ABBD` | `0x00479395` |
| Map bounds on the callback stack | `0x74, 0x78, 0x7C, 0x80` | `0x78, 0x7C, 0x80, 0x84` |
| Stock `GetKeyState` IAT slot | `0x0073547C` | `0x0074E538` |
| Stock cursor-coordinate thunk | `0x00635370 -> 0x006352D0` | `0x0064A7B0 -> 0x0064A710` |

beta2 adds multiplayer-related locals and state to this callback. The port uses
beta2's actual registers and shifted stack slots; it does not reuse the public
offsets speculatively.

On each pass, the patch preserves all registers, asks the stock key-state import
for the left mouse button, and uses the stock cursor-coordinate thunk. While the
button is held inside the stock map rectangle, it applies the cursor delta to
the two stock scroll locals before executing the displaced loads. The rest of
the stock callback therefore consumes the adjusted coordinates in its original
order.

Five process-local dwords hold the drag marker, previous cursor coordinates,
and current cursor coordinates. The marker is cleared synchronously whenever
the button is up or the cursor leaves the stock map rectangle. No heap object or
callback is registered, so there is no separate destructor or cancellation
owner. Closing the process clears all state; a later input pass also clears a
stale marker as soon as the stock key/bounds test fails.

## Cave and state ownership proof

The two cave-based QoL utilities reserve one adjacent, non-overlapping tail in
each executable. Quest Map Drag owns only the first range:

| Profile | `.text` virtual/raw tail | Quest Map Drag | Unlock All Quests |
| --- | --- | --- | --- |
| Public | zero bytes `0x33427D..0x3343FF` | `0x334280..0x334329` (`0xAA`) | `0x33432A..0x3343FF` (`0xD6`) |
| beta2 | zero bytes `0x34C60D..0x34C7FF` | `0x34C610..0x34C6BC` (`0xAD`) | `0x34C6BD..0x34C792` (`0xD6`) |

For beta2, `.text` has RVA `0x1000`, raw pointer `0x400`, virtual size
`0x34C20D`, and raw size `0x34C400`. Thus the selected bytes are zero-filled,
loaded, and executable, and `0x34C793..0x34C7FF` remains unclaimed.

The public state is `0x007C25E0..0x007C25F3`. beta2 uses
`0x007E1150..0x007E1163`. The latter lies in `.data`'s loader-zeroed region
(initialized raw data ends at VA `0x007DF200`) and in a direct-reference gap
between stock addresses `0x007E1040` and `0x007E20E8`. The pristine beta2 text
contains no direct reference to any byte in the owned state range.

Install writes only the exact hook and owned cave. Restore requires both to
match this profile byte-for-byte, restores the displaced stock bytes, and zeros
only this utility's cave range.
