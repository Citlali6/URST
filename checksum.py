#!/usr/bin/env python3
"""
CSK3630 UART Protocol Checksum Calculator - Interactive Mode

直接运行 (F5 / Ctrl+F5)，输入十六进制字节，自动算校验码。

输入格式:
    A1 05 67              -> 简单协议 (cmd addr data)
    55 A1 05 67           -> 简单协议 (带帧头)
    01 04 04 11 22 33 44  -> 扩展协议 (cmd addr len data...)
    55 AA 04 00 00        -> 扩展协议 PING

输入 q 或 quit 退出。
"""

import sys

def xor_all(*values):
    result = 0
    for v in values:
        result ^= v
    return result

def parse_hex(token):
    token = token.strip().lower().replace("0x", "")
    if not token or not all(c in "0123456789abcdef" for c in token):
        return None
    if len(token) > 2:
        return None
    return int(token, 16)

def fmt(v):
    return f"{v:02X}"

def simple_str(cmd): return "SIMPLE" if cmd & 0x80 else "EXT"
CMD_NAMES = {
    0x01: "WRITE", 0x02: "READ", 0x03: "ERASE_ALL", 0x04: "PING",
    0xA1: "SIMPLE_WRITE", 0xA2: "SIMPLE_READ", 0xA3: "SIMPLE_ERASE",
    0x80: "ACK", 0x81: "DATA", 0xE0: "BAD_CRC", 0xE1: "BAD_CMD",
    0xE2: "BAD_ADDR", 0xE3: "BAD_LEN",
}

def cmd_name(cmd):
    return CMD_NAMES.get(cmd, "?")

def main():
    if len(sys.argv) > 1:
        # Command-line mode (for terminal use)
        args = [parse_hex(a) for a in sys.argv[1:]]
        if None in args:
            print("ERROR: invalid hex value")
            sys.exit(1)
        calculate(args)
    else:
        # Interactive mode (for VS Code Run)
        print("=" * 55)
        print("  CSK3630 UART Checksum Calculator")
        print("=" * 55)
        print("  Enter hex bytes, auto-detects protocol.")
        print("  Type 'q' or 'quit' to exit.\n")

        while True:
            try:
                line = input("  > ").strip()
            except (EOFError, KeyboardInterrupt):
                print("\n  Bye!")
                break

            if not line:
                continue
            if line.lower() in ("q", "quit", "exit"):
                print("  Bye!")
                break

            tokens = line.split()
            args = [parse_hex(t) for t in tokens]
            if None in args:
                print("  ERROR: invalid hex value, use format like A1 05 67\n")
                continue

            calculate(args)
            print()  # blank line for readability

def calculate(args):
    simple = False
    offset = 0

    if args[0] == 0x55 and len(args) >= 4:
        if args[1] == 0xAA:
            offset = 2
        elif len(args) == 4:
            offset = 1
            simple = True
        else:
            print("  ERROR: unexpected bytes after 55")
            return
    elif len(args) == 3:
        simple = True
    elif args[0] & 0x80 and args[0] not in (0x55, 0xAA):
        simple = True

    if simple:
        if len(args) - offset < 3:
            print("  ERROR: simple protocol needs cmd addr data (3 bytes after header)")
            return
        cmd, addr, data = args[offset], args[offset + 1], args[offset + 2]
        cs = xor_all(cmd, addr, data)

        print(f"  Protocol:  Simple ({cmd_name(cmd)})")
        print(f"  CMD  = {fmt(cmd)}    ADDR = {fmt(addr)}    DATA = {fmt(data)}")
        print(f"  CS   = {fmt(cmd)} XOR {fmt(addr)} XOR {fmt(data)} = {fmt(cs)}")

        if cmd in (0xA1, 0xA3):
            print(f"  Alt  = {fmt(cs ^ 1)}  (WRITE/ERASE tolerates +-1)")

        print(f"  >>> 55 {fmt(cmd)} {fmt(addr)} {fmt(data)} {fmt(cs)}\n")

    else:
        if len(args) - offset < 3:
            print("  ERROR: extended protocol needs at least cmd addr len")
            return
        cmd, addr, length = args[offset], args[offset + 1], args[offset + 2]
        data = args[offset + 3:]

        if length != len(data):
            print(f"  ERROR: LEN={fmt(length)} but {len(data)} data bytes given")
            return

        cs = xor_all(cmd, addr, length, *data)

        print(f"  Protocol:  Extended ({cmd_name(cmd)})")
        print(f"  CMD  = {fmt(cmd)}    ADDR = {fmt(addr)}    LEN  = {fmt(length)}")
        if data:
            print(f"  DATA = {' '.join(fmt(d) for d in data)}")

        parts = [fmt(cmd), fmt(addr), fmt(length)] + [fmt(d) for d in data]
        expr = " XOR ".join(parts)
        print(f"  CRC  = {expr} = {fmt(cs)}")

        data_str = " ".join(fmt(d) for d in data)
        space = " " if data else ""
        print(f"  >>> 55 AA {fmt(cmd)} {fmt(addr)} {fmt(length)} {data_str}{space}{fmt(cs)}\n")

if __name__ == "__main__":
    main()
