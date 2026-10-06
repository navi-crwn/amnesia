// Amnesia v5.3 — app Mac asli (SwiftUI): jendela utama + ikon status di menu bar.
// Dibuild oleh build.sh (swiftc dari Command Line Tools, tanpa Xcode).
// Logika berat tetap di ~/.amnesia: clean.sh, agent.sh, vault.py (dipanggil lewat Process).
import AppKit
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

struct VaultReply: Decodable {
    let ok: Bool
    let error: String?
    let exists: Bool?
    let manifest: Manifest?
    let attempts: Int?
    let max: Int?
    let min: Int?
    let apps: [String]?

    static func fail(_ msg: String) -> VaultReply {
        VaultReply(ok: false, error: msg, exists: nil, manifest: nil, attempts: nil, max: nil, min: nil, apps: nil)
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

// MARK: - Backup ke drive

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

func appendLine(_ line: String, to path: String) {
    if let h = FileHandle(forWritingAtPath: path) {
        h.seekToEndOfFile()
        h.write(Data(line.utf8))
        h.closeFile()
    } else {
        try? line.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

/// Hasil: pesan error (nil = berhasil) dan ukuran MB.
func runBackup(target: String, folders: [String], input: String) -> (error: String?, mb: Double) {
    let fm = FileManager.default
    guard fm.isExecutableFile(atPath: P.sevenz) else {
        return ("7zz tidak ditemukan. Jalankan di Terminal: brew install sevenzip", 0)
    }
    let r = sh(P.sevenz, ["a", "-t7z", "-m0=lzma2", "-mx=5", "-mhe=on", "-p", "-bso0", "-bsp0", target]
        + folders + ["-xr!node_modules", "-xr!.DS_Store"], input: input, cwd: P.home)
    guard r.code == 0 || r.code == 1, fm.fileExists(atPath: target) else {
        return ("7zz gagal (kode \(r.code)):\n" + String(r.err.suffix(300)), 0)
    }
    let s = sh("/usr/bin/shasum", ["-a", "256", target])
    let hash = s.out.split(separator: " ").first.map(String.init) ?? "?"
    appendLine("\(hash)  \(target)\n", to: P.checksums)
    let attrs = try? fm.attributesOfItem(atPath: target)
    let size = (attrs?[.size] as? NSNumber)?.doubleValue ?? 0
    return (nil, size / 1_048_576)
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
    @Published var state: AState = .off
    @Published var lastClean = ""
    @Published var vault: VaultReply?
    @Published var busy: String?
    private var timer: Timer?

    init() {
        refresh()
        refreshVault()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
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
            "ExitTimeOut": 120,
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

enum Page { case home, vault, keep, backup }

struct MainView: View {
    @EnvironmentObject var m: Model
    @Environment(\.openWindow) private var openWindow
    @State private var page: Page = .home

    var body: some View {
        ZStack {
            Backdrop()
            Group {
                switch page {
                case .home: home
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
        .animation(.easeInOut(duration: 0.2), value: page)
        .onAppear {
            Opener.open = { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
            m.refresh()
            m.refreshVault()
        }
    }

    private func goHome() { page = .home; m.refreshVault() }

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
            }
            HeroCard(state: m.state, lastClean: m.lastClean)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                      spacing: 14) {
                Tile(title: "Profile Vault", sub: vaultSub, icon: "lock.rectangle.stack.fill",
                     colors: Pal.vault) { page = .vault }
                Tile(title: "Simpan & Logout", sub: "Simpan login Chrome, Claude, OpenCode lalu logout",
                     icon: "rectangle.portrait.and.arrow.right", colors: Pal.logout) { m.saveAndLogout() }
                Tile(title: m.state == .paused ? "Batalkan Jeda" : "Jeda 1 Sesi",
                     sub: m.state == .off ? "Aktifkan Amnesia dulu" : "Lewati 1x logout & login berikutnya",
                     icon: "pause.fill", colors: Pal.pause) { m.togglePause() }
                    .disabled(m.state == .off)
                Tile(title: "Keep List", sub: "\(Keep.entries().count) item tidak dihapus",
                     icon: "pin.fill", colors: Pal.keep) { page = .keep }
                Tile(title: "Backup", sub: "Salin terenkripsi ke SSD / flashdisk",
                     icon: "externaldrive.fill", colors: Pal.backup) { page = .backup }
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
    @State private var drives: [Drive] = []
    @State private var drive = ""
    @State private var folders: Set<String> = ["Keep"]
    @State private var pw = ""
    @State private var pw2 = ""
    private let all = ["Keep", "Documents", "Desktop", "Downloads", "Pictures", "Music", "Movies"]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                PageHeader(title: "Backup", icon: "externaldrive.fill", colors: Pal.backup, back: back)
                Note(text: "File .7z terenkripsi AES-256. Nama file di dalamnya juga ikut terenkripsi.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Card {
                    HStack {
                        Text("Drive tujuan").font(.system(size: 13, weight: .semibold))
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
                Card {
                    Text("Folder").font(.system(size: 13, weight: .semibold))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading,
                              spacing: 8) {
                        ForEach(all, id: \.self) { f in
                            Toggle(f, isOn: Binding(get: { folders.contains(f) },
                                                    set: { on in if on { folders.insert(f) } else { folders.remove(f) } }))
                                .toggleStyle(.checkbox)
                        }
                    }
                }
                Card {
                    Field(label: "Password enkripsi", text: $pw)
                    Field(label: "Ulangi password", text: $pw2)
                    Note(text: "Simpan password ini. Tanpa password, backup tidak bisa dibuka.",
                         icon: "exclamationmark.triangle.fill", color: .orange)
                }
                Button { start() } label: { Label("Mulai Backup", systemImage: "arrow.down.doc.fill") }
                    .buttonStyle(Pill(colors: Pal.backup))
                    .disabled(drive.isEmpty || pw.isEmpty)
            }
        }
        .scrollIndicators(.never)
        .onAppear { load() }
    }

    private func load() {
        drives = listDrives()
        if !drives.contains(where: { $0.name == drive }) { drive = drives.first?.name ?? "" }
    }

    private func start() {
        let fm = FileManager.default
        let sel = all.filter { folders.contains($0) && fm.fileExists(atPath: P.home + "/" + $0) }
        guard !sel.isEmpty else { info("Backup", "Pilih minimal 1 folder.", error: true); return }
        guard pw == pw2 else { info("Backup", "Password tidak cocok.", error: true); return }
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmm"
        let target = "/Volumes/\(drive)/amnesia_backup_\(f.string(from: Date())).7z"
        let input = pw + "\n" + pw + "\n"
        let d = drive
        m.background("Backup ke \(d)…\nJangan cabut drive.",
                     { runBackup(target: target, folders: sel, input: input) }) { r in
            if let err = r.error {
                info("Backup gagal", err, error: true)
            } else {
                pw = ""; pw2 = ""
                info("Backup berhasil", "\((target as NSString).lastPathComponent)\n"
                     + String(format: "%.1f MB di %@", r.mb, d)
                     + "\n\nChecksum SHA256 dicatat di backup_checksums.txt.")
                back()
            }
        }
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

    // Ikon app diklik lagi (Finder/Desktop) saat app sudah jalan → buka jendela utama.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Opener.open?() }
        return true
    }
}

@main
struct AmnesiaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = Model()
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
