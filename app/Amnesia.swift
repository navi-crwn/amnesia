// Amnesia v5.7 — app Mac asli (SwiftUI): jendela utama + ikon status di menu bar.
// Dibuild oleh build.sh (swiftc dari Command Line Tools, tanpa Xcode).
// Logika berat tetap di ~/.amnesia: clean.sh, agent.sh, vault.py (dipanggil lewat Process).
import AppKit
import Security
import SwiftUI

// MARK: - Lokasi file

enum P {
    static let home = NSHomeDirectory()
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
func sh(_ exe: String, _ args: [String], input: String? = nil, cwd: String? = nil, timeout: Double? = nil) -> Out {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    if let cwd = cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
    let o = Pipe(), e = Pipe(), i = Pipe()
    p.standardOutput = o
    p.standardError = e
    p.standardInput = i
    do { try p.run() } catch { return Out(code: -1, out: "", err: error.localizedDescription) }
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
        errBox.data = e.fileHandleForReading.readDataToEndOfFile()
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

// MARK: - Deteksi app yang terpasang (untuk memilih yang di-keep)

struct FoundApp: Identifiable {
    let name: String
    let icon: NSImage
    let paths: [String]      // relatif dari home
    let inVault: Bool
    var id: String { name }
}

/// App yang login-nya sudah diurus Profile Vault.
let vaultApps = ["Google Chrome", "Claude", "WhatsApp", "Windows App", "Antigravity"]
/// App yang disarankan untuk di-keep (VPN & password manager): settingnya tidak rahasia dan repot diatur ulang.
let suggestWords = ["vpn", "tailscale", "nord", "surfshark", "proton", "mullvad", "1password", "bitwarden"]

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
        !a.inVault && (a.paths.allSatisfy { keepMatches($0, kept) }
                       || suggestWords.contains { a.name.lowercased().contains($0) })
    }.map(\.name))
}

/// Tambah app yang dipilih ke Keep List; app yang dimatikan dihapus (hanya baris yang persis miliknya).
func applyPicks(_ apps: [FoundApp], _ picked: Set<String>) {
    let kept = Keep.entries()
    for a in apps where !a.inVault && !picked.contains(a.name) {
        for p in a.paths where kept.contains(p) { Keep.remove(p) }
    }
    let add = apps.filter { picked.contains($0.name) && !$0.inVault }.flatMap(\.paths).filter { !keepMatches($0, kept) }
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

func dryRun() -> [DryGroup] {
    let r = sh("/bin/bash", [P.a + "/clean.sh", "logout", "--dry-run"])
    var groups: [String: [String]] = [:]
    for line in r.out.split(separator: "\n").map(String.init) {
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

/// Hubungkan cloud tanpa Terminal: pasang rclone kalau perlu, buka login di browser, lalu cek koneksinya.
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
    let c = sh(r, ["config", "create", remote, p.id], timeout: 300)
    guard c.code == 0, sh(r, ["lsd", remote + ":"], timeout: 60).code == 0 else {
        return T("\(p.name) isn't connected. Try again and finish the login in your browser.",
                 "\(p.name) belum terhubung. Coba lagi dan selesaikan login di browser.")
    }
    return nil
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

/// Buka Terminal dengan perintah siap jalan (untuk setup yang butuh browser / ketik password).
func openTerminal(_ title: String, _ lines: [String]) {
    let path = NSTemporaryDirectory() + "amnesia-setup.command"
    let text = "#!/bin/bash\nexport PATH=\"/opt/homebrew/bin:$PATH\"\nclear\necho \"== Amnesia: \(title) ==\"\n"
        + lines.joined(separator: "\n")
        + "\necho\necho \"" + T("Done. Go back to Amnesia, then close this window.",
                                "Selesai. Kembali ke Amnesia, lalu tutup jendela ini.") + "\"\n"
    try? text.write(toFile: path, atomically: true, encoding: .utf8)
    chmod(path, 0o700)
    NSWorkspace.shared.open(URL(fileURLWithPath: path))
}

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
    private var timer: Timer?
    private var backupTimer: Timer?
    private var backupRunning = false

    init() {
        Engine.install()
        refresh()
        refreshVault()
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

    func refresh() {
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
            guard confirm(T("Turn on Amnesia?", "Aktifkan Amnesia?"),
                          T("From the next logout on, everything outside the Keep List and the ~/Keep folder will be "
                            + "DELETED at logout/restart/shutdown, then checked again at login.\n\n"
                            + "Move important files to ~/Keep first. This session is safe until you log out.",
                            "Mulai logout berikutnya, semua data di luar Keep List dan folder ~/Keep akan DIHAPUS "
                            + "saat logout/restart/shutdown, lalu dicek ulang saat login.\n\n"
                            + "Pindahkan file penting ke ~/Keep dulu. Sesi sekarang aman sampai kamu logout."),
                          ok: T("Turn On", "Aktifkan"), danger: true) else { return }
            if let err = activate() {
                info(T("Could not turn on", "Gagal mengaktifkan"), err, error: true)
            } else {
                info(T("Amnesia is ON", "Amnesia AKTIF"),
                     T("This session will be wiped at logout/restart/shutdown, then checked again at login.\n"
                       + "The ~/Keep folder stays safe.",
                       "Sesi ini dibersihkan saat logout/restart/shutdown, lalu dicek ulang saat login.\n"
                       + "Folder ~/Keep tetap aman."))
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
        let dict: [String: Any] = [
            "Label": P.label,
            "ProgramArguments": ["/bin/bash", P.a + "/agent.sh"],
            "RunAtLoad": true,
            "ExitTimeOut": 300,      // waktu untuk snapshot otomatis + pembersihan
        ]
        do {
            try fm.createDirectory(atPath: (P.plist as NSString).deletingLastPathComponent,
                                   withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
            try data.write(to: URL(fileURLWithPath: P.plist))
        } catch {
            return T("Could not write the LaunchAgent: ", "Tidak bisa menulis LaunchAgent: ") + error.localizedDescription
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
            Toggle(T("The panic word also empties ~/Keep", "Kata panik juga mengosongkan ~/Keep"), isOn: Binding(get: { panicFull && !panic.isEmpty }, set: { panicFull = $0 }))
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
            Toggle(T("Also empty ~/Keep", "Juga kosongkan ~/Keep"), isOn: $newPanicFull).font(.system(size: 12)).disabled(newPanic.isEmpty)
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
            Note(text: T("Everything here is NOT wiped at logout. The ~/Keep and ~/.amnesia folders are always safe.",
                         "Yang ada di sini TIDAK dihapus saat logout. Folder ~/Keep dan ~/.amnesia selalu aman."))
                .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - Pilih app yang di-keep

struct AppPickList: View {
    let apps: [FoundApp]
    @Binding var picked: Set<String>

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(apps) { a in
                    HStack(spacing: 10) {
                        Image(nsImage: a.icon).resizable().frame(width: 30, height: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(a.name).font(.system(size: 13, weight: .semibold))
                            Text(a.inVault ? T("Logins saved in the Profile Vault", "Login disimpan di Profile Vault")
                                 : picked.contains(a.name) ? T("Kept: data & settings stay", "Disimpan: data & setting tetap ada")
                                 : T("Wiped at logout", "Dihapus saat logout"))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if a.inVault {
                            Image(systemName: "lock.fill").foregroundStyle(.indigo)
                        } else {
                            Toggle("", isOn: Binding(get: { picked.contains(a.name) },
                                                     set: { on in if on { picked.insert(a.name) } else { picked.remove(a.name) } }))
                                .toggleStyle(.switch).labelsHidden().controlSize(.small)
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
                }
            }
        }
        .scrollIndicators(.never)
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
                AppPickList(apps: a, picked: $picked).frame(height: 360)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 360)
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
        .frame(width: 460)
        .onAppear {
            let a = scanApps()
            apps = a
            picked = defaultPicks(a)
        }
    }
}

// MARK: - Tur perkenalan (pertama kali dibuka)

struct OnboardingView: View {
    @EnvironmentObject var m: Model
    @State private var step = 0
    @State private var apps: [FoundApp]?
    @State private var picked = Set<String>()
    @State private var recheck = 0
    private let last = 5

    var body: some View {
        VStack(spacing: 16) {
            Group {
                switch step {
                case 0: welcome
                case 1: features
                case 2: setup
                case 3: appsPage
                case 4: vaultPage
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
                    Text(step == last ? T("Let's go", "Ayo mulai") : T("Next", "Lanjut"))
                }
                .buttonStyle(Pill(colors: Pal.vault))
                .keyboardShortcut(.defaultAction)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    private func next() {
        if step == 3, let a = apps { applyPicks(a, picked) }
        if step == last { m.finishOnboarding() } else { step += 1 }
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
        VStack(spacing: 18) {
            Spacer(minLength: 10)
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 120, height: 120)
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
        }
    }

    // 2. Cara kerja
    private var features: some View {
        VStack(spacing: 16) {
            title(T("How it works", "Cara kerjanya"), T("Four things to know.", "Cukup tahu 4 hal ini."))
            Card {
                item("sparkles", Pal.on, T("Wiped at logout", "Dihapus saat logout"),
                     T("Browser history, downloads, caches, app data: gone when you log out, restart or shut down.",
                       "Riwayat browser, download, cache, data app: hilang saat logout, restart, atau shutdown."))
                item("pin.fill", Pal.keep, T("Keep List & ~/Keep", "Keep List & ~/Keep"),
                     T("Apps and folders you pick stay. Files inside the ~/Keep folder always stay.",
                       "App dan folder pilihanmu tetap ada. File di folder ~/Keep selalu aman."))
                item("lock.rectangle.stack.fill", Pal.vault, "Profile Vault",
                     T("Your logins go into an encrypted safe. One password brings them back.",
                       "Login kamu masuk ke brankas terenkripsi. 1 password untuk mengembalikan semuanya."))
                item("externaldrive.fill", Pal.backup, "Backup",
                     T("Encrypted copies to a USB drive, your server or the cloud.",
                       "Salinan terenkripsi ke flashdisk, server kamu, atau cloud."))
            }
        }
    }

    // 3. Cek kesiapan
    private var setup: some View {
        let _ = recheck
        return VStack(spacing: 16) {
            title(T("Quick check", "Cek dulu"), T("Amnesia needs these to run.", "Amnesia butuh ini supaya bisa jalan."))
            Card {
                status(Engine.ready, T("Amnesia engine", "Mesin Amnesia"),
                       T("The scripts that do the wiping.", "Script yang melakukan pembersihan."))
                status(Engine.sevenz != nil, "7-Zip",
                       T("Locks your vault and backups (AES-256).", "Mengunci vault dan backup (AES-256)."))
                status(Engine.hasPython, T("Apple Command Line Tools", "Apple Command Line Tools"),
                       T("Free tools from Apple. The Profile Vault needs them.", "Alat gratis dari Apple, dibutuhkan Profile Vault."))
            }
            if !Engine.hasPython {
                Button { _ = sh("/usr/bin/xcode-select", ["--install"]) } label: {
                    Label(T("Install Command Line Tools", "Pasang Command Line Tools"), systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(Pill(colors: Pal.logout))
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

    // 4. Pilih app
    private var appsPage: some View {
        VStack(spacing: 12) {
            title(T("What should stay?", "Apa yang tetap disimpan?"),
                  T("We found these apps. Switch on the ones that should keep their data (VPNs are on already). "
                    + "Apps with a lock are handled by the Profile Vault.",
                    "Ini app yang ketemu di Mac kamu. Nyalakan yang datanya mau disimpan (VPN sudah dinyalakan). "
                    + "App bergembok diurus oleh Profile Vault."))
            if let a = apps {
                AppPickList(apps: a, picked: $picked)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if apps == nil {
                let a = scanApps()
                apps = a
                picked = defaultPicks(a)
            }
        }
    }

    // 5. Profile Vault
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

    // 6. Cara pakai sehari-hari
    private var routine: some View {
        VStack(spacing: 16) {
            title(T("Your daily routine", "Rutinitas harian"), T("Use it like this and you'll never lose a thing.",
                                                                 "Pakai seperti ini dan tidak ada yang hilang."))
            Card {
                item("tray.full.fill", Pal.keep, T("Put important files in ~/Keep", "Taruh file penting di ~/Keep"),
                     T("Anything outside it can disappear.", "Yang di luar folder itu bisa hilang."))
                item("rectangle.portrait.and.arrow.right", Pal.logout, T("Done? Save & Log Out", "Selesai? Simpan & Logout"),
                     T("Saves your logins, then logs out.", "Simpan login dulu, baru logout."))
                item("arrow.counterclockwise", Pal.vault, T("Back? Restore Profiles", "Kembali? Restore Profil"),
                     T("Open Profile Vault, type your password, done.", "Buka Profile Vault, ketik password, selesai."))
                item("eye.fill", Pal.pause, T("Not sure? Check first", "Ragu? Cek dulu"),
                     T("Settings → See what would be deleted now.", "Pengaturan → Lihat yang akan dihapus sekarang."))
            }
            Note(text: T("Amnesia stays OFF until you press Turn On. Take your time.",
                         "Amnesia tetap MATI sampai kamu tekan Aktifkan. Santai saja."),
                 icon: "power", color: .green)
        }
    }
}

// MARK: - Backup

struct BackupView: View {
    @EnvironmentObject var m: Model
    let back: () -> Void
    @State private var dest = Config.get("BACKUP_DEST", "drive")
    @State private var drives: [Drive] = []
    @State private var drive = Config.get("BACKUP_DRIVE")
    @State private var server = Config.get("BACKUP_SSH")
    @State private var cloud = Config.get("BACKUP_RCLONE", "gdrive:Amnesia")
    @State private var folders = Set(Config.get("BACKUP_FOLDERS", "Keep").split(separator: ",").map(String.init))
    @State private var extra = Config.get("BACKUP_FOLDERS", "Keep").split(separator: ",").map(String.init)
        .filter { !BackupView.defaults.contains($0) }
    @State private var provider = cloudProviders.first(where: { $0.id == Config.get("BACKUP_CLOUD", "drive") }) ?? cloudProviders[0]
    @State private var connected: [String] = []
    @State private var withVault = Config.get("BACKUP_VAULT") == "1"
    @State private var schedule = Config.get("BACKUP_SCHEDULE", "off")
    @State private var remember = Secret.exists
    @State private var pw = ""
    @State private var pw2 = ""
    @State private var status = lastBackupStatus()
    static let defaults = ["Keep", "Documents", "Desktop", "Downloads", "Pictures", "Music", "Movies"]
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
                            Toggle(f, isOn: Binding(get: { folders.contains(f) },
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
        Note(text: T("Sent with SSH + rsync, logging in with an SSH key (no password). Don't have one? "
                     + "Press Set Up SSH Key, just once.",
                     "Dikirim lewat SSH + rsync, login pakai kunci SSH (tanpa password). Belum punya? "
                     + "Tekan Siapkan Kunci SSH sekali saja."))
        HStack(spacing: 10) {
            Button { testSSH() } label: { Label(T("Test Connection", "Tes Koneksi"), systemImage: "bolt.horizontal.fill") }
                .buttonStyle(Pill(colors: Pal.logout))
            Button { setupSSH() } label: { Label(T("Set Up SSH Key", "Siapkan Kunci SSH"), systemImage: "key.fill") }
                .buttonStyle(Pill(colors: Pal.vault))
        }
        .disabled(host.isEmpty)
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
        Note(text: T("Just log in in your browser, no Terminal needed. S3, WebDAV, SFTP and 40+ more work too: "
                     + "set them up with rclone config, then type the remote name above.",
                     "Cukup login di browser, tanpa Terminal. S3, WebDAV, SFTP dan 40+ layanan lain juga bisa: "
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
            let path = url.path
            guard path.hasPrefix(P.home + "/"), !path.contains(",") else {
                info("Backup", T("Pick a folder inside your home folder (and without a comma in its name).",
                                 "Pilih folder di dalam folder home kamu (dan tanpa koma di namanya)."), error: true)
                continue
            }
            let rel = String(path.dropFirst(P.home.count + 1))
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
        if dest == "ssh" && !server.contains("@") {
            info("Backup", T("Type the server as user@host:folder.", "Isi server dengan format user@alamat:folder."), error: true); return false
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

    private func testSSH() {
        let h = host
        m.background(T("Connecting to \(h)…", "Menghubungi \(h)…"), {
            sh("/usr/bin/ssh", ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
                                "-o", "StrictHostKeyChecking=accept-new", h, "echo amnesia-ok"])
        }) { r in
            if r.out.contains("amnesia-ok") {
                info(T("Connected", "Koneksi berhasil"), T("\(h) is ready for backups.", "\(h) bisa dipakai untuk backup."))
            } else {
                info(T("Couldn't connect", "Koneksi gagal"), String(r.err.suffix(300))
                     + T("\n\nCheck the server address, then press Set Up SSH Key.",
                         "\n\nCek alamat server, lalu tekan Siapkan Kunci SSH."), error: true)
            }
        }
    }

    private func setupSSH() {
        openTerminal(T("SSH key for backups", "Kunci SSH untuk backup"), [
            "[ -f ~/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -N \"\" -f ~/.ssh/id_ed25519",
            "echo \"" + T("Type the server password ONCE (to install the key):",
                          "Masukkan password server SEKALI (untuk memasang kunci):") + "\"",
            "ssh-copy-id -i ~/.ssh/id_ed25519.pub \(shq(host))",
        ])
    }

    /// Cek remote rclone yang sudah terhubung (diam-diam).
    private func checkCloud() {
        m.quiet({ rcloneRemotes() }) { r in connected = r }
    }

    private func setupCloud() {
        let p = provider
        if remote.isEmpty { cloud = p.remote + ":Amnesia" }
        let name = remote
        m.background(T("Log in to \(p.name) in your browser…\n(Amnesia waits up to 5 minutes)",
                       "Login ke \(p.name) di browser…\n(Amnesia menunggu sampai 5 menit)"),
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
                Button { m.showTour() } label: {
                    Label(T("Show the welcome tour again", "Tampilkan tur perkenalan lagi"), systemImage: "sparkles")
                }
                .buttonStyle(Pill(colors: Pal.vault))
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
    @State private var groups: [DryGroup]?

    private var total: Int { (groups ?? []).reduce(0) { $0 + $1.items.count } }

    var body: some View {
        VStack(spacing: 14) {
            PageHeader(title: T("What Gets Deleted", "Yang Akan Dihapus"), icon: "eye.fill", colors: Pal.logout, back: { cancel() })
            if let a = m.pending {
                Card {
                    Note(text: T("\(a.title) is on hold so you can check first. ~/Keep, the Keep List and the "
                                 + "Profile Vault stay safe.",
                                 "\(a.title) ditahan sebentar supaya kamu bisa cek dulu. Isi ~/Keep, Keep List "
                                 + "dan Profile Vault tetap aman."), icon: "hand.raised.fill", color: .orange)
                }
            }
            if let g = groups {
                HStack {
                    Text(T("\(total) items", "\(total) item")).font(.system(size: 20, weight: .bold, design: .rounded))
                    Spacer()
                    Text(T("\(g.count) groups · click for details", "\(g.count) kelompok · klik untuk detail")).font(.system(size: 11)).foregroundStyle(.secondary)
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

    private func load() {
        groups = nil
        m.quiet({ dryRun() }) { g in groups = g }
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

// MARK: - App

@MainActor
enum Opener {
    static var open: (@MainActor () -> Void)?
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Hanya boleh jalan 1x: kalau sudah ada Amnesia lain yang jalan, pakai yang itu lalu keluar.
    func applicationWillFinishLaunching(_ notification: Notification) {
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != me }
        guard let other = others.first else { return }
        if !CommandLine.arguments.contains("--background"), let url = other.bundleURL {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
        exit(0)
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
        signal(SIGPIPE, SIG_IGN)   // program yang ditutup lebih cepat tidak boleh membuat app crash
    }

    var body: some Scene {
        Window("Amnesia", id: "main") {
            MainView().environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(background ? .suppressed : .presented)

        MenuBarExtra {
            MenuPanel().environmentObject(model)
        } label: {
            MenuIcon(state: model.state)
        }
        .menuBarExtraStyle(.window)
    }
}
