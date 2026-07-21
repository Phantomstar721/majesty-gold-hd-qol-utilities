from __future__ import annotations

import argparse
import re
import struct
from pathlib import Path


def u16(data: bytes, offset: int) -> int:
    return struct.unpack_from("<H", data, offset)[0]


def u32(data: bytes, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def sections(data: bytes) -> list[dict[str, int | str]]:
    pe = u32(data, 0x3C)
    section_count = u16(data, pe + 6)
    optional_header_size = u16(data, pe + 20)
    image_base = u32(data, pe + 24 + 28)
    section_table = pe + 24 + optional_header_size
    result: list[dict[str, int | str]] = []
    for index in range(section_count):
        off = section_table + index * 40
        name = data[off : off + 8].rstrip(b"\0").decode("ascii", errors="replace")
        result.append(
            {
                "name": name,
                "virtual_size": u32(data, off + 8),
                "rva": u32(data, off + 12),
                "raw_size": u32(data, off + 16),
                "raw": u32(data, off + 20),
                "image_base": image_base,
            }
        )
    return result


def file_to_va(data: bytes, file_offset: int) -> int | None:
    for section in sections(data):
        raw = int(section["raw"])
        raw_size = int(section["raw_size"])
        if raw <= file_offset < raw + raw_size:
            return int(section["image_base"]) + int(section["rva"]) + file_offset - raw
    return None


def va_to_file(data: bytes, va: int) -> int | None:
    image_base = int(sections(data)[0]["image_base"])
    rva = va - image_base
    for section in sections(data):
        section_rva = int(section["rva"])
        size = max(int(section["virtual_size"]), int(section["raw_size"]))
        if section_rva <= rva < section_rva + size:
            return int(section["raw"]) + rva - section_rva
    return None


def find_ascii(data: bytes, needle: bytes) -> list[tuple[int, int | None]]:
    found: list[tuple[int, int | None]] = []
    start = 0
    while True:
        offset = data.find(needle, start)
        if offset < 0:
            return found
        found.append((offset, file_to_va(data, offset)))
        start = offset + 1


def find_push_refs(data: bytes, va: int) -> list[tuple[int, int | None]]:
    needle = b"\x68" + struct.pack("<I", va)
    return [(m.start(), file_to_va(data, m.start())) for m in re.finditer(re.escape(needle), data)]


def find_imm_refs(data: bytes, va: int) -> list[tuple[int, int | None]]:
    needle = struct.pack("<I", va)
    return [(m.start(), file_to_va(data, m.start())) for m in re.finditer(re.escape(needle), data)]


def find_call_refs(data: bytes, target_va: int) -> list[tuple[int, int | None]]:
    refs: list[tuple[int, int | None]] = []
    for offset, byte in enumerate(data[:-4]):
        if byte != 0xE8:
            continue
        source_va = file_to_va(data, offset)
        if source_va is None:
            continue
        rel = struct.unpack_from("<i", data, offset + 1)[0]
        if source_va + 5 + rel == target_va:
            refs.append((offset, source_va))
    return refs


def dump_bytes(data: bytes, file_offset: int, length: int = 96) -> None:
    chunk = data[file_offset : file_offset + length]
    for i in range(0, len(chunk), 16):
        raw = " ".join(f"{b:02X}" for b in chunk[i : i + 16])
        text = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk[i : i + 16])
        print(f"{file_offset+i:08X}  {raw:<47}  {text}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("exe", type=Path)
    parser.add_argument("--string", action="append", default=[])
    parser.add_argument("--dump-va", type=lambda value: int(value, 0))
    parser.add_argument("--dump-file", type=lambda value: int(value, 0))
    parser.add_argument("--disasm-va", type=lambda value: int(value, 0))
    parser.add_argument("--call-refs", type=lambda value: int(value, 0))
    parser.add_argument("--length", type=lambda value: int(value, 0), default=128)
    args = parser.parse_args()

    data = args.exe.read_bytes()
    print("Sections:")
    for section in sections(data):
        print(
            f"  {section['name']:<8} raw=0x{int(section['raw']):X} "
            f"rva=0x{int(section['rva']):X} raw_size=0x{int(section['raw_size']):X}"
        )

    for text in args.string:
        print(f"\nString {text!r}:")
        for file_offset, va in find_ascii(data, text.encode("ascii")):
            va_text = f"0x{va:X}" if va is not None else "n/a"
            print(f"  file=0x{file_offset:X} va={va_text}")
            if va is not None:
                refs = find_push_refs(data, va)
                for ref_file, ref_va in refs[:20]:
                    ref_va_text = f"0x{ref_va:X}" if ref_va is not None else "n/a"
                    print(f"    push ref file=0x{ref_file:X} va={ref_va_text}")
                imm_refs = find_imm_refs(data, va)
                for ref_file, ref_va in imm_refs[:20]:
                    ref_va_text = f"0x{ref_va:X}" if ref_va is not None else "n/a"
                    print(f"    imm ref  file=0x{ref_file:X} va={ref_va_text}")

    if args.dump_va is not None:
        file_offset = va_to_file(data, args.dump_va)
        if file_offset is None:
            raise SystemExit(f"VA 0x{args.dump_va:X} is not in a file-backed section")
        dump_bytes(data, file_offset, args.length)

    if args.dump_file is not None:
        dump_bytes(data, args.dump_file, args.length)

    if args.disasm_va is not None:
        from capstone import Cs, CS_ARCH_X86, CS_MODE_32

        file_offset = va_to_file(data, args.disasm_va)
        if file_offset is None:
            raise SystemExit(f"VA 0x{args.disasm_va:X} is not in a file-backed section")
        md = Cs(CS_ARCH_X86, CS_MODE_32)
        for insn in md.disasm(data[file_offset : file_offset + args.length], args.disasm_va):
            print(f"0x{insn.address:08X}: {insn.mnemonic:<8} {insn.op_str}")

    if args.call_refs is not None:
        print(f"\nCall refs to 0x{args.call_refs:X}:")
        for file_offset, va in find_call_refs(data, args.call_refs):
            print(f"  file=0x{file_offset:X} va=0x{va:X}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
