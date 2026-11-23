"""Read-only three-profile dismissal-command evidence; no runtime installation.

Uses workspace pefile/capstone. Exact fixture identities only. This bounded audit
does not certify HUD wiring, queue delivery, persistence or live gameplay.
"""
import argparse
import hashlib
import json
from pathlib import Path

import capstone
import pefile


PROFILES = {
    "public": ("255957fb09a4f8d5db6dde6d4127943dea965fa71c1da5db57951302b92e40b4",
               0x4C45C0, 0x5A15F0, 0x4D6FC0, 0x595DC0),
    "beta2": ("05dbd67ae90b2cc14370dabcf3f9e4f9de5dd12c17f85730ac3d237fceec2f82",
              0x4C5000, 0x5B65A0, 0x4D81F0, 0x5A82B0),
    "gog": ("65c6dd32c3d873c2e320bdaa2de1b00488af85b44573fd0fd82f79a2ffd37792",
            0x4C5600, 0x5B58F0, 0x4D88E0, 0x5A9630),
}


def audit(profile, path):
    expected, constructor, resolve, service, submit = PROFILES[profile]
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != expected:
        raise ValueError("Uninvestigated executable identity: " + digest)
    pe = pefile.PE(data=data)
    try:
        if pe.OPTIONAL_HEADER.ImageBase != 0x400000 or pe.FILE_HEADER.Machine != 0x14C:
            raise ValueError("Unexpected image architecture/base")
        decoder = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
        result = {}
        bodies = {}
        for name, va, length in (("constructor", constructor, 0x97),
                                 ("handler", constructor + 0x150, 0x71),
                                 ("factory", constructor + 0x1D0, 0x78)):
            raw = pe.get_data(va - 0x400000, length)
            instructions = list(decoder.disasm(raw, va))
            if len(raw) != length or sum(i.size for i in instructions) != length:
                raise ValueError("Incomplete instruction span: " + name)
            bodies[name] = instructions
            result[name] = {"va": hex(va), "length": length,
                            "sha256": hashlib.sha256(raw).hexdigest(),
                            "instructions": [f"{i.address:08x} {i.mnemonic} {i.op_str}" for i in instructions]}
        ctor = [(i.mnemonic, i.op_str) for i in bodies["constructor"]]
        handler = [(i.mnemonic, i.op_str) for i in bodies["handler"]]
        if ("mov", "edx, 0x3f5") not in ctor or ctor[-1] != ("ret", "8"):
            raise ValueError("Unexpected command type or constructor ABI")
        for required in (("mov", "ecx, dword ptr [ecx + 0xf0]"),
                         ("call", hex(resolve)), ("test", "eax, eax"),
                         ("test", "byte ptr [eax + 0x74], 4"),
                         ("mov", "eax, dword ptr [edx + 0x30]"),
                         ("call", "eax")):
            if required not in handler:
                raise ValueError("Dismissal guard/dispatch mismatch: " + str(required))
        # Preserve exact ordering and both exits around virtual retirement.
        sequence = [i.mnemonic for i in bodies["handler"]]
        if sequence[14:24] != ["call", "test", "je", "test", "jne", "mov", "mov", "mov", "call", "mov"]:
            raise ValueError("Handler control-flow sequence differs; inspect before use")
        exit_target = hex(constructor + 0x19E)
        if bodies["handler"][16].op_str != exit_target or bodies["handler"][18].op_str != exit_target:
            raise ValueError("Null/deleting branches do not skip retirement")
        calls = [int(i.op_str, 16) for i in bodies["factory"]
                 if i.mnemonic == "call" and i.op_str.startswith("0x")]
        if calls[1:] != [constructor, service, submit] or len(calls) != 4:
            raise ValueError("Factory submission chain differs")
        if handler[-1] != ("ret", "8") or bodies["factory"][-1].mnemonic != "ret":
            raise ValueError("Unexpected cleanup convention")
        return {"profile": profile, "image_sha256": digest, "spans": result,
                "scope": "Static command factory and guarded target-retirement dispatch only"}
    finally:
        pe.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("profile", choices=PROFILES)
    parser.add_argument("executable", type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(audit(args.profile, args.executable), indent=2))
    except (ValueError, OSError, pefile.PEFormatError) as error:
        parser.exit(1, str(error) + "\n")
