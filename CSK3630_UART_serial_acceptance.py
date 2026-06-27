#!/usr/bin/env python3
"""
PC-side hardware acceptance test for the CSK3630_UART FPGA project.

Usage:
  python CSK3630_UART_serial_acceptance.py --port COM3

The serial assistant equivalent settings are:
  115200 baud, 8 data bits, no parity, 1 stop bit, HEX send/receive.
"""

import argparse
import sys
import time


def require_pyserial():
    try:
        import serial
        from serial.tools import list_ports
    except ImportError:
        print("ERROR: pyserial is not installed.")
        print("Install it with: python -m pip install pyserial")
        sys.exit(2)
    return serial, list_ports


def hex_to_bytes(text):
    compact = "".join(text.split())
    if len(compact) % 2 != 0:
        raise ValueError(f"Odd hex digit count: {text}")
    return bytes(int(compact[i : i + 2], 16) for i in range(0, len(compact), 2))


def bytes_to_hex(data):
    return " ".join(f"{value:02X}" for value in data)


def read_exact_or_timeout(port, size, deadline):
    result = bytearray()
    while len(result) < size and time.monotonic() < deadline:
        chunk = port.read(size - len(result))
        if chunk:
            result.extend(chunk)
    return bytes(result)


def run_case(port, name, send_hex, expect_hex, timeout_s, settle_s):
    send_data = hex_to_bytes(send_hex)
    expect_data = hex_to_bytes(expect_hex)

    port.reset_input_buffer()
    port.reset_output_buffer()
    time.sleep(settle_s)

    port.write(send_data)
    port.flush()

    got = read_exact_or_timeout(port, len(expect_data), time.monotonic() + timeout_s)
    ok = got == expect_data
    status = "PASS" if ok else "FAIL"
    print(f"[{status}] {name}")
    print(f"  send:   {bytes_to_hex(send_data)}")
    print(f"  expect: {bytes_to_hex(expect_data)}")
    print(f"  got:    {bytes_to_hex(got)}")
    return ok


def list_available_ports(list_ports):
    ports = list(list_ports.comports())
    if not ports:
        return "No serial ports found."
    lines = ["Available serial ports:"]
    for item in ports:
        lines.append(f"  {item.device}: {item.description}")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Run CSK3630_UART hardware serial acceptance tests.")
    parser.add_argument("--port", required=False, help="Serial port, for example COM3.")
    parser.add_argument("--baud", type=int, default=115200, help="Baud rate. Default: 115200.")
    parser.add_argument("--timeout", type=float, default=0.5, help="Read timeout per test in seconds.")
    parser.add_argument("--settle", type=float, default=0.05, help="Delay before each send in seconds.")
    parser.add_argument("--list", action="store_true", help="List available serial ports and exit.")
    args = parser.parse_args()

    serial, list_ports = require_pyserial()

    if args.list:
        print(list_available_ports(list_ports))
        return 0

    if not args.port:
        print("ERROR: --port is required unless --list is used.")
        print(list_available_ports(list_ports))
        return 2

    cases = [
        ("single byte echo AA", "AA", "AA"),
        ("single byte echo 55", "55", "55"),
        ("single byte echo 0F", "0F", "0F"),
        ("simple write addr03=5A", "55 A1 03 5A F9", "06"),
        ("simple read addr03", "55 A2 03 00 A1", "5A"),
        ("simple erase addr03", "55 A3 03 00 A0", "06"),
        ("simple read addr03 after erase", "55 A2 03 00 A1", "00"),
        ("bad checksum returns NACK", "55 A1 03 5A 00", "15"),
    ]

    print("== CSK3630_UART serial acceptance ==")
    print(f"Port: {args.port}")
    print(f"Baud: {args.baud}, 8N1")

    with serial.Serial(
        port=args.port,
        baudrate=args.baud,
        bytesize=serial.EIGHTBITS,
        parity=serial.PARITY_NONE,
        stopbits=serial.STOPBITS_ONE,
        timeout=0.02,
        write_timeout=1.0,
    ) as port:
        all_ok = True
        for name, send_hex, expect_hex in cases:
            all_ok = run_case(port, name, send_hex, expect_hex, args.timeout, args.settle) and all_ok

    if all_ok:
        print("== ALL TESTS PASSED ==")
        return 0

    print("== SOME TESTS FAILED ==")
    print("Check that the latest output_files/CSK3630_UART.sof is programmed and the COM port is CH340.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
