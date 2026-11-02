// Amnesia v5.24: halaman Perawatan (Care): mengosongkan ruang kapan saja, selalu dengan daftar untuk dicek dulu.
// Dibuild bersama Amnesia.swift, Extras.swift dan Safety.swift (lihat build.sh).
// v5.24: idenya terinspirasi pembersih disk lain; semua kode, daftar dan teks di sini ditulis sendiri
// dari dokumentasi Apple dan kode Amnesia.
//
// Aturan pengaman (sama untuk semua fitur):
// - tidak pernah menyentuh ~/.amnesia (termasuk vault), folder Keep itu sendiri, com.apple.*, folder sistem,
//   akun lain, atau apa pun yang butuh password admin. Item di Keep List tidak bisa dipilih (kecuali cache/log);
// - tidak pernah mengikuti symlink: lstat, dan tidak boleh ada folder induk yang berupa symlink;
// - tidak bisa dicek (error, waktu habis, tidak terbaca) = dilindungi;
// - selalu: pindai (di background, maks 30 detik / 300.000 item, bisa dibatalkan) -> daftar -> konfirmasi
//   -> kerjakan -> hasil. Tepat sebelum dihapus, tiap item dicek ulang (inode + device sama, bukan link);
// - app, sisa app, installer dan folder build ke Trash macOS; cache, log dan tempat sampah Amnesia dihapus langsung.
// - trace.log hanya mencatat langkah + jumlah, tidak pernah nama file.
import AppKit
import SwiftUI

// MARK: - Bagian 1: logika (hanya Foundation)

/// v5.24: fitur Perawatan. rawValue dipakai di history.log: "<waktu>\tcare\t<fitur> <item> <KB> <gagal>".
enum CareFeature: String, CaseIterable, Sendable {
    case quick, apps, projects, installers, tune
}

/// v5.24: nama fitur untuk layar dan Riwayat.
func careFeatureName(_ raw: String) -> String {
    switch raw {
    case "quick": return T("Clean now", "Bersihkan sekarang")
    case "apps": return T("Uninstall apps", "Hapus app")
    case "projects": return T("Project build folders", "Folder build project")
    case "installers": return T("Old installers", "Installer lama")
    case "tune": return T("Safe tune-ups", "Perawatan ringan")
    default: return raw
    }
}

/// v5.24: cara 1 item dibereskan.
enum CareAct: Sendable, Equatable {
    case trash                 // pindah ke Trash macOS (bisa dikembalikan)
    case emptyInside(Double)   // isi folder dihapus langsung; angka = umur minimal isinya (detik)
    case task(String)          // tugas ringan: "ql" (Quick Look), "dock"
}

/// v5.24: 1 baris di daftar Perawatan.
struct CareItem: Identifiable, Sendable {
    let path: String           // path lengkap ("task:..." untuk tugas)
    let name: String
    var detail: String
    var kb: Int64 = -1         // -1 = ukuran tidak diketahui
    let group: String
    var pick = false           // dicentang dari awal
    var locked: String? = nil  // ada isinya = tidak bisa dipilih, dengan alasannya
    var tag: String? = nil     // label tambahan, mis. "Ada di Keep List" (masih bisa dipilih)
    let act: CareAct
    var dev: Int64 = 0         // identitas saat dipindai (dicek ulang sebelum dihapus)
    var ino: UInt64 = 0
    var keepOK = false         // cache/log: boleh dipilih walau ada di Keep List
    var id: String { path }
}

/// v5.24: 1 app di /Applications atau ~/Applications.
struct CareApp: Identifiable, Sendable {
    let path: String
    let name: String
    let bid: String
    var kb: Int64 = -1
    var locked: String? = nil
    let dev: Int64
    let ino: UInt64
    var id: String { path }
}

/// v5.24: app yang sedang terbuka (diambil di main thread, lalu dipakai di background).
struct CareRunning: Sendable {
    var ids: [String] = []
    var names: Set<String> = []
    var paths: Set<String> = []
    /// daftar kosong = tidak bisa dicek, jadi semua cache dianggap sedang dipakai
    var known: Bool { !ids.isEmpty }

    /// Folder cache/log ini milik app yang sedang terbuka?
    func uses(_ folder: String) -> Bool {
        if !known { return true }
        let f = folder.lowercased()
        if names.contains(f) { return true }
        return ids.contains { id in
            let b = id.lowercased()
            return b == f || b.hasPrefix(f + ".") || f.hasPrefix(b + ".")
        }
    }

    func runs(bid: String, path: String) -> Bool { ids.contains(bid) || paths.contains(path) }
}

/// v5.24: hasil lstat (tidak mengikuti symlink).
struct CareStat: Sendable {
    let dev: Int64
    let ino: UInt64
    let link: Bool
    let dir: Bool
    let mtime: Double
    let birth: Double
    let uid: UInt32
    let blocks: Int64
}

/// v5.24: pengecekan file yang dipakai semua fitur.
enum CareFS {
    static func info(_ p: String) -> CareStat? {
        var st = stat()
        guard lstat(p, &st) == 0 else { return nil }
        let fmt = st.st_mode & S_IFMT
        return CareStat(dev: Int64(st.st_dev), ino: UInt64(st.st_ino), link: fmt == S_IFLNK, dir: fmt == S_IFDIR,
                        mtime: Double(st.st_mtimespec.tv_sec), birth: Double(st.st_birthtimespec.tv_sec),
                        uid: UInt32(st.st_uid), blocks: Int64(st.st_blocks))
    }

    /// Isi folder. nil = tidak bisa dibaca (dianggap dilindungi oleh pemanggil).
    static func list(_ dir: String) -> [String]? { try? FileManager.default.contentsOfDirectory(atPath: dir) }

    /// Path relatif dari home, atau nil kalau di luar home.
    static func rel(_ p: String) -> String? { p.hasPrefix(P.home + "/") ? String(p.dropFirst(P.home.count + 1)) : nil }

    /// Untuk ditampilkan: ~/Downloads/x.dmg
    static func shown(_ p: String) -> String { rel(p).map { "~/" + $0 } ?? p }

    /// Ada symlink di path ini (item itu sendiri atau folder induknya di bawah home / folder Keep / Applications)?
    /// Tidak bisa dicek = true.
    static func linkInPath(_ p: String) -> Bool {
        let h = P.home, keep = KeepDir.path
        let base: String
        if p.hasPrefix(h + "/") {
            base = h
        } else if p.hasPrefix(keep + "/") {
            guard let k = info(keep), !k.link else { return true }
            base = keep
        } else if p.hasPrefix("/Applications/") {
            base = "/Applications"
        } else {
            return true
        }
        var cur = base
        for c in p.dropFirst(base.count + 1).split(separator: "/") {
            cur += "/" + String(c)
            guard let i = info(cur) else { return true }
            if i.link { return true }
        }
        return false
    }

    /// Aturan keras: true = path ini TIDAK boleh dipindah/dihapus utuh.
    static func refuse(_ p: String) -> Bool {
        let h = P.home, keep = KeepDir.path
        guard p.hasPrefix("/"), p.count > 1 else { return true }
        let comps = p.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map(String.init)
        if comps.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) { return true }
        if comps.contains(where: { $0.hasPrefix("com.apple.") }) { return true }
        let last = comps.last ?? ""
        if last.hasPrefix("Brankas.") || last.hasSuffix(".sparsebundle") || last.hasSuffix(".sparseimage") { return true }
        if p == h || p == keep || keep.hasPrefix(p + "/") { return true }          // home, folder Keep, atau induknya
        if p == P.a || p.hasPrefix(P.a + "/") { return true }                     // ~/.amnesia (vault, Keep List)
        if p == h + "/.amnesia-trash" || p == h + "/.Trash" { return true }       // hanya dikosongkan, tidak dihapus utuh
        if let r = rel(p) {
            let depth = r.split(separator: "/").count
            if depth < 2 { return true }                                           // folder pertama di home: tidak pernah
            if r.hasPrefix("Library/") && depth < 3 { return true }               // Library/Caches dan sejenisnya
            return false
        }
        if !keep.hasPrefix(h + "/") && p.hasPrefix(keep + "/") { return false }  // folder Keep di luar home (mis. SSD)
        // app di /Applications (hanya tingkat pertama)
        if (p as NSString).deletingLastPathComponent == "/Applications" && p.hasSuffix(".app") { return false }
        return true
    }

    /// Folder yang boleh dikosongkan isinya (cache/log per app, tempat sampah Amnesia, Trash macOS).
    static func containerOK(_ p: String) -> Bool {
        let h = P.home
        if p == h + "/.Trash" || p == h + "/.amnesia-trash" { return true }
        let parent = (p as NSString).deletingLastPathComponent
        let n = (p as NSString).lastPathComponent
        guard parent == h + "/Library/Caches" || parent == h + "/Library/Logs" else { return false }
        return !n.hasPrefix(".") && !n.hasPrefix("com.apple.") && !n.hasPrefix("com.amnesia")
            && n != "Amnesia" && n != "DiagnosticReports"
    }

    /// Ada di Keep List (path ini, folder induknya, atau ada item Keep List di dalamnya)?
    static func onKeepList(_ p: String, _ entries: [String]) -> Bool {
        guard let r = rel(p) else { return false }
        if keepMatches(r, entries) { return true }
        for e in entries {
            let fixed = e.prefix { !"*?[".contains($0) }
            if fixed.hasPrefix(r + "/") { return true }
        }
        return false
    }
}

/// v5.24: batas 1 pemindaian: 30 detik, 300.000 item, atau tombol Batal.
final class CareScan: @unchecked Sendable {
    static let maxSecs = 30.0
    static let maxEntries = 300_000
    private let lock = NSLock()
    private var stop = false
    private var proc: Process?
    let start = Date()
    private(set) var entries = 0
    /// pemindaian berhenti sebelum selesai (batas atau Batal): daftarnya mungkin tidak lengkap
    private(set) var cut = false

    var cancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return stop
    }

    func cancel() {
        lock.lock()
        stop = true
        let p = proc
        lock.unlock()
        if let p = p, p.isRunning { p.terminate() }
    }

    /// Program yang sedang jalan (du, git): ikut dihentikan kalau Batal ditekan.
    func running(_ p: Process) {
        lock.lock()
        proc = p
        let s = stop
        lock.unlock()
        if s { p.terminate() }
    }

    var timeLeft: Double { max(0, Self.maxSecs - Date().timeIntervalSince(start)) }

    /// Masih boleh lanjut?
    func alive() -> Bool {
        if cut { return false }
        if cancelled || timeLeft <= 0 || entries > Self.maxEntries { cut = true }
        return !cut
    }

    /// Hitung 1 item. false = berhenti.
    func step() -> Bool {
        entries += 1
        return alive()
    }
}

/// v5.24: ukuran folder.
enum CareSize {
    /// du -sk (tidak mengikuti symlink). Hasil: KB per path; yang tidak terukur tidak ada di hasil.
    static func du(_ paths: [String], scan: CareScan?, timeout: Double = 20) -> [String: Int64] {
        var out: [String: Int64] = [:]
        var i = 0
        while i < paths.count {
            let part = Array(paths[i..<min(i + 100, paths.count)])
            i += 100
            var t = timeout
            if let s = scan {
                guard s.alive() else { break }
                t = min(t, max(1, s.timeLeft))
            }
            let r = sh("/usr/bin/du", ["-sk"] + part, timeout: t, onStart: { p in scan?.running(p) })
            for line in r.out.split(separator: "\n") {
                let f = line.split(separator: "\t", maxSplits: 1)
                guard f.count == 2, let kb = Int64(f[0]) else { continue }
                out[String(f[1])] = kb
            }
        }
        return out
    }
}

/// v5.24: hasil 1 kali menjalankan fitur.
struct CareResult: Sendable {
    struct Line: Identifiable, Sendable {
        let group: String
        var done = 0
        var failed = 0
        var kb: Int64 = 0
        var id: String { group }
    }
    var lines: [Line] = []
    var done = 0
    var failed = 0
    var changed = 0            // berubah sejak dipindai, jadi dilewati (ikut dihitung gagal)
    var kb: Int64 = 0          // dihapus langsung
    var trashKB: Int64 = 0     // dipindah ke Trash (ruangnya kembali setelah Trash dikosongkan)

    mutating func add(_ group: String, ok: Bool, kb: Int64, trash: Bool) {
        if let i = lines.firstIndex(where: { $0.group == group }) {
            if ok { lines[i].done += 1 } else { lines[i].failed += 1 }
            lines[i].kb += kb
        } else {
            lines.append(Line(group: group, done: ok ? 1 : 0, failed: ok ? 0 : 1, kb: kb))
        }
        if ok { done += 1 } else { failed += 1 }
        if trash { trashKB += kb } else { self.kb += kb }
    }
}

/// v5.24: Ringkasan disk (hanya dibaca).
struct CareSpot: Identifiable, Sendable {
    let name: String
    let path: String
    var kb: Int64
    var id: String { name + "|" + path }
}

struct CareOverview: Sendable {
    var total: Int64 = -1
    var free: Int64 = -1
    var spots: [CareSpot] = []
    var folders: [CareSpot] = []
    var files: [CareSpot] = []
    var oldCount = 0
    var oldKB: Int64 = 0
    var cut = false
}

/// v5.24: pemindaian dan pekerjaan semua fitur. Jalan di background (bukan main thread).
enum CareScanner {
    static let day = 86_400.0
    /// Nama folder build + file penanda yang harus ada di sebelahnya (kosong = tidak perlu penanda).
    static let buildTargets: [String: [String]] = [
        "node_modules": ["package.json"],
        ".next": ["package.json"], ".nuxt": ["package.json"], ".turbo": ["package.json"],
        "dist": ["package.json", "pyproject.toml", "setup.py"],
        "build": ["package.json", "build.gradle", "build.gradle.kts", "CMakeLists.txt", "pyproject.toml", "setup.py"],
        "target": ["Cargo.toml", "pom.xml"],
        ".build": ["Package.swift"],
        "DerivedData": [],
        ".gradle": ["build.gradle", "build.gradle.kts"],
    ]
    /// Paket/bundle yang tidak pernah ditelusuri isinya.
    static let bundleExts: Set<String> = ["app", "sparsebundle", "sparseimage", "utm", "vmwarevm", "pvm", "photoslibrary",
                                          "musiclibrary", "tvlibrary", "photolibrary", "fcpbundle", "logicx", "band"]
    /// Image mesin virtual: tidak pernah ditampilkan.
    static let vmExts: Set<String> = ["utm", "vmwarevm", "pvm", "vbox", "vdi", "vmdk", "qcow2", "vhd", "vhdx"]

    static func now() -> Double { Date().timeIntervalSince1970 }

    /// v5.24: Keep List untuk Perawatan (sama urutannya dengan clean.sh dan vault.py: keep.conf, lalu salinan
    /// keep.conf.last, lalu keep.example.conf). nil = ada tapi tidak bisa dibaca: Perawatan tidak menghapus apa pun.
    /// "~/" di depan dibuang seperti di clean.sh; baris "app:" tetap ada (untuk Hapus app).
    static func keepEntries() -> [String]? {
        var seen = false
        for name in ["keep.conf", "keep.conf.last", "keep.example.conf"] {
            let f = P.a + "/" + name
            guard CareFS.info(f) != nil else { continue }
            if name == "keep.example.conf" && seen { break }
            seen = true
            guard let t = try? String(contentsOfFile: f, encoding: .utf8) else { continue }
            return t.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
                .map { $0.hasPrefix("~/") ? String($0.dropFirst(2)) : $0 }
        }
        return seen ? nil : []
    }

    /// Menelusuri folder tanpa mengikuti symlink, paling dalam `depth` tingkat. body: true = boleh masuk folder ini.
    /// Hasil false = berhenti di tengah (batas waktu/jumlah atau Batal).
    @discardableResult
    static func walk(_ root: String, depth: Int, scan: CareScan, skipHidden: Bool = true,
                     _ body: (String, String, CareStat, Int) -> Bool) -> Bool {
        var stack: [(String, Int)] = [(root, 1)]
        while let top = stack.popLast() {
            let (dir, d) = top
            guard let names = CareFS.list(dir) else { continue }
            for n in names {
                guard scan.step() else { return false }
                if skipHidden && n.hasPrefix(".") { continue }
                let p = dir + "/" + n
                guard let i = CareFS.info(p), !i.link else { continue }
                let ext = (n as NSString).pathExtension.lowercased()
                let descend = body(p, n, i, d)
                if i.dir && descend && d < depth && !bundleExts.contains(ext) { stack.append((p, d + 1)) }
            }
        }
        return true
    }

    /// Isi identitas (device + inode) dari lstat. nil = tidak ada / symlink / tidak bisa dicek.
    static func stamp(_ it: inout CareItem) -> Bool {
        guard let i = CareFS.info(it.path), !i.link else { return false }
        it.dev = i.dev
        it.ino = i.ino
        return true
    }

    static func fillSizes(_ items: inout [CareItem], scan: CareScan, timeout: Double = 20) {
        let kb = CareSize.du(items.filter { $0.kb < 0 && !$0.path.hasPrefix("task:") }.map { $0.path }, scan: scan, timeout: timeout)
        for i in items.indices { if let k = kb[items[i].path] { items[i].kb = k } }
    }

    // MARK: Bersihkan sekarang

    static func quick(_ scan: CareScan, running: CareRunning, entries: [String]) -> [CareItem] {
        let h = P.home
        var items: [CareItem] = []
        for (sub, group) in [("Library/Caches", "caches"), ("Library/Logs", "logs")] {
            let dir = h + "/" + sub
            guard let names = CareFS.list(dir) else { continue }
            for n in names.sorted() {
                guard scan.step() else { break }
                let p = dir + "/" + n
                guard CareFS.containerOK(p), let i = CareFS.info(p), i.dir, !i.link, !CareFS.linkInPath(p) else { continue }
                var it = CareItem(path: p, name: n, detail: group == "caches" ? T("Cache, made again when needed", "Cache, dibuat lagi saat perlu")
                                                                                 : T("Log files", "File log"),
                                  group: group, act: .emptyInside(0), dev: i.dev, ino: i.ino, keepOK: true)
                if !running.known {
                    it.locked = T("Could not check which apps are open", "Tidak bisa dicek app mana yang terbuka")
                } else if running.uses(n) {
                    it.locked = T("In use by an open app, skipped", "Dipakai app yang terbuka, dilewati")
                } else if CareFS.onKeepList(p, entries) {
                    it.tag = T("On your Keep List", "Ada di Keep List")
                } else {
                    it.pick = true
                }
                items.append(it)
            }
        }
        // tempat sampah Amnesia: sisa pembersihan sebelumnya
        let tr = h + "/.amnesia-trash"
        if let i = CareFS.info(tr), i.dir, !i.link {
            var it = CareItem(path: tr, name: T("Amnesia's trash", "Tempat sampah Amnesia"),
                              detail: T("Leftovers of earlier cleanups, deleted for good", "Sisa pembersihan sebelumnya, dihapus permanen"),
                              group: "atrash", act: .emptyInside(60), dev: i.dev, ino: i.ino)
            if let kids = CareFS.list(tr) {
                if !kids.filter({ $0 != ".metadata_never_index" && $0 != ".DS_Store" }).isEmpty {
                    if now() - i.mtime < 60 {
                        it.locked = T("A cleanup is running right now, try again in a minute",
                                      "Pembersihan sedang berjalan, coba lagi sebentar lagi")
                    } else {
                        it.pick = true
                    }
                    items.append(it)
                }
            } else {
                it.locked = T("Could not check", "Tidak bisa dicek")
                items.append(it)
            }
        }
        // Trash macOS: permanen, tidak pernah dicentang dari awal
        let mt = h + "/.Trash"
        if let i = CareFS.info(mt), i.dir, !i.link {
            var it = CareItem(path: mt, name: T("macOS Trash", "Trash macOS"),
                              detail: T("Emptied for good, this cannot be undone", "Dikosongkan permanen, tidak bisa dibatalkan"),
                              group: "mtrash", act: .emptyInside(0), dev: i.dev, ino: i.ino)
            if let kids = CareFS.list(mt) {
                if !kids.filter({ $0 != ".DS_Store" }).isEmpty { items.append(it) }
            } else {
                it.locked = T("Could not check (Amnesia may need Full Disk Access)",
                              "Tidak bisa dicek (Amnesia mungkin perlu Akses Disk Penuh)")
                items.append(it)
            }
        }
        fillSizes(&items, scan: scan)
        // folder cache kosong tidak perlu ditampilkan
        return items.filter { !($0.group == "caches" || $0.group == "logs") || $0.kb != 0 }
    }

    // MARK: Hapus app

    static func apps(_ scan: CareScan, running: CareRunning) -> [CareApp] {
        var out: [CareApp] = []
        let me = getuid()
        for dir in ["/Applications", P.home + "/Applications"] {
            guard let names = CareFS.list(dir) else { continue }
            let writable = access(dir, W_OK) == 0
            for n in names.sorted() where n.hasSuffix(".app") && !n.hasPrefix(".") {
                guard scan.step() else { break }
                let p = dir + "/" + n
                guard let i = CareFS.info(p), i.dir, !i.link, !CareFS.linkInPath(p), !CareFS.refuse(p) else { continue }
                let plist = NSDictionary(contentsOfFile: p + "/Contents/Info.plist")
                let bid = plist?["CFBundleIdentifier"] as? String ?? ""
                let name = String(n.dropLast(4))
                if bid.hasPrefix("com.apple.") || bid.hasPrefix("com.amnesia") || name == "Amnesia" || name == "Amnesia Shots" { continue }
                var a = CareApp(path: p, name: name, bid: bid, dev: i.dev, ino: i.ino)
                if bid.isEmpty {
                    a.locked = T("Could not check", "Tidak bisa dicek")
                } else if i.uid != me || !writable {
                    a.locked = T("Installed with an admin password, use Finder", "Dipasang dengan password admin, pakai Finder")
                } else if running.runs(bid: bid, path: p) {
                    a.locked = T("Quit it first", "Tutup dulu app-nya")
                }
                out.append(a)
            }
        }
        let kb = CareSize.du(out.map { $0.path }, scan: scan, timeout: 20)
        for i in out.indices { out[i].kb = kb[out[i].path] ?? -1 }
        return out.sorted { $0.kb > $1.kb }
    }

    /// App + sisa datanya (hanya bundle id yang sama persis atau nama app yang sama persis).
    static func leftovers(_ app: CareApp, scan: CareScan, entries: [String]) -> [CareItem] {
        let h = P.home
        let lib = h + "/Library/"
        var items: [CareItem] = []
        var app1 = CareItem(path: app.path, name: app.name, detail: T("The app", "App-nya"), kb: app.kb, group: "app",
                            pick: true, act: .trash, dev: app.dev, ino: app.ino)
        if CareFS.onKeepList(app.path, entries) || entries.contains("app:" + app.path) {
            app1.locked = T("On your Keep List", "Ada di Keep List")
            app1.pick = false
        }
        items.append(app1)
        guard !app.bid.isEmpty else { return items }
        let groups = CareFS.list(lib + "Group Containers") ?? []
        var rels: [String] = []
        for r in appDataPaths(bid: app.bid, names: [app.name], groups: groups) {
            if r.hasSuffix("*") {
                // Library/Preferences/<bid>* -> file yang namanya diawali bundle id
                let base = h + "/" + String(r.dropLast())
                let dir = (base as NSString).deletingLastPathComponent
                let pre = (base as NSString).lastPathComponent
                // v5.24: hanya bundle id yang sama persis ("com.app.plist", "com.app.helper.plist"), bukan "com.appx"
                for n in (CareFS.list(dir) ?? []).sorted() where n == pre || n.hasPrefix(pre + ".") {
                    rels.append(String(dir.dropFirst(h.count + 1)) + "/" + n)
                }
            } else {
                rels.append(r)
            }
        }
        rels += ["Library/Caches/" + app.bid, "Library/Logs/" + app.name, "Library/Logs/" + app.bid,
                 "Library/Saved Application State/\(app.bid).savedState", "Library/HTTPStorages/" + app.bid]
        for n in (CareFS.list(lib + "LaunchAgents") ?? []).sorted() where n.hasPrefix(app.bid + ".") && n.hasSuffix(".plist") {
            rels.append("Library/LaunchAgents/" + n)
        }
        var seen = Set<String>()
        for r in rels where seen.insert(r).inserted {
            guard scan.step() else { break }
            let p = h + "/" + r
            guard CareFS.info(p) != nil else { continue }
            let quick = ["Library/Caches/", "Library/Logs/", "Library/Saved Application State/", "Library/HTTPStorages/",
                         "Library/LaunchAgents/"].contains { r.hasPrefix($0) }
            var it = CareItem(path: p, name: (r as NSString).lastPathComponent, detail: leftoverKind(r),
                              group: quick ? "leftcache" : "leftdata", act: .trash)
            if !stamp(&it) || CareFS.linkInPath(p) {
                it.locked = T("A link, skipped", "Berupa link, dilewati")
            } else if CareFS.refuse(p) {
                continue
            } else if CareFS.onKeepList(p, entries) {
                it.locked = T("On your Keep List", "Ada di Keep List")
            } else {
                it.pick = quick
            }
            items.append(it)
        }
        fillSizes(&items, scan: scan)
        return items
    }

    static func leftoverKind(_ r: String) -> String {
        if r.hasPrefix("Library/Caches/") { return T("Cache", "Cache") }
        if r.hasPrefix("Library/Logs/") { return T("Logs", "Log") }
        if r.hasPrefix("Library/Saved Application State/") { return T("Saved window state", "Posisi jendela tersimpan") }
        if r.hasPrefix("Library/HTTPStorages/") { return T("Web cookies of the app", "Cookie web app ini") }
        if r.hasPrefix("Library/LaunchAgents/") { return T("Starts a helper at login", "Menjalankan pembantu saat login") }
        return pathKind(r).label + T(", your own data", ", data milik kamu")
    }

    // MARK: Folder build project

    static func gitBinary() -> String? {
        let fm = FileManager.default
        for g in ["/opt/homebrew/bin/git", "/usr/local/bin/git"] where fm.isExecutableFile(atPath: g) { return g }
        // /usr/bin/git tanpa Command Line Tools membuka jendela pemasangan, jadi dicek dulu
        if fm.isExecutableFile(atPath: "/usr/bin/git") && sh("/usr/bin/xcode-select", ["-p"], timeout: 5).code == 0 {
            return "/usr/bin/git"
        }
        return nil
    }

    /// Folder terdekat (dari `dir` ke atas) yang punya .git.
    static func repoRoot(_ dir: String) -> String? {
        var cur = dir
        while cur.count > 1 {
            if CareFS.info(cur + "/.git") != nil { return cur }
            cur = (cur as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// Isi 1 folder build: ukuran, file terbaru, ada .git / kunci di dalamnya, dan apakah selesai dicek.
    static func inspect(_ dir: String, scan: CareScan) -> (kb: Int64, newest: Double, git: Bool, secret: Bool, complete: Bool) {
        var blocks: Int64 = 0
        var newest = CareFS.info(dir)?.mtime ?? now()
        var git = false, secret = false
        let complete = walk(dir, depth: 64, scan: scan, skipHidden: false) { _, n, i, _ in
            blocks += i.blocks
            newest = max(newest, i.mtime)
            let l = n.lowercased()
            if n == ".git" { git = true }
            if l.hasSuffix(".pem") || l.hasSuffix(".p12") || l.hasSuffix(".key") || l.hasSuffix(".keystore") || l.hasPrefix("id_rsa") {
                secret = true
            }
            return n != ".git"
        }
        return (blocks * 512 / 1024, newest, git, secret, complete)
    }

    static func projects(_ scan: CareScan, entries: [String]) -> [CareItem] {
        let h = P.home
        var roots = [KeepDir.path]
        roots += ["Developer", "Projects", "Code", "dev", "src", "work", "GitHub", "Documents", "Desktop"].map { h + "/" + $0 }
        // 1. cari folder build
        var found: [(path: String, parent: String)] = []
        var visited = Set<String>()
        var queue: [(String, Int)] = []
        for r in roots {
            guard let i = CareFS.info(r), i.dir, !i.link else { continue }
            if r.hasPrefix(h + "/") && CareFS.linkInPath(r) { continue }
            queue.append((r, 0))
        }
        var qi = 0
        while qi < queue.count {
            guard scan.alive() else { break }
            let (dir, depth) = queue[qi]
            qi += 1
            guard visited.insert(dir).inserted, let names = CareFS.list(dir) else { continue }
            if names.contains(where: { $0.hasSuffix(".vmx") || $0.hasSuffix(".vbox") }) { continue }   // folder VM: jangan disentuh
            let here = Set(names)
            for n in names.sorted() {
                guard scan.step() else { break }
                let p = dir + "/" + n
                if let markers = buildTargets[n] {
                    if markers.isEmpty || markers.contains(where: { here.contains($0) }) {
                        if let i = CareFS.info(p), i.dir, !i.link { found.append((path: p, parent: dir)) }
                        continue                    // tidak masuk ke dalam folder build
                    }
                    if n == "node_modules" { continue }
                }
                if n.hasPrefix(".") || n == "Library" || depth + 1 > 5 { continue }
                let ext = (n as NSString).pathExtension.lowercased()
                if bundleExts.contains(ext) || vmExts.contains(ext) { continue }
                guard let i = CareFS.info(p), i.dir, !i.link else { continue }
                queue.append((p, depth + 1))
            }
        }
        // 2. cek tiap folder build
        let git = gitBinary()
        var items: [CareItem] = []
        var seen = Set<String>()
        for f in found where seen.insert(f.path).inserted {
            let name = (f.path as NSString).lastPathComponent
            var it = CareItem(path: f.path, name: (f.parent as NSString).lastPathComponent + "/" + name, detail: "",
                              group: "p:" + f.parent, act: .trash)
            if !stamp(&it) || CareFS.linkInPath(f.path) || CareFS.refuse(f.path) { continue }
            if CareFS.onKeepList(f.path, entries) {
                it.locked = T("On your Keep List", "Ada di Keep List")
                items.append(it)
                continue
            }
            guard scan.alive() else {
                it.locked = T("Could not check (scan stopped)", "Tidak bisa dicek (pemindaian berhenti)")
                items.append(it)
                continue
            }
            if let repo = repoRoot(f.parent) {
                guard let g = git else {
                    it.locked = T("Inside a git project, could not check (git is not installed)",
                                  "Di dalam project git, tidak bisa dicek (git belum terpasang)")
                    items.append(it)
                    continue
                }
                let rel = repo == "/" ? f.path : String(f.path.dropFirst(repo.count + 1))
                let r = sh(g, ["-C", repo, "ls-files", "-z", "--", rel], timeout: 5, onStart: { p in scan.running(p) })
                if r.code != 0 {
                    it.locked = T("Could not check with git", "Tidak bisa dicek dengan git")
                    items.append(it)
                    continue
                }
                if !r.out.isEmpty {
                    it.locked = T("Tracked by git, left alone", "Dilacak git, tidak disentuh")
                    items.append(it)
                    continue
                }
            }
            let x = inspect(f.path, scan: scan)
            it.kb = x.kb
            if !x.complete {
                it.locked = T("Could not check (too big or scan stopped)", "Tidak bisa dicek (terlalu besar atau pemindaian berhenti)")
            } else if x.git {
                it.locked = T("Has a .git folder inside, left alone", "Ada folder .git di dalamnya, tidak disentuh")
            } else if x.secret {
                it.locked = T("Has key or certificate files inside, left alone", "Ada file kunci atau sertifikat di dalamnya, tidak disentuh")
            } else {
                let days = Int((now() - x.newest) / day)
                if days >= 7 {
                    it.pick = true
                    it.detail = T("Not changed for \(days) days, made again by your build tool", "Tidak berubah \(days) hari, dibuat lagi oleh alat build")
                } else {
                    it.detail = T("Used in the last 7 days", "Dipakai dalam 7 hari terakhir")
                }
            }
            items.append(it)
        }
        return items.sorted { $0.group == $1.group ? $0.name < $1.name : $0.group < $1.group }
    }

    // MARK: Installer lama

    /// Image disk yang sedang terbuka (hdiutil info). nil = tidak bisa dicek.
    static func mountedImages() -> Set<String>? {
        let r = sh("/usr/bin/hdiutil", ["info", "-plist"], timeout: 10)
        guard r.code == 0, let d = r.out.data(using: .utf8),
              let pl = (try? PropertyListSerialization.propertyList(from: d, options: [], format: nil)) as? [String: Any]
        else { return nil }
        let imgs = pl["images"] as? [[String: Any]] ?? []
        return Set(imgs.compactMap { $0["image-path"] as? String })
    }

    static func installers(_ scan: CareScan, entries: [String]) -> [CareItem] {
        let h = P.home
        let mounted = mountedImages()
        let roots: [(String, String)] = [(h + "/Downloads", "i:downloads"), (h + "/Desktop", "i:desktop"), (KeepDir.path, "i:keep")]
        var items: [CareItem] = []
        var seen = Set<String>()
        for (root, group) in roots {
            guard let ri = CareFS.info(root), ri.dir, !ri.link else { continue }
            walk(root, depth: 2, scan: scan) { p, n, i, _ in
                let ext = (n as NSString).pathExtension.lowercased()
                let low = n.lowercased()
                // tidak pernah: disk terenkripsi, Brankas, mesin virtual (dan folder yang berisi VM)
                if ext == "sparsebundle" || ext == "sparseimage" || n.hasPrefix("Brankas.") || vmExts.contains(ext) { return false }
                if i.dir, let kids = CareFS.list(p), kids.contains(where: { $0.hasSuffix(".vmx") || $0.hasSuffix(".vbox") }) { return false }
                let main = ["dmg", "pkg", "mpkg", "xip"].contains(ext)
                let zip = ext == "zip" && (low.contains("install") || low.contains("setup"))
                let disk = ext == "iso" || ext == "img"
                guard main || zip || disk else { return true }
                if i.dir && !(ext == "pkg" || ext == "mpkg") { return true }
                guard seen.insert(p).inserted else { return false }
                let days = Int((now() - max(i.mtime, i.birth)) / day)
                var it = CareItem(path: p, name: n, detail: "", group: group, act: .trash, dev: i.dev, ino: i.ino)
                if CareFS.linkInPath(p) || CareFS.refuse(p) { return false }
                if CareFS.onKeepList(p, entries) {
                    it.locked = T("On your Keep List", "Ada di Keep List")
                } else if (ext == "dmg" || disk) && mounted == nil {
                    it.locked = T("Could not check if it is open", "Tidak bisa dicek apakah sedang terbuka")
                } else if ext == "dmg" || disk, let m = mounted,
                          m.contains(p) || m.contains((p as NSString).resolvingSymlinksInPath) {
                    it.locked = T("Open right now, eject it first", "Sedang terbuka, keluarkan (eject) dulu")
                } else if main {
                    it.pick = days >= 14
                    it.detail = days >= 14 ? T("Installer, \(days) days old", "Installer, umur \(days) hari")
                                           : T("Installer from the last 14 days", "Installer dari 14 hari terakhir")
                } else if zip {
                    it.detail = T("Zip that looks like an installer, check it first", "Zip yang mirip installer, cek dulu")
                } else {
                    it.detail = T("Disk image, check it first", "Image disk, cek dulu")
                }
                items.append(it)
                return false
            }
        }
        fillSizes(&items, scan: scan)
        return items
    }

    // MARK: Perawatan ringan

    static func tune() -> [CareItem] {
        [CareItem(path: "task:ql", name: T("Refresh Quick Look thumbnails", "Segarkan thumbnail Quick Look"),
                  detail: T("Fixes old or wrong previews in Finder", "Memperbaiki pratinjau lama atau salah di Finder"),
                  kb: 0, group: "tune", pick: true, act: .task("ql")),
         CareItem(path: "task:dock", name: T("Restart the Dock", "Mulai ulang Dock"),
                  detail: T("Helps when the Dock or Mission Control acts up. It disappears for a second.",
                            "Membantu kalau Dock atau Mission Control bermasalah. Dock hilang sebentar."),
                  kb: 0, group: "tune", act: .task("dock"))]
    }

    // MARK: Ringkasan disk

    static func overview(_ scan: CareScan) -> CareOverview {
        var o = CareOverview()
        let h = P.home
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        if let v = try? URL(fileURLWithPath: h).resourceValues(forKeys: keys) {
            if let t = v.volumeTotalCapacity { o.total = Int64(t) }
            if let f = v.volumeAvailableCapacityForImportantUsage { o.free = f }
        }
        let keep = KeepDir.path
        let spots: [(String, String)] = [
            (T("Keep folder", "Folder Keep"), keep), ("Profile Vault", P.a + "/vault"),
            (T("Amnesia's trash", "Tempat sampah Amnesia"), h + "/.amnesia-trash"), (T("macOS Trash", "Trash macOS"), h + "/.Trash"),
            (T("App caches", "Cache app"), h + "/Library/Caches"), ("Downloads", h + "/Downloads"),
        ]
        let have = spots.filter { s in CareFS.info(s.1).map { $0.dir && !$0.link } ?? false }
        let kb = CareSize.du(have.map { $0.1 }, scan: scan, timeout: 15)
        o.spots = have.map { CareSpot(name: $0.0, path: $0.1, kb: kb[$0.1] ?? -1) }
        // file besar (200 MB ke atas) dan unduhan lama
        let big: Int64 = 200 * 1024 * 1024
        var files: [CareSpot] = []
        var seen = Set<String>()
        for root in [keep, h + "/Downloads", h + "/Desktop"] {
            guard let ri = CareFS.info(root), ri.dir, !ri.link else { continue }
            let dl = root == h + "/Downloads"
            walk(root, depth: 4, scan: scan) { p, n, i, _ in
                if i.dir { return true }
                let bytes = i.blocks * 512
                if bytes >= big && seen.insert(p).inserted { files.append(CareSpot(name: n, path: p, kb: bytes / 1024)) }
                if dl && now() - i.mtime >= 30 * day { o.oldCount += 1; o.oldKB += bytes / 1024 }
                return true
            }
        }
        o.files = Array(files.sorted { $0.kb > $1.kb }.prefix(10))
        // folder terbesar: tingkat pertama di home dan di folder Keep
        var dirs: [String] = []
        for base in [h, keep] {
            for n in (CareFS.list(base) ?? []).sorted() {
                let p = base + "/" + n
                guard let i = CareFS.info(p), i.dir, !i.link, !dirs.contains(p), p != keep || base == keep else { continue }
                dirs.append(p)
            }
        }
        let dk = CareSize.du(dirs, scan: scan, timeout: 25)
        o.folders = Array(dirs.compactMap { p in dk[p].map { CareSpot(name: CareFS.shown(p), path: p, kb: $0) } }
            .sorted { $0.kb > $1.kb }.prefix(10))
        o.cut = scan.cut || dk.count < dirs.count
        return o
    }

    // MARK: Mengerjakan (setelah konfirmasi)

    /// Tepat sebelum dihapus: masih item yang sama (device + inode), bukan link, dan masih lolos semua aturan.
    static func allowed(_ it: CareItem, _ entries: [String]) -> Bool {
        guard let i = CareFS.info(it.path), !i.link, i.dev == it.dev, i.ino == it.ino, !CareFS.linkInPath(it.path) else { return false }
        switch it.act {
        case .trash: return !CareFS.refuse(it.path) && !CareFS.onKeepList(it.path, entries)
        case .emptyInside: return CareFS.containerOK(it.path) && (it.keepOK || !CareFS.onKeepList(it.path, entries))
        case .task: return false
        }
    }

    static func act(_ feature: CareFeature, _ items: [CareItem], running: CareRunning) -> CareResult {
        var r = CareResult()
        if Shots.mandul { return r }          // salinan screenshot tidak pernah menghapus apa pun
        let fm = FileManager.default
        let keep = keepEntries()          // nil = Keep List tidak bisa dibaca: tidak ada yang dihapus
        let entries = keep ?? []
        let h = P.home
        for it in items {
            switch it.act {
            case .task(let t):
                let ok: Bool
                switch t {
                case "ql": ok = sh("/usr/bin/qlmanage", ["-r", "cache"], timeout: 20).code == 0
                case "dock": ok = sh("/usr/bin/killall", ["Dock"], timeout: 10).code == 0
                default: ok = false
                }
                r.add("t:" + it.name, ok: ok, kb: 0, trash: false)
            case .trash:
                guard keep != nil, allowed(it, entries),
                      !(it.path.hasSuffix(".app") && running.paths.contains(it.path)) else {
                    r.changed += 1
                    r.add(it.group, ok: false, kb: 0, trash: true)
                    continue
                }
                do {
                    try fm.trashItem(at: URL(fileURLWithPath: it.path), resultingItemURL: nil)
                    r.add(it.group, ok: true, kb: max(0, it.kb), trash: true)
                } catch {
                    r.add(it.group, ok: false, kb: 0, trash: true)
                }
            case .emptyInside(let minAge):
                let cache = it.group == "caches" || it.group == "logs"
                guard keep != nil, allowed(it, entries), !(cache && running.uses(it.name)) else {
                    r.changed += 1
                    r.add(it.group, ok: false, kb: 0, trash: false)
                    continue
                }
                guard let kids = CareFS.list(it.path) else {
                    r.add(it.group, ok: false, kb: 0, trash: false)
                    continue
                }
                // item Keep List yang ada DI DALAM folder ini tetap disimpan (kecuali folder ini sendiri dicentang di Keep List)
                let selfKept = CareFS.rel(it.path).map { keepMatches($0, entries) } ?? false
                var bad = 0
                for k in kids {
                    if it.path == h + "/.amnesia-trash" && k == ".metadata_never_index" { continue }
                    let p = it.path + "/" + k
                    guard let ki = CareFS.info(p) else { continue }
                    if minAge > 0 && now() - ki.mtime < minAge { continue }
                    if !selfKept && CareFS.onKeepList(p, entries) { continue }
                    do { try fm.removeItem(atPath: p) } catch { bad += 1 }      // removeItem tidak mengikuti symlink
                }
                let left = CareSize.du([it.path], scan: nil, timeout: 20)[it.path]
                let freed = (it.kb >= 0 && left != nil) ? max(0, it.kb - (left ?? 0)) : 0
                r.add(it.group, ok: bad == 0, kb: freed, trash: false)
            }
        }
        log(feature, r)
        return r
    }

    /// Riwayat + trace (hanya jumlah, tidak pernah nama file).
    static func log(_ f: CareFeature, _ r: CareResult) {
        trace("care \(f.rawValue): \(r.done) done, \(r.failed) failed, \(r.changed) changed since scan")
        let line = "\(History.stamp())\tcare\t\(f.rawValue) \(r.done) \(f == .tune ? 0 : r.kb + r.trashKB) \(r.failed)\n"
        if let hd = FileHandle(forWritingAtPath: History.path) {
            hd.seekToEndOfFile()
            hd.write(Data(line.utf8))
            try? hd.close()
        } else {
            try? line.write(toFile: History.path, atomically: true, encoding: .utf8)
        }
    }
}

/// v5.24: baris Cek kesehatan: sisa ruang disk, memori, kondisi baterai. Tidak bisa dicek = info.
enum CareHealth {
    static func rows() -> [HealthRow] {
        var rows: [HealthRow] = []
        let cant = T("Couldn't check.", "Tidak bisa dicek.")
        // ruang disk
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        if let v = try? URL(fileURLWithPath: P.home).resourceValues(forKeys: keys),
           let total = v.volumeTotalCapacity, total > 0, let free = v.volumeAvailableCapacityForImportantUsage {
            let pct = Double(free) / Double(total) * 100
            let low = pct < 10 || free < 15_000_000_000
            rows.append(HealthRow(level: low ? .warn : .ok, title: T("Free disk space", "Sisa ruang disk"),
                                  detail: T("\(bytesText(free)) free of \(bytesText(Int64(total))) (\(Int(pct))%).",
                                            "\(bytesText(free)) kosong dari \(bytesText(Int64(total))) (\(Int(pct))%).")
                                      + (low ? T(" Getting full. Care on the home page can help.",
                                                 " Hampir penuh. Perawatan di halaman utama bisa membantu.") : "")))
        } else {
            rows.append(HealthRow(level: .info, title: T("Free disk space", "Sisa ruang disk"), detail: cant))
        }
        // memori
        let mem = sh("/usr/bin/memory_pressure", ["-Q"], timeout: 10)
        if mem.code == 0, let r = mem.out.range(of: "free percentage:"),
           let pct = Int(mem.out[r.upperBound...].trimmingCharacters(in: .whitespaces).prefix { $0.isNumber }) {
            rows.append(HealthRow(level: pct < 15 ? .warn : .ok, title: T("Memory", "Memori"),
                                  detail: T("\(pct)% free.", "\(pct)% kosong.")
                                      + (pct < 15 ? T(" Quitting apps you don't use frees some.",
                                                      " Menutup app yang tidak dipakai akan mengosongkannya.") : "")))
        } else {
            rows.append(HealthRow(level: .info, title: T("Memory", "Memori"), detail: cant))
        }
        // baterai (hanya kalau ada)
        let bat = sh("/usr/sbin/system_profiler", ["SPPowerDataType"], timeout: 15)
        if bat.code != 0 || bat.out.isEmpty {
            rows.append(HealthRow(level: .info, title: T("Battery", "Baterai"), detail: cant))
        } else if bat.out.contains("Battery Information") {
            func field(_ k: String) -> String? {
                for l in bat.out.split(separator: "\n") {
                    let t = l.trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix(k + ":") { return t.dropFirst(k.count + 1).trimmingCharacters(in: .whitespaces) }
                }
                return nil
            }
            if let cond = field("Condition") {
                let cycles = field("Cycle Count").map { T(", \($0) charge cycles", ", \($0) siklus pengisian") } ?? ""
                let normal = cond == "Normal"
                rows.append(HealthRow(level: normal ? .info : .warn, title: T("Battery", "Baterai"),
                                      detail: T("Condition: \(cond)\(cycles).", "Kondisi: \(cond)\(cycles).")
                                          + (normal ? "" : T(" Check System Settings → Battery.", " Cek Pengaturan Sistem → Baterai."))))
            } else {
                rows.append(HealthRow(level: .info, title: T("Battery", "Baterai"), detail: cant))
            }
        }
        return rows
    }
}

// MARK: - Bagian 2: tampilan (SwiftUI + AppKit)

extension CareRunning {
    @MainActor static func now() -> CareRunning {
        let apps = NSWorkspace.shared.runningApplications
        return CareRunning(ids: apps.compactMap { $0.bundleIdentifier },
                           names: Set(apps.compactMap { $0.localizedName?.lowercased() }),
                           paths: Set(apps.compactMap { $0.bundleURL?.path }))
    }
}

extension CareFeature {
    var title: String { careFeatureName(rawValue) }
    var sub: String {
        switch self {
        case .quick: return T("Caches, logs and Amnesia's trash", "Cache, log dan tempat sampah Amnesia")
        case .apps: return T("Apps you installed, and their caches", "App yang kamu pasang, beserta cachenya")
        case .projects: return T("node_modules, target, build and more", "node_modules, target, build dan lainnya")
        case .installers: return T(".dmg and .pkg files you no longer need", "File .dmg dan .pkg yang tidak dipakai lagi")
        case .tune: return T("Small fixes, no admin password", "Perbaikan kecil, tanpa password admin")
        }
    }
    var icon: String {
        switch self {
        case .quick: return "sparkles"
        case .apps: return "app.dashed"
        case .projects: return "hammer.fill"
        case .installers: return "shippingbox.fill"
        case .tune: return "wand.and.stars"
        }
    }
    var colors: [Color] {
        switch self {
        case .quick: return Pal.logout
        case .apps: return Pal.backup
        case .projects: return Pal.preview
        case .installers: return Pal.vault
        case .tune: return Pal.keep
        }
    }
    /// Penjelasan jujur di atas daftar.
    var note: String {
        switch self {
        case .quick:
            return T("Apps make caches and logs again when they need them. Caches of apps that are open now are skipped. "
                     + "Amnesia already empties these at every logout, so this helps most during a long session.",
                     "App membuat cache dan log lagi saat perlu. Cache app yang sedang terbuka dilewati. "
                     + "Amnesia sudah mengosongkannya setiap logout, jadi ini paling berguna saat sesi panjang.")
        case .apps:
            return T("Only apps you installed yourself. The app and its caches go to the Trash, so you can put them back. "
                     + "Its personal data (settings, saved files) stays unless you tick it.",
                     "Hanya app yang kamu pasang sendiri. App dan cachenya dipindah ke Trash, jadi bisa dikembalikan. "
                     + "Data pribadinya (pengaturan, file tersimpan) tetap ada kecuali kamu centang.")
        case .projects:
            return T("Folders your build tools make again with one command (npm install, cargo build and so on). "
                     + "Folders used in the last 7 days, tracked by git or holding keys are not picked for you. "
                     + "Everything goes to the Trash.",
                     "Folder yang dibuat lagi oleh alat build dengan 1 perintah (npm install, cargo build dan lainnya). "
                     + "Folder yang dipakai 7 hari terakhir, dilacak git, atau berisi kunci tidak dipilihkan. "
                     + "Semuanya dipindah ke Trash.")
        case .installers:
            return T("Installers in Downloads, Desktop and your Keep folder. Ones older than 14 days that are not open are picked. "
                     + "Disk images and virtual machines are never picked for you. Everything goes to the Trash.",
                     "Installer di Downloads, Desktop dan folder Keep. Yang lebih dari 14 hari dan tidak sedang terbuka dipilih. "
                     + "Image disk dan mesin virtual tidak pernah dipilihkan. Semuanya dipindah ke Trash.")
        case .tune:
            return T("Small fixes that need no admin password. Nothing is deleted.",
                     "Perbaikan kecil tanpa password admin. Tidak ada yang dihapus.")
        }
    }
    var actionTitle: String {
        switch self {
        case .quick: return T("Clean Up…", "Bersihkan…")
        case .tune: return T("Run…", "Jalankan…")
        default: return T("Move to Trash…", "Pindahkan ke Trash…")
        }
    }
}

/// v5.24: nama kelompok di daftar dan di hasil.
func careGroupTitle(_ g: String) -> String {
    switch g {
    case "caches": return T("App caches", "Cache app")
    case "logs": return T("Logs", "Log")
    case "atrash": return T("Amnesia's trash", "Tempat sampah Amnesia")
    case "mtrash": return T("macOS Trash", "Trash macOS")
    case "app": return T("App", "App")
    case "leftcache": return T("Caches, logs and helpers", "Cache, log dan pembantu")
    case "leftdata": return T("Personal data (not picked for you)", "Data pribadi (tidak dipilihkan)")
    case "tune": return T("Tasks", "Tugas")
    case "i:downloads": return "Downloads"
    case "i:desktop": return "Desktop"
    case "i:keep": return T("Keep folder", "Folder Keep")
    default:
        if g.hasPrefix("p:") { return CareFS.shown(String(g.dropFirst(2))) }
        if g.hasPrefix("t:") { return String(g.dropFirst(2)) }
        return g
    }
}

func careSize(_ kb: Int64) -> String { kb < 0 ? "?" : bytesText(kb * 1024) }

@MainActor
func careReveal(_ p: String) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }

/// v5.24: halaman Perawatan: daftar fitur.
struct CareView: View {
    let back: () -> Void
    @State private var feature: CareFeature?
    @State private var overview = false

    var body: some View {
        if overview {
            CareOverviewView(back: { overview = false })
        } else if let f = feature {
            CareRunView(feature: f, back: { feature = nil }).id(f)
        } else {
            menu
        }
    }

    private var menu: some View {
        VStack(spacing: 14) {
            PageHeader(title: T("Care", "Perawatan"), icon: "wrench.and.screwdriver.fill", colors: Pal.keep, back: back)
            RoomyScroll {
                VStack(spacing: 10) {
                    Text(T("Amnesia already wipes most of your home folder at every logout. Care helps with what stays: your "
                           + "Keep folder, the apps you kept, and big files from this session. You always see a list first, "
                           + "and nothing is removed until you confirm.",
                           "Amnesia sudah membersihkan sebagian besar folder home setiap logout. Perawatan membantu untuk yang "
                           + "tetap ada: folder Keep, app yang kamu simpan, dan file besar dari sesi ini. Kamu selalu melihat "
                           + "daftarnya dulu, dan tidak ada yang dihapus sebelum kamu setuju."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    row("chart.pie.fill", Pal.gray, T("Disk overview", "Ringkasan disk"),
                        T("What takes space. Read only.", "Apa yang memakan ruang. Hanya dibaca.")) { overview = true }
                    ForEach(CareFeature.allCases, id: \.self) { f in
                        row(f.icon, f.colors, f.title, f.sub) { feature = f }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    private func row(_ icon: String, _ colors: [Color], _ title: String, _ sub: String,
                     _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                IconBadge(icon: icon, colors: colors, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text(sub).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(12)
            .surface(18, fill: Th.tile)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)      // v5.25 (198)
        }
        .buttonStyle(.plain)
    }
}

/// v5.24: 1 fitur: pindai -> daftar -> konfirmasi -> kerjakan -> hasil.
struct CareRunView: View {
    @EnvironmentObject var m: Model
    let feature: CareFeature
    let back: () -> Void

    enum Phase { case scanning, apps, preview, acting, done }
    @State private var phase: Phase = .scanning
    @State private var scan: CareScan?
    @State private var cut = false
    @State private var items: [CareItem] = []
    @State private var picked: Set<String> = []
    @State private var apps: [CareApp] = []
    @State private var chosen: CareApp?
    @State private var result: CareResult?
    @State private var keepBad = false     // Keep List tidak bisa dibaca: tidak ada yang ditampilkan untuk dihapus

    var body: some View {
        VStack(spacing: 14) {
            PageHeader(title: feature.title, icon: feature.icon, colors: feature.colors, back: { leave() })
            Text(feature.note).font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            switch phase {
            case .scanning: waiting(T("Looking…", "Mencari…"), cancel: true)
            case .acting: waiting(T("Working…", "Sedang dikerjakan…"), cancel: false)
            case .apps: appList
            case .preview: preview
            case .done: done
            }
        }
        .onAppear { if phase == .scanning && scan == nil { start() } }
        .onDisappear { scan?.cancel() }
    }

    // MARK: alur

    private func start() {
        phase = .scanning
        cut = false
        let s = CareScan()
        scan = s
        let running = CareRunning.now()
        let f = feature
        // v5.24: Keep List tidak bisa dibaca = tidak tahu apa yang kamu simpan = tidak ada yang ditawarkan untuk dihapus
        let keep = CareScanner.keepEntries()
        keepBad = keep == nil && f != .tune
        if keepBad {
            show([], cut: false)
            return
        }
        let entries = keep ?? []
        if f == .apps {
            m.quiet({ CareScanner.apps(s, running: running) }) { r in
                guard scan === s, !s.cancelled else { return }
                apps = r
                cut = s.cut
                phase = .apps
            }
            return
        }
        m.quiet({ () -> [CareItem] in
            switch f {
            case .quick: return CareScanner.quick(s, running: running, entries: entries)
            case .projects: return CareScanner.projects(s, entries: entries)
            case .installers: return CareScanner.installers(s, entries: entries)
            case .tune: return CareScanner.tune()
            case .apps: return []
            }
        }) { r in
            guard scan === s, !s.cancelled else { return }
            show(r, cut: s.cut)
        }
    }

    private func choose(_ a: CareApp) {
        chosen = a
        phase = .scanning
        let s = CareScan()
        scan = s
        guard let entries = CareScanner.keepEntries() else {
            keepBad = true
            show([], cut: false)
            return
        }
        m.quiet({ CareScanner.leftovers(a, scan: s, entries: entries) }) { r in
            guard scan === s, !s.cancelled else { return }
            show(r, cut: s.cut)
        }
    }

    private func show(_ r: [CareItem], cut c: Bool) {
        items = r
        picked = Set(r.filter { $0.pick && $0.locked == nil }.map { $0.id })
        cut = c
        phase = .preview
    }

    private func cancelScan() {
        scan?.cancel()
        scan = nil
        if feature == .apps && chosen != nil {
            chosen = nil
            phase = apps.isEmpty ? .scanning : .apps
            if apps.isEmpty { start() }
        } else {
            back()
        }
    }

    private func leave() {
        if phase == .acting { return }               // jangan ditinggal di tengah pekerjaan
        if phase == .preview && feature == .apps && chosen != nil {
            chosen = nil
            phase = .apps
            return
        }
        scan?.cancel()
        back()
    }

    private var selected: [CareItem] { items.filter { picked.contains($0.id) && $0.locked == nil } }

    private func run() {
        let sel = selected
        guard !sel.isEmpty else { return }
        let kb = sel.reduce(Int64(0)) { $0 + max(0, $1.kb) }
        let toTrash = sel.filter { $0.act == .trash }.count
        let emptied = sel.filter { if case .emptyInside = $0.act { return true } else { return false } }.count
        let tasks = sel.filter { if case .task = $0.act { return true } else { return false } }.count
        let permanent = sel.contains { $0.group == "mtrash" || $0.group == "atrash" }
        var text: [String] = []
        if tasks > 0 {
            text.append(T("\(tasks) task(s) run now. Nothing is deleted.", "\(tasks) tugas dijalankan sekarang. Tidak ada yang dihapus."))
        } else {
            text.append(T("\(sel.count) items, \(bytesText(kb * 1024)).", "\(sel.count) item, \(bytesText(kb * 1024))."))
        }
        if toTrash > 0 {
            text.append(T("\(toTrash) go to the Trash, so you can put them back from there.",
                          "\(toTrash) dipindah ke Trash, jadi bisa dikembalikan dari sana."))
        }
        if emptied > 0 {
            text.append(T("\(emptied) are emptied right away.", "\(emptied) langsung dikosongkan."))
        }
        if permanent {
            text.append(T("Emptying a trash cannot be undone.", "Mengosongkan tempat sampah tidak bisa dibatalkan."))
        }
        // v5.24: jujur kalau ada yang di dalam folder Keep (installer, folder build)
        let keepRoot = KeepDir.path
        let inKeep = sel.filter { $0.path.hasPrefix(keepRoot + "/") }.count
        if inKeep > 0 {
            text.append(T("\(inKeep) of them are inside your Keep folder. The Keep List and the Profile Vault are not touched.",
                          "\(inKeep) di antaranya ada di dalam folder Keep. Keep List dan Profile Vault tidak disentuh."))
        } else {
            text.append(T("Your Keep folder, the Keep List and the Profile Vault are not touched.",
                          "Folder Keep, Keep List dan Profile Vault tidak disentuh."))
        }
        guard confirm(feature.title, text.joined(separator: "\n\n"), ok: feature.actionTitle.replacingOccurrences(of: "…", with: ""),
                      danger: permanent) else { return }
        phase = .acting
        let running = CareRunning.now()
        let f = feature
        m.quiet({ CareScanner.act(f, sel, running: running) }) { r in
            result = r
            phase = .done
        }
    }

    // MARK: tampilan

    private func waiting(_ text: String, cancel: Bool) -> some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView().controlSize(.large)
            Text(text).font(.system(size: 13, weight: .semibold))
            if cancel {
                Button { cancelScan() } label: { Label(T("Cancel", "Batal"), systemImage: "xmark.circle.fill") }
                    .buttonStyle(Pill(colors: Pal.gray)).frame(maxWidth: 200)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var cutNote: some View {
        Note(text: T("The search stopped after 30 seconds or a lot of files, so this list may not be complete.",
                     "Pencarian berhenti setelah 30 detik atau terlalu banyak file, jadi daftar ini mungkin belum lengkap."),
             icon: "clock.badge.exclamationmark", color: Th.orange)
    }

    private var appList: some View {
        VStack(spacing: 10) {
            if cut { cutNote }
            RoomyScroll {
                LazyVStack(spacing: 6) {
                    if apps.isEmpty {
                        Note(text: T("No apps found that you can remove here.", "Tidak ada app yang bisa dihapus di sini."))
                    }
                    ForEach(apps) { a in
                        Button { choose(a) } label: {
                            HStack(spacing: 10) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: a.path)).resizable().frame(width: 26, height: 26)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(a.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    Text(a.locked ?? CareFS.shown(a.path)).font(.system(size: 10))
                                        .foregroundStyle(a.locked != nil ? Th.orange : .secondary).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer(minLength: 6)
                                Text(careSize(a.kb)).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                                if a.locked == nil { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                            }
                            .padding(10)
                            .surface(12, fill: Th.tile)
                            .opacity(a.locked != nil ? 0.55 : 1)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(a.locked != nil)
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    private var groups: [String] {
        var seen = Set<String>()
        return items.map { $0.group }.filter { seen.insert($0).inserted }
    }

    private var preview: some View {
        let sel = selected
        let kb = sel.reduce(Int64(0)) { $0 + max(0, $1.kb) }
        return VStack(spacing: 10) {
            if cut { cutNote }
            if items.isEmpty {
                Card {
                    if keepBad {
                        Note(text: T("The Keep List could not be read, so Care does not offer anything to remove. "
                                     + "Open Keep List to check it, then look again.",
                                     "Keep List tidak bisa dibaca, jadi Perawatan tidak menawarkan apa pun untuk dihapus. "
                                     + "Buka Keep List untuk mengeceknya, lalu cari lagi."),
                             icon: "exclamationmark.octagon.fill", color: Th.red)
                    } else {
                        Note(text: T("Nothing to clean up here right now.", "Tidak ada yang perlu dibersihkan di sini sekarang."),
                             icon: "checkmark.seal.fill", color: Th.green)
                    }
                }
                Spacer()
            } else {
                RoomyScroll {
                    LazyVStack(spacing: 8) {
                        ForEach(groups, id: \.self) { g in group(g) }
                        if feature == .tune {
                            Button {
                                if let u = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                                    NSWorkspace.shared.open(u)
                                }
                            } label: {
                                Label(T("Open Login Items", "Buka Item Login"), systemImage: "arrow.up.forward.app")
                            }
                            .buttonStyle(Pill(colors: Pal.gray))
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            HStack {
                Text(feature == .tune ? T("\(sel.count) picked", "\(sel.count) dipilih")
                                      : T("\(sel.count) picked, \(bytesText(kb * 1024))", "\(sel.count) dipilih, \(bytesText(kb * 1024))"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { start() } label: { Label(T("Look again", "Cari lagi"), systemImage: "arrow.clockwise") }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
                    .opacity(feature == .apps ? 0 : 1).disabled(feature == .apps)
            }
            Button { run() } label: { Label(feature.actionTitle, systemImage: feature == .tune ? "play.fill" : "trash.fill") }
                .buttonStyle(Pill(colors: feature == .tune ? Pal.keep : Pal.danger))
                .disabled(sel.isEmpty)
        }
    }

    private func group(_ g: String) -> some View {
        let list = items.filter { $0.group == g }
        let free = list.filter { $0.locked == nil }
        let all = !free.isEmpty && free.allSatisfy { picked.contains($0.id) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(careGroupTitle(g)).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 6)
                if free.count > 1 {
                    Button(all ? T("None", "Kosongkan") : T("All", "Semua")) {
                        for i in free { if all { _ = picked.remove(i.id) } else { _ = picked.insert(i.id) } }
                    }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(Pal.ink)
                }
            }
            ForEach(list) { it in row(it) }
        }
        .padding(10)
        .surface(12, fill: Th.tile)
    }

    private func row(_ it: CareItem) -> some View {
        let line = it.locked ?? (it.tag.map { $0 + (it.detail.isEmpty ? "" : ". " + it.detail) } ?? it.detail)
        return HStack(alignment: .top, spacing: 8) {
            Toggle(it.name, isOn: Binding(get: { picked.contains(it.id) && it.locked == nil },
                                     set: { on in if on { _ = picked.insert(it.id) } else { _ = picked.remove(it.id) } }))
                .toggleStyle(.checkbox).labelsHidden()
                .accessibilityLabel(it.name)      // v5.25 (197)
                .disabled(it.locked != nil)
            VStack(alignment: .leading, spacing: 1) {
                Text(it.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                if !line.isEmpty {
                    Text(line).font(.system(size: 10))
                        .foregroundStyle(it.locked != nil || it.tag != nil ? Th.orange : Color.secondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            if !it.path.hasPrefix("task:") {
                Text(careSize(it.kb)).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                Button { careReveal(it.path) } label: { Label(T("Show in Finder", "Tampilkan di Finder"), systemImage: "magnifyingglass").labelStyle(.iconOnly) }
                    .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                    .help(T("Show in Finder", "Tampilkan di Finder"))
                    .accessibilityLabel(T("Show in Finder", "Tampilkan di Finder"))      // v5.25 (197)
            }
        }
        .opacity(it.locked != nil ? 0.6 : 1)
        .help(it.path.hasPrefix("task:") ? it.name : CareFS.shown(it.path))
    }

    private var done: some View {
        let r = result ?? CareResult()
        return RoomyScroll {
            VStack(spacing: 10) {
                Card {
                    Text(T("Done", "Selesai")).font(.system(size: 15, weight: .bold))
                    ForEach(r.lines) { l in
                        HStack(alignment: .top) {
                            Image(systemName: l.failed == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(l.failed == 0 ? Th.green : Th.orange)
                            Text(careGroupTitle(l.group)).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 6)
                            Text(lineText(l)).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    if r.changed > 0 {
                        Note(text: T("\(r.changed) changed since the list was made, so they were left alone.",
                                     "\(r.changed) berubah sejak daftar dibuat, jadi tidak disentuh."),
                             icon: "exclamationmark.triangle.fill", color: Th.orange)
                    }
                    if r.failed > r.changed {
                        Note(text: T("Some could not be removed (open or locked files). Nothing else was touched.",
                                     "Ada yang tidak bisa dihapus (file sedang dipakai atau dikunci). Yang lain tidak disentuh."),
                             icon: "info.circle.fill", color: Th.muted)
                    }
                    if feature != .tune {
                        Text(T("Space freed +\(bytesText((r.kb + r.trashKB) * 1024))", "Ruang kosong +\(bytesText((r.kb + r.trashKB) * 1024))"))
                            .font(.system(size: 20, weight: .bold)).foregroundStyle(Th.green)
                        if r.trashKB > 0 {
                            Note(text: T("\(bytesText(r.trashKB * 1024)) of it is in the Trash now. The space comes back when the "
                                         + "Trash is emptied (Amnesia empties it at your next logout).",
                                         "\(bytesText(r.trashKB * 1024)) di antaranya sekarang ada di Trash. Ruangnya kembali setelah "
                                         + "Trash dikosongkan (Amnesia mengosongkannya saat logout berikutnya)."))
                        }
                    }
                }
                HStack(spacing: 10) {
                    Button { back() } label: { Label(T("Back", "Kembali"), systemImage: "chevron.left") }
                        .buttonStyle(Pill(colors: Pal.gray))
                    Button { chosen = nil; result = nil; start() } label: {
                        Label(T("Look again", "Cari lagi"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(Pill(colors: feature.colors))
                }
            }
        }
        .scrollIndicators(.never)
    }

    private func lineText(_ l: CareResult.Line) -> String {
        var s = feature == .tune ? (l.failed == 0 ? T("done", "selesai") : T("skipped", "dilewati"))
                                 : T("\(l.done) done", "\(l.done) selesai")
        if feature != .tune && l.failed > 0 { s += T(", \(l.failed) failed", ", \(l.failed) gagal") }
        if feature != .tune && l.kb > 0 { s += ", " + bytesText(l.kb * 1024) }
        return s
    }
}

/// v5.24: Ringkasan disk. Hanya dibaca; tombolnya hanya membuka Finder.
struct CareOverviewView: View {
    @EnvironmentObject var m: Model
    let back: () -> Void
    @State private var data: CareOverview?
    @State private var scan: CareScan?

    var body: some View {
        VStack(spacing: 14) {
            PageHeader(title: T("Disk overview", "Ringkasan disk"), icon: "chart.pie.fill", colors: Pal.gray, back: { scan?.cancel(); back() })
            if let o = data {
                RoomyScroll {
                    VStack(spacing: 10) {
                        if o.cut {
                            Note(text: T("Some folders took too long and are not counted.", "Beberapa folder terlalu lama dihitung dan tidak ikut."),
                                 icon: "clock.badge.exclamationmark", color: Th.orange)
                        }
                        disk(o)
                        list(T("What takes space", "Yang memakan ruang"), o.spots)
                        if !o.folders.isEmpty { list(T("Biggest folders", "Folder terbesar"), o.folders) }
                        list(T("Big files (200 MB or more)", "File besar (200 MB ke atas)"), o.files,
                             empty: T("None in Keep, Downloads or Desktop.", "Tidak ada di Keep, Downloads atau Desktop."))
                        Card {
                            Text(T("Old downloads", "Unduhan lama")).font(.system(size: 13, weight: .semibold))
                            Text(o.oldCount == 0 ? T("No files older than 30 days in Downloads.", "Tidak ada file lebih dari 30 hari di Downloads.")
                                 : T("\(o.oldCount) files not changed for 30 days or more, \(bytesText(o.oldKB * 1024)). "
                                     + "Wiped at the next logout anyway unless you keep them.",
                                     "\(o.oldCount) file tidak berubah 30 hari atau lebih, \(bytesText(o.oldKB * 1024)). "
                                     + "Tetap dihapus saat logout berikutnya kecuali kamu simpan."))
                                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Button { load() } label: { Label(T("Check Again", "Cek Lagi"), systemImage: "arrow.clockwise") }
                            .buttonStyle(Pill(colors: Pal.gray))
                    }
                }
                .scrollIndicators(.never)
            } else {
                Spacer()
                ProgressView().controlSize(.large)
                Text(T("Measuring…", "Mengukur…")).font(.system(size: 12)).foregroundStyle(.secondary)
                Button { scan?.cancel(); back() } label: { Label(T("Cancel", "Batal"), systemImage: "xmark.circle.fill") }
                    .buttonStyle(Pill(colors: Pal.gray)).frame(maxWidth: 200)
                Spacer()
            }
        }
        .onAppear { if data == nil && scan == nil { load() } }
        .onDisappear { scan?.cancel() }
    }

    private func load() {
        data = nil
        let s = CareScan()
        scan = s
        m.quiet({ CareScanner.overview(s) }) { o in
            guard scan === s, !s.cancelled else { return }
            data = o
        }
    }

    private func disk(_ o: CareOverview) -> some View {
        Card {
            Text(T("Startup disk", "Disk utama")).font(.system(size: 13, weight: .semibold))
            if o.total > 0 && o.free >= 0 {
                let used = Double(o.total - o.free) / Double(o.total)
                ProgressView(value: min(1, max(0, used))).tint(used > 0.9 ? Th.orange : Th.green)
                Text(T("\(bytesText(o.free)) free of \(bytesText(o.total))", "\(bytesText(o.free)) kosong dari \(bytesText(o.total))"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Text(T("Couldn't check.", "Tidak bisa dicek.")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private func list(_ title: String, _ spots: [CareSpot], empty: String = "") -> some View {
        Card {
            Text(title).font(.system(size: 13, weight: .semibold))
            if spots.isEmpty && !empty.isEmpty {
                Text(empty).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ForEach(spots) { s in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(s.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        if s.name != CareFS.shown(s.path) {
                            Text(CareFS.shown(s.path)).font(.system(size: 10)).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 6)
                    Text(careSize(s.kb)).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Button { careReveal(s.path) } label: { Label(T("Show in Finder", "Tampilkan di Finder"), systemImage: "magnifyingglass").labelStyle(.iconOnly) }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                        .help(T("Show in Finder", "Tampilkan di Finder"))
                        .accessibilityLabel(T("Show in Finder", "Tampilkan di Finder"))      // v5.25 (197)
                }
            }
        }
    }
}
