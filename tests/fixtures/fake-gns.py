"""A stand-in that answers just enough of SteamNetworkingSockets to test tools/healthcheck.sh. Not a server.

    python3 fake-gns.py <mode> <port> <bind>

The rules are the real server's, from ValveSoftware/GameNetworkingSockets
(steamnetworkingsockets_udp.cpp): a ChallengeRequest is message id 32, padded
to at least 512 bytes, a two-byte length and then a protobuf body with a
non-zero connection_id (field 1, fixed32). Anything else is dropped. The reply
is message id 33 and a body that starts with field 1, the connection id.

mode   answers   a ChallengeReply to every valid ChallengeRequest
       wrongid   a ChallengeReply carrying another connection id
       silent    binds the port and never answers
       noloop    answers, except a request from 127.0.0.1 (or ::1)
bind   an IPv4 address, "iface" for the container's own address, "0.0.0.0",
       or "::" for every address of both families, which is what VEIN binds

Every request it saw is logged as "seen <bytes> <valid>", so a test can tell
a check that never reached it from one it ignored.
"""
import socket
import struct
import sys

mode, port, bind = sys.argv[1], int(sys.argv[2]), sys.argv[3]
if bind == "iface":
    bind = socket.gethostbyname(socket.gethostname())
if ":" in bind:
    s = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
    s.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
else:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind((bind, port))
print("bound", bind, port, flush=True)


def connection_id(pkt):
    """The request's connection id, or None when the server would drop it."""
    if len(pkt) < 512 or pkt[0] != 32:
        return None
    n = struct.unpack("<H", pkt[1:3])[0]
    body = pkt[3:3 + n]
    if n <= 0 or len(body) < n or body[:1] != b"\x0d" or len(body) < 5:
        return None
    cid = body[1:5]
    return None if cid == b"\x00\x00\x00\x00" else cid


while True:
    data, peer = s.recvfrom(4096)
    cid = connection_id(data)
    print("seen", len(data), cid is not None, flush=True)
    if cid is None or mode == "silent":
        continue
    if mode == "noloop" and peer[0] in ("127.0.0.1", "::1", "::ffff:127.0.0.1"):
        continue
    if mode == "wrongid":
        cid = bytes(b ^ 0xFF for b in cid)
    reply = b"\x21" + b"\x0d" + cid + b"\x11" + b"\x01" * 8 + b"\x19" + b"\x00" * 8 + b"\x20\x0b"
    s.sendto(reply, peer)
