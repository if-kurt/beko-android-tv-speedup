"""A strict fake adbd for testing AdbClient: checks framing, checksums, signatures and the key format.

Connection 1: unknown key, client must give up after the second token.
Connection 2: unknown key, client sends its public key, we "approve" it, then serve `shell:echo ok`.
Connection 3: known key, signature must verify, then `shell:reboot -p` drops the connection.
"""
import base64
import os
import socket
import struct
import sys

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding, rsa, utils
from cryptography.exceptions import InvalidSignature

A_CNXN, A_AUTH, A_OPEN, A_OKAY, A_CLSE, A_WRTE = 0x4e584e43, 0x48545541, 0x4e45504f, 0x59414b4f, 0x45534c43, 0x45545257
NAMES = {A_CNXN: "CNXN", A_AUTH: "AUTH", A_OPEN: "OPEN", A_OKAY: "OKAY", A_CLSE: "CLSE", A_WRTE: "WRTE"}
problems = []
known_keys = []


def fail(msg):
    problems.append(msg)
    print("MOCK FAIL", msg, flush=True)


def recv_exact(conn, n):
    buf = b""
    while len(buf) < n:
        chunk = conn.recv(n - len(buf))
        if not chunk:
            raise EOFError("client closed")
        buf += chunk
    return buf


def read_msg(conn):
    cmd, a0, a1, length, check, magic = struct.unpack("<6I", recv_exact(conn, 24))
    data = recv_exact(conn, length) if length else b""
    if magic != (cmd ^ 0xFFFFFFFF):
        fail("bad magic for %s" % NAMES.get(cmd, hex(cmd)))
    if check != (sum(data) & 0xFFFFFFFF):
        fail("bad checksum for %s" % NAMES.get(cmd, hex(cmd)))
    print("  <- %s %d %d len=%d" % (NAMES.get(cmd, hex(cmd)), a0, a1, length), flush=True)
    return cmd, a0, a1, data


def send_msg(conn, cmd, a0, a1, data=b""):
    conn.sendall(struct.pack("<6I", cmd, a0, a1, len(data), sum(data) & 0xFFFFFFFF, cmd ^ 0xFFFFFFFF) + data)
    print("  -> %s %d %d len=%d" % (NAMES[cmd], a0, a1, len(data)), flush=True)


def parse_android_pubkey(payload):
    if not payload.endswith(b"\0"):
        fail("public key payload not NUL terminated")
    text = payload.rstrip(b"\0").decode("ascii")
    b64, _, name = text.partition(" ")
    blob = base64.b64decode(b64, validate=True)
    if len(blob) != 524:
        fail("key blob is %d bytes, expected 524" % len(blob))
    words, n0inv = struct.unpack_from("<II", blob, 0)
    n = int.from_bytes(blob[8:8 + 256], "little")
    rr = int.from_bytes(blob[264:264 + 256], "little")
    (e,) = struct.unpack_from("<I", blob, 520)
    if words != 64:
        fail("len words %d" % words)
    if (n0inv * (n % (1 << 32))) % (1 << 32) != (1 << 32) - 1:
        fail("n0inv is not -1/n[0] mod 2^32")
    if rr != pow(2, 4096, n):
        fail("rr is not R^2 mod n")
    if e != 65537:
        fail("exponent %d" % e)
    print("  key ok, name=%r" % name, flush=True)
    return rsa.RSAPublicNumbers(e, n).public_key()


def verify(sig, token):
    for key in known_keys:
        try:
            key.verify(sig, token, padding.PKCS1v15(), utils.Prehashed(hashes.SHA1()))
            return True
        except InvalidSignature:
            pass
    return False


def handshake(conn, expect):
    cmd, a0, a1, data = read_msg(conn)
    if cmd != A_CNXN or data != b"host::\0":
        fail("first message must be CNXN host::")
    token = os.urandom(20)
    send_msg(conn, A_AUTH, 1, 0, token)
    while True:
        cmd, a0, a1, data = read_msg(conn)
        if cmd != A_AUTH:
            fail("expected AUTH")
            return False
        if a0 == 2:
            if verify(data, token):
                if expect == "unknown":
                    fail("signature verified with a key that should be unknown")
                send_msg(conn, A_CNXN, 0x01000000, 4096, b"device::ro.product.name=mock;ro.product.model=MockTV;\0")
                return True
            if expect == "known":
                fail("signature of a known key did not verify")
            token = os.urandom(20)
            send_msg(conn, A_AUTH, 1, 0, token)
        elif a0 == 3:
            known_keys.append(parse_android_pubkey(data))
            send_msg(conn, A_CNXN, 0x01000000, 4096, b"device::ro.product.name=mock;ro.product.model=MockTV;\0")
            return True


def serve_shell(conn):
    cmd, local_id, zero, data = read_msg(conn)
    if cmd != A_OPEN:
        fail("expected OPEN")
        return
    service = data.rstrip(b"\0").decode()
    send_msg(conn, A_OKAY, 7, local_id)
    if service == "shell:echo ok":
        send_msg(conn, A_WRTE, 7, local_id, b"ok\n")
        cmd, a0, a1, _ = read_msg(conn)
        if cmd != A_OKAY or a0 != local_id or a1 != 7:
            fail("client did not acknowledge WRTE correctly")
        send_msg(conn, A_CLSE, 7, local_id)
    elif service == "shell:reboot -p":
        print("  simulating power-off: dropping the connection", flush=True)
    else:
        fail("unexpected service %r" % service)


def main():
    port = int(sys.argv[1])
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", port))
    srv.listen(1)
    print("MOCK READY", flush=True)
    for step, expect in enumerate(["unknown", "approve", "known"], 1):
        conn, _ = srv.accept()
        conn.settimeout(10)
        print("connection %d (%s)" % (step, expect), flush=True)
        try:
            ok = handshake(conn, expect)
            if expect == "unknown":
                if ok:
                    fail("client should not have been let in")
                # the client should close by itself now
                try:
                    read_msg(conn)
                    fail("client kept talking after the second token")
                except EOFError:
                    print("  client gave up, as expected", flush=True)
            elif ok:
                serve_shell(conn)
                if expect == "approve":
                    try:
                        read_msg(conn)
                    except EOFError:
                        pass
        except EOFError as e:
            if expect != "unknown":
                fail("connection %d: %s" % (step, e))
            else:
                print("  client gave up, as expected", flush=True)
        finally:
            conn.close()
    print("MOCK DONE problems=%d" % len(problems), flush=True)
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
