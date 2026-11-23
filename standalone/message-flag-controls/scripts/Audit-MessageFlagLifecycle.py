"""Read-only, identity-guarded evidence dump; not a runtime patch or installer.

Requires the workspace's pefile and capstone packages. JSON is written to stdout.
Only the locally investigated, patched Steam Public image is accepted. These
addresses must not be applied to beta2/GOG or treated as a portable profile.
"""

import argparse
import hashlib
import json
import struct
from pathlib import Path

import capstone
import pefile


IMAGE_SHA256 = "255957fb09a4f8d5db6dde6d4127943dea965fa71c1da5db57951302b92e40b4"
BASE = 0x400000
# Explicit bounded spans, not inferred function sizes. Some include padding.
SPANS = (
    ("creation_entry_legacy_patch", 0x449690, 6),
    ("stock_dismiss_ui_branch", 0x4645A0, 0x8F),
    ("dismiss_command_constructor", 0x4C45C0, 0x97),
    ("dismiss_command_handler", 0x4C4710, 0x71),
    ("dismiss_command_submit", 0x4C4790, 0x78),
    ("command_dispatch", 0x595DC0, 0xAB),
    ("msgf_virtual_30", 0x4474F0, 0x2A1),
    ("relation_callback", 0x447380, 0x21),
    ("selected_object_check", 0x42ACB0, 0x11),
    ("base_destroy_lifecycle", 0x5BA530, 0xA8),
    ("owner_remove_and_delete", 0x5CFBC0, 0x1D),
    ("kind_collection_lookup", 0x5A4080, 0x6A),
    ("world_catalog_lookup", 0x5A15D0, 0x1E),
    ("all_units_enumerate", 0x5CE900, 0x89),
    ("catalog_unregister", 0x5CFB30, 0x83),
    ("agent_cleanup", 0x5BA720, 0x3F),
    ("relation_cleanup", 0x5A8DE0, 0xB5),
    ("runtime_unit_notification", 0x5C6C60, 0x17),
    ("order_channel_retire", 0x5C9D40, 0x2D),
    ("order_channel_destroy", 0x5C9E00, 0x2B),
    ("notification_fanout", 0x425520, 0xC6),
    ("tracking_target_change", 0x457690, 0xF5),
    ("tracking_notification_handler", 0x457790, 0x5A0),
    ("command_service_getter", 0x4D6FC0, 0x6F),
    ("command_queue_submit", 0x595F90, 0x75),
    ("queue_append_wrapper", 0x5F4EE0, 0x5F),
    ("queue_append_storage", 0x5F47D0, 0x74),
    ("accepted_save_attach_call", 0x4252A9, 0x26),
    ("world_attach", 0x424CC0, 0xF7),
    ("menu_save_attach_call", 0x49496E, 0x23),
    ("runtime_world_start", 0x4F6240, 0x23),
    ("command_service_world_store", 0x4D6070, 0xD),
    ("queue_handle_initialization", 0x4C6230, 0x51),
    ("service_queue_processing", 0x595BF0, 0xD2),
    ("service_queue_processing_alternate", 0x595CD0, 0xEC),
    ("queue_replacement_prefix", 0x5975D0, 0x129),
    ("queue_replacement_complete", 0x5975D0, 0x232),
    ("queue_replacement_override", 0x4C5E60, 0x39),
    ("step_reset_before_execution", 0x426788, 0x75),
    ("step_late_queue_submission", 0x4269C4, 0xC),
    ("packet_submit", 0x5978C0, 0x12A),
    ("received_command_execution", 0x598130, 0x236),
    ("game_command_dispatch", 0x4C9300, 0x326),
)
VIRTUAL_OFFSETS = (0, 0x14, 0x30, 0x98, 0xB8, 0x164, 0x170, 0x1DC, 0x1E0)


def audit(path):
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != IMAGE_SHA256:
        raise ValueError("Uninvestigated executable identity: " + digest)
    pe = pefile.PE(data=data)
    try:
        if pe.OPTIONAL_HEADER.ImageBase != BASE or pe.FILE_HEADER.Machine != 0x14C:
            raise ValueError("Unexpected PE base or architecture")
        decoder = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
        records = []
        for name, va, size in SPANS:
            raw = pe.get_data(va - BASE, size)
            instructions = list(decoder.disasm(raw, va))
            if len(raw) != size or sum(i.size for i in instructions) != size:
                raise ValueError("Incomplete instruction coverage: " + name)
            records.append({
                "name": name, "va": hex(va), "length": size,
                "bytes": raw.hex(), "sha256": hashlib.sha256(raw).hexdigest(),
                "instructions": [
                    {"va": hex(i.address), "text": i.mnemonic + " " + i.op_str}
                    for i in instructions
                ],
            })
        return {
            "image_sha256": digest,
            "scope": "Patched Steam Public 1.5.2.24 static evidence only",
            "limitations": "Not live validation; no beta2/GOG coverage; queue drain timing and safe load-time mutation unresolved",
            "attachment_mode_targets": [hex(value) for value in struct.unpack(
                "<4I", pe.get_data(0x424DB8 - BASE, 16))],
            "concrete_slots": {
                "all_units_enumerate": hex(struct.unpack("<I", pe.get_data(0x748D4C + 0x30 - BASE, 4))[0]),
                "runtime_world_start": hex(struct.unpack("<I", pe.get_data(0x736EB0 + 4 - BASE, 4))[0]),
                "command_queue_submit": hex(struct.unpack("<I", pe.get_data(0x73FA14 + 0x48 - BASE, 4))[0]),
                "step_queue_reset": hex(struct.unpack("<I", pe.get_data(0x73FA14 + 0x10 - BASE, 4))[0]),
                "packet_submit": hex(struct.unpack("<I", pe.get_data(0x73FA14 + 0x68 - BASE, 4))[0]),
                "game_command_dispatch": hex(struct.unpack("<I", pe.get_data(0x73FA14 + 0x64 - BASE, 4))[0]),
                "dismiss_case_3f5": hex(struct.unpack("<I", pe.get_data(0x4C9628 + 12 * 4 - BASE, 4))[0]),
            },
            "msgf_vtable": hex(0x73AB7C),
            "virtuals": {
                hex(offset): hex(struct.unpack("<I", pe.get_data(0x73AB7C + offset - BASE, 4))[0])
                for offset in VIRTUAL_OFFSETS
            },
            "spans": records,
        }
    finally:
        pe.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    args = parser.parse_args()
    try:
        result = audit(args.executable)
    except (OSError, ValueError, pefile.PEFormatError) as error:
        parser.exit(1, str(error) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
