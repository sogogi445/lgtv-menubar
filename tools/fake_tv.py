"""A fake webOS TV on 127.0.0.1:3001, used to test the app without touching a real TV.

Logs every message it receives. Needs the `websockets` package and `openssl`.
Usage: python3 tools/fake_tv.py [seconds_to_run]
"""
import asyncio, json, os, ssl, subprocess, sys
from websockets.asyncio.server import serve

HERE = os.path.dirname(os.path.abspath(__file__))
CERT_DIR = os.path.join(HERE, ".certs")
CRT, KEY = os.path.join(CERT_DIR, "fake.crt"), os.path.join(CERT_DIR, "fake.key")


def ensure_cert():
    if os.path.exists(CRT) and os.path.exists(KEY):
        return
    os.makedirs(CERT_DIR, exist_ok=True)
    subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", KEY, "-out", CRT,
                    "-days", "2", "-subj", "/CN=fake-tv"], check=True, capture_output=True)


async def handler(conn):
    if conn.request.path == "/pointer":
        async for m in conn:
            print("POINTER <-", repr(m), flush=True)
        return
    async for raw in conn:
        j = json.loads(raw)
        t, i = j.get("type"), j.get("id")
        if t == "register":
            p = j["payload"]
            print(f"REGISTER client-key-sent={'client-key' in p} manifest={'manifest' in p}", flush=True)
            await conn.send(json.dumps({"type": "registered", "id": i, "payload": {"client-key": "FAKEKEY"}}))
        elif t == "request":
            uri, p = j["uri"], j.get("payload")
            print(f"REQUEST {uri} {p}", flush=True)
            if uri.endswith("getVolume"):
                body = {"returnValue": True, "volumeStatus": {"volume": 12, "muteStatus": False}}
            elif uri.endswith("getChannelList"):
                body = {"returnValue": True, "channelList": [
                    {"channelNumber": "2-1", "channelName": "Test Channel 1"}, {"channelNumber": "5-1", "channelName": "Test Channel 2"}]}
            elif uri.endswith("getPointerInputSocket"):
                body = {"returnValue": True, "socketPath": "wss://127.0.0.1:3001/pointer"}
            else:
                body = {"returnValue": True}
            await conn.send(json.dumps({"type": "response", "id": i, "payload": body}))


async def main(seconds):
    ensure_cert()
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(CRT, KEY)
    async with serve(handler, "127.0.0.1", 3001, ssl=ctx):
        print("fake TV listening on 127.0.0.1:3001", flush=True)
        await asyncio.sleep(seconds)


asyncio.run(main(float(sys.argv[1]) if len(sys.argv) > 1 else 40))
