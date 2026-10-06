// Amnesia v5.8 — app Mac asli (SwiftUI): jendela utama + ikon status di menu bar.
// Dibuild oleh build.sh (swiftc dari Command Line Tools, tanpa Xcode).
// Logika berat tetap di ~/.amnesia: clean.sh, agent.sh, vault.py (dipanggil lewat Process).
import AppKit
import AuthenticationServices
import Security
import SwiftUI

// MARK: - Lokasi file

enum P {
    /// AMNESIA_HOME = home palsu (dipakai mode screenshot & tes). Normalnya folder home kamu.
    static let home = ProcessInfo.processInfo.environment["AMNESIA_HOME"] ?? NSHomeDirectory()
    static let realHome = NSHomeDirectory()
    static let a = home + "/.amnesia"
    static let label = "com.amnesia.agent"
    static let plist = home + "/Library/LaunchAgents/com.amnesia.agent.plist"
    static let oldLabel = "com.amnesia.loginreset"
    static let oldPlist = home + "/Library/LaunchAgents/com.amnesia.loginreset.plist"
    static let keep = a + "/keep.conf"
    static let pause = a + "/pause_once"
    static let cleanLog = a + "/clean.log"
    static let checksums = a + "/backup_checksums.txt"
    static let vaultPy = a + "/vault.py"
    static let backupSh = a + "/backup.sh"
    static let backupLog = a + "/backup.log"
    static let backupOk = a + "/backup.ok"
    static let report = a + "/report.txt"
    static let sevenz = "/opt/homebrew/bin/7zz"
    static let launchctl = "/bin/launchctl"
    static let domain = "gui/\(getuid())"
    static var python: String {
        FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/python3")
            ? "/opt/homebrew/bin/python3" : "/usr/bin/python3"
    }
}

let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"

// MARK: - Bahasa (English utama, Bahasa Indonesia tambahan). Disimpan di settings.conf: LANG=en|id

enum Lang: String, CaseIterable {
    case en, id
    var name: String { self == .en ? "English" : "Bahasa Indonesia" }

    static var current: Lang = load()

    static func load() -> Lang {
        if let l = Lang(rawValue: Config.get("LANG")) { return l }
        let l: Lang = Locale.preferredLanguages.first?.hasPrefix("id") == true ? .id : .en
        Config.set("LANG", l.rawValue)          // agent.sh, backup.sh & vault.py ikut bahasa ini
        return l
    }
}

/// Teks sesuai bahasa yang dipilih: T("English", "Indonesia")
func T(_ en: String, _ id: String) -> String { Lang.current == .id ? id : en }

// MARK: - Menjalankan program lain

struct Out {
    var code: Int32
    var out: String
    var err: String
}

final class DataBox: @unchecked Sendable { var data = Data() }

/// Jalankan program. Password dikirim lewat stdin, tidak pernah lewat argumen.
@discardableResult
func sh(_ exe: String, _ args: [String], input: String? = nil, cwd: String? = nil, timeout: Double? = nil,
        env: [String: String] = [:], onStart: (@Sendable (Process) -> Void)? = nil,
        onErr: (@Sendable (String) -> Void)? = nil) -> Out {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    if !env.isEmpty { p.environment = ProcessInfo.processInfo.environment.merging(env) { _, n in n } }
    if let cwd = cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
    let o = Pipe(), e = Pipe(), i = Pipe()
    p.standardOutput = o
    p.standardError = e
    p.standardInput = i
    do { try p.run() } catch { return Out(code: -1, out: "", err: error.localizedDescription) }
    onStart?(p)
    if let t = timeout {
        DispatchQueue.global().asyncAfter(deadline: .now() + t) { if p.isRunning { p.terminate() } }
    }
    if let input = input { try? i.fileHandleForWriting.write(contentsOf: Data(input.utf8)) }
    try? i.fileHandleForWriting.close()
    // stderr dibaca paralel supaya program tidak macet kalau outputnya banyak
    let errBox = DataBox()
    let g = DispatchGroup()
    g.enter()
    DispatchQueue.global().async {
        let h = e.fileHandleForReading
        while true {                       // dibaca per potong, supaya onErr bisa melihat output secara langsung
            let d = h.availableData
            if d.isEmpty { break }
            errBox.data.append(d)
            onErr?(String(decoding: errBox.data, as: UTF8.self))
        }
        g.leave()
    }
    let od = o.fileHandleForReading.readDataToEndOfFile()
    g.wait()
    p.waitUntilExit()
    return Out(code: p.terminationStatus, out: String(decoding: od, as: UTF8.self),
               err: String(decoding: errBox.data, as: UTF8.self))
}

// MARK: - Profile Vault (lewat vault.py)

struct Manifest: Decodable {
    let apps: [String]
    let time: String
    let size_mb: Double
}

struct KeysInfo: Decodable {
    let apps: [String]
    let time: String
}

struct VaultReply: Decodable {
    let ok: Bool
    let error: String?
    let exists: Bool?
    let manifest: Manifest?
    let attempts: Int?
    let max: Int?
    let min: Int?
    let apps: [String]?
    let keys: KeysInfo?

    static func fail(_ msg: String) -> VaultReply {
        VaultReply(ok: false, error: msg, exists: nil, manifest: nil, attempts: nil, max: nil, min: nil, apps: nil,
                   keys: nil)
    }
}

func vaultCall(_ args: [String], input: String = "") -> VaultReply {
    let r = sh(P.python, [P.vaultPy] + args, input: input)
    let last = r.out.split(separator: "\n").last.map(String.init) ?? ""
    do {
        return try JSONDecoder().decode(VaultReply.self, from: Data(last.utf8))
    } catch {
        let detail = r.err.isEmpty ? "\(error)" : r.err
        return .fail(T("vault.py is not responding.\n", "vault.py tidak merespons.\n") + String(detail.suffix(300)))
    }
}

// MARK: - Mesin Amnesia (script di dalam app → ~/.amnesia)

enum Engine {
    static let files = ["clean.sh", "agent.sh", "vault.py", "backup.sh", "keep.example.conf"]

    static var sevenz: String? {
        [P.a + "/bin/7zz", "/opt/homebrew/bin/7zz", "/usr/local/bin/7zz"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var ready: Bool { files.allSatisfy { FileManager.default.fileExists(atPath: P.a + "/" + $0) } }

    /// Python untuk Profile Vault: dari Homebrew, atau dari Command Line Tools Apple.
    static var hasPython: Bool {
        FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/python3")
            || sh("/usr/bin/xcode-select", ["-p"]).code == 0
    }

    /// Full Disk Access: 1 izin untuk semua folder (Desktop, Documents, Downloads, Safari, dll.).
    /// Dicek dengan membuka file yang hanya bisa dibaca kalau izin itu sudah ada.
    static var hasFullDisk: Bool {
        guard let h = FileHandle(forReadingAtPath: P.realHome + "/Library/Application Support/com.apple.TCC/TCC.db")
        else { return false }
        try? h.close()
        return true
    }

    static func openFullDiskSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }

    /// Pasang/perbarui script di ~/.amnesia dari dalam app (sekali per versi).
    /// keep.conf, settings.conf dan vault tidak pernah ditimpa. Folder hasil git clone (developer) tidak disentuh.
    static func install() {
        let fm = FileManager.default
        guard let res = Bundle.main.resourcePath, fm.fileExists(atPath: res + "/engine") else { return }
        try? fm.createDirectory(atPath: P.a + "/bin", withIntermediateDirectories: true)
        let mark = P.a + "/.engine_version"
        let fresh = (try? String(contentsOfFile: mark, encoding: .utf8)) != appVersion
        let dev = fm.fileExists(atPath: P.a + "/.git")
        for f in files where !dev && (fresh || !fm.fileExists(atPath: P.a + "/" + f)) {
            try? fm.removeItem(atPath: P.a + "/" + f)
            try? fm.copyItem(atPath: res + "/engine/" + f, toPath: P.a + "/" + f)
        }
        let z = res + "/bin/7zz", dz = P.a + "/bin/7zz"
        if fm.fileExists(atPath: z) && (fresh || !fm.fileExists(atPath: dz)) {
            try? fm.removeItem(atPath: dz)
            try? fm.copyItem(atPath: z, toPath: dz)
            sh("/usr/bin/xattr", ["-d", "com.apple.quarantine", dz])
        }
        if !fm.fileExists(atPath: P.keep) { try? fm.copyItem(atPath: P.a + "/keep.example.conf", toPath: P.keep) }
        if Config.get("LANG").isEmpty { Config.set("LANG", Lang.current.rawValue) }
        try? appVersion.write(toFile: mark, atomically: true, encoding: .utf8)
    }
}

// MARK: - Agent (dijalankan launchd saat login)

enum Agent {
    /// App yang dibuka dari Downloads (macOS "App Translocation") punya path sementara: pakai yang di Applications.
    static var program: [String] {
        let fallback = "/Applications/Amnesia.app/Contents/MacOS/Amnesia"
        guard let exe = Bundle.main.executablePath, !exe.contains("/AppTranslocation/"),
              exe.hasPrefix("/Applications/") || exe.hasPrefix(P.realHome + "/Applications/") else { return [fallback, "--agent"] }
        return [exe, "--agent"]
    }

    /// LaunchAgent menjalankan app ini dengan --agent, lalu app menjalankan agent.sh sebagai "anaknya".
    /// Dengan begitu izin Full Disk Access milik Amnesia ikut berlaku untuk pembersihan saat logout.
    static func writePlist() -> String? {
        let dict: [String: Any] = [
            "Label": P.label,
            "ProgramArguments": program,
            "RunAtLoad": true,
            "ExitTimeOut": 300,      // waktu untuk snapshot otomatis + pembersihan
        ]
        do {
            try FileManager.default.createDirectory(atPath: (P.plist as NSString).deletingLastPathComponent,
                                                    withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
            try data.write(to: URL(fileURLWithPath: P.plist), options: .atomic)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Plist versi lama (bash langsung) atau app yang dipindah: perbarui. Berlaku mulai login berikutnya.
    static func migrate() {
        guard let d = NSDictionary(contentsOfFile: P.plist),
              (d["ProgramArguments"] as? [String]) != program else { return }
        _ = writePlist()
    }

    /// Mode --agent: jalankan agent.sh, teruskan sinyal logout (TERM) ke sana, tunggu sampai selesai.
    static func run() -> Never {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [P.a + "/agent.sh"]
        do { try p.run() } catch { exit(1) }
        // sinyal diabaikan SETELAH agent.sh jalan (kalau sebelumnya, trap di bash tidak berfungsi)
        var sources: [DispatchSourceSignal] = []
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .global())
            src.setEventHandler { if p.isRunning { kill(p.processIdentifier, sig) } }
            src.resume()
            sources.append(src)
        }
        p.waitUntilExit()
        withExtendedLifetime(sources) {}
        exit(p.terminationStatus)
    }
}

// MARK: - Deteksi app yang terpasang (untuk memilih yang di-keep)

struct FoundApp: Identifiable {
    let name: String
    let icon: NSImage
    let paths: [String]      // relatif dari home
    let inVault: Bool
    var id: String { name }
}

/// App yang login-nya sudah diurus Profile Vault (tetap bisa dipilih untuk di-keep utuh).
let vaultApps = ["Google Chrome", "Claude", "WhatsApp", "Windows App", "Antigravity"]
/// App yang disarankan untuk di-keep (VPN & password manager): settingnya tidak rahasia dan repot diatur ulang.
let suggestWords = ["vpn", "tailscale", "nord", "surfshark", "proton", "mullvad", "1password", "bitwarden"]

/// Nama yang mudah dibaca untuk 1 path data app.
func pathKind(_ p: String) -> (icon: String, label: String) {
    if p.hasPrefix("Library/Application Support/") { return ("folder.fill", T("App data", "Data app")) }
    if p.hasPrefix("Library/Containers/") { return ("shippingbox.fill", T("App data (sandbox)", "Data app (sandbox)")) }
    if p.hasPrefix("Library/Group Containers/") { return ("square.stack.3d.up.fill", T("Shared data", "Data bersama")) }
    if p.hasPrefix("Library/Preferences/") { return ("slider.horizontal.3", T("Settings", "Setting")) }
    return ("doc.fill", T("Files", "File"))
}

/// Ukuran folder yang mudah dibaca, mis. "120 MB" (pakai du, cepat).
func folderSize(_ rel: String) -> String {
    let base = P.home + "/" + rel.replacingOccurrences(of: "*", with: "")
    let paths = rel.hasSuffix("*")
        ? (((try? FileManager.default.contentsOfDirectory(atPath: (base as NSString).deletingLastPathComponent)) ?? [])
            .filter { $0.hasPrefix((base as NSString).lastPathComponent) }
            .map { ((base as NSString).deletingLastPathComponent as NSString).appendingPathComponent($0) })
        : [base]
    let out = sh("/usr/bin/du", ["-sk"] + paths, timeout: 20).out
    let kb = out.split(separator: "\n").compactMap { Int($0.split(separator: "\t").first ?? "") }.reduce(0, +)
    return ByteCountFormatter.string(fromByteCount: Int64(kb) * 1024, countStyle: .file)
}

func keepMatches(_ path: String, _ entries: [String]) -> Bool {
    entries.contains { fnmatch($0, path, 0) == 0 || path.hasPrefix($0 + "/") }
}

func scanApps() -> [FoundApp] {
    let fm = FileManager.default
    let lib = P.home + "/Library/"
    let groups = (try? fm.contentsOfDirectory(atPath: lib + "Group Containers")) ?? []
    var out: [FoundApp] = []
    var seen = Set<String>()
    for dir in ["/Applications", P.home + "/Applications"] {
        for f in ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).sorted() where f.hasSuffix(".app") {
            let path = dir + "/" + f
            guard let bid = Bundle(path: path)?.bundleIdentifier, !bid.hasPrefix("com.apple."),
                  bid != Bundle.main.bundleIdentifier, !seen.contains(bid) else { continue }
            seen.insert(bid)
            let name = String(f.dropLast(4))
            var p: [String] = []
            for c in ["Application Support/" + name, "Application Support/" + bid, "Containers/" + bid]
            where fm.fileExists(atPath: lib + c) {
                p.append("Library/" + c)
            }
            p += groups.filter { $0.localizedCaseInsensitiveContains(bid) }.map { "Library/Group Containers/" + $0 }
            if fm.fileExists(atPath: lib + "Preferences/\(bid).plist") { p.append("Library/Preferences/\(bid)*") }
            guard !p.isEmpty else { continue }
            out.append(FoundApp(name: name, icon: NSWorkspace.shared.icon(forFile: path), paths: p,
                                inVault: vaultApps.contains(name)))
        }
    }
    return out
}

func defaultPicks(_ apps: [FoundApp]) -> Set<String> {
    let kept = Keep.entries()
    return Set(apps.filter { a in
        a.paths.allSatisfy { keepMatches($0, kept) }
            || (!a.inVault && suggestWords.contains { a.name.lowercased().contains($0) })
    }.map(\.name))
}

/// Tambah app yang dipilih ke Keep List; app yang dimatikan dihapus (hanya baris yang persis miliknya).
func applyPicks(_ apps: [FoundApp], _ picked: Set<String>) {
    let kept = Keep.entries()
    for a in apps where !picked.contains(a.name) {
        for p in a.paths where kept.contains(p) { Keep.remove(p) }
    }
    let add = apps.filter { picked.contains($0.name) }.flatMap(\.paths).filter { !keepMatches($0, kept) }
    if !add.isEmpty { Keep.add(add) }
}

// MARK: - Keep List (keep.conf)

enum Keep {
    static func text() -> String { (try? String(contentsOfFile: P.keep, encoding: .utf8)) ?? "" }

    static func entries() -> [String] {
        text().components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    static func add(_ items: [String]) {
        var t = text()
        if !t.isEmpty && !t.hasSuffix("\n") { t += "\n" }
        t += items.map { $0 + "\n" }.joined()
        try? t.write(toFile: P.keep, atomically: true, encoding: .utf8)
    }

    /// Komentar & baris lain tetap utuh.
    static func remove(_ item: String) {
        let lines = text().components(separatedBy: "\n").filter { $0.trimmingCharacters(in: .whitespaces) != item }
        try? lines.joined(separator: "\n").write(toFile: P.keep, atomically: true, encoding: .utf8)
    }

    static func candidates() -> [String] {
        let fm = FileManager.default
        let kept = Set(entries())
        var out: [String] = []
        for base in ["Library/Application Support", "Library/Containers", "Library/Group Containers"] {
            let names = ((try? fm.contentsOfDirectory(atPath: P.home + "/" + base)) ?? []).sorted()
            out += names.filter { !$0.hasPrefix(".") && !$0.contains("com.apple") && $0 != "Apple" }
                .map { base + "/" + $0 }
        }
        let dots = ((try? fm.contentsOfDirectory(atPath: P.home)) ?? []).sorted().filter { n in
            var dir: ObjCBool = false
            return n.hasPrefix(".") && n != ".Trash" && n != ".amnesia"
                && fm.fileExists(atPath: P.home + "/" + n, isDirectory: &dir) && dir.boolValue
        }
        return (out + dots).filter { !kept.contains($0) }
    }
}

// MARK: - Folder Keep (bisa di mana saja, nama apa saja). settings.conf: KEEP_DIR=~/Keep | /path/lengkap

enum KeepDir {
    static var raw: String {
        let r = Config.get("KEEP_DIR", "~/Keep")
        return r.hasPrefix("~/") || r.hasPrefix("/") ? r : "~/Keep"
    }
    static var path: String { raw.hasPrefix("~/") ? P.home + "/" + String(raw.dropFirst(2)) : raw }
    /// Untuk ditampilkan: ~/Keep, ~/Documents/Penting, /Volumes/SSD/Keep
    static var shown: String { raw }
    static var name: String { (path as NSString).lastPathComponent }

    /// Folder yang tidak boleh dijadikan folder Keep. Hasil: pesan error, atau nil kalau boleh.
    static func problem(_ p: String) -> String? {
        let h = P.home
        let bad = ["/", "/Users", "/Volumes", "/Applications", "/System", "/Library", "/private", h, h + "/Library",
                   h + "/Desktop", h + "/Documents", h + "/Downloads"]
        if bad.contains(p) || p.hasPrefix(h + "/.amnesia") || p.hasPrefix(h + "/.Trash") || p.split(separator: "/").count < 2 {
            return T("Pick or create a folder of its own, not a whole system or home folder.",
                     "Pilih atau buat folder tersendiri, bukan folder sistem atau folder home utuh.")
        }
        return nil
    }

    /// Simpan lokasi baru. Isi folder lama bisa dipindahkan ke yang baru.
    static func set(_ newPath: String, moveFiles: Bool) {
        let fm = FileManager.default
        let old = path
        try? fm.createDirectory(atPath: newPath, withIntermediateDirectories: true)
        if moveFiles && old != newPath {
            for f in (try? fm.contentsOfDirectory(atPath: old)) ?? [] where !fm.fileExists(atPath: newPath + "/" + f) {
                try? fm.moveItem(atPath: old + "/" + f, toPath: newPath + "/" + f)
            }
        }
        // pintasan di Desktop ikut diganti
        let oldLink = P.home + "/Desktop/" + (old as NSString).lastPathComponent
        if (try? fm.destinationOfSymbolicLink(atPath: oldLink)) == old { try? fm.removeItem(atPath: oldLink) }
        let stored = newPath.hasPrefix(P.home + "/") ? "~/" + String(newPath.dropFirst(P.home.count + 1)) : newPath
        Config.set("KEEP_DIR", stored)
        let link = P.home + "/Desktop/" + (newPath as NSString).lastPathComponent
        if !newPath.hasPrefix(P.home + "/Desktop") && !fm.fileExists(atPath: link) {
            try? fm.createSymbolicLink(atPath: link, withDestinationPath: newPath)
        }
    }
}

// MARK: - Pengaturan (~/.amnesia/settings.conf, juga dibaca agent.sh). Default semua AKTIF.

enum Config {
    static let path = P.a + "/settings.conf"

    static func lines() -> [String] {
        ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "").components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    static func get(_ key: String, _ def: String = "") -> String {
        lines().last { $0.hasPrefix(key + "=") }.map { String($0.dropFirst(key.count + 1)) } ?? def
    }

    static func set(_ key: String, _ value: String) {
        let v = value.replacingOccurrences(of: "\n", with: "").trimmingCharacters(in: .whitespaces)
        let l = lines().filter { !$0.hasPrefix(key + "=") } + ["\(key)=\(v)"]
        try? (l.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }
}

enum Setting: String {
    case autoSnapshot = "AUTO_SNAPSHOT", notify = "NOTIFY", preview = "PREVIEW"

    var isOn: Bool { Config.get(rawValue) != "0" }
    func set(_ on: Bool) { Config.set(rawValue, on ? "1" : "0") }
}

// MARK: - Dry-run (lihat yang akan dihapus)

struct DryGroup: Identifiable {
    let name: String
    let items: [String]
    var id: String { name }
}

/// Jalankan clean.sh --dry-run dan simpan hasilnya di report.txt (dihapus lagi saat pembersihan sungguhan).
func dryRun() -> [DryGroup] {
    let r = sh("/bin/bash", [P.a + "/clean.sh", "logout", "--dry-run"])
    if FileManager.default.createFile(atPath: P.report, contents: Data(r.out.utf8), attributes: [.posixPermissions: 0o600]) == false {
        try? r.out.write(toFile: P.report, atomically: true, encoding: .utf8)
    }
    return parseDry(r.out)
}

/// Laporan terakhir yang tersimpan (langsung tampil, tanpa menunggu).
func cachedReport() -> (groups: [DryGroup], time: Date)? {
    guard let t = try? String(contentsOfFile: P.report, encoding: .utf8),
          let d = (try? FileManager.default.attributesOfItem(atPath: P.report))?[.modificationDate] as? Date
    else { return nil }
    return (parseDry(t), d)
}

func parseDry(_ text: String) -> [DryGroup] {
    var groups: [String: [String]] = [:]
    for line in text.split(separator: "\n").map(String.init) {
        let parts = line.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { continue }
        let kind = String(parts[0])
        let item = parts[1].trimmingCharacters(in: .whitespaces)
        let key: String
        if kind.hasPrefix("KEYCHAIN") {
            key = T("Keychain (passwords & logins)", "Keychain (password & login)")
        } else if kind == "HAPUS" {
            let comps = item.replacingOccurrences(of: "~/", with: "").split(separator: "/").map(String.init)
            let first = comps.first ?? item
            if first == "Library" && comps.count > 1 {
                key = "Library/" + comps[1]
            } else if first.hasPrefix(".") {
                key = T("Hidden files & folders", "File & folder tersembunyi")
            } else {
                key = first
            }
        } else {
            continue
        }
        groups[key, default: []].append(item)
    }
    return groups.map { DryGroup(name: $0.key, items: $0.value) }.sorted { $0.items.count > $1.items.count }
}

enum QuitAction {
    case logout, restart, shutdown

    var title: String {
        switch self {
        case .logout: return "Logout"
        case .restart: return "Restart"
        case .shutdown: return T("Shut Down", "Matikan Mac")
        }
    }

    /// Event ke loginwindow tanpa dialog konfirmasi.
    var event: String {
        switch self {
        case .logout: return "aevtrlgo"
        case .restart: return "aevtrrst"
        case .shutdown: return "aevtrsdn"
        }
    }
}

// MARK: - Backup (lewat backup.sh)

struct Drive: Identifiable, Hashable {
    let name: String
    let free: String
    var id: String { name }
}

func listDrives() -> [Drive] {
    let fm = FileManager.default
    return ((try? fm.contentsOfDirectory(atPath: "/Volumes")) ?? []).sorted().compactMap { (n: String) -> Drive? in
        let path = "/Volumes/" + n
        guard !n.hasPrefix("."),
              URL(fileURLWithPath: path).resolvingSymlinksInPath().path != "/",
              fm.isWritableFile(atPath: path),
              let attrs = try? fm.attributesOfFileSystem(forPath: path),
              let free = (attrs[.systemFreeSize] as? NSNumber)?.doubleValue
        else { return nil }
        return Drive(name: n, free: String(format: T("%.1f GB free", "%.1f GB kosong"), free / 1_073_741_824))
    }
}

/// Password backup disimpan di Keychain (hanya kalau user mau), untuk backup terjadwal.
/// Item "Amnesia Backup" ada di Keep List, jadi tidak ikut dihapus saat logout.
enum Secret {
    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "Amnesia Backup",
         kSecAttrAccount as String: "amnesia"]
    }

    static func get() -> String? {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    /// Cek ada atau tidak, tanpa membaca isinya (tidak memicu dialog izin).
    static var exists: Bool {
        var q = base
        q[kSecReturnAttributes as String] = true
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func set(_ pw: String) -> Bool {
        SecItemDelete(base as CFDictionary)
        var q = base
        q[kSecValueData as String] = Data(pw.utf8)
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func delete() { SecItemDelete(base as CFDictionary) }
}

/// Layanan cloud yang bisa dihubungkan cukup dengan login di browser (lewat rclone).
struct CloudProvider: Identifiable, Hashable {
    let id: String        // tipe rclone
    let name: String
    let remote: String    // nama remote bawaan
}

let cloudProviders = [
    CloudProvider(id: "drive", name: "Google Drive", remote: "gdrive"),
    CloudProvider(id: "dropbox", name: "Dropbox", remote: "dropbox"),
    CloudProvider(id: "onedrive", name: "OneDrive", remote: "onedrive"),
    CloudProvider(id: "box", name: "Box", remote: "box"),
    CloudProvider(id: "pcloud", name: "pCloud", remote: "pcloud"),
]

func rcloneBin() -> String? {
    ["/opt/homebrew/bin/rclone", "/usr/local/bin/rclone"].first { FileManager.default.isExecutableFile(atPath: $0) }
}

func rcloneRemotes() -> [String] {
    guard let r = rcloneBin() else { return [] }
    return sh(r, ["listremotes"], timeout: 20).out.split(separator: "\n").map { String($0.dropLast()) }
}

/// Jendela login kecil milik macOS (ASWebAuthenticationSession), bukan Chrome/browser kamu.
/// Diizinkan oleh Google & yang lain, dan tidak memakai cookie browser (sesi sekali pakai).
@MainActor
final class WebLogin: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebLogin()
    private var session: ASWebAuthenticationSession?
    private var done = false

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.windows.first { $0.isVisible && $0.canBecomeKey } ?? NSApp.keyWindow ?? NSWindow()
        }
    }

    /// onCancel: dipanggil kalau kamu menutup jendelanya sebelum selesai.
    func open(_ url: URL, onCancel: @escaping @MainActor () -> Void) {
        close()
        done = false
        // callback "amnesia-login" tidak pernah dipanggil: rclone menerima kodenya sendiri di 127.0.0.1,
        // lalu jendela ini ditutup oleh app begitu rclone selesai.
        let s = ASWebAuthenticationSession(url: url, callbackURLScheme: "amnesia-login") { [weak self] _, _ in
            Task { @MainActor in
                guard let self, !self.done else { return }
                self.session = nil
                onCancel()
            }
        }
        s.presentationContextProvider = self
        s.prefersEphemeralWebBrowserSession = true
        session = s
        if !s.start() { NSWorkspace.shared.open(url) }   // cadangan: browser biasa
    }

    func close() {
        done = true
        session?.cancel()
        session = nil
    }
}

final class ProcBox: @unchecked Sendable { var p: Process?; var opened = false }

/// Hubungkan cloud tanpa Terminal: pasang rclone kalau perlu, buka login di jendela kecil, lalu cek koneksinya.
/// Hasil: pesan error, atau nil kalau berhasil. Token tidak pernah ditampilkan.
func connectCloud(_ p: CloudProvider, remote: String) -> String? {
    var rc = rcloneBin()
    if rc == nil {
        guard let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return T("rclone isn't installed, and neither is Homebrew. Install Homebrew from brew.sh first.",
                     "rclone belum terpasang, Homebrew juga belum. Pasang Homebrew dulu dari brew.sh.")
        }
        sh(brew, ["install", "rclone"], timeout: 900)
        rc = rcloneBin()
    }
    guard let r = rc else { return T("Couldn't install rclone.", "Gagal memasang rclone.") }
    if rcloneRemotes().contains(remote) { sh(r, ["config", "delete", remote]) }   // login ulang = token baru
    // rclone tidak membuka browser sendiri; link login-nya dibuka di jendela kecil Amnesia
    let box = ProcBox()
    let c = sh(r, ["config", "create", remote, p.id, "--auth-no-open-browser"], timeout: 300,
               onStart: { box.p = $0 },
               onErr: { text in
                   guard !box.opened,
                         let m = text.range(of: #"http://127\.0\.0\.1:53682/auth\?state=[A-Za-z0-9_-]+"#, options: .regularExpression),
                         let url = URL(string: String(text[m])) else { return }
                   box.opened = true
                   Task { @MainActor in
                       WebLogin.shared.open(url) { if box.p?.isRunning == true { box.p?.terminate() } }
                   }
               })
    Task { @MainActor in WebLogin.shared.close() }
    guard c.code == 0, sh(r, ["lsd", remote + ":"], timeout: 60).code == 0 else {
        return T("\(p.name) isn't connected. Try again and finish the login in your browser.",
                 "\(p.name) belum terhubung. Coba lagi dan selesaikan login di browser.")
    }
    return nil
}

/// Format server yang aman dipakai: user@host atau user@host:folder (tanpa spasi & karakter aneh).
func validServer(_ s: String) -> Bool {
    s.range(of: #"^[A-Za-z0-9._-]+@[A-Za-z0-9.-]+(:[A-Za-z0-9._/~-]*)?$"#, options: .regularExpression) != nil
}

/// Hubungkan server SSH tanpa Terminal. Kalau kunci SSH belum diterima server, password dipakai SEKALI
/// untuk memasang kunci (lewat SSH_ASKPASS, file sementara 0600 yang langsung dihapus). Password tidak disimpan.
/// Hasil: (berhasil, pesan). Pesan sukses menyebut folder lengkap tujuan backup di server.
func connectSSH(_ server: String, password: String) -> (ok: Bool, msg: String) {
    let parts = server.split(separator: ":", maxSplits: 1).map(String.init)
    let host = parts.first ?? ""
    let rpath = parts.count > 1 && !parts[1].isEmpty ? parts[1] : "amnesia-backup"
    let base = ["-o", "ConnectTimeout=15", "-o", "StrictHostKeyChecking=accept-new"]
    let fm = FileManager.default
    let key = P.home + "/.ssh/id_ed25519"
    func whereIs() -> Out {
        sh("/usr/bin/ssh", base + ["-o", "BatchMode=yes", host, "mkdir -p -- \(rpath) && cd -- \(rpath) && pwd"], timeout: 40)
    }
    var w = whereIs()
    if w.code != 0 {
        if w.err.contains("Could not resolve") || w.err.contains("timed out") || w.err.contains("refused") {
            return (false, T("Can't reach \(host). Check the address and your internet.",
                             "\(host) tidak bisa dihubungi. Cek alamat dan internet kamu.") + "\n\n" + String(w.err.suffix(200)))
        }
        guard !password.isEmpty else {
            return (false, T("This server doesn't know Amnesia's key yet. Type the server password once, then press Connect.",
                             "Server ini belum kenal kunci Amnesia. Ketik password server sekali, lalu tekan Hubungkan."))
        }
        if !fm.fileExists(atPath: key) {
            try? fm.createDirectory(atPath: P.home + "/.ssh", withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
            let g = sh("/usr/bin/ssh-keygen", ["-t", "ed25519", "-N", "", "-q", "-f", key, "-C", "amnesia"])
            guard g.code == 0 else { return (false, T("Couldn't make an SSH key: ", "Gagal membuat kunci SSH: ") + g.err) }
        }
        guard let pub = try? String(contentsOfFile: key + ".pub", encoding: .utf8) else {
            return (false, T("Couldn't read ~/.ssh/id_ed25519.pub", "Tidak bisa membaca ~/.ssh/id_ed25519.pub"))
        }
        let dir = NSTemporaryDirectory() + "amnesia-ssh-" + UUID().uuidString
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(atPath: dir) }
        let pwFile = dir + "/pw", ask = dir + "/askpass"
        fm.createFile(atPath: pwFile, contents: Data(password.utf8), attributes: [.posixPermissions: 0o600])
        fm.createFile(atPath: ask, contents: Data("#!/bin/sh\ncat \(shq(pwFile))\n".utf8), attributes: [.posixPermissions: 0o700])
        // kunci publik lewat stdin; dipasang hanya kalau belum ada
        let install = "umask 077; mkdir -p ~/.ssh && k=$(cat) && touch ~/.ssh/authorized_keys && "
            + "{ grep -qxF \"$k\" ~/.ssh/authorized_keys || printf '%s\\n' \"$k\" >> ~/.ssh/authorized_keys; }"
        let r = sh("/usr/bin/ssh", base + ["-o", "NumberOfPasswordPrompts=1", "-o", "PubkeyAuthentication=no",
                                           "-o", "PreferredAuthentications=keyboard-interactive,password", host, install],
                   input: pub, timeout: 60, env: ["SSH_ASKPASS": ask, "SSH_ASKPASS_REQUIRE": "force", "DISPLAY": ":0"])
        guard r.code == 0 else {
            return (false, r.err.contains("Permission denied")
                    ? T("Wrong password, or this server doesn't allow password logins.",
                        "Password salah, atau server ini tidak mengizinkan login pakai password.")
                    : String(r.err.suffix(300)))
        }
        w = whereIs()
        guard w.code == 0 else {
            return (false, T("The key is installed, but logging in with it failed: ", "Kunci sudah dipasang, tapi login pakai kunci gagal: ")
                    + String(w.err.suffix(200)))
        }
    }
    if !keepMatches(".ssh/id_ed25519", Keep.entries()) { Keep.add([".ssh"]) }   // kunci tidak ikut terhapus saat logout
    let path = w.out.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n").last ?? rpath
    return (true, T("Connected to \(host), no password needed from now on.\n\nBackups go to this folder on the server:\n\(path)",
                    "Terhubung ke \(host), mulai sekarang tanpa password.\n\nBackup masuk ke folder ini di server:\n\(path)"))
}

/// Jalankan backup.sh; password lewat stdin. Hasil: (berhasil, pesan).
func runBackup(_ pw: String, auto: Bool = false) -> (ok: Bool, msg: String) {
    let r = sh("/bin/bash", [P.backupSh] + (auto ? ["--auto"] : []), input: pw + "\n")
    let msg = (r.code == 0 ? r.out : r.err).trimmingCharacters(in: .whitespacesAndNewlines)
    return (r.code == 0, msg.isEmpty ? T("backup.sh exited with code \(r.code)", "backup.sh keluar dengan kode \(r.code)") : msg)
}

/// Buang awalan "FAILED: " / "GAGAL: " dari pesan script.
func stripFail(_ s: String) -> String {
    s.replacingOccurrences(of: "FAILED: ", with: "").replacingOccurrences(of: "GAGAL: ", with: "")
}

func lastBackupStatus() -> String {
    (try? String(contentsOfFile: P.backupLog, encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

/// Umur file dalam detik (tak hingga kalau belum ada).
func fileAge(_ path: String) -> Double {
    guard let d = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    else { return .infinity }
    return Date().timeIntervalSince(d)
}

/// Kutip aman untuk shell: 'abc' -> 'abc', it's -> 'it'\''s'
func shq(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

// MARK: - Dialog

@MainActor
func confirm(_ title: String, _ text: String, ok: String = T("Continue", "Lanjut"), danger: Bool = false) -> Bool {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = text
    a.alertStyle = danger ? .critical : .informational
    a.addButton(withTitle: ok)
    a.addButton(withTitle: T("Cancel", "Batal"))
    if danger { a.buttons.first?.hasDestructiveAction = true }
    NSApp.activate(ignoringOtherApps: true)
    return a.runModal() == .alertFirstButtonReturn
}

@MainActor
func info(_ title: String, _ text: String, error: Bool = false) {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = text
    a.alertStyle = error ? .warning : .informational
    a.addButton(withTitle: "OK")
    NSApp.activate(ignoringOtherApps: true)
    a.runModal()
}

// MARK: - Status & aksi

enum AState {
    case active, paused, off

    var title: String {
        switch self {
        case .active: return T("Amnesia is On", "Amnesia Aktif")
        case .paused: return T("Paused for 1 Session", "Dijeda 1 Sesi")
        case .off: return T("Amnesia is Off", "Amnesia Mati")
        }
    }

    var subtitle: String {
        switch self {
        case .active: return T("Everything is wiped at logout, restart & shutdown, then checked again at login.",
                               "Semua dibersihkan saat logout, restart & shutdown, lalu dicek ulang saat login.")
        case .paused: return T("The next logout & login are not wiped. It turns back on by itself afterwards.",
                               "Logout & login berikutnya tidak dibersihkan. Sesudahnya aktif lagi otomatis.")
        case .off: return T("Nothing is wiped. Turn it on to protect this Mac.",
                            "Data TIDAK dibersihkan. Aktifkan untuk melindungi Mac ini.")
        }
    }

    var icon: String {
        switch self {
        case .active: return "checkmark.shield.fill"
        case .paused: return "pause.circle.fill"
        case .off: return "xmark.shield.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .active: return [Color(hex: 0x34D399), Color(hex: 0x0EA5E9)]
        case .paused: return [Color(hex: 0xFBBF24), Color(hex: 0xF97316)]
        case .off: return [Color(hex: 0xFB7185), Color(hex: 0xDB2777)]
        }
    }
}

@MainActor
final class Model: ObservableObject {
    static let shared = Model()
    @Published var page: Page = .home
    @Published var onboarded = Config.get("ONBOARDED") == "1"
    @Published var lang = Lang.current {
        didSet {
            Lang.current = lang
            Config.set("LANG", lang.rawValue)
            refresh()
            refreshVault()
        }
    }
    @Published var pending: QuitAction?     // logout/restart/shutdown yang sedang ditahan
    var allowQuit = false
    @Published var state: AState = .off
    @Published var lastClean = ""
    @Published var vault: VaultReply?
    @Published var busy: String?
    /// Laporan "yang akan dihapus": disiapkan di background, jadi halaman Preview langsung tampil.
    @Published var report: [DryGroup]?
    @Published var reportTime: Date?
    @Published var reportBusy = false
    private var reportTimer: Timer?
    private var timer: Timer?
    private var backupTimer: Timer?
    private var backupRunning = false

    init() {
        Engine.install()
        if let c = cachedReport() { report = c.groups; reportTime = c.time }
        if Shots.on { state = .active; refreshVault(); return }    // mode screenshot: tanpa timer & backup
        Agent.migrate()
        refresh()
        refreshVault()
        // laporan: 20 detik setelah app jalan, lalu tiap 30 menit
        reportTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateReport() }
        }
        Task {
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            self.updateReport()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // cek jadwal backup: 2 menit setelah app jalan, lalu tiap 10 menit
        backupTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.autoBackup() }
        }
        Task {
            try? await Task.sleep(nanoseconds: 120_000_000_000)
            self.autoBackup()
        }
    }

    /// Backup terjadwal. Diam saja kalau belum waktunya, drive tidak tercolok, atau password tidak disimpan.
    func autoBackup() {
        let days: Double
        switch Config.get("BACKUP_SCHEDULE") {
        case "daily": days = 1
        case "weekly": days = 7
        default: return
        }
        guard !backupRunning, busy == nil,
              fileAge(P.backupOk) > days * 86_400 - 600,
              fileAge(P.backupLog) > 3_600          // baru saja gagal: coba lagi 1 jam kemudian
        else { return }
        if Config.get("BACKUP_DEST", "drive") == "drive" {
            let d = Config.get("BACKUP_DRIVE")
            guard !d.isEmpty, FileManager.default.fileExists(atPath: "/Volumes/" + d) else { return }
        }
        guard Secret.exists else { return }
        backupRunning = true
        quiet({ () -> Bool in
            guard let pw = Secret.get() else { return false }
            _ = runBackup(pw, auto: true)
            return true
        }) { _ in self.backupRunning = false }
    }

    func updateReport() {
        guard !reportBusy else { return }
        reportBusy = true
        quiet({ dryRun() }) { g in
            self.report = g
            self.reportTime = Date()
            self.reportBusy = false
        }
    }

    func refresh() {
        if Shots.on { return }
        let fm = FileManager.default
        let on = fm.fileExists(atPath: P.plist)
            && sh(P.launchctl, ["print", "\(P.domain)/\(P.label)"]).code == 0
        let s: AState = !on ? .off : (fm.fileExists(atPath: P.pause) ? .paused : .active)
        if s != state { state = s }
        let log = (try? String(contentsOfFile: P.cleanLog, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lc = log.isEmpty ? T("Never wiped yet", "Belum pernah dibersihkan") : T("Last: ", "Terakhir: ") + log
        if lc != lastClean { lastClean = lc }
    }

    func refreshVault() {
        DispatchQueue.global().async {
            let r = vaultCall(["status"])
            Task { @MainActor in self.vault = r }
        }
    }

    func finishOnboarding() {
        Config.set("ONBOARDED", "1")
        onboarded = true
        page = vault?.exists == true ? .home : .vault
    }

    func showTour() {
        page = .home
        onboarded = false
    }

    /// Kerja di background tanpa overlay.
    func quiet<R>(_ work: @escaping @Sendable () -> R, done: @escaping @MainActor (R) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let r = work()
            Task { @MainActor in done(r) }
        }
    }

    /// Lanjutkan logout/restart/shutdown yang tadi ditahan.
    func continueQuit() {
        guard let a = pending else { return }
        pending = nil
        page = .home
        allowQuit = true
        Task {
            try? await Task.sleep(nanoseconds: 120_000_000_000)
            self.allowQuit = false          // kalau ternyata dibatalkan app lain, tahan lagi lain kali
        }
        sh("/usr/bin/osascript", ["-e", "tell application \"loginwindow\" to «event \(a.event)»"])
    }

    /// Kerja berat di background; tampilkan overlay "busy" selama berjalan.
    func background<R>(_ msg: String, _ work: @escaping @Sendable () -> R,
                       done: @escaping @MainActor (R) -> Void) {
        busy = msg
        DispatchQueue.global(qos: .userInitiated).async {
            let r = work()
            Task { @MainActor in
                self.busy = nil
                done(r)
            }
        }
    }

    func vaultError(_ r: VaultReply) {
        let e = r.error ?? T("Something went wrong.", "Terjadi kesalahan.")
        if e == "DOOMSDAY" {
            info(T("Vault destroyed", "Vault dimusnahkan"),
                 T("The vault was destroyed to protect your data.", "Vault telah dimusnahkan untuk melindungi data."),
                 error: true)
        } else {
            info("Profile Vault", e, error: true)
        }
    }

    // --- aktif / mati ---

    func togglePower() {
        if state != .off {
            guard confirm(T("Turn off Amnesia?", "Matikan Amnesia?"),
                          T("Nothing will be wiped at logout until you turn it on again.",
                            "Data tidak akan dibersihkan saat logout sampai kamu aktifkan lagi."),
                          ok: T("Turn Off", "Matikan"), danger: true) else { return }
            deactivate()
        } else {
            guard Config.get("TERMS") == "1" else {
                info(T("Read this first", "Baca ini dulu"),
                     T("Before turning Amnesia on, please read the warning in the welcome tour and tick that you understand.",
                       "Sebelum mengaktifkan Amnesia, baca dulu peringatan di tur perkenalan dan centang bahwa kamu paham."))
                showTour()
                return
            }
            guard confirm(T("Turn on Amnesia?", "Aktifkan Amnesia?"),
                          T("From the next logout on, everything outside the Keep List and your Keep folder (\(KeepDir.shown)) will be "
                            + "DELETED at logout/restart/shutdown, then checked again at login.\n\n"
                            + "Move important files to \(KeepDir.shown) first. This session is safe until you log out.",
                            "Mulai logout berikutnya, semua data di luar Keep List dan folder Keep (\(KeepDir.shown)) akan DIHAPUS "
                            + "saat logout/restart/shutdown, lalu dicek ulang saat login.\n\n"
                            + "Pindahkan file penting ke \(KeepDir.shown) dulu. Sesi sekarang aman sampai kamu logout."),
                          ok: T("Turn On", "Aktifkan"), danger: true) else { return }
            if let err = activate() {
                info(T("Could not turn on", "Gagal mengaktifkan"), err, error: true)
            } else {
                info(T("Amnesia is ON", "Amnesia AKTIF"),
                     T("This session will be wiped at logout/restart/shutdown, then checked again at login.\n"
                       + "Your Keep folder (\(KeepDir.shown)) stays safe.",
                       "Sesi ini dibersihkan saat logout/restart/shutdown, lalu dicek ulang saat login.\n"
                       + "Folder Keep (\(KeepDir.shown)) tetap aman."))
            }
        }
        refresh()
    }

    private func activate() -> String? {
        let fm = FileManager.default
        // Plist dihapus DULU: agent yang masih jalan melihatnya dan tidak membersihkan saat dihentikan.
        try? fm.removeItem(atPath: P.plist)
        sh(P.launchctl, ["bootout", "\(P.domain)/\(P.label)"])
        sh(P.launchctl, ["bootout", "\(P.domain)/\(P.oldLabel)"])
        try? fm.removeItem(atPath: P.oldPlist)
        if let e = Agent.writePlist() {
            return T("Could not write the LaunchAgent: ", "Tidak bisa menulis LaunchAgent: ") + e
        }
        fm.createFile(atPath: P.a + "/.just_activated", contents: nil)   // jangan hapus sesi yang sedang dipakai
        if sh(P.launchctl, ["bootstrap", P.domain, P.plist]).code != 0 {
            sh(P.launchctl, ["load", P.plist])
        }
        return nil
    }

    private func deactivate() {
        let fm = FileManager.default
        try? fm.removeItem(atPath: P.plist)
        sh(P.launchctl, ["bootout", "\(P.domain)/\(P.label)"])
        try? fm.removeItem(atPath: P.pause)
    }

    // --- jeda ---

    func togglePause() {
        let fm = FileManager.default
        if fm.fileExists(atPath: P.pause) {
            try? fm.removeItem(atPath: P.pause)
        } else {
            fm.createFile(atPath: P.pause, contents: nil)
            info(T("Paused for 1 session", "Dijeda 1 sesi"),
                 T("The next logout and login will NOT be wiped.\nThe logout after that is wiped again as usual.",
                   "Logout dan login berikutnya TIDAK dibersihkan.\nLogout sesudahnya otomatis dibersihkan lagi."))
        }
        refresh()
    }

    // --- simpan profil & logout ---

    func saveAndLogout() {
        guard let v = vault, v.ok, v.exists == true else {
            info(T("Profile Vault not set up yet", "Profile Vault belum dibuat"),
                 T("Create a vault first in Profile Vault.", "Buat vault dulu di menu Profile Vault."))
            return
        }
        let apps = v.apps ?? []
        guard !apps.isEmpty else {
            info(T("Save & Log Out", "Simpan & Logout"),
                 T("There is no app data to save on this Mac yet.", "Belum ada data app yang bisa disimpan di Mac ini."))
            return
        }
        guard confirm(T("Save Profiles & Log Out", "Simpan Profil & Logout"),
                      T("Save \(apps.joined(separator: ", ")) to the vault, then log out?\n\nThese apps will be closed first.",
                        "Simpan profil \(apps.joined(separator: ", ")) ke vault, lalu logout?\n\nApp tersebut akan ditutup dulu."),
                      ok: T("Save & Log Out", "Simpan & Logout")) else { return }
        background(T("Saving profiles to the vault…", "Menyimpan profil ke vault…"), { vaultCall(["snapshot"]) }) { r in
            if r.ok {
                self.allowQuit = true       // logout ini dari kita sendiri: jangan ditahan
                _ = vaultCall(["logout"])
            } else {
                info(T("Snapshot failed", "Snapshot gagal"),
                     (r.error ?? "") + T("\n\nLogout was cancelled so your profiles are not lost.",
                                         "\n\nLogout dibatalkan supaya profil tidak hilang."), error: true)
                self.refreshVault()
            }
        }
    }
}

// MARK: - Gaya

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

enum Pal {
    static let vault = [Color(hex: 0xA78BFA), Color(hex: 0x6366F1)]
    static let logout = [Color(hex: 0x38BDF8), Color(hex: 0x2563EB)]
    static let pause = [Color(hex: 0xFBBF24), Color(hex: 0xF97316)]
    static let keep = [Color(hex: 0x34D399), Color(hex: 0x14B8A6)]
    static let backup = [Color(hex: 0xF472B6), Color(hex: 0xE11D48)]
    static let on = [Color(hex: 0x4ADE80), Color(hex: 0x16A34A)]
    static let danger = [Color(hex: 0xF87171), Color(hex: 0xDC2626)]
    static let gray = [Color(hex: 0x9CA3AF), Color(hex: 0x6B7280)]
}

struct Backdrop: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            Circle().fill(Color(hex: 0x22D3EE).opacity(0.35)).frame(width: 360, height: 360)
                .blur(radius: 90).offset(x: -170, y: -260)
            Circle().fill(Color(hex: 0xEC4899).opacity(0.28)).frame(width: 340, height: 340)
                .blur(radius: 90).offset(x: 180, y: 40)
            Circle().fill(Color(hex: 0x6366F1).opacity(0.30)).frame(width: 380, height: 380)
                .blur(radius: 100).offset(x: -120, y: 300)
        }
        .ignoresSafeArea()
    }
}

struct IconBadge: View {
    let icon: String
    let colors: [Color]
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: icon)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: (colors.last ?? .black).opacity(0.35), radius: 6, y: 3)
    }
}

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial))
    }
}

struct PillLabel<L: View>: View {
    let label: L
    let colors: [Color]
    let pressed: Bool
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)))
            .opacity(enabled ? (pressed ? 0.8 : 1) : 0.4)
            .scaleEffect(pressed ? 0.98 : 1)
            .contentShape(Rectangle())
    }
}

struct Pill: ButtonStyle {
    var colors: [Color]
    func makeBody(configuration: Configuration) -> some View {
        PillLabel(label: configuration.label, colors: colors, pressed: configuration.isPressed)
    }
}

struct Field: View {
    let label: String
    @Binding var text: String
    var secure = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Group {
                if secure { SecureField("", text: $text) } else { TextField("", text: $text) }
            }
            .textFieldStyle(.plain)
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.06)))
        }
    }
}

struct PageHeader: View {
    let title: String
    let icon: String
    let colors: [Color]
    let back: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.regularMaterial))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help(T("Back", "Kembali"))
            IconBadge(icon: icon, colors: colors, size: 36)
            Text(title).font(.system(size: 22, weight: .bold, design: .rounded))
            Spacer()
        }
    }
}

struct Note: View {
    let text: String
    var icon = "info.circle.fill"
    var color = Color.secondary

    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Halaman utama

struct HeroCard: View {
    let state: AState
    let lastClean: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.white.opacity(0.25)).frame(width: 64, height: 64)
                Image(systemName: state.icon).font(.system(size: 30, weight: .bold))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(state.title).font(.system(size: 22, weight: .bold, design: .rounded))
                Text(state.subtitle).font(.system(size: 12)).opacity(0.92)
                    .fixedSize(horizontal: false, vertical: true)
                Label(lastClean, systemImage: "clock.fill").font(.system(size: 11, weight: .medium))
                    .opacity(0.85).padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(colors: state.colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
        .shadow(color: (state.colors.last ?? .black).opacity(0.4), radius: 16, y: 8)
        .animation(.easeInOut(duration: 0.3), value: state)
    }
}

struct Tile: View {
    let title: String
    let sub: String
    let icon: String
    let colors: [Color]
    let action: () -> Void
    @State private var hover = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                IconBadge(icon: icon, colors: colors, size: 38)
                Spacer(minLength: 0)
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
                Text(sub).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(colors[0].opacity(hover ? 0.7 : 0.15), lineWidth: 1))
            .shadow(color: .black.opacity(hover ? 0.12 : 0.05), radius: hover ? 12 : 6, y: hover ? 6 : 3)
            .scaleEffect(hover && enabled ? 1.02 : 1)
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}

enum Page { case home, vault, keep, backup, settings, preview }

struct MainView: View {
    @EnvironmentObject var m: Model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
            Backdrop()
            Group {
                if !m.onboarded {
                    OnboardingView()
                } else {
                switch m.page {
                case .home: home
                case .settings: SettingsView(back: { goHome() })
                case .preview: PreviewView(back: { goHome() })
                case .vault: VaultView(back: { goHome() })
                case .keep: KeepView(back: { goHome() })
                case .backup: BackupView(back: { goHome() })
                }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 34)
            .padding(.bottom, 20)
            .transition(.opacity)
            if let b = m.busy {
                ZStack {
                    Color.black.opacity(0.25)
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large)
                        Text(b).font(.system(size: 13, weight: .semibold)).multilineTextAlignment(.center)
                    }
                    .padding(28)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.regularMaterial))
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .frame(width: 480, height: 690)
        .animation(.easeInOut(duration: 0.2), value: m.page)
        .animation(.easeInOut(duration: 0.2), value: m.onboarded)
        .onAppear {
            Opener.open = { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
            _ = NSApp.setActivationPolicy(.regular)   // jendela terbuka → muncul di Cmd-Tab & Dock
            NSApp.activate(ignoringOtherApps: true)
            m.refresh()
            m.refreshVault()
        }
        .onDisappear { _ = NSApp.setActivationPolicy(.accessory) }   // jendela ditutup → hanya ikon menu bar
    }

    private func goHome() { m.page = .home; m.refreshVault() }

    private var vaultSub: String {
        guard let v = m.vault else { return T("Loading…", "Memuat…") }
        if !v.ok { return T("Needs a check", "Perlu dicek") }
        if v.exists != true { return T("Not set up yet", "Belum dibuat") }
        if let man = v.manifest { return "Snapshot \(man.time)" }
        return T("Ready, no snapshot yet", "Siap, belum ada snapshot")
    }

    private var home: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Amnesia").font(.system(size: 26, weight: .heavy, design: .rounded))
                        Text("v\(appVersion)").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0x22D3EE), Color(hex: 0xEC4899)],
                                                                      startPoint: .leading, endPoint: .trailing)))
                    }
                    Text(T("Your Mac forgets everything, except what you choose.",
                           "Mac kamu lupa semuanya, kecuali yang kamu pilih."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button { m.page = .settings } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.regularMaterial))
                }
                .buttonStyle(.plain)
                .help(T("Settings", "Pengaturan"))
            }
            HeroCard(state: m.state, lastClean: m.lastClean)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                      spacing: 14) {
                Tile(title: "Profile Vault", sub: vaultSub, icon: "lock.rectangle.stack.fill",
                     colors: Pal.vault) { m.page = .vault }
                Tile(title: T("Save & Log Out", "Simpan & Logout"),
                     sub: T("Save your logins to the vault, then log out", "Simpan login ke vault, lalu logout"),
                     icon: "rectangle.portrait.and.arrow.right", colors: Pal.logout) { m.saveAndLogout() }
                Tile(title: m.state == .paused ? T("Cancel Pause", "Batalkan Jeda") : T("Pause 1 Session", "Jeda 1 Sesi"),
                     sub: m.state == .off ? T("Turn on Amnesia first", "Aktifkan Amnesia dulu")
                                          : T("Skip the next logout & login", "Lewati 1x logout & login berikutnya"),
                     icon: "pause.fill", colors: Pal.pause) { m.togglePause() }
                    .disabled(m.state == .off)
                Tile(title: "Keep List", sub: T("\(Keep.entries().count) items never wiped",
                                                "\(Keep.entries().count) item tidak dihapus"),
                     icon: "pin.fill", colors: Pal.keep) { m.page = .keep }
                Tile(title: "Backup", sub: T("To a USB drive, server or cloud", "Ke flashdisk, server atau cloud"),
                     icon: "externaldrive.fill", colors: Pal.backup) { m.page = .backup }
                Tile(title: m.state == .off ? T("Turn On", "Aktifkan") : T("Turn Off", "Matikan"),
                     sub: m.state == .off ? T("Start protecting this Mac", "Mulai lindungi Mac ini")
                                          : T("Stop automatic wiping", "Hentikan pembersihan otomatis"),
                     icon: "power", colors: m.state == .off ? Pal.on : Pal.danger) { m.togglePower() }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Profile Vault

struct VaultView: View {
    @EnvironmentObject var m: Model
    let back: () -> Void
    @State private var pw = ""
    @State private var pw2 = ""
    @State private var panic = ""
    @State private var panicFull = false
    @State private var showPanic = false
    @State private var newPanic = ""
    @State private var newPanicFull = false
    @State private var backupPw = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                PageHeader(title: "Profile Vault", icon: "lock.rectangle.stack.fill", colors: Pal.vault, back: back)
                if let v = m.vault {
                    if !v.ok {
                        Card { Note(text: v.error ?? T("Error", "Error"), icon: "exclamationmark.triangle.fill", color: .red) }
                    } else if v.exists != true {
                        setup(v)
                    } else {
                        opened(v)
                    }
                } else {
                    ProgressView().padding(40)
                }
            }
        }
        .scrollIndicators(.never)
        .onAppear { m.refreshVault() }
        .sheet(isPresented: $showPanic) { panicSheet }
    }

    @ViewBuilder
    private func setup(_ v: VaultReply) -> some View {
        Card {
            Text(T("Keep your logins (Chrome, Claude, WhatsApp, coding tools) in 1 encrypted safe. "
                   + "After the Mac is wiped, bring them all back with 1 password.",
                   "Simpan login (Chrome, Claude, WhatsApp, alat coding) dalam 1 brankas terenkripsi. "
                   + "Setelah Mac dibersihkan, pulihkan semuanya dengan 1 password."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Note(text: T("The password CANNOT be recovered if you forget it.", "Password TIDAK bisa dipulihkan kalau lupa."),
                 icon: "exclamationmark.triangle.fill",
                 color: .orange)
            Field(label: T("Vault password (min. \(v.min ?? 12) characters)",
                           "Password vault (min. \(v.min ?? 12) karakter)"), text: $pw)
            Field(label: T("Repeat password", "Ulangi password"), text: $pw2)
        }
        Card {
            Field(label: T("Panic word (optional)", "Kata panik (opsional)"), text: $panic)
            Note(text: T("Typing this word in the password box deletes the vault completely, right away.",
                         "Kalau kata ini diketik di kolom password, vault langsung dihapus total."))
            Toggle(T("The panic word also empties the Keep folder", "Kata panik juga mengosongkan folder Keep"), isOn: Binding(get: { panicFull && !panic.isEmpty }, set: { panicFull = $0 }))
                .font(.system(size: 12)).disabled(panic.isEmpty)
        }
        Button { create() } label: { Label(T("Create Vault", "Buat Vault"), systemImage: "lock.fill") }
            .buttonStyle(Pill(colors: Pal.vault))
            .disabled(pw.isEmpty)
        Card {
            HStack(spacing: 10) {
                IconBadge(icon: "arrow.left.arrow.right", colors: Pal.backup, size: 30)
                Text(T("Moving from an old Mac?", "Pindah dari Mac lama?")).font(.system(size: 14, weight: .semibold))
            }
            Text(T("Have an Amnesia backup that includes the Profile Vault? Take the vault from that file "
                   + "instead of creating a new one.",
                   "Punya file backup Amnesia yang berisi Profile Vault? Ambil vault-nya dari file itu, "
                   + "tidak perlu buat vault baru."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Field(label: T("Backup password", "Password backup"), text: $backupPw)
            Button { importVault() } label: {
                Label(T("Get Vault from Backup…", "Ambil Vault dari Backup…"), systemImage: "tray.and.arrow.down.fill")
            }
                .buttonStyle(Pill(colors: Pal.backup))
                .disabled(backupPw.isEmpty)
        }
    }

    @ViewBuilder
    private func opened(_ v: VaultReply) -> some View {
        let maxTry = v.max ?? 3
        let left = maxTry - (v.attempts ?? 0)
        Card {
            if let man = v.manifest {
                HStack {
                    Text(T("Last snapshot", "Snapshot terakhir")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(man.size_mb, specifier: "%.1f") MB").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text(man.time).font(.system(size: 17, weight: .bold, design: .rounded))
                HStack(spacing: 6) {
                    ForEach(man.apps, id: \.self) { a in
                        Text(a).font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Capsule().fill(Color.indigo.opacity(0.15)))
                    }
                }
            } else {
                Note(text: T("The vault is ready, no snapshot yet. Log in to your apps, then press Snapshot.",
                             "Vault siap, belum ada snapshot. Login ke app dulu, lalu tekan Snapshot."))
            }
        }
        if left < maxTry {
            Card {
                Note(text: T("\(left) tries left. Run out of tries = the vault is DELETED FOREVER.",
                             "Sisa \(left)x percobaan. Salah lagi sampai habis = vault DIHAPUS PERMANEN."),
                     icon: "exclamationmark.octagon.fill", color: .red)
            }
        }
        Card {
            Field(label: T("Vault password", "Password vault"), text: $pw).onSubmit { restore() }
            Button { restore() } label: {
                Label(T("Restore Profiles", "Restore Profil"), systemImage: "arrow.counterclockwise")
            }
                .buttonStyle(Pill(colors: Pal.keep))
                .disabled(pw.isEmpty)
        }
        HStack(spacing: 10) {
            Button { snapshot(v) } label: { Label("Snapshot", systemImage: "camera.fill") }
                .buttonStyle(Pill(colors: Pal.logout))
            Button { showPanic = true } label: { Label(T("Panic Word", "Kata Panik"), systemImage: "flame.fill") }
                .buttonStyle(Pill(colors: Pal.vault))
            Button { deleteVault() } label: { Label(T("Delete", "Hapus"), systemImage: "trash.fill") }
                .buttonStyle(Pill(colors: Pal.danger))
        }
        Card {
            HStack(spacing: 10) {
                IconBadge(icon: "arrow.left.arrow.right", colors: Pal.backup, size: 30)
                Text(T("Move to a New Mac", "Pindah Mac")).font(.system(size: 14, weight: .semibold))
            }
            Text(T("Chrome, Claude & WhatsApp logins are locked with this Mac's Keychain keys. To keep them working "
                   + "on a new Mac, save the keys to the vault, then back up with Include Profile Vault.",
                   "Login Chrome, Claude & WhatsApp dikunci oleh kunci Keychain milik Mac ini. Supaya tetap jalan "
                   + "di Mac baru, simpan kuncinya ke vault, lalu backup dengan Sertakan Profile Vault."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let k = v.keys {
                Note(text: T("Keys saved \(k.time): ", "Kunci tersimpan \(k.time): ") + k.apps.joined(separator: ", "),
                     icon: "checkmark.circle.fill", color: .green)
            }
            HStack(spacing: 10) {
                Button { exportKeys() } label: { Label(T("Prepare Move", "Siapkan Pindah Mac"), systemImage: "key.fill") }
                    .buttonStyle(Pill(colors: Pal.vault))
                Button { importKeys() } label: { Label(T("Restore Keys", "Pulihkan Kunci"), systemImage: "key.horizontal.fill") }
                    .buttonStyle(Pill(colors: Pal.keep))
                    .disabled(pw.isEmpty || v.keys == nil)
            }
            Note(text: T("Use Restore Keys only on the NEW Mac, after Restore Profiles. It uses the vault password above.",
                         "Pulihkan Kunci hanya di Mac BARU, setelah Restore Profil. Pakai password vault di atas."))
        }
    }

    private var panicSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(T("Set Panic Word", "Atur Kata Panik")).font(.system(size: 17, weight: .bold))
            Text(T("Typing this word in the vault password box deletes the vault and all snapshots right away. "
                   + "Leave it empty to turn the panic word off.",
                   "Kalau kata ini diketik di kolom password vault, vault dan semua snapshot langsung dihapus. "
                   + "Kosongkan untuk mematikan kata panik."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Field(label: T("Vault password", "Password vault"), text: $pw)
            Field(label: T("New panic word", "Kata panik baru"), text: $newPanic)
            Toggle(T("Also empty the Keep folder", "Juga kosongkan folder Keep"), isOn: $newPanicFull).font(.system(size: 12)).disabled(newPanic.isEmpty)
            HStack {
                Button(T("Cancel", "Batal")) { showPanic = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(T("Save", "Simpan")) { savePanic() }.keyboardShortcut(.defaultAction).disabled(pw.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    private func create() {
        guard pw == pw2 else { info("Profile Vault", T("The passwords do not match.", "Password tidak cocok."), error: true); return }
        let input = pw + "\n" + panic + "\n"
        let args = ["create"] + (panicFull && !panic.isEmpty ? ["full"] : [])
        m.background(T("Creating vault keys…", "Membuat kunci vault…"), { vaultCall(args, input: input) }) { r in
            if r.ok {
                pw = ""; pw2 = ""; panic = ""
                info(T("Vault created", "Vault dibuat"),
                     T("Log in to your apps as usual, then press Snapshot (or Save & Log Out).",
                       "Login ke app seperti biasa, lalu tekan Snapshot (atau Simpan & Logout)."))
            } else {
                m.vaultError(r)
            }
            m.refreshVault()
        }
    }

    private func restore() {
        guard !pw.isEmpty else { return }
        let input = pw + "\n"
        m.background(T("Restoring profiles…", "Memulihkan profil…"), { vaultCall(["restore"], input: input) }) { r in
            pw = ""
            if r.ok {
                info(T("Profiles restored", "Profil dipulihkan"),
                     (r.apps ?? []).joined(separator: ", ") + T(" are ready to use.", " siap dipakai."))
            } else {
                m.vaultError(r)
            }
            m.refreshVault()
        }
    }

    private func snapshot(_ v: VaultReply) {
        let apps = v.apps ?? []
        guard !apps.isEmpty else {
            info("Profile Vault", T("There is no app data to save on this Mac yet.",
                                    "Belum ada data app yang bisa disimpan di Mac ini."))
            return
        }
        guard confirm("Snapshot", T("Save \(apps.joined(separator: ", "))?\n\nThese apps will be closed first.",
                                    "Simpan profil \(apps.joined(separator: ", "))?\n\nApp tersebut akan ditutup dulu."),
                      ok: T("Save", "Simpan")) else { return }
        m.background(T("Saving profiles to the vault…", "Menyimpan profil ke vault…"), { vaultCall(["snapshot"]) }) { r in
            if !r.ok { m.vaultError(r) }
            m.refreshVault()
        }
    }

    private func savePanic() {
        let input = pw + "\n" + newPanic + "\n"
        let args = ["panic"] + (newPanicFull && !newPanic.isEmpty ? ["full"] : [])
        let word = newPanic
        showPanic = false
        m.background(T("Checking password…", "Memeriksa password…"), { vaultCall(args, input: input) }) { r in
            pw = ""; newPanic = ""
            if r.ok {
                info(T("Panic Word", "Kata Panik"), word.isEmpty ? T("Panic word turned off.", "Kata panik dimatikan.")
                                                                  : T("Panic word saved.", "Kata panik disimpan."))
            } else {
                m.vaultError(r)
            }
            m.refreshVault()
        }
    }

    private func exportKeys() {
        guard confirm(T("Prepare Move", "Siapkan Pindah Mac"),
                      T("The Keychain keys (Chrome, Claude, WhatsApp, etc.) are saved, encrypted, to the vault.\n\n"
                        + "macOS will ask a few times. Type your Mac login password, then click Always Allow.",
                        "Kunci Keychain (Chrome, Claude, WhatsApp, dll.) disimpan terenkripsi ke vault.\n\n"
                        + "macOS akan bertanya beberapa kali. Ketik password login Mac lalu klik Always Allow / "
                        + "Selalu Izinkan."), ok: T("Start", "Mulai")) else { return }
        m.background(T("Saving Keychain keys to the vault…\nAnswer the macOS permission dialogs.",
                       "Menyimpan kunci Keychain ke vault…\nJawab dialog izin dari macOS."),
                     { vaultCall(["exportkeys"]) }) { r in
            if r.ok {
                let apps = (r.apps ?? []).joined(separator: ", ")
                info(T("Ready to move", "Siap pindah Mac"),
                     T("Keys saved: \(apps).\n\nNow make a backup with Include Profile Vault checked.",
                       "Kunci tersimpan: \(apps).\n\nSekarang buat backup dengan Sertakan Profile Vault dicentang."))
            } else {
                m.vaultError(r)
            }
            m.refreshVault()
        }
    }

    private func importKeys() {
        guard confirm(T("Restore Keys?", "Pulihkan Kunci?"),
                      T("The Keychain keys for Chrome, Claude, etc. on this Mac are REPLACED with the keys from the old "
                        + "Mac. Only do this on the new Mac, after Restore Profiles.\n\nThose apps will be closed first.",
                        "Kunci Keychain Chrome, Claude, dll. di Mac ini DIGANTI dengan kunci dari Mac lama. "
                        + "Lakukan hanya di Mac baru, setelah Restore Profil.\n\nApp terkait akan ditutup dulu."),
                      ok: T("Restore", "Pulihkan"), danger: true) else { return }
        let input = pw + "\n"
        m.background(T("Putting keys into the Keychain…", "Memasang kunci ke Keychain…"),
                     { vaultCall(["importkeys"], input: input) }) { r in
            pw = ""
            if r.ok {
                info(T("Keys restored", "Kunci dipulihkan"), (r.apps ?? []).joined(separator: ", ")
                     + T(" will open with your old logins.", " siap dibuka dengan login lama."))
            } else {
                m.vaultError(r)
            }
            m.refreshVault()
        }
    }

    private func importVault() {
        let panel = NSOpenPanel()
        panel.title = T("Choose an Amnesia backup file (.7z)", "Pilih file backup Amnesia (.7z)")
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let file = panel.url?.path else { return }
        let input = backupPw + "\n"
        m.background(T("Taking the vault from the backup…", "Mengambil vault dari backup…"), {
            sh("/bin/bash", [P.backupSh, "--restore-vault", file], input: input)
        }) { r in
            backupPw = ""
            if r.code == 0 {
                info(T("Vault restored", "Vault dipulihkan"),
                     T("Next steps:\n1. Restore Profiles (vault password).\n2. Restore Keys (vault password).",
                       "Langkah berikutnya:\n1. Restore Profil (password vault).\n2. Pulihkan Kunci (password vault)."))
            } else {
                info(T("Failed", "Gagal"), stripFail(r.err), error: true)
            }
            m.refreshVault()
        }
    }

    private func deleteVault() {
        guard confirm(T("Delete Vault?", "Hapus Vault?"),
                      T("The vault and all profile snapshots are deleted.\n\nThis cannot be undone.",
                        "Vault dan semua snapshot profil dihapus.\n\nTidak bisa dibatalkan."),
                      ok: T("Delete", "Hapus"), danger: true) else { return }
        m.background(T("Deleting the vault…", "Menghapus vault…"), { vaultCall(["delete"]) }) { r in
            if !r.ok { m.vaultError(r) }
            m.refreshVault()
        }
    }
}

// MARK: - Keep List

struct KeepView: View {
    @EnvironmentObject var m: Model
    let back: () -> Void
    @State private var entries: [String] = []
    @State private var adding = false
    @State private var addingApps = false

    var body: some View {
        VStack(spacing: 14) {
            PageHeader(title: "Keep List", icon: "pin.fill", colors: Pal.keep, back: back)
            Note(text: T("Everything here is NOT wiped at logout. Your Keep folder and ~/.amnesia are always safe.",
                         "Yang ada di sini TIDAK dihapus saat logout. Folder Keep kamu dan ~/.amnesia selalu aman."))
                .frame(maxWidth: .infinity, alignment: .leading)
            KeepFolderCard()
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(entries, id: \.self) { e in row(e) }
                }
            }
            .scrollIndicators(.never)
            HStack(spacing: 10) {
                Button { addingApps = true } label: { Label(T("Pick Apps", "Pilih App"), systemImage: "square.grid.2x2.fill") }
                    .buttonStyle(Pill(colors: Pal.vault))
                Button { adding = true } label: { Label(T("Add Folder", "Tambah Folder"), systemImage: "plus") }
                    .buttonStyle(Pill(colors: Pal.keep))
            }
        }
        .sheet(isPresented: $addingApps) { AppPickerSheet { entries = Keep.entries() } }
        .onAppear { entries = Keep.entries() }
        .sheet(isPresented: $adding) {
            KeepAddSheet { picked in
                Keep.add(picked)
                entries = Keep.entries()
            }
        }
    }

    private func row(_ e: String) -> some View {
        let isKey = e.hasPrefix("keychain:")
        let shown = isKey ? T("Key: ", "Kunci: ") + String(e.dropFirst(9)) : "~/" + e
        return HStack(spacing: 10) {
            Image(systemName: isKey ? "key.fill" : "folder.fill")
                .foregroundStyle(isKey ? Color.orange : Color.teal)
            Text(shown)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            Button { remove(e) } label: {
                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help(T("Remove from Keep List", "Hapus dari Keep List"))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.regularMaterial))
    }

    private func remove(_ e: String) {
        guard confirm(T("Remove from Keep List?", "Hapus dari Keep List?"),
                      e + T("\n\nIts data will be wiped at the next logout.", "\n\nDatanya akan ikut dibersihkan saat logout berikutnya."),
                      ok: T("Remove", "Hapus"), danger: true) else { return }
        Keep.remove(e)
        entries = Keep.entries()
    }
}

struct KeepAddSheet: View {
    let onAdd: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var cands: [String] = []
    @State private var picked = Set<String>()
    @State private var query = ""

    private var filtered: [String] {
        query.isEmpty ? cands : cands.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(T("Add to Keep List", "Tambah ke Keep List")).font(.system(size: 17, weight: .bold))
            TextField(T("Search…", "Cari…"), text: $query).textFieldStyle(.roundedBorder)
            if cands.isEmpty {
                Text(T("There are no other folders to add.", "Tidak ada folder lain yang bisa ditambahkan.")).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                List(filtered, id: \.self) { c in
                    Toggle(c, isOn: Binding(get: { picked.contains(c) },
                                            set: { on in if on { picked.insert(c) } else { picked.remove(c) } }))
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                }
                .frame(height: 300)
            }
            HStack {
                Button(T("Cancel", "Batal")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(T("Add (\(picked.count))", "Tambah (\(picked.count))")) {
                    onAdd(picked.sorted())
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(picked.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { cands = Keep.candidates() }
    }
}

// MARK: - Folder Keep (lokasi & nama bebas)

/// Pilih folder Keep baru lewat Finder. Isi folder lama boleh ikut dipindah.
@MainActor
func chooseKeepDir() -> Bool {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = T("Use as Keep folder", "Pakai jadi folder Keep")
    panel.message = T("Pick (or create) the folder that should never be wiped. Any place, any name.",
                      "Pilih (atau buat) folder yang tidak pernah dihapus. Di mana saja, nama apa saja.")
    panel.directoryURL = URL(fileURLWithPath: (KeepDir.path as NSString).deletingLastPathComponent)
    NSApp.activate(ignoringOtherApps: true)
    guard panel.runModal() == .OK, let url = panel.url else { return false }
    let new = url.standardizedFileURL.path
    if new == KeepDir.path { return false }
    if let err = KeepDir.problem(new) { info(T("Keep folder", "Folder Keep"), err, error: true); return false }
    let oldFiles = ((try? FileManager.default.contentsOfDirectory(atPath: KeepDir.path)) ?? []).filter { $0 != ".DS_Store" }
    var move = false
    if !oldFiles.isEmpty {
        move = confirm(T("Move your files too?", "Pindahkan file kamu juga?"),
                       T("\(KeepDir.shown) has \(oldFiles.count) items. Move them to the new folder?\n\n"
                         + "If you don't, they stay where they are.",
                         "\(KeepDir.shown) berisi \(oldFiles.count) item. Pindahkan ke folder baru?\n\n"
                         + "Kalau tidak, file tetap di tempat lama."),
                       ok: T("Move", "Pindahkan"))
    }
    KeepDir.set(new, moveFiles: move)
    return true
}

struct KeepFolderCard: View {
    @State private var shown = KeepDir.shown

    var body: some View {
        Card {
            HStack(spacing: 12) {
                IconBadge(icon: "tray.full.fill", colors: Pal.keep, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(T("Keep folder", "Folder Keep")).font(.system(size: 14, weight: .semibold))
                    Text(shown).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Button { NSWorkspace.shared.open(URL(fileURLWithPath: KeepDir.path)) } label: { Image(systemName: "folder") }
                    .help(T("Show in Finder", "Buka di Finder"))
                Button(T("Change…", "Ganti…")) { if chooseKeepDir() { shown = KeepDir.shown } }
            }
            Text(T("Files in here are never wiped. Put it anywhere and call it anything, even on an external drive.",
                   "File di sini tidak pernah dihapus. Taruh di mana saja dan beri nama apa saja, bahkan di drive eksternal."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { shown = KeepDir.shown }
    }
}

// MARK: - Pilih app yang di-keep

struct AppPickList: View {
    let apps: [FoundApp]
    @Binding var picked: Set<String>
    @State private var sizes: [String: String] = [:]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(apps) { a in row(a) }
            }
        }
        .scrollIndicators(.never)
    }

    private func subtitle(_ a: FoundApp, _ on: Bool) -> String {
        switch (a.inVault, on) {
        case (true, true): return T("Kept whole, not encrypted", "Disimpan utuh, tidak dienkripsi")
        case (true, false): return T("Logins go in the Profile Vault (encrypted)", "Login masuk Profile Vault (terenkripsi)")
        case (false, true): return T("Kept: data & settings stay", "Disimpan: data & setting tetap ada")
        default: return T("Wiped at logout", "Dihapus saat logout")
        }
    }

    private func row(_ a: FoundApp) -> some View {
        let on = picked.contains(a.name)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(nsImage: a.icon).resizable().frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(a.name).font(.system(size: 13, weight: .semibold))
                        if a.inVault {
                            Image(systemName: "lock.rectangle.stack.fill").font(.system(size: 10)).foregroundStyle(.indigo)
                                .help(T("The Profile Vault can save this app's logins", "Profile Vault bisa menyimpan login app ini"))
                        }
                    }
                    Text(subtitle(a, on)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { on }, set: { v in
                    withAnimation(.easeInOut(duration: 0.15)) { if v { _ = picked.insert(a.name) } else { _ = picked.remove(a.name) } }
                }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
            if on { details(a) }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
    }

    /// Apa saja yang disimpan dari app ini: jenis data, lokasinya, dan ukurannya.
    private func details(_ a: FoundApp) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(a.paths, id: \.self) { p in
                let k = pathKind(p)
                HStack(spacing: 8) {
                    Image(systemName: k.icon).font(.system(size: 10)).foregroundStyle(.teal).frame(width: 14)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(k.label).font(.system(size: 11, weight: .semibold))
                        Text("~/" + p).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 6)
                    Text(sizes[p] ?? "…").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
                .onAppear {
                    guard sizes[p] == nil else { return }
                    DispatchQueue.global(qos: .utility).async {
                        let s = folderSize(p)
                        Task { @MainActor in sizes[p] = s }
                    }
                }
            }
            if a.inVault {
                Note(text: T("You don't need the vault for this app now: its data simply stays.",
                             "App ini tidak perlu vault lagi: datanya langsung tetap ada."),
                     icon: "info.circle.fill", color: .secondary)
            }
        }
        .padding(.leading, 40)
        .padding(.trailing, 4)
        .transition(.opacity)
    }
}

struct AppPickerSheet: View {
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var apps: [FoundApp]?
    @State private var picked = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(T("Pick apps to keep", "Pilih app yang disimpan")).font(.system(size: 17, weight: .bold))
            Text(T("Apps you switch on keep their data and settings. Everything else gets wiped at logout.",
                   "App yang dinyalakan tetap menyimpan data & settingnya. Sisanya dihapus saat logout."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let a = apps {
                AppPickList(apps: a, picked: $picked).frame(height: 400)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 400)
            }
            HStack {
                Button(T("Cancel", "Batal")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(T("Save", "Simpan")) {
                    if let a = apps { applyPicks(a, picked) }
                    onDone()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(apps == nil)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            let a = scanApps()
            apps = a
            picked = defaultPicks(a)
        }
    }
}

// MARK: - Atur Keep List (langsung setelah tur)

struct KeepSetupView: View {
    @EnvironmentObject var m: Model
    let back: () -> Void
    @State private var apps: [FoundApp]?
    @State private var picked = Set<String>()

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(T("What should stay?", "Apa yang tetap disimpan?")).font(.system(size: 26, weight: .heavy, design: .rounded))
                Text(T("These apps are on your Mac. Switch on the ones that should keep their data; we already "
                       + "switched on VPNs and password managers. Switch one on to see exactly what's kept.",
                       "Ini app yang ada di Mac kamu. Nyalakan yang datanya mau disimpan; VPN dan password manager "
                       + "sudah dinyalakan. Nyalakan satu untuk lihat apa saja yang disimpan."))
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            KeepFolderCard()
            if let a = apps {
                AppPickList(apps: a, picked: $picked)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 10) {
                Button { back() } label: { Text(T("Back", "Kembali")) }
                    .buttonStyle(Pill(colors: Pal.gray))
                Button {
                    if let a = apps { applyPicks(a, picked) }
                    m.finishOnboarding()
                } label: { Text(T("Save & Start", "Simpan & Mulai")) }
                .buttonStyle(Pill(colors: Pal.keep))
                .keyboardShortcut(.defaultAction)
                .disabled(apps == nil)
            }
            Text(T("You can change this anytime on the Keep List page.", "Bisa diubah kapan saja di halaman Keep List."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .onAppear {
            guard apps == nil else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let a = scanApps()
                let p = defaultPicks(a)
                Task { @MainActor in apps = a; picked = p }
            }
        }
    }
}

// MARK: - Tur perkenalan (pertama kali dibuka)

struct OnboardingView: View {
    @EnvironmentObject var m: Model
    @State private var step: Int
    @State private var keepSetup = false
    @State private var recheck = 0
    @State private var accepted = Config.get("TERMS") == "1"
    private let last = 6

    init(step: Int = 0, keepSetup: Bool = false) {
        _step = State(initialValue: step)
        _keepSetup = State(initialValue: keepSetup)
    }

    var body: some View {
        if keepSetup {
            KeepSetupView(back: { keepSetup = false })
        } else {
            tour
        }
    }

    private var tour: some View {
        VStack(spacing: 16) {
            Group {
                switch step {
                case 0: welcome
                case 1: terms
                case 2: features
                case 3: setup
                case 4: appsExample
                case 5: vaultPage
                default: routine
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.opacity)
            HStack(spacing: 6) {
                ForEach(0...last, id: \.self) { i in
                    Capsule().fill(i == step ? Color.indigo : Color.primary.opacity(0.15))
                        .frame(width: i == step ? 18 : 7, height: 7)
                }
            }
            HStack(spacing: 10) {
                if step > 0 {
                    Button { step -= 1 } label: { Text(T("Back", "Kembali")) }
                        .buttonStyle(Pill(colors: Pal.gray))
                }
                Button { next() } label: {
                    Text(step == last ? T("Pick my apps", "Pilih app saya") : T("Next", "Lanjut"))
                }
                .buttonStyle(Pill(colors: Pal.vault))
                .keyboardShortcut(.defaultAction)
                .disabled(step == 1 && !accepted)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    private func next() {
        if step == last { keepSetup = true } else { step += 1 }
    }

    private func title(_ t: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t).font(.system(size: 26, weight: .heavy, design: .rounded))
            Text(sub).font(.system(size: 13)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func item(_ icon: String, _ colors: [Color], _ t: String, _ sub: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(icon: icon, colors: colors, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(t).font(.system(size: 14, weight: .semibold))
                Text(sub).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // 1. Sambutan + bahasa
    private var welcome: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 104, height: 104)
            Text(T("Welcome to Amnesia", "Selamat datang di Amnesia"))
                .font(.system(size: 28, weight: .heavy, design: .rounded))
            Text(T("Your Mac forgets everything every time you log out, except the stuff you choose to keep. "
                   + "This quick tour sets it up with you. Nothing gets deleted until you say so.",
                   "Mac kamu lupa semuanya setiap logout, kecuali yang kamu pilih untuk disimpan. "
                   + "Tur singkat ini bantu kamu menyiapkannya. Tidak ada yang dihapus sampai kamu bilang iya."))
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Card {
                HStack {
                    Label(T("Language", "Bahasa"), systemImage: "globe").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Picker("", selection: $m.lang) {
                        ForEach(Lang.allCases, id: \.self) { l in Text(l.name).tag(l) }
                    }
                    .labelsHidden().frame(width: 170)
                }
            }
            PrivacyNote()
        }
    }

    // 2. Baca dulu (wajib dicentang)
    private var terms: some View {
        VStack(spacing: 14) {
            title(T("Read this first", "Baca ini dulu"),
                  T("Amnesia really deletes data. Please read before you continue.",
                    "Amnesia benar-benar menghapus data. Tolong baca sebelum lanjut."))
            Card {
                item("exclamationmark.triangle.fill", Pal.danger, T("It deletes for real", "Benar-benar menghapus"),
                     T("Once it's on, files outside the Keep folder and the Keep List are deleted at every logout, "
                       + "restart and shutdown. They don't go to the Trash and can't be undone.",
                       "Setelah aktif, file di luar folder Keep dan Keep List dihapus setiap logout, restart dan "
                       + "shutdown. Tidak masuk Trash dan tidak bisa dibatalkan."))
                item("key.fill", Pal.pause, T("Forget the password, lose the vault", "Lupa password, vault hilang"),
                     T("Nobody can open the Profile Vault without its password, including us.",
                       "Profile Vault tidak bisa dibuka tanpa password-nya, termasuk oleh kami."))
                item("checkmark.shield.fill", Pal.keep, T("Check before you turn it on", "Cek dulu sebelum mengaktifkan"),
                     T("Back up your files first and use \"What would be deleted\" to see the list.",
                       "Backup file kamu dulu dan pakai \"Lihat yang akan dihapus\" untuk melihat daftarnya."))
                item("doc.text.fill", Pal.gray, T("Free software, no warranty", "Software gratis, tanpa garansi"),
                     T("Amnesia is MIT licensed and comes as-is. You use it at your own risk.",
                       "Amnesia berlisensi MIT dan diberikan apa adanya. Risiko pemakaian ada di kamu."))
            }
            Toggle(T("I've read this and understand that Amnesia deletes data.",
                     "Saya sudah membaca dan paham bahwa Amnesia menghapus data."), isOn: Binding(get: { accepted }, set: { v in
                accepted = v
                Config.set("TERMS", v ? "1" : "0")
            }))
            .toggleStyle(.checkbox).font(.system(size: 12, weight: .semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { NSWorkspace.shared.open(URL(string: termsURL)!) } label: {
                Label(T("Read the full terms", "Baca ketentuan lengkap"), systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(.indigo)
        }
    }

    // 3. Cara kerja
    private var features: some View {
        VStack(spacing: 16) {
            title(T("How it works", "Cara kerjanya"), T("Four things to know.", "Cukup tahu 4 hal ini."))
            Card {
                item("sparkles", Pal.on, T("Wiped at logout", "Dihapus saat logout"),
                     T("Browser history, downloads, caches, app data: gone when you log out, restart or shut down.",
                       "Riwayat browser, download, cache, data app: hilang saat logout, restart, atau shutdown."))
                item("pin.fill", Pal.keep, T("Keep List & Keep folder", "Keep List & folder Keep"),
                     T("Apps and folders you pick stay. Files inside your Keep folder always stay.",
                       "App dan folder pilihanmu tetap ada. File di folder Keep kamu selalu aman."))
                item("lock.rectangle.stack.fill", Pal.vault, "Profile Vault",
                     T("Your logins go into an encrypted safe. One password brings them back.",
                       "Login kamu masuk ke brankas terenkripsi. 1 password untuk mengembalikan semuanya."))
                item("externaldrive.fill", Pal.backup, "Backup",
                     T("Encrypted copies to a USB drive, your server or the cloud.",
                       "Salinan terenkripsi ke flashdisk, server kamu, atau cloud."))
            }
        }
    }

    // 4. Cek kesiapan
    private var setup: some View {
        let _ = recheck
        return VStack(spacing: 14) {
            title(T("Quick check", "Cek dulu"), T("Amnesia needs these to run.", "Amnesia butuh ini supaya bisa jalan."))
            Card {
                status(Engine.ready, T("Amnesia engine", "Mesin Amnesia"),
                       T("The scripts that do the wiping.", "Script yang melakukan pembersihan."))
                status(Engine.sevenz != nil, "7-Zip",
                       T("Locks your vault and backups (AES-256).", "Mengunci vault dan backup (AES-256)."))
                status(Engine.hasPython, T("Apple Command Line Tools", "Apple Command Line Tools"),
                       T("Free tools from Apple. The Profile Vault needs them.", "Alat gratis dari Apple, dibutuhkan Profile Vault."))
                status(Engine.hasFullDisk, T("Full Disk Access", "Akses Disk Penuh"),
                       T("Allow once, and macOS stops asking about every folder.",
                         "Izinkan sekali, macOS tidak akan tanya lagi per folder."))
            }
            if !Engine.hasPython {
                Button { _ = sh("/usr/bin/xcode-select", ["--install"]) } label: {
                    Label(T("Install Command Line Tools", "Pasang Command Line Tools"), systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(Pill(colors: Pal.logout))
            }
            if !Engine.hasFullDisk {
                Button { Engine.openFullDiskSettings() } label: {
                    Label(T("Allow Full Disk Access", "Izinkan Akses Disk Penuh"), systemImage: "lock.open.fill")
                }
                .buttonStyle(Pill(colors: Pal.vault))
                Note(text: T("Switch on Amnesia in the list. Still red after that? Quit and reopen Amnesia.",
                             "Nyalakan Amnesia di daftar itu. Masih merah? Tutup lalu buka lagi Amnesia."))
            }
            if Engine.sevenz == nil {
                Note(text: T("7-Zip is missing. Run in Terminal: brew install sevenzip",
                             "7-Zip belum ada. Jalankan di Terminal: brew install sevenzip"),
                     icon: "exclamationmark.triangle.fill", color: .orange)
            }
            Button { recheck += 1 } label: { Label(T("Check again", "Cek lagi"), systemImage: "arrow.clockwise") }
                .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
        }
    }

    private func status(_ ok: Bool, _ t: String, _ sub: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 20)).foregroundStyle(ok ? .green : .red)
            VStack(alignment: .leading, spacing: 1) {
                Text(t).font(.system(size: 13, weight: .semibold))
                Text(sub).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    // 5. Contoh memilih app (yang asli muncul setelah tur)
    private var appsExample: some View {
        VStack(spacing: 14) {
            title(T("You choose what stays", "Kamu yang pilih apa yang tetap ada"),
                  T("Right after this tour, Amnesia lists the apps on your Mac. It looks like this:",
                    "Setelah tur ini, Amnesia menampilkan app yang ada di Mac kamu. Bentuknya seperti ini:"))
            VStack(spacing: 6) {
                exampleRow("shield.lefthalf.filled", Pal.logout, "My VPN", on: true,
                           T("Kept: data & settings stay", "Disimpan: data & setting tetap ada"),
                           [(T("App data", "Data app"), "~/Library/Application Support/MyVPN", "12 MB"),
                            (T("Settings", "Setting"), "~/Library/Preferences/com.myvpn*", "4 KB")])
                exampleRow("globe", Pal.vault, T("Web browser", "Browser"), on: false,
                           T("Logins go in the Profile Vault (encrypted)", "Login masuk Profile Vault (terenkripsi)"), [])
                exampleRow("gamecontroller.fill", Pal.backup, T("Some game", "Game"), on: false,
                           T("Wiped at logout", "Dihapus saat logout"), [])
            }
            .allowsHitTesting(false)
            Note(text: T("Switch an app on to see exactly what gets kept and how big it is. Also, you pick where "
                         + "your Keep folder lives and what it's called.",
                         "Nyalakan sebuah app untuk lihat apa saja yang disimpan dan seberapa besar. Kamu juga bisa "
                         + "pilih lokasi dan nama folder Keep."),
                 icon: "hand.point.up.left.fill", color: .secondary)
        }
    }

    private func exampleRow(_ icon: String, _ colors: [Color], _ name: String, on: Bool, _ sub: String,
                            _ detail: [(String, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                IconBadge(icon: icon, colors: colors, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.system(size: 13, weight: .semibold))
                    Text(sub).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: .constant(on)).toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
            ForEach(0..<detail.count, id: \.self) { i in
                let d = detail[i]
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill").font(.system(size: 10)).foregroundStyle(.teal).frame(width: 14)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(d.0).font(.system(size: 11, weight: .semibold))
                        Text(d.1).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(d.2).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
                .padding(.leading, 40)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
    }

    // 6. Profile Vault
    private var vaultPage: some View {
        VStack(spacing: 16) {
            title("Profile Vault", T("So you don't have to log in again every day.",
                                     "Supaya kamu tidak perlu login ulang setiap hari."))
            Card {
                item("1.circle.fill", Pal.vault, T("Create a vault", "Buat vault"),
                     T("Pick a strong password. It can't be recovered, so write it down somewhere safe.",
                       "Pilih password yang kuat. Tidak bisa dipulihkan, jadi catat di tempat aman."))
                item("2.circle.fill", Pal.logout, T("Log in to your apps", "Login ke app kamu"),
                     T("Chrome, WhatsApp, Claude, your coding tools… just like normal.",
                       "Chrome, WhatsApp, Claude, alat coding… seperti biasa."))
                item("3.circle.fill", Pal.keep, T("Press Snapshot", "Tekan Snapshot"),
                     T("Your logins are now locked in the vault.", "Login kamu sekarang terkunci di vault."))
            }
            Note(text: T("Panic word: set a word that destroys the vault right away if you ever type it.",
                         "Kata panik: atur 1 kata yang langsung memusnahkan vault kalau kamu mengetiknya."),
                 icon: "flame.fill", color: .orange)
        }
    }

    // 7. Cara pakai sehari-hari
    private var routine: some View {
        VStack(spacing: 16) {
            title(T("Your daily routine", "Rutinitas harian"), T("Use it like this and you'll never lose a thing.",
                                                                 "Pakai seperti ini dan tidak ada yang hilang."))
            Card {
                item("tray.full.fill", Pal.keep, T("Put important files in your Keep folder", "Taruh file penting di folder Keep"),
                     T("Anything outside it can disappear.", "Yang di luar folder itu bisa hilang."))
                item("rectangle.portrait.and.arrow.right", Pal.logout, T("Done? Save & Log Out", "Selesai? Simpan & Logout"),
                     T("Saves your logins, then logs out.", "Simpan login dulu, baru logout."))
                item("arrow.counterclockwise", Pal.vault, T("Back? Restore Profiles", "Kembali? Restore Profil"),
                     T("Open Profile Vault, type your password, done.", "Buka Profile Vault, ketik password, selesai."))
                item("eye.fill", Pal.pause, T("Not sure? Check first", "Ragu? Cek dulu"),
                     T("Settings → See what would be deleted.", "Pengaturan → Lihat yang akan dihapus."))
            }
            Note(text: T("Amnesia stays OFF until you press Turn On. Take your time.",
                         "Amnesia tetap MATI sampai kamu tekan Aktifkan. Santai saja."),
                 icon: "power", color: .green)
        }
    }
}

/// "Data kamu tetap di Mac ini": tidak ada server, tidak ada pelacakan.
struct PrivacyNote: View {
    var body: some View {
        Label(T("Everything stays on this Mac. Amnesia has no servers, no tracking and no analytics. "
                + "Nothing is sent anywhere unless you set up a backup yourself.",
                "Semua tetap di Mac ini. Amnesia tidak punya server, tidak melacak, tidak mengumpulkan data. "
                + "Tidak ada yang dikirim ke mana pun, kecuali kamu sendiri yang mengatur backup."),
              systemImage: "hand.raised.fill")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

let termsURL = "https://github.com/navi-crwn/amnesia-mac/blob/main/TERMS.md"

// MARK: - Backup

struct BackupView: View {
    @EnvironmentObject var m: Model
    let back: () -> Void
    @State private var dest = Config.get("BACKUP_DEST", "drive")
    @State private var drives: [Drive] = []
    @State private var drive = Config.get("BACKUP_DRIVE")
    @State private var server = Config.get("BACKUP_SSH")
    @State private var cloud = Config.get("BACKUP_RCLONE", "gdrive:Amnesia")
    @State private var folders = Set(BackupView.saved)
    @State private var extra = BackupView.saved.filter { !BackupView.defaults.contains($0) }
    @State private var sshPw = ""
    @State private var provider = cloudProviders.first(where: { $0.id == Config.get("BACKUP_CLOUD", "drive") }) ?? cloudProviders[0]
    @State private var connected: [String] = []
    @State private var withVault = Config.get("BACKUP_VAULT") == "1"
    @State private var schedule = Config.get("BACKUP_SCHEDULE", "off")
    @State private var remember = Secret.exists
    @State private var pw = ""
    @State private var pw2 = ""
    @State private var status = lastBackupStatus()
    static let defaults = ["@keep", "Documents", "Desktop", "Downloads", "Pictures", "Music", "Movies"]
    /// "@keep" = folder Keep (di mana pun letaknya). "Keep" dari versi lama juga berarti folder Keep.
    static var saved: [String] {
        Config.get("BACKUP_FOLDERS", "@keep").split(separator: ",").map { $0 == "Keep" ? "@keep" : String($0) }
    }

    private func label(_ f: String) -> String {
        f == "@keep" ? T("Keep folder (\(KeepDir.name))", "Folder Keep (\(KeepDir.name))") : f
    }
    private var all: [String] { BackupView.defaults + extra }
    private var remote: String { String(cloud.split(separator: ":", maxSplits: 1).first ?? "") }

    private var host: String { String(server.split(separator: ":", maxSplits: 1).first ?? "") }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                PageHeader(title: "Backup", icon: "externaldrive.fill", colors: Pal.backup, back: back)
                if !status.isEmpty {
                    Card {
                        Note(text: T("Last: ", "Terakhir: ") + status,
                             icon: status.contains("OK:") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                             color: status.contains("OK:") ? .green : .red)
                    }
                }
                Card {
                    Text(T("Where to", "Tujuan")).font(.system(size: 13, weight: .semibold))
                    Picker("", selection: $dest) {
                        Text(T("USB / SSD", "Flashdisk / SSD")).tag("drive")
                        Text(T("SSH Server", "Server SSH")).tag("ssh")
                        Text("Cloud").tag("rclone")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    switch dest {
                    case "ssh": sshBox
                    case "rclone": cloudBox
                    default: driveBox
                    }
                }
                Card {
                    Text(T("What to back up", "Yang di-backup")).font(.system(size: 13, weight: .semibold))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading,
                              spacing: 8) {
                        ForEach(all, id: \.self) { f in
                            Toggle(label(f), isOn: Binding(get: { folders.contains(f) },
                                                    set: { on in if on { folders.insert(f) } else { folders.remove(f) } }))
                                .toggleStyle(.checkbox)
                        }
                    }
                    Button { addFolder() } label: {
                        Label(T("Add another folder…", "Tambah folder lain…"), systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(.pink)
                    Toggle(T("Include Profile Vault (for moving Macs)", "Sertakan Profile Vault (untuk Pindah Mac)"), isOn: $withVault)
                        .toggleStyle(.checkbox)
                }
                Card {
                    Field(label: remember ? T("Backup password (leave empty to use the saved one)",
                                              "Password backup (kosongkan = pakai yang tersimpan)")
                                          : T("Backup password", "Password backup"),
                          text: $pw)
                    if !pw.isEmpty { Field(label: T("Repeat password", "Ulangi password"), text: $pw2) }
                    Toggle(T("Save password in Keychain (needed for scheduled backups)",
                             "Simpan password di Keychain (wajib untuk backup terjadwal)"), isOn: $remember)
                        .toggleStyle(.checkbox).font(.system(size: 12))
                    Note(text: T("The .7z file is locked with AES-256, file names too. Without the password, "
                                 + "nobody can open it.",
                                 "File .7z dikunci AES-256, nama file di dalamnya juga. Tanpa password, backup "
                                 + "tidak bisa dibuka."), icon: "exclamationmark.triangle.fill", color: .orange)
                }
                Card {
                    Text(T("Schedule", "Jadwal")).font(.system(size: 13, weight: .semibold))
                    Picker("", selection: $schedule) {
                        Text(T("Off", "Mati")).tag("off")
                        Text(T("Daily", "Harian")).tag("daily")
                        Text(T("Weekly", "Mingguan")).tag("weekly")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Note(text: T("Runs on its own while the Amnesia icon is in the menu bar. If it goes to a USB drive, "
                                 + "it runs when the drive is plugged in.",
                                 "Berjalan sendiri selama ikon Amnesia ada di menu bar. Kalau tujuannya flashdisk, "
                                 + "backup jalan saat flashdisk tercolok."))
                }
                HStack(spacing: 10) {
                    Button { if save() { info("Backup", T("Settings saved.", "Pengaturan disimpan.")) } } label: {
                        Label(T("Save", "Simpan"), systemImage: "checkmark")
                    }
                    .buttonStyle(Pill(colors: Pal.gray))
                    Button { start() } label: { Label(T("Back Up Now", "Backup Sekarang"), systemImage: "arrow.up.doc.fill") }
                        .buttonStyle(Pill(colors: Pal.backup))
                }
            }
        }
        .scrollIndicators(.never)
        .onAppear { load() }
    }

    @ViewBuilder private var driveBox: some View {
        HStack {
            Text(T("Plugged-in drives", "Drive yang tercolok")).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Button { load() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).help(T("Look again", "Cari drive lagi"))
        }
        if drives.isEmpty {
            Note(text: T("No external drive found. Plug in an SSD/USB drive, then press ↻.",
                         "Tidak ada drive eksternal. Colok SSD/flashdisk lalu tekan ↻."),
                 icon: "externaldrive.badge.xmark", color: .red)
        } else {
            Picker("", selection: $drive) {
                ForEach(drives) { d in Text("\(d.name)  ·  \(d.free)").tag(d.name) }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
        }
    }

    @ViewBuilder private var sshBox: some View {
        Field(label: T("Server (user@host:folder), e.g. user@remoteserv.er:backup",
                       "Server (user@alamat:folder), mis. user@remoteserv.er:backup"), text: $server, secure: false)
        Field(label: T("Server password (only the first time, never saved)",
                       "Password server (hanya pertama kali, tidak disimpan)"), text: $sshPw)
        Button { connectServer() } label: { Label(T("Connect", "Hubungkan"), systemImage: "bolt.horizontal.fill") }
            .buttonStyle(Pill(colors: Pal.logout))
            .disabled(host.isEmpty)
        Note(text: T("No Terminal needed. Amnesia makes an SSH key and installs it on the server with your password, "
                     + "once. After that, backups log in with the key. No folder after the colon? Backups go to "
                     + "amnesia-backup in your home folder on the server.",
                     "Tanpa Terminal. Amnesia membuat kunci SSH dan memasangnya di server pakai password kamu, "
                     + "sekali saja. Sesudah itu backup login pakai kunci. Tidak ada folder setelah titik dua? "
                     + "Backup masuk ke amnesia-backup di folder home server."))
    }

    @ViewBuilder private var cloudBox: some View {
        Picker(T("Service", "Layanan"), selection: $provider) {
            ForEach(cloudProviders) { p in Text(p.name).tag(p) }
        }
        .onChange(of: provider) { _, p in cloud = p.remote + ":Amnesia" }
        Field(label: T("Folder in the cloud (remote:folder)", "Folder di cloud (remote:folder)"), text: $cloud, secure: false)
        if connected.contains(remote) {
            Note(text: T("\(provider.name) is connected.", "\(provider.name) sudah terhubung."),
                 icon: "checkmark.circle.fill", color: .green)
        }
        Button { setupCloud() } label: {
            Label(connected.contains(remote) ? T("Reconnect \(provider.name)", "Hubungkan ulang \(provider.name)")
                                             : T("Connect \(provider.name)", "Hubungkan \(provider.name)"),
                  systemImage: "icloud.and.arrow.up.fill")
        }
        .buttonStyle(Pill(colors: Pal.logout))
        Note(text: T("Just log in in a small login window, no Terminal or Chrome needed. S3, WebDAV, SFTP and 40+ more work too: "
                     + "set them up with rclone config, then type the remote name above.",
                     "Cukup login di jendela kecil, tanpa Terminal atau Chrome. S3, WebDAV, SFTP dan 40+ layanan lain juga bisa: "
                     + "atur lewat rclone config, lalu ketik nama remote-nya di atas."))
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: P.home)
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let path = url.standardizedFileURL.path
            guard !path.contains(","), path != P.home, path != "/" else {
                info("Backup", T("Pick a folder without a comma in its name (and not your whole home folder).",
                                 "Pilih folder tanpa koma di namanya (dan bukan seluruh folder home)."), error: true)
                continue
            }
            // di dalam home: disimpan relatif; di luar home (mis. drive lain): path lengkap
            let rel = path.hasPrefix(P.home + "/") ? String(path.dropFirst(P.home.count + 1)) : path
            if !all.contains(rel) { extra.append(rel) }
            folders.insert(rel)
        }
    }

    private func load() {
        checkCloud()
        drives = listDrives()
        if !drives.contains(where: { $0.name == drive }) { drive = drives.first?.name ?? drive }
        status = lastBackupStatus()
    }

    /// Simpan pengaturan ke settings.conf (+ password ke Keychain kalau dipilih).
    private func save() -> Bool {
        let sel = all.filter { folders.contains($0) }
        guard !sel.isEmpty || withVault else { info("Backup", T("Pick at least 1 folder.", "Pilih minimal 1 folder."), error: true); return false }
        if !pw.isEmpty && pw != pw2 { info("Backup", T("The passwords don't match.", "Password tidak cocok."), error: true); return false }
        if dest == "ssh" && !validServer(server) {
            info("Backup", T("Type the server as user@host or user@host:folder (no spaces).",
                             "Isi server dengan format user@alamat atau user@alamat:folder (tanpa spasi)."), error: true); return false
        }
        if dest == "rclone" && !cloud.contains(":") {
            info("Backup", T("Type the cloud destination as remote:folder, e.g. gdrive:Amnesia.",
                             "Isi tujuan cloud dengan format remote:folder, mis. gdrive:Amnesia."), error: true)
            return false
        }
        if remember {
            if !pw.isEmpty && !Secret.set(pw) {
                info("Backup", T("Couldn't save the password to Keychain.", "Password gagal disimpan ke Keychain."), error: true); return false
            }
            if pw.isEmpty && !Secret.exists {
                info("Backup", T("Type a password first so it can be saved.", "Isi password dulu supaya bisa disimpan."), error: true); return false
            }
        } else {
            Secret.delete()
            if schedule != "off" {
                info("Backup", T("Scheduled backups need a saved password. Tick Save password in Keychain.",
                                 "Backup terjadwal butuh password tersimpan. Centang Simpan password di Keychain."),
                     error: true)
                return false
            }
        }
        Config.set("BACKUP_DEST", dest)
        Config.set("BACKUP_DRIVE", drive)
        Config.set("BACKUP_SSH", server)
        Config.set("BACKUP_RCLONE", cloud)
        Config.set("BACKUP_CLOUD", provider.id)
        Config.set("BACKUP_FOLDERS", sel.joined(separator: ","))
        Config.set("BACKUP_VAULT", withVault ? "1" : "0")
        Config.set("BACKUP_SCHEDULE", schedule)
        return true
    }

    private func start() {
        guard save() else { return }
        let typed = pw
        guard !typed.isEmpty || remember else { info("Backup", T("Type the backup password.", "Isi password backup."), error: true); return }
        let to = dest == "drive" ? drive : (dest == "ssh" ? host : cloud)
        m.background(T("Backing up to \(to)…\nDon't unplug the drive or turn off the internet.",
                       "Backup ke \(to)…\nJangan cabut drive / matikan internet."), { () -> (ok: Bool, msg: String) in
            guard let p = typed.isEmpty ? Secret.get() : typed else { return (false, T("Couldn't read the saved password.", "Password tersimpan tidak bisa dibaca.")) }
            return runBackup(p)
        }) { r in
            status = lastBackupStatus()
            if r.ok {
                pw = ""; pw2 = ""
                info(T("Backup done", "Backup berhasil"), r.msg.replacingOccurrences(of: "OK: ", with: "")
                     + T("\n\nSHA256 checksum saved in backup_checksums.txt.",
                         "\n\nChecksum SHA256 dicatat di backup_checksums.txt."))
            } else {
                info(T("Backup failed", "Backup gagal"), stripFail(r.msg), error: true)
            }
        }
    }

    private func connectServer() {
        let srv = server.trimmingCharacters(in: .whitespaces), pw = sshPw
        guard validServer(srv) else {
            info("Backup", T("Type the server as user@host or user@host:folder (no spaces).",
                             "Isi server dengan format user@alamat atau user@alamat:folder (tanpa spasi)."), error: true)
            return
        }
        server = srv
        m.background(T("Connecting to \(host)…", "Menghubungi \(host)…"), { connectSSH(srv, password: pw) }) { r in
            sshPw = ""
            if r.ok {
                Config.set("BACKUP_SSH", srv)
                info(T("Connected", "Terhubung"), r.msg)
            } else {
                info(T("Couldn't connect", "Koneksi gagal"), r.msg, error: true)
            }
        }
    }

    /// Cek remote rclone yang sudah terhubung (diam-diam).
    private func checkCloud() {
        m.quiet({ rcloneRemotes() }) { r in connected = r }
    }

    private func setupCloud() {
        let p = provider
        if remote.isEmpty { cloud = p.remote + ":Amnesia" }
        let name = remote
        m.background(T("Log in to \(p.name) in the login window…\n(Amnesia waits up to 5 minutes)",
                       "Login ke \(p.name) di jendela login…\n(Amnesia menunggu sampai 5 menit)"),
                     { connectCloud(p, remote: name) }) { err in
            if let e = err {
                info(p.name, e, error: true)
            } else {
                _ = save()
                info(p.name, T("Connected! Backups can now go to \(cloud).", "Terhubung! Backup sekarang bisa ke \(cloud)."))
            }
            checkCloud()
        }
    }
}

// MARK: - Pengaturan

struct SettingsView: View {
    @EnvironmentObject var m: Model
    let back: () -> Void
    @State private var auto = Setting.autoSnapshot.isOn
    @State private var notify = Setting.notify.isOn
    @State private var preview = Setting.preview.isOn

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                PageHeader(title: T("Settings", "Pengaturan"), icon: "gearshape.fill", colors: Pal.gray, back: back)
                language
                row(T("Auto snapshot at logout", "Snapshot otomatis saat logout"),
                    T("Your logins get saved to the vault on every logout, restart or shutdown, even if you didn't "
                      + "use Save & Log Out. Needs a vault.",
                      "Login kamu disimpan ke vault setiap logout, restart atau shutdown, walau tidak lewat tombol "
                      + "Simpan & Logout. Butuh vault yang sudah dibuat."),
                    "camera.fill", Pal.vault, $auto) { Setting.autoSnapshot.set($0) }
                row(T("Notification after login", "Notifikasi setelah login"),
                    T("Tells you the Mac is clean and reminds you to restore your profiles.",
                      "Muncul pemberitahuan bahwa Mac sudah bersih, plus pengingat untuk restore profil."),
                    "bell.badge.fill", Pal.pause, $notify) { Setting.notify.set($0) }
                row(T("Check before logout", "Cek dulu sebelum logout"),
                    T("On logout, restart or shutdown, Amnesia holds on for a moment and shows what will be deleted. "
                      + "You pick Continue or Cancel.",
                      "Saat logout, restart atau shutdown, Amnesia menahan sebentar dan menampilkan daftar yang "
                      + "akan dihapus. Kamu pilih Lanjut atau Batal."),
                    "eye.fill", Pal.logout, $preview) { Setting.preview.set($0) }
                Button { m.page = .preview } label: {
                    Label(T("See what would be deleted now", "Lihat yang akan dihapus sekarang"), systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(Pill(colors: Pal.backup))
                KeepFolderCard()
                if !Engine.hasFullDisk {
                    Card {
                        Note(text: T("Give Amnesia Full Disk Access once, so macOS stops asking about every folder.",
                                     "Beri Amnesia Akses Disk Penuh sekali, supaya macOS tidak tanya per folder."),
                             icon: "lock.open.fill", color: .orange)
                        Button(T("Open Privacy Settings", "Buka Pengaturan Privasi")) { Engine.openFullDiskSettings() }
                    }
                }
                Button { m.showTour() } label: {
                    Label(T("Show the welcome tour again", "Tampilkan tur perkenalan lagi"), systemImage: "sparkles")
                }
                .buttonStyle(Pill(colors: Pal.vault))
                PrivacyNote().padding(.horizontal, 4)
            }
        }
        .scrollIndicators(.never)
    }

    private var language: some View {
        Card {
            HStack(spacing: 12) {
                IconBadge(icon: "globe", colors: Pal.keep, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(T("Language", "Bahasa")).font(.system(size: 14, weight: .semibold))
                    Text(T("For the app and notifications.", "Untuk app dan notifikasi."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Picker("", selection: $m.lang) {
                    ForEach(Lang.allCases, id: \.self) { l in Text(l.name).tag(l) }
                }
                .labelsHidden()
                .frame(width: 170)
            }
        }
    }

    private func row(_ title: String, _ sub: String, _ icon: String, _ colors: [Color], _ value: Binding<Bool>,
                     save: @escaping (Bool) -> Void) -> some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(icon: icon, colors: colors, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(sub).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(get: { value.wrappedValue },
                                         set: { on in value.wrappedValue = on; save(on) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }
}

// MARK: - Lihat yang akan dihapus

struct PreviewView: View {
    @EnvironmentObject var m: Model
    let back: () -> Void
    private var groups: [DryGroup]? { m.report }

    private var updated: String {
        if m.reportBusy { return T("Updating…", "Memperbarui…") }
        guard let d = m.reportTime else { return "" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: Lang.current == .id ? "id" : "en")
        return T("Updated ", "Diperbarui ") + f.localizedString(for: d, relativeTo: Date())
    }

    private var total: Int { (groups ?? []).reduce(0) { $0 + $1.items.count } }

    var body: some View {
        VStack(spacing: 14) {
            PageHeader(title: T("What Gets Deleted", "Yang Akan Dihapus"), icon: "eye.fill", colors: Pal.logout, back: { cancel() })
            if let a = m.pending {
                Card {
                    Note(text: T("\(a.title) is on hold so you can check first. Your Keep folder (\(KeepDir.shown)), "
                                 + "the Keep List and the Profile Vault stay safe.",
                                 "\(a.title) ditahan sebentar supaya kamu bisa cek dulu. Folder Keep (\(KeepDir.shown)), "
                                 + "Keep List dan Profile Vault tetap aman."), icon: "hand.raised.fill", color: .orange)
                }
            }
            if let g = groups {
                HStack {
                    Text(T("\(total) items", "\(total) item")).font(.system(size: 20, weight: .bold, design: .rounded))
                    Spacer()
                    Text(T("\(g.count) groups · click for details", "\(g.count) kelompok · klik untuk detail")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    if m.reportBusy { ProgressView().controlSize(.mini) }
                    Text(updated).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button { m.updateReport() } label: { Label(T("Refresh", "Muat ulang"), systemImage: "arrow.clockwise") }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).disabled(m.reportBusy)
                }
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(g) { grp in group(grp) }
                    }
                }
                .scrollIndicators(.never)
            } else {
                Spacer()
                ProgressView(T("Checking…", "Mengecek…"))
                Spacer()
            }
            if let a = m.pending {
                HStack(spacing: 10) {
                    Button { cancel() } label: { Label(T("Cancel", "Batal"), systemImage: "xmark") }
                        .buttonStyle(Pill(colors: Pal.gray))
                    Button { m.continueQuit() } label: { Label(T("Continue \(a.title)", "Lanjut \(a.title)"), systemImage: "checkmark") }
                        .buttonStyle(Pill(colors: Pal.danger))
                }
            }
        }
        .onAppear { load() }
    }

    private func group(_ grp: DryGroup) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(grp.items.prefix(200)), id: \.self) { i in
                    Text(i).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                if grp.items.count > 200 {
                    Text(T("…and \(grp.items.count - 200) more", "…dan \(grp.items.count - 200) lagi")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        } label: {
            HStack {
                Text(grp.name).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(grp.items.count)").font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(Color.pink.opacity(0.15)))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
    }

    /// Laporan lama langsung tampil; yang baru disiapkan di background.
    private func load() {
        if !Shots.on { m.updateReport() }
    }

    private func cancel() {
        m.pending = nil
        back()
    }
}

// MARK: - Menu bar

struct MenuTile: View {
    let title: String
    let icon: String
    let colors: [Color]
    let action: () -> Void
    @State private var hover = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                IconBadge(icon: icon, colors: colors, size: 30)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(hover && enabled ? 0.10 : 0.05)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(colors[0].opacity(hover && enabled ? 0.6 : 0), lineWidth: 1))
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
    }
}

struct InfoChip: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.12)))
    }
}

struct MenuPanel: View {
    @EnvironmentObject var m: Model
    @Environment(\.openWindow) private var openWindow

    private var vaultValue: String {
        guard let v = m.vault, v.ok else { return "—" }
        if v.exists != true { return T("Not set up", "Belum dibuat") }
        if let man = v.manifest { return man.time }
        return T("No snapshot yet", "Belum ada snapshot")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // kartu status berwarna
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.25)).frame(width: 46, height: 46)
                    Image(systemName: m.state.icon).font(.system(size: 22, weight: .bold))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(m.state.title).font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(m.lastClean).font(.system(size: 11, weight: .medium)).opacity(0.9)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: m.state.colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
            .shadow(color: (m.state.colors.last ?? .black).opacity(0.35), radius: 10, y: 5)

            HStack(spacing: 8) {
                InfoChip(icon: "lock.rectangle.stack.fill", label: "Snapshot vault", value: vaultValue,
                         color: Color(hex: 0x6366F1))
                InfoChip(icon: "pin.fill", label: "Keep List", value: T("\(Keep.entries().count) items", "\(Keep.entries().count) item"),
                         color: Color(hex: 0x14B8A6))
            }

            if let b = m.busy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(b).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                MenuTile(title: T("Open Amnesia", "Buka Amnesia"), icon: "macwindow", colors: [Color(hex: 0x22D3EE), Color(hex: 0x6366F1)]) {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                MenuTile(title: T("Save & Log Out", "Simpan Profil & Logout"), icon: "rectangle.portrait.and.arrow.right",
                         colors: Pal.logout) { m.saveAndLogout() }
                    .disabled(m.busy != nil)
                MenuTile(title: m.state == .paused ? T("Cancel Pause", "Batalkan Jeda") : T("Pause 1 Session", "Jeda 1 Sesi"), icon: "pause.fill",
                         colors: Pal.pause) { m.togglePause() }
                    .disabled(m.state == .off)
                MenuTile(title: m.state == .off ? T("Turn On", "Aktifkan") : T("Turn Off", "Matikan"), icon: "power",
                         colors: m.state == .off ? Pal.on : Pal.danger) { m.togglePower() }
            }

            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Amnesia v\(appVersion)").font(.system(size: 11, weight: .semibold))
                    Text(T("Quitting the app doesn't stop the wiping.", "Menutup app tidak menghentikan pembersihan."))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(T("Quit App", "Tutup App")) { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear {
            m.refresh()
            m.refreshVault()
        }
    }
}

struct MenuIcon: View {
    let state: AState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: state.icon)
            .onAppear {
                Opener.open = { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
            }
    }
}

// MARK: - Screenshot otomatis (untuk README & website)
// app/screenshots.sh menjalankan:  AMNESIA_HOME=<home palsu> Amnesia --shots <folder>
// Semua data dari home palsu (contoh), jadi data pribadimu tidak ikut terfoto. Tidak ada yang dihapus.

@MainActor
enum Shots {
    static let on = CommandLine.arguments.contains("--shots")
    static var dir: String {
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--shots"), i + 1 < a.count { return a[i + 1] }
        return P.realHome + "/Desktop/amnesia-shots"
    }

    static func wait(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }

    static func run() async {
        let m = Model.shared
        m.onboarded = true
        await wait(3)
        for lang in Lang.allCases {
            m.lang = lang
            await wait(2.5)
            let log = (try? String(contentsOfFile: P.cleanLog, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            m.lastClean = T("Last: ", "Terakhir: ") + log
            let out = dir + "/" + lang.rawValue
            try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
            await shot(Shell { OnboardingView(step: 0) }, out + "/tour-welcome.png")
            await shot(Shell { OnboardingView(step: 1) }, out + "/tour-terms.png")
            await shot(Shell { OnboardingView(step: 3) }, out + "/tour-check.png")
            await shot(Shell { OnboardingView(step: 4) }, out + "/tour-apps.png")
            await shot(Shell { OnboardingView(keepSetup: true) }, out + "/keep-setup.png", settle: 4)
            let pages: [(Page, String)] = [(.home, "home"), (.vault, "vault"), (.keep, "keep"), (.backup, "backup"),
                                           (.settings, "settings")]
            for (page, name) in pages {
                m.page = page
                await shot(MainView(), out + "/\(name).png")
            }
            m.report = dryRun()
            m.reportTime = Date()
            m.page = .preview
            await shot(MainView(), out + "/preview.png")
            m.page = .home
            await shot(MainView(), out + "/home-dark.png", dark: true)
            await shot(MenuPanel().background(Color(nsColor: .windowBackgroundColor)), out + "/menu.png", window: false)
        }
        exit(0)
    }

    /// Bungkus seperti jendela utama (latar + jarak tepi yang sama).
    struct Shell<C: View>: View {
        let content: C
        init(@ViewBuilder _ c: () -> C) { content = c() }
        var body: some View {
            ZStack {
                Backdrop()
                content.padding(.horizontal, 24).padding(.top, 34).padding(.bottom, 20)
            }
            .frame(width: 480, height: 690)
        }
    }

    static func shot<V: View>(_ v: V, _ path: String, dark: Bool = false, settle: Double = 1.5, window: Bool = true) async {
        let host = NSHostingView(rootView: v.environmentObject(Model.shared))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let w = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        w.contentView = host
        w.setFrameOrigin(NSPoint(x: -30000, y: -30000))     // di luar layar
        w.orderFrontRegardless()
        await wait(settle)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        w.orderOut(nil)
        if let png = framed(rep, points: size, radius: window ? 12 : 10, dots: window) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }

    /// Sudut membulat, bayangan lembut, dan (untuk jendela) 3 tombol bulat di kiri atas.
    static func framed(_ rep: NSBitmapImageRep, points: NSSize, radius: CGFloat, dots: Bool) -> Data? {
        let s = CGFloat(rep.pixelsWide) / max(points.width, 1)
        let w = CGFloat(rep.pixelsWide), h = CGFloat(rep.pixelsHigh), pad = 36 * s
        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w + pad * 2), pixelsHigh: Int(h + pad * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: out) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        let rect = NSRect(x: pad, y: pad, width: w, height: h)
        let shape = NSBezierPath(roundedRect: rect, xRadius: radius * s, yRadius: radius * s)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
        shadow.shadowBlurRadius = 22 * s
        shadow.shadowOffset = NSSize(width: 0, height: -8 * s)
        shadow.set()
        NSColor.windowBackgroundColor.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        rep.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.withAlphaComponent(0.12).setStroke()
        shape.lineWidth = 1 * s
        shape.stroke()
        if dots {
            for (i, c) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
                NSColor(red: CGFloat(c >> 16 & 255) / 255, green: CGFloat(c >> 8 & 255) / 255,
                        blue: CGFloat(c & 255) / 255, alpha: 1).setFill()
                NSBezierPath(ovalIn: NSRect(x: pad + (14 + CGFloat(i) * 20) * s, y: pad + h - 26 * s,
                                            width: 12 * s, height: 12 * s)).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return out.representation(using: .png, properties: [:])
    }
}

// MARK: - App

@MainActor
enum Opener {
    static var open: (@MainActor () -> Void)?
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Hanya boleh jalan 1x: kalau sudah ada Amnesia lain yang jalan, pakai yang itu lalu keluar.
    func applicationWillFinishLaunching(_ notification: Notification) {
        if Shots.on { return }
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != me }
        guard let other = others.first else { return }
        if !CommandLine.arguments.contains("--background"), let url = other.bundleURL {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
        exit(0)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Shots.on { Task { await Shots.run() } }
    }

    // Logout/restart/shutdown dari menu Apple → tahan dulu & tampilkan yang akan dihapus (kalau diaktifkan).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let m = Model.shared
        if m.allowQuit { return .terminateNow }
        let reason = NSAppleEventManager.shared().currentAppleEvent?
            .attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.typeCodeValue ?? 0
        let action: QuitAction?
        switch reason {
        case OSType(kAELogOut), OSType(kAEReallyLogOut): action = .logout
        case OSType(kAERestart), OSType(kAEShowRestartDialog): action = .restart
        case OSType(kAEShutDown), OSType(kAEShowShutdownDialog): action = .shutdown
        default: action = nil
        }
        // Tidak ditahan kalau: bukan logout, Amnesia mati/jeda, fitur dimatikan, atau jendela tidak bisa dibuka.
        guard let a = action, m.state == .active, Setting.preview.isOn, let open = Opener.open else {
            return .terminateNow
        }
        m.pending = a
        m.page = .preview
        open()
        return .terminateCancel
    }

    // Ikon app diklik lagi (Finder/Desktop) saat app sudah jalan → buka jendela utama.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Opener.open?() }
        return true
    }
}

@main
struct AmnesiaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = Model.shared
    // Dibuka otomatis saat login (agent.sh) → hanya ikon menu bar, tanpa jendela.
    private let background = CommandLine.arguments.contains("--background")

    init() {
        if CommandLine.arguments.contains("--agent") { Agent.run() }   // dijalankan launchd, tanpa jendela
        signal(SIGPIPE, SIG_IGN)   // program yang ditutup lebih cepat tidak boleh membuat app crash
    }

    var body: some Scene {
        Window("Amnesia", id: "main") {
            MainView().environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(background || Shots.on ? .suppressed : .presented)

        MenuBarExtra(isInserted: .constant(!Shots.on)) {
            MenuPanel().environmentObject(model)
        } label: {
            MenuIcon(state: model.state)
        }
        .menuBarExtraStyle(.window)
    }
}
