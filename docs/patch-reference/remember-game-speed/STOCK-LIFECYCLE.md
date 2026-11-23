# Stock lifecycle and beta2 relocation trace

## Builds and selection

| Profile | File version | Pristine SHA-256 |
| --- | --- | --- |
| Default Public Version | 1.5.2.24 | `AA9BE61DC095773CCC5C08B9E5729A30EE856258249371C5189CE52FB675DB00` |
| beta2 Steam Multiplayer Support | 1.5.2.28 | `99848B5DB16CC3EA540D7E909CB24966AD9F3CD15D302CDE47AAB3BA81E3167E` |

Install and restore share `scripts/MajestyBuildProfiles.ps1`. Selection requires
the profile's COFF timestamp, PE geometry, and complete first-four-section
layout. Exact stock/patched bytes are then checked at every owned site.

## Stock-equivalent address trace

| Stock lifecycle site | Public VA / file | beta2 VA / file |
| --- | --- | --- |
| slider writes current speed | `46AF18` / `06A318` | `46C218` / `06B618` |
| slower control writes game object | `4644F3` / `0638F3` | `465523` / `064923` |
| faster control writes game object | `464595` / `063995` | `4655C5` / `0649C5` |
| quest restore path 1 | `4D90F9` / `0D84F9` | `4D96E5` / `0D8AE5` |
| quest restore path 2 | `4D9B4A` / `0D8F4A` | `4DA0E9` / `0D94E9` |
| UI/object copy path 1 | `46A0C4` / `0694C4` | `46B304` / `06A704` |
| UI/object copy path 2 | `46A209` / `069609` | `46B449` / `06A849` |
| loaded-game object construction | `484DD2` / `0841D2` | `47C0EB` / `07B4EB` |
| new-quest construction path 1 | `429006` / `028406` | `42ABF2` / `029FF2` |
| new-quest construction path 2 | `429019` / `028419` | `42AC05` / `02A005` |
| stock game accessor | `4D6FC0` | `4D81F0` |
| current-speed global | `7B5304` | `7D3304` |

The public restore sites displace six-byte `mov [global],ecx` instructions.
beta2's corresponding functions update the same object/global state in the same
return paths but use five-byte `mov [global],eax` instructions. The beta2
profile therefore replays those exact five stock bytes and returns at `+5`; it
does not synthesize another state path. CRT `fopen/fread/fwrite/fclose` IATs map
from `735430/735434/735438/735444` to
`74E428/74E42C/74E430/74E43C`.

## Complete lifecycle

Majesty owns the live speed at the game object's `+98` field and mirrors it in
the current-speed global. The patch owns only a four-byte cached value, a
one-byte loaded/dirty flag, and the preference file in `.mskp`.

The slider dispatch replays the stock global write, updates the cache/flag, and
synchronously writes four bytes. The faster/slower dispatches replay the stock
object write before saving the same value. Both return to the original caller;
the stock UI/event path continues to perform its normal refresh.

The two stock quest restore paths first replay their exact displaced global
write. On the first process use, the existing restore block opens and reads the
four-byte preference. A successful read marks the cache loaded and writes the
value through Majesty's stock game object/global owners; open/read failure keeps
the stock value. Later restore calls use the loaded cache without another read.
The two UI copy sites and three stock object-construction sites preserve their
original ordering while substituting the loaded value before handing control
back. The construction sites use the same synchronous load helper, not a timer
or watcher.

Every successful open is paired with `fclose`. No heap object, thread, timer,
poll, callback registration, or cancellation token is created. State lifetime
is the process lifetime of the private section; the preference file is the only
cross-process state. Uninstall restores each exact profile byte sequence.

When `.msrt` (Speedrun Timer) is present, the existing handoff is preserved in
either installation order. Remember Game Speed owns the two shared constructor
sites, its established block tails jump to `.msrt+100/+130`, and uninstall
hands the sites back to the timer's direct `.msrt+140/+160` stubs. beta2 uses
the same argument/order/section-offset contract with its relocated stock sites.
The older runtime-options upgrade hooks existed only for the public build and
are intentionally not guessed for beta2.

Before restore truncates or zeroes `.mskp`, every owned hook site must classify
as the selected build's exact stock bytes, an exact current or supported
public-legacy Remember Game Speed hook, or the exact Speedrun Timer direct
handoff at one of the two shared sites. A stock/owned mix left by an interrupted
install is recoverable. Any unknown byte aborts before mutation, preventing a
branch from being left behind when private code is removed.

If Game Speed is removed before a later Timer, `.mskp` stays inert and its two
shared sites are handed directly to `.msrt`. The Timer can then be removed. A
final Game Speed restore recognizes only the exact direct hooks to the retired
last-section `.msrt+140/+160` placement, changes them back to stock, and removes
the inert `.mskp`; arbitrary jumps are never accepted as a handoff.
