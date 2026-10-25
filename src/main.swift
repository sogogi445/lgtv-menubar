import Cocoa
import ServiceManagement

// MARK: - Config

let defaults = UserDefaults.standard
let env = ProcessInfo.processInfo.environment

// MARK: - Localization
// English is the default. Korean can be chosen from the menu (Language). Strings live in
// res/<lang>.lproj/Localizable.strings; the English text is also the lookup key, so a missing
// translation simply falls back to English.

enum Lang {
    static var code: String {
        get {
            let c = env["LGTV_LANG"] ?? defaults.string(forKey: "language") ?? "en"
            return c == "ko" ? "ko" : "en"
        }
        set { defaults.set(newValue, forKey: "language") }
    }
    static var bundle: Bundle {
        if let p = Bundle.main.path(forResource: code, ofType: "lproj"), let b = Bundle(path: p) { return b }
        return Bundle.main
    }
}

func L(_ key: String) -> String { Lang.bundle.localizedString(forKey: key, value: key, table: nil) }
func LF(_ key: String, _ args: CVarArg...) -> String { String(format: L(key), arguments: args) }

enum Config {
    /// TV address. Empty until the TV has been discovered (SSDP) or set by the user.
    static var ip: String {
        get { env["LGTV_IP"] ?? defaults.string(forKey: "ip") ?? "" }
        set { if env["LGTV_IP"] == nil { defaults.set(newValue, forKey: "ip") } }
    }
    /// TV MAC address (needed for Wake-on-LAN). Learned automatically once the TV has been reached.
    static var mac: String {
        get { defaults.string(forKey: "mac") ?? "" }
        set { if env["LGTV_IP"] == nil { defaults.set(newValue, forKey: "mac") } }
    }
    static var port: Int { Int(env["LGTV_PORT"] ?? "") ?? 3001 }
    static var clientKey: String? {
        get { env["LGTV_IP"] != nil ? nil : defaults.string(forKey: "clientKey") }
        set { if env["LGTV_IP"] == nil { defaults.set(newValue, forKey: "clientKey") } }
    }
    static var channels: [[String]] {
        get {
            if let c = defaults.array(forKey: "channels") as? [[String]], !c.isEmpty { return c }
            return []
        }
        set { if env["LGTV_IP"] == nil { defaults.set(newValue, forKey: "channels") } }
    }
}

// MARK: - Helpers

func normMac(_ m: String) -> String {
    m.lowercased().split(separator: ":").map { $0.count == 1 ? "0" + $0 : String($0) }.joined(separator: ":")
}

func ipFromARP(mac: String) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
    p.arguments = ["-an"]
    let pipe = Pipe()
    p.standardOutput = pipe
    guard (try? p.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    let want = normMac(mac)
    for line in (String(data: data, encoding: .utf8) ?? "").split(separator: "\n") {
        guard let a = line.firstIndex(of: "("), let b = line.firstIndex(of: ")"), a < b else { continue }
        let ip = String(line[line.index(after: a)..<b])
        let rest = line[line.index(after: b)...]
        let parts = rest.split(separator: " ")
        if parts.count >= 2, parts[0] == "at", normMac(String(parts[1])) == want { return ip }
    }
    return nil
}

/// Look up the MAC address of `ip` in the ARP table (filled in once the TV has answered us).
func macFromARP(ip: String) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
    p.arguments = ["-n", ip]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    guard (try? p.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    let text = String(data: data, encoding: .utf8) ?? ""
    guard let r = text.range(of: " at ") else { return nil }
    let mac = text[r.upperBound...].split(separator: " ").first.map(String.init) ?? ""
    return mac.split(separator: ":").count == 6 ? normMac(mac) : nil
}

/// Find LG webOS TVs on the local network with an SSDP M-SEARCH. Returns their IP addresses.
/// `LGTV_SSDP=host:port` overrides the multicast target (used by the self-test only).
func ssdpDiscover(timeout: Double = 4.0) -> [String] {
    let target = env["LGTV_SSDP"] ?? "239.255.255.250:1900"
    let hp = target.split(separator: ":")
    guard hp.count == 2, let port = UInt16(hp[1]) else { return [] }
    let fd = socket(AF_INET, SOCK_DGRAM, 0)
    guard fd >= 0 else { return [] }
    defer { close(fd) }
    var tv = timeval(tv_sec: 0, tv_usec: 400_000)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    var dest = sockaddr_in()
    dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    dest.sin_family = sa_family_t(AF_INET)
    dest.sin_port = port.bigEndian
    inet_pton(AF_INET, String(hp[0]), &dest.sin_addr)
    let msg = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\n"
        + "ST: urn:lge-com:service:webos-second-screen:1\r\n\r\n"
    let bytes = Array(msg.utf8)
    for _ in 0..<2 {
        withUnsafePointer(to: &dest) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = sendto(fd, bytes, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }
    var found: [String] = []
    let end = Date().addingTimeInterval(timeout)
    var buf = [UInt8](repeating: 0, count: 2048)
    while Date() < end {
        var from = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let n = withUnsafeMutablePointer(to: &from) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                recvfrom(fd, &buf, buf.count, 0, $0, &len)
            }
        }
        if n <= 0 { continue }
        let text = String(decoding: buf[0..<n], as: UTF8.self).lowercased()
        guard text.contains("webos") || text.contains("lge-com") else { continue }
        var addr = from.sin_addr
        var cstr = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &addr, &cstr, socklen_t(INET_ADDRSTRLEN))
        let ip = String(cString: cstr)
        if !found.contains(ip) { found.append(ip) }
    }
    return found
}

func sendWoL(mac: String, tvIP: String) {
    let bytes = mac.split(separator: ":").compactMap { UInt8($0, radix: 16) }
    guard bytes.count == 6 else { return }
    var pkt = [UInt8](repeating: 0xFF, count: 6)
    for _ in 0..<16 { pkt += bytes }
    let fd = socket(AF_INET, SOCK_DGRAM, 0)
    guard fd >= 0 else { return }
    defer { close(fd) }
    var yes: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
    var dests = ["255.255.255.255"]
    let oct = tvIP.split(separator: ".")
    if oct.count == 4 { dests.append(oct[0...2].joined(separator: ".") + ".255") }
    for d in dests {
        for port in [9, 7] {
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = UInt16(port).bigEndian
            inet_pton(AF_INET, d, &addr.sin_addr)
            withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    _ = sendto(fd, pkt, pkt.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }
}

// MARK: - TV connection (webOS SSAP over secure websocket)

final class TV: NSObject, URLSessionDelegate, URLSessionWebSocketDelegate {
    private var session: URLSession!
    private var ws: URLSessionWebSocketTask?
    private var handlers: [String: ([String: Any]) -> Void] = [:]
    private var counter = 0
    private var waiters: [(Bool) -> Void] = []
    private var connecting = false
    private var timeout: DispatchWorkItem?
    /// Fallback stage when the TV is unreachable: 0 = try ARP by MAC, 1 = try SSDP discovery, 2 = give up.
    private var stage = 0
    private(set) var connected = false
    var log: (String) -> Void = { _ in }

    override init() {
        super.init()
        session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    }

    // The TV uses a self-signed certificate.
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    // MARK: connect

    func ensureConnected(_ done: @escaping (Bool) -> Void) {
        if connected { done(true); return }
        waiters.append(done)
        if connecting { return }
        connecting = true
        stage = 0
        open()
    }

    /// Forget the current connection (used by "Find TV Again").
    func reset() {
        timeout?.cancel()
        ws?.cancel(with: .goingAway, reason: nil)
        ws = nil
        connected = false
        connecting = false
        handlers.removeAll()
        waiters.removeAll()
    }

    private func discoverThenOpen() {
        stage = 2
        DispatchQueue.global().async { [weak self] in
            let ips = ssdpDiscover()
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let ip = ips.first { Config.ip = ip; self.open() } else { self.finish(false) }
            }
        }
    }

    private func open() {
        if Config.ip.isEmpty { discoverThenOpen(); return }
        ws?.cancel(with: .goingAway, reason: nil)
        handlers.removeAll()
        guard let url = URL(string: "wss://\(Config.ip):\(Config.port)") else { finish(false); return }
        let task = session.webSocketTask(with: url)
        ws = task
        task.resume()
        listen(task)
        sendRegister()
        armTimeout(6)
    }

    private func armTimeout(_ seconds: Double) {
        timeout?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.failed() }
        timeout = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }

    /// Connection attempt failed: the TV may have a new IP. Look it up by MAC (ARP), then by SSDP discovery.
    private func failed() {
        timeout?.cancel()
        switch stage {
        case 0:
            stage = 1
            DispatchQueue.global().async { [weak self] in
                let found = Config.mac.isEmpty ? nil : ipFromARP(mac: Config.mac)
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if let ip = found, ip != Config.ip { Config.ip = ip; self.open() } else { self.failed() }
                }
            }
        case 1:
            stage = 2
            DispatchQueue.global().async { [weak self] in
                let ips = ssdpDiscover(timeout: 3.0)
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if let ip = ips.first(where: { $0 != Config.ip }) { Config.ip = ip; self.open() } else { self.finish(false) }
                }
            }
        default:
            finish(false)
        }
    }

    private func finish(_ ok: Bool) {
        timeout?.cancel()
        connecting = false
        connected = ok
        if !ok { ws?.cancel(with: .goingAway, reason: nil); ws = nil }
        let w = waiters
        waiters.removeAll()
        w.forEach { $0(ok) }
    }

    private func sendRegister() {
        var payload: [String: Any] = [:]
        if let path = Bundle.main.path(forResource: "registration", ofType: "json") ??
            env["LGTV_REG"],
           let data = FileManager.default.contents(atPath: path),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            payload = obj
        }
        if let key = Config.clientKey { payload["client-key"] = key }
        send(["type": "register", "id": "register_0", "payload": payload])
    }

    // MARK: messaging

    private func listen(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, task === self.ws else { return }
                switch result {
                case .failure:
                    if self.connecting { self.failed() } else { self.connected = false; self.ws = nil }
                case .success(let msg):
                    if case .string(let s) = msg, let d = s.data(using: .utf8),
                       let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                        self.handle(j)
                    }
                    self.listen(task)
                }
            }
        }
    }

    private func handle(_ j: [String: Any]) {
        let type = j["type"] as? String ?? ""
        let id = j["id"] as? String ?? ""
        let payload = j["payload"] as? [String: Any] ?? [:]
        if id == "register_0" {
            if type == "registered" {
                if let key = payload["client-key"] as? String { Config.clientKey = key }
                finish(true)
                // Remember the TV's MAC address (needed for Wake-on-LAN) now that it has answered us.
                DispatchQueue.global().async {
                    if let m = macFromARP(ip: Config.ip), m != Config.mac {
                        DispatchQueue.main.async { Config.mac = m }
                    }
                }
            } else if type == "error" {
                finish(false)
            } else {
                log(L("Please allow the connection on the TV screen."))
                armTimeout(90)   // waiting for the pairing prompt on the TV
            }
            return
        }
        if let h = handlers[id] { handlers[id] = nil; h(j) }
    }

    private func send(_ obj: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: d, encoding: .utf8) else { return }
        ws?.send(.string(s)) { _ in }
    }

    func request(_ uri: String, _ payload: [String: Any] = [:], _ done: (([String: Any]) -> Void)? = nil) {
        ensureConnected { [weak self] ok in
            guard let self = self, ok else { self?.log(L("The TV is off or unreachable.")); return }
            self.counter += 1
            let id = "req_\(self.counter)"
            if let done = done { self.handlers[id] = done }
            self.send(["type": "request", "id": id, "uri": uri, "payload": payload])
        }
    }

    // MARK: high level commands

    func volumeUp() { request("ssap://audio/volumeUp") }
    func volumeDown() { request("ssap://audio/volumeDown") }
    func powerOff() { request("ssap://system/turnOff") }
    func openChannel(_ number: String) { request("ssap://tv/openChannel", ["channelNumber": number]) }
    func channelUp() { request("ssap://tv/channelUp") }
    func channelDown() { request("ssap://tv/channelDown") }
    func switchInput(_ id: String) { request("ssap://tv/switchInput", ["inputId": id]) }

    func toggleMute() {
        request("ssap://audio/getVolume") { [weak self] j in
            let p = j["payload"] as? [String: Any] ?? [:]
            let vs = p["volumeStatus"] as? [String: Any]
            let cur = (p["muted"] as? Bool) ?? (vs?["muteStatus"] as? Bool) ?? false
            self?.request("ssap://audio/setMute", ["mute": !cur])
        }
    }

    func volume(_ done: @escaping (Int?, Bool?) -> Void) {
        request("ssap://audio/getVolume") { j in
            let p = j["payload"] as? [String: Any] ?? [:]
            let vs = p["volumeStatus"] as? [String: Any]
            let v = (p["volume"] as? Int) ?? (vs?["volume"] as? Int)
            let m = (p["muted"] as? Bool) ?? (vs?["muteStatus"] as? Bool)
            done(v, m)
        }
    }

    func fetchChannels(_ done: @escaping ([[String]]) -> Void) {
        request("ssap://tv/getChannelList") { j in
            let list = (j["payload"] as? [String: Any])?["channelList"] as? [[String: Any]] ?? []
            done(list.compactMap {
                guard let n = $0["channelNumber"] as? String else { return nil }
                return [n, ($0["channelName"] as? String) ?? ""]
            })
        }
    }

    /// Remote-control keys (HOME, BACK, ENTER, UP, ...) go through the TV's pointer socket.
    func button(_ name: String) {
        request("ssap://com.webos.service.networkinput/getPointerInputSocket") { [weak self] j in
            guard let self = self,
                  let path = (j["payload"] as? [String: Any])?["socketPath"] as? String,
                  let url = URL(string: path) else { return }
            let t = self.session.webSocketTask(with: url)
            t.resume()
            t.send(.string("type:button\nname:\(name)\n\n")) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { t.cancel(with: .normalClosure, reason: nil) }
            }
        }
    }
}

// MARK: - Menu bar app

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let tv = TV()
    var item: NSStatusItem!
    let menu = NSMenu()
    let statusLine = NSMenuItem(title: "TV", action: nil, keyEquivalent: "")
    var channelMenu = NSMenu()
    var loginItem: NSMenuItem!
    var powering = false

    func applicationDidFinishLaunching(_ n: Notification) {
        tv.log = { [weak self] s in self?.setStatus(s) }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = item.button {
            if let img = NSImage(systemSymbolName: "tv", accessibilityDescription: "LG TV") {
                img.isTemplate = true
                b.image = img
            } else {
                b.title = "TV"
            }
        }
        buildMenu()
        item.menu = menu
    }

    func setStatus(_ s: String) { statusLine.title = "TV: " + s }

    func add(_ title: String, _ sel: Selector, to m: NSMenu? = nil, key: String = "") {
        let mi = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        mi.target = self
        (m ?? menu).addItem(mi)
    }

    func sub(_ title: String) -> NSMenu {
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let m = NSMenu(title: title)
        mi.submenu = m
        menu.addItem(mi)
        return m
    }

    func buildMenu() {
        menu.delegate = self
        statusLine.isEnabled = false
        setStatus(L("Checking…"))
        menu.addItem(statusLine)
        menu.addItem(.separator())
        add(L("Power On"), #selector(powerOn))
        add(L("Power Off"), #selector(powerOff))
        menu.addItem(.separator())
        add(L("Volume +"), #selector(volUp))
        add(L("Volume −"), #selector(volDown))
        add(L("Mute"), #selector(mute))
        menu.addItem(.separator())

        channelMenu = sub(L("Channel"))
        rebuildChannels()

        let inputs = sub(L("Input"))
        for (title, id) in [("HDMI 1", "HDMI_1"), ("HDMI 2", "HDMI_2"), ("HDMI 3", "HDMI_3"),
                            (L("External (AV)"), "AV_1"), (L("Component"), "COMP_1")] {
            let mi = NSMenuItem(title: title, action: #selector(inputPicked(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = id
            inputs.addItem(mi)
        }

        let remote = sub(L("Remote"))
        for (title, name) in [(L("Home"), "HOME"), (L("Back"), "BACK"), (L("OK"), "ENTER"), (L("▲ Up"), "UP"),
                              (L("▼ Down"), "DOWN"), (L("◀ Left"), "LEFT"), (L("▶ Right"), "RIGHT"), (L("Exit"), "EXIT")] {
            let mi = NSMenuItem(title: title, action: #selector(keyPicked(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = name
            remote.addItem(mi)
        }

        menu.addItem(.separator())
        add(L("Find TV Again"), #selector(rediscover))

        // Language: English is the default; Korean can be chosen here.
        let langMenu = sub(L("Language"))
        for (title, code) in [("English", "en"), ("한국어", "ko")] {
            let mi = NSMenuItem(title: title, action: #selector(languagePicked(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = code
            mi.state = Lang.code == code ? .on : .off
            langMenu.addItem(mi)
        }

        loginItem = NSMenuItem(title: L("Launch at Login"), action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        add(L("Quit"), #selector(quit), key: "q")
    }

    func rebuildChannels() {
        channelMenu.removeAllItems()
        for (title, sel) in [(L("Next Channel"), #selector(chUp)), (L("Previous Channel"), #selector(chDown))] {
            let mi = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            mi.target = self
            channelMenu.addItem(mi)
        }
        channelMenu.addItem(.separator())
        if Config.channels.isEmpty {
            let mi = NSMenuItem(title: L("Channel list loads when the TV is on"), action: nil, keyEquivalent: "")
            mi.isEnabled = false
            channelMenu.addItem(mi)
        }
        for c in Config.channels {
            let mi = NSMenuItem(title: "\(c[0])  \(c[1])", action: #selector(channelPicked(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = c[0]
            channelMenu.addItem(mi)
        }
    }

    // Refresh the status line whenever the menu is opened.
    func menuWillOpen(_ menu: NSMenu) {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        refreshStatus()
    }

    func refreshStatus() {
        if powering { return }
        setStatus(L("Checking…"))
        tv.ensureConnected { [weak self] ok in
            guard let self = self else { return }
            if !ok {
                self.setStatus(Config.ip.isEmpty
                               ? L("TV not found - turn it on and choose 'Find TV Again'")
                               : L("Off - choose Power On"))
                return
            }
            self.tv.volume { v, m in
                self.setStatus(LF("Connected, volume %@", v.map(String.init) ?? "?") + (m == true ? L(" (muted)") : ""))
            }
            self.tv.fetchChannels { list in
                if !list.isEmpty { Config.channels = list; self.rebuildChannels() }
            }
        }
    }

    // MARK: actions

    @objc func powerOn() {
        if powering { return }
        if Config.mac.isEmpty {
            setStatus(L("The TV's MAC address is not known yet - open this menu once while the TV is on"))
            return
        }
        powering = true
        setStatus(L("Turning on… (about 20-30 s)"))
        var attempts = 0
        func tick() {
            attempts += 1
            sendWoL(mac: Config.mac, tvIP: Config.ip)
            tv.ensureConnected { [weak self] ok in
                guard let self = self else { return }
                if ok { self.powering = false; self.setStatus(L("Connected")); return }
                if attempts >= 20 {
                    self.powering = false
                    self.setStatus(L("No response - check the TV's Wake on LAN setting"))
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { tick() }
            }
        }
        tick()
    }

    @objc func powerOff() { tv.powerOff(); setStatus(L("Turning off…")) }
    @objc func volUp() { tv.volumeUp() }
    @objc func volDown() { tv.volumeDown() }
    @objc func mute() { tv.toggleMute() }
    @objc func chUp() { tv.channelUp() }
    @objc func chDown() { tv.channelDown() }
    @objc func channelPicked(_ s: NSMenuItem) { if let n = s.representedObject as? String { tv.openChannel(n) } }
    @objc func inputPicked(_ s: NSMenuItem) { if let n = s.representedObject as? String { tv.switchInput(n) } }
    @objc func keyPicked(_ s: NSMenuItem) { if let n = s.representedObject as? String { tv.button(n) } }

    /// Forget the saved TV address and search the network again (e.g. after buying a new TV).
    @objc func rediscover() {
        Config.ip = ""
        tv.reset()
        setStatus(L("Searching for the TV…"))
        refreshStatus()
    }

    /// Switch the menu language and rebuild the menu.
    @objc func languagePicked(_ s: NSMenuItem) {
        guard let code = s.representedObject as? String else { return }
        Lang.code = code
        menu.removeAllItems()
        buildMenu()
        refreshStatus()
    }

    @objc func toggleLogin() {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
        } catch {
            setStatus(LF("Couldn't change launch at login: %@", error.localizedDescription))
        }
    }

    @objc func quit() { NSApp.terminate(nil) }
}

// MARK: - entry point

if CommandLine.arguments.contains("--l10n-test") {
    // Prints a few translated strings for the language given by LGTV_LANG.
    print(Lang.code, "|", L("Power On"), "|", L("Quit"), "|", LF("Connected, volume %@", "12"))
    exit(0)
} else if CommandLine.arguments.contains("--discover-test") {
    // Prints the TVs found by SSDP discovery, then exits.
    print("found:", ssdpDiscover(timeout: 3.0))
    exit(0)
} else if CommandLine.arguments.contains("--selftest") {
    // Used only against a fake local server: connects, runs a few commands, prints results.
    let tv = TV()
    tv.log = { print("log:", $0) }
    tv.ensureConnected { ok in
        print("connected:", ok)
        guard ok else { exit(1) }
        tv.volumeUp()
        tv.openChannel("5-1")
        tv.switchInput("HDMI_1")
        tv.toggleMute()
        tv.button("HOME")
        tv.volume { v, m in print("volume:", v as Any, "muted:", m as Any) }
        tv.fetchChannels { print("channels:", $0) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { print("done"); exit(0) }
    }
    dispatchMain()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
