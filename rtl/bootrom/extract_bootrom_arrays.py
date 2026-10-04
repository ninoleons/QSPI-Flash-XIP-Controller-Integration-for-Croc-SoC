import re

blocks = {
    "StartRom":       (0x02000000, 0x02000100),
    "EocRom":         (0x02000100, 0x02000200),
    "TrapHandlerRom": (0x02000200, 0x02000300),
    "TrapExitRom":    (0x02000300, 0x02000400),
}

words = {name: [] for name in blocks}

with open("bootrom.dump") as f:
    for line in f:
        m = re.match(r"\s*([0-9a-fA-F]+):\s+([0-9a-fA-F]{8})\s", line)
        if not m:
            continue

        addr = int(m.group(1), 16)
        word = m.group(2).upper()

        for name, (lo, hi) in blocks.items():
            if lo <= addr < hi:
                words[name].append((addr, word))
                break

for name, arr in words.items():
    print(f"// {name}")
    print(f"localparam int unsigned {name}Words = {len(arr)};")
    print(f"localparam logic [31:0] {name} [{name}Words] = '{{")
    for i, (addr, word) in enumerate(arr):
        comma = "," if i != len(arr) - 1 else ""
        print(f"    32'h{word}{comma} // 0x{addr:08X}")
    print("};")
    print()
