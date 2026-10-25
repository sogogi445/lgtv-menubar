# LG TV Menu Bar

**English** | [한국어](README.ko.md)

A tiny macOS **menu bar app** to control an LG webOS TV on your local network.

> Unofficial. Not affiliated with LG Electronics; "LG" and "webOS" are trademarks of their respective owners.

## Features

- Power on (Wake-on-LAN) / power off
- Volume +/−, mute
- Channel list (read from the TV), next / previous channel
- Input switching (HDMI 1–3, AV, Component)
- Remote keys: Home, Back, OK, arrow keys, Exit
- Finds your TV automatically (SSDP) - no IP or MAC to type in. If the TV's IP changes, it is found again by its MAC address
- Menu language: **English (default)** or **한국어** (menu bar icon → *Language*)
- Optional "Launch at Login", no Dock icon
- No telemetry, no external servers: it only talks to the TV on your network

## Requirements

- macOS 13 or later (Apple silicon and Intel)
- An LG webOS TV (tested on webOS 4.5; webOS 3–6 use the same protocol)
- The Mac and the TV on the same network
- *Power On* uses Wake-on-LAN. It worked out of the box on the TV it was tested with (webOS 4.5, no setting changed). If your TV does not wake up, try enabling **Wake on LAN / LG Connect Apps / Quick Start+** in its settings

## Install

**Option 1 - download a release:** get `LG-TV.dmg` (or `LG-TV.zip`) from [Releases](../../releases) and move `LG TV.app` to your Applications folder.
The app is signed ad hoc and **not notarized**, so macOS warns on first launch: **right-click the app → Open**,
or System Settings → Privacy & Security → *Open Anyway*, or

```sh
xattr -dr com.apple.quarantine "/Applications/LG TV.app"
```

**Option 2 - build it yourself:** you only need the Xcode command line tools (`xcode-select --install`).

```sh
git clone https://github.com/sogogi445/lgtv-menubar.git && cd lgtv-menubar
./build.sh                       # build/LG TV.app (universal: Apple silicon + Intel)
cp -R "build/LG TV.app" /Applications/
```

## First run

1. Open the app. A TV icon appears in the menu bar. **With the TV turned on**, click the icon.
2. The app looks for the TV on its own. If macOS asks for **Local Network** access, allow it.
3. When the TV shows an **"allow connection" prompt**, accept it with the TV remote (once per Mac).
4. From now on you can use *Power On* even when the TV is off. The TV's MAC address is saved automatically on the first connection.

Bought a new TV? Choose **Find TV Again** in the menu.

## Troubleshooting

| Symptom | Check |
|---|---|
| "TV not found" | The TV is on and on the same Wi-Fi/router; Local Network access is allowed (System Settings → Privacy & Security → Local Network) |
| *Power On* does nothing | The TV is in standby, not unplugged. If the MAC is not known yet, open the menu once while the TV is on. Some TVs also need **Wake on LAN / LG Connect Apps / Quick Start+** turned on in their settings |
| The TV keeps asking for permission | Pairing data was lost. Reset the app's settings and pair again: `defaults delete dev.lgtvmenubar.app` |
| Channel list is empty | It is loaded from the TV while it is on; open the menu with the TV turned on |

Manual settings (only if automatic discovery does not work):

```sh
defaults write dev.lgtvmenubar.app ip  "TV_IP_ADDRESS"
defaults write dev.lgtvmenubar.app mac "TV_MAC_ADDRESS"
```

## How it works

- Connects to `wss://<tv-ip>:3001` using the webOS **SSAP** websocket protocol, registers (pairs) and sends commands such as
  `ssap://audio/volumeUp` or `ssap://tv/openChannel`. The TV uses a self-signed certificate, so certificate validation is skipped for this connection only.
- Remote keys (Home/Back/arrows) are sent over the pointer-input socket the TV hands out.
- *Power On* sends a **Wake-on-LAN** magic packet (UDP 9/7). A TV that is off closes its websocket, so it cannot be turned on through the API.
- Discovery is an SSDP search for `urn:lge-com:service:webos-second-screen:1`; the MAC address is read from the ARP table.

## Security & privacy

- The pairing key is stored only in this Mac's app settings (UserDefaults, `dev.lgtvmenubar.app`) - not in the repository or the app bundle.
  Anyone who has the key can control the TV from the same network, so don't share it.
- No analytics and no connections to anything except your TV.

## Language

English is the default. To add a language, copy `res/en.lproj` to `res/<code>.lproj`, translate the right-hand side of each line in
`Localizable.strings` (the English text on the left is the lookup key) and add the language in `Info.plist` (`CFBundleLocalizations`) and in the *Language* menu (`src/main.swift`).

## Development

```sh
./tools/run_tests.sh   # tests against fake local servers (127.0.0.1); nothing is sent to a real TV
                       # needs python3 with `pip install websockets` (set PYTHON=... to choose the interpreter)
```

- `src/main.swift` - the whole app (AppKit, no third-party dependencies)
- `res/` - registration manifest and translations
- `tools/` - fake TV / SSDP servers and the test script

## License

MIT - see [LICENSE](LICENSE). Third-party notices: [NOTICE](NOTICE).
