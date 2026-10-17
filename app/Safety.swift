// Amnesia v5.22 — pengaman tambahan: folder yang dilewati (symlink, iCloud Desktop & Dokumen), Kunci Keep,
// Brankas (disk terenkripsi di folder Keep), halaman Cek kesehatan dan Batasan, meter kekuatan password,
// dan saran app untuk Profile Vault. Dibuild bersama Amnesia.swift dan Extras.swift (lihat build.sh).
// Pekerjaan berat tetap di ~/.amnesia: keeplock.sh (kunci + Brankas), clean.sh --skips, vault.py.
import AppKit
import Security
import SwiftUI

// MARK: - Folder yang dilewati clean.sh

/// clean.sh tidak mengosongkan folder yang berupa symlink, dan tidak menyentuh Desktop & Documents kalau
/// iCloud "Desktop & Documents" menyala (menghapus di sana = menghapus di iCloud dan semua perangkat Apple kamu).
enum Skipped {
    struct Item: Hashable, Sendable {
        let folder: String      // "~/Desktop"
        let why: String         // "symlink" | "icloud"
    }

    /// clean.sh --skips: cepat, hanya membaca. Kosong = tidak ada yang dilewati.
    static func list() -> [Item] {
        parse(sh("/bin/bash", [P.a + "/clean.sh", "--skips"], timeout: 15).out)
    }

    /// Baris "LEWATI  ~/Desktop (icloud)" (juga ada di hasil --dry-run).
    static func parse(_ text: String) -> [Item] {
        var out: [Item] = []
        for l in text.split(separator: "\n") where l.hasPrefix("LEWATI ") {
            let rest = l.dropFirst(7).trimmingCharacters(in: .whitespaces)
            guard rest.hasSuffix(")"), let open = rest.range(of: " (", options: .backwards) else { continue }
            let it = Item(folder: String(rest[..<open.lowerBound]),
                          why: String(rest[open.upperBound..<rest.index(before: rest.endIndex)]))
            if !out.contains(it) { out.append(it) }
        }
        return out
    }

    /// Kalimat untuk ditampilkan (1 baris per alasan).
    static func lines(_ items: [Item]) -> [String] {
        var out: [String] = []
        if items.contains(where: { $0.why == "icloud" }) {
            out.append(T("iCloud Desktop & Documents is on, so Amnesia does not wipe Desktop and Documents. Wiping them "
                         + "would delete the files in iCloud and on your other Apple devices too. Turn it off in "
                         + "System Settings → Apple Account → iCloud → iCloud Drive if you want them wiped.",
                         "iCloud Desktop & Documents menyala, jadi Amnesia tidak membersihkan Desktop dan Documents. "
                         + "Membersihkannya berarti ikut menghapus file di iCloud dan di perangkat Apple kamu yang lain. "
                         + "Matikan di System Settings → Apple Account → iCloud → iCloud Drive kalau ingin ikut dibersihkan."))
        }
        let links = items.filter { $0.why == "symlink" }.map(\.folder)
        if !links.isEmpty {
            out.append(T("These folders are shortcuts (symlinks) to another place, so their contents are not wiped: "
                         + links.joined(separator: ", ") + ".",
                         "Folder ini berupa jalan pintas (symlink) ke tempat lain, jadi isinya tidak dibersihkan: "
                         + links.joined(separator: ", ") + "."))
        }
        return out
    }
}

/// Kotak kecil di "Yang Akan Dihapus": folder yang tidak dibersihkan dan kenapa. Kosong = tidak tampil.
struct SkipNotice: View {
    @State private var items: [Skipped.Item] = []

    var body: some View {
        VStack(spacing: 0) {
            if !items.isEmpty {
                Card {
                    ForEach(Skipped.lines(items), id: \.self) { l in
                        Note(text: l, icon: "arrow.uturn.right.circle.fill", color: Th.orange, more: true)
                    }
                }
            }
        }
        .task {
            let r = await Task.detached { Skipped.list() }.value
            items = r
        }
    }
}

/// Isi Trash Amnesia yang gagal dihapus pada pembersihan terakhir (ditulis clean.sh di ~/.amnesia/trash.failed).
func trashFailedCount() -> Int {
    Int(((try? String(contentsOfFile: P.a + "/trash.failed", encoding: .utf8)) ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
}

// MARK: - Popup password

/// Popup dengan 1 kolom password (NSSecureTextField). nil = Batal.
@MainActor
func askPassword(_ title: String, _ text: String, ok: String) -> String? {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = text
    a.addButton(withTitle: ok)
    a.addButton(withTitle: T("Cancel", "Batal"))
    let f = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
    a.accessoryView = f
    a.window.initialFirstResponder = f
    guard runAlert(a) == .alertFirstButtonReturn else { return nil }
    return f.stringValue
}

// MARK: - Kunci Keep (v5.22, baru)
// settings.conf: KEEP_LOCK=1 (nyala), KEEP_LOCK_PW=<salt>:<hash PBKDF2 dari vault.py keephash>,
// KEEP_LOCK_MIN=<menit terbuka setelah password benar> (default 10).
// Pengaman ringan: izin "deny" macOS (ACL), BUKAN enkripsi. Penjelasan lengkap di keeplock.sh.

enum KeepLock {
    static var script: String { P.a + "/keeplock.sh" }
    static var on: Bool { Config.get("KEEP_LOCK") == "1" && !Config.get("KEEP_LOCK_PW").isEmpty }
    static var minutes: Int {
        let m = Int(Config.get("KEEP_LOCK_MIN", "10")) ?? 10
        return [5, 10, 30, 60].contains(m) ? m : 10
    }

    @discardableResult
    static func run(_ args: [String], input: String? = nil, timeout: Double = 120) -> Out {
        sh("/bin/bash", [script] + args, input: input, timeout: timeout)
    }

    /// "locked" | "open" | "unsupported"
    static func status() -> String {
        guard FileManager.default.fileExists(atPath: script) else { return "unsupported" }
        return run(["status"], timeout: 20).out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var locked: Bool { on && status() == "locked" }

    static func lock() { if on { run(["lock"]) } }

    /// true = sudah terbuka
    @discardableResult
    static func unlock() -> Bool { run(["unlock"]).code == 0 }

    /// Password Keep benar? Hasil: pesan error, atau nil kalau benar.
    static func check(_ pw: String) -> String? {
        let r = vaultCall(["keepcheck"], input: pw + "\n")
        return r.ok ? nil : (r.error ?? T("Wrong Keep password.", "Password Keep salah."))
    }

    /// Nyalakan: simpan hash password, lalu kunci. Hasil: pesan error, atau nil kalau berhasil.
    static func turnOn(_ pw: String) -> String? {
        let r = vaultCall(["keephash"], input: pw + "\n")
        guard r.ok, let h = r.hash, h.contains(":") else { return r.error ?? T("Something went wrong.", "Terjadi kesalahan.") }
        Config.set("KEEP_LOCK_PW", h)
        Config.set("KEEP_LOCK", "1")
        let o = run(["lock"])
        if o.code != 0 || o.out.contains("unsupported") {
            Config.set("KEEP_LOCK", "0")
            run(["unlock"])
            return T("macOS did not accept the lock on this folder (for example on a USB drive formatted as ExFAT). "
                     + "The Keep lock stays off.",
                     "macOS tidak menerima kunci di folder ini (misalnya di flashdisk ber-format ExFAT). Kunci Keep tetap mati.")
        }
        trace("keep lock turned on")
        return nil
    }

    static func turnOff() {
        run(["unlock"])
        Config.set("KEEP_LOCK", "0")
        Config.set("KEEP_LOCK_PW", "")
        trace("keep lock turned off")
    }

    /// Keep terkunci → minta password, buka selama KEEP_LOCK_MIN menit. true = boleh lanjut (terbuka / tidak terkunci).
    @MainActor
    static func askUnlock(_ why: String) -> Bool {
        guard locked else { return true }
        while true {
            guard let pw = askPassword(T("Keep is locked", "Keep terkunci"),
                                       why + "\n\n" + T("Type the Keep password. It stays open for \(minutes) minutes, "
                                                        + "or until the screen locks.",
                                                        "Ketik password Keep. Keep terbuka selama \(minutes) menit, "
                                                        + "atau sampai layar terkunci."),
                                       ok: T("Unlock", "Buka")) else { return false }
            if let e = check(pw) {
                info(T("Not unlocked", "Tidak dibuka"), e, error: true)
                continue
            }
            guard unlock() else {
                info(T("Not unlocked", "Tidak dibuka"),
                     T("The password is right, but the lock could not be removed. In Terminal: chmod -RN ",
                       "Password benar, tapi kuncinya gagal dilepas. Di Terminal: chmod -RN ") + KeepDir.shown, error: true)
                return false
            }
            KeepRelock.shared.schedule()
            return true
        }
    }
}

/// Mengunci Keep lagi setelah KEEP_LOCK_MIN menit, saat layar terkunci, dan saat Amnesia ditutup.
@MainActor
final class KeepRelock {
    static let shared = KeepRelock()
    private var timer: Timer?
    private var watching = false

    func start() {
        guard !watching else { return }
        watching = true
        _ = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"),
                                                                object: nil, queue: .main) { _ in
            Task { @MainActor in KeepRelock.shared.relockNow() }
        }
        // Keep yang dibiarkan terbuka (app ditutup paksa, Mac crash): kunci lagi saat app jalan
        DispatchQueue.global().async { KeepLock.lock() }
    }

    func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Double(KeepLock.minutes) * 60, repeats: false) { _ in
            Task { @MainActor in KeepRelock.shared.relockNow() }
        }
    }

    func relockNow() {
        timer?.invalidate()
        timer = nil
        guard KeepLock.on else { return }
        DispatchQueue.global().async { KeepLock.lock() }
    }
}

// MARK: - Brankas (v5.22, eksperimen): disk APFS terenkripsi (AES-256) di Keep/Brankas.sparsebundle

enum Brankas {
    enum State: Equatable { case missing, closed, open(String) }

    static var path: String { KeepDir.path + "/Brankas.sparsebundle" }

    static func status() -> State {
        let o = KeepLock.run(["box-status"], timeout: 20).out.trimmingCharacters(in: .whitespacesAndNewlines)
        if o.hasPrefix("open ") { return .open(String(o.dropFirst(5))) }
        return o == "closed" ? .closed : .missing
    }

    private static func msg(_ err: String) -> String {
        let e = stripFail(err.split(separator: "\n").last.map(String.init) ?? "")
        if e.contains("[wrongpw]") { return T("Wrong Brankas password.", "Password Brankas salah.") }
        if e.contains("[locked]") { return T("Unlock Keep first.", "Buka Kunci Keep dulu.") }
        return e.isEmpty ? T("Something went wrong.", "Terjadi kesalahan.") : e
    }

    /// Password lewat stdin tanpa enter di akhir (hdiutil -stdinpass). Hasil: pesan error, atau nil.
    static func create(gb: Int, pw: String) -> String? {
        let r = KeepLock.run(["box-create", String(gb)], input: pw, timeout: 300)
        return r.code == 0 ? nil : msg(r.err)
    }

    static func attach(_ pw: String) -> (mount: String?, error: String?) {
        let r = KeepLock.run(["box-attach"], input: pw, timeout: 120)
        guard r.code == 0 else { return (nil, msg(r.err)) }
        let m = r.out.split(separator: "\n").last { $0.hasPrefix("MOUNT ") }.map { String($0.dropFirst(6)) } ?? ""
        return (m.isEmpty ? nil : m, nil)
    }

    @discardableResult
    static func detach() -> Bool { KeepLock.run(["box-detach"], timeout: 120).code == 0 }
}

// MARK: - Kartu di Pengaturan

struct KeepLockCard: View {
    @EnvironmentObject var m: Model
    @State private var on = KeepLock.on
    @State private var st = ""
    @State private var pw = ""
    @State private var pw2 = ""
    @State private var setting = false
    @State private var mins = KeepLock.minutes

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(icon: st == "locked" ? "lock.fill" : "lock.open.fill",
                          colors: on ? Pal.keep : Pal.gray, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(T("Keep lock", "Kunci Keep")).font(.system(size: 14, weight: .semibold))
                        NewBadge(text: T("NEW", "BARU"))
                    }
                    MoreText(T("Finder and other apps can't open or change what's in your Keep folder until you type the "
                               + "Keep password here. It locks again after a few minutes, when the screen locks, and at logout.\n"
                               + "Honest note: this is light protection with macOS permissions, not encryption. Anyone "
                               + "logged in as you can remove it in Terminal with chmod -RN \(KeepDir.shown), and it does "
                               + "nothing against someone who takes the disk. For that, use FileVault or the Brankas below.",
                               "Finder dan app lain tidak bisa membuka atau mengubah isi folder Keep sampai kamu mengetik "
                               + "password Keep di sini. Terkunci lagi setelah beberapa menit, saat layar terkunci, dan saat logout.\n"
                               + "Jujur saja: ini pengaman ringan memakai izin macOS, bukan enkripsi. Siapa pun yang login "
                               + "sebagai kamu bisa melepasnya di Terminal dengan chmod -RN \(KeepDir.shown), dan tidak "
                               + "melindungi dari orang yang mengambil disknya. Untuk itu pakai FileVault atau Brankas di bawah."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(get: { on }, set: { v in if v { setting = true } else { turnOff() } }))
                    .toggleStyle(.switch).labelsHidden()
                    .disabled(st == "unsupported" || m.busy != nil)
            }
            if st == "unsupported" {
                Note(text: T("Not available for this Keep folder.", "Tidak tersedia untuk folder Keep ini."), color: Th.orange)
            }
            if setting {
                Field(label: T("Keep password (at least 8 characters)", "Password Keep (minimal 8 karakter)"), text: $pw)
                PasswordMeter(pw: pw)
                Field(label: T("Type it again", "Ketik sekali lagi"), text: $pw2)
                MatchNote(a: pw, b: pw2)
                Note(text: T("Use a different password from your Mac login and your vault. If you forget it, turn the lock "
                             + "off in Terminal with chmod -RN \(KeepDir.shown). Your files are not lost.",
                             "Pakai password yang berbeda dari login Mac dan vault. Kalau lupa, lepas kuncinya di Terminal "
                             + "dengan chmod -RN \(KeepDir.shown). File kamu tidak hilang."))
                HStack {
                    Button(T("Cancel", "Batal")) { setting = false; pw = ""; pw2 = "" }
                        .buttonStyle(Pill(colors: Pal.gray))
                    Button(T("Lock Keep", "Kunci Keep")) { turnOn() }
                        .buttonStyle(Pill(colors: Pal.keep))
                        .disabled(pw.count < 8 || pw != pw2)
                }
            }
            if on {
                HStack {
                    Text(st == "locked" ? T("Locked now.", "Sedang terkunci.") : T("Open now.", "Sedang terbuka."))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(st == "locked" ? Th.green : Th.orange)
                    Spacer()
                    Picker(T("Stays open", "Terbuka selama"), selection: $mins) {
                        ForEach([5, 10, 30, 60], id: \.self) { n in Text(T("\(n) min", "\(n) menit")).tag(n) }
                    }
                    .frame(width: 200)
                    .onChange(of: mins) { _, n in Config.set("KEEP_LOCK_MIN", String(n)) }
                }
                HStack {
                    if st == "locked" {
                        Button(T("Unlock for \(mins) Minutes", "Buka \(mins) Menit")) {
                            _ = KeepLock.askUnlock(T("Unlock the Keep folder.", "Buka folder Keep."))
                            reload()
                        }
                        .buttonStyle(Pill(colors: Pal.keep))
                    } else {
                        Button(T("Lock Now", "Kunci Sekarang")) {
                            KeepRelock.shared.relockNow()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { reload() }
                        }
                        .buttonStyle(Pill(colors: Pal.keep))
                    }
                }
            }
        }
        .task { reload() }
    }

    private func reload() {
        on = KeepLock.on
        m.quiet({ KeepLock.status() }) { s in st = s }
    }

    private func turnOn() {
        let p = pw
        m.background(T("Locking Keep…", "Mengunci Keep…"), { KeepLock.turnOn(p) }) { e in
            pw = ""; pw2 = ""
            if let e = e { info(T("Keep lock", "Kunci Keep"), e, error: true) } else { setting = false }
            reload()
        }
    }

    private func turnOff() {
        guard KeepLock.on else { return }
        guard let p = askPassword(T("Turn off the Keep lock?", "Matikan Kunci Keep?"),
                                  T("Type the Keep password. Your files stay where they are.",
                                    "Ketik password Keep. File kamu tetap di tempatnya."),
                                  ok: T("Turn Off", "Matikan")) else { return }
        m.background(T("Unlocking Keep…", "Membuka Keep…"), { () -> String? in
            if let e = KeepLock.check(p) { return e }
            KeepLock.turnOff()
            return nil
        }) { e in
            if let e = e { info(T("Keep lock", "Kunci Keep"), e, error: true) }
            reload()
        }
    }
}

struct BrankasCard: View {
    @EnvironmentObject var m: Model
    @State private var st: Brankas.State?
    @State private var creating = false
    @State private var gb = 10
    @State private var pw = ""
    @State private var pw2 = ""

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(icon: "lock.square.stack.fill", colors: Pal.vault, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Brankas").font(.system(size: 14, weight: .semibold))
                        NewBadge(text: T("EXPERIMENTAL", "EKSPERIMEN"), color: Th.orange)
                    }
                    MoreText(T("An encrypted disk (AES-256) inside your Keep folder. Files you put in it can't be read "
                               + "without the Brankas password, even by someone who copies the folder or takes the disk. "
                               + "Amnesia closes it before every cleanup.\n"
                               + "Forget the password and the files in it are gone for good. Nobody can open it for you.",
                               "Disk terenkripsi (AES-256) di dalam folder Keep. File di dalamnya tidak bisa dibaca tanpa "
                               + "password Brankas, juga oleh orang yang menyalin foldernya atau mengambil disknya. "
                               + "Amnesia menutupnya sebelum setiap pembersihan.\n"
                               + "Lupa password = file di dalamnya hilang untuk selamanya. Tidak ada yang bisa membukakannya."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            switch st {
            case .missing?:
                if creating {
                    Picker(T("Size (it only takes the space it uses)", "Ukuran (hanya memakai ruang yang terisi)"),
                           selection: $gb) {
                        ForEach([5, 10, 50, 100], id: \.self) { n in Text("\(n) GB").tag(n) }
                    }
                    Field(label: T("Brankas password (at least 8 characters)", "Password Brankas (minimal 8 karakter)"), text: $pw)
                    PasswordMeter(pw: pw)
                    Field(label: T("Type it again", "Ketik sekali lagi"), text: $pw2)
                    MatchNote(a: pw, b: pw2)
                    HStack {
                        Button(T("Cancel", "Batal")) { creating = false; pw = ""; pw2 = "" }
                            .buttonStyle(Pill(colors: Pal.gray))
                        Button(T("Create Brankas", "Buat Brankas")) { create() }
                            .buttonStyle(Pill(colors: Pal.vault))
                            .disabled(pw.count < 8 || pw != pw2)
                    }
                } else {
                    Button(T("Create a Brankas…", "Buat Brankas…")) { creating = true }
                        .buttonStyle(Pill(colors: Pal.vault))
                        .disabled(m.busy != nil)
                }
            case .closed?:
                Note(text: T("Closed.", "Tertutup."), icon: "lock.fill", color: Th.green)
                Button(T("Open Brankas", "Buka Brankas")) { open() }
                    .buttonStyle(Pill(colors: Pal.vault))
                    .disabled(m.busy != nil)
            case .open(let dir)?:
                Note(text: T("Open at \(dir). Close it when you're done.", "Terbuka di \(dir). Tutup kalau sudah selesai."),
                     icon: "lock.open.fill", color: Th.orange)
                HStack {
                    Button(T("Show in Finder", "Tampilkan di Finder")) { NSWorkspace.shared.open(URL(fileURLWithPath: dir)) }
                        .buttonStyle(Pill(colors: Pal.gray))
                    Button(T("Close Brankas", "Tutup Brankas")) { close() }
                        .buttonStyle(Pill(colors: Pal.vault))
                }
            case nil:
                Text(T("Checking…", "Mengecek…")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .task { reload() }
    }

    private func reload() { m.quiet({ Brankas.status() }) { s in st = s } }

    private func create() {
        guard KeepLock.askUnlock(T("The Brankas is made inside your Keep folder.", "Brankas dibuat di dalam folder Keep.")) else { return }
        let p = pw, size = gb
        m.background(T("Creating the Brankas…", "Membuat Brankas…"), { Brankas.create(gb: size, pw: p) }) { e in
            pw = ""; pw2 = ""
            if let e = e { info("Brankas", e, error: true) } else { creating = false; trace("brankas created") }
            reload()
        }
    }

    private func open() {
        guard let p = askPassword(T("Open Brankas", "Buka Brankas"), T("Type the Brankas password.", "Ketik password Brankas."),
                                  ok: T("Open", "Buka")) else { return }
        m.background(T("Opening the Brankas…", "Membuka Brankas…"), { Brankas.attach(p) }) { r in
            if let e = r.error { info("Brankas", e, error: true) }
            else if let d = r.mount { NSWorkspace.shared.open(URL(fileURLWithPath: d)) }
            reload()
        }
    }

    private func close() {
        m.background(T("Closing the Brankas…", "Menutup Brankas…"), { Brankas.detach() }) { ok in
            if !ok {
                info("Brankas", T("It could not be closed. Close the files that are open from it, then try again.",
                                  "Gagal ditutup. Tutup dulu file yang sedang dibuka dari Brankas, lalu coba lagi."), error: true)
            }
            reload()
        }
    }
}

/// Label kecil "BARU" / "EKSPERIMEN" di samping judul kartu.
struct NewBadge: View {
    let text: String
    var color: Color = Th.cyan
    var body: some View {
        Text(text).font(.system(size: 9, weight: .heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
            .overlay(Capsule().strokeBorder(color.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Meter kekuatan password (perkiraan kasar, bukan jaminan)

/// 0 = kosong, 1 = lemah, 2 = lumayan, 3 = kuat, 4 = sangat kuat
func passwordStrength(_ s: String) -> Int {
    guard !s.isEmpty else { return 0 }
    let common = ["password", "123456", "12345678", "qwerty", "11111111", "iloveyou", "admin", "letmein",
                  "rahasia", "bismillah", "sayang", "indonesia", "amnesia"]
    let low = s.lowercased()
    if Set(s).count <= 3 || common.contains(where: { low.contains($0) && s.count < $0.count + 4 }) { return 1 }
    var kinds = 0
    for set in [CharacterSet.lowercaseLetters, .uppercaseLetters, .decimalDigits] where s.rangeOfCharacter(from: set) != nil {
        kinds += 1
    }
    if s.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil { kinds += 1 }
    let n = s.count
    var score = n >= 8 ? 1 : 0
    if n >= 12 { score += 1 }
    if n >= 16 { score += 1 }
    if kinds >= 3 { score += 1 }
    // kalimat panjang (beberapa kata) juga kuat walau tanpa angka/simbol
    if n >= 20 && s.split(separator: " ").count >= 4 { score = 4 }
    return min(max(score, 1), 4)
}

struct PasswordMeter: View {
    let pw: String

    var body: some View {
        let s = passwordStrength(pw)
        let color = s <= 1 ? Th.red : (s == 2 ? Th.orange : Th.green)
        if !pw.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(1...4, id: \.self) { i in
                        Capsule().fill(i <= s ? color : Th.line2).frame(height: 4)
                    }
                }
                Text(label(s)).font(.system(size: 11, weight: .medium)).foregroundStyle(color)
            }
        }
    }

    private func label(_ s: Int) -> String {
        switch s {
        case 1: return T("Weak. Easy to guess. Make it longer.", "Lemah. Mudah ditebak. Buat lebih panjang.")
        case 2: return T("OK. Longer is better: a short sentence works well.",
                         "Lumayan. Makin panjang makin baik: kalimat pendek cocok.")
        case 3: return T("Strong.", "Kuat.")
        default: return T("Very strong. Write it down somewhere safe.", "Sangat kuat. Catat di tempat yang aman.")
        }
    }
}

/// v5.22: penjelasan jujur cara vault (dan folder Keep) dihapus oleh kata panik / Hapus Vault / salah password.
func doomsdayHonest(keep: Bool) -> String {
    T("How it deletes: the files are removed the normal way, not overwritten (on an SSD that wouldn't help anyway). "
      + "The vault is encrypted, so leftovers on the disk can't be read without the password."
      + (keep ? " Files emptied from the Keep folder are NOT encrypted: without FileVault, recovery tools may still find them." : "")
      + " Copies in backups, Time Machine and the cloud are not touched.",
      "Cara menghapusnya: file dihapus dengan cara biasa, tidak ditimpa (di SSD itu juga tidak membantu). "
      + "Vault terenkripsi, jadi sisa di disk tidak bisa dibaca tanpa password."
      + (keep ? " File yang dikosongkan dari folder Keep TIDAK terenkripsi: tanpa FileVault, alat pemulihan mungkin masih menemukannya." : "")
      + " Salinan di backup, Time Machine, dan cloud tidak disentuh.")
}

// MARK: - Saran app untuk Profile Vault (v5.22)

/// App terpasang yang kelihatannya menyimpan login (punya item Keychain "<Nama> Safe Storage", seperti app
/// berbasis Chromium/Electron), tapi belum ada di vault. Tidak ada yang dicentang otomatis: kamu yang memilih.
struct VaultSuggestion: Identifiable, Hashable {
    let name: String
    let path: String        // lokasi .app (untuk ikon)
    let quit: String        // nama proses untuk ditutup sebelum snapshot
    let paths: [String]     // data app, relatif dari home
    var id: String { name }
}

/// Ada item Keychain "<nama> Safe Storage"? Hanya atribut yang dibaca (tanpa isi), jadi macOS tidak minta izin.
func hasSafeStorage(_ name: String) -> Bool {
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                            kSecAttrService as String: name + " Safe Storage",
                            kSecReturnAttributes as String: true,
                            kSecMatchLimit as String: kSecMatchLimitOne]
    var out: CFTypeRef?
    return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess
}

func scanVaultSuggestions(known: Set<String>) -> [VaultSuggestion] {
    let fm = FileManager.default
    let groups = (try? fm.contentsOfDirectory(atPath: P.home + "/Library/Group Containers")) ?? []
    let kept = Keep.entries()
    var out: [VaultSuggestion] = []
    for dir in ["/Applications", P.home + "/Applications"] {
        for f in ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).sorted() where f.hasSuffix(".app") {
            let path = dir + "/" + f
            let name = String(f.dropLast(4))
            guard !known.contains(name), !vaultApps.contains(name), !out.contains(where: { $0.name == name }),
                  let b = Bundle(path: path), let bid = b.bundleIdentifier, !bid.hasPrefix("com.apple."),
                  bid != Bundle.main.bundleIdentifier else { continue }
            let info = b.infoDictionary ?? [:]
            let cfName = info["CFBundleName"] as? String ?? ""
            guard hasSafeStorage(name) || (!cfName.isEmpty && cfName != name && hasSafeStorage(cfName)) else { continue }
            let names = [name, cfName, info["CFBundleDisplayName"] as? String ?? ""]
            // Preferences tidak ikut: itu pengaturan, bukan login (dan Keep List bisa menyimpannya)
            let p = appDataPaths(bid: bid, names: names, groups: groups)
                .filter { !$0.hasPrefix("Library/Preferences/") && !keepMatches($0, kept) }
            guard !p.isEmpty else { continue }
            let exe = info["CFBundleExecutable"] as? String ?? name
            out.append(VaultSuggestion(name: name, path: path, quit: exe, paths: p))
        }
    }
    return out
}

// MARK: - Cek kesehatan (v5.22, baru)

struct HealthRow: Identifiable {
    enum Level { case ok, warn, bad, info }
    enum Fix { case nothing, turnOn, keepVM([String]), fileVault, backup, settings, fullDisk, update }
    let id = UUID()
    let level: Level
    let title: String
    let detail: String
    var fix: Fix = .nothing
}

enum Health {
    /// Semua pengecekan (di background: launchctl, fdesetup, du).
    static func run(report: [DryGroup]?) -> [HealthRow] {
        let fm = FileManager.default
        var rows: [HealthRow] = []

        // 1. agent
        let plistOK = fm.fileExists(atPath: P.plist)
        let loaded = plistOK && sh(P.launchctl, ["print", "\(P.domain)/\(P.label)"]).code == 0
        if loaded {
            rows.append(HealthRow(level: .ok, title: T("Amnesia is on", "Amnesia aktif"),
                                  detail: T("The login agent is loaded, so logout, restart and shutdown are wiped.",
                                            "Agent login sudah jalan, jadi logout, restart dan shutdown dibersihkan.")))
        } else {
            rows.append(HealthRow(level: .warn, title: T("Amnesia is off", "Amnesia mati"),
                                  detail: T("Nothing is wiped at logout.", "Tidak ada yang dibersihkan saat logout."), fix: .turnOn))
        }
        if plistOK, let d = NSDictionary(contentsOfFile: P.plist), let prog = (d["ProgramArguments"] as? [String])?.first {
            let app = prog.components(separatedBy: "/Contents/").first ?? prog
            if fm.isExecutableFile(atPath: prog) {
                rows.append(HealthRow(level: .ok, title: T("App location", "Lokasi app"),
                                      detail: T("The agent starts the app at \(app).", "Agent menjalankan app di \(app).")))
            } else {
                rows.append(HealthRow(level: .bad, title: T("App location", "Lokasi app"),
                                      detail: T("The agent points to an app that isn't there anymore (moved or deleted), so "
                                                + "nothing is wiped at logout. Open Amnesia from Applications and turn it on again.",
                                                "Agent menunjuk ke app yang sudah tidak ada (dipindah atau dihapus), jadi tidak "
                                                + "ada yang dibersihkan saat logout. Buka Amnesia dari Applications lalu aktifkan lagi."),
                                      fix: .turnOn))
            }
        }
        if !Engine.hasFullDisk {
            rows.append(HealthRow(level: .warn, title: T("Full Disk Access", "Akses Disk Penuh"),
                                  detail: T("Not given yet. Some folders can't be read or wiped without it.",
                                            "Belum diberikan. Beberapa folder tidak bisa dibaca atau dibersihkan tanpa izin ini."),
                                  fix: .fullDisk))
        }

        // 2. folder yang dilewati
        let skipped = Skipped.list()
        if skipped.contains(where: { $0.why == "icloud" }) {
            rows.append(HealthRow(level: .warn, title: T("iCloud Desktop & Documents", "iCloud Desktop & Documents"),
                                  detail: Skipped.lines(skipped.filter { $0.why == "icloud" }).joined()))
        } else {
            rows.append(HealthRow(level: .ok, title: T("iCloud Desktop & Documents", "iCloud Desktop & Documents"),
                                  detail: T("Off (or not detected). Desktop and Documents are wiped as usual.",
                                            "Mati (atau tidak terdeteksi). Desktop dan Documents dibersihkan seperti biasa.")))
        }
        if skipped.contains(where: { $0.why == "symlink" }) {
            rows.append(HealthRow(level: .info, title: T("Folders that are shortcuts", "Folder berupa jalan pintas"),
                                  detail: Skipped.lines(skipped.filter { $0.why == "symlink" }).joined()))
        }
        let failed = trashFailedCount()
        if failed > 0 {
            rows.append(HealthRow(level: .warn, title: T("Leftovers from the last cleanup", "Sisa pembersihan terakhir"),
                                  detail: T("\(failed) items could not be deleted. Amnesia tries again at the next cleanup. "
                                            + "If it keeps happening, check the files are not locked (Get Info → Locked).",
                                            "\(failed) item gagal dihapus. Amnesia mencoba lagi pada pembersihan berikutnya. "
                                            + "Kalau terus terjadi, cek apakah filenya dikunci (Get Info → Locked).")))
        }

        // 3. data VM yang tidak disimpan
        let kept = Keep.entries()
        var vmLost: [String] = []
        var vmNames: [String] = []
        for v in vmApps {
            let lost = vmDataPaths(v).filter { !keepMatches($0, kept) }
            if !lost.isEmpty { vmLost += lost; vmNames.append(v.name) }
        }
        if !vmLost.isEmpty {
            rows.append(HealthRow(level: .bad, title: T("Virtual machines not kept", "Mesin virtual tidak disimpan"),
                                  detail: T("\(vmNames.joined(separator: ", ")): the VM disks are deleted at the next logout.",
                                            "\(vmNames.joined(separator: ", ")): disk VM-nya terhapus saat logout berikutnya."),
                                  fix: .keepVM(vmLost)))
        }

        // 4. file besar di daftar "yang akan dihapus"
        if let groups = report {
            let items = groups.filter { !$0.system }.flatMap(\.items).filter { !$0.keychain }
            let sizes = itemSizes(items)
            let big = items.filter { (sizes[$0.id] ?? 0) >= 1_048_576 }
                .sorted { (sizes[$0.id] ?? 0) > (sizes[$1.id] ?? 0) }
            if !big.isEmpty {
                let list = big.prefix(5).map { "\($0.shown) (\(bytesText((sizes[$0.id] ?? 0) * 1024)))" }
                rows.append(HealthRow(level: .warn, title: T("Big files get deleted", "File besar ikut dihapus"),
                                      detail: T("At least 1 GB each, deleted at the next logout: ", "Minimal 1 GB per item, dihapus saat "
                                                + "logout berikutnya: ") + list.joined(separator: ", ")
                                          + (big.count > 5 ? T(" and \(big.count - 5) more.", " dan \(big.count - 5) lagi.") : ".")))
            }
        }

        // 5. backup
        let age = fileAge(P.backupOk)
        if age == .infinity {
            rows.append(HealthRow(level: .warn, title: "Backup", detail: T("No backup yet.", "Belum pernah backup."), fix: .backup))
        } else {
            let days = Int(age / 86_400)
            let warnLast = lastBackupStatus().contains(" WARN: ")
            rows.append(HealthRow(level: days > 14 ? .warn : (warnLast ? .info : .ok), title: "Backup",
                                  detail: (days == 0 ? T("Last good backup: today.", "Backup berhasil terakhir: hari ini.")
                                                     : T("Last good backup: \(days) days ago.", "Backup berhasil terakhir: \(days) hari lalu."))
                                      + (warnLast ? T(" The last one finished with warnings (some files skipped).",
                                                      " Yang terakhir selesai dengan peringatan (ada file yang dilewati).") : ""),
                                  fix: days > 14 ? .backup : .nothing))
        }

        // 6. update
        let every = UpdateEvery.days
        rows.append(HealthRow(level: every == 0 ? .warn : .ok, title: T("Update check", "Cek update"),
                              detail: every == 0 ? T("Off. You won't hear about fixes.", "Mati. Kamu tidak tahu kalau ada perbaikan.")
                                                 : UpdateEvery.label(every) + ".",
                              fix: every == 0 ? .update : .nothing))
        if !UpdateSig.ready {
            rows.append(HealthRow(level: .info, title: T("Signed updates", "Update bertanda tangan"),
                                  detail: T("This copy has no update signing key, so updates are not installed from inside the app. "
                                            + "Download them from the release page.",
                                            "Salinan ini belum punya kunci tanda tangan update, jadi update tidak dipasang dari dalam "
                                            + "app. Unduh dari halaman rilis.")))
        }

        // 7. Kunci Keep & FileVault
        if KeepLock.on {
            let s = KeepLock.status()
            rows.append(HealthRow(level: s == "locked" ? .ok : .info, title: T("Keep lock", "Kunci Keep"),
                                  detail: s == "locked" ? T("On and locked.", "Nyala dan terkunci.")
                                                        : T("On, open right now.", "Nyala, sedang terbuka.")))
        } else {
            rows.append(HealthRow(level: .info, title: T("Keep lock", "Kunci Keep"),
                                  detail: T("Off. Optional, see Settings.", "Mati. Tidak wajib, lihat Pengaturan."), fix: .settings))
        }
        switch DiskCrypt.status() {
        case .on: rows.append(HealthRow(level: .ok, title: "FileVault", detail: T("On.", "Aktif.")))
        case .busy: rows.append(HealthRow(level: .info, title: "FileVault", detail: T("Encrypting now.", "Sedang mengenkripsi.")))
        case .off: rows.append(HealthRow(level: .bad, title: "FileVault",
                                         detail: T("Off. Your Keep folder and vault files can be read by someone who takes the disk.",
                                                   "Mati. Folder Keep dan file vault bisa dibaca orang yang mengambil disknya."),
                                         fix: .fileVault))
        case .unknown: rows.append(HealthRow(level: .info, title: "FileVault", detail: T("Couldn't check.", "Tidak bisa dicek.")))
        }
        return rows
    }
}

struct HealthView: View {
    @EnvironmentObject var m: Model
    let back: () -> Void
    @State private var rows: [HealthRow]?

    var body: some View {
        VStack(spacing: 14) {
            PageHeader(title: T("Health check", "Cek kesehatan"), icon: "stethoscope", colors: Pal.keep, back: back)
            RoomyScroll {
                VStack(spacing: 10) {
                    if let rows = rows {
                        let bad = rows.filter { $0.level == .bad || $0.level == .warn }.count
                        Note(text: bad == 0 ? T("Everything looks fine.", "Semuanya terlihat baik.")
                                            : T("\(bad) things need a look.", "\(bad) hal perlu dicek."),
                             icon: bad == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                             color: bad == 0 ? Th.green : Th.orange)
                        ForEach(rows) { r in row(r) }
                        Button { load() } label: { Label(T("Check Again", "Cek Lagi"), systemImage: "arrow.clockwise") }
                            .buttonStyle(Pill(colors: Pal.gray))
                    } else {
                        ProgressView().padding(30)
                        Text(T("Checking…", "Mengecek…")).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .task { load() }
    }

    private func load() {
        rows = nil
        let rep = m.report
        m.quiet({ Health.run(report: rep) }) { r in rows = r }
    }

    private func row(_ r: HealthRow) -> some View {
        let (icon, color): (String, Color) = {
            switch r.level {
            case .ok: return ("checkmark.circle.fill", Th.green)
            case .warn: return ("exclamationmark.triangle.fill", Th.orange)
            case .bad: return ("xmark.octagon.fill", Th.red)
            case .info: return ("info.circle.fill", Th.muted)
            }
        }()
        return Card {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.title).font(.system(size: 13, weight: .semibold))
                    Text(r.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            fixButton(r.fix)
        }
    }

    @ViewBuilder private func fixButton(_ f: HealthRow.Fix) -> some View {
        switch f {
        case .nothing: EmptyView()
        case .turnOn:
            Button(T("Turn On…", "Aktifkan…")) { m.page = .home; m.togglePower() }.buttonStyle(Pill(colors: Pal.on))
                .disabled(m.state != .off)
        case .keepVM(let paths):
            Button(T("Add to the Keep List", "Tambahkan ke Keep List")) {
                Keep.add(paths.filter { !keepMatches($0, Keep.entries()) })
                trace("health: vm data added to the Keep List")
                load()
            }
            .buttonStyle(Pill(colors: Pal.keep))
        case .fileVault:
            Button(T("Open FileVault Settings", "Buka Pengaturan FileVault")) { DiskCrypt.openSettings() }
                .buttonStyle(Pill(colors: Pal.pause))
        case .backup:
            Button(T("Open Backup", "Buka Backup")) { m.page = .backup }.buttonStyle(Pill(colors: Pal.backup))
        case .settings, .update:
            Button(T("Open Settings", "Buka Pengaturan")) { m.page = .settings }.buttonStyle(Pill(colors: Pal.gray))
        case .fullDisk:
            Button(T("Open Privacy Settings", "Buka Pengaturan Privasi")) { Engine.openFullDiskSettings() }
                .buttonStyle(Pill(colors: Pal.pause))
        }
    }
}

// MARK: - Batasan (v5.22): yang TIDAK bisa dihapus Amnesia, ditulis jujur

struct LimitsView: View {
    let back: () -> Void

    struct Item {
        let icon: String
        let title: String
        let text: String
        init(_ icon: String, _ title: String, _ text: String) { self.icon = icon; self.title = title; self.text = text }
    }

    private var items: [Item] {
        [
            Item("clock.arrow.circlepath", T("Time Machine and APFS snapshots", "Time Machine dan snapshot APFS"),
             T("Copies made by Time Machine (and the local snapshots macOS keeps for it) still have your old files. "
               + "Amnesia doesn't touch them. Exclude folders in Time Machine settings, or turn it off.",
               "Salinan dari Time Machine (dan snapshot lokal yang disimpan macOS untuknya) masih berisi file lama kamu. "
               + "Amnesia tidak menyentuhnya. Kecualikan folder di pengaturan Time Machine, atau matikan.")),
            Item("magnifyingglass", "Spotlight",
             T("The Spotlight index can still hold names and bits of text from deleted files until macOS updates it.",
               "Indeks Spotlight masih bisa menyimpan nama dan potongan teks dari file yang dihapus sampai macOS memperbaruinya.")),
            Item("icloud.fill", T("iCloud and other clouds", "iCloud dan cloud lain"),
             T("Anything synced to iCloud, Google Drive, Dropbox and so on stays in the cloud and on your other devices. "
               + "Amnesia only cleans this Mac.",
               "Semua yang tersinkron ke iCloud, Google Drive, Dropbox dan lainnya tetap ada di cloud dan di perangkat kamu "
               + "yang lain. Amnesia hanya membersihkan Mac ini.")),
            Item("memorychip", T("Swap and sleep image", "Swap dan sleep image"),
             T("macOS writes memory to disk (swap files, and sleepimage when the Mac sleeps). These are system files "
               + "Amnesia can't wipe. FileVault keeps them encrypted.",
               "macOS menulis isi memori ke disk (file swap, dan sleepimage saat Mac tidur). Ini file sistem yang tidak "
               + "bisa dihapus Amnesia. FileVault membuatnya tetap terenkripsi.")),
            Item("list.bullet.rectangle", T("System logs", "Log sistem"),
             T("The macOS unified log keeps records of what ran (app names, sometimes more) for days. "
               + "Amnesia doesn't delete system logs.",
               "Log sistem macOS mencatat apa yang dijalankan (nama app, kadang lebih) selama beberapa hari. "
               + "Amnesia tidak menghapus log sistem.")),
            Item("person.2.fill", T("Other accounts", "Akun lain"),
             T("Only your own account is cleaned. Other users on this Mac, and shared folders like /Users/Shared, are not.",
               "Hanya akun kamu yang dibersihkan. Akun lain di Mac ini dan folder bersama seperti /Users/Shared tidak.")),
            Item("lock.shield.fill", "FileVault",
             T("Deleted files can sometimes be recovered from the disk. With FileVault on, what's left on the disk is "
               + "encrypted and can't be read without your password.",
               "File yang dihapus kadang masih bisa dipulihkan dari disk. Dengan FileVault menyala, sisa di disk "
               + "terenkripsi dan tidak bisa dibaca tanpa password kamu.")),
            Item("tray.full.fill", T("The Keep folder is not encrypted", "Folder Keep tidak dienkripsi"),
             T("Files in Keep are normal files. The Keep lock only blocks Finder and apps. Use FileVault, or the Brankas "
               + "(experimental) for files that must stay secret.",
               "File di Keep adalah file biasa. Kunci Keep hanya menghalangi Finder dan app. Pakai FileVault, atau Brankas "
               + "(eksperimen) untuk file yang harus tetap rahasia.")),
            Item("network", T("Things outside this Mac", "Hal di luar Mac ini"),
             T("Websites, your internet provider, and the apps' own servers still have their records of you.",
               "Website, penyedia internet, dan server milik app tetap punya catatan mereka tentang kamu.")),
        ]
    }

    var body: some View {
        VStack(spacing: 14) {
            PageHeader(title: T("Limitations", "Batasan"), icon: "exclamationmark.shield.fill", colors: Pal.pause, back: back)
            RoomyScroll {
                VStack(spacing: 10) {
                    Note(text: T("Amnesia wipes your files and app data at logout. Some traces live in places it can't reach. "
                                 + "Here they are, so you know what to expect.",
                                 "Amnesia menghapus file dan data app kamu saat logout. Ada jejak di tempat yang tidak bisa "
                                 + "dijangkaunya. Ini daftarnya, supaya kamu tahu apa yang bisa diharapkan."))
                    ForEach(items, id: \.title) { it in
                        Card {
                            HStack(alignment: .top, spacing: 12) {
                                IconBadge(icon: it.icon, colors: Pal.pause, size: 30)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(it.title).font(.system(size: 13, weight: .semibold))
                                    Text(it.text).font(.system(size: 11)).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }
}
