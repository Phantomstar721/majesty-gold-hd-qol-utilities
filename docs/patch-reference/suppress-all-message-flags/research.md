# Message-flag patch research

## Target builds

- Default Public: Majesty Gold HD 1.5.2.24 (Steam, 32-bit), constructor
  VA/file `0x00449690` / `0x48A90`
- beta2 Multiplayer Support: Majesty Gold HD 1.5.2.28 (Steam, 32-bit),
  constructor VA/file `0x0044A5A0` / `0x499A0`
- image base: `0x00400000`
- stock sections: `.text`, `.rdata`, `.data`, `.rsrc`

The profiles use each build's PE version and linker timestamp, then guard the
instruction bytes and unchanged constructor tail at the target. Compatible QOL
patches elsewhere in the executable do not prevent installation.

## Call path

The GPL native registration table binds `MessageFlag` to `0x00431840` on Public
and the corresponding `0x004327A0` handler on beta2. Each handler resolves its
unit/location, optional third argument, player controller, and message
identifier, then makes the executable's only direct call to its constructor:

```text
Public  0x00449690  message-flag constructor
beta2   0x0044A5A0  message-flag constructor
```

The constructor's first six bytes are:

```text
8B 4C 24 10    mov ecx,[esp+10h]
56             push esi
57             push edi
```

At Public file offset `0x48A90` and beta2 file offset `0x499A0`, the patch
replaces them with:

```text
C3             ret
90 90 90 90 90 nop padding
```

The routine is void and uses caller stack cleanup. Its sole direct caller does
not consume a return value, so the early return preserves the caller's stack and
control flow.

## Effects covered by the same routine

The stock body supplies `MSGF` and `ARE1` to the engine object factory, attaches
the banner action, and displays it. It then:

- checks `ZoomMessageFlags` and calls the mini-camera target routine when allowed;
- asks the sound manager to play event `ME02`, subtype `EBE0`.

Returning before the body therefore suppresses the icon, sound, and focus as one
atomic behavior. No general sound-manager, camera, action, or object-factory
routine is patched.

## Scope and tradeoff

`IsMessageFlagPresent` remains stock. Since suppressed flags are never inserted,
it reports false for them. That is intentional and is the closest semantic match
to "the flag was never shown."

The shipped GPL sources contain 12 `IsMessageFlagPresent` calls: six original-game
calls plus their six Northern Expansion counterparts. They are confined to the
Bell, Book and Candle and Forsaken Lands scripts. Each advances a sequence after
the preceding flag is dismissed and then sets a one-time `Message_Check_*` latch.
With this patch those informational sequences advance immediately, once, rather
than waiting for banners the player cannot dismiss. No stock victory condition is
gated on a message flag being present.

Reward flags use separate `RewardFlag` / `PlaceRewardFlag` paths and are not
affected. The message text is not moved to another UI surface; it is suppressed
with the flag.
