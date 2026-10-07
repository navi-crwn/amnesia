// Amnesia v5.10 — app Mac asli (SwiftUI): jendela utama + ikon status di menu bar.
// Dibuild oleh build.sh (swiftc dari Command Line Tools, tanpa Xcode).
// Logika berat tetap di ~/.amnesia: clean.sh, agent.sh, vault.py (dipanggil lewat Process).
import AppKit
import QuickLookThumbnailing
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
            // hanya bagian akhir: backup panjang menulis baris kemajuan tiap detik
            onErr?(String(decoding: errBox.data.suffix(8192), as: UTF8.self))
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

struct PerApp: Decodable {
    let time: String?
    let size_mb: Double?
    let legacy: Bool?
}

struct Manifest: Decodable {
    let apps: [String]
    let time: String
    let size_mb: Double
    /// v5.10: snapshot per app (waktu & ukuran masing-masing)
    let per_app: [String: PerApp]?
}

/// Hasil cek otomatis setelah restore.
struct RestoreCheck: Decodable {
    let app: String
    let ok: Bool
    let note: String
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
    let skip: [String]?
    let folders: [String]?
    let patterns: [String: [String]]?
    let sizes: [String: Double]?
    let checks: [RestoreCheck]?

    static func fail(_ msg: String) -> VaultReply {
        VaultReply(ok: false, error: msg, exists: nil, manifest: nil, attempts: nil, max: nil, min: nil, apps: nil,
                   keys: nil, skip: nil, folders: nil, patterns: nil, sizes: nil, checks: nil)
    }
}

/// Pekerjaan yang bisa dibatalkan (tombol Batal di layar tunggu).
final class JobBox: @unchecked Sendable {
    var p: Process?
    var cancelled = false
    var stalled = false
    var lastTick = Date()
}

/// "PROGRESS 42 save 2/3 Chrome" -> (0.42, "save", 2, 3, "Chrome")
func parseProgress(_ text: String) -> (pct: Double, stage: String, i: Int, n: Int, rest: String)? {
    let tail = text.suffix(600).split(separator: "\n").reversed()
    guard let line = tail.first(where: { $0.hasPrefix("PROGRESS ") }) else { return nil }
    let parts = line.split(separator: " ", maxSplits: 4).map(String.init)
    guard parts.count >= 2, let n = Double(parts[1]) else { return nil }
    let stage = parts.count > 2 ? parts[2] : ""
    let ord = (parts.count > 3 ? parts[3] : "1/1").split(separator: "/").compactMap { Int($0) }
    return (min(max(n / 100, 0), 1), stage, ord.first ?? 1, ord.count > 1 ? ord[1] : 1, parts.count > 4 ? parts[4] : "")
}

/// Teks kemajuan Profile Vault yang mudah dibaca, sesuai app yang sedang dikerjakan.
func vaultStepText(_ stage: String, _ i: Int, _ n: Int, _ name: String) -> String {
    switch stage {
    case "quit": return T("Closing the apps first…", "Menutup app dulu…")
    case "save": return T("Saving \(name)… \(i) of \(n)", "Menyimpan \(name)… \(i) dari \(n)")
    case "restore": return T("Unpacking \(name)… \(i) of \(n)", "Membongkar \(name)… \(i) dari \(n)")
    case "swap": return T("Putting the files back…", "Mengembalikan file…")
    case "check": return T("Checking the result…", "Mengecek hasilnya…")
    default: return ""
    }
}

/// progress: dipanggil dengan (0…1, teks langkah) setiap vault.py menulis baris "PROGRESS ...".
/// job: kalau diisi, tombol Batal bisa menghentikan vault.py (SIGTERM; vault.py berhenti dengan rapi).
func vaultCall(_ args: [String], input: String = "", job: JobBox? = nil,
               progress: (@Sendable (Double, String) -> Void)? = nil) -> VaultReply {
    let onErr: (@Sendable (String) -> Void)? = progress.map { cb in
        { @Sendable text in
            if let p = parseProgress(text) { cb(p.pct, vaultStepText(p.stage, p.i, p.n, p.rest)) }
        }
    }
    let r = sh(P.python, [P.vaultPy] + args, input: input, onStart: { p in job?.p = p }, onErr: onErr)
    let last = r.out.split(separator: "\n").last.map(String.init) ?? ""
    do {
        return try JSONDecoder().decode(VaultReply.self, from: Data(last.utf8))
    } catch {
        let clean = r.err.split(separator: "\n").filter { !$0.hasPrefix("PROGRESS ") }.joined(separator: "\n")
        let detail = clean.isEmpty ? "\(error)" : clean
        return .fail(T("vault.py is not responding.\n", "vault.py tidak merespons.\n") + String(detail.suffix(300)))
    }
}

// MARK: - Mesin Amnesia (script di dalam app → ~/.amnesia)

enum Engine {
    static let files = ["clean.sh", "agent.sh", "vault.py", "backup.sh", "uninstall.sh", "keep.example.conf"]

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

    /// "Lanjut Tanpa Izin" dipilih: tidak ditanya lagi sampai app dibuka ulang.
    @MainActor static var fdaSkipped = false

    static func openFullDiskSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }

    /// Tutup lalu buka lagi Amnesia (izin Full Disk Access baru berlaku setelah app dibuka ulang).
    /// Tidak boleh di tengah snapshot/restore/backup: tunggu sampai selesai.
    @MainActor static func relaunch() {
        if let b = Model.shared.busy {
            info(T("Wait a moment", "Tunggu sebentar"),
                 T("Amnesia is still working:\n\(b)\n\nQuit & Reopen after it's done.",
                   "Amnesia masih bekerja:\n\(b)\n\nTutup & Buka Lagi setelah selesai."))
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1.5; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? p.run()
        Model.shared.allowQuit = true
        NSApp.terminate(nil)
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

    /// v5.13: Amnesia otomatis jalan di menu bar setiap login (juga saat Amnesia mati).
    /// LaunchAgent kecil terpisah: hanya membuka app di background, tidak membersihkan apa pun.
    enum LoginItem {
        static let label = "com.amnesia.menubar"
        static let plist = P.home + "/Library/LaunchAgents/com.amnesia.menubar.plist"

        /// Samakan file plist dengan pengaturan OPEN_AT_LOGIN. Berlaku mulai login berikutnya.
        static func sync() {
            let fm = FileManager.default
            guard Setting.openAtLogin.isOn else {
                if fm.fileExists(atPath: plist) {
                    try? fm.removeItem(atPath: plist)
                    sh(P.launchctl, ["bootout", "\(P.domain)/\(label)"])
                }
                return
            }
            let dict: [String: Any] = [
                "Label": label,
                "ProgramArguments": ["/usr/bin/open", "-g", "-b", "com.amnesia.controlpanel", "--args", "--background"],
                "RunAtLoad": true,
            ]
            if let d = NSDictionary(contentsOfFile: plist), d.isEqual(to: dict) { return }
            try? fm.createDirectory(atPath: (plist as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            if let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0) {
                try? data.write(to: URL(fileURLWithPath: plist), options: .atomic)
            }
        }
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
            // Google Drive menyimpan datanya di Application Support/Google/DriveFS (bukan nama app-nya)
            if bid == "com.google.drivefs", fm.fileExists(atPath: lib + "Application Support/Google/DriveFS") {
                p.append("Library/Application Support/Google/DriveFS")
            }
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

// MARK: - Akun & data Apple (bagian khusus di Keep List, otomatis dicentang)

/// Data Apple yang dulu ikut terhapus saat logout (akun iCloud, Foto, Notes, dll.).
/// Disimpan di Keep List, bukan vault: akun Apple terikat ke Mac ini, dan Foto bisa sangat besar.
struct AppleItem: Identifiable {
    let id: String
    let title: String
    let sub: String
    let icon: String
    let paths: [String]
}

var appleItems: [AppleItem] {
    [
        AppleItem(id: "icloud", title: T("iCloud / Apple ID account", "Akun iCloud / Apple ID"),
                  sub: T("Stay signed in to iCloud. Otherwise iCloud Drive downloads everything again after each logout.",
                         "Tetap login iCloud. Kalau tidak, iCloud Drive mengunduh ulang semuanya setiap logout."),
                  icon: "icloud.fill",
                  paths: ["Library/Application Support/iCloud", "Library/Preferences/MobileMeAccounts.plist",
                          "Library/Group Containers/group.com.apple.iCloudDrive", "Library/Containers/com.apple.CloudDocs*"]),
        AppleItem(id: "photos", title: T("Photos", "Foto"),
                  sub: T("Your Photos library. Photos that are only on this Mac would be lost.",
                         "Library Foto kamu. Foto yang hanya ada di Mac ini bisa hilang."),
                  icon: "photo.on.rectangle.angled",
                  paths: ["Pictures/Photos Library.photoslibrary", "Library/Containers/com.apple.Photos*"]),
        AppleItem(id: "notes", title: "Notes", sub: T("Notes saved \"On My Mac\" (iCloud notes come back by themselves).",
                                                        "Catatan \"On My Mac\" (catatan iCloud kembali sendiri)."),
                  icon: "note.text",
                  paths: ["Library/Group Containers/group.com.apple.notes*", "Library/Containers/com.apple.Notes*"]),
        AppleItem(id: "mail", title: "Mail", sub: T("Mail accounts and mail stored on this Mac.", "Akun Mail dan email yang tersimpan di Mac ini."),
                  icon: "envelope.fill",
                  paths: ["Library/Containers/com.apple.mail*", "Library/Group Containers/group.com.apple.mail*",
                          "Library/Group Containers/group.com.apple.MailPersonaStorage"]),
        AppleItem(id: "calendar", title: T("Calendar & Reminders", "Calendar & Reminders"),
                  sub: T("Local calendars and reminders.", "Kalender dan pengingat lokal."), icon: "calendar",
                  paths: ["Library/Containers/com.apple.iCal*", "Library/Group Containers/group.com.apple.calendar*",
                          "Library/Containers/com.apple.reminders*", "Library/Group Containers/group.com.apple.reminders*"]),
        AppleItem(id: "contacts", title: T("Contacts", "Kontak"), sub: T("Contacts stored on this Mac.", "Kontak yang tersimpan di Mac ini."),
                  icon: "person.crop.circle.fill",
                  paths: ["Library/Application Support/AddressBook", "Library/Containers/com.apple.AddressBook*"]),
        AppleItem(id: "messages", title: "Messages", sub: T("iMessage settings on this Mac.", "Pengaturan iMessage di Mac ini."),
                  icon: "message.fill",
                  paths: ["Library/Containers/com.apple.iChat*", "Library/Containers/com.apple.MobileSMS*"]),
        AppleItem(id: "shortcuts", title: "Shortcuts", sub: T("Shortcuts you made yourself.", "Shortcut buatan kamu sendiri."),
                  icon: "square.2.layers.3d.fill",
                  paths: ["Library/Group Containers/group.is.workflow.shortcuts", "Library/Containers/com.apple.shortcuts*"]),
        AppleItem(id: "git", title: T("Git settings", "Pengaturan git"), sub: T("Your git name and email.", "Nama dan email git kamu."),
                  icon: "chevron.left.forwardslash.chevron.right",
                  paths: [".gitconfig", ".config/git"]),
    ]
}

/// Semua path bagian Apple (untuk menyembunyikannya dari daftar Keep List biasa).
var applePaths: Set<String> { Set(appleItems.flatMap(\.paths)) }

enum AppleKeep {
    static func isOn(_ a: AppleItem) -> Bool {
        let e = Set(Keep.entries())
        return a.paths.allSatisfy { e.contains($0) }
    }

    static func set(_ a: AppleItem, _ on: Bool) {
        if on {
            let e = Set(Keep.entries())
            let add = a.paths.filter { !e.contains($0) }
            if !add.isEmpty { Keep.add(add) }
        } else {
            for p in a.paths { Keep.remove(p) }
        }
    }

    /// Sekali saja (v5.10): semua dicentang otomatis, supaya aman secara default. Sesudahnya pilihan kamu dihormati.
    static func applyDefaultsOnce() {
        guard Config.get("APPLE_KEEP").isEmpty else { return }
        for a in appleItems { set(a, true) }
        Config.set("APPLE_KEEP", "1")
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
    case openAtLogin = "OPEN_AT_LOGIN", vaultLight = "VAULT_LIGHT"     // v5.13

    var isOn: Bool { Config.get(rawValue) != "0" }
    func set(_ on: Bool) { Config.set(rawValue, on ? "1" : "0") }
}

// MARK: - Dry-run (lihat yang akan dihapus)

/// 1 baris dari clean.sh --dry-run: path (relatif dari home) atau nama item Keychain.
struct DryEntry: Sendable {
    let keychain: Bool
    let web: Bool
    let rel: String
}

enum DryIcon: Hashable, Sendable {
    case symbol(String)      // ikon SF Symbol
    case app(String)         // ikon app (path .app)
    case file(String)        // ikon jenis file (path lengkap), plus thumbnail kalau perlu
}

struct DryItem: Identifiable, Hashable, Sendable {
    let rel: String
    let title: String
    let detail: String
    let icon: DryIcon
    let thumb: Bool          // buat thumbnail asli (hanya Desktop, Downloads, Documents, Pictures)
    let keychain: Bool
    var id: String { (keychain ? "kc:" : "") + rel }
    var shown: String { keychain ? "Keychain: " + rel : "~/" + rel }
}

struct DryGroup: Identifiable, Sendable {
    let id: String
    let name: String
    let note: String
    let symbol: String
    let system: Bool         // disembunyikan secara default
    let items: [DryItem]
}

/// Jalankan clean.sh --dry-run dan simpan hasilnya di report.txt (dihapus lagi saat pembersihan sungguhan).
func dryRun() -> [DryEntry] {
    let r = sh("/bin/bash", [P.a + "/clean.sh", "logout", "--dry-run"])
    if FileManager.default.createFile(atPath: P.report, contents: Data(r.out.utf8), attributes: [.posixPermissions: 0o600]) == false {
        try? r.out.write(toFile: P.report, atomically: true, encoding: .utf8)
    }
    return parseDry(r.out)
}

/// Laporan terakhir yang tersimpan (langsung tampil, tanpa menunggu).
func cachedReport() -> (entries: [DryEntry], time: Date)? {
    guard let t = try? String(contentsOfFile: P.report, encoding: .utf8),
          let d = (try? FileManager.default.attributesOfItem(atPath: P.report))?[.modificationDate] as? Date
    else { return nil }
    return (parseDry(t), d)
}

func parseDry(_ text: String) -> [DryEntry] {
    text.split(separator: "\n").compactMap { line -> DryEntry? in
        let parts = line.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let kind = String(parts[0])
        let item = parts[1].trimmingCharacters(in: .whitespaces)
        if kind.hasPrefix("KEYCHAIN") { return DryEntry(keychain: true, web: kind == "KEYCHAIN-WEB", rel: item) }
        guard kind == "HAPUS" else { return nil }
        return DryEntry(keychain: false, web: false, rel: item.hasPrefix("~/") ? String(item.dropFirst(2)) : item)
    }
}

/// Cari app pemilik sebuah folder data (mis. "net.whatsapp.WhatsApp" -> WhatsApp). Hasil di-cache.
final class AppLookup: @unchecked Sendable {
    static let shared = AppLookup()
    private var cache: [String: (name: String, path: String)?] = [:]
    private let lock = NSLock()

    func find(_ raw: String) -> (name: String, path: String)? {
        lock.lock(); defer { lock.unlock() }
        if let c = cache[raw] { return c }
        let r = search(raw)
        cache[raw] = r
        return r
    }

    private func search(_ raw: String) -> (name: String, path: String)? {
        var k = raw
        for suf in [".plist", ".savedState", ".binarycookies"] where k.hasSuffix(suf) { k = String(k.dropLast(suf.count)) }
        if k.hasPrefix("group.") { k = String(k.dropFirst(6)) }
        // "UBF8T346G9.ms" = ID tim developer + nama: ID-nya dibuang
        if let r = k.range(of: #"^[A-Z0-9]{10}\."#, options: .regularExpression) { k.removeSubrange(r) }
        var parts = k.split(separator: ".").map(String.init)
        while parts.count >= 2 {
            if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: parts.joined(separator: ".")) {
                return (FileManager.default.displayName(atPath: u.path).replacingOccurrences(of: ".app", with: ""), u.path)
            }
            parts.removeLast()
        }
        for d in ["/Applications", P.realHome + "/Applications"] {
            let p = d + "/" + k + ".app"
            if FileManager.default.fileExists(atPath: p) { return (k, p) }
        }
        return nil
    }
}

/// Jenis data menurut folder Library-nya.
func libKind(_ sub: String) -> String {
    switch sub {
    case "Application Support", "Containers": return T("data", "data")
    case "Group Containers": return T("shared data", "data bersama")
    case "Preferences": return T("settings", "setting")
    case "Caches": return "cache"
    case "Logs": return "log"
    case "Saved Application State": return T("last open windows", "jendela terakhir")
    case "HTTPStorages", "WebKit": return T("web data", "data web")
    case "Cookies": return "cookies"
    default: return sub
    }
}

/// Nama yang mudah dibaca untuk file/folder tersembunyi di home.
func dotTitle(_ n: String) -> String {
    switch n {
    case ".zsh_history", ".bash_history": return T("Terminal history", "Riwayat Terminal")
    case ".zsh_sessions": return T("Terminal sessions", "Sesi Terminal")
    case ".python_history", ".node_repl_history", ".sqlite_history", ".psql_history", ".mysql_history":
        return T("Command history", "Riwayat perintah") + " (\(n))"
    case ".lesshst", ".viminfo", ".wget-hsts": return T("Small history file", "File riwayat kecil") + " (\(n))"
    case ".npm", ".cache": return T("Downloaded cache", "Cache unduhan") + " (\(n))"
    default: return n
    }
}

/// path cocok dengan pola (glob), atau salah satunya ada di dalam yang lain
func dryMatch(_ rel: String, _ pattern: String) -> Bool {
    fnmatch(pattern, rel, 0) == 0 || rel.hasPrefix(pattern + "/") || pattern.hasPrefix(rel + "/")
}

/// Kelompokkan berdasarkan ARTI (bukan nama folder teknis). patterns = app yang ikut snapshot vault.
func categorize(_ entries: [DryEntry], patterns: [String: [String]]) -> [DryGroup] {
    let fm = FileManager.default
    let userDirs = ["Desktop", "Downloads", "Documents", "Pictures", "Movies", "Music", "Public", ".Trash"]
    let thumbDirs: Set<String> = ["Desktop", "Downloads", "Documents", "Pictures"]
    let traceSubs: Set<String> = ["Caches", "Logs", "HTTPStorages", "WebKit", "Cookies"]
    let appSubs: Set<String> = ["Application Support", "Containers", "Group Containers", "Preferences", "Saved Application State"]
    let apple = appleItems
    let keepName = KeepDir.name
    let kept = Keep.entries().map { $0.lowercased() }
    /// App ini (sebagian) ada di Keep List? Dipakai untuk keterangan "login tetap aman".
    func inKeep(_ bundleOrName: String, _ appName: String?) -> Bool {
        let keys = [bundleOrName.lowercased(), appName?.lowercased()].compactMap { $0 }.filter { $0.count > 2 }
        return kept.contains { e in keys.contains { k in e.contains(k) } }
    }
    var g: [String: [DryItem]] = [:]
    func put(_ key: String, _ item: DryItem) { g[key, default: []].append(item) }

    for e in entries {
        if e.keychain {
            put("keychain", DryItem(rel: e.rel, title: e.rel,
                                    detail: e.web ? T("website password", "password website") : T("app password or login", "password atau login app"),
                                    icon: .symbol("key.fill"), thumb: false, keychain: true))
            continue
        }
        let rel = e.rel
        let full = P.home + "/" + rel
        let comps = rel.split(separator: "/").map(String.init)
        // pintasan buatan Amnesia sendiri (dibuat ulang otomatis): tidak perlu ditampilkan
        if (rel == "Desktop/Amnesia.app" || rel == "Desktop/" + keepName),
           (try? fm.destinationOfSymbolicLink(atPath: full)) != nil { continue }
        if let app = patterns.first(where: { kv in kv.value.contains { p in dryMatch(rel, p) } })?.key {
            let kind = comps.count > 1 && comps[0] == "Library" ? libKind(comps[1]) : T("files", "file")
            put("vault", DryItem(rel: rel, title: app + " · " + kind, detail: T("comes back with Restore", "kembali lewat Restore"),
                                 icon: .symbol("lock.fill"), thumb: false, keychain: false))
            continue
        }
        if let a = apple.first(where: { ai in ai.paths.contains { p in dryMatch(rel, p) } }) {
            put("apple", DryItem(rel: rel, title: a.title, detail: a.sub, icon: .symbol(a.icon), thumb: false, keychain: false))
            continue
        }
        guard let first = comps.first else { continue }
        if userDirs.contains(first) {
            let parent = comps.dropLast().joined(separator: "/")
            put("files", DryItem(rel: rel, title: comps.last ?? rel,
                                 detail: first == ".Trash" ? T("Trash", "Trash") : parent,
                                 icon: .file(full), thumb: thumbDirs.contains(first), keychain: false))
            continue
        }
        if first.hasPrefix(".") {
            put("traces", DryItem(rel: rel, title: dotTitle(first), detail: "~/" + rel, icon: .symbol("terminal.fill"),
                                  thumb: false, keychain: false))
            continue
        }
        if first == "Library", comps.count >= 2 {
            let sub = comps[1]
            let name = comps.count >= 3 ? (comps[2] == "ByHost" && comps.count >= 4 ? comps[3] : comps[2]) : sub
            let isApple = name.hasPrefix("com.apple") || name.hasPrefix("group.com.apple") || name == "Apple"
                || name.contains(".com.apple.")
            if sub == "Safari" {
                put("traces", DryItem(rel: rel, title: T("Safari history & data", "Riwayat & data Safari"), detail: "~/" + rel,
                                      icon: .symbol("safari.fill"), thumb: false, keychain: false))
                continue
            }
            if traceSubs.contains(sub) && !isApple {
                let owner = comps.count >= 3 ? AppLookup.shared.find(name) : nil
                let safe = comps.count >= 3 && inKeep(name, owner?.name)
                put("traces", DryItem(rel: rel, title: (owner?.name ?? (comps.count >= 3 ? name : sub)) + " · " + libKind(sub),
                                      detail: safe ? T("only \(libKind(sub)): the app is in your Keep List, its login stays",
                                                       "hanya \(libKind(sub)): app ini ada di Keep List, login-nya tetap aman")
                                                   : "~/" + rel, icon: owner.map { o in DryIcon.app(o.path) } ?? DryIcon.symbol("clock.fill"),
                                      thumb: false, keychain: false))
                continue
            }
            if appSubs.contains(sub) && comps.count >= 3 && !isApple {
                let owner = AppLookup.shared.find(name)
                let partly = inKeep(name, owner?.name)
                put("apps", DryItem(rel: rel, title: (owner?.name ?? name) + " · " + libKind(sub),
                                    detail: partly ? T("extra \(libKind(sub)) not in the Keep List; the app's main data stays",
                                                       "\(libKind(sub)) tambahan yang tidak ada di Keep List; data utama app tetap")
                                                   : "~/" + rel,
                                    icon: owner.map { o in DryIcon.app(o.path) } ?? DryIcon.symbol("app.dashed"),
                                    thumb: false, keychain: false))
                continue
            }
        }
        put("system", DryItem(rel: rel, title: comps.last ?? rel, detail: "~/" + rel, icon: .symbol("gearshape.fill"),
                              thumb: false, keychain: false))
    }

    let meta: [(String, String, String, String, Bool)] = [
        ("vault", T("Restored from your vault", "Dipulihkan dari vault"),
         T("Deleted at logout, back with your vault password (Restore).", "Dihapus saat logout, kembali dengan password vault (Restore)."),
         "lock.rectangle.stack.fill", false),
        ("files", T("Your files", "File kamu"),
         T("Move anything you need to your Keep folder (\(KeepDir.shown)) first.", "Pindahkan yang masih perlu ke folder Keep (\(KeepDir.shown)) dulu."),
         "doc.fill", false),
        ("apple", T("Apple accounts & sync", "Akun & sinkronisasi Apple"),
         T("Switched off in Keep List → Apple accounts & data.", "Dimatikan di Keep List → Akun & data Apple."),
         "applelogo", false),
        ("apps", T("App data & settings", "Data & setting app"),
         T("These apps start fresh after logout, like a new install.", "App ini mulai dari awal setelah logout, seperti baru dipasang."),
         "square.grid.2x2.fill", false),
        ("keychain", T("Keychain (saved passwords & logins)", "Keychain (password & login tersimpan)"),
         T("Saved passwords that aren't in the Keep List.", "Password tersimpan yang tidak ada di Keep List."), "key.fill", false),
        ("traces", T("History, caches & logs", "Riwayat, cache & log"),
         T("Traces of what you did. Safe to delete.", "Jejak aktivitas kamu. Aman dihapus."), "clock.arrow.circlepath", false),
        ("system", T("macOS system data (made again automatically)", "Data sistem macOS (dibuat ulang otomatis)"),
         T("Small files macOS rebuilds by itself at login. Safe to delete.", "File kecil yang dibuat ulang macOS saat login. Aman dihapus."),
         "gearshape.2.fill", true),
    ]
    return meta.compactMap { m in
        guard let items = g[m.0], !items.isEmpty else { return nil }
        let sorted = m.0 == "files" ? items : items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return DryGroup(id: m.0, name: m.1, note: m.2, symbol: m.3, system: m.4, items: sorted)
    }
}

/// Ukuran beberapa path (relatif dari home) yang mudah dibaca, mis. "1,2 GB".
func pathsSize(_ rels: [String]) -> String {
    guard !rels.isEmpty else { return "" }
    var kb = 0
    for chunk in stride(from: 0, to: rels.count, by: 200) {
        let part = rels[chunk..<min(chunk + 200, rels.count)].map { P.home + "/" + $0 }
        kb += sh("/usr/bin/du", ["-sk"] + part, timeout: 60).out.split(separator: "\n")
            .compactMap { Int($0.split(separator: "\t").first ?? "") }.reduce(0, +)
    }
    return ByteCountFormatter.string(fromByteCount: Int64(kb) * 1024, countStyle: .file)
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

/// Browser bawaan Mac (http). Mac baru tanpa browser default: Safari.
func defaultBrowser() -> URL? {
    NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
}

func openInBrowser(_ url: URL) {
    if defaultBrowser() != nil, NSWorkspace.shared.open(url) { return }
    let safari = URL(fileURLWithPath: "/Applications/Safari.app")
    NSWorkspace.shared.open([url], withApplicationAt: safari, configuration: NSWorkspace.OpenConfiguration())
}

/// Hubungkan cloud tanpa Terminal: pasang rclone kalau perlu, buka halaman login di browser bawaan Mac,
/// lalu cek koneksinya. clientID/secret: akses Google milik user sendiri (Lanjutan).
/// onURL: alamat halaman login, untuk tombol "Buka halaman login lagi". job: tombol Batal.
/// Hasil: pesan error, "CANCELLED", atau nil kalau berhasil. Token tidak pernah ditampilkan atau dicatat.
func connectCloud(_ p: CloudProvider, remote: String, clientID: String = "", secret: String = "",
                  job: JobBox? = nil, onURL: (@Sendable (URL) -> Void)? = nil) -> String? {
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
    let own = clientID.isEmpty ? [] : ["client_id", clientID, "client_secret", secret]
    // rclone membuka halaman login di browser bawaan Mac sendiri (perintah "open").
    // Alamatnya juga ditangkap, untuk tombol cadangan kalau browser tidak terbuka.
    final class Seen: @unchecked Sendable { var url = false }
    let seen = Seen()
    let c = sh(r, ["config", "create", remote, p.id] + own, timeout: 300,
               onStart: { job?.p = $0 },
               onErr: { text in
                   guard !seen.url,
                         let m = text.range(of: #"http://127\.0\.0\.1:53682/auth\?state=[A-Za-z0-9_-]+"#, options: .regularExpression),
                         let url = URL(string: String(text[m])) else { return }
                   seen.url = true
                   onURL?(url)
               })
    // catatan untuk mencari penyebab kalau gagal (tanpa token: baris berisi token/kurung kurawal dibuang)
    let diag = c.err.split(separator: "\n").filter { l in
        !l.localizedCaseInsensitiveContains("token") && !l.contains("{") && !l.contains("}") && !l.contains("secret")
    }.suffix(40).joined(separator: "\n")
    FileManager.default.createFile(atPath: P.a + "/cloud.log",
                                   contents: Data("\(Date()) \(p.name) code \(c.code)\n\(diag)\n".utf8),
                                   attributes: [.posixPermissions: 0o600])
    if job?.cancelled == true { return "CANCELLED" }
    guard c.code == 0, sh(r, ["lsd", remote + ":"], timeout: 60).code == 0 else {
        return T("\(p.name) isn't connected. The login wasn't finished in the browser (or took longer than 5 minutes). "
                 + "Press Connect to try again. (Details: ~/.amnesia/cloud.log)",
                 "\(p.name) belum terhubung. Login di browser belum selesai (atau lebih dari 5 menit). "
                 + "Tekan Hubungkan untuk mencoba lagi. (Detail: ~/.amnesia/cloud.log)")
    }
    return nil
}

/// Nama akun cloud yang terhubung (kalau layanan itu memberitahukannya), mis. "kamu@gmail.com".
func cloudUser(_ remote: String) -> String? {
    guard let r = rcloneBin() else { return nil }
    let o = sh(r, ["config", "userinfo", remote + ":", "--json"], timeout: 20)
    guard o.code == 0, let d = try? JSONSerialization.jsonObject(with: Data(o.out.utf8)) as? [String: Any] else { return nil }
    for k in ["Email", "Login", "Name", "email", "login", "name"] {
        if let v = d[k] as? String, !v.isEmpty { return v }
    }
    return nil
}

// MARK: - Google Drive lewat app resmi (Google Drive for Desktop)

/// Folder "My Drive" dari app Google Drive for Desktop (kalau terpasang & sudah login).
func googleDriveFolder() -> (path: String, account: String)? {
    let fm = FileManager.default
    let base = P.home + "/Library/CloudStorage"
    let skip: Set<String> = ["Other computers", "Shared drives", "Komputer lain", "Drive bersama", "Icon\r"]
    for d in ((try? fm.contentsOfDirectory(atPath: base)) ?? []).sorted() where d.hasPrefix("GoogleDrive-") {
        let inner = ((try? fm.contentsOfDirectory(atPath: base + "/" + d)) ?? []).sorted()
        let my = inner.first(where: { $0 == "My Drive" })
            ?? inner.first(where: { n in
                var dir: ObjCBool = false
                return !n.hasPrefix(".") && !skip.contains(n)
                    && fm.fileExists(atPath: base + "/" + d + "/" + n, isDirectory: &dir) && dir.boolValue
            })
        if let my { return (base + "/" + d + "/" + my, String(d.dropFirst("GoogleDrive-".count))) }
    }
    if fm.fileExists(atPath: "/Volumes/GoogleDrive/My Drive") { return ("/Volumes/GoogleDrive/My Drive", "Google Drive") }
    return nil
}

/// Folder akun Google Drive sudah ada (berarti sudah login), walau isinya belum bisa dibuka
/// (app Google Drive masih menyiapkan/menyinkronkan, "Operation timed out").
func googleDriveSignedIn() -> Bool {
    let base = P.home + "/Library/CloudStorage"
    return ((try? FileManager.default.contentsOfDirectory(atPath: base)) ?? []).contains { $0.hasPrefix("GoogleDrive-") }
}

func googleDriveInstalled() -> Bool {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.drivefs") != nil
        || FileManager.default.fileExists(atPath: "/Applications/Google Drive.app")
}

/// Data app Google Drive ikut Keep List, supaya app-nya tidak logout setiap Mac dibersihkan.
let googleDriveKeep = ["Library/Application Support/Google/DriveFS", "Library/Group Containers/*google.drivefs*",
                       "Library/Containers/com.google.drivefs*", "Library/Preferences/com.google.drivefs*",
                       "keychain:*DriveFS*", "keychain:*drivefs*"]

/// Format server yang aman dipakai: user@host atau user@host:folder (tanpa spasi & karakter aneh).
func validServer(_ s: String) -> Bool {
    s.range(of: #"^[A-Za-z0-9._-]+@[A-Za-z0-9.-]+(:[A-Za-z0-9._/~-]*)?$"#, options: .regularExpression) != nil
}

/// Waktu yang mudah dibaca, mis. "sisa ± 3 menit".
func etaText(_ secs: Double) -> String {
    let s = max(Int(secs.rounded()), 1)
    if s < 60 { return T("about \(s) s left", "sisa ± \(s) detik") }
    if s < 3600 { return T("about \(s / 60) min left", "sisa ± \(s / 60) menit") }
    return T("about \(s / 3600) h \(s % 3600 / 60) min left", "sisa ± \(s / 3600) jam \(s % 3600 / 60) menit")
}

func durationText(_ secs: Double) -> String {
    let s = max(Int(secs.rounded()), 1)
    if s < 60 { return T("\(s) seconds", "\(s) detik") }
    if s < 3600 { return T("\(s / 60) minutes", "\(s / 60) menit") }
    return T("\(s / 3600) h \(s % 3600 / 60) min", "\(s / 3600) jam \(s % 3600 / 60) menit")
}

/// Hubungkan server SSH tanpa Terminal. Kalau kunci SSH belum diterima server, password dipakai SEKALI
/// untuk memasang kunci (lewat SSH_ASKPASS, file sementara 0600 yang langsung dihapus). Password tidak disimpan.
/// Folder tujuan dibuat dan DIUJI bisa ditulis (tanpa sudo). Lalu kecepatan upload diukur (2 MB).
/// forgetOldKey: hapus catatan kunci server lama (setelah user setuju, misalnya server diinstal ulang).
/// hostChanged = true kalau kunci server berbeda dari yang dulu; app lalu bertanya dulu ke user.
func connectSSH(_ server: String, port: Int = 22, password: String, forgetOldKey: Bool = false)
    -> (ok: Bool, msg: String, hostChanged: Bool) {
    let parts = server.split(separator: ":", maxSplits: 1).map(String.init)
    let host = parts.first ?? ""
    if forgetOldKey {
        let name = host.split(separator: "@").last.map(String.init) ?? host
        sh("/usr/bin/ssh-keygen", ["-R", port == 22 ? name : "[\(name)]:\(port)"])
    }
    let rpath = parts.count > 1 && !parts[1].isEmpty ? parts[1] : "amnesia-backup"
    let base = ["-p", String(port), "-o", "ConnectTimeout=15", "-o", "StrictHostKeyChecking=accept-new"]
    let fm = FileManager.default
    let key = P.home + "/.ssh/id_ed25519"
    func whereIs() -> Out {
        sh("/usr/bin/ssh", base + ["-o", "BatchMode=yes", host,
                                   "mkdir -p -- \(rpath) 2>/dev/null && cd -- \(rpath) && touch .amnesia-write-test 2>/dev/null "
                                   + "&& rm -f .amnesia-write-test && pwd || echo AMNESIA_NOWRITE"], timeout: 40)
    }
    var w = whereIs()
    if w.code != 0 && (w.err.contains("IDENTIFICATION HAS CHANGED") || w.err.contains("Host key verification failed")) {
        return (false, T("\(host) has a different identity than before. That's normal if the server was reinstalled. "
                         + "If not, someone may be pretending to be your server.",
                         "Identitas \(host) berbeda dari sebelumnya. Wajar kalau server baru diinstal ulang. "
                         + "Kalau tidak, bisa jadi ada pihak lain yang menyamar jadi server kamu."), true)
    }
    if w.code != 0 {
        if w.err.contains("Could not resolve") || w.err.contains("timed out") || w.err.contains("refused") {
            return (false, T("Can't reach \(host) on port \(port). Check the address, the port and your internet.",
                             "\(host) di port \(port) tidak bisa dihubungi. Cek alamat, port dan internet kamu.")
                    + "\n\n" + String(w.err.suffix(200)), false)
        }
        guard !password.isEmpty else {
            return (false, T("This server doesn't know Amnesia's key yet. Type the server password once, then press Connect.",
                             "Server ini belum kenal kunci Amnesia. Ketik password server sekali, lalu tekan Hubungkan."), false)
        }
        if !fm.fileExists(atPath: key) {
            try? fm.createDirectory(atPath: P.home + "/.ssh", withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
            let g = sh("/usr/bin/ssh-keygen", ["-t", "ed25519", "-N", "", "-q", "-f", key, "-C", "amnesia"])
            guard g.code == 0 else { return (false, T("Couldn't make an SSH key: ", "Gagal membuat kunci SSH: ") + g.err, false) }
        }
        guard let pub = try? String(contentsOfFile: key + ".pub", encoding: .utf8) else {
            return (false, T("Couldn't read ~/.ssh/id_ed25519.pub", "Tidak bisa membaca ~/.ssh/id_ed25519.pub"), false)
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
                    : String(r.err.suffix(300)), false)
        }
        w = whereIs()
        guard w.code == 0 else {
            return (false, T("The key is installed, but logging in with it failed: ", "Kunci sudah dipasang, tapi login pakai kunci gagal: ")
                    + String(w.err.suffix(200)), false)
        }
    }
    if !keepMatches(".ssh/id_ed25519", Keep.entries()) { Keep.add([".ssh"]) }   // kunci tidak ikut terhapus saat logout
    if w.out.contains("AMNESIA_NOWRITE") {
        return (false, T("Connected, but this account can't write to \"\(rpath)\" on the server (it needs admin rights). "
                         + "Pick a folder in your home on the server instead, e.g. \(host):backup. Amnesia never uses sudo.",
                         "Terhubung, tapi akun ini tidak bisa menulis ke \"\(rpath)\" di server (butuh hak admin). "
                         + "Pilih folder di home server saja, mis. \(host):backup. Amnesia tidak pernah memakai sudo."), false)
    }
    let path = w.out.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n").last ?? rpath
    // tes kecepatan upload: kirim 1 MB lalu 5 MB acak (tidak disimpan di server). Selisih waktunya = waktu untuk
    // 4 MB tambahan, jadi waktu membuka koneksi SSH (bisa beberapa detik) tidak ikut terhitung. Kalau selisihnya
    // terlalu kecil untuk dipercaya, pakai waktu total 5 MB (angkanya jadi lebih rendah, bukan terlalu tinggi).
    func send(_ n: Int) -> Double? {
        let t0 = Date()
        let r = sh("/bin/sh", ["-c", "head -c \(n) /dev/urandom | /usr/bin/ssh \"$@\" 'cat > /dev/null'", "sh"]
                   + base + ["-o", "BatchMode=yes", host], timeout: 120)
        return r.code == 0 ? Date().timeIntervalSince(t0) : nil
    }
    var bps: Double? = nil
    if let small = send(1_000_000), let big = send(5_000_000) {
        let d = big - small
        bps = d >= 0.5 ? 4_000_000 / d : 5_000_000 / max(big, 0.5)
    }
    var speed = ""
    if let bps {
        let kb = Int(bps / 1000), mbit = String(format: "%.1f", bps * 8 / 1_000_000)
        speed = T("\n\nUpload speed: about \(kb) KB/s (\(mbit) Mbps), a rough estimate. A 100 MB backup takes about "
                  + "\(durationText(100_000_000 / bps)), sometimes less: the connection often speeds up during a real backup.",
                  "\n\nKecepatan upload: sekitar \(kb) KB/s (\(mbit) Mbps), perkiraan kasar. Backup 100 MB butuh sekitar "
                  + "\(durationText(100_000_000 / bps)), kadang lebih cepat: koneksi sering makin kencang saat backup sungguhan.")
    }
    return (true, T("Connected to \(host), no password needed from now on.\n\nBackups go to this folder on the server "
                    + "(tested, it can be written to):\n\(path)",
                    "Terhubung ke \(host), mulai sekarang tanpa password.\n\nBackup masuk ke folder ini di server "
                    + "(sudah dites, bisa ditulis):\n\(path)") + speed, false)
}

/// Kecepatan transfer (dirata-rata), untuk teks "1,2 MB/s · sisa ± 15 detik".
final class SpeedMeter: @unchecked Sendable {
    private var stage = ""
    private var lastT = Date()
    private var lastB: Double = 0
    var speed: Double = 0          // byte per detik

    func update(stage s: String, done: Double) {
        let now = Date()
        if s != stage { stage = s; lastT = now; lastB = done; speed = 0; return }
        let dt = now.timeIntervalSince(lastT)
        guard dt >= 1, done >= lastB else { return }
        let inst = (done - lastB) / dt
        speed = speed == 0 ? inst : speed * 0.7 + inst * 0.3
        lastT = now
        lastB = done
    }
}

/// Teks kemajuan backup, mis. "2/2 Mengunggah… · 1,2 MB/s · sisa ± 15 detik".
func backupStepText(_ stage: String, _ done: Double, _ total: Double, _ speed: Double) -> String {
    switch stage {
    case "compress": return T("1/2 Locking the files (encrypting)…", "1/2 Mengunci file (enkripsi)…")
    case "copy", "upload":
        var t = stage == "copy" ? T("2/2 Copying…", "2/2 Menyalin…") : T("2/2 Uploading…", "2/2 Mengunggah…")
        if speed > 0 {
            t += " · " + ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file) + "/s"
            if total > done { t += " · " + etaText((total - done) / speed) }
        }
        return t
    default: return ""
    }
}

/// Jalankan backup.sh; password lewat stdin. job: tombol Batal + penjaga macet (10 menit tanpa kemajuan = dihentikan).
func runBackup(_ pw: String, auto: Bool = false, job: JobBox? = nil,
               progress: (@Sendable (Double, String) -> Void)? = nil) -> (ok: Bool, msg: String, code: Int32) {
    let jb = job ?? JobBox()
    let meter = SpeedMeter()
    jb.lastTick = Date()
    let r = sh("/bin/bash", [P.backupSh] + (auto ? ["--auto"] : []), input: pw + "\n",
               onStart: { p in
                   jb.p = p
                   DispatchQueue.global(qos: .utility).async {
                       while p.isRunning {
                           Thread.sleep(forTimeInterval: 15)
                           if p.isRunning && Date().timeIntervalSince(jb.lastTick) > 600 {
                               jb.stalled = true
                               p.terminate()
                               return
                           }
                       }
                   }
               },
               onErr: { text in
                   guard let pr = parseProgress(text) else { return }
                   jb.lastTick = Date()
                   let nums = pr.rest.split(separator: " ").compactMap { Double($0) }
                   let total = nums.count > 1 ? nums[1] : 0
                   let done = nums.first.map { $0 > 0 ? $0 : pr.pct * total } ?? pr.pct * total
                   meter.update(stage: pr.stage, done: done)
                   progress?(pr.pct, backupStepText(pr.stage, done, total, meter.speed))
               })
    let errText = r.err.split(separator: "\n").filter { !$0.hasPrefix("PROGRESS ") && $0 != "CANCELLED" }
        .joined(separator: "\n")
    let msg = (r.code == 0 ? r.out : errText).trimmingCharacters(in: .whitespacesAndNewlines)
    return (r.code == 0, msg.isEmpty ? T("backup.sh exited with code \(r.code)", "backup.sh keluar dengan kode \(r.code)") : msg, r.code)
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

/// Jendela utama Amnesia (atau sheet yang sedang terbuka di atasnya), tempat popup ditempelkan.
@MainActor
func alertWindow() -> NSWindow? {
    var w = NSApp.windows.first { $0.isVisible && $0.canBecomeMain && !($0 is NSPanel) && $0.frame.width >= 400 }
    while let sheet = w?.attachedSheet { w = sheet }
    return w
}

/// Popup menempel di jendela Amnesia (turun dari atas jendela), bukan di tengah layar.
/// Kalau jendela tidak terbuka (hanya ikon menu bar), popup biasa di tengah layar.
@MainActor
func runAlert(_ a: NSAlert) -> NSApplication.ModalResponse {
    NSApp.activate(ignoringOtherApps: true)
    if Shots.on { return a.runModal() }
    // v5.13: jendela belum terbuka (hanya ikon menu bar) → buka dulu, supaya popup bisa menempel di sana
    if alertWindow() == nil, let open = Opener.open {
        open()
        let until = Date(timeIntervalSinceNow: 1.5)
        while alertWindow() == nil && Date() < until { pump() }
    }
    guard let w = alertWindow() else { return a.runModal() }
    // v5.13: tunggu jawaban TANPA NSApp.runModal. runModal menahan permintaan logout/restart/shutdown
    // dari macOS sampai popup ditutup, sehingga "Cancel" Amnesia datang terlambat (shutdown tetap jalan).
    // Event diproses di mode biasa, jadi permintaan shutdown langsung dijawab walau popup terbuka.
    var result: NSApplication.ModalResponse?
    a.beginSheetModal(for: w) { r in result = r }
    while result == nil { pump() }
    return result ?? .abort
}

/// Proses 1 event (klik, ketik, permintaan logout dari macOS) di mode biasa, maksimal 0,2 detik menunggu.
@MainActor
private func pump() {
    if let e = NSApp.nextEvent(matching: .any, until: Date(timeIntervalSinceNow: 0.2), inMode: .default, dequeue: true) {
        NSApp.sendEvent(e)
    }
}

@MainActor
func confirm(_ title: String, _ text: String, ok: String = T("Continue", "Lanjut"), danger: Bool = false) -> Bool {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = text
    a.alertStyle = danger ? .critical : .informational
    a.addButton(withTitle: ok)
    a.addButton(withTitle: T("Cancel", "Batal"))
    if danger { a.buttons.first?.hasDestructiveAction = true }
    return runAlert(a) == .alertFirstButtonReturn
}

@MainActor
func info(_ title: String, _ text: String, error: Bool = false) {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = text
    a.alertStyle = error ? .warning : .informational
    a.addButton(withTitle: "OK")
    _ = runAlert(a)
}

/// Izin Akses Disk Penuh dicek SEKALI sebelum snapshot/restore, supaya macOS tidak memunculkan
/// banyak popup izin (atau minta "Tutup & Buka Lagi") di tengah proses. Hasil: boleh lanjut atau tidak.
@MainActor
func ensureFullDisk() -> Bool {
    if Engine.hasFullDisk || Shots.on || Engine.fdaSkipped { return true }
    let a = NSAlert()
    a.messageText = T("Allow Full Disk Access first", "Izinkan Akses Disk Penuh dulu")
    a.informativeText = T("Without it, macOS asks again and again while Amnesia works, and may ask you to "
                          + "\"Quit & Reopen\" in the middle of a snapshot.\n\n"
                          + "1. Press Open Settings and switch on Amnesia.\n"
                          + "2. macOS asks to Quit & Reopen: that's fine now, nothing is running.\n\n"
                          + "Pressed \"Limit Access\" or \"Don't Allow\" by mistake? Open System Settings → Privacy & Security "
                          + "→ Full Disk Access, switch Amnesia on, then Quit & Reopen Amnesia.",
                          "Tanpa izin ini, macOS bertanya berkali-kali selama Amnesia bekerja, dan bisa meminta "
                          + "\"Tutup & Buka Lagi\" di tengah snapshot.\n\n"
                          + "1. Tekan Buka Pengaturan lalu nyalakan Amnesia.\n"
                          + "2. macOS minta Tutup & Buka Lagi: aman sekarang, tidak ada yang sedang jalan.\n\n"
                          + "Terlanjur menekan \"Limit Access\" atau \"Don't Allow\"? Buka System Settings → Privacy & Security "
                          + "→ Full Disk Access, nyalakan Amnesia, lalu Tutup & Buka Lagi Amnesia.")
    a.addButton(withTitle: T("Open Settings", "Buka Pengaturan"))
    a.addButton(withTitle: T("Continue Without", "Lanjut Tanpa Izin"))
    a.addButton(withTitle: T("Cancel", "Batal"))
    switch runAlert(a) {
    case .alertFirstButtonReturn:
        Engine.openFullDiskSettings()
        return false
    case .alertSecondButtonReturn:
        Engine.fdaSkipped = true          // tidak ditanya lagi sampai app dibuka ulang
        return true
    default:
        return false
    }
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
    /// Kemajuan kerja berat (0…1), tampil sebagai progress bar di overlay. nil = tidak diketahui.
    @Published var progress: Double?
    /// Langkah yang sedang dikerjakan, mis. "Menyimpan Chrome… 1 dari 3".
    @Published var progressText = ""
    /// Pekerjaan yang sedang jalan dan bisa dibatalkan (tombol Batal di layar tunggu).
    @Published var job: JobBox?
    /// Login cloud: halaman login di browser (tombol cadangan "Buka halaman login lagi" di layar tunggu).
    @Published var loginURL: URL?
    nonisolated static let progressSink: @Sendable (Double, String) -> Void = { p, text in
        Task { @MainActor in
            let m = Model.shared
            m.progress = p
            if !text.isEmpty { m.progressText = text }
            // saat file dipindahkan ke tempatnya, Batal tidak bisa lagi
            if text == vaultStepText("swap", 1, 1, "") || text == vaultStepText("check", 1, 1, "") { m.job = nil }
        }
    }

    /// Tombol Batal: hentikan proses yang sedang jalan (script-nya berhenti dengan rapi).
    func cancelJob() {
        guard let j = job else { return }
        j.cancelled = true
        j.p?.terminate()
        progressText = T("Cancelling…", "Membatalkan…")
        job = nil
    }
    /// Laporan "yang akan dihapus": disiapkan di background, jadi halaman Preview langsung tampil.
    @Published var report: [DryGroup]?
    /// Hasil mentah clean.sh --dry-run (dikelompokkan ulang kalau isi vault berubah).
    var rawReport: [DryEntry]?
    private var groupedWith: [String: [String]]?
    @Published var reportTime: Date?
    @Published var reportBusy = false
    private var reportTimer: Timer?
    private var timer: Timer?
    private var backupTimer: Timer?
    private var backupRunning = false

    init() {
        Engine.install()
        AppleKeep.applyDefaultsOnce()        // v5.10: "Akun & data Apple" otomatis dicentang (sekali saja)
        if let c = cachedReport() { rawReport = c.entries; reportTime = c.time; regroup() }
        if Shots.on { state = .active; refreshVault(); return }    // mode screenshot: tanpa timer & backup
        Agent.migrate()
        Agent.LoginItem.sync()
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
        quiet({ dryRun() }) { e in
            self.rawReport = e
            self.reportTime = Date()
            self.reportBusy = false
            self.regroup(force: true)
        }
    }

    /// Kelompokkan laporan berdasarkan arti (di background: mencari ikon app butuh waktu).
    func regroup(force: Bool = false) {
        guard let raw = rawReport else { return }
        let pats = vault?.patterns ?? [:]
        if !force && groupedWith == pats { return }
        groupedWith = pats
        quiet({ categorize(raw, patterns: pats) }) { g in self.report = g }
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
            Task { @MainActor in
                self.vault = r
                self.regroup()
            }
        }
    }

    func finishOnboarding() {
        Config.set("ONBOARDED", "1")
        Config.set("TOUR_STEP", "0")
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
    /// job: kalau diisi, layar tunggu punya tombol Batal.
    func background<R>(_ msg: String, job: JobBox? = nil, _ work: @escaping @Sendable () -> R,
                       done: @escaping @MainActor (R) -> Void) {
        busy = msg
        progress = nil
        progressText = ""
        loginURL = nil
        self.job = job
        DispatchQueue.global(qos: .userInitiated).async {
            let r = work()
            Task { @MainActor in
                self.busy = nil
                self.progress = nil
                self.progressText = ""
                self.loginURL = nil
                self.job = nil
                done(r)
            }
        }
    }

    /// v5.13: tinggal 1 percobaan → tanya dulu. Salah sekali lagi = vault terhapus selamanya.
    func lastTryOK() -> Bool {
        guard let v = vault, (v.max ?? 3) - (v.attempts ?? 0) <= 1 else { return true }
        return confirm(T("LAST TRY", "PERCOBAAN TERAKHIR"),
                       T("You have 1 try left. If this password is wrong, the vault is DELETED FOREVER and cannot be "
                         + "brought back.\n\nNot 100% sure? Press Cancel and check your password notes first.",
                         "Tinggal 1 percobaan. Kalau password ini salah, vault TERHAPUS SELAMANYA dan tidak bisa "
                         + "dikembalikan.\n\nTidak 100% yakin? Tekan Batal lalu cek catatan password kamu dulu."),
                       ok: T("I'm Sure, Try", "Saya Yakin, Coba"), danger: true)
    }

    func vaultError(_ r: VaultReply, cancelled: String? = nil) {
        let e = r.error ?? T("Something went wrong.", "Terjadi kesalahan.")
        if e == "CANCELLED" {
            info(T("Cancelled", "Dibatalkan"), cancelled ?? T("Nothing was changed.", "Tidak ada yang diubah."))
        } else if e == "DOOMSDAY" {
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
            // v5.13: vault yang belum pernah ikut backup hilang total kalau password salah 3x (kejadian 7 Okt)
            if vault?.exists == true, !FileManager.default.fileExists(atPath: P.a + "/backup.vault.ok") {
                guard confirm(T("Your vault is not in any backup yet", "Vault kamu belum ada di backup mana pun"),
                              T("If the vault is lost (for example 3 wrong passwords), your saved logins are gone for good.\n\n"
                                + "Recommended: open Backup, keep \"Include Profile Vault\" ticked and press Back Up Now. "
                                + "Then turn Amnesia on.",
                                "Kalau vault hilang (misalnya salah password 3x), login yang tersimpan hilang selamanya.\n\n"
                                + "Disarankan: buka Backup, biarkan \"Sertakan Profile Vault\" tercentang, lalu tekan Back Up Now. "
                                + "Setelah itu baru aktifkan Amnesia."),
                              ok: T("Turn On Anyway", "Tetap Aktifkan"), danger: true) else {
                    page = .backup
                    return
                }
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
        guard ensureFullDisk() else { return }
        let job = JobBox()
        background(T("Saving profiles to the vault…", "Menyimpan profil ke vault…"), job: job,
                   { vaultCall(["snapshot"], job: job, progress: Model.progressSink) }) { r in
            if r.error == "CANCELLED" {
                info(T("Cancelled", "Dibatalkan"), T("You're still logged in. Apps saved before Cancel keep their new snapshot.",
                                                     "Kamu tetap login. App yang tersimpan sebelum Batal memakai snapshot baru."))
                self.refreshVault()
            } else if r.ok {
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

/// Popup panduan: judul, isi yang bisa di-scroll, tombol Tutup.
struct GuideSheet<C: View>: View {
    let title: String
    let close: () -> Void
    let content: C
    init(_ title: String, close: @escaping () -> Void, @ViewBuilder content: () -> C) {
        self.title = title
        self.close = close
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: "questionmark.circle.fill").font(.system(size: 17, weight: .bold))
            ScrollView { content.frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 460)
            HStack {
                Spacer()
                Button(T("Close", "Tutup")) { close() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

/// Di bawah kolom "ulangi": langsung memberi tahu kalau isinya belum sama (atau sudah sama).
struct MatchNote: View {
    let a: String
    let b: String
    var body: some View {
        if !b.isEmpty {
            if a == b {
                Note(text: T("Both match.", "Sudah sama."), icon: "checkmark.circle.fill", color: .green)
            } else {
                Note(text: T("They don't match yet.", "Belum sama dengan yang di atas."), icon: "xmark.circle.fill", color: .red)
            }
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
                Text(state.title).font(.system(size: 24, weight: .bold, design: .rounded))
                Text(state.subtitle).font(.system(size: 13.5)).opacity(0.92)
                    .fixedSize(horizontal: false, vertical: true)
                Label(lastClean, systemImage: "clock.fill").font(.system(size: 12, weight: .medium))
                    .opacity(0.85).padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(18)
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
            // ikon di kiri, teks di kanan: lebih padat, teks lebih besar, tanpa ruang kosong
            HStack(alignment: .center, spacing: 10) {
                IconBadge(icon: icon, colors: colors, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(sub).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .padding(12)
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

enum Page { case home, vault, keep, backup, settings, preview, move }

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
                case .move: MoveView(back: { m.page = .vault })
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
                    VStack(spacing: 12) {
                        if let p = m.progress {
                            Text("\(Int(p * 100))%").font(.system(size: 22, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            ProgressView(value: p).frame(width: 260)
                        } else {
                            ProgressView().controlSize(.large)
                        }
                        if !m.progressText.isEmpty {
                            Text(m.progressText).font(.system(size: 13, weight: .semibold)).multilineTextAlignment(.center)
                                .monospacedDigit()
                            Text(b).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        } else {
                            Text(b).font(.system(size: 13, weight: .semibold)).multilineTextAlignment(.center)
                        }
                        if m.progress != nil {
                            Text(T("Please wait, don't close Amnesia.", "Tunggu sebentar, jangan tutup Amnesia."))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        if let u = m.loginURL {
                            Button { openInBrowser(u) } label: {
                                Label(T("Browser didn't open? Open the login page", "Browser tidak terbuka? Buka halaman login"),
                                      systemImage: "safari.fill")
                            }
                            .controlSize(.large)
                        }
                        if m.job != nil {
                            Button { m.cancelJob() } label: { Label(T("Cancel", "Batal"), systemImage: "xmark.circle.fill") }
                                .controlSize(.large)
                        }
                    }
                    .frame(maxWidth: 340)
                    .padding(28)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.regularMaterial))
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .frame(width: 480, height: 690)
        .background(WindowKeeper())
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
        ScrollView {
        VStack(spacing: 14) {
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
                        .font(.system(size: 13)).foregroundStyle(.secondary)
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
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                      spacing: 12) {
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
            Button { m.page = .preview } label: {
                HStack(spacing: 10) {
                    IconBadge(icon: "eye.fill", colors: Pal.logout, size: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(T("What Gets Deleted", "Yang Akan Dihapus")).font(.system(size: 15, weight: .semibold))
                        Text(previewSub).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        }
        .scrollIndicators(.never)
    }

    private var previewSub: String {
        guard let r = m.report else { return T("See the list before you turn Amnesia on", "Lihat daftarnya sebelum mengaktifkan Amnesia") }
        let n = r.filter { !$0.system }.reduce(0) { $0 + $1.items.count }
        return T("\(n) items at the next logout (plus macOS system data)", "\(n) item saat logout berikutnya (plus data sistem macOS)")
    }
}

// MARK: - Profile Vault

/// Kenapa app ini bisa lama disimpan (untuk peringatan sebelum snapshot).
func bigReason(_ app: String) -> String {
    switch app {
    case "Chrome": return T("big browser profile", "profil browser besar")
    case "Claude": return T("many projects and chats", "banyak project dan chat")
    case "WhatsApp": return T("big chat history", "riwayat chat besar")
    default: return T("lots of data", "datanya banyak")
    }
}

/// Ikon app di vault: ikon asli kalau app-nya terpasang, kalau tidak ikon terminal (alat coding).
@MainActor
func vaultAppIcon(_ name: String) -> some View {
    let candidates = ["/Applications/\(name).app", "/Applications/Google \(name).app", P.home + "/Applications/\(name).app"]
    if let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
        return AnyView(Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().interpolation(.high))
    }
    return AnyView(Image(systemName: name.hasPrefix("~/") ? "folder.fill" : "terminal.fill")
        .font(.system(size: 18)).foregroundStyle(.indigo))
}

func mbText(_ mb: Double) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(mb * 1_048_576), countStyle: .file)
}

struct VaultView: View {
    @EnvironmentObject var m: Model
    let back: () -> Void
    @State private var pw = ""
    @State private var pw2 = ""
    @State private var panic = ""
    @State private var panic2 = ""
    @State private var panicFull = false
    @State private var showPanic = false
    @State private var newPanic = ""
    @State private var newPanic2 = ""
    @State private var newPanicFull = false
    @State private var showPassword = false
    @State private var oldPw = ""
    @State private var newPw = ""
    @State private var newPw2 = ""
    @State private var pwStep = 0
    @State private var checking = false
    @State private var skip = Set(Config.get("VAULT_SKIP").split(separator: ",").map(String.init))
    @State private var sizes: [String: Double] = [:]
    @State private var sizesLoaded = false

    static let bigMB = 500.0

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
        .onAppear { m.refreshVault(); loadSizes() }
        .sheet(isPresented: $showPanic) { panicSheet }
        .sheet(isPresented: $showPassword, onDismiss: { oldPw = ""; newPw = ""; newPw2 = ""; pwStep = 0 }) { passwordSheet }
    }

    private func loadSizes() {
        if Shots.on { return }
        m.quiet({ vaultCall(["sizes"]) }) { r in
            sizes = r.sizes ?? [:]
            sizesLoaded = true
        }
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
            Note(text: T("The password CANNOT be recovered if you forget it. You can change it later.",
                         "Password TIDAK bisa dipulihkan kalau lupa. Nanti bisa diganti."),
                 icon: "exclamationmark.triangle.fill",
                 color: .orange)
            Field(label: T("Vault password (min. \(v.min ?? 12) characters)",
                           "Password vault (min. \(v.min ?? 12) karakter)"), text: $pw)
            if !pw.isEmpty {
                Field(label: T("Repeat password", "Ulangi password"), text: $pw2)
                MatchNote(a: pw, b: pw2)
            }
        }
        Card {
            Field(label: T("Panic word (optional)", "Kata panik (opsional)"), text: $panic)
            if !panic.isEmpty {
                Field(label: T("Repeat panic word", "Ulangi kata panik"), text: $panic2)
                MatchNote(a: panic, b: panic2)
            }
            Note(text: T("Typing this word in the password box deletes the vault completely, right away.",
                         "Kalau kata ini diketik di kolom password, vault langsung dihapus total."))
            Toggle(T("The panic word also empties the Keep folder", "Kata panik juga mengosongkan folder Keep"), isOn: Binding(get: { panicFull && !panic.isEmpty }, set: { panicFull = $0 }))
                .font(.system(size: 12)).disabled(panic.isEmpty)
        }
        Button { create() } label: { Label(T("Create Vault", "Buat Vault"), systemImage: "lock.fill") }
            .buttonStyle(Pill(colors: Pal.vault))
            .disabled(pw.isEmpty || pw != pw2 || (!panic.isEmpty && panic != panic2))
        moveRow(T("Moving from an old Mac? Take the vault from a backup instead.",
                  "Pindah dari Mac lama? Ambil vault dari file backup saja."))
    }

    @ViewBuilder
    private func opened(_ v: VaultReply) -> some View {
        let maxTry = v.max ?? 3
        let left = maxTry - (v.attempts ?? 0)
        Card {
            if let man = v.manifest {
                HStack {
                    Text(T("Snapshots", "Snapshot")).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(T("\(mbText(man.size_mb)) in total", "total \(mbText(man.size_mb))"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                ForEach(man.apps, id: \.self) { a in
                    let p = man.per_app?[a]
                    HStack(spacing: 8) {
                        Image(systemName: a.hasPrefix("~/") ? "folder.fill" : "app.badge.checkmark.fill")
                            .font(.system(size: 11)).foregroundStyle(.indigo).frame(width: 16)
                        Text(a).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 6)
                        Text(p?.time ?? man.time).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                        if let mb = p?.size_mb {
                            Text(mbText(mb)).font(.system(size: 11)).foregroundStyle(.secondary)
                                .frame(width: 64, alignment: .trailing)
                        }
                        Button { deleteSnapshots(only: a) } label: {
                            Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(.red)
                        }
                        .buttonStyle(.plain).help(T("Delete only this snapshot", "Hapus snapshot ini saja"))
                    }
                }
                Text(T("Each app has its own snapshot: saving one app doesn't touch the others.",
                       "Tiap app punya snapshot sendiri: menyimpan 1 app tidak mengubah yang lain."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                .disabled(pw.isEmpty || v.manifest == nil)
        }
        appsCard(v)
        foldersCard(v)
        Button { snapshot(v) } label: { Label(T("Snapshot Now", "Snapshot Sekarang"), systemImage: "camera.fill") }
            .buttonStyle(Pill(colors: Pal.logout))
        HStack(spacing: 10) {
            Button { pwStep = 0; showPassword = true } label: { Label(T("Password", "Password"), systemImage: "key.fill") }
                .buttonStyle(Pill(colors: Pal.gray))
            Button { showPanic = true } label: { Label(T("Panic Word", "Kata Panik"), systemImage: "flame.fill") }
                .buttonStyle(Pill(colors: Pal.vault))
        }
        HStack(spacing: 10) {
            Button { deleteSnapshots() } label: { Label(T("Delete All Snapshots", "Hapus Semua Snapshot"), systemImage: "camera.badge.ellipsis") }
                .buttonStyle(Pill(colors: Pal.pause))
                .disabled(v.manifest == nil)
            Button { deleteVault() } label: { Label(T("Delete Vault", "Hapus Vault"), systemImage: "trash.fill") }
                .buttonStyle(Pill(colors: Pal.danger))
        }
        Text(T("To delete one app's snapshot, use the trash icon next to it. Delete All Snapshots keeps the vault and its "
               + "password. Delete Vault removes everything.",
               "Untuk menghapus snapshot 1 app, pakai ikon tempat sampah di sampingnya. Hapus Semua Snapshot: vault dan "
               + "password tetap ada. Hapus Vault: semuanya dihapus."))
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        moveRow(T("Moving to a new Mac? Take your logins with you.", "Pindah ke Mac baru? Bawa login kamu."))
    }

    private func sizeText(_ a: String) -> String {
        guard let mb = sizes[a] else { return sizesLoaded ? "" : "…" }
        return mbText(mb)
    }

    /// Pilih app mana yang ikut disimpan di vault (VAULT_SKIP = yang dimatikan), dengan ukurannya.
    /// Kotak kecil yang bisa diklik, dan 1 catatan ringkas di bawah (bukan peringatan per app).
    private func appsCard(_ v: VaultReply) -> some View {
        let apps = v.apps ?? []
        let chosen = apps.filter { !skip.contains($0) }
        let totalMB = chosen.compactMap { sizes[$0] }.reduce(0, +)
        let big = chosen.filter { (sizes[$0] ?? 0) >= VaultView.bigMB }
        return Card {
            HStack {
                Text(T("What goes in the vault", "Yang disimpan di vault")).font(.system(size: 13, weight: .semibold))
                Spacer()
                if sizesLoaded {
                    Text(T("\(chosen.count) picked · \(mbText(totalMB))", "\(chosen.count) dipilih · \(mbText(totalMB))"))
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            Text(T("Tap an app to pick it. Snapshot needs no password; Restore does.",
                   "Klik app untuk memilih. Snapshot tanpa password; Restore pakai password."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if apps.isEmpty {
                Text(T("No app data found yet.", "Belum ada data app.")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                      spacing: 8) {
                ForEach(apps, id: \.self) { a in appTile(a, on: !skip.contains(a)) }
            }
            if !big.isEmpty || totalMB >= 1024 {
                Note(text: slowText(totalMB, big), icon: "hourglass", color: .orange)
            }
        }
    }

    /// 1 catatan ringkas: snapshot bisa lama (total, dan app mana yang paling besar).
    private func slowText(_ totalMB: Double, _ big: [String]) -> String {
        let names = big.joined(separator: ", ")
        if big.isEmpty {
            return T("Snapshot can take a few minutes: \(mbText(totalMB)) in total.",
                     "Snapshot bisa makan beberapa menit: total \(mbText(totalMB)).")
        }
        return T("Snapshot can take a few minutes: \(mbText(totalMB)) in total, mostly \(names).",
                 "Snapshot bisa makan beberapa menit: total \(mbText(totalMB)), terutama \(names).")
    }

    /// Kotak kecil 1 app: ikon, nama, ukuran. Terpilih = garis warna + centang.
    private func appTile(_ a: String, on: Bool) -> some View {
        Button {
            if on { skip.insert(a) } else { skip.remove(a) }
            Config.set("VAULT_SKIP", skip.sorted().joined(separator: ","))
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    vaultAppIcon(a).frame(width: 28, height: 28)
                    if on {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(.white, .indigo)
                            .offset(x: 6, y: -4)
                    }
                }
                Text(a).font(.system(size: 11, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                Text(sizeText(a)).font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(maxWidth: .infinity, minHeight: 74)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? Color.indigo.opacity(0.18) : Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(on ? Color.indigo : Color.clear, lineWidth: 1.5))
            .opacity(on ? 1 : 0.65)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(on ? T("Picked: tap to leave it out", "Dipilih: klik untuk tidak ikut") : T("Tap to pick", "Klik untuk memilih"))
    }

    /// Folder pilihan yang ikut vault (VAULT_FOLDERS): dihapus saat logout, kembali lewat Restore.
    private func foldersCard(_ v: VaultReply) -> some View {
        let folders = v.folders ?? []
        return Card {
            Text(T("Folders in the vault", "Folder di vault")).font(.system(size: 13, weight: .semibold))
            Text(T("For documents, PDFs, music or videos you want locked away. They're wiped at logout like everything "
                   + "else, but a copy stays locked in the vault. Restore brings them back with your password.",
                   "Untuk dokumen, PDF, musik atau video yang mau dikunci. Ikut dihapus saat logout seperti yang lain, "
                   + "tapi salinannya terkunci di vault. Restore mengembalikannya dengan password kamu."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(folders, id: \.self) { f in
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill").foregroundStyle(.teal)
                    Text("~/" + f).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(sizeText("~/" + f)).font(.system(size: 11)).foregroundStyle(.secondary)
                    Button { removeFolder(f) } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
                        .buttonStyle(.plain).help(T("Remove from the vault", "Hapus dari vault"))
                }
                if (sizes["~/" + f] ?? 0) >= 1024 {
                    Note(text: T("This folder is big: snapshots and restores of it take a while, and the vault grows by its size.",
                                 "Folder ini besar: snapshot dan restore-nya makan waktu, dan vault bertambah sebesar itu."),
                         icon: "hourglass", color: .orange)
                }
            }
            Button { addFolder() } label: {
                Label(T("Add a folder…", "Tambah folder…"), systemImage: "plus.circle.fill")
            }
            .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(.indigo)
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: P.home + "/Documents")
        panel.prompt = T("Add to the vault", "Tambah ke vault")
        guard panel.runModal() == .OK else { return }
        var list = (m.vault?.folders ?? [])
        for u in panel.urls {
            let path = u.standardizedFileURL.path
            guard path.hasPrefix(P.home + "/"), !path.contains(","), !path.hasPrefix(P.a),
                  let rel = KeepAddSheet.relative(path) else {
                info("Profile Vault", T("Pick a folder inside your home folder (not the home folder itself, and no comma in its name).",
                                        "Pilih folder di dalam folder home (bukan folder home-nya, dan tanpa koma di namanya)."),
                     error: true)
                continue
            }
            if path == KeepDir.path || path.hasPrefix(KeepDir.path + "/") {
                info("Profile Vault", T("This folder is inside your Keep folder, so it's never wiped anyway.",
                                        "Folder ini ada di dalam folder Keep, jadi memang tidak pernah dihapus."))
                continue
            }
            if !list.contains(rel) { list.append(rel) }
        }
        Config.set("VAULT_FOLDERS", list.joined(separator: ","))
        m.refreshVault()
        loadSizes()
    }

    private func removeFolder(_ f: String) {
        guard confirm(T("Remove from the vault?", "Hapus dari vault?"),
                      T("~/\(f) is no longer saved in the vault. The folder itself stays on this Mac until the next logout.",
                        "~/\(f) tidak lagi disimpan di vault. Foldernya tetap ada di Mac ini sampai logout berikutnya."),
                      ok: T("Remove", "Hapus")) else { return }
        let list = (m.vault?.folders ?? []).filter { $0 != f }
        Config.set("VAULT_FOLDERS", list.joined(separator: ","))
        m.refreshVault()
    }

    private func moveRow(_ text: String) -> some View {
        Button { m.page = .move } label: {
            HStack(spacing: 10) {
                IconBadge(icon: "arrow.left.arrow.right", colors: Pal.backup, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(T("Move to a New Mac", "Pindah Mac")).font(.system(size: 14, weight: .semibold))
                    Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            if !newPanic.isEmpty {
                Field(label: T("Repeat panic word", "Ulangi kata panik"), text: $newPanic2)
                MatchNote(a: newPanic, b: newPanic2)
            }
            Toggle(T("Also empty the Keep folder", "Juga kosongkan folder Keep"), isOn: $newPanicFull).font(.system(size: 12)).disabled(newPanic.isEmpty)
            HStack {
                Button(T("Cancel", "Batal")) { showPanic = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(T("Save", "Simpan")) { savePanic() }.keyboardShortcut(.defaultAction)
                    .disabled(pw.isEmpty || newPanic != newPanic2)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    /// Ganti password bertahap: password sekarang dulu (dicek), baru password baru.
    private var passwordSheet: some View {
        let minLen = m.vault?.min ?? 12
        return VStack(alignment: .leading, spacing: 12) {
            Text(T("Change Vault Password", "Ganti Password Vault")).font(.system(size: 17, weight: .bold))
            Text(T("Your snapshots stay as they are. Only the password that opens them changes.",
                   "Snapshot kamu tetap utuh. Yang berubah hanya password untuk membukanya."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if pwStep == 0 {
                Field(label: T("Step 1: current password", "Langkah 1: password sekarang"), text: $oldPw)
                    .onSubmit { checkOld() }
                Note(text: T("A wrong current password counts as a failed try.", "Password sekarang yang salah dihitung sebagai percobaan gagal."),
                     icon: "exclamationmark.triangle.fill", color: .orange)
                HStack {
                    Button(T("Cancel", "Batal")) { showPassword = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    if checking { ProgressView().controlSize(.small) }
                    Button(T("Next", "Lanjut")) { checkOld() }.keyboardShortcut(.defaultAction)
                        .disabled(oldPw.isEmpty || checking)
                }
            } else {
                Note(text: T("The current password is correct.", "Password sekarang benar."), icon: "checkmark.circle.fill", color: .green)
                Field(label: T("Step 2: new password (min. \(minLen) characters)", "Langkah 2: password baru (min. \(minLen) karakter)"),
                      text: $newPw)
                if !newPw.isEmpty {
                    Field(label: T("Repeat new password", "Ulangi password baru"), text: $newPw2)
                }
                if !newPw.isEmpty && newPw == oldPw {
                    Note(text: T("The new password must be different from the current one.", "Password baru harus beda dengan password sekarang."),
                         icon: "xmark.circle.fill", color: .red)
                } else if !newPw.isEmpty && newPw.count < minLen {
                    Note(text: T("Needs at least \(minLen) characters.", "Minimal \(minLen) karakter."), icon: "info.circle.fill", color: .orange)
                } else {
                    MatchNote(a: newPw, b: newPw2)
                }
                HStack {
                    Button(T("Cancel", "Batal")) { showPassword = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(T("Change", "Ganti")) { changePassword() }.keyboardShortcut(.defaultAction)
                        .disabled(newPw.isEmpty || newPw != newPw2 || newPw == oldPw || newPw.count < minLen)
                }
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    private func create() {
        guard pw == pw2 else { info("Profile Vault", T("The passwords do not match.", "Password tidak cocok."), error: true); return }
        guard panic.isEmpty || panic == panic2 else {
            info("Profile Vault", T("The panic words do not match.", "Kata panik tidak cocok."), error: true); return
        }
        let input = pw + "\n" + panic + "\n"
        let args = ["create"] + (panicFull && !panic.isEmpty ? ["full"] : [])
        m.background(T("Creating vault keys…", "Membuat kunci vault…"), { vaultCall(args, input: input) }) { r in
            if r.ok {
                pw = ""; pw2 = ""; panic = ""; panic2 = ""
                // vault baru: belum ada app yang dicentang, kamu sendiri yang memilih
                skip = Set(m.vault?.apps ?? [])
                Config.set("VAULT_SKIP", skip.sorted().joined(separator: ","))
                info(T("Vault created", "Vault dibuat"),
                     T("Now tick the apps you want in the vault, log in to them as usual, then press Snapshot "
                       + "(or Save & Log Out).",
                       "Sekarang centang app yang mau disimpan di vault, login ke app itu seperti biasa, lalu tekan "
                       + "Snapshot (atau Simpan & Logout)."))
            } else {
                m.vaultError(r)
            }
            m.refreshVault()
        }
    }

    /// Ringkasan cek otomatis setelah restore (centang hijau / silang merah per app).
    private func restoreReport(_ r: VaultReply) -> String {
        let checks = r.checks ?? (r.apps ?? []).map { RestoreCheck(app: $0, ok: true, note: "") }
        var lines: [String] = checks.map { (c: RestoreCheck) -> String in
            let mark = c.ok ? "✅ " : "❌ "
            return mark + c.app + (c.note.isEmpty ? "" : " — " + c.note)
        }
        if checks.contains(where: { $0.app == "Chrome" }) {
            lines.append("")
            lines.append(T("Check yourself (web logins can't be checked automatically): open Chrome and look at Gmail, "
                           + "WhatsApp Web and Telegram Web.",
                           "Cek sendiri (login web tidak bisa dicek otomatis): buka Chrome lalu lihat Gmail, "
                           + "WhatsApp Web dan Telegram Web."))
        }
        lines.append("")
        lines.append(T("The app data that was on this Mac before the restore was moved (not deleted) to "
                       + "~/Library/Caches/Amnesia/before-restore. It stays there until the next logout.",
                       "Data app yang ada di Mac ini sebelum restore dipindah (tidak dihapus) ke "
                       + "~/Library/Caches/Amnesia/before-restore. Folder itu ada sampai logout berikutnya."))
        return lines.joined(separator: "\n")
    }

    private func restore() {
        guard !pw.isEmpty, m.lastTryOK(), ensureFullDisk() else { return }
        let input = pw + "\n"
        let job = JobBox()
        m.background(T("Restoring profiles…\nThe apps are closed just before the files are put back.",
                       "Memulihkan profil…\nApp baru ditutup tepat sebelum file dikembalikan."), job: job,
                     { vaultCall(["restore"], input: input, job: job, progress: Model.progressSink) }) { r in
            pw = ""
            if r.ok {
                let allOk = (r.checks ?? []).allSatisfy(\.ok)
                info(allOk ? T("Restore done", "Restore selesai") : T("Restore done, check the list", "Restore selesai, cek daftarnya"),
                     restoreReport(r), error: !allOk)
            } else {
                m.vaultError(r, cancelled: T("Nothing on this Mac was changed.", "Tidak ada yang diubah di Mac ini."))
            }
            m.refreshVault()
        }
    }

    private func snapshot(_ v: VaultReply) {
        let apps = (v.apps ?? []).filter { !skip.contains($0) }
        guard !apps.isEmpty else {
            info("Profile Vault", T("No apps are switched on under \"What goes in the vault\".",
                                    "Tidak ada app yang dicentang di \"Yang disimpan di vault\"."))
            return
        }
        let list = apps.map { a in sizes[a].map { "\(a) (\(mbText($0)))" } ?? a }.joined(separator: ", ")
        let slow = apps.filter { (sizes[$0] ?? 0) >= VaultView.bigMB }
        let slowNote = slow.isEmpty ? "" : T("\n\nThis can take a few minutes: ", "\n\nIni bisa makan beberapa menit: ")
            + slow.map { "\($0) (\(bigReason($0)))" }.joined(separator: ", ") + "."
        guard confirm("Snapshot", T("Save \(list)?\n\nThese apps will be closed first. No password needed. Only these get a "
                                    + "new snapshot; the others keep theirs.",
                                    "Simpan \(list)?\n\nApp tersebut akan ditutup dulu. Tidak perlu password. Hanya app ini "
                                    + "yang snapshot-nya diperbarui; yang lain tetap.") + slowNote,
                      ok: T("Save", "Simpan")) else { return }
        guard ensureFullDisk() else { return }
        let job = JobBox()
        m.background(T("Saving to the vault…", "Menyimpan ke vault…"), job: job,
                     { vaultCall(["snapshot"] + apps, job: job, progress: Model.progressSink) }) { r in
            if r.ok {
                info("Snapshot", T("Saved: ", "Tersimpan: ") + (r.apps ?? apps).joined(separator: ", "))
            } else {
                m.vaultError(r, cancelled: T("Apps saved before you pressed Cancel keep their new snapshot. "
                                             + "The others keep the snapshot they already had.",
                                             "App yang sudah tersimpan sebelum Batal ditekan memakai snapshot baru. "
                                             + "Yang lain tetap memakai snapshot lamanya."))
            }
            m.refreshVault()
            loadSizes()
        }
    }

    private func savePanic() {
        guard newPanic == newPanic2, m.lastTryOK() else { return }
        let input = pw + "\n" + newPanic + "\n"
        let args = ["panic"] + (newPanicFull && !newPanic.isEmpty ? ["full"] : [])
        let word = newPanic
        showPanic = false
        m.background(T("Checking password…", "Memeriksa password…"), { vaultCall(args, input: input) }) { r in
            pw = ""; newPanic = ""; newPanic2 = ""
            if r.ok {
                info(T("Panic Word", "Kata Panik"), word.isEmpty ? T("Panic word turned off.", "Kata panik dimatikan.")
                                                                  : T("Panic word saved.", "Kata panik disimpan."))
            } else {
                m.vaultError(r)
            }
            m.refreshVault()
        }
    }

    /// Langkah 1: cek password sekarang dulu, baru tampilkan kolom password baru.
    private func checkOld() {
        guard !oldPw.isEmpty, !checking, m.lastTryOK() else { return }
        checking = true
        let input = oldPw + "\n"
        m.quiet({ vaultCall(["check"], input: input) }) { r in
            checking = false
            if r.ok {
                pwStep = 1
            } else {
                oldPw = ""
                if r.error == "DOOMSDAY" { showPassword = false }
                m.vaultError(r)
                m.refreshVault()
            }
        }
    }

    private func changePassword() {
        let input = oldPw + "\n" + newPw + "\n"
        showPassword = false
        m.background(T("Changing the password…", "Mengganti password…"), { vaultCall(["passwd"], input: input) }) { r in
            oldPw = ""; newPw = ""; newPw2 = ""; pwStep = 0
            if r.ok {
                info(T("Password changed", "Password diganti"),
                     T("From now on, open the vault with the new password.", "Mulai sekarang buka vault pakai password baru."))
            } else {
                m.vaultError(r)
            }
            m.refreshVault()
        }
    }

    /// only: hapus snapshot 1 app/folder saja; nil = semua.
    private func deleteSnapshots(only: String? = nil) {
        if let a = only {
            guard confirm(T("Delete the snapshot of \(a)?", "Hapus snapshot \(a)?"),
                          T("Only this snapshot is deleted. The other apps keep theirs.\n\nThis cannot be undone.",
                            "Hanya snapshot ini yang dihapus. App lain tetap.\n\nTidak bisa dibatalkan."),
                          ok: T("Delete", "Hapus"), danger: true) else { return }
        } else {
            guard confirm(T("Delete all snapshots?", "Hapus semua snapshot?"),
                          T("The saved apps and folders are deleted from the vault. The vault, its password, the panic word "
                            + "and the Move-Mac keys stay.\n\nThis cannot be undone.",
                            "App dan folder yang tersimpan dihapus dari vault. Vault, password, kata panik dan kunci Pindah Mac "
                            + "tetap ada.\n\nTidak bisa dibatalkan."),
                          ok: T("Delete All", "Hapus Semua"), danger: true) else { return }
        }
        let args = ["delsnap"] + (only.map { [$0] } ?? [])
        m.background(T("Deleting snapshots…", "Menghapus snapshot…"), { vaultCall(args) }) { r in
            if !r.ok { m.vaultError(r) }
            m.refreshVault()
        }
    }

    private func deleteVault() {
        guard confirm(T("Delete Vault?", "Hapus Vault?"),
                      T("The vault, its password and all snapshots are deleted.\n\nThis cannot be undone.",
                        "Vault, password-nya dan semua snapshot dihapus.\n\nTidak bisa dibatalkan."),
                      ok: T("Delete", "Hapus"), danger: true) else { return }
        m.background(T("Deleting the vault…", "Menghapus vault…"), { vaultCall(["delete"]) }) { r in
            if !r.ok { m.vaultError(r) }
            m.refreshVault()
        }
    }
}

// MARK: - Pindah Mac

struct MoveView: View {
    @EnvironmentObject var m: Model
    let back: () -> Void
    @State private var pw = ""
    @State private var backupPw = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                PageHeader(title: T("Move to a New Mac", "Pindah Mac"), icon: "arrow.left.arrow.right", colors: Pal.backup, back: back)
                Card {
                    Text(T("How it works", "Cara kerjanya")).font(.system(size: 13, weight: .semibold))
                    Text(T("Chrome, Claude and WhatsApp lock their logins with secret keys in this Mac's Keychain. "
                           + "A new Mac doesn't have those keys, so restored profiles would be logged out. "
                           + "This page carries the keys over, safely inside your vault.",
                           "Chrome, Claude dan WhatsApp mengunci login dengan kunci rahasia di Keychain Mac ini. "
                           + "Mac baru tidak punya kunci itu, jadi profil yang dipulihkan akan ter-logout. "
                           + "Halaman ini membawa kunci tersebut, aman di dalam vault kamu."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    step("1", T("Old Mac: Prepare Move", "Mac lama: Siapkan Pindah"),
                         T("Saves the Keychain keys into the vault.", "Menyimpan kunci Keychain ke vault."))
                    step("2", T("Old Mac: Back up", "Mac lama: Backup"),
                         T("Backup page, tick Include Profile Vault.", "Halaman Backup, centang Sertakan Profile Vault."))
                    step("3", T("New Mac: Get Vault from Backup", "Mac baru: Ambil Vault dari Backup"),
                         T("Install Amnesia, then use the box below.", "Pasang Amnesia, lalu pakai kotak di bawah."))
                    step("4", T("New Mac: Restore Profiles, then Restore Keys", "Mac baru: Restore Profil, lalu Pulihkan Kunci"),
                         T("Your apps open with your old logins.", "App terbuka dengan login lama."))
                }
                if let v = m.vault, v.ok {
                    if v.exists == true { oldMac(v); newMacKeys(v) } else { newMacVault }
                } else {
                    ProgressView().padding(30)
                }
            }
        }
        .scrollIndicators(.never)
        .onAppear { m.refreshVault() }
    }

    private func step(_ n: String, _ t: String, _ sub: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Circle().fill(Color.pink))
            VStack(alignment: .leading, spacing: 1) {
                Text(t).font(.system(size: 13, weight: .semibold))
                Text(sub).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func oldMac(_ v: VaultReply) -> some View {
        Card {
            Text(T("On the old Mac", "Di Mac lama")).font(.system(size: 13, weight: .semibold))
            if let k = v.keys {
                Note(text: T("Keys saved \(k.time): ", "Kunci tersimpan \(k.time): ") + k.apps.joined(separator: ", "),
                     icon: "checkmark.circle.fill", color: .green)
            }
            HStack(spacing: 10) {
                Button { exportKeys() } label: { Label(T("Prepare Move", "Siapkan Pindah"), systemImage: "key.fill") }
                    .buttonStyle(Pill(colors: Pal.vault))
                Button { m.page = .backup } label: { Label(T("Go to Backup", "Ke Backup"), systemImage: "externaldrive.fill") }
                    .buttonStyle(Pill(colors: Pal.backup))
            }
        }
    }

    @ViewBuilder
    private func newMacKeys(_ v: VaultReply) -> some View {
        Card {
            Text(T("On the new Mac", "Di Mac baru")).font(.system(size: 13, weight: .semibold))
            Note(text: T("Do this only on the NEW Mac, after Restore Profiles on the Profile Vault page.",
                         "Lakukan hanya di Mac BARU, setelah Restore Profil di halaman Profile Vault."))
            Field(label: T("Vault password", "Password vault"), text: $pw)
            Button { importKeys() } label: { Label(T("Restore Keys", "Pulihkan Kunci"), systemImage: "key.horizontal.fill") }
                .buttonStyle(Pill(colors: Pal.keep))
                .disabled(pw.isEmpty || v.keys == nil)
            if v.keys == nil {
                Text(T("This vault has no keys yet (step 1 wasn't done on the old Mac).",
                       "Vault ini belum berisi kunci (langkah 1 belum dilakukan di Mac lama)."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var newMacVault: some View {
        Card {
            Text(T("On the new Mac", "Di Mac baru")).font(.system(size: 13, weight: .semibold))
            Text(T("Pick the Amnesia backup file (.7z) that includes the Profile Vault.",
                   "Pilih file backup Amnesia (.7z) yang berisi Profile Vault."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Field(label: T("Backup password", "Password backup"), text: $backupPw)
            Button { importVault() } label: {
                Label(T("Get Vault from Backup…", "Ambil Vault dari Backup…"), systemImage: "tray.and.arrow.down.fill")
            }
            .buttonStyle(Pill(colors: Pal.backup))
            .disabled(backupPw.isEmpty)
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
                      ok: T("Restore", "Pulihkan"), danger: true), m.lastTryOK() else { return }
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
                    AppleKeepCard { entries = Keep.entries() }
                    ForEach(entries.filter { !applePaths.contains($0) }, id: \.self) { e in row(e) }
                }
            }
            .scrollIndicators(.never)
            HStack(spacing: 10) {
                Button { addingApps = true } label: { Label(T("Pick Apps", "Pilih App"), systemImage: "square.grid.2x2.fill") }
                    .buttonStyle(Pill(colors: Pal.vault))
                Button { adding = true } label: { Label(T("Add Folder or File", "Tambah Folder / File"), systemImage: "plus") }
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
        var dir: ObjCBool = true
        let isFile = !isKey && !e.contains("*") && FileManager.default.fileExists(atPath: P.home + "/" + e, isDirectory: &dir)
            && !dir.boolValue
        return HStack(spacing: 10) {
            Image(systemName: isKey ? "key.fill" : (isFile ? "doc.fill" : "folder.fill"))
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
    @State private var typed = ""

    /// Path yang boleh masuk Keep List: di dalam home, bukan home itu sendiri. Hasil: path relatif, atau nil.
    static func relative(_ raw: String) -> String? {
        var p = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.hasPrefix(P.home + "/") { p = String(p.dropFirst(P.home.count + 1)) }
        if p.hasPrefix("~/") { p = String(p.dropFirst(2)) }
        while p.hasSuffix("/") { p.removeLast() }
        guard !p.isEmpty, !p.hasPrefix("/"), !p.split(separator: "/").contains(".."), !p.contains("\n") else { return nil }
        return p
    }

    /// Pilih file atau folder lewat Finder (folder tersembunyi seperti Library ikut terlihat).
    private func pickInFinder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: P.home + "/Library")
        panel.prompt = T("Add to Keep List", "Tambah ke Keep List")
        guard panel.runModal() == .OK else { return }
        var add: [String] = []
        for u in panel.urls {
            guard let r = KeepAddSheet.relative(u.standardizedFileURL.path), u.path.hasPrefix(P.home + "/") else {
                info("Keep List", T("Pick something inside your home folder (\(P.home)). Things outside it are never wiped.",
                                    "Pilih yang ada di dalam folder home (\(P.home)). Yang di luar home tidak pernah dihapus."),
                     error: true)
                continue
            }
            add.append(r)
        }
        finish(add)
    }

    private func addTyped() {
        guard let r = KeepAddSheet.relative(typed) else {
            info("Keep List", T("Type a path inside your home folder, e.g. Library/Preferences/MobileMeAccounts.plist",
                                "Ketik path di dalam folder home, mis. Library/Preferences/MobileMeAccounts.plist"), error: true)
            return
        }
        finish([r])
    }

    private func finish(_ add: [String]) {
        var seen = Set(Keep.entries())
        var new: [String] = []
        for x in picked.sorted() + add where !seen.contains(x) {
            seen.insert(x)
            new.append(x)
        }
        if !new.isEmpty { onAdd(new) }
        dismiss()
    }

    private var filtered: [String] {
        query.isEmpty ? cands : cands.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(T("Add to Keep List", "Tambah ke Keep List")).font(.system(size: 17, weight: .bold))
            TextField(T("Search…", "Cari…"), text: $query).textFieldStyle(.roundedBorder)
            if cands.isEmpty {
                Text(T("There are no other folders to add.", "Tidak ada folder lain yang bisa ditambahkan.")).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                List(filtered, id: \.self) { c in
                    Toggle(c, isOn: Binding(get: { picked.contains(c) },
                                            set: { on in if on { picked.insert(c) } else { picked.remove(c) } }))
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                }
                .frame(height: 240)
            }
            Divider()
            Text(T("Not in the list? A file (like a .plist) or any other folder:",
                   "Tidak ada di daftar? File (mis. .plist) atau folder lain:"))
                .font(.system(size: 12, weight: .semibold))
            HStack {
                TextField(T("Path from your home folder, e.g. Library/Preferences/x.plist",
                            "Path dari folder home, mis. Library/Preferences/x.plist"), text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addTyped() }
                Button(T("Add", "Tambah")) { addTyped() }.disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Button { pickInFinder() } label: {
                Label(T("Choose in Finder…", "Pilih di Finder…"), systemImage: "folder.badge.plus")
            }
            HStack {
                Button(T("Cancel", "Batal")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(T("Add (\(picked.count))", "Tambah (\(picked.count))")) { finish([]) }
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

/// Bagian "Akun & data Apple" di Keep List (dan di halaman setelah tur).
struct AppleKeepCard: View {
    var compact = false
    var changed: () -> Void = {}
    @State private var on: [String: Bool] = [:]
    @State private var expanded: Bool

    init(compact: Bool = false, changed: @escaping () -> Void = {}) {
        self.compact = compact
        self.changed = changed
        _expanded = State(initialValue: !compact)
    }

    private var count: Int { appleItems.filter { on[$0.id] == true }.count }

    var body: some View {
        Card {
            Button { if compact { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } } } label: {
                HStack(spacing: 10) {
                    IconBadge(icon: "applelogo", colors: Pal.gray, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(T("Apple accounts & data", "Akun & data Apple")).font(.system(size: 13, weight: .semibold))
                        Text(T("Switched on = stays after logout. Switch off what you don't need.",
                               "Nyala = tetap ada setelah logout. Matikan yang tidak perlu."))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    if compact {
                        Text("\(count)/\(appleItems.count)").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                ForEach(appleItems) { a in row(a) }
            }
        }
        .onAppear { load() }
    }

    private func load() {
        var d: [String: Bool] = [:]
        for a in appleItems { d[a.id] = AppleKeep.isOn(a) }
        on = d
    }

    private func row(_ a: AppleItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: a.icon).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(a.title).font(.system(size: 12, weight: .semibold))
                Text(a.sub).font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Toggle("", isOn: Binding(get: { on[a.id] ?? false }, set: { v in
                if !v && !confirm(T("Stop keeping \(a.title)?", "Berhenti menyimpan \(a.title)?"),
                                  T("\(a.title) will be DELETED from this Mac at the next logout.",
                                    "\(a.title) akan DIHAPUS dari Mac ini saat logout berikutnya."),
                                  ok: T("Stop Keeping", "Berhenti Simpan"), danger: true) { return }
                AppleKeep.set(a, v)
                load()
                changed()
            }))
            .toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
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
            AppleKeepCard(compact: true)
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

    /// step nil = lanjutkan dari halaman terakhir (disimpan di TOUR_STEP), misalnya setelah app dibuka ulang
    /// untuk Full Disk Access. 7 = halaman pilih app.
    init(step: Int? = nil, keepSetup: Bool = false) {
        let saved = step == nil ? Int(Config.get("TOUR_STEP")) ?? 0 : 0
        _step = State(initialValue: step ?? min(max(saved, 0), 6))
        _keepSetup = State(initialValue: keepSetup || saved == 7)
    }

    var body: some View {
        Group {
            if keepSetup {
                KeepSetupView(back: { keepSetup = false })
            } else {
                tour
            }
        }
        .onChange(of: step) { _, s in saveStep(s) }
        .onChange(of: keepSetup) { _, k in saveStep(k ? 7 : step) }
    }

    private func saveStep(_ s: Int) {
        if !Shots.on { Config.set("TOUR_STEP", String(s)) }
    }

    private var tour: some View {
        VStack(spacing: 16) {
            ScrollView {
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
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.never)
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
            Text(t).font(.system(size: 30, weight: .heavy, design: .rounded))
            Text(sub).font(.system(size: 15)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func item(_ icon: String, _ colors: [Color], _ t: String, _ sub: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(icon: icon, colors: colors, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(t).font(.system(size: 16, weight: .semibold))
                Text(sub).font(.system(size: 13.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // 1. Sambutan + bahasa
    private var welcome: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 128, height: 128)
            Text(T("Welcome to Amnesia", "Selamat datang di Amnesia"))
                .font(.system(size: 32, weight: .heavy, design: .rounded))
            Text(T("Your Mac forgets everything every time you log out, except the stuff you choose to keep. "
                   + "This quick tour sets it up with you. Nothing gets deleted until you say so.",
                   "Mac kamu lupa semuanya setiap logout, kecuali yang kamu pilih untuk disimpan. "
                   + "Tur singkat ini bantu kamu menyiapkannya. Tidak ada yang dihapus sampai kamu bilang iya."))
                .font(.system(size: 16)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Card {
                HStack {
                    Label(T("Language", "Bahasa"), systemImage: "globe").font(.system(size: 15, weight: .semibold))
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
        VStack(spacing: 18) {
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
            .toggleStyle(.checkbox).font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { NSWorkspace.shared.open(URL(string: termsURL)!) } label: {
                Label(T("Read the full terms", "Baca ketentuan lengkap"), systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.plain).font(.system(size: 14, weight: .semibold)).foregroundStyle(.indigo)
        }
    }

    // 3. Cara kerja
    private var features: some View {
        VStack(spacing: 20) {
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
        return VStack(spacing: 18) {
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
                Note(text: T("Switch on Amnesia in the list, then press Quit & Reopen. The tour continues right here.",
                             "Nyalakan Amnesia di daftar itu, lalu tekan Tutup & Buka Lagi. Tur lanjut dari halaman ini."))
                Button { Engine.relaunch() } label: {
                    Label(T("Quit & Reopen Amnesia", "Tutup & Buka Lagi Amnesia"), systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(Pill(colors: Pal.gray))
            }
            if Engine.sevenz == nil {
                Note(text: T("7-Zip is missing. Run in Terminal: brew install sevenzip",
                             "7-Zip belum ada. Jalankan di Terminal: brew install sevenzip"),
                     icon: "exclamationmark.triangle.fill", color: .orange)
            }
            Button { recheck += 1 } label: { Label(T("Check again", "Cek lagi"), systemImage: "arrow.clockwise") }
                .buttonStyle(.plain).font(.system(size: 14, weight: .semibold))
        }
    }

    private func status(_ ok: Bool, _ t: String, _ sub: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 24)).foregroundStyle(ok ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(t).font(.system(size: 16, weight: .semibold))
                Text(sub).font(.system(size: 13.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // 5. Contoh memilih app (yang asli muncul setelah tur)
    private var appsExample: some View {
        VStack(spacing: 18) {
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
                IconBadge(icon: icon, colors: colors, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 15, weight: .semibold))
                    Text(sub).font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: .constant(on)).toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
            ForEach(0..<detail.count, id: \.self) { i in
                let d = detail[i]
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill").font(.system(size: 10)).foregroundStyle(.teal).frame(width: 14)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(d.0).font(.system(size: 12.5, weight: .semibold))
                        Text(d.1).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(d.2).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                .padding(.leading, 40)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
    }

    // 6. Profile Vault
    private var vaultPage: some View {
        VStack(spacing: 20) {
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
        VStack(spacing: 20) {
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
                     T("Home page → What Gets Deleted.", "Halaman utama → Yang Akan Dihapus."))
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
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

let termsURL = "https://github.com/navi-crwn/amnesia-mac/blob/main/TERMS.md"

// MARK: - Backup

struct BackupView: View {
    @EnvironmentObject var m: Model
    let back: () -> Void
    @State private var dest = Config.get("BACKUP_DEST", "drive") == "folder" ? "rclone" : Config.get("BACKUP_DEST", "drive")
    @State private var drives: [Drive] = []
    @State private var drive = Config.get("BACKUP_DRIVE")
    @State private var server = Config.get("BACKUP_SSH")
    @State private var port = Config.get("BACKUP_SSH_PORT", "22")
    @State private var cloud = BackupView.savedCloud
    @State private var folderName = BackupView.savedFolderName
    @State private var folders = Set(BackupView.saved)
    @State private var extra = BackupView.saved.filter { !BackupView.defaults.contains($0) }
    @State private var sshPw = ""
    @State private var provider = cloudProviders.first(where: { $0.id == Config.get("BACKUP_CLOUD", "drive") }) ?? cloudProviders[0]
    /// Google Drive: "app" = lewat app Google Drive for Desktop (disarankan), "direct" = lewat rclone
    @State private var gMode = Config.get("BACKUP_DEST") == "folder" || Config.get("BACKUP_GMODE", "app") == "app" ? "app" : "direct"
    @State private var gdrive: (path: String, account: String)? = nil
    /// "checking" = sedang dicek, "ready" = ketemu, "syncing" = sudah login tapi belum siap, "none" = belum login/terpasang
    @State private var gState = "checking"
    @State private var clientID = Config.get("BACKUP_GCLIENT")
    @State private var clientSecret = ""
    @State private var connected: [String] = []
    @State private var user: [String: String] = [:]
    @State private var withVault = Config.get("BACKUP_VAULT") != "0"     // v5.13: ikut secara default
    @State private var schedule = Config.get("BACKUP_SCHEDULE", "off")
    @State private var remember = Secret.exists
    @State private var pw = ""
    @State private var pw2 = ""
    @State private var status = lastBackupStatus()
    @State private var showGuide = false
    @State private var showGoogleGuide = false
    static let defaults = ["@keep", "Documents", "Desktop", "Downloads", "Pictures", "Music", "Movies"]
    /// "@keep" = folder Keep (di mana pun letaknya). "Keep" dari versi lama juga berarti folder Keep.
    static var saved: [String] {
        Config.get("BACKUP_FOLDERS", "@keep").split(separator: ",").map { $0 == "Keep" ? "@keep" : String($0) }
    }
    /// "remote:folder". Versi lama kadang hanya menyimpan "Amnesia" (tanpa nama layanan): diperbaiki di sini.
    static var savedCloud: String {
        let c = Config.get("BACKUP_RCLONE", "gdrive:Amnesia")
        if c.contains(":") { return c }
        let p = cloudProviders.first(where: { $0.id == Config.get("BACKUP_CLOUD", "drive") }) ?? cloudProviders[0]
        return p.remote + ":" + (c.isEmpty ? "Amnesia" : c)
    }
    static var savedFolderName: String {
        if Config.get("BACKUP_DEST") == "folder" {
            let l = (Config.get("BACKUP_LOCAL") as NSString).lastPathComponent
            if !l.isEmpty { return l }
        }
        let f = savedCloud.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
        return f.isEmpty ? "Amnesia" : f
    }

    private func label(_ f: String) -> String {
        f == "@keep" ? T("Keep folder (\(KeepDir.name))", "Folder Keep (\(KeepDir.name))") : f
    }
    private var all: [String] { BackupView.defaults + extra }
    private var remote: String { String(cloud.split(separator: ":", maxSplits: 1).first ?? "") }
    private var host: String { String(server.split(separator: ":", maxSplits: 1).first ?? "") }
    private var portNumber: Int? { Int(port.trimmingCharacters(in: .whitespaces)).flatMap { (1...65535).contains($0) ? $0 : nil } }
    /// Google Drive lewat app resmi (backup disalin ke folder Google Drive di Mac)
    private var viaGoogleApp: Bool { dest == "rclone" && provider.id == "drive" && gMode == "app" }
    private var localTarget: String? { gdrive.map { $0.path + "/" + cleanFolder } }
    private var cleanFolder: String {
        let f = folderName.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "-")
        return f.isEmpty ? "Amnesia" : f
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                PageHeader(title: "Backup", icon: "externaldrive.fill", colors: Pal.backup, back: back)
                Button { showGuide = true } label: {
                    Label(T("How backup works (guide)", "Cara kerja backup (panduan)"), systemImage: "questionmark.circle.fill")
                }
                .buttonStyle(Pill(colors: Pal.gray))
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
                    Toggle(T("Include Profile Vault (your saved app logins, encrypted)",
                             "Sertakan Profile Vault (login app yang tersimpan, terenkripsi)"), isOn: $withVault)
                        .toggleStyle(.checkbox)
                    if !withVault {
                        Note(text: T("Without this, a lost vault (for example 3 wrong passwords) cannot be brought back.",
                                     "Tanpa ini, vault yang hilang (misalnya salah password 3x) tidak bisa dikembalikan."),
                             icon: "exclamationmark.triangle.fill", color: .orange)
                    }
                }
                Card {
                    Field(label: remember ? T("Backup password (leave empty to use the saved one)",
                                              "Password backup (kosongkan = pakai yang tersimpan)")
                                          : T("Backup password", "Password backup"),
                          text: $pw)
                    if !pw.isEmpty {
                        Field(label: T("Repeat password", "Ulangi password"), text: $pw2)
                        MatchNote(a: pw, b: pw2)
                    }
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
        .sheet(isPresented: $showGuide) {
            GuideSheet(T("How backup works", "Cara kerja backup"), close: { showGuide = false }) { guideContent }
        }
        .sheet(isPresented: $showGoogleGuide) {
            GuideSheet(T("Your own Google access", "Akses Google milik sendiri"), close: { showGoogleGuide = false }) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(T("Google is shutting down the shared access rclone uses, so make your own once (about 10 minutes, free):",
                           "Google sedang menutup akses bersama yang dipakai rclone, jadi buat akses sendiri sekali (±10 menit, gratis):"))
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(googleSteps.enumerated()), id: \.offset) { i, t in
                        Text("\(i + 1). " + t).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    }
                    Button(T("Open Google Cloud Console", "Buka Google Cloud Console")) {
                        NSWorkspace.shared.open(URL(string: "https://console.cloud.google.com/apis/credentials")!)
                    }
                }
            }
        }
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
        HStack(alignment: .bottom, spacing: 8) {
            Field(label: T("Server (user@host:folder), e.g. user@remoteserv.er:backup",
                           "Server (user@alamat:folder), mis. user@remoteserv.er:backup"), text: $server, secure: false)
            Field(label: "Port", text: $port, secure: false).frame(width: 70)
        }
        if portNumber == nil {
            Note(text: T("The port is a number from 1 to 65535 (usually 22).", "Port berupa angka 1 sampai 65535 (biasanya 22)."),
                 icon: "xmark.circle.fill", color: .red)
        }
        Field(label: T("Server password (only the first time, never saved)",
                       "Password server (hanya pertama kali, tidak disimpan)"), text: $sshPw)
        Button { connectServer() } label: { Label(T("Connect", "Hubungkan"), systemImage: "bolt.horizontal.fill") }
            .buttonStyle(Pill(colors: Pal.logout))
            .disabled(host.isEmpty || portNumber == nil)
        Note(text: T("No Terminal needed. Amnesia makes an SSH key and installs it on the server with your password, "
                     + "once. It also checks the folder can be written to, and measures your upload speed. "
                     + "Use a folder in your home on the server (no admin rights needed). No folder after the colon? "
                     + "Backups go to amnesia-backup in your home folder on the server.",
                     "Tanpa Terminal. Amnesia membuat kunci SSH dan memasangnya di server pakai password kamu, "
                     + "sekali saja. Folder tujuan juga dicek bisa ditulis, dan kecepatan upload diukur. "
                     + "Pakai folder di home server (tidak butuh hak admin). Tidak ada folder setelah titik dua? "
                     + "Backup masuk ke amnesia-backup di folder home server."))
    }

    private func stepTitle(_ t: String) -> some View {
        Text(t).font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var destText: String {
        guard viaGoogleApp else { return cloud }
        guard let t = localTarget else { return "—" }
        let parent = ((t as NSString).deletingLastPathComponent as NSString).lastPathComponent
        return "Google Drive › " + parent + " › " + cleanFolder
    }

    @ViewBuilder private var cloudBox: some View {
        stepTitle(T("1. Pick your service", "1. Pilih layanan"))
        Picker(T("Service", "Layanan"), selection: $provider) {
            ForEach(cloudProviders) { p in Text(p.name).tag(p) }
        }
        .pickerStyle(.menu)
        .onChange(of: provider) { _, p in cloud = p.remote + ":" + cleanFolder }
        if provider.id == "drive" {
            Picker("", selection: $gMode) {
                Text(T("Through the Google Drive app (recommended)", "Lewat app Google Drive (disarankan)")).tag("app")
                Text(T("Connect directly (advanced)", "Hubungkan langsung (lanjutan)")).tag("direct")
            }
            .pickerStyle(.radioGroup).labelsHidden().font(.system(size: 12))
        }
        if viaGoogleApp {
            stepTitle(T("2. The Google Drive app", "2. App Google Drive"))
            if let g = gdrive {
                Note(text: T("Found, signed in as \(g.account). Nothing to log in here: Amnesia puts the backup in your Google "
                             + "Drive folder and the Google Drive app uploads it.",
                             "Ketemu, login sebagai \(g.account). Tidak perlu login lagi: Amnesia menaruh backup di folder "
                             + "Google Drive dan app Google Drive yang mengunggahnya."),
                     icon: "checkmark.circle.fill", color: .green)
            } else if gState == "checking" {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(T("Looking for the Google Drive app…", "Mencari app Google Drive…")).font(.system(size: 12))
                }
            } else {
                if gState == "syncing" {
                    Note(text: T("Google Drive is signed in, but isn't ready yet (it's still syncing). Wait until it's done, "
                                 + "then press Check Again.",
                                 "Google Drive sudah login, tapi belum siap (masih sinkron). Tunggu sampai selesai, "
                                 + "lalu tekan Cek Lagi."),
                         icon: "hourglass", color: .orange)
                } else if !googleDriveInstalled() {
                    Note(text: T("The Google Drive app isn't installed. It's free from Google. Or pick another service, "
                                 + "or Connect directly.",
                                 "App Google Drive belum terpasang. Gratis dari Google. Atau pilih layanan lain, atau Hubungkan langsung."),
                         icon: "exclamationmark.triangle.fill", color: .orange)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(T("1. Open the Google Drive app and sign in.", "1. Buka app Google Drive dan login."))
                    Text(T("2. Wait until syncing is done (Google Drive icon in the menu bar).",
                           "2. Tunggu sampai sinkron selesai (ikon Google Drive di menu bar)."))
                    Text(T("3. Press Check Again.", "3. Tekan Cek Lagi."))
                }
                .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if !googleDriveInstalled() {
                        Button { NSWorkspace.shared.open(URL(string: "https://www.google.com/drive/download/")!) } label: {
                            Label(T("Download Google Drive", "Download Google Drive"), systemImage: "arrow.down.circle.fill")
                        }
                        .buttonStyle(Pill(colors: Pal.logout))
                    }
                    Button { checkGoogleDrive() } label: {
                        Label(T("Check Again", "Cek Lagi"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(Pill(colors: Pal.gray))
                }
            }
        } else {
            stepTitle(T("2. Connect", "2. Hubungkan"))
            if provider.id == "drive" { googleOwnAccess }
            if connected.contains(remote) {
                Note(text: user[remote].map { T("Connected as \($0).", "Terhubung sebagai \($0).") }
                     ?? T("\(provider.name) is connected.", "\(provider.name) sudah terhubung."),
                     icon: "checkmark.circle.fill", color: .green)
            }
            Button { setupCloud() } label: {
                Label(connected.contains(remote) ? T("Reconnect \(provider.name)", "Hubungkan ulang \(provider.name)")
                                                 : T("Connect \(provider.name)", "Hubungkan \(provider.name)"),
                      systemImage: "icloud.and.arrow.up.fill")
            }
            .buttonStyle(Pill(colors: Pal.logout))
            Text(T("The login page opens in your browser. Log in there and press Allow; no Terminal needed.",
                   "Halaman login terbuka di browser. Login di sana lalu tekan Allow / Izinkan; tanpa Terminal."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        stepTitle(T("3. Folder name", "3. Nama folder"))
        Field(label: T("Backups go into this folder", "Backup masuk ke folder ini"), text: Binding(get: { folderName }, set: { v in
            folderName = v
            cloud = (remote.isEmpty ? provider.remote : remote) + ":" + cleanFolder
        }), secure: false)
        Text(T("Destination: ", "Tujuan: ") + destText)
            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        DisclosureGroup(T("Advanced", "Lanjutan")) {
            VStack(alignment: .leading, spacing: 8) {
                Field(label: T("rclone destination (remote:folder)", "Tujuan rclone (remote:folder)"), text: $cloud, secure: false)
                Note(text: T("S3, WebDAV, SFTP and 40+ more services work too: set them up with rclone config in Terminal, "
                             + "then type the remote name above.",
                             "S3, WebDAV, SFTP dan 40+ layanan lain juga bisa: atur lewat rclone config di Terminal, "
                             + "lalu ketik nama remote-nya di atas."))
            }
            .padding(.top, 6)
        }
        .font(.system(size: 12))
    }

    /// Google Drive langsung: akses Google milik user sendiri (akses bersama rclone sedang dihentikan Google).
    @ViewBuilder private var googleOwnAccess: some View {
        Text(T("Google Drive needs your own Google access (one time, about 10 minutes, free).",
               "Google Drive butuh akses Google milik sendiri (sekali saja, ±10 menit, gratis)."))
            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Button { showGoogleGuide = true } label: {
            Label(T("Show me how (7 steps)", "Lihat caranya (7 langkah)"), systemImage: "questionmark.circle.fill")
        }
        .buttonStyle(Pill(colors: Pal.gray))
        Field(label: "Client ID", text: $clientID, secure: false)
        Field(label: "Client Secret", text: $clientSecret)
    }

    private var googleSteps: [String] {
        [T("Open Google Cloud Console and sign in with your Google account.", "Buka Google Cloud Console dan login dengan akun Google."),
         T("Create a new project.", "Buat project baru."),
         T("APIs & Services → Library: turn on \"Google Drive API\".", "APIs & Services → Library: aktifkan \"Google Drive API\"."),
         T("OAuth consent screen: fill in the app name and your email, then set the status to \"In production\" "
           + "(otherwise the login expires every 7 days).",
           "OAuth consent screen: isi nama app dan email kamu, lalu ubah status ke \"In production\" "
           + "(kalau tidak, login kedaluwarsa tiap 7 hari)."),
         T("Credentials → Create credentials → OAuth client ID, type \"Desktop app\".",
           "Credentials → Create credentials → OAuth client ID, jenis \"Desktop app\"."),
         T("Copy the Client ID and Client Secret into the boxes below.", "Salin Client ID dan Client Secret ke kotak di bawah."),
         T("Press Connect. Google warns \"app isn't verified\": that's your own app, click Advanced → Go to (your app).",
           "Tekan Hubungkan. Google memperingatkan \"app belum diverifikasi\": itu app kamu sendiri, klik Advanced → Go to (nama app).")]
    }

    /// Panduan singkat di dalam app (popup).
    private var guideContent: some View {
        VStack(alignment: .leading, spacing: 10) {
                    guideItem("externaldrive.fill", T("USB / SSD", "Flashdisk / SSD"),
                              T("Plug in, pick the drive, press Back Up Now. Fast: usually seconds to a few minutes. "
                                + "Check: open the drive in Finder, the file is called amnesia_backup_….7z.",
                                "Colok, pilih drive-nya, tekan Backup Sekarang. Cepat: biasanya detik sampai beberapa menit. "
                                + "Cek: buka drive di Finder, nama filenya amnesia_backup_….7z."))
                    guideItem("server.rack", T("SSH server", "Server SSH"),
                              T("Type user@address:folder, with a folder in your home on the server (e.g. backup), and the port if it isn't 22. "
                                + "Press Connect once. The speed depends on your internet upload: Connect shows an estimate. "
                                + "Check: on the server, run ls -lh ~/backup.",
                                "Ketik user@alamat:folder, dengan folder di home server (mis. backup), dan port kalau bukan 22. "
                                + "Tekan Hubungkan sekali. Kecepatannya tergantung upload internet kamu: Hubungkan menampilkan perkiraan. "
                                + "Cek: di server, jalankan ls -lh ~/backup."))
                    guideItem("icloud.fill", "Cloud",
                              T("Google Drive: easiest through the Google Drive app. Other services: press Connect and log in in your browser. "
                                + "Check: open the service's website, folder \(cleanFolder).",
                                "Google Drive: paling mudah lewat app Google Drive. Layanan lain: tekan Hubungkan lalu login di browser. "
                                + "Cek: buka website layanan itu, folder \(cleanFolder)."))
                    guideItem("clock.fill", T("How long?", "Berapa lama?"),
                              T("Size ÷ speed. Example: 100 MB at 1 MB/s takes about 2 minutes, at 100 KB/s about 17 minutes. "
                                + "The progress bar shows the speed and the time left.",
                                "Ukuran ÷ kecepatan. Contoh: 100 MB di 1 MB/s sekitar 2 menit, di 100 KB/s sekitar 17 menit. "
                                + "Progress bar menampilkan kecepatan dan sisa waktu."))
                    guideItem("lock.fill", T("Password", "Password"),
                              T("Every backup is a locked .7z file. Keep the password safe: without it the backup can't be opened. "
                                + "Each backup's SHA256 checksum is in ~/.amnesia/backup_checksums.txt.",
                                "Setiap backup adalah file .7z terkunci. Simpan password-nya baik-baik: tanpa itu backup tidak bisa dibuka. "
                                + "Checksum SHA256 tiap backup ada di ~/.amnesia/backup_checksums.txt."))
                }
    }

    private func guideItem(_ icon: String, _ t: String, _ sub: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(.pink).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(t).font(.system(size: 12, weight: .semibold))
                Text(sub).font(.system(size: 11, weight: .regular)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
        checkGoogleDrive()
    }

    /// Dicek di background: folder Google Drive yang belum siap bisa membuat Finder/app menunggu lama.
    private func checkGoogleDrive() {
        gState = "checking"
        m.quiet({ (googleDriveFolder(), googleDriveSignedIn()) }) { r in
            gdrive = r.0
            gState = r.0 != nil ? "ready" : (r.1 ? "syncing" : "none")
        }
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
        if dest == "ssh" && portNumber == nil {
            info("Backup", T("The port is a number from 1 to 65535 (usually 22).", "Port berupa angka 1 sampai 65535 (biasanya 22)."),
                 error: true); return false
        }
        if viaGoogleApp && localTarget == nil {
            info("Backup", T("The Google Drive app isn't ready yet (installed and signed in). Or pick Connect directly.",
                             "App Google Drive belum siap (terpasang dan login). Atau pilih Hubungkan langsung."), error: true)
            return false
        }
        if dest == "rclone" && !viaGoogleApp && (remote.isEmpty || !cloud.contains(":")) {
            info("Backup", T("Pick a service and connect it first.", "Pilih layanan dan hubungkan dulu."), error: true)
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
        Config.set("BACKUP_DEST", viaGoogleApp ? "folder" : dest)
        Config.set("BACKUP_DRIVE", drive)
        Config.set("BACKUP_SSH", server)
        Config.set("BACKUP_SSH_PORT", String(portNumber ?? 22))
        Config.set("BACKUP_RCLONE", cloud)
        Config.set("BACKUP_CLOUD", provider.id)
        Config.set("BACKUP_GMODE", gMode)
        Config.set("BACKUP_GCLIENT", clientID.trimmingCharacters(in: .whitespaces))
        if viaGoogleApp, let t = localTarget {
            Config.set("BACKUP_LOCAL", t.hasPrefix(P.home + "/") ? "~/" + String(t.dropFirst(P.home.count + 1)) : t)
            // app Google Drive harus tetap login setelah Mac dibersihkan
            let have = Keep.entries()
            let add = googleDriveKeep.filter { !have.contains($0) }
            if !add.isEmpty { Keep.add(add) }
        }
        Config.set("BACKUP_FOLDERS", sel.joined(separator: ","))
        Config.set("BACKUP_VAULT", withVault ? "1" : "0")
        Config.set("BACKUP_SCHEDULE", schedule)
        return true
    }

    private var destLabel: String {
        switch dest {
        case "drive": return drive
        case "ssh": return host
        default: return viaGoogleApp ? "Google Drive" : cloud
        }
    }

    private func start() {
        guard save() else { return }
        let typed = pw
        guard !typed.isEmpty || remember else { info("Backup", T("Type the backup password.", "Isi password backup."), error: true); return }
        let to = destLabel
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let started = f.string(from: Date())
        let which = T("The backup to \(to) (started \(started))", "Backup ke \(to) (mulai \(started))")
        let job = JobBox()
        let hint = dest == "drive" ? T("Don't unplug the drive.", "Jangan cabut drive-nya.")
            : viaGoogleApp ? T("The Google Drive app uploads it afterwards.", "Setelah itu app Google Drive yang mengunggahnya.")
            : T("Keep the internet on.", "Jangan matikan internet.")
        m.background(T("Backing up to \(to)…\n", "Backup ke \(to)…\n") + hint, job: job,
                     { () -> (ok: Bool, msg: String, code: Int32) in
            guard let p = typed.isEmpty ? Secret.get() : typed else {
                return (false, T("Couldn't read the saved password.", "Password tersimpan tidak bisa dibaca."), 1)
            }
            return runBackup(p, job: job, progress: Model.progressSink)
        }) { r in
            status = lastBackupStatus()
            if r.ok {
                pw = ""; pw2 = ""
                let extra = viaGoogleApp ? T("\n\nThe Google Drive app now uploads it in the background.",
                                             "\n\nApp Google Drive sekarang mengunggahnya di background.") : ""
                info(T("Backup done", "Backup berhasil"), which + ":\n" + r.msg.replacingOccurrences(of: "OK: ", with: "")
                     + extra + T("\n\nSHA256 checksum saved in backup_checksums.txt.",
                                 "\n\nChecksum SHA256 dicatat di backup_checksums.txt."))
            } else if job.cancelled {
                info(T("Backup cancelled", "Backup dibatalkan"),
                     which + T(" was cancelled. Previous backups are safe; the unfinished file was removed.",
                               " dibatalkan. Backup sebelumnya tetap aman; file yang belum selesai sudah dihapus."))
            } else if job.stalled {
                info(T("Backup stopped", "Backup dihentikan"),
                     which + T(" didn't move for 10 minutes (the internet or the server stopped answering), so Amnesia stopped it. "
                               + "Previous backups are safe. Try again later.",
                               " tidak bergerak selama 10 menit (internet atau server tidak menjawab), jadi Amnesia menghentikannya. "
                               + "Backup sebelumnya tetap aman. Coba lagi nanti."), error: true)
            } else if [130, 143, 15, 9].contains(r.code) {
                info(T("Backup stopped", "Backup dihentikan"),
                     which + T(" was stopped from outside Amnesia (for example by a Terminal command). Previous backups are safe; "
                               + "the unfinished file was removed.",
                               " dihentikan dari luar Amnesia (misalnya oleh perintah di Terminal). Backup sebelumnya tetap aman; "
                               + "file yang belum selesai sudah dihapus."), error: true)
            } else {
                info(T("Backup failed", "Backup gagal"), which + ":\n" + stripFail(r.msg), error: true)
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
        guard let pn = portNumber else { return }
        server = srv
        connect(srv, pn, pw, forget: false)
    }

    private func connect(_ srv: String, _ pn: Int, _ pw: String, forget: Bool) {
        m.background(T("Connecting to \(host)…\nThen testing the folder and the upload speed.",
                       "Menghubungi \(host)…\nLalu mengetes folder dan kecepatan upload."),
                     { connectSSH(srv, port: pn, password: pw, forgetOldKey: forget) }) { r in
            if r.hostChanged {
                if confirm(T("Server changed", "Server berubah"),
                           r.msg + "\n\n" + T("Was the server reinstalled? Then forget the old identity and connect again "
                                              + "(you may need the server password once).",
                                              "Server baru diinstal ulang? Lupakan identitas lama lalu hubungkan lagi "
                                              + "(mungkin perlu password server sekali)."),
                           ok: T("Yes, reconnect", "Ya, hubungkan lagi")) {
                    connect(srv, pn, pw, forget: true)
                } else { sshPw = "" }
                return
            }
            sshPw = ""
            if r.ok {
                Config.set("BACKUP_SSH", srv)
                Config.set("BACKUP_SSH_PORT", String(pn))
                info(T("Connected", "Terhubung"), r.msg)
            } else {
                info(T("Couldn't connect", "Koneksi gagal"), r.msg, error: true)
            }
        }
    }

    /// Cek remote rclone yang sudah terhubung (diam-diam), plus nama akunnya.
    private func checkCloud() {
        let r = remote
        m.quiet({ () -> ([String], String?) in
            let list = rcloneRemotes()
            return (list, list.contains(r) ? cloudUser(r) : nil)
        }) { res in
            connected = res.0
            if let u = res.1 { user[r] = u }
        }
    }

    private func setupCloud() {
        let p = provider
        if remote.isEmpty { cloud = p.remote + ":" + cleanFolder }
        let name = remote
        let id = p.id == "drive" ? clientID.trimmingCharacters(in: .whitespaces) : ""
        let sec = p.id == "drive" ? clientSecret.trimmingCharacters(in: .whitespaces) : ""
        if !id.isEmpty && sec.isEmpty {
            info(p.name, T("Also paste the Client Secret.", "Tempel juga Client Secret-nya."), error: true)
            return
        }
        let browser = defaultBrowser().map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            ?? "Safari"
        let job = JobBox()
        m.background(T("Log in to \(p.name) in \(browser), then press Allow.\nCome back here afterwards. Amnesia waits up to 5 minutes.",
                       "Login ke \(p.name) di \(browser), lalu tekan Allow / Izinkan.\nSetelah itu kembali ke sini. Amnesia menunggu sampai 5 menit."),
                     job: job,
                     { connectCloud(p, remote: name, clientID: id, secret: sec, job: job, onURL: { url in
                         Task { @MainActor in
                             Model.shared.loginURL = url
                             if defaultBrowser() == nil { openInBrowser(url) }   // Mac baru tanpa browser default: Safari
                         }
                     }) }) { err in
            if err == "CANCELLED" {
                info(p.name, T("Login cancelled. Nothing was changed.", "Login dibatalkan. Tidak ada yang diubah."))
            } else if let e = err {
                info(p.name, e, error: true)
            } else {
                clientSecret = ""
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
    @State private var atLogin = Setting.openAtLogin.isOn
    @State private var light = Setting.vaultLight.isOn

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
                row(T("Open at login", "Buka saat login"),
                    T("Amnesia starts by itself in the menu bar every time you log in, also while it is turned off. "
                      + "Takes effect from the next login.",
                      "Amnesia jalan sendiri di menu bar setiap kamu login, juga saat sedang dimatikan. "
                      + "Berlaku mulai login berikutnya."),
                    "power.circle.fill", Pal.keep, $atLogin) { Setting.openAtLogin.set($0); Agent.LoginItem.sync() }
                row(T("Light Chrome snapshot", "Snapshot Chrome ringan"),
                    T("Skips Chrome's extension program files and caches (about 1 GB → 150 MB). Logins, bookmarks and "
                      + "extension settings are kept. After Restore, Chrome downloads the extensions again from the "
                      + "Web Store (needs internet). Extensions not from the Web Store do not come back.",
                      "Melewati file program extension dan cache Chrome (sekitar 1 GB → 150 MB). Login, bookmark dan "
                      + "pengaturan extension tetap disimpan. Setelah Restore, Chrome mengunduh ulang extension dari "
                      + "Web Store (butuh internet). Extension yang bukan dari Web Store tidak kembali."),
                    "leaf.fill", Pal.vault, $light) { Setting.vaultLight.set($0) }
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
                        Note(text: T("Pressed \"Limit Access\" or \"Don't Allow\" by mistake? Open Privacy Settings → "
                                     + "Full Disk Access, switch Amnesia on, then Quit & Reopen.",
                                     "Terlanjur menekan \"Limit Access\" atau \"Don't Allow\"? Buka Pengaturan Privasi → "
                                     + "Full Disk Access, nyalakan Amnesia, lalu Tutup & Buka Lagi."))
                        HStack {
                            Button(T("Open Privacy Settings", "Buka Pengaturan Privasi")) { Engine.openFullDiskSettings() }
                            Button(T("Quit & Reopen", "Tutup & Buka Lagi")) { Engine.relaunch() }
                                .disabled(m.busy != nil)
                                .help(T("Wait until the current job is finished.", "Tunggu sampai proses yang jalan selesai."))
                        }
                    }
                }
                Button { m.page = .move } label: {
                    Label(T("Move to a new Mac", "Pindah ke Mac baru"), systemImage: "arrow.right.arrow.left.circle.fill")
                }
                .buttonStyle(Pill(colors: Pal.backup))
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

/// Ikon 1 baris: ikon app, ikon jenis file, atau thumbnail asli (dibuat saat terlihat saja).
struct DryRowIcon: View {
    let item: DryItem
    @State private var img: NSImage?

    private var symbolName: String {
        if case .symbol(let s) = item.icon { return s }
        return "doc"
    }

    var body: some View {
        Group {
            if let i = img {
                Image(nsImage: i).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: symbolName).font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 22, height: 22)
        .task(id: item.id) { await load() }
    }

    private func load() async {
        switch item.icon {
        case .symbol: return
        case .app(let path): img = NSWorkspace.shared.icon(forFile: path)
        case .file(let path):
            img = NSWorkspace.shared.icon(forFile: path)
            guard item.thumb, !Shots.on else { return }
            let req = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: path), size: CGSize(width: 44, height: 44),
                                                   scale: 2, representationTypes: .thumbnail)
            if let t = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: req) {
                img = t.nsImage
            }
        }
    }
}

struct PreviewView: View {
    @EnvironmentObject var m: Model
    let back: () -> Void
    @State private var open: Set<String> = []
    @State private var showPath: Set<String> = []
    @State private var sizes: [String: String] = [:]
    @State private var showSystem = false

    private var all: [DryGroup] { m.report ?? [] }
    private var shown: [DryGroup] { all.filter { showSystem || !$0.system } }
    private var hiddenCount: Int { all.filter(\.system).reduce(0) { $0 + $1.items.count } }

    /// Jam pembaruan yang pasti (misal "Diperbarui hari ini 15:20"), bukan "0 detik lalu".
    private var updated: String {
        if m.reportBusy { return T("Updating…", "Memperbarui…") }
        guard let d = m.reportTime else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: Lang.current == .id ? "id_ID" : "en_US")
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return T("Updated ", "Diperbarui ") + f.string(from: d)
    }

    private var total: Int { all.reduce(0) { $0 + $1.items.count } }

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
            if m.report != nil {
                HStack {
                    Text(T("\(total) items", "\(total) item")).font(.system(size: 20, weight: .bold, design: .rounded))
                    Spacer()
                    Text(T("click a group for details", "klik kelompok untuk detail")).font(.system(size: 11)).foregroundStyle(.secondary)
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
                        ForEach(shown) { grp in group(grp) }
                        if hiddenCount > 0 {
                            Toggle(T("Show macOS system data (\(hiddenCount) items, made again automatically)",
                                     "Tampilkan data sistem macOS (\(hiddenCount) item, dibuat ulang otomatis)"), isOn: $showSystem)
                                .toggleStyle(.checkbox).font(.system(size: 11)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }
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

    private func colors(_ id: String) -> [Color] {
        switch id {
        case "vault": return Pal.vault
        case "files": return Pal.backup
        case "apple": return Pal.gray
        case "apps": return Pal.logout
        case "keychain": return Pal.pause
        case "traces": return Pal.keep
        default: return Pal.gray
        }
    }

    private func group(_ grp: DryGroup) -> some View {
        let isOpen = open.contains(grp.id)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isOpen { _ = open.remove(grp.id) } else { _ = open.insert(grp.id) }
                }
                if !isOpen { measure(grp) }
            } label: {
                HStack(spacing: 10) {
                    IconBadge(icon: grp.symbol, colors: colors(grp.id), size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(grp.name).font(.system(size: 13, weight: .semibold))
                        Text(grp.note).font(.system(size: 10)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(grp.items.count)").font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(Color.pink.opacity(0.15)))
                        if let sz = sizes[grp.id], !sz.isEmpty {
                            Text(sz).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        }
                    }
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                        .rotationEffect(.degrees(isOpen ? 90 : 0)).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())      // seluruh baris bisa diklik, bukan cuma panahnya
            }
            .buttonStyle(.plain)
            if isOpen {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(grp.items.prefix(300))) { i in row(i) }
                    if grp.items.count > 300 {
                        Text(T("…and \(grp.items.count - 300) more", "…dan \(grp.items.count - 300) lagi"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
    }

    /// 1 baris: ikon + nama yang jelas. Path lengkap muncul saat disorot atau diklik.
    private func row(_ i: DryItem) -> some View {
        let full = showPath.contains(i.id)
        return Button {
            if full { _ = showPath.remove(i.id) } else { _ = showPath.insert(i.id) }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                DryRowIcon(item: i)
                VStack(alignment: .leading, spacing: 1) {
                    Text(i.title).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Text(full ? i.shown : i.detail).font(.system(size: 10, design: full ? .monospaced : .default))
                        .foregroundStyle(.secondary)
                        .lineLimit(full ? nil : 1).truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(i.shown)
    }

    /// Ukuran kelompok dihitung saat dibuka (di background).
    private func measure(_ grp: DryGroup) {
        guard sizes[grp.id] == nil, !Shots.on else { return }
        let rels = grp.items.filter { !$0.keychain }.map(\.rel)
        guard !rels.isEmpty else { return }
        sizes[grp.id] = ""
        DispatchQueue.global(qos: .utility).async {
            let s = pathsSize(rels)
            Task { @MainActor in sizes[grp.id] = s }
        }
    }

    /// Laporan lama langsung tampil; yang baru disiapkan di background.
    /// Laporan baru dibuat lagi kalau yang ada sudah lebih dari 1 menit (atau logout sedang ditahan).
    private func load() {
        if Shots.on { return }
        let age = m.reportTime.map { Date().timeIntervalSince($0) } ?? .infinity
        if age > 60 || m.pending != nil { m.updateReport() }
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
                    Text((m.progressText.isEmpty ? b : m.progressText) + (m.progress.map { " \(Int($0 * 100))%" } ?? ""))
                        .font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                    if m.job != nil {
                        Button(T("Cancel", "Batal")) { m.cancelJob() }.controlSize(.small)
                    }
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

    /// --lang en|id: hanya 1 bahasa (screenshots.sh menjalankan per bahasa, jadi 1 masalah tidak menghentikan semuanya)
    static var langs: [Lang] {
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--lang"), i + 1 < a.count, let l = Lang(rawValue: a[i + 1]) { return [l] }
        return Lang.allCases
    }

    /// Catatan langkah ke stderr (screenshots.sh menyimpannya di ~/.amnesia/shots.log)
    static func log(_ s: String) { FileHandle.standardError.write(Data(("shots: " + s + "\n").utf8)) }

    static func wait(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }

    static var running = false

    static func run() async {
        running = true
        // macOS boleh menutup app tanpa jendela secara otomatis. Saat menyiapkan daftar "yang akan dihapus"
        // (lama, tanpa jendela) itu membuat app keluar diam-diam. Dimatikan selama mode screenshot.
        ProcessInfo.processInfo.disableAutomaticTermination("screenshots")
        ProcessInfo.processInfo.disableSuddenTermination()
        let m = Model.shared
        m.onboarded = true
        await wait(3)
        for lang in langs {
            log("language \(lang.rawValue)")
            m.lang = lang
            await wait(2.5)
            let cleanLog = (try? String(contentsOfFile: P.cleanLog, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            m.lastClean = T("Last: ", "Terakhir: ") + cleanLog
            let out = dir + "/" + lang.rawValue
            try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
            await shot(Shell { OnboardingView(step: 0) }, out + "/tour-welcome.png")
            await shot(Shell { OnboardingView(step: 1) }, out + "/tour-terms.png")
            await shot(Shell { OnboardingView(step: 3) }, out + "/tour-check.png")
            await shot(Shell { OnboardingView(step: 4) }, out + "/tour-apps.png")
            await shot(Shell { OnboardingView(keepSetup: true) }, out + "/keep-setup.png", settle: 4)
            let pages: [(Page, String)] = [(.home, "home"), (.vault, "vault"), (.keep, "keep"), (.backup, "backup"),
                                           (.settings, "settings"), (.move, "move")]
            for (page, name) in pages {
                m.page = page
                await shot(MainView(), out + "/\(name).png")
            }
            m.page = .home
            await shot(MainView(), out + "/home-dark.png", dark: true)
            await shot(MenuPanel().background(Color(nsColor: .windowBackgroundColor)), out + "/menu.png", window: false)
            log("preparing what-gets-deleted list")
            let r = await Task.detached { dryRun() }.value
            let pats = m.vault?.patterns ?? [:]
            let g = await Task.detached { categorize(r, patterns: pats) }.value
            m.rawReport = r
            m.report = g
            m.reportTime = Date()
            log("list has \(g.count) groups")
            m.page = .preview
            await shot(MainView(), out + "/preview.png")
        }
        log("done")
        running = false
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
        log("shot " + (path as NSString).lastPathComponent)
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
        } else {
            log("could not draw " + path)
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

/// Jendela utama ingat posisinya sendiri (tidak loncat ke tengah saat dibuka lagi atau saat popup muncul/tutup).
struct WindowKeeper: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        let skip = Shots.on
        DispatchQueue.main.async {
            guard !skip, let w = v.window, w.frameAutosaveName != "AmnesiaMain" else { return }
            w.setFrameUsingName("AmnesiaMain")
            w.setFrameAutosaveName("AmnesiaMain")
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

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
        if Shots.running { return .terminateCancel }   // mode screenshot belum selesai
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

    // Jendela ditutup → app tetap jalan (ikon menu bar), juga saat mode screenshot.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

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
