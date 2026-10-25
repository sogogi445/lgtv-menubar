"""A fake SSDP responder on 127.0.0.1:1900, used to test TV discovery without a real TV.

Usage: python3 tools/fake_ssdp.py [seconds_to_run]
"""
import socket, sys, time

REPLY = (b"HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nST: urn:lge-com:service:webos-second-screen:1\r\n"
         b"USN: uuid:00000000-0000-0000-0000-000000000000::urn:lge-com:service:webos-second-screen:1\r\n"
         b"SERVER: WebOS/4.1.0 UPnP/1.0\r\n\r\n")

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 1900))
s.settimeout(0.5)
print("fake SSDP listening on 127.0.0.1:1900", flush=True)
end = time.time() + (float(sys.argv[1]) if len(sys.argv) > 1 else 15)
while time.time() < end:
    try:
        data, addr = s.recvfrom(2048)
    except socket.timeout:
        continue
    if b"M-SEARCH" in data:
        print("M-SEARCH from", addr, flush=True)
        s.sendto(REPLY, addr)
