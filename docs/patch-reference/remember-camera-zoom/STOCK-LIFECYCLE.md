# Stock lifecycle and beta2 relocation trace

## Builds and selection

| Profile | File version | Pristine SHA-256 |
| --- | --- | --- |
| Default Public Version | 1.5.2.24 | `AA9BE61DC095773CCC5C08B9E5729A30EE856258249371C5189CE52FB675DB00` |
| beta2 Steam Multiplayer Support | 1.5.2.28 | `99848B5DB16CC3EA540D7E909CB24966AD9F3CD15D302CDE47AAB3BA81E3167E` |

Install and restore share `scripts/MajestyBuildProfiles.ps1`. The COFF
timestamp, PE geometry, and every field in the four stock section headers must
match before any build-specific site is used.

## Stock-equivalent address trace

| Role | Public VA / file | beta2 VA / file |
| --- | --- | --- |
| constructor's default-zoom setter call | `5DDCC6` / `1DD0C6` | `5F3006` / `1F2406` |
| stock zoom setter | `5DD910` | `5F2C50` |
| primary camera setter vtable slot | `749288` / `348688` | `763358` / `361B58` |
| runtime camera setter vtable slot | `73B810` / `33AC10` | `7548E0` / `3530E0` |

Both constructor calls have the identical stock `E8 45 FC FF FF` encoding in
their respective builds. Both beta2 vtable slots point to `5F2C50`, just as the
public slots point to `5DD910`. CRT `fopen/fread/fwrite/fclose` IATs map from
`735430/735434/735438/735444` to
`74E428/74E42C/74E430/74E43C`.

## Complete lifecycle

Construction remains stock: the camera constructor pushes `1.0`, calls the
stock zoom setter, and continues its normal initialization. The constructor
hook redirects only that call to the restore wrapper. The wrapper saves
registers, synchronously reads one float, accepts only `0.5` through `3.0`, and
replaces the already-pushed argument when valid. It then restores registers and
tail-jumps to the same stock setter. Missing, short, or invalid files leave the
stock `1.0` argument unchanged.

Runtime dispatch remains the stock virtual call. The two stock vtable entries
that owned zoom changes are redirected to the save wrapper. It captures the
unchanged float argument, writes it synchronously, restores registers, and
tail-jumps to the stock setter. The setter still executes exactly once and
continues to own camera fields, derived projection values, and visible refresh.

Every successful file open is closed on both wrappers' completed I/O path.
There are no new objects, timers, threads, polls, deferred callbacks, or
cancellation state. File failure simply follows the stock setter path.
Before uninstall removes or zeroes `.mczp`, it classifies all three owned sites.
Every site must contain either its exact stock bytes or this section's exact
utility-owned hook. This makes a stock/owned mix from an interrupted install
recoverable while rejecting any unknown or damaged byte before the executable
is written. The rule also preserves the verified historical public two-hook set
(constructor plus primary vtable, with the runtime vtable still stock) installed
before the runtime-camera fix; beta2 never had that legacy release. A fully
stock hook set is accepted only with an already-inert `.mczp`. If a later
section depends on PE addresses, the verified `.mczp` section is zeroed and
retained until safe removal.
