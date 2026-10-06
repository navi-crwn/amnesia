// Amnesia v5.5 — app Mac asli (SwiftUI): jendela utama + ikon status di menu bar.
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

// MARK: - Menjalankan program lain

struct Out {
    var code: Int32
    var out: String
    var err: String
}

final class DataBox: @unchecked Sendable { var data = Data() }

/// Jalankan program. Password dikirim lewat stdin, tidak pernah lewat argumen.
@discardableResult
func sh(_ exe: String, _ args: [String], input: String? = nil, cwd: String? = nil) -> Out {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    if let cwd = cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
    let o = Pipe(), e = Pipe(), i = Pipe()
    p.standardOutput = o
    p.standardError = e
    p.standardInput = i
    do { try p.run() } catch { return Out(code: -1, out: "", err: error.localizedDescription) }
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
        return .fail("vault.py tidak merespons.\n" + String(detail.suffix(300)))
    }
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
            key = "Keychain (password & login)"
        } else if kind == "HAPUS" {
            let comps = item.replacingOccurrences(of: "~/", with: "").split(separator: "/").map(String.init)
            let first = comps.first ?? item
            if first == "Library" && comps.count > 1 {
                key = "Library/" + comps[1]
            } else if first.hasPrefix(".") {
                key = "File & folder tersembunyi"
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
        case .shutdown: return "Matikan Mac"
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
        return Drive(name: n, free: String(format: "%.1f GB kosong", free / 1_073_741_824))
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

/// Jalankan backup.sh; password lewat stdin. Hasil: (berhasil, pesan).
func runBackup(_ pw: String, auto: Bool = false) -> (ok: Bool, msg: String) {
    let r = sh("/bin/bash", [P.backupSh] + (auto ? ["--auto"] : []), input: pw + "\n")
    let msg = (r.code == 0 ? r.out : r.err).trimmingCharacters(in: .whitespacesAndNewlines)
    return (r.code == 0, msg.isEmpty ? "backup.sh keluar dengan kode \(r.code)" : msg)
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
        + "\necho\necho \"Selesai. Kembali ke Amnesia, lalu tutup jendela ini.\"\n"
    try? text.write(toFile: path, atomically: true, encoding: .utf8)
    chmod(path, 0o700)
    NSWorkspace.shared.open(URL(fileURLWithPath: path))
}

// MARK: - Dialog

@MainActor
func confirm(_ title: String, _ text: String, ok: String = "Lanjut", danger: Bool = false) -> Bool {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = text
    a.alertStyle = danger ? .critical : .informational
    a.addButton(withTitle: ok)
    a.addButton(withTitle: "Batal")
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
        case .active: return "Amnesia Aktif"
        case .paused: return "Dijeda 1 Sesi"
        case .off: return "Amnesia Mati"
        }
    }

    var subtitle: String {
        switch self {
        case .active: return "Semua dibersihkan saat logout, restart & shutdown, lalu dicek ulang saat login."
        case .paused: return "Logout & login berikutnya tidak dibersihkan. Sesudahnya aktif lagi otomatis."
        case .off: return "Data TIDAK dibersihkan. Aktifkan untuk melindungi Mac ini."
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
        let lc = log.isEmpty ? "Belum pernah dibersihkan" : "Terakhir: " + log
        if lc != lastClean { lastClean = lc }
    }

    func refreshVault() {
        DispatchQueue.global().async {
            let r = vaultCall(["status"])
            Task { @MainActor in self.vault = r }
        }
    }

    /// Kerja di background tanpa overlay.
    func quiet<T>(_ work: @escaping @Sendable () -> T, done: @escaping @MainActor (T) -> Void) {
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
    func background<T>(_ msg: String, _ work: @escaping @Sendable () -> T,
                       done: @escaping @MainActor (T) -> Void) {
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
        let e = r.error ?? "Terjadi kesalahan."
        if e == "DOOMSDAY" {
            info("Vault dimusnahkan", "Vault telah dimusnahkan untuk melindungi data.", error: true)
        } else {
            info("Profile Vault", e, error: true)
        }
    }

    // --- aktif / mati ---

    func togglePower() {
        if state != .off {
            guard confirm("Matikan Amnesia?",
                          "Data tidak akan dibersihkan saat logout sampai kamu aktifkan lagi.",
                          ok: "Matikan", danger: true) else { return }
            deactivate()
        } else {
            guard confirm("Aktifkan Amnesia?",
                          "Mulai logout berikutnya, semua data di luar Keep List dan folder ~/Keep akan DIHAPUS "
                          + "saat logout/restart/shutdown, lalu dicek ulang saat login.\n\n"
                          + "Pindahkan file penting ke ~/Keep dulu. Sesi sekarang aman sampai kamu logout.",
                          ok: "Aktifkan", danger: true) else { return }
            if let err = activate() {
                info("Gagal mengaktifkan", err, error: true)
            } else {
                info("Amnesia AKTIF", "Sesi ini dibersihkan saat logout/restart/shutdown, lalu dicek ulang saat login.\n"
                     + "Folder ~/Keep tetap aman.")
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
            return "Tidak bisa menulis LaunchAgent: \(error.localizedDescription)"
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
            info("Dijeda 1 sesi", "Logout dan login berikutnya TIDAK dibersihkan.\n"
                 + "Logout sesudahnya otomatis dibersihkan lagi.")
        }
        refresh()
    }

    // --- simpan profil & logout ---

    func saveAndLogout() {
        guard let v = vault, v.ok, v.exists == true else {
            info("Profile Vault belum dibuat", "Buat vault dulu di menu Profile Vault.")
            return
        }
        let apps = v.apps ?? []
        guard !apps.isEmpty else {
            info("Simpan & Logout", "Belum ada data Chrome, Claude atau OpenCode di Mac ini.")
            return
        }
        guard confirm("Simpan Profil & Logout",
                      "Simpan profil \(apps.joined(separator: ", ")) ke vault, lalu logout?\n\n"
                      + "App tersebut akan ditutup dulu.", ok: "Simpan & Logout") else { return }
        background("Menyimpan profil ke vault…", { vaultCall(["snapshot"]) }) { r in
            if r.ok {
                self.allowQuit = true       // logout ini dari kita sendiri: jangan ditahan
                _ = vaultCall(["logout"])
            } else {
                info("Snapshot gagal", (r.error ?? "") + "\n\nLogout dibatalkan supaya profil tidak hilang.",
                     error: true)
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
            .help("Kembali")
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
                switch m.page {
                case .home: home
                case .settings: SettingsView(back: { goHome() })
                case .preview: PreviewView(back: { goHome() })
                case .vault: VaultView(back: { goHome() })
                case .keep: KeepView(back: { goHome() })
                case .backup: BackupView(back: { goHome() })
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
        .onAppear {
            Opener.open = { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
            m.refresh()
            m.refreshVault()
        }
    }

    private func goHome() { m.page = .home; m.refreshVault() }

    private var vaultSub: String {
        guard let v = m.vault else { return "Memuat…" }
        if !v.ok { return "Perlu dicek" }
        if v.exists != true { return "Belum dibuat" }
        if let man = v.manifest { return "Snapshot \(man.time)" }
        return "Siap, belum ada snapshot"
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
                    Text("Mac kamu lupa semuanya, kecuali yang kamu pilih.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { m.page = .settings } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.regularMaterial))
                }
                .buttonStyle(.plain)
                .help("Pengaturan")
            }
            HeroCard(state: m.state, lastClean: m.lastClean)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                      spacing: 14) {
                Tile(title: "Profile Vault", sub: vaultSub, icon: "lock.rectangle.stack.fill",
                     colors: Pal.vault) { m.page = .vault }
                Tile(title: "Simpan & Logout", sub: "Simpan login Chrome, Claude, OpenCode lalu logout",
                     icon: "rectangle.portrait.and.arrow.right", colors: Pal.logout) { m.saveAndLogout() }
                Tile(title: m.state == .paused ? "Batalkan Jeda" : "Jeda 1 Sesi",
                     sub: m.state == .off ? "Aktifkan Amnesia dulu" : "Lewati 1x logout & login berikutnya",
                     icon: "pause.fill", colors: Pal.pause) { m.togglePause() }
                    .disabled(m.state == .off)
                Tile(title: "Keep List", sub: "\(Keep.entries().count) item tidak dihapus",
                     icon: "pin.fill", colors: Pal.keep) { m.page = .keep }
                Tile(title: "Backup", sub: "Ke flashdisk, server atau cloud",
                     icon: "externaldrive.fill", colors: Pal.backup) { m.page = .backup }
                Tile(title: m.state == .off ? "Aktifkan" : "Matikan",
                     sub: m.state == .off ? "Mulai lindungi Mac ini" : "Hentikan pembersihan otomatis",
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
                        Card { Note(text: v.error ?? "Error", icon: "exclamationmark.triangle.fill", color: .red) }
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
            Text("Simpan login Chrome (Gmail, WhatsApp, Telegram), Claude dan OpenCode dalam 1 brankas "
                 + "terenkripsi. Setelah Mac dibersihkan, pulihkan semuanya dengan 1 password.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Note(text: "Password TIDAK bisa dipulihkan kalau lupa.", icon: "exclamationmark.triangle.fill",
                 color: .orange)
            Field(label: "Password vault (min. \(v.min ?? 12) karakter)", text: $pw)
            Field(label: "Ulangi password", text: $pw2)
        }
        Card {
            Field(label: "Kata panik (opsional)", text: $panic)
            Note(text: "Kalau kata ini diketik di kolom password, vault langsung dihapus total.")
            Toggle("Kata panik juga mengosongkan ~/Keep", isOn: Binding(get: { panicFull && !panic.isEmpty }, set: { panicFull = $0 }))
                .font(.system(size: 12)).disabled(panic.isEmpty)
        }
        Button { create() } label: { Label("Buat Vault", systemImage: "lock.fill") }
            .buttonStyle(Pill(colors: Pal.vault))
            .disabled(pw.isEmpty)
        Card {
            HStack(spacing: 10) {
                IconBadge(icon: "arrow.left.arrow.right", colors: Pal.backup, size: 30)
                Text("Pindah dari Mac lama?").font(.system(size: 14, weight: .semibold))
            }
            Text("Punya file backup Amnesia yang berisi Profile Vault? Ambil vault-nya dari file itu, "
                 + "tidak perlu buat vault baru.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Field(label: "Password backup", text: $backupPw)
            Button { importVault() } label: { Label("Ambil Vault dari Backup…", systemImage: "tray.and.arrow.down.fill") }
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
                    Text("Snapshot terakhir").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
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
                Note(text: "Vault siap, belum ada snapshot. Login ke app dulu, lalu tekan Snapshot.")
            }
        }
        if left < maxTry {
            Card {
                Note(text: "Sisa \(left)x percobaan. Salah lagi sampai habis = vault DIHAPUS PERMANEN.",
                     icon: "exclamationmark.octagon.fill", color: .red)
            }
        }
        Card {
            Field(label: "Password vault", text: $pw).onSubmit { restore() }
            Button { restore() } label: { Label("Restore Profil", systemImage: "arrow.counterclockwise") }
                .buttonStyle(Pill(colors: Pal.keep))
                .disabled(pw.isEmpty)
        }
        HStack(spacing: 10) {
            Button { snapshot(v) } label: { Label("Snapshot", systemImage: "camera.fill") }
                .buttonStyle(Pill(colors: Pal.logout))
            Button { showPanic = true } label: { Label("Kata Panik", systemImage: "flame.fill") }
                .buttonStyle(Pill(colors: Pal.vault))
            Button { deleteVault() } label: { Label("Hapus", systemImage: "trash.fill") }
                .buttonStyle(Pill(colors: Pal.danger))
        }
        Card {
            HStack(spacing: 10) {
                IconBadge(icon: "arrow.left.arrow.right", colors: Pal.backup, size: 30)
                Text("Pindah Mac").font(.system(size: 14, weight: .semibold))
            }
            Text("Login Chrome, Claude & WhatsApp dikunci oleh kunci Keychain milik Mac ini. Supaya tetap jalan "
                 + "di Mac baru, simpan kuncinya ke vault, lalu backup dengan Sertakan Profile Vault.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let k = v.keys {
                Note(text: "Kunci tersimpan \(k.time): \(k.apps.joined(separator: ", "))",
                     icon: "checkmark.circle.fill", color: .green)
            }
            HStack(spacing: 10) {
                Button { exportKeys() } label: { Label("Siapkan Pindah Mac", systemImage: "key.fill") }
                    .buttonStyle(Pill(colors: Pal.vault))
                Button { importKeys() } label: { Label("Pulihkan Kunci", systemImage: "key.horizontal.fill") }
                    .buttonStyle(Pill(colors: Pal.keep))
                    .disabled(pw.isEmpty || v.keys == nil)
            }
            Note(text: "Pulihkan Kunci hanya di Mac BARU, setelah Restore Profil. Pakai password vault di atas.")
        }
    }

    private var panicSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Atur Kata Panik").font(.system(size: 17, weight: .bold))
            Text("Kalau kata ini diketik di kolom password vault, vault dan semua snapshot langsung dihapus. "
                 + "Kosongkan untuk mematikan kata panik.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Field(label: "Password vault", text: $pw)
            Field(label: "Kata panik baru", text: $newPanic)
            Toggle("Juga kosongkan ~/Keep", isOn: $newPanicFull).font(.system(size: 12)).disabled(newPanic.isEmpty)
            HStack {
                Button("Batal") { showPanic = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Simpan") { savePanic() }.keyboardShortcut(.defaultAction).disabled(pw.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    private func create() {
        guard pw == pw2 else { info("Profile Vault", "Password tidak cocok.", error: true); return }
        let input = pw + "\n" + panic + "\n"
        let args = ["create"] + (panicFull && !panic.isEmpty ? ["full"] : [])
        m.background("Membuat kunci vault…", { vaultCall(args, input: input) }) { r in
            if r.ok {
                pw = ""; pw2 = ""; panic = ""
                info("Vault dibuat", "Login ke Chrome, Claude dan OpenCode seperti biasa, lalu tekan Snapshot "
                     + "(atau Simpan & Logout).")
            } else {
                m.vaultError(r)
            }
            m.refreshVault()
        }
    }

    private func restore() {
        guard !pw.isEmpty else { return }
        let input = pw + "\n"
        m.background("Memulihkan profil…", { vaultCall(["restore"], input: input) }) { r in
            pw = ""
            if r.ok {
                info("Profil dipulihkan", "\((r.apps ?? []).joined(separator: ", ")) siap dipakai.")
            } else {
                m.vaultError(r)
            }
            m.refreshVault()
        }
    }

    private func snapshot(_ v: VaultReply) {
        let apps = v.apps ?? []
        guard !apps.isEmpty else {
            info("Profile Vault", "Belum ada data Chrome, Claude atau OpenCode di Mac ini.")
            return
        }
        guard confirm("Snapshot", "Simpan profil \(apps.joined(separator: ", "))?\n\nApp tersebut akan ditutup dulu.",
                      ok: "Simpan") else { return }
        m.background("Menyimpan profil ke vault…", { vaultCall(["snapshot"]) }) { r in
            if !r.ok { m.vaultError(r) }
            m.refreshVault()
        }
    }

    private func savePanic() {
        let input = pw + "\n" + newPanic + "\n"
        let args = ["panic"] + (newPanicFull && !newPanic.isEmpty ? ["full"] : [])
        let word = newPanic
        showPanic = false
        m.background("Memeriksa password…", { vaultCall(args, input: input) }) { r in
            pw = ""; newPanic = ""
            if r.ok {
                info("Kata Panik", word.isEmpty ? "Kata panik dimatikan." : "Kata panik disimpan.")
            } else {
                m.vaultError(r)
            }
            m.refreshVault()
        }
    }

    private func exportKeys() {
        guard confirm("Siapkan Pindah Mac",
                      "Kunci Keychain (Chrome, Claude, WhatsApp, dll.) disimpan terenkripsi ke vault.\n\n"
                      + "macOS akan bertanya beberapa kali. Ketik password login Mac lalu klik Always Allow / "
                      + "Selalu Izinkan.", ok: "Mulai") else { return }
        m.background("Menyimpan kunci Keychain ke vault…\nJawab dialog izin dari macOS.",
                     { vaultCall(["exportkeys"]) }) { r in
            if r.ok {
                info("Siap pindah Mac", "Kunci \((r.apps ?? []).joined(separator: ", ")) tersimpan.\n\n"
                     + "Sekarang buat backup dengan Sertakan Profile Vault dicentang.")
            } else {
                m.vaultError(r)
            }
            m.refreshVault()
        }
    }

    private func importKeys() {
        guard confirm("Pulihkan Kunci?",
                      "Kunci Keychain Chrome, Claude, dll. di Mac ini DIGANTI dengan kunci dari Mac lama. "
                      + "Lakukan hanya di Mac baru, setelah Restore Profil.\n\nApp terkait akan ditutup dulu.",
                      ok: "Pulihkan", danger: true) else { return }
        let input = pw + "\n"
        m.background("Memasang kunci ke Keychain…", { vaultCall(["importkeys"], input: input) }) { r in
            pw = ""
            if r.ok {
                info("Kunci dipulihkan", "\((r.apps ?? []).joined(separator: ", ")) siap dibuka dengan login lama.")
            } else {
                m.vaultError(r)
            }
            m.refreshVault()
        }
    }

    private func importVault() {
        let panel = NSOpenPanel()
        panel.title = "Pilih file backup Amnesia (.7z)"
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let file = panel.url?.path else { return }
        let input = backupPw + "\n"
        m.background("Mengambil vault dari backup…", {
            sh("/bin/bash", [P.backupSh, "--restore-vault", file], input: input)
        }) { r in
            backupPw = ""
            if r.code == 0 {
                info("Vault dipulihkan", "Langkah berikutnya:\n1. Restore Profil (password vault).\n"
                     + "2. Pulihkan Kunci (password vault).")
            } else {
                info("Gagal", r.err.replacingOccurrences(of: "GAGAL: ", with: ""), error: true)
            }
            m.refreshVault()
        }
    }

    private func deleteVault() {
        guard confirm("Hapus Vault?", "Vault dan semua snapshot profil dihapus.\n\nTidak bisa dibatalkan.",
                      ok: "Hapus", danger: true) else { return }
        m.background("Menghapus vault…", { vaultCall(["delete"]) }) { r in
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

    var body: some View {
        VStack(spacing: 14) {
            PageHeader(title: "Keep List", icon: "pin.fill", colors: Pal.keep, back: back)
            Note(text: "Yang ada di sini TIDAK dihapus saat logout. Folder ~/Keep dan ~/.amnesia selalu aman.")
                .frame(maxWidth: .infinity, alignment: .leading)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(entries, id: \.self) { e in row(e) }
                }
            }
            .scrollIndicators(.never)
            Button { adding = true } label: { Label("Tambah Folder", systemImage: "plus") }
                .buttonStyle(Pill(colors: Pal.keep))
        }
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
        let shown = isKey ? "Kunci: " + String(e.dropFirst(9)) : "~/" + e
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
            .help("Hapus dari Keep List")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.regularMaterial))
    }

    private func remove(_ e: String) {
        guard confirm("Hapus dari Keep List?", "\(e)\n\nDatanya akan ikut dibersihkan saat logout berikutnya.",
                      ok: "Hapus", danger: true) else { return }
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
            Text("Tambah ke Keep List").font(.system(size: 17, weight: .bold))
            TextField("Cari…", text: $query).textFieldStyle(.roundedBorder)
            if cands.isEmpty {
                Text("Tidak ada folder lain yang bisa ditambahkan.").foregroundStyle(.secondary)
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
                Button("Batal") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Tambah (\(picked.count))") {
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
    @State private var withVault = Config.get("BACKUP_VAULT") == "1"
    @State private var schedule = Config.get("BACKUP_SCHEDULE", "off")
    @State private var remember = Secret.exists
    @State private var pw = ""
    @State private var pw2 = ""
    @State private var status = lastBackupStatus()
    private let all = ["Keep", "Documents", "Desktop", "Downloads", "Pictures", "Music", "Movies"]

    private var host: String { String(server.split(separator: ":", maxSplits: 1).first ?? "") }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                PageHeader(title: "Backup", icon: "externaldrive.fill", colors: Pal.backup, back: back)
                if !status.isEmpty {
                    Card {
                        Note(text: "Terakhir: " + status,
                             icon: status.contains("OK:") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                             color: status.contains("OK:") ? .green : .red)
                    }
                }
                Card {
                    Text("Tujuan").font(.system(size: 13, weight: .semibold))
                    Picker("", selection: $dest) {
                        Text("Flashdisk / SSD").tag("drive")
                        Text("Server SSH").tag("ssh")
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
                    Text("Yang di-backup").font(.system(size: 13, weight: .semibold))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading,
                              spacing: 8) {
                        ForEach(all, id: \.self) { f in
                            Toggle(f, isOn: Binding(get: { folders.contains(f) },
                                                    set: { on in if on { folders.insert(f) } else { folders.remove(f) } }))
                                .toggleStyle(.checkbox)
                        }
                    }
                    Toggle("Sertakan Profile Vault (untuk Pindah Mac)", isOn: $withVault)
                        .toggleStyle(.checkbox)
                }
                Card {
                    Field(label: remember ? "Password backup (kosongkan = pakai yang tersimpan)" : "Password backup",
                          text: $pw)
                    if !pw.isEmpty { Field(label: "Ulangi password", text: $pw2) }
                    Toggle("Simpan password di Keychain (wajib untuk backup terjadwal)", isOn: $remember)
                        .toggleStyle(.checkbox).font(.system(size: 12))
                    Note(text: "File .7z dikunci AES-256, nama file di dalamnya juga. Tanpa password, backup "
                         + "tidak bisa dibuka.", icon: "exclamationmark.triangle.fill", color: .orange)
                }
                Card {
                    Text("Jadwal").font(.system(size: 13, weight: .semibold))
                    Picker("", selection: $schedule) {
                        Text("Mati").tag("off")
                        Text("Harian").tag("daily")
                        Text("Mingguan").tag("weekly")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Note(text: "Berjalan sendiri selama ikon Amnesia ada di menu bar. Kalau tujuannya flashdisk, "
                         + "backup jalan saat flashdisk tercolok.")
                }
                HStack(spacing: 10) {
                    Button { if save() { info("Backup", "Pengaturan disimpan.") } } label: {
                        Label("Simpan", systemImage: "checkmark")
                    }
                    .buttonStyle(Pill(colors: Pal.gray))
                    Button { start() } label: { Label("Backup Sekarang", systemImage: "arrow.up.doc.fill") }
                        .buttonStyle(Pill(colors: Pal.backup))
                }
            }
        }
        .scrollIndicators(.never)
        .onAppear { load() }
    }

    @ViewBuilder private var driveBox: some View {
        HStack {
            Text("Drive yang tercolok").font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Button { load() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).help("Cari drive lagi")
        }
        if drives.isEmpty {
            Note(text: "Tidak ada drive eksternal. Colok SSD/flashdisk lalu tekan ↻.",
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
        Field(label: "Server (user@alamat:folder), mis. ivan@vps.com:backup", text: $server, secure: false)
        Note(text: "Dikirim lewat SSH + rsync, login pakai kunci SSH (tanpa password). Belum punya? "
             + "Tekan Siapkan Kunci SSH sekali saja.")
        HStack(spacing: 10) {
            Button { testSSH() } label: { Label("Tes Koneksi", systemImage: "bolt.horizontal.fill") }
                .buttonStyle(Pill(colors: Pal.logout))
            Button { setupSSH() } label: { Label("Siapkan Kunci SSH", systemImage: "key.fill") }
                .buttonStyle(Pill(colors: Pal.vault))
        }
        .disabled(host.isEmpty)
    }

    @ViewBuilder private var cloudBox: some View {
        Field(label: "Tujuan rclone (remote:folder)", text: $cloud, secure: false)
        Note(text: "Pakai rclone. Google Drive: tekan tombol di bawah, login di browser, selesai. "
             + "Dropbox, OneDrive, S3 juga bisa lewat perintah rclone config di Terminal.")
        Button { setupDrive() } label: { Label("Hubungkan Google Drive", systemImage: "icloud.and.arrow.up.fill") }
            .buttonStyle(Pill(colors: Pal.logout))
    }

    private func load() {
        drives = listDrives()
        if !drives.contains(where: { $0.name == drive }) { drive = drives.first?.name ?? drive }
        status = lastBackupStatus()
    }

    /// Simpan pengaturan ke settings.conf (+ password ke Keychain kalau dipilih).
    private func save() -> Bool {
        let sel = all.filter { folders.contains($0) }
        guard !sel.isEmpty || withVault else { info("Backup", "Pilih minimal 1 folder.", error: true); return false }
        if !pw.isEmpty && pw != pw2 { info("Backup", "Password tidak cocok.", error: true); return false }
        if dest == "ssh" && !server.contains("@") {
            info("Backup", "Isi server dengan format user@alamat:folder.", error: true); return false
        }
        if dest == "rclone" && !cloud.contains(":") {
            info("Backup", "Isi tujuan cloud dengan format remote:folder, mis. gdrive:Amnesia.", error: true)
            return false
        }
        if remember {
            if !pw.isEmpty && !Secret.set(pw) {
                info("Backup", "Password gagal disimpan ke Keychain.", error: true); return false
            }
            if pw.isEmpty && !Secret.exists {
                info("Backup", "Isi password dulu supaya bisa disimpan.", error: true); return false
            }
        } else {
            Secret.delete()
            if schedule != "off" {
                info("Backup", "Backup terjadwal butuh password tersimpan. Centang Simpan password di Keychain.",
                     error: true)
                return false
            }
        }
        Config.set("BACKUP_DEST", dest)
        Config.set("BACKUP_DRIVE", drive)
        Config.set("BACKUP_SSH", server)
        Config.set("BACKUP_RCLONE", cloud)
        Config.set("BACKUP_FOLDERS", sel.joined(separator: ","))
        Config.set("BACKUP_VAULT", withVault ? "1" : "0")
        Config.set("BACKUP_SCHEDULE", schedule)
        return true
    }

    private func start() {
        guard save() else { return }
        let typed = pw
        guard !typed.isEmpty || remember else { info("Backup", "Isi password backup.", error: true); return }
        let to = dest == "drive" ? drive : (dest == "ssh" ? host : cloud)
        m.background("Backup ke \(to)…\nJangan cabut drive / matikan internet.", { () -> (ok: Bool, msg: String) in
            guard let p = typed.isEmpty ? Secret.get() : typed else { return (false, "Password tersimpan tidak bisa dibaca.") }
            return runBackup(p)
        }) { r in
            status = lastBackupStatus()
            if r.ok {
                pw = ""; pw2 = ""
                info("Backup berhasil", r.msg.replacingOccurrences(of: "OK: ", with: "")
                     + "\n\nChecksum SHA256 dicatat di backup_checksums.txt.")
            } else {
                info("Backup gagal", r.msg.replacingOccurrences(of: "GAGAL: ", with: ""), error: true)
            }
        }
    }

    private func testSSH() {
        let h = host
        m.background("Menghubungi \(h)…", {
            sh("/usr/bin/ssh", ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
                                "-o", "StrictHostKeyChecking=accept-new", h, "echo amnesia-ok"])
        }) { r in
            if r.out.contains("amnesia-ok") {
                info("Koneksi berhasil", "\(h) bisa dipakai untuk backup.")
            } else {
                info("Koneksi gagal", String(r.err.suffix(300))
                     + "\n\nCek alamat server, lalu tekan Siapkan Kunci SSH.", error: true)
            }
        }
    }

    private func setupSSH() {
        openTerminal("Kunci SSH untuk backup", [
            "[ -f ~/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -N \"\" -f ~/.ssh/id_ed25519",
            "echo \"Masukkan password server SEKALI (untuk memasang kunci):\"",
            "ssh-copy-id -i ~/.ssh/id_ed25519.pub \(shq(host))",
        ])
    }

    private func setupDrive() {
        let remote = String(cloud.split(separator: ":", maxSplits: 1).first ?? "gdrive")
        openTerminal("Hubungkan Google Drive", [
            "command -v rclone >/dev/null || brew install rclone",
            "echo \"Browser akan terbuka. Login Google lalu klik Izinkan.\"",
            "rclone config create \(shq(remote.isEmpty ? "gdrive" : remote)) drive",
        ])
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
                PageHeader(title: "Pengaturan", icon: "gearshape.fill", colors: Pal.gray, back: back)
                row("Snapshot otomatis saat logout",
                    "Login kamu disimpan ke vault setiap logout, restart atau shutdown, walau tidak lewat tombol "
                    + "Simpan & Logout. Butuh vault yang sudah dibuat.",
                    "camera.fill", Pal.vault, $auto) { Setting.autoSnapshot.set($0) }
                row("Notifikasi setelah login",
                    "Muncul pemberitahuan bahwa Mac sudah bersih, plus pengingat untuk restore profil.",
                    "bell.badge.fill", Pal.pause, $notify) { Setting.notify.set($0) }
                row("Cek dulu sebelum logout",
                    "Saat logout, restart atau shutdown, Amnesia menahan sebentar dan menampilkan daftar yang "
                    + "akan dihapus. Kamu pilih Lanjut atau Batal.",
                    "eye.fill", Pal.logout, $preview) { Setting.preview.set($0) }
                Button { m.page = .preview } label: {
                    Label("Lihat yang akan dihapus sekarang", systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(Pill(colors: Pal.backup))
            }
        }
        .scrollIndicators(.never)
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
            PageHeader(title: "Yang Akan Dihapus", icon: "eye.fill", colors: Pal.logout, back: { cancel() })
            if let a = m.pending {
                Card {
                    Note(text: "\(a.title) ditahan sebentar supaya kamu bisa cek dulu. Isi ~/Keep, Keep List "
                         + "dan Profile Vault tetap aman.", icon: "hand.raised.fill", color: .orange)
                }
            }
            if let g = groups {
                HStack {
                    Text("\(total) item").font(.system(size: 20, weight: .bold, design: .rounded))
                    Spacer()
                    Text("\(g.count) kelompok · klik untuk detail").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(g) { grp in group(grp) }
                    }
                }
                .scrollIndicators(.never)
            } else {
                Spacer()
                ProgressView("Mengecek…")
                Spacer()
            }
            if let a = m.pending {
                HStack(spacing: 10) {
                    Button { cancel() } label: { Label("Batal", systemImage: "xmark") }
                        .buttonStyle(Pill(colors: Pal.gray))
                    Button { m.continueQuit() } label: { Label("Lanjut \(a.title)", systemImage: "checkmark") }
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
                    Text("…dan \(grp.items.count - 200) lagi").font(.system(size: 11)).foregroundStyle(.secondary)
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
        if v.exists != true { return "Belum dibuat" }
        if let man = v.manifest { return man.time }
        return "Belum ada snapshot"
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
                InfoChip(icon: "pin.fill", label: "Keep List", value: "\(Keep.entries().count) item",
                         color: Color(hex: 0x14B8A6))
            }

            if let b = m.busy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(b).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                MenuTile(title: "Buka Amnesia", icon: "macwindow", colors: [Color(hex: 0x22D3EE), Color(hex: 0x6366F1)]) {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                MenuTile(title: "Simpan Profil & Logout", icon: "rectangle.portrait.and.arrow.right",
                         colors: Pal.logout) { m.saveAndLogout() }
                    .disabled(m.busy != nil)
                MenuTile(title: m.state == .paused ? "Batalkan Jeda" : "Jeda 1 Sesi", icon: "pause.fill",
                         colors: Pal.pause) { m.togglePause() }
                    .disabled(m.state == .off)
                MenuTile(title: m.state == .off ? "Aktifkan" : "Matikan", icon: "power",
                         colors: m.state == .off ? Pal.on : Pal.danger) { m.togglePower() }
            }

            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Amnesia v\(appVersion)").font(.system(size: 11, weight: .semibold))
                    Text("Menutup app tidak menghentikan pembersihan.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Tutup App") { NSApp.terminate(nil) }
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
