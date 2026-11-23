# Stock lifecycle and beta2 relocation trace

## Builds and selection

The two reference executables are:

| Profile | File version | Pristine SHA-256 |
| --- | --- | --- |
| Default Public Version | 1.5.2.24 | `AA9BE61DC095773CCC5C08B9E5729A30EE856258249371C5189CE52FB675DB00` |
| beta2 Steam Multiplayer Support | 1.5.2.28 | `99848B5DB16CC3EA540D7E909CB24966AD9F3CD15D302CDE47AAB3BA81E3167E` |

Install and restore share `scripts/MajestyBuildProfiles.ps1`. A profile must
match the COFF timestamp, image/file alignment, header size, image base, and all
fields of the first four stock section headers. Appended private sections do not
change that identity. Hook validation then accepts only the selected profile's
stock bytes or this utility's exact calculated hook.

## Stock-equivalent address trace

Static disassembly traced the same surrounding instructions, arguments, list
owners, and callees in both builds:

| Role | Public VA / file | beta2 VA / file |
| --- | --- | --- |
| startup/menu restore dispatch | `478930` / `077D30` | `477090` / `076490` |
| Mods OK save dispatch | `524D96` / `124196` | `539656` / `138A56` |
| original Mods OK handler | `5253E0` | `539CA0` |
| canonical apply-active-mods routine | `525540` | `539E00` |
| canonical Active-list node routines | `522340`, `5223F0` | `536C00`, `536CB0` |
| installed-mod list owner | `7C1E30` | `7E09A0` |
| Active-list owner/sentinel | `7C1E38`, `7C1E4C` | `7E09A8`, `7E09BC` |
| Active-list dirty flag | `7C1DFC` | `7E096C` |

The CRT IAT operands are likewise relocated: public `fprintf/fopen/fread/fclose/sscanf`
at `7353E0/735430/735434/735444/73544C` map to beta2
`74E3E0/74E428/74E42C/74E43C/74E450`.

## Complete lifecycle

Construction and ownership remain Majesty's. The installed-mod and Active-mod
lists, their nodes, the dirty flag, and the effective mod configuration are all
stock objects. The patch owns only code, strings, temporary parsing storage,
and the preference filename.

The public payload's parsing storage is one contiguous, process-lifetime
scratch arena at `7BD900..7BDD2F`: a `0x400`-byte `fread` buffer, eleven dwords
written by `sscanf`, and one temporary matched-node pointer. All 27 absolute
operands were traced: three name the input buffer and two name each dword. The
public build maps that arena writable in `.data`, so its established output is
unchanged. In beta2, however, the same VAs fall in read-only `.rdata`; writing
the `fread` bytes, NUL terminator, or parsed fields there would fault.

For beta2 only, the installer relocates those exact operands and their unchanged
relative layout to `.mpst+700..B2F`. The beta2 profile therefore marks this
private section code/execute/read/write (`E0000020`); the public profile keeps
the original code/execute/read (`60000020`) characteristics. Image mapping
zero-initializes the arena, each restore dispatch overwrites it synchronously,
and nothing retains a pointer after the wrapper returns. There is no allocation,
new state machine, callback, cancellation path, or cleanup responsibility.
Strict relocation counts make installation fail before writing if any operand
is added, removed, or changes shape.

Restore likewise classifies both dispatch sites before mutation. Each must be
either the selected build's exact stock call or this section's exact hook. A
recoverable stock/hook mix left by an interrupted install is unwound, while any
unknown byte aborts before `.mpst` can be zeroed or removed.

Save dispatch occurs at the stock Mods screen OK call. The wrapper first calls
the exact stock apply-active-mods routine displaced at that site. It then saves
registers, opens the preference file, walks the stock Active-list sentinel in
stock order, writes each stock GUID, closes the file, restores registers, and
returns to the unchanged OK handler. Cancel never reaches this OK-only hook.
File-open failure takes the existing no-save exit and changes no stock state.

Restore dispatch occurs at the corresponding stock startup/menu Mods handler
call. The wrapper preserves the original handler call and argument shape, reads
saved GUIDs, walks the stock installed-mod list, and ignores absent GUIDs. It
checks the Active list before insertion, so repeated dispatch cannot duplicate
a node. Matches are inserted through the same paired stock node routines used
by the Mods UI, the stock dirty flag is set, and the canonical apply-active-mods
routine runs once after reconstruction. This is the stock commit that owns XML
description/build-menu refresh; no replacement UI refresher exists here.

All work is synchronous at those two stock dispatch points. There are no
threads, timers, polling hooks, deferred callbacks, or cancellation objects.
Every successfully opened file is closed on its success/failure path; register
state is restored before returning. Uninstall restores both stock calls
immediately. If a later PE section must retain its address, `.mpst` is zeroed
and kept inert until it can safely become the last section and be removed.
