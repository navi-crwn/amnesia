// Amnesia v5.25: halaman "Tanya AI" dan perintah Terminal `amnesia`.
// Dibuild bersama Amnesia.swift, Extras.swift, Safety.swift dan Care.swift (lihat build.sh).
//
// v5.25: Amnesia sendiri TIDAK memakai internet di sini. Alurnya:
//   1. report.py membuat laporan tanpa isi file dan tanpa nama file kamu (+ prompt siap pakai);
//   2. kamu salin atau simpan laporan itu, lalu tempel sendiri ke AI pilihanmu;
//   3. jawaban AI ditempel kembali; report.py --parse-suggestion membaca blok ```amnesia-suggestion dan mengecek
//      semuanya (path relatif dari home, tanpa "..", baris milik Amnesia tidak bisa dihapus, app tak dikenal dibuang);
//   4. tiap perubahan tampil dengan kotak centang; tidak ada yang diterapkan otomatis. Mode & Keep List lewat
//      Keep.applyMode / Keep.commitMode (pratinjau + konfirmasi), profil vault lewat profilesCall(["profile-set"]).

import SwiftUI
import AppKit

// MARK: - Jawaban report.py --parse-suggestion

struct AIItem: Decodable {
    let item: String
    let why: String
}

struct AISuggestion: Decodable {
    let ok: Bool
    let error: String?
    let mode: String?
    let keep_add: [String]?
    let keep_remove: [String]?
    let profiles: [String: [String]]?
    let notes: String?
    let rejected: [AIItem]?
    let skipped: [AIItem]?
    let ignored_apps: [String]?
}

/// 1 perubahan dari saran AI, dengan kotak centang.
struct AIChange: Identifiable {
    enum Kind { case mode, add, remove, profile }
    let id: String
    let kind: Kind
    let value: String
    var apps: [String] = []
    var on: Bool
}

/// v5.25: menjalankan report.py (laporan, simpan, cek jawaban). Tidak pernah memakai internet.
enum AIReport {
    static var script: String { P.a + "/report.py" }

    static func args(_ extra: [String], hide: Bool, lang: String) -> [String] {
        [script] + extra + ["--lang", lang] + (hide ? ["--hide-names"] : [])
    }

    /// Prompt + laporan (Markdown). Menjalankan clean.sh --dry-run, jadi panggil di background.
    static func make(hide: Bool, lang: String) -> Out {
        sh(P.python, args(["--prompt"], hide: hide, lang: lang), timeout: 420)
    }

    /// Simpan ke folder Keep. Hasil: path file (stdout).
    static func save(hide: Bool, lang: String) -> Out {
        sh(P.python, args(["--save"], hide: hide, lang: lang), timeout: 420)
    }

    static func parse(_ answer: String) -> AISuggestion? {
        let r = sh(P.python, [script, "--parse-suggestion"], input: answer, timeout: 120)
        let last = r.out.split(separator: "\n").last.map(String.init) ?? ""
        return try? JSONDecoder().decode(AISuggestion.self, from: Data(last.utf8))
    }

    /// Baris Keep List untuk ditampilkan: "~/path" atau "Keychain: nama".
    static func shown(_ line: String) -> String {
        line.hasPrefix("keychain:") ? "Keychain: " + String(line.dropFirst(9)) : "~/" + line
    }

    /// Kenapa sebuah saran tidak dipakai (alasan dari report.py).
    static func whyText(_ why: String) -> String {
        switch why {
        case "unknown-mode": return T("not a mode Amnesia has", "bukan mode yang dimiliki Amnesia")
        case "dots": return T("contains \"..\" or \".\"", "berisi \"..\" atau \".\"")
        case "absolute": return T("not inside your home folder", "bukan di dalam folder home kamu")
        case "control-character": return T("contains hidden characters", "berisi karakter tersembunyi")
        case "too-long": return T("too long", "terlalu panjang")
        case "empty": return T("empty", "kosong")
        case "not-text": return T("not a line of text", "bukan baris teks")
        case "unknown-tag": return T("not a path or keychain: line", "bukan path atau baris keychain:")
        case "protected": return T("Amnesia's own folder or the Trash", "folder milik Amnesia atau Trash")
        case "in-keep-folder": return T("already safe inside your Keep folder", "sudah aman di dalam folder Keep")
        case "wildcard-top": return T("would keep almost everything", "akan menyimpan hampir semuanya")
        case "already-kept": return T("already on your Keep List", "sudah ada di Keep List")
        case "not-on-list": return T("not on your Keep List", "tidak ada di Keep List")
        case "required": return T("Amnesia needs this line", "baris ini dibutuhkan Amnesia")
        case "duplicate": return T("listed twice", "disebut dua kali")
        case "conflict": return T("both added and removed", "ditambah sekaligus dikeluarkan")
        case "reserved": return T("this name is used by Everything", "nama ini dipakai untuk Semua")
        case "bad-name": return T("name must be 1 to 40 characters", "nama harus 1 sampai 40 karakter")
        case "no-known-apps": return T("none of its apps are in your vault", "tidak ada app-nya yang ada di vault kamu")
        case "too-many": return T("too many items", "terlalu banyak item")
        default: return why
        }
    }

    static func errorText(_ e: String?) -> String {
        switch e {
        case "no-block":
            return T("No ```amnesia-suggestion block was found. Ask the AI to end its answer with that block, then paste "
                     + "the whole answer again.",
                     "Blok ```amnesia-suggestion tidak ditemukan. Minta AI menutup jawabannya dengan blok itu, lalu "
                     + "tempel seluruh jawabannya lagi.")
        case "bad-json", "not-object":
            return T("The suggestion block could not be read. Ask the AI to write it again in the format from the prompt.",
                     "Blok saran tidak bisa dibaca. Minta AI menulisnya lagi dengan format dari prompt.")
        case "too-big":
            return T("The answer is too long (more than 64 KB). Paste only the end with the suggestion block.",
                     "Jawabannya terlalu panjang (lebih dari 64 KB). Tempel bagian akhirnya saja yang berisi blok saran.")
        default:
            return T("The answer could not be checked. Is Amnesia installed completely?",
                     "Jawaban tidak bisa dicek. Apakah Amnesia terpasang lengkap?")
        }
    }
}

// MARK: - Halaman Tanya AI

struct AskAIView: View {
    @EnvironmentObject var m: Model
    let back: () -> Void
    @State private var hide = false
    @State private var report = ""             // prompt + laporan terakhir
    @State private var showReport = false
    @State private var answer = ""
    @State private var result: AISuggestion?
    @State private var changes: [AIChange] = []
    @State private var problem: String?
    @State private var done: String?

    private var lang: String { Lang.current.rawValue }

    var body: some View {
        RoomyScroll {
            VStack(spacing: 14) {
                PageHeader(title: T("Ask an AI", "Tanya AI"), icon: "bubble.left.and.text.bubble.right.fill",
                           colors: Pal.preview, back: back)
                Text(T("Get advice on your mode, Keep List and vault profiles from the AI you choose. Amnesia makes a "
                       + "report with no file contents and no names of your files, plus a ready-made prompt. You paste it "
                       + "into the AI, then paste the answer back here and tick the changes you want.",
                       "Minta saran tentang mode, Keep List dan profil vault dari AI pilihanmu. Amnesia membuat laporan "
                       + "tanpa isi file dan tanpa nama file kamu, plus prompt siap pakai. Kamu tempel ke AI, lalu tempel "
                       + "jawabannya kembali di sini dan centang perubahan yang kamu mau."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Note(text: T("Amnesia never sends anything. You choose where to paste it.",
                             "Amnesia tidak pernah mengirim apa pun. Kamu yang memilih mau ditempel ke mana."),
                     icon: "lock.shield.fill", color: Th.green)
                reportCard
                answerCard
                if let r = result, r.ok { suggestionCard(r) }
                if let d = done {
                    Card { Note(text: d, icon: "checkmark.circle.fill", color: Th.green) }
                }
            }
        }
        .scrollIndicators(.never)
    }

    // MARK: 1. laporan

    private var reportCard: some View {
        Card {
            HStack(spacing: 10) {
                IconBadge(icon: "doc.text.magnifyingglass", colors: Pal.preview, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(T("1. Your report", "1. Laporan kamu")).font(.system(size: 14, weight: .semibold))
                    Text(T("Mode, Keep List, vault apps, folder sizes and what the next logout wipes. Read it before you share it.",
                           "Mode, Keep List, app vault, ukuran folder dan yang dihapus saat logout berikutnya. Baca dulu sebelum dibagikan."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Toggle(isOn: $hide) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(T("Hide folder names", "Sembunyikan nama folder")).font(.system(size: 12, weight: .semibold))
                    Text(T("Your own folder names and Keep List lines become numbers. App names stay.",
                           "Nama folder dan baris Keep List kamu sendiri diganti nomor. Nama app tetap."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)
            .onChange(of: hide) { _, _ in report = "" }
            HStack(spacing: 10) {
                Button { withReport { text in copy(text) } } label: {
                    Label(T("Copy report and prompt", "Salin laporan dan prompt"), systemImage: "doc.on.doc.fill")
                }
                .buttonStyle(Pill(colors: Pal.accent))
                Button { saveReport() } label: {
                    Label(T("Save to Keep folder", "Simpan ke folder Keep"), systemImage: "tray.and.arrow.down.fill")
                }
                .buttonStyle(Pill(colors: Pal.keep))
            }
            .disabled(m.busy != nil)
            Button {
                if showReport { showReport = false } else { withReport { _ in showReport = true } }
            } label: {
                Label(showReport ? T("Hide the report", "Tutup laporan") : T("Show the report", "Lihat laporan"),
                      systemImage: showReport ? "eye.slash" : "eye")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Pal.ink)
            .disabled(m.busy != nil)
            if showReport && !report.isEmpty {
                ScrollView {
                    Text(verbatim: report)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 240)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Th.tint))
            }
        }
    }

    /// Laporan dibuat sekali (dry-run butuh beberapa detik), lalu dipakai lagi sampai pilihan "sembunyikan" berubah.
    private func withReport(_ then: @escaping @MainActor (String) -> Void) {
        if !report.isEmpty { then(report); return }
        guard ready() else { return }
        let h = hide, l = lang
        m.background(T("Making the report… (checking what the next logout wipes)",
                       "Membuat laporan… (mengecek yang dihapus saat logout berikutnya)"), {
            AIReport.make(hide: h, lang: l)
        }) { r in
            let text = r.out
            if r.code != 0 || !text.contains("# Amnesia report") {
                info(T("The report could not be made", "Laporan tidak bisa dibuat"),
                     String((r.err.isEmpty ? r.out : r.err).suffix(400)), error: true)
                return
            }
            report = text
            then(text)
        }
    }

    private func ready() -> Bool {
        guard Engine.hasPython else {
            info(T("Python is needed", "Butuh Python"),
                 T("The report uses Python from Apple's Command Line Tools. Install them with: xcode-select --install",
                   "Laporan memakai Python dari Command Line Tools Apple. Pasang dengan: xcode-select --install"), error: true)
            return false
        }
        guard FileManager.default.fileExists(atPath: AIReport.script) else {
            info(T("Not installed yet", "Belum terpasang"),
                 T("report.py is missing in ~/.amnesia. Quit and reopen Amnesia, then try again.",
                   "report.py tidak ada di ~/.amnesia. Tutup dan buka lagi Amnesia, lalu coba lagi."), error: true)
            return false
        }
        return true
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        // v5.25 (item 196): "Jangan tampilkan lagi" (AI_COPIED_HIDE=1 di settings.conf)
        guard Config.get("AI_COPIED_HIDE") != "1" else { return }
        let r = popup(T("Copied", "Disalin"), "",
                      [PopSection(.happens, [T("The prompt and the report are on the clipboard. Paste them into the AI you choose. "
                                               + "Then copy the AI's whole answer and come back here.",
                                               "Prompt dan laporan sudah ada di clipboard. Tempel ke AI pilihanmu. Lalu salin "
                                               + "seluruh jawaban AI dan kembali ke sini.")])],
                      check: T("Don't show this again", "Jangan tampilkan lagi"))
        if r.checked { Config.set("AI_COPIED_HIDE", "1") }
    }

    private func saveReport() {
        guard ready() else { return }
        let h = hide, l = lang
        m.background(T("Saving the report…", "Menyimpan laporan…"), { AIReport.save(hide: h, lang: l) }) { r in
            let path = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
            guard r.code == 0, !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
                info(T("Not saved", "Tidak tersimpan"), String((r.err.isEmpty ? r.out : r.err).suffix(400)), error: true)
                return
            }
            let shownPath = path.hasPrefix(P.home + "/") ? "~/" + String(path.dropFirst(P.home.count + 1)) : path
            if popup(T("Saved in your Keep folder", "Tersimpan di folder Keep"), "",
                     [PopSection(.kept, [shownPath]),
                      PopSection(.note, [T("It stays after logout. Open it, copy everything and paste it into the AI you choose.",
                                           "File ini tetap ada setelah logout. Buka, salin semuanya dan tempel ke AI pilihanmu.")])],
                     ok: T("Show in Finder", "Buka di Finder"), cancel: "OK").ok {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        }
    }

    // MARK: 2. jawaban AI

    private var answerCard: some View {
        Card {
            HStack(spacing: 10) {
                IconBadge(icon: "text.bubble.fill", colors: Pal.accent, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(T("2. Paste the AI's answer", "2. Tempel jawaban AI")).font(.system(size: 14, weight: .semibold))
                    Text(T("The whole answer is fine. Amnesia only reads the amnesia-suggestion block at the end.",
                           "Seluruh jawaban boleh. Amnesia hanya membaca blok amnesia-suggestion di bagian akhir."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            TextEditor(text: $answer)
                .font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 110, maxHeight: 180)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Th.tint))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Th.line2, lineWidth: 1))
            HStack(spacing: 10) {
                Button {
                    if let s = NSPasteboard.general.string(forType: .string) { answer = s }
                } label: {
                    Label(T("Paste the AI's answer", "Tempel jawaban AI"), systemImage: "doc.on.clipboard.fill")
                }
                .buttonStyle(Pill(colors: Pal.gray))
                Button { check() } label: {
                    Label(T("Check the answer", "Cek jawabannya"), systemImage: "checklist")
                }
                .buttonStyle(Pill(colors: Pal.accent))
                .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .disabled(m.busy != nil)
            if let p = problem {
                Note(text: p, icon: "exclamationmark.triangle.fill", color: Th.orange)
            }
        }
    }

    private func check() {
        guard ready() else { return }
        let text = answer
        problem = nil
        done = nil
        m.background(T("Checking the answer…", "Mengecek jawabannya…"), { AIReport.parse(text) }) { r in
            guard let r = r, r.ok else {
                result = nil
                changes = []
                problem = AIReport.errorText(r?.error)
                return
            }
            result = r
            changes = makeChanges(r)
            if changes.isEmpty {
                problem = T("The AI suggests no changes Amnesia can make. See the notes below.",
                            "AI tidak menyarankan perubahan yang bisa dilakukan Amnesia. Lihat catatannya di bawah.")
            }
        }
    }

    private func makeChanges(_ r: AISuggestion) -> [AIChange] {
        var out: [AIChange] = []
        if let md = r.mode, Keep.modeIds.contains(md), md != Keep.currentMode() {
            out.append(AIChange(id: "mode", kind: .mode, value: md, on: false))
        }
        for a in r.keep_add ?? [] { out.append(AIChange(id: "add:" + a, kind: .add, value: a, on: true)) }
        for a in r.keep_remove ?? [] { out.append(AIChange(id: "remove:" + a, kind: .remove, value: a, on: false)) }
        for name in (r.profiles ?? [:]).keys.sorted(by: { $0.lowercased() < $1.lowercased() }) {
            out.append(AIChange(id: "profile:" + name, kind: .profile, value: name, apps: r.profiles?[name] ?? [], on: true))
        }
        return out
    }

    // MARK: 3. saran dengan kotak centang

    private func title(_ c: AIChange) -> String {
        switch c.kind {
        case .mode: return T("Switch mode to \(Keep.modeTitle(c.value))", "Ganti mode ke \(Keep.modeTitle(c.value))")
        case .add: return T("Keep ", "Simpan ") + AIReport.shown(c.value)
        case .remove: return T("Stop keeping ", "Berhenti menyimpan ") + AIReport.shown(c.value)
        case .profile: return T("Vault profile \"\(c.value)\"", "Profil vault \"\(c.value)\"")
        }
    }

    private func detail(_ c: AIChange) -> String {
        switch c.kind {
        case .mode: return Keep.modeSub(c.value)
        case .add: return T("Not wiped at logout from now on.", "Mulai sekarang tidak dihapus saat logout.")
        case .remove: return T("Wiped at every logout from now on. Move what you still need to your Keep folder first.",
                               "Mulai sekarang dihapus setiap logout. Pindahkan dulu yang masih kamu perlukan ke folder Keep.")
        case .profile: return c.apps.joined(separator: ", ")
        }
    }

    private func icon(_ c: AIChange) -> (String, Color) {
        switch c.kind {
        case .mode: return ("dial.medium.fill", Th.indigo)
        case .add: return ("checkmark.shield.fill", Th.green)
        case .remove: return ("trash.fill", Th.red)
        case .profile: return ("person.crop.rectangle.stack.fill", Th.cyan)
        }
    }

    private func suggestionCard(_ r: AISuggestion) -> some View {
        Card {
            HStack(spacing: 10) {
                IconBadge(icon: "checklist", colors: Pal.keep, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(T("3. Pick the changes you want", "3. Pilih perubahan yang kamu mau"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(T("Nothing is applied until you press Review changes and confirm.",
                           "Tidak ada yang diterapkan sebelum kamu menekan Tinjau perubahan dan konfirmasi."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach($changes) { $c in
                Toggle(isOn: $c.on) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: icon(c).0).foregroundStyle(icon(c).1).frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: title(c)).font(.system(size: 12, weight: .semibold))
                                .lineLimit(2).truncationMode(.middle)
                            Text(verbatim: detail(c)).font(.system(size: 11)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .toggleStyle(.checkbox)
            }
            let left = (r.rejected ?? []) + (r.skipped ?? [])
            if !left.isEmpty || !(r.ignored_apps ?? []).isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(T("Left out", "Tidak dipakai")).font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                    ForEach(Array(left.prefix(30).enumerated()), id: \.offset) { _, x in
                        Text(verbatim: "• " + x.item + " (" + AIReport.whyText(x.why) + ")")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .lineLimit(2).truncationMode(.middle)
                    }
                    if left.count > 30 {
                        Text(T("…and \(left.count - 30) more", "…dan \(left.count - 30) lainnya"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if let ig = r.ignored_apps, !ig.isEmpty {
                        Text(verbatim: T("Apps not in your vault: ", "App yang tidak ada di vault kamu: ")
                             + ig.prefix(20).joined(separator: ", "))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let n = r.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(T("The AI's notes", "Catatan dari AI")).font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                    Text(verbatim: n).font(.system(size: 11)).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !changes.isEmpty {
                Button { review() } label: {
                    Label(T("Review changes", "Tinjau perubahan"), systemImage: "eye.fill")
                }
                .buttonStyle(Pill(colors: Pal.accent))
                .disabled(m.busy != nil || !changes.contains(where: { $0.on }))
            }
        }
    }

    // MARK: 4. tinjau & terapkan (selalu dengan pratinjau dan konfirmasi)

    private func review() {
        let adds = changes.filter { $0.on && $0.kind == .add }.map { $0.value }
        let removes = changes.filter { $0.on && $0.kind == .remove }.map { $0.value }
        let newMode = changes.first(where: { $0.on && $0.kind == .mode })?.value
        let profs = changes.filter { $0.on && $0.kind == .profile }
        done = nil
        if adds.isEmpty && removes.isEmpty && newMode == nil {
            guard !profs.isEmpty else { return }
            guard ask(T("Save these vault profiles?", "Simpan profil vault ini?"), "",
                      [PopSection(.happens, profs.map { $0.value + ": " + $0.apps.joined(separator: ", ") },
                                  title: T("Vault profiles", "Profil vault")),
                       PopSection(.note, [T("A profile only chooses which apps a restore brings back. Nothing is deleted.",
                                            "Profil hanya memilih app mana yang dikembalikan saat restore. Tidak ada yang dihapus.")])],
                      ok: T("Save profiles", "Simpan profil")) else { return }
            saveProfiles(profs, keepDone: nil)
            return
        }
        let target = newMode ?? Keep.currentMode()
        m.background(T("Checking what would change… (two dry runs, nothing is deleted)",
                       "Mengecek apa yang berubah… (dua kali dry-run, tidak ada yang dihapus)"), {
            Keep.applyMode(target, extraAdd: adds, extraRemove: removes)
        }) { p in confirmPreview(p, profs) }
    }

    private func capped(_ lines: [String]) -> [String] {
        let shown = lines.prefix(25).map { l -> String in
            l.hasPrefix("/") || l.hasPrefix("~/") || l.hasPrefix("Keychain") || l.hasPrefix("keychain:") ? l : "~/" + l
        }
        return lines.count > 25 ? shown + [T("…and \(lines.count - 25) more", "…dan \(lines.count - 25) lainnya")] : shown
    }

    private func confirmPreview(_ p: ModePreview, _ profs: [AIChange]) {
        if let prob = p.problem {
            info(T("Nothing was changed", "Tidak ada yang diubah"), prob, error: true)
            return
        }
        let switching = p.mode != p.from
        var secs: [PopSection] = []
        if p.wipesMore {
            secs.append(PopSection(.warn, [T("This mode wipes more than your current one. Move anything you still need into your Keep folder first.",
                                             "Mode ini menghapus lebih banyak dari mode sekarang. Pindahkan dulu yang masih kamu perlukan ke folder Keep.")]))
        }
        secs.append(PopSection(.deleted, capped(p.newlyWiped),
                               title: T("Will now be wiped at logout", "Mulai sekarang dihapus saat logout")))
        secs.append(PopSection(.kept, capped(p.newlyKept), title: T("Will now be kept", "Mulai sekarang disimpan")))
        secs.append(PopSection(.happens, p.added.map { AIReport.shown($0) },
                               title: T("Lines added to your Keep List", "Baris yang ditambahkan ke Keep List")))
        secs.append(PopSection(.warn, p.removed.map { AIReport.shown($0) },
                               title: T("Lines taken off your Keep List", "Baris yang dikeluarkan dari Keep List")))
        if !profs.isEmpty {
            secs.append(PopSection(.happens, profs.map { $0.value + ": " + $0.apps.joined(separator: ", ") },
                                   title: T("Vault profiles saved too", "Profil vault yang ikut disimpan")))
        }
        var notes = [T("Next logout: \(p.wipeAfter) items wiped (now \(p.wipeBefore)).",
                       "Logout berikutnya: \(p.wipeAfter) item dihapus (sekarang \(p.wipeBefore)).")]
        if p.settings[Setting.autoSnapshot.rawValue] == "0" {
            notes.append(T("Auto snapshot at logout is turned off. Your snapshots stay and you can still restore by hand.",
                           "Snapshot otomatis saat logout dimatikan. Snapshot kamu tetap ada dan masih bisa di-restore manual."))
        }
        if let n = p.note { notes.append(n) }
        notes.append(T("It takes effect at the next logout. Nothing is deleted now.",
                       "Berlaku mulai logout berikutnya. Sekarang tidak ada yang dihapus."))
        secs.append(PopSection(.note, notes))
        let title = switching ? T("Switch to \(Keep.modeTitle(p.mode))?", "Ganti ke \(Keep.modeTitle(p.mode))?")
                              : T("Change your Keep List?", "Ubah Keep List kamu?")
        let ok = switching ? T("Switch mode", "Ganti mode") : T("Apply changes", "Terapkan perubahan")
        guard ask(title, "", secs, ok: ok, danger: p.wipesMore) else { return }
        guard Keep.commitMode(p) else {
            // v5.25: alasan dari Keep.commitMode (berubah sejak pratinjau, gagal menulis, dll.)
            let why = Keep.commitError.isEmpty
                ? T("The Keep List changed since the preview. Look at the preview again.",
                    "Keep List berubah sejak pratinjau. Lihat pratinjaunya lagi.")
                : Keep.commitError
            info(T("Nothing was changed", "Tidak ada yang diubah"), why, error: true)
            return
        }
        let msg = T("Saved. It takes effect at the next logout.", "Tersimpan. Berlaku mulai logout berikutnya.")
        if profs.isEmpty { finish(msg) } else { saveProfiles(profs, keepDone: msg) }
    }

    /// Profil dengan nama yang sama (huruf besar/kecil tidak penting) diperbarui, yang lain dibuat baru. Tidak pernah menghapus.
    private func saveProfiles(_ profs: [AIChange], keepDone: String?) {
        let items = profs.map { (name: $0.value, apps: $0.apps) }
        m.background(T("Saving vault profiles…", "Menyimpan profil vault…"), { () -> [String] in
            let now = profilesCall(["profiles"])
            var failed: [String] = []
            for it in items {
                var obj: [String: Any] = ["name": it.name, "apps": it.apps]
                if let id = now.profiles?.first(where: { $0.name.lowercased() == it.name.lowercased() })?.id {
                    obj["id"] = id
                }
                guard let d = try? JSONSerialization.data(withJSONObject: obj) else { failed.append(it.name); continue }
                let r = profilesCall(["profile-set"], input: String(decoding: d, as: UTF8.self) + "\n")
                if !r.ok { failed.append(it.name + (r.error.map { ": " + $0 } ?? "")) }
            }
            return failed
        }) { failed in
            if !failed.isEmpty {
                info(T("Some profiles were not saved", "Ada profil yang tidak tersimpan"), failed.joined(separator: "\n"), error: true)
            }
            let ok = profs.count - failed.count
            var parts: [String] = []
            if let k = keepDone { parts.append(k) }
            if ok > 0 { parts.append(T("\(ok) vault profile(s) saved. Pick one on the Profile Vault page when you restore.",
                                       "\(ok) profil vault disimpan. Pilih di halaman Profile Vault saat restore.")) }
            if !parts.isEmpty { finish(parts.joined(separator: " ")) }
        }
    }

    private func finish(_ msg: String) {
        done = msg
        changes = []
        result = nil
        problem = nil
        report = ""          // laporan lama tidak cocok lagi
    }
}

// MARK: - Perintah Terminal `amnesia` (hanya membaca)

/// v5.25: symlink /opt/homebrew/bin/amnesia atau /usr/local/bin/amnesia -> ~/.amnesia/amnesia.
/// Hanya folder yang bisa ditulis tanpa admin. File yang bukan symlink kita tidak pernah ditimpa atau dihapus.
enum TerminalCommand {
    static let dirs = ["/opt/homebrew/bin", "/usr/local/bin"]
    /// ~/.amnesia/amnesia (dipasang app). Folder hasil git clone (developer): ~/.amnesia/bin/amnesia.
    static var target: String {
        let a = P.a + "/amnesia", dev = P.a + "/bin/amnesia"
        let fm = FileManager.default
        return !fm.fileExists(atPath: a) && fm.fileExists(atPath: dev) ? dev : a
    }

    static func ours(_ link: String) -> Bool {
        let d = try? FileManager.default.destinationOfSymbolicLink(atPath: link)
        return d == P.a + "/amnesia" || d == P.a + "/bin/amnesia"
    }

    /// Symlink kita yang terpasang sekarang (dicek dari disk), atau nil.
    static var linked: String? { dirs.map { $0 + "/amnesia" }.first { ours($0) } }

    /// Pasang. Hasil: nil = berhasil, atau pesan untuk ditampilkan.
    static func install() -> String? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: target) else {
            return T("The command file is missing in ~/.amnesia. Quit and reopen Amnesia, then try again.",
                     "File perintahnya tidak ada di ~/.amnesia. Tutup dan buka lagi Amnesia, lalu coba lagi.")
        }
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target)
        if linked != nil { return nil }
        for d in dirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: d, isDirectory: &isDir), isDir.boolValue, access(d, W_OK) == 0 else { continue }
            let l = d + "/amnesia"
            // sudah ada sesuatu di sana (file, folder, link lain, link rusak): jangan ditimpa
            if fm.fileExists(atPath: l) || (try? fm.destinationOfSymbolicLink(atPath: l)) != nil { continue }
            if (try? fm.createSymbolicLink(atPath: l, withDestinationPath: target)) != nil { return nil }
        }
        return T("Run it with the full path: ~/.amnesia/amnesia status",
                 "Jalankan dengan path lengkap: ~/.amnesia/amnesia status")
    }

    /// Lepas: hanya symlink kita sendiri.
    static func remove() {
        for d in dirs where ours(d + "/amnesia") {
            try? FileManager.default.removeItem(atPath: d + "/amnesia")
        }
    }
}

struct TerminalCommandCard: View {
    @State private var on = TerminalCommand.linked != nil
    @State private var msg: String?

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(icon: "terminal.fill", colors: Pal.gray, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(SettingsView.tTerminal.title).font(.system(size: 14, weight: .semibold))
                    MoreText(SettingsView.tTerminal.sub).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(get: { on }, set: { v in toggle(v) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel(SettingsView.tTerminal.title)      // v5.25 (197)
            }
            if let l = TerminalCommand.linked, on {
                Note(text: T("Ready. Type amnesia status in the Terminal. (\(l))",
                             "Siap. Ketik amnesia status di Terminal. (\(l))"),
                     icon: "checkmark.circle.fill", color: Th.green)
            }
            if let t = msg {
                Note(text: t, icon: "info.circle.fill", color: Th.orange)
            }
        }
        .onAppear { on = TerminalCommand.linked != nil }
    }

    private func toggle(_ v: Bool) {
        if Shots.mandul { return }
        if v {
            msg = TerminalCommand.install()
        } else {
            TerminalCommand.remove()
            msg = nil
        }
        on = TerminalCommand.linked != nil
    }
}

extension SettingsView {
    static let tTerminal = SetText(
        en: "Terminal command", id: "Perintah Terminal",
        subEn: "Adds a read-only `amnesia` command for the Terminal: status, preview, report. It never deletes anything.",
        subId: "Menambah perintah `amnesia` (hanya membaca) untuk Terminal: status, preview, report. Tidak pernah menghapus apa pun.",
        tags: "cli terminal shell command perintah amnesia status preview report")
}
