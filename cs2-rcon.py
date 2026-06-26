#!/usr/bin/env python3
"""
External Source RCON client for the CS2 server (LXC 117, 192.168.68.60:27015).

Why this exists: CS2's built-in in-game `rcon` command fails to connect to
direct-IP servers (Socket connection failed / EINPROGRESS), especially when the
game session rides Steam Datagram Relay. The server-side RCON listener is fine -
this talks to it directly over TCP.

Reads rcon_password from the gitignored ./cs2-pass file (no secrets live here).

Usage:
    ./cs2-rcon.py                 # interactive prompt
    ./cs2-rcon.py status          # run one command and exit
    ./cs2-rcon.py "bot_kick"
"""
import socket
import struct
import sys
import os

HOST = "192.168.68.60"
PORT = 27015
PASS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cs2-pass")

SERVERDATA_AUTH = 3
SERVERDATA_EXECCOMMAND = 2


def load_password():
    with open(PASS_FILE) as f:
        for line in f:
            line = line.strip()
            if line.startswith("rcon_password="):
                return line.split("=", 1)[1].strip().strip('"')
    raise SystemExit("rcon_password not found in " + PASS_FILE)


def encode(req_id, req_type, body):
    payload = struct.pack("<ii", req_id, req_type) + body.encode() + b"\x00\x00"
    return struct.pack("<i", len(payload)) + payload


def read_packet(sock):
    raw_len = recv_exact(sock, 4)
    size = struct.unpack("<i", raw_len)[0]
    data = recv_exact(sock, size)
    req_id, req_type = struct.unpack("<ii", data[:8])
    body = data[8:-2].decode(errors="replace")
    return req_id, req_type, body


def recv_exact(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("connection closed by server")
        buf += chunk
    return buf


def main():
    password = load_password()
    sock = socket.create_connection((HOST, PORT), timeout=5)
    sock.sendall(encode(1, SERVERDATA_AUTH, password))
    req_id, _, _ = read_packet(sock)
    if req_id == -1:
        raise SystemExit("AUTH FAILED - bad rcon_password")

    def run(cmd):
        sock.sendall(encode(2, SERVERDATA_EXECCOMMAND, cmd))
        _, _, body = read_packet(sock)
        print(body, end="" if body.endswith("\n") else "\n")

    args = " ".join(sys.argv[1:]).strip()
    if args:
        run(args)
        return

    print("Connected to CS2 RCON %s:%d. Type commands, 'quit' to exit." % (HOST, PORT))
    try:
        while True:
            cmd = input("rcon> ").strip()
            if cmd in ("quit", "exit"):
                break
            if cmd:
                run(cmd)
    except (EOFError, KeyboardInterrupt):
        print()


if __name__ == "__main__":
    main()
