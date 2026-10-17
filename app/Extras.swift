// Amnesia v5.19: fitur baru di file terpisah supaya Amnesia.swift tidak makin panjang.
// - Lanjutan (Advanced): logout otomatis, hapus app baru, kata panik, pindah Mac (v5.20: grup di Pengaturan)
// - Cek enkripsi disk (FileVault)
// - Update dari dalam app (cek, unduh otomatis, pasang dengan 1 tombol)
// v5.22: update hanya dipasang kalau SHA256SUMS.txt ditandatangani kunci developer (ECDSA P-256, CryptoKit)
import SwiftUI
import AppKit
import CoreGraphics
import CryptoKit

// MARK: - Update

enum UpdateFiles {
    /// Ada file ini = Amnesia dimatikan sebentar untuk update; versi baru menyalakannya lagi saat dibuka.
    static let turnOnFlag = P.a + "/.turn_on_after_update"
    static let dir = P.home + "/Library/Caches/Amnesia/update"
    static let repo = "navi-crwn/amnesia"
    static let api = "https://api.github.com/repos/\(repo)/releases/latest"
    static let page = "https://github.com/\(repo)/releases/latest"

    /// Dipasang lewat Homebrew: update lewat brew saja, supaya brew tidak bingung versinya.
    static var brew: Bool {
        ["/opt/homebrew/Caskroom/amnesia", "/usr/local/Caskroom/amnesia"].contains { FileManager.default.fileExists(atPath: $0) }
    }
}

/// v5.20: seberapa sering cek update otomatis. Dulu sehari sekali (terlalu sering).
/// settings.conf: UPDATE_CHECK=0 → Mati; UPDATE_DAYS=7|14|30 (default 7). Nilai lama/aneh dianggap 7 (seminggu).
enum UpdateEvery {
    static let choices = [0, 7, 14, 30]

    /// 0 = mati, selain itu jumlah hari
    static var days: Int {
        guard Setting.updateCheck.isOn else { return 0 }
        let d = Int(Config.get("UPDATE_DAYS", "7")) ?? 7
        return choices.contains(d) && d > 0 ? d : 7
    }

    static func set(_ d: Int) {
        Setting.updateCheck.set(d > 0)
        if d > 0 { Config.set("UPDATE_DAYS", String(d)) }
    }

    /// Sekali saja: pengaturan "sehari sekali" dari versi lama jadi "seminggu sekali".
    static func migrate() {
        let d = Config.get("UPDATE_DAYS")
        if d.isEmpty || !choices.contains(Int(d) ?? -1) || d == "0" { Config.set("UPDATE_DAYS", "7") }
    }

    static func label(_ d: Int) -> String {
        switch d {
        case 0: return T("Off", "Mati")
        case 7: return T("Every week", "Seminggu sekali")
        case 14: return T("Every 2 weeks", "2 minggu sekali")
        default: return T("Every month", "Sebulan sekali")
        }
    }
}

/// "5.19.0" lebih baru dari "5.18.2"? Angka dibandingkan satu per satu.
func isNewer(_ a: String, than b: String) -> Bool {
    let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
    for i in 0..<max(x.count, y.count) {
        let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
        if p != q { return p > q }
    }
    return false
}

struct ReleaseInfo: Sendable {
    let version: String
    let dmg: String      // URL unduhan
    let sums: String?    // SHA256SUMS.txt (tanpa ini update dari app ditolak)
    let sig: String?     // v5.22: SHA256SUMS.txt.sig (tanpa ini update dari app juga ditolak)
}

/// v5.22: tanda tangan update. SHA256SUMS.txt ditandatangani di Mac developer (openssl dgst -sha256 -sign, kunci
/// privat tidak pernah di GitHub). App hanya memasang update kalau tanda tangannya cocok dengan kunci publik di bawah.
/// Hash saja (dulu) hanya melindungi dari unduhan rusak: siapa pun yang bisa mengunggah ke rilis bisa mengganti
/// .dmg dan SHA256SUMS.txt sekaligus. Tanda tangan tidak bisa dibuat tanpa kunci privat.
enum UpdateSig {
    /// Kunci publik ECDSA P-256 (SubjectPublicKeyInfo DER, base64). Diganti oleh script update developer.
    static let publicKey = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE52jL2iMKP6nxCJ02PXei1luJqVjR7BngXg5FeyHIdlum7BV0b4wXwU5A2b5LvsuexEEQ2WLYuorAu0tqBCghTQ=="

    static var key: P256.Signing.PublicKey? {
        guard let der = Data(base64Encoded: publicKey) else { return nil }     // teks pengganti = bukan base64
        return try? P256.Signing.PublicKey(derRepresentation: der)
    }

    /// Versi ini punya kunci publik yang benar (bukan teks pengganti)?
    static var ready: Bool { key != nil }

    /// sig = tanda tangan DER atas byte persis SHA256SUMS.txt
    static func valid(_ sums: Data, _ sig: Data) -> Bool {
        guard let k = key, let s = try? P256.Signing.ECDSASignature(derRepresentation: sig) else { return false }
        return k.isValidSignature(s, for: sums)
    }
}

/// Tanya GitHub versi terbaru. Hanya 1 permintaan biasa ke api.github.com, tidak ada data pribadi yang dikirim.
func fetchLatest() -> ReleaseInfo? {
    let r = sh("/usr/bin/curl", ["-fsSL", "-m", "20", "-H", "Accept: application/vnd.github+json", UpdateFiles.api], timeout: 30)
    guard r.code == 0, let data = r.out.data(using: .utf8),
          let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tag = j["tag_name"] as? String else { return nil }
    let v = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    let assets = (j["assets"] as? [[String: Any]]) ?? []
    func url(_ name: String) -> String? {
        assets.first { ($0["name"] as? String) == name }?["browser_download_url"] as? String
    }
    guard let dmg = url("Amnesia-v\(v).dmg") else { return nil }
    return ReleaseInfo(version: v, dmg: dmg, sums: url("SHA256SUMS.txt"), sig: url("SHA256SUMS.txt.sig"))
}

/// Unduh .dmg + SHA256SUMS.txt (+ .sig), cek tanda tangan, lalu cocokkan sidiknya. Hasil: path .dmg, atau pesan gagal.
/// page = true: kirim kamu ke halaman rilis (tanda tangan tidak ada / tidak cocok), bukan sekadar "coba lagi".
func downloadRelease(_ rel: ReleaseInfo) -> (path: String?, error: String?, page: Bool) {
    guard let sumsURL = rel.sums else {
        return (nil, T("This release has no SHA256SUMS.txt, so Amnesia can't check the download. Download it from GitHub yourself.",
                       "Rilis ini tidak punya SHA256SUMS.txt, jadi Amnesia tidak bisa mengecek unduhannya. Unduh sendiri dari GitHub."), true)
    }
    guard let sigURL = rel.sig else {
        return (nil, T("This release isn't signed (no SHA256SUMS.txt.sig), so Amnesia won't install it by itself. "
                       + "Open the release page, check it, and install it by hand if you trust it.",
                       "Rilis ini tidak ditandatangani (tidak ada SHA256SUMS.txt.sig), jadi Amnesia tidak mau memasangnya sendiri. "
                       + "Buka halaman rilis, cek dulu, lalu pasang sendiri kalau kamu percaya."), true)
    }
    let fm = FileManager.default
    try? fm.createDirectory(atPath: UpdateFiles.dir, withIntermediateDirectories: true)
    let name = "Amnesia-v\(rel.version).dmg"
    let file = UpdateFiles.dir + "/" + name, sums = UpdateFiles.dir + "/SHA256SUMS.txt", sig = sums + ".sig"
    // unduhan lama dari versi lain dibuang
    for f in (try? fm.contentsOfDirectory(atPath: UpdateFiles.dir)) ?? [] where f != name {
        try? fm.removeItem(atPath: UpdateFiles.dir + "/" + f)
    }
    guard sh("/usr/bin/curl", ["-fsSL", "-m", "60", "-o", sums, sumsURL], timeout: 70).code == 0,
          let sumsData = try? Data(contentsOf: URL(fileURLWithPath: sums)),
          let text = String(data: sumsData, encoding: .utf8) else {
        return (nil, T("Could not download SHA256SUMS.txt.", "Gagal mengunduh SHA256SUMS.txt."), false)
    }
    guard sh("/usr/bin/curl", ["-fsSL", "-m", "60", "-o", sig, sigURL], timeout: 70).code == 0,
          let sigData = try? Data(contentsOf: URL(fileURLWithPath: sig)) else {
        return (nil, T("Could not download SHA256SUMS.txt.sig.", "Gagal mengunduh SHA256SUMS.txt.sig."), false)
    }
    guard UpdateSig.valid(sumsData, sigData) else {
        try? fm.removeItem(atPath: sums)
        try? fm.removeItem(atPath: sig)
        trace("update signature bad")
        return (nil, T("The signature of this release doesn't match the developer's key, so Amnesia did not install it. "
                       + "It may have been changed by someone else. Open the release page and don't install it unless you're sure.",
                       "Tanda tangan rilis ini tidak cocok dengan kunci developer, jadi Amnesia tidak memasangnya. "
                       + "Mungkin sudah diubah orang lain. Buka halaman rilis, dan jangan pasang kecuali kamu yakin."), true)
    }
    let want = text.split(separator: "\n").map { $0.split(separator: " ", omittingEmptySubsequences: true) }
        .first { $0.count >= 2 && $0.last.map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "*")) } == name }?
        .first.map(String.init)?.lowercased()
    guard let want, want.count == 64 else {
        return (nil, T("SHA256SUMS.txt has no line for \(name).", "SHA256SUMS.txt tidak berisi baris untuk \(name)."), true)
    }
    func hash() -> String {
        sh("/usr/bin/shasum", ["-a", "256", file], timeout: 120).out.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
    }
    if fm.fileExists(atPath: file), hash() == want { return (file, nil, false) }      // sudah diunduh sebelumnya
    guard sh("/usr/bin/curl", ["-fsSL", "-m", "900", "-o", file, rel.dmg], timeout: 920).code == 0 else {
        try? fm.removeItem(atPath: file)
        return (nil, T("The download failed. Check your internet and try again.", "Unduhan gagal. Cek internet, lalu coba lagi."), false)
    }
    guard hash() == want else {
        try? fm.removeItem(atPath: file)
        return (nil, T("The downloaded file doesn't match SHA256SUMS.txt, so it was deleted. Try again later.",
                       "File yang diunduh tidak cocok dengan SHA256SUMS.txt, jadi dihapus. Coba lagi nanti."), false)
    }
    return (file, nil, false)
}

/// Buka .dmg, salin Amnesia.app ke folder sementara, cek versinya. Hasil: path app baru, atau pesan gagal.
func unpackRelease(_ dmg: String, version: String) -> (app: String?, error: String?) {
    let fm = FileManager.default
    let mnt = UpdateFiles.dir + "/mnt", out = UpdateFiles.dir + "/new"
    try? fm.removeItem(atPath: out)
    try? fm.createDirectory(atPath: mnt, withIntermediateDirectories: true)
    try? fm.createDirectory(atPath: out, withIntermediateDirectories: true)
    guard sh("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mnt, dmg], timeout: 120).code == 0 else {
        return (nil, T("Could not open the downloaded .dmg.", "Tidak bisa membuka file .dmg yang diunduh."))
    }
    let copied = sh("/usr/bin/ditto", [mnt + "/Amnesia.app", out + "/Amnesia.app"], timeout: 300).code == 0
    sh("/usr/bin/hdiutil", ["detach", mnt, "-force"], timeout: 60)
    let app = out + "/Amnesia.app"
    guard copied else { return (nil, T("Amnesia.app was not found in the .dmg.", "Amnesia.app tidak ditemukan di dalam .dmg.")) }
    let v = NSDictionary(contentsOfFile: app + "/Contents/Info.plist")?["CFBundleShortVersionString"] as? String
    guard v == version else {
        return (nil, T("The app in the .dmg is not version \(version).", "App di dalam .dmg bukan versi \(version)."))
    }
    // sidik file sudah cocok dengan SHA256SUMS.txt yang tanda tangannya benar, jadi tanda "diunduh dari internet" boleh dilepas
    sh("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app], timeout: 60)
    return (app, nil)
}

@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    enum Phase: Equatable {
        case idle, checking, upToDate
        case available(String)          // ada versi baru, belum diunduh
        case downloading(String)
        case ready(String)              // sudah diunduh & dicek, tinggal pasang
        case installing
        case failed(String)
    }

    @Published var phase: Phase = .idle
    /// v5.22: unduhan ditolak karena tanda tangan: tampilkan tombol ke halaman rilis
    @Published var sendToPage = false
    private var release: ReleaseInfo?
    private var file: String?
    private var timer: Timer?

    var version: String? {
        switch phase {
        case .available(let v), .downloading(let v), .ready(let v): return v
        default: return nil
        }
    }

    /// Cek otomatis: 1 menit setelah app jalan, lalu dicek tiap 6 jam, tapi GitHub hanya ditanya
    /// sesuai pilihan (v5.20: seminggu / 2 minggu / sebulan sekali, atau mati).
    func startSchedule() {
        UpdateEvery.migrate()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
            Task { @MainActor in Updater.shared.autoCheck() }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            self.autoCheck()
        }
    }

    private func autoCheck() {
        let days = UpdateEvery.days
        guard days > 0 else { return }
        let last = Double(Config.get("UPDATE_LAST", "0")) ?? 0
        // 4 jam lebih awal boleh, supaya cek mingguan tidak mundur terus karena jadwal 6 jam
        guard Date().timeIntervalSince1970 - last > Double(days) * 86400 - 4 * 3600 else { return }
        check(manual: false)
    }

    func check(manual: Bool) {
        switch phase {
        case .checking, .downloading, .installing: return
        default: break
        }
        phase = .checking
        Config.set("UPDATE_LAST", String(Int(Date().timeIntervalSince1970)))
        Model.shared.quiet({ fetchLatest() }) { rel in
            guard let rel else {
                self.phase = manual ? .failed(T("Could not reach GitHub. Check your internet and try again.",
                                                "Tidak bisa menghubungi GitHub. Cek internet, lalu coba lagi.")) : .idle
                return
            }
            guard isNewer(rel.version, than: appVersion) else { self.phase = .upToDate; return }
            self.release = rel
            self.phase = .available(rel.version)
            trace("update available: \(rel.version)")
            if Setting.updateAuto.isOn && self.canInstall == nil { self.download() }
        }
    }

    func download() {
        guard let rel = release else { return }
        phase = .downloading(rel.version)
        sendToPage = false
        Model.shared.quiet({ downloadRelease(rel) }) { r in
            if let f = r.path {
                self.file = f
                self.phase = .ready(rel.version)
                trace("update downloaded: \(rel.version)")
            } else {
                self.sendToPage = r.page
                self.phase = .failed(r.error ?? "")
                trace("update download failed")
            }
        }
    }

    /// nil = boleh dipasang dari app. Kalau tidak, alasannya (dan apa yang harus dilakukan).
    var canInstall: String? {
        if UpdateFiles.brew {
            return T("You installed Amnesia with Homebrew. Update it in Terminal: brew upgrade --cask amnesia",
                     "Amnesia dipasang lewat Homebrew. Update lewat Terminal: brew upgrade --cask amnesia")
        }
        if !UpdateSig.ready {
            return T("This copy of Amnesia has no update key, so it can't check that an update really comes from the "
                     + "developer. Download the new version from the release page and install it yourself.",
                     "Salinan Amnesia ini tidak punya kunci update, jadi tidak bisa memastikan update benar dari developer. "
                     + "Unduh versi baru dari halaman rilis, lalu pasang sendiri.")
        }
        if !Model.shared.installedApp {
            return T("Amnesia is not in the Applications folder, so it can't update itself.",
                     "Amnesia tidak ada di folder Applications, jadi tidak bisa update sendiri.")
        }
        let parent = (Bundle.main.bundlePath as NSString).deletingLastPathComponent
        if !FileManager.default.isWritableFile(atPath: parent) {
            return T("Your user can't write to \(parent). Download the update from GitHub and drag it in yourself.",
                     "User kamu tidak boleh menulis di \(parent). Unduh update dari GitHub lalu seret sendiri.")
        }
        return nil
    }

    func install() {
        guard case .ready(let v) = phase, let file else { return }
        if let why = canInstall { info(T("Can't update from the app", "Tidak bisa update dari app"), why, error: true); return }
        let m = Model.shared
        guard m.busy == nil else {
            info(T("Wait a moment", "Tunggu sebentar"), T("Wait until the current job is finished.",
                                                         "Tunggu sampai proses yang sedang berjalan selesai."))
            return
        }
        let wasOn = m.state != .off
        guard ask(T("Install Amnesia \(v)?", "Pasang Amnesia \(v)?"), "",
                  [PopSection(.happens, [T("1. Amnesia closes and the new version replaces it in Applications.",
                                           "1. Amnesia ditutup, lalu versi baru menggantikannya di Applications."),
                                         T("2. The new version opens by itself.", "2. Versi baru terbuka sendiri.")]
                              + (wasOn ? [T("3. Amnesia is turned off for a moment while it updates (nothing is wiped), "
                                            + "then the new version turns it back on.",
                                            "3. Selama update, Amnesia dimatikan sebentar (tidak ada yang dibersihkan), "
                                            + "lalu versi baru menyalakannya lagi.")] : [])),
                   PopSection(.kept, [T("Your vault, snapshots, Keep List, Keep folder and settings.",
                                        "Vault, snapshot, Keep List, folder Keep, dan pengaturan kamu.")]),
                   PopSection(.note, [T("If copying fails, the old version is put back.",
                                        "Kalau penyalinan gagal, versi lama dikembalikan.")])],
                  ok: T("Install & Reopen", "Pasang & Buka Lagi")) else { return }
        phase = .installing
        m.background(T("Preparing the update…", "Menyiapkan update…"), { unpackRelease(file, version: v) }) { r in
            guard let app = r.app else {
                self.phase = .failed(r.error ?? "")
                info(T("Update failed", "Update gagal"), (r.error ?? "") + "\n\n"
                     + T("Nothing was changed.", "Tidak ada yang diubah."), error: true)
                return
            }
            self.swap(app, version: v, wasOn: wasOn)
        }
    }

    private func swap(_ newApp: String, version: String, wasOn: Bool) {
        let fm = FileManager.default
        let dest = Bundle.main.bundlePath
        let script = UpdateFiles.dir + "/swap.sh"
        // Script kecil yang jalan setelah app ini tertutup: ganti app, kembalikan yang lama kalau gagal, lalu buka.
        let body = """
        #!/bin/bash
        PID="$1"; NEW="$2"; DEST="$3"; HIST="$4"; V="$5"
        for i in $(seq 1 120); do kill -0 "$PID" 2>/dev/null || break; sleep 0.5; done
        OLD="$DEST.old-update"
        rm -rf "$OLD"
        if ! mv "$DEST" "$OLD"; then open "$DEST"; exit 1; fi
        if ditto "$NEW" "$DEST"; then
            rm -rf "$OLD" "$NEW"
            printf '%s\\tupdate\\t%s\\n' "$(date '+%F %T')" "$V" >> "$HIST"
        else
            rm -rf "$DEST"; mv "$OLD" "$DEST"
        fi
        open "$DEST"
        """
        do { try body.write(toFile: script, atomically: true, encoding: .utf8) } catch {
            phase = .failed(error.localizedDescription); return
        }
        if wasOn {
            // sama seperti Matikan, tapi Jeda 1 Sesi tidak dibatalkan. Plist dihapus DULU: agent keluar tanpa membersihkan.
            fm.createFile(atPath: UpdateFiles.turnOnFlag, contents: nil)
            try? fm.removeItem(atPath: P.plist)
            sh(P.launchctl, ["bootout", "\(P.domain)/\(P.label)"])
        }
        let args = ["/bin/bash", script, String(getpid()), newApp, dest, History.path, version]
        guard spawnDetached(args) else {
            if wasOn { try? fm.removeItem(atPath: UpdateFiles.turnOnFlag); _ = Model.shared.activate() }
            phase = .failed(T("Could not start the updater.", "Tidak bisa menjalankan proses update."))
            return
        }
        trace("installing update \(version)")
        Model.shared.quitNow()
    }
}

/// Jalankan program di sesi sendiri (setsid), supaya tetap jalan setelah Amnesia tertutup.
func spawnDetached(_ args: [String]) -> Bool {
    var attr: posix_spawnattr_t? = nil
    posix_spawnattr_init(&attr)
    defer { posix_spawnattr_destroy(&attr) }
    posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
    var cargs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
    defer { cargs.forEach { free($0) } }
    var pid: pid_t = 0
    return posix_spawn(&pid, args[0], nil, &attr, &cargs, environ) == 0
}

struct UpdateCard: View {
    @ObservedObject private var u = Updater.shared
    @State private var check = Setting.updateCheck.isOn
    @State private var every = UpdateEvery.days
    @State private var auto = Setting.updateAuto.isOn

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(icon: "arrow.down.circle.fill", colors: Pal.accent, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(T("Updates", "Update")).font(.system(size: 14, weight: .semibold))
                    Text(T("You have Amnesia \(appVersion).", "Versi kamu: Amnesia \(appVersion)."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            // v5.20: pilih seberapa sering (dulu selalu sehari sekali)
            HStack(spacing: 8) {
                Text(T("Check for updates", "Cek update")).font(.system(size: 12))
                Spacer(minLength: 8)
                Picker("", selection: Binding(get: { every }, set: { d in
                    every = d; check = d > 0; UpdateEvery.set(d)
                })) {
                    ForEach(UpdateEvery.choices, id: \.self) { d in Text(UpdateEvery.label(d)).tag(d) }
                }
                .labelsHidden()
                .frame(width: 170)
            }
            Toggle(T("Download new versions by themselves", "Unduh versi baru otomatis"), isOn: Binding(get: { auto }, set: {
                auto = $0; Setting.updateAuto.set($0)
            }))
            .font(.system(size: 12))
            .disabled(!check)
            Note(text: T("Only asks GitHub which version is the newest. Nothing about you or your Mac is sent. "
                         + "Installing always waits for you to press the button.",
                         "Hanya bertanya ke GitHub versi mana yang terbaru. Tidak ada data tentang kamu atau Mac kamu yang dikirim. "
                         + "Pemasangan selalu menunggu kamu menekan tombol."), more: true)
            status
            HStack(spacing: 8) { buttons }
        }
    }

    @ViewBuilder private var status: some View {
        switch u.phase {
        case .idle: EmptyView()
        case .checking: Note(text: T("Checking…", "Mengecek…"), icon: "arrow.triangle.2.circlepath")
        case .upToDate: Note(text: T("You have the newest version.", "Kamu sudah memakai versi terbaru."),
                             icon: "checkmark.circle.fill", color: Th.green)
        case .available(let v): Note(text: T("Amnesia \(v) is out.", "Amnesia \(v) sudah keluar."),
                                     icon: "sparkles", color: Th.indigo)
        case .downloading(let v): Note(text: T("Downloading Amnesia \(v)…", "Mengunduh Amnesia \(v)…"),
                                       icon: "arrow.down.circle", color: Th.indigo)
        case .ready(let v): Note(text: T("Amnesia \(v) is downloaded and checked (signature + SHA-256). Ready to install.",
                                         "Amnesia \(v) sudah diunduh dan dicek (tanda tangan + SHA-256). Siap dipasang."),
                                 icon: "checkmark.seal.fill", color: Th.green)
        case .installing: Note(text: T("Installing…", "Memasang…"), icon: "hourglass")
        case .failed(let e): Note(text: e, icon: "exclamationmark.triangle.fill", color: Th.orange)
        }
        if u.version != nil, let why = u.canInstall {
            Note(text: why, icon: "info.circle.fill", color: Th.orange)
        }
    }

    @ViewBuilder private var buttons: some View {
        switch u.phase {
        case .available:
            if u.canInstall == nil {
                Button(T("Download", "Unduh")) { u.download() }.buttonStyle(Pill(colors: Pal.accent))
            } else {
                Button(T("Open GitHub", "Buka GitHub")) { NSWorkspace.shared.open(URL(string: UpdateFiles.page)!) }
                    .buttonStyle(Pill(colors: Pal.gray))
            }
        case .ready:
            Button(T("Install & Reopen", "Pasang & Buka Lagi")) { u.install() }.buttonStyle(Pill(colors: Pal.accent))
        case .failed where u.sendToPage:
            Button(T("Open Release Page", "Buka Halaman Rilis")) { NSWorkspace.shared.open(URL(string: UpdateFiles.page)!) }
                .buttonStyle(Pill(colors: Pal.gray))
            Button(T("Check Again", "Cek Lagi")) { u.check(manual: true) }.buttonStyle(Pill(colors: Pal.gray))
        case .checking, .downloading, .installing:
            Button(T("Please wait…", "Tunggu…")) {}.buttonStyle(Pill(colors: Pal.gray)).disabled(true)
        default:
            Button(T("Check Now", "Cek Sekarang")) { u.check(manual: true) }.buttonStyle(Pill(colors: Pal.gray))
        }
    }
}

/// Di menu bar: hanya muncul kalau ada versi baru.
struct MenuUpdateRow: View {
    @ObservedObject private var u = Updater.shared

    var body: some View {
        switch u.phase {
        case .available(let v):
            MenuTile(title: T("Amnesia \(v) is out: open Settings", "Amnesia \(v) sudah keluar: buka Pengaturan"),
                     icon: "sparkles", colors: Pal.accent) {
                Model.shared.page = .settings
                Opener.open?()
            }
        case .downloading(let v):
            MenuTile(title: T("Downloading Amnesia \(v)…", "Mengunduh Amnesia \(v)…"), icon: "arrow.down.circle",
                     colors: Pal.accent) {}
                .disabled(true)
        case .ready(let v):
            MenuTile(title: T("Install Amnesia \(v)", "Pasang Amnesia \(v)"), icon: "arrow.down.circle.fill",
                     colors: Pal.accent) { u.install() }
        default:
            EmptyView()
        }
    }
}

// MARK: - Enkripsi disk (FileVault)

enum DiskCrypt {
    enum State { case on, off, busy, unknown }

    static func status() -> State {
        let o = sh("/usr/bin/fdesetup", ["status"], timeout: 10).out
        if o.contains("FileVault is On") { return .on }
        if o.contains("FileVault is Off") { return .off }
        if o.contains("progress") { return .busy }
        return .unknown
    }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?FileVault")!)
    }
}

struct EncryptionCard: View {
    @State private var s: DiskCrypt.State?

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(icon: s == .on ? "lock.shield.fill" : "lock.open.fill",
                          colors: s == .on ? Pal.on : (s == nil || s == .unknown ? Pal.gray : Pal.pause), size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(T("Disk encryption (FileVault)", "Enkripsi disk (FileVault)")).font(.system(size: 14, weight: .semibold))
                    Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if s == .off {
                Button(T("Open FileVault Settings", "Buka Pengaturan FileVault")) { DiskCrypt.openSettings() }
                    .buttonStyle(Pill(colors: Pal.pause))
            }
        }
        .task {
            let r = await Task.detached { DiskCrypt.status() }.value
            s = r
        }
    }

    private var text: String {
        switch s {
        case .none: return T("Checking…", "Mengecek…")
        case .on?: return T("On. Your Keep folder and everything else on the disk can't be read without your password.",
                            "Aktif. Folder Keep dan isi disk lainnya tidak bisa dibaca tanpa password kamu.")
        case .busy?: return T("Encrypting now. Keep the Mac plugged in until it's done.",
                              "Sedang mengenkripsi. Biarkan Mac tercolok listrik sampai selesai.")
        case .off?: return T("Off. Amnesia only wipes at logout, and your Keep folder is not encrypted. With FileVault off, "
                             + "someone who takes the disk can read it. Turning FileVault on is strongly recommended.",
                             "Mati. Amnesia hanya membersihkan saat logout, dan folder Keep tidak dienkripsi. Tanpa FileVault, "
                             + "orang yang mengambil disknya bisa membacanya. Sangat disarankan menyalakan FileVault.")
        case .unknown?: return T("Couldn't check. Look in System Settings → Privacy & Security → FileVault.",
                                 "Tidak bisa dicek. Lihat di System Settings → Privacy & Security → FileVault.")
        }
    }
}

// MARK: - Logout otomatis kalau Mac ditinggal

@MainActor
final class IdleWatch: ObservableObject {
    static let shared = IdleWatch()
    @Published var left = 60
    private var timer: Timer?
    private var tick1: Timer?
    private var panel: NSPanel?

    static let choices = [0, 5, 10, 15, 30, 60]
    static var minutes: Int { Int(Config.get("AUTO_LOGOUT_MIN", "0")) ?? 0 }

    /// Detik sejak keyboard / mouse / trackpad terakhir dipakai.
    static var idle: Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            Task { @MainActor in IdleWatch.shared.check() }
        }
    }

    private func check() {
        let min = IdleWatch.minutes
        let m = Model.shared
        // hanya saat Amnesia aktif (bukan dijeda / mati) dan tidak ada proses berat (snapshot, backup)
        guard min > 0, panel == nil, m.state == .active, m.busy == nil, m.pending == nil,
              IdleWatch.idle >= Double(min * 60) else { return }
        showCountdown()
    }

    private func showCountdown() {
        left = 60
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 210),
                        styleMask: [.titled, .nonactivatingPanel, .hudWindow, .utilityWindow], backing: .buffered, defer: false)
        p.title = "Amnesia"
        p.level = .screenSaver
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: CountdownView(w: self))
        p.center()
        p.orderFrontRegardless()
        panel = p
        trace("auto logout countdown started")
        tick1 = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in IdleWatch.shared.step() }
        }
    }

    private func step() {
        // keyboard / mouse dipakai lagi → batal
        if IdleWatch.idle < 2 { cancel(); return }
        left -= 1
        if left <= 0 { logoutNow() }
    }

    func cancel() {
        tick1?.invalidate(); tick1 = nil
        panel?.close(); panel = nil
        trace("auto logout cancelled")
    }

    private func logoutNow() {
        let min = IdleWatch.minutes
        tick1?.invalidate(); tick1 = nil
        panel?.close(); panel = nil
        trace("auto logout")
        let line = "\(History.stamp())\tautologout\t\(min)\n"
        if let h = FileHandle(forWritingAtPath: History.path) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else {
            try? line.write(toFile: History.path, atomically: true, encoding: .utf8)
        }
        Model.shared.allowQuit = true          // logout dari kita sendiri: jangan ditahan "Cek dulu sebelum logout"
        sh("/usr/bin/osascript", ["-e", "tell application \"loginwindow\" to «event aevtrlgo»"])
    }
}

extension History {
    static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }
}

struct CountdownView: View {
    @ObservedObject var w: IdleWatch

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.zzz.fill").font(.system(size: 28, weight: .semibold)).foregroundStyle(Th.orange)
            Text(T("Logging out in \(w.left) s", "Logout dalam \(w.left) detik"))
                .font(.system(size: 18, weight: .bold)).monospacedDigit()
            Text(T("This Mac wasn't used for a while. Amnesia logs out and wipes this session. Move the mouse or press a key to stay.",
                   "Mac ini lama tidak dipakai. Amnesia akan logout dan membersihkan sesi ini. Gerakkan mouse atau tekan tombol apa saja untuk batal."))
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(T("I'm Here", "Saya Masih di Sini")) { w.cancel() }
                .buttonStyle(Pill(colors: Pal.accent))
                .frame(width: 200)
        }
        .padding(20)
        .frame(width: 360)
    }
}

// MARK: - Hapus app yang dipasang setelah fitur ini dinyalakan

struct NewApp: Identifiable {
    let path: String
    let name: String
    let icon: NSImage
    let mine: Bool       // milik user ini (bisa dihapus). Kalau tidak: dipasang dengan password admin, tidak disentuh
    let kept: Bool
    var id: String { path }
}

enum NewApps {
    static let baseline = P.a + "/apps_baseline.txt"
    static var on: Bool { Config.get("REMOVE_NEW_APPS") == "1" }

    /// Sama dengan clean.sh: /Applications dan ~/Applications (mode tes: hanya ~/Applications palsu).
    static var dirs: [String] {
        ProcessInfo.processInfo.environment["AMNESIA_HOME"] != nil ? [P.home + "/Applications"]
                                                                   : ["/Applications", P.home + "/Applications"]
    }

    static func current() -> [String] {
        let fm = FileManager.default
        var out: [String] = []
        for d in dirs {
            for n in ((try? fm.contentsOfDirectory(atPath: d)) ?? []).sorted() where n.hasSuffix(".app") {
                let p = d + "/" + n
                if (try? fm.destinationOfSymbolicLink(atPath: p)) != nil { continue }
                out.append(p)
            }
        }
        return out
    }

    static func turnOn() -> Int {
        let apps = current()
        try? (apps.joined(separator: "\n") + "\n").write(toFile: baseline, atomically: true, encoding: .utf8)
        Config.set("REMOVE_NEW_APPS", "1")
        return apps.count
    }

    static func turnOff() {
        Config.set("REMOVE_NEW_APPS", "0")
        try? FileManager.default.removeItem(atPath: baseline)
    }

    static func list() -> [NewApp] {
        guard let text = try? String(contentsOfFile: baseline, encoding: .utf8) else { return [] }
        let base = Set(text.split(separator: "\n").map(String.init))
        let keep = Set(Keep.entries())
        let fm = FileManager.default
        return current().filter { p in
            let n = (p as NSString).lastPathComponent
            return !base.contains(p) && n != "Amnesia.app" && n != "Amnesia Shots.app"
        }.map { p in
            let owner = (try? fm.attributesOfItem(atPath: p))?[.ownerAccountID] as? NSNumber
            return NewApp(path: p, name: ((p as NSString).lastPathComponent as NSString).deletingPathExtension,
                          icon: NSWorkspace.shared.icon(forFile: p), mine: owner?.uint32Value == getuid(),
                          kept: keep.contains("app:" + p))
        }
    }

    static func setKept(_ path: String, _ on: Bool) {
        if on { Keep.add(["app:" + path]) } else { Keep.remove("app:" + path) }
    }
}

// MARK: - Pencarian di Pengaturan (v5.20)

/// Huruf kecil, tanpa aksen: "Pengaturan" dan "pengaturan" dianggap sama.
func searchFold(_ s: String) -> String {
    s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
}

/// Semua kata yang diketik harus ada di teks (urutan bebas). Kolom kosong = semua cocok.
func searchHit(_ query: String, _ hay: String) -> Bool {
    let words = searchFold(query).split(separator: " ").map(String.init)
    if words.isEmpty { return true }
    let h = searchFold(hay)
    return words.allSatisfy { h.contains($0) }
}

/// Teks 1 kartu di Pengaturan: judul + penjelasan dalam English dan Indonesia, plus kata lain (tidak ditampilkan).
/// Pencarian selalu memakai kedua bahasa, apa pun bahasa app yang dipilih.
struct SetText {
    let en: String
    let id: String
    var subEn = ""
    var subId = ""
    var tags = ""
    var title: String { T(en, id) }
    var sub: String { T(subEn, subId) }
    func hit(_ query: String) -> Bool { searchHit(query, [en, id, subEn, subId, tags].joined(separator: " ")) }
}

// MARK: - Lanjutan (v5.20: grup di dalam Pengaturan, dulu halaman sendiri)

struct AdvancedGroup: View {
    @EnvironmentObject var m: Model
    let query: String
    @State private var idleMin = IdleWatch.minutes
    @State private var newOn = NewApps.on
    @State private var apps: [NewApp] = []

    /// judul grup: mencari "lanjutan" / "advanced" menampilkan semua isinya
    static let tGroup = SetText(en: "Advanced", id: "Lanjutan", tags: "expert danger bahaya")
    static let tAutoLogout = SetText(
        en: "Log out when the Mac is left alone", id: "Logout otomatis kalau Mac ditinggal",
        subEn: "If nobody touches the keyboard, mouse or trackpad for this long, a 60-second countdown appears, "
            + "then you are logged out and the session is wiped. Any key or mouse move cancels it. "
            + "Only while Amnesia is on (not paused). An app with an unsaved document can still stop the logout. "
            + "Your auto snapshot runs as usual.",
        subId: "Kalau keyboard, mouse, atau trackpad tidak disentuh selama waktu ini, muncul hitung mundur 60 detik, "
            + "lalu kamu di-logout dan sesi dibersihkan. Tekan tombol apa saja atau gerakkan mouse untuk batal. "
            + "Hanya saat Amnesia aktif (tidak dijeda). App dengan dokumen yang belum disimpan masih bisa menahan "
            + "logout. Snapshot otomatis tetap berjalan seperti biasa.",
        tags: "idle timer away lock kunci auto")
    static let tNewApps = SetText(
        en: "Remove apps installed later", id: "Hapus app yang dipasang belakangan",
        subEn: "Apps you install after switching this on are removed at every logout, unless you keep them below. "
            + "Apps that were already installed stay. Apps installed with an admin password are not touched, "
            + "only noted in History. The vault keeps app data, not the apps themselves.",
        subId: "App yang kamu pasang setelah ini dinyalakan dihapus setiap logout, kecuali kamu simpan di bawah. "
            + "App yang sudah terpasang sebelumnya tetap ada. App yang dipasang dengan password admin tidak disentuh, "
            + "hanya dicatat di Riwayat. Vault menyimpan data app, bukan app-nya.",
        tags: "uninstall application aplikasi install pasang")
    static let tPanic = SetText(
        en: "Panic word", id: "Kata panik",
        subEn: "A second password for the vault. Typing it deletes the vault for good (and, if you chose so, empties the "
            + "Keep folder). It can't be undone. Set or change it on the Profile Vault page.",
        subId: "Password kedua untuk vault. Kalau diketik, vault terhapus selamanya (dan, kalau kamu memilihnya, folder Keep "
            + "ikut dikosongkan). Tidak bisa dibatalkan. Atur atau ganti di halaman Profile Vault.",
        tags: "duress emergency darurat wipe")
    static let tMove = SetText(
        en: "Move to a New Mac", id: "Pindah Mac",
        subEn: "Take your vault, Keep List and settings to another Mac, or get the vault back from a backup.",
        subId: "Bawa vault, Keep List, dan pengaturan ke Mac lain, atau ambil lagi vault dari backup.",
        tags: "migrate migrasi transfer export import restore")
    /// semua teks grup ini (untuk "tidak ada yang cocok" di Pengaturan)
    static var texts: [SetText] { [tGroup, tAutoLogout, tNewApps, tPanic, tMove] }

    private func show(_ t: SetText) -> Bool { Self.tGroup.hit(query) || t.hit(query) }
    private var anyShown: Bool { [Self.tAutoLogout, Self.tNewApps, Self.tPanic, Self.tMove].contains { show($0) } }

    var body: some View {
        VStack(spacing: 14) {
            if anyShown {
                HStack(spacing: 10) {
                    IconBadge(icon: "exclamationmark.shield.fill", colors: Pal.pause, size: 28)
                    Text(Self.tGroup.title).font(.system(size: 17, weight: .bold))
                    Spacer()
                }
                .padding(.top, 10)
                Note(text: T("These settings can delete more, or act by themselves. Read each one before you switch it on.",
                             "Pengaturan di sini bisa menghapus lebih banyak, atau berjalan sendiri. Baca dulu sebelum menyalakannya."),
                     icon: "exclamationmark.triangle.fill", color: Th.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if show(Self.tAutoLogout) { autoLogout }
                if show(Self.tNewApps) { newApps }
                if show(Self.tPanic) {
                    link(Self.tPanic, "flame.fill", Pal.danger, T("Open Profile Vault", "Buka Profile Vault")) { m.page = .vault }
                }
                if show(Self.tMove) {
                    link(Self.tMove, "arrow.right.arrow.left.circle.fill", Pal.backup,
                         T("Open Move to a New Mac", "Buka Pindah Mac")) { m.page = .move }
                }
            }
        }
        .onAppear { reload() }
    }

    private func reload() { apps = newOn ? NewApps.list() : [] }

    private var autoLogout: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(icon: "moon.zzz.fill", colors: Pal.pause, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.tAutoLogout.title)
                        .font(.system(size: 14, weight: .semibold))
                    MoreText(Self.tAutoLogout.sub)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Picker("", selection: Binding(get: { idleMin }, set: { setIdle($0) })) {
                    ForEach(IdleWatch.choices, id: \.self) { n in
                        Text(n == 0 ? T("Off", "Mati") : T("\(n) min", "\(n) menit")).tag(n)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
            }
        }
    }

    private func setIdle(_ n: Int) {
        if n > 0 && idleMin == 0 {
            guard ask(T("Log out by itself after \(n) minutes?", "Logout sendiri setelah \(n) menit?"), "",
                      [PopSection(.happens, [T("When the Mac isn't used for \(n) minutes, a 60-second countdown appears.",
                                               "Kalau Mac tidak dipakai selama \(n) menit, muncul hitung mundur 60 detik."),
                                             T("Then you are logged out, and everything outside the Keep List and Keep folder is wiped.",
                                               "Lalu kamu di-logout, dan semua di luar Keep List dan folder Keep dibersihkan.")]),
                       PopSection(.todo, [T("Save your work often. A long download or render with no keyboard use can be cut off.",
                                            "Sering-sering simpan pekerjaan. Unduhan atau render panjang tanpa sentuhan keyboard bisa terpotong.")])],
                      ok: T("Turn On", "Nyalakan"), danger: true) else { return }
        }
        idleMin = n
        Config.set("AUTO_LOGOUT_MIN", String(n))
        trace("auto logout: \(n) min")
    }

    private var newApps: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(icon: "trash.square.fill", colors: Pal.danger, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.tNewApps.title)
                        .font(.system(size: 14, weight: .semibold))
                    MoreText(Self.tNewApps.sub)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(get: { newOn }, set: { setNewApps($0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
            if newOn {
                if apps.isEmpty {
                    Note(text: T("No new apps since you switched this on.", "Belum ada app baru sejak fitur ini dinyalakan."),
                         icon: "checkmark.circle.fill", color: Th.green)
                }
                ForEach(apps) { a in appRow(a) }
                Button(T("Refresh List", "Muat Ulang Daftar")) { reload() }.buttonStyle(Pill(colors: Pal.gray))
            }
        }
    }

    private func appRow(_ a: NewApp) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: a.icon).resizable().frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(a.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Text(!a.mine ? T("Installed with an admin password: not removed", "Dipasang dengan password admin: tidak dihapus")
                     : a.kept ? T("Kept", "Disimpan") : T("Removed at logout", "Dihapus saat logout"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(!a.mine ? Th.muted : (a.kept ? Th.green : Th.red))
            }
            Spacer(minLength: 6)
            if a.mine {
                Button(a.kept ? T("Don't Keep", "Jangan Simpan") : T("Keep", "Simpan")) {
                    NewApps.setKept(a.path, !a.kept)
                    reload()
                }
                .buttonStyle(Pill(colors: a.kept ? Pal.gray : Pal.keep))
                .frame(width: 110)
            }
        }
        .padding(8)
        .surface(12, fill: Th.tile)
    }

    private func setNewApps(_ on: Bool) {
        if on {
            let n = NewApps.current().count
            guard ask(T("Remove apps installed from now on?", "Hapus app yang dipasang mulai sekarang?"), "",
                      [PopSection(.happens, [T("Every app you install in Applications from now on is removed at each logout, "
                                               + "while Amnesia is on.",
                                               "Setiap app yang kamu pasang di Applications mulai sekarang dihapus setiap logout, "
                                               + "selama Amnesia aktif."),
                                             T("Want to keep one? Press Keep next to it on this page.",
                                               "Mau menyimpan salah satunya? Tekan Simpan di sampingnya di halaman ini.")]),
                       PopSection(.kept, [T("The \(n) apps already installed now, and Amnesia itself.",
                                            "\(n) app yang sudah terpasang sekarang, dan Amnesia sendiri."),
                                          T("Apps installed with an admin password (they are only noted in History).",
                                            "App yang dipasang dengan password admin (hanya dicatat di Riwayat).")]),
                       PopSection(.note, [T("The vault keeps app data, not programs. A removed app must be installed again.",
                                            "Vault menyimpan data app, bukan program-nya. App yang terhapus harus dipasang ulang.")])],
                      ok: T("Turn On", "Nyalakan"), danger: true) else { return }
            _ = NewApps.turnOn()
            trace("remove new apps: on (\(n) in baseline)")
        } else {
            NewApps.turnOff()
            trace("remove new apps: off")
        }
        newOn = on
        reload()
    }

    private func link(_ t: SetText, _ icon: String, _ colors: [Color], _ button: String,
                      action: @escaping () -> Void) -> some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(icon: icon, colors: colors, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(t.title).font(.system(size: 14, weight: .semibold))
                    MoreText(t.sub).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Button(button, action: action).buttonStyle(Pill(colors: Pal.gray))
        }
    }
}

// MARK: - v5.19.1: jalan pintas ke folder Keep (Desktop + sidebar Finder)
// Desktop dan daftar sidebar Finder (Library/Application Support/com.apple.sharedfilelist) ikut dibersihkan setiap
// logout, jadi Amnesia memasang lagi keduanya saat app jalan setelah login, saat Aktifkan, dan saat saklarnya diganti.
// clean.sh juga membuat ulang alias di Desktop sesudah membersihkan (KEEP_SHORTCUT di settings.conf).

enum KeepLinks {
    static var desktopLink: String { P.home + "/Desktop/" + KeepDir.name }

    /// Pasang (atau lepas) alias Desktop + sidebar Finder sesuai Pengaturan.
    static func sync() {
        let fm = FileManager.default
        let keep = KeepDir.path
        if !keep.hasPrefix(P.home + "/Desktop/") {
            let link = desktopLink
            let target = try? fm.destinationOfSymbolicLink(atPath: link)
            if Setting.keepShortcut.isOn {
                if target == nil && !fm.fileExists(atPath: link) && fm.fileExists(atPath: keep) {
                    try? fm.createSymbolicLink(atPath: link, withDestinationPath: keep)
                }
            } else if target == keep {
                try? fm.removeItem(atPath: link)      // hanya alias buatan Amnesia, bukan file kamu yang namanya sama
            }
        }
        if fm.fileExists(atPath: keep) {
            FinderSidebar.set(URL(fileURLWithPath: keep), on: Setting.keepSidebar.isOn)
        }
    }

    /// v5.22: Kunci Keep menyala dan terkunci → minta password Keep dulu.
    @MainActor static func open() {
        guard KeepLock.askUnlock(T("Open the Keep folder in Finder.", "Buka folder Keep di Finder.")) else { return }
        try? FileManager.default.createDirectory(atPath: KeepDir.path, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: KeepDir.path))
    }
}

/// Favorit di sidebar Finder lewat LSSharedFileList. API ini sudah lama "deprecated" tapi masih dipakai Finder;
/// dipanggil lewat dlsym supaya build tidak gagal kalau suatu saat Apple menghapusnya (fiturnya diam saja).
enum FinderSidebar {
    private typealias Ref = UnsafeMutableRawPointer
    private typealias CreateFn = @convention(c) (Ref?, Ref, Ref?) -> Ref?
    private typealias SnapshotFn = @convention(c) (Ref, UnsafeMutablePointer<UInt32>?) -> Ref?
    private typealias ResolveFn = @convention(c) (Ref, UInt32, Ref?) -> Ref?
    private typealias InsertFn = @convention(c) (Ref, Ref, Ref?, Ref?, Ref, Ref?, Ref?) -> Ref?
    private typealias RemoveFn = @convention(c) (Ref, Ref) -> Int32

    static func set(_ url: URL, on: Bool) {
        guard let h = dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_NOW),
              let c = dlsym(h, "LSSharedFileListCreate"), let s = dlsym(h, "LSSharedFileListCopySnapshot"),
              let r = dlsym(h, "LSSharedFileListItemCopyResolvedURL"), let i = dlsym(h, "LSSharedFileListInsertItemURL"),
              let rm = dlsym(h, "LSSharedFileListItemRemove"),
              let favP = dlsym(h, "kLSSharedFileListFavoriteItems"), let lastP = dlsym(h, "kLSSharedFileListItemLast"),
              let fav = favP.load(as: Ref?.self), let last = lastP.load(as: Ref?.self)
        else { trace("finder sidebar: api missing"); return }
        let create = unsafeBitCast(c, to: CreateFn.self), snapshot = unsafeBitCast(s, to: SnapshotFn.self)
        let resolve = unsafeBitCast(r, to: ResolveFn.self), insert = unsafeBitCast(i, to: InsertFn.self)
        let remove = unsafeBitCast(rm, to: RemoveFn.self)

        guard let list = create(nil, fav, nil) else { trace("finder sidebar: no list"); return }
        let listObj = Unmanaged<AnyObject>.fromOpaque(list).takeRetainedValue()
        let want = url.standardizedFileURL.path
        var found = false
        if let arrP = snapshot(list, nil) {
            let items = Unmanaged<CFArray>.fromOpaque(arrP).takeRetainedValue() as NSArray
            for item in items {
                let ip = Unmanaged.passUnretained(item as AnyObject).toOpaque()
                // 1 = tanpa dialog, 2 = jangan mount drive
                guard let uP = resolve(ip, 3, nil) else { continue }
                let u = Unmanaged<CFURL>.fromOpaque(uP).takeRetainedValue() as URL
                guard u.standardizedFileURL.path == want else { continue }
                found = true
                if !on { _ = remove(list, ip); trace("finder sidebar: keep removed") }
            }
        }
        if on && !found {
            let cu = url as CFURL
            if let added = insert(list, last, nil, nil, Unmanaged.passUnretained(cu).toOpaque(), nil, nil) {
                Unmanaged<AnyObject>.fromOpaque(added).release()
                trace("finder sidebar: keep added")
            }
            withExtendedLifetime(cu) {}
        }
        withExtendedLifetime(listObj) {}
    }
}
