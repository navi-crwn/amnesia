// Amnesia for Windows, the page side. Talks to C# (Bridge.cs) through WebView2 messages.
// v0.4: all texts live here (English + Indonesian); the HTML only has data-t keys.
(function () {
  'use strict';
  var wv = window.chrome && window.chrome.webview;
  var waiting = {}, next = 1, onProgress = {};
  if (wv) wv.addEventListener('message', function (e) {
    var m = e.data;
    if (m.event === 'progress') { var f = onProgress[m.op]; if (f) f(m.pct, m.step); return; }
    if (m.event === 'view') { go(m.view); return; }
    var w = waiting[m.id];
    if (!w) return;
    delete waiting[m.id];
    m.ok ? w.ok(m.data) : w.fail(new Error(m.error || 'Unknown error'));
  });
  function ask(cmd, arg) {
    return new Promise(function (ok, fail) {
      if (!wv) return fail(new Error('Open this page inside the Amnesia app.'));
      var id = next++;
      waiting[id] = { ok: ok, fail: fail };
      wv.postMessage(arg === undefined ? { id: id, cmd: cmd } : { id: id, cmd: cmd, arg: arg });
    });
  }

  var EN = {
    tagline: 'Your PC forgets everything, except what you choose.', back: 'Back',
    tVaultSub: 'Your app logins, locked', tOut: 'Review & sign out', tOutSub: 'See what goes, then sign out',
    tPauseSub: 'Skip the next cleanup once', tPauseOff: 'Turn on Amnesia first', tKeepSub: 'Never wiped',
    tBackupSub: 'To a USB drive or server', tHistSub: 'Cleanups, snapshots, backups', tPrevSub: 'A dry run of the next sign out',
    searchPh: 'Search settings (also Advanced)', searchNone: 'Nothing found. Try another word.', gGeneral: 'General',
    advNote: 'For when you want more. All of these are off until you turn them on.',
    badge: 'Test in a VM', tabHome: 'Home', tabKeep: 'Keep List', tabVault: 'Vault', tabBackup: 'Backup', tabAdvanced: 'Advanced', tabSettings: 'Settings',
    agree: 'I understand: at every sign out, restart and shut down, everything outside my Keep folder and Keep List is deleted. I tried "Show preview" first. For now I only use this in a VM.',
    turnOn: 'Turn On', turnOff: 'Turn Off', confirmOff: 'Click again to turn off',
    offTitle: 'Off', offText: 'Nothing gets deleted. Try "Show preview" first, then turn Amnesia on.',
    onTitle: 'On', onText: 'At every sign out, restart and shut down your user folder is wiped. At the next sign in Amnesia checks again.',
    pausedTitle: 'Paused for one session', pausedText: 'The next sign out and sign in are skipped. After that Amnesia is back on by itself.',
    pause: 'Pause one session', resume: 'Cancel pause', reviewBtn: 'Review and sign out',
    restarting: 'Amnesia moved to its own folder and starts again from there...',
    blockedTitle: 'Something blocked Amnesia',
    blockedHow: 'Usually this is "Controlled folder access" in Windows Security, or another antivirus. Add Amnesia as an allowed app there (Windows Security → Virus & threat protection → Ransomware protection → Allow an app). Please don\'t turn your antivirus off.',
    blocked: function (d) { var p = d.split(' '); return 'Last cleanup (' + p[0] + ' ' + (p[1] || '') + '): ' + (p[2] || '?') + ' items were refused by Windows. They stay until Amnesia is allowed.'; },
    openSecurity: 'Open Windows Security', reportFp: 'Report a false alarm to Microsoft',
    previewTitle: 'What gets wiped', previewText: 'A dry run of your user folder. Your Keep folder, the Keep List, OneDrive and what Windows needs to log you in always stay.',
    previewBtn: 'Show preview', keptTitle: 'What stays', busy: 'Checking your user folder...',
    sum: function (n) { return n + ' item' + (n === 1 ? '' : 's') + ' would be deleted. This is only a preview, nothing was touched.'; },
    more: function (n) { return '...and ' + n + ' more'; },
    file: 'file', folder: 'folder', trace: 'trace', kept: 'stays', app: 'app',
    encTitle: 'Disk encryption',
    encOn: 'BitLocker / device encryption is on. Good: your Keep folder is protected too when the PC is off.',
    encOff: 'BitLocker / device encryption is off, or the drive is encrypted but its protection is off (no key yet). Amnesia does not encrypt your Keep folder, so turn on encryption: Settings → Privacy & security → Device encryption (or BitLocker).',
    encPaused: 'BitLocker is paused. Turn it back on in Control Panel → BitLocker.',
    encUnknown: 'Amnesia could not read the encryption state. Check it yourself: Settings → Privacy & security → Device encryption, or Control Panel → BitLocker. (Often in a VM.)',
    histTitle: 'History', histEmpty: 'Nothing yet. After the first sign out with Amnesia on, it shows up here.',
    hClean: function (d) { var p = d.split(' '); return (p[0] === 'login' ? 'Sign in check' : p[0] === 'logout' ? 'Sign out' : 'Cleanup') + ': ' + (p[1] || 0) + ' items' + (p[2] ? ', ' + size(+p[2]) : ''); },
    hPaused: function (d) { return 'Skipped (paused): ' + (d === 'login' ? 'sign in' : 'sign out'); },
    hSnapshot: function (d) { return (d.indexOf('auto:') === 0 ? 'Automatic snapshot: ' + d.slice(5) : 'Snapshot: ' + d); },
    hRestore: function (d) { return d === 'backup' ? 'Restored from a backup' : 'Restored: ' + d; },
    hBackup: function (d) { return 'Backup (' + (d === 'ssh' ? 'server' : 'folder') + ')'; },
    hDoom: function (d) { return 'Doomsday: vault deleted' + (d === 'keep' ? ' + Keep emptied' : ''); },
    hQuick: function (d) { return 'Quick sign out (' + d + ')'; },
    hApps: function (d) { var p = d.split(' '); return 'Removed ' + p[1] + ' new app item(s)'; },
    hLeft: function (d) { return d + ' leftover(s) deleted'; }, hSys: function () { return 'Windows traces cleaned (admin)'; }, hWipe: function (d) { return 'Free space wipe started on ' + d; },
    hBlocked: function (d) { return d + ' items blocked by Windows Security / antivirus'; },
    hVault: function () { return 'Vault created'; },
    reviewTitle: 'Review before you sign out', reviewText: 'This is what goes when you sign out now. Want to keep something? Add it to the Keep List first.',
    revApps: 'Programs that will be removed', signOutNow: 'Sign out now', keepFirst: 'Keep something first', cancel: 'Cancel',
    keepTitle: 'Keep folder', keepText: 'Files in here are never wiped. Everything else in your user folder goes at sign out.', openKeep: 'Open Keep',
    klTitle: 'Keep List', klText: 'Folders and files (from your user folder) that stay at sign out, besides the Keep folder. * works as a wildcard.',
    klEmpty: 'Nothing on the list yet.', klPick: 'Add a folder...', klPathPh: 'or type a path, e.g. .ssh or AppData\\Roaming\\Code\\User', add: 'Add', remove: 'Remove',
    klMissing: 'this folder does not exist yet', klSuggTitle: 'Apps on this PC', klSuggText: 'App data found on this PC. Click one to keep it (its logins and settings stay).',
    klNone: 'Nothing else found.', outsideHome: 'Only things inside your user folder can go on the Keep List (other drives are never touched anyway).',
    vTitle: 'Vault', vIntro: 'The vault keeps locked snapshots of the apps you choose (browser logins, chat apps...). After a sign out you open it with your password and everything is back.',
    vLimit: 'Honest note: Windows locks saved logins to your Windows user. Snapshots come back on this PC and this Windows user, not on another PC.',
    vPw: 'Vault password (at least 12 characters)', vPw2: 'Password again', vPanic: 'Panic word (optional)',
    vPanicText: 'Typing the panic word instead of your password deletes the vault on the spot. 3 wrong passwords in a row do the same (Doomsday). Write your password down somewhere safe: without it the vault can never be opened.',
    vPanicFull: 'The panic word also empties my Keep folder', vCreate: 'Create vault', vMismatch: 'The two passwords are not the same.',
    vAppsTitle: 'What goes in the vault', vAppsText: 'Pick the apps to keep. "Snapshot now" saves them (the apps are closed for a moment). No password needed for that.',
    vSnap: 'Snapshot now', vAddFolder: 'Add a folder...', vNever: 'no snapshot yet', vNotHere: 'not installed here', vDelete: 'Delete snapshot',
    vRestoreTitle: 'Restore', vRestoreText: 'Puts every app with a snapshot back. What the app has now is moved to Temp first (wiped at the next sign out).',
    vPwPh: 'Vault password', vRestore: 'Restore', vRestored: function (n) { return 'Back: ' + n.join(', ') + '. Open the apps, you are signed in again.'; },
    vRestoreIssue: function (name, v) { return v === 'failed' ? name + ' could not be put back (its snapshot is still in the vault).' : name + ': ' + v.split(':')[1] + ' file(s) were in use and stayed as they were.'; },
    vOptions: 'Vault options', vAuto: 'Automatic snapshot at sign out', vAutoText: 'Apps that changed are saved right before the cleanup (at most 60 seconds).',
    vRemind: 'Remind me after sign in', vRemindText: 'A notification after each sign in: click it to restore.',
    vDoom: 'Doomsday after 3 wrong passwords', vDoomText: 'Three wrong passwords in a row delete the vault for good. Off = no limit.',
    vChangePw: 'Change password', vOldPh: 'Current password', vNewPh: 'New password (12+ characters)', vChangePanic: 'Change panic word', vPanicPh: 'New panic word (empty = none)',
    save: 'Save', saved: 'Saved.', working: 'Working...', done: 'Done.',
    vSaved: function (t) { return 'Saved ' + t; },
    bTitle: 'Backup', bNeedVault: 'Backups are locked with your vault password, so create the vault first.',
    bText: 'Your Keep folder, Keep List and vault in one locked file. No password needed here: it is locked with your vault. To put a backup back, use "Move to a new PC" below. Old backups are never deleted by Amnesia.',
    bFolder: 'Folder or USB drive', bSsh: 'My server (SSH)',
    bFolderText: 'A USB drive, another drive, or a cloud folder (OneDrive, Google Drive for desktop). A folder inside your user folder would be wiped at sign out.',
    bPick: 'Choose folder...', bNoFolder: 'No folder chosen yet.', bFolderGone: '(not plugged in right now)',
    bSshText: 'user@server:/path/to/folder. Uses your SSH key (no passwords). Amnesia adds .ssh to your Keep List so the key survives the sign out.',
    bSshPh: 'user@server:/backups/amnesia', bPortPh: 'port', bTest: 'Test', bTestOk: 'Connection works.',
    bEvery: 'Automatic backup', bOff: 'Off', bDay: 'Every day', bWeek: 'Every week', bNow: 'Back up now',
    bLast: function (t) { return t ? 'Last backup: ' + t : 'No backup yet.'; }, bDone: function (w) { return 'Backup done: ' + w; },
    mTitle: 'Move to a new PC', mText: 'On the new PC: install Amnesia, then pick a backup and type your vault password. Your Keep folder, Keep List and vault come back. Amnesia stays off until you turn it on.',
    mPick: 'Choose backup...', mRestore: 'Put it back', mNoFile: 'Choose a backup file first.', mDone: function (n) { return n + ' files are back: your Keep folder, Keep List and vault (whatever was in this backup).'; },
    aIdle: 'Sign out when idle', aIdleText: 'No mouse or keyboard for a while? Amnesia shows a 60 second countdown, then locks, cleans and signs out. Moving the mouse cancels it.',
    aIdleAfter: 'Sign out after', aNever: 'Never',
    aQuick: 'Quick exit', aQuickText: 'A hotkey or pulling out your USB key locks the screen right away, cleans up and signs out without waiting for other apps. Unsaved work is lost.',
    aHotkey: 'Panic hotkey', aOff: 'Off', aUsb: 'USB key', aUsbNone: 'None', aUsbChoose: '(plug in the USB drive, then pick it here)',
    aUsbState: function (n, here) { return n ? 'USB key: ' + n + (here ? ' (plugged in: pulling it out signs you out)' : ' (not plugged in)') : 'No USB key chosen.'; },
    aPanicNow: 'Panic sign out now', aPanicConfirm: 'Lock, clean and sign out right now? Unsaved work is lost.',
    hotkeyTaken: 'Another app already uses this hotkey. Pick another one.',
    aApps: 'Remove new apps', aAppsSwitch: 'Remove programs installed after Turn On',
    aAppsText: 'Programs installed just for you (and Microsoft Store apps) after Amnesia was turned on are removed at sign out. Press Keep to keep one. Programs for everyone need admin, so they are only listed. Careful: Microsoft Store apps you install after turning this on (Claude, WhatsApp...) are removed too, unless you press Keep.',
    aAppsEmpty: 'No new programs since Turn On.', aKeepAll: 'Keep all of these', keep: 'Keep', uninstall: 'Uninstall', needsAdmin: 'for everyone: needs admin',
    kUser: 'just for you', kStart: 'Start menu', kRun: 'starts with Windows', kAppx: 'Microsoft Store', kMachine: 'for everyone', kReg: 'settings in the registry',
    aUsbAction: 'When the USB key is pulled out', aUsbSignOut: 'Clean and sign out', aUsbShutdown: 'Clean and shut down (like Tails)',
    pvTitle: 'Stop Windows remembering', pvText: 'Windows\' own privacy switches, just for your account (no admin). Amnesia writes down the old values, so Undo puts back exactly what was there.',
    pvTrack: 'No lists of recently opened apps and files (Start, Quick access, jump lists).',
    pvClipboard: 'No clipboard history (Win+V) and no clipboard sync to other devices.',
    pvSearch: 'No web results and no search history in Start search.',
    pvTyping: 'Windows stops learning from what you type, write and say.',
    pvAds: 'No advertising ID, tailored tips or suggested apps.',
    pvAi: 'Recall snapshots, Click to Do and Copilot off for you.',
    pvUndo: 'Undo all', pvMac: 'Tip (from Tails): Wi-Fi → "Random hardware addresses" makes your PC harder to recognise on public networks.', pvWifi: 'Open Wi-Fi settings',
    loTitle: 'Find leftovers', loText: 'Uninstallers often leave folders in Program Files and ProgramData, and settings in the registry. This lists what no installed program uses anymore. Nothing is deleted until you tick it and press Delete. Folders need admin (Windows asks once).',
    loScan: 'Look for leftovers', loDelete: 'Delete ticked', loNone: 'No leftovers found.', loScanning: 'Looking... (can take a minute)',
    loLikely: 'probably safe', loCareful: 'has programs inside: only if you are sure', loEmpty: 'empty', loKey: 'registry settings',
    loDone: function (n) { return n + ' leftover(s) deleted.'; },
    xlTitle: 'Extra cleaning list', xlSwitch: 'Use the community list (Winapp2)',
    xlText: 'Winapp2 is a free list of where ~4,000 apps leave history. Amnesia uses the parts in the folders that stay on purpose (AppData\\Microsoft, Store apps) and your registry. The list is downloaded from GitHub, never sent anywhere.',
    xlDownload: 'Download / update list', xlAbout: 'About Winapp2',
    xlState: function (l) { return l.exists ? 'List version ' + (l.version || '?') + ', ' + l.entries + ' apps, downloaded ' + l.date + '.' : 'Not downloaded yet: press the button first.'; },
    xlDone: 'List downloaded.', sbTitle: 'Throwaway Windows', sbText: 'Opens Windows Sandbox: a fresh Windows in a window. Try a strange file or website there; everything inside is gone when you close it. Idea from Sandboxie.',
    sbKeep: 'Show my Keep folder inside (read only)', sbNet: 'Internet inside the sandbox', sbOpen: 'Open throwaway Windows',
    sbMissing: 'Windows Sandbox is not switched on. It needs Windows Pro or Enterprise and virtualization (inside a VM it often does not work). Switch on "Windows Sandbox" in Windows features, then restart.',
    sbFeatures: 'Open Windows features',
    wfTitle: 'Wipe free space', wfText: 'Deleted files can sometimes be brought back with recovery tools. This runs Windows\' own "cipher /w" on your drive: it overwrites the free space. Slow (can take an hour) and uses the disk hard. On an SSD Windows already does most of this by itself.',
    wfRun: 'Wipe free space', wfConfirm: 'Start wiping the free space now? A black window shows the progress. You can keep working, but the PC is slower until it is done.', wfStarted: 'Started in a separate window.',
    adCopilot: 'Turn off Copilot for every user.', adTelemetry: 'Lower Windows diagnostic data (telemetry) to the minimum. Fully off only on Enterprise and Education.',
    adSysText: 'One time: empty Windows\' own trace folders outside your user folder (Prefetch, Windows Temp, crash reports, memory dumps).',
    adSysClean: 'Clean Windows traces now', adSysDone: 'Windows traces cleaned.',
    aDyn: 'Dynamic Lock', aDynSwitch: 'Lock when my phone walks away',
    aDynText: 'Windows\' own feature: pair your phone with Bluetooth, and Windows locks itself when the phone is out of range (about a minute later).',
    aBluetooth: 'Pair a phone (Bluetooth)',
    aAdmin: 'Windows protections (admin)', aAdminText: 'Switches for the whole PC. Windows asks for admin rights once when you press Apply.',
    adPagefile: 'Empty the page file at every shut down (memory written to disk). Shut down takes a bit longer.',
    adHiber: 'Turn off hibernation (no copy of your memory on disk).',
    adRecall: 'Stop Windows Recall from saving screenshots (Copilot+ PCs).',
    adActivity: 'Turn off Windows activity history.',
    adApply: 'Apply', adNo: 'Windows did not get admin rights, nothing changed.',
    avTitle: 'Antivirus', avText: 'Amnesia deletes lots of files at sign out, so an antivirus may get suspicious. Since v0.4 the cleanup runs inside Amnesia.exe (no hidden PowerShell). If something blocks it, Amnesia tells you on the Home page.',
    cfaOn: 'Controlled folder access is ON. Allow Amnesia there, or your Documents, Desktop and Pictures are not cleaned.',
    cfaOff: 'Controlled folder access is off.', cfaUnknown: 'Could not read the Windows Security settings (that is normal without admin).',
    langTitle: 'Language', langAuto: 'Same as Windows',
    linksTitle: 'Quick ways to Keep', shortcutTitle: 'Keep shortcut on the Desktop',
    shortcutText: 'A "Keep" shortcut on your Desktop that Amnesia leaves alone at sign out. Shortcuts you make yourself are wiped like any other file.',
    pinTitle: 'Keep in Explorer\'s side bar',
    pinText: 'Pins Keep to Quick access in File Explorer. Windows forgets pins at every sign out, so Amnesia pins it again after each sign in.',
    linksNote: 'Only while Amnesia is on. The tray icon\'s menu (right click) also has Open Keep folder and Turn On / Off.',
    upTitle: 'Update', upCheck: 'Check now', upAuto: 'Check once a day', upAutoText: 'Only asks GitHub for the newest version number. You decide when to install.',
    upInstall: 'Install update',
    upNone: function (c) { return 'You have the newest version (' + c + ').'; },
    upNo: function (c) { return 'No Windows release on GitHub yet. You have ' + c + '.'; },
    upNew: function (l, c) { return 'Amnesia ' + l + ' is out (you have ' + c + ').'; },
    upPortable: 'This copy was not installed with Setup.exe: download the new version from the website.',
    upChecking: 'Checking...', checksum: 'The download did not match its checksum and was deleted. Try again later.',
    logTitle: 'Collect log', logText: 'Something not working? This writes one text file (amnesia-log.txt in your Keep folder) and opens it in Notepad. Amnesia\'s steps and Windows errors, no file names. Nothing is sent anywhere.',
    logBtn: 'Collect log', logOpened: 'Making the log, Notepad opens in a moment.',
    tourTitle: 'Welcome tour', tourText: 'The short introduction from the first start.', tourBtn: 'Show again',
    unTitle: 'Uninstall', unText: 'Turns Amnesia off first, so nothing is wiped any more, then removes the app. Your Keep folder always stays.',
    unApp: 'Uninstall Amnesia', unAllTitle: 'Also delete settings, Keep List and vault',
    unAllText: 'Deletes %USERPROFILE%\\.amnesia too, including the vault (it can\'t come back). Type DELETE to confirm.',
    unAll: 'Uninstall and delete everything', unWord: 'DELETE', unConfirm: 'Uninstall Amnesia? It turns off first, your Keep folder stays.', unBye: 'Amnesia is being removed. Bye!',
    site: 'Amnesia website',
    tour: [
      ['Welcome to Amnesia', 'Every time you sign out, restart or shut down, Amnesia wipes your user folder. Like a guest account, but it is yours.'],
      ['Your Keep folder', 'Put what you want to keep in Keep (there is a shortcut on the Desktop). Folders like .ssh or an app\'s settings go on the Keep List.'],
      ['Vault for logins', 'The vault saves locked snapshots of your browser and chat apps, so you don\'t sign in again every time.'],
      ['Try it safely', 'Press "Show preview" first: it only lists what would go. Test in a VM before your real PC.']
    ],
    tourNext: 'Next', tourDone: 'Let\'s go', tourSkip: 'Skip',
    err: {
      'short-password': 'The password needs at least 12 characters.', 'panic-same': 'The panic word can\'t be the same as the password.',
      'no-vault': 'Create the vault first.', 'nothing': 'Pick at least one app that is on this PC.', 'no-snapshot': 'No snapshot yet. Make one first.', 'restore-failed': 'Nothing could be put back. Your snapshots are still safe in the vault. Close the app (also in Task Manager) and try again.',
      'doomsday': 'DOOMSDAY: the vault was deleted.', 'outside-home': 'Only folders inside your user folder.', 'backup-in-home': 'That folder is inside your user folder and would be wiped at sign out. Pick a USB drive, another drive, a cloud folder or a folder inside Keep.',
      'hotkey-taken': 'Another app already uses this hotkey. Pick another one.', 'admin-no': 'Windows did not get admin rights, nothing changed.',
      'checksum': 'The download did not match its checksum and was deleted. Try again later.', 'busy': 'Another job is still running.', 'cancelled': 'Stopped.',
      'destination-missing': 'The backup folder is not there (USB drive unplugged?).', 'no-destination': 'Choose where backups go first.',
      'no-file': 'Choose a backup file first.', 'not-a-backup': 'That is not an Amnesia backup.', 'no-release': 'No Windows release on GitHub yet.',
      'offline': 'Could not reach GitHub. Check the internet connection.', 'list-bad': 'The downloaded list did not look right and was not used.', 'sandbox-missing': 'Windows Sandbox is not switched on.'
    },
    wrong: function (left) { return left < 0 ? 'Wrong password.' : left === 1 ? 'Wrong password. LAST TRY: one more wrong password DELETES the vault for good. Stop and check your password notes first.' : 'Wrong password. Tries left: ' + left; }
  };

  var ID = {
    tagline: 'PC kamu lupa semuanya, kecuali yang kamu pilih.', back: 'Kembali',
    tVaultSub: 'Login app kamu, terkunci', tOut: 'Cek & sign out', tOutSub: 'Lihat yang dihapus, lalu sign out',
    tPauseSub: 'Lewati 1 kali pembersihan', tPauseOff: 'Nyalakan Amnesia dulu', tKeepSub: 'Tidak pernah dihapus',
    tBackupSub: 'Ke flashdisk atau server', tHistSub: 'Pembersihan, snapshot, backup', tPrevSub: 'Simulasi sign out berikutnya',
    searchPh: 'Cari pengaturan (termasuk Lanjutan)', searchNone: 'Tidak ketemu. Coba kata lain.', gGeneral: 'Umum',
    advNote: 'Untuk yang mau lebih. Semua ini mati sampai kamu nyalakan.',
    badge: 'Tes di VM', tabHome: 'Beranda', tabKeep: 'Keep List', tabVault: 'Vault', tabBackup: 'Backup', tabAdvanced: 'Lanjutan', tabSettings: 'Pengaturan',
    agree: 'Saya paham: setiap sign out, restart dan shut down, semua di luar folder Keep dan Keep List dihapus. Saya sudah coba "Lihat simulasi". Untuk sekarang saya pakai ini di VM saja.',
    turnOn: 'Nyalakan', turnOff: 'Matikan', confirmOff: 'Klik sekali lagi untuk mematikan',
    offTitle: 'Mati', offText: 'Tidak ada yang dihapus. Coba "Lihat simulasi" dulu, lalu nyalakan Amnesia.',
    onTitle: 'Menyala', onText: 'Setiap sign out, restart dan shut down, folder user kamu dibersihkan. Saat login berikutnya Amnesia mengecek lagi.',
    pausedTitle: 'Dijeda satu sesi', pausedText: 'Sign out dan login berikutnya dilewati. Setelah itu Amnesia menyala lagi sendiri.',
    pause: 'Jeda satu sesi', resume: 'Batalkan jeda', reviewBtn: 'Cek dulu, lalu sign out',
    restarting: 'Amnesia pindah ke foldernya sendiri dan dibuka ulang dari sana...',
    blockedTitle: 'Ada yang memblok Amnesia',
    blockedHow: 'Biasanya ini "Controlled folder access" di Windows Security, atau antivirus lain. Tambahkan Amnesia sebagai app yang diizinkan di sana (Windows Security → Virus & threat protection → Ransomware protection → Allow an app). Jangan matikan antivirus kamu.',
    blocked: function (d) { var p = d.split(' '); return 'Pembersihan terakhir (' + p[0] + ' ' + (p[1] || '') + '): ' + (p[2] || '?') + ' item ditolak Windows. Item itu tetap ada sampai Amnesia diizinkan.'; },
    openSecurity: 'Buka Windows Security', reportFp: 'Laporkan salah deteksi ke Microsoft',
    previewTitle: 'Yang dihapus', previewText: 'Simulasi di folder user kamu. Folder Keep, Keep List, OneDrive dan semua yang dibutuhkan Windows untuk login selalu aman.',
    previewBtn: 'Lihat simulasi', keptTitle: 'Yang tetap ada', busy: 'Sedang mengecek folder user kamu...',
    sum: function (n) { return n + ' item akan dihapus. Ini cuma simulasi, tidak ada yang disentuh.'; },
    more: function (n) { return '...dan ' + n + ' lainnya'; },
    file: 'file', folder: 'folder', trace: 'jejak', kept: 'aman', app: 'app',
    encTitle: 'Enkripsi disk',
    encOn: 'BitLocker / enkripsi perangkat menyala. Bagus: folder Keep kamu ikut terlindungi saat PC mati.',
    encOff: 'BitLocker / enkripsi perangkat mati, atau drive sudah terenkripsi tapi perlindungannya mati (belum ada kunci). Amnesia tidak mengenkripsi folder Keep, jadi nyalakan enkripsi: Settings → Privacy & security → Device encryption (atau BitLocker).',
    encPaused: 'BitLocker sedang dijeda. Nyalakan lagi di Control Panel → BitLocker.',
    encUnknown: 'Amnesia tidak bisa membaca status enkripsi. Cek sendiri: Settings → Privacy & security → Device encryption, atau Control Panel → BitLocker. (Sering terjadi di VM.)',
    histTitle: 'Riwayat', histEmpty: 'Belum ada. Setelah sign out pertama dengan Amnesia menyala, riwayatnya muncul di sini.',
    hClean: function (d) { var p = d.split(' '); return (p[0] === 'login' ? 'Cek saat login' : p[0] === 'logout' ? 'Sign out' : 'Pembersihan') + ': ' + (p[1] || 0) + ' item' + (p[2] ? ', ' + size(+p[2]) : ''); },
    hPaused: function (d) { return 'Dilewati (jeda): ' + (d === 'login' ? 'login' : 'sign out'); },
    hSnapshot: function (d) { return (d.indexOf('auto:') === 0 ? 'Snapshot otomatis: ' + d.slice(5) : 'Snapshot: ' + d); },
    hRestore: function (d) { return d === 'backup' ? 'Dipulihkan dari backup' : 'Dipulihkan: ' + d; },
    hBackup: function (d) { return 'Backup (' + (d === 'ssh' ? 'server' : 'folder') + ')'; },
    hDoom: function (d) { return 'Doomsday: vault dihapus' + (d === 'keep' ? ' + Keep dikosongkan' : ''); },
    hQuick: function (d) { return 'Sign out cepat (' + d + ')'; },
    hApps: function (d) { var p = d.split(' '); return p[1] + ' app baru dihapus'; },
    hLeft: function (d) { return d + ' sisa app dihapus'; }, hSys: function () { return 'Jejak Windows dibersihkan (admin)'; }, hWipe: function (d) { return 'Hapus ruang kosong dimulai di ' + d; },
    hBlocked: function (d) { return d + ' item diblok Windows Security / antivirus'; },
    hVault: function () { return 'Vault dibuat'; },
    reviewTitle: 'Cek dulu sebelum sign out', reviewText: 'Ini yang hilang kalau kamu sign out sekarang. Mau simpan sesuatu? Masukkan ke Keep List dulu.',
    revApps: 'Program yang akan dihapus', signOutNow: 'Sign out sekarang', keepFirst: 'Simpan sesuatu dulu', cancel: 'Batal',
    keepTitle: 'Folder Keep', keepText: 'File di sini tidak pernah dihapus. Semua yang lain di folder user kamu hilang saat sign out.', openKeep: 'Buka Keep',
    klTitle: 'Keep List', klText: 'Folder dan file (dari folder user kamu) yang tetap ada saat sign out, selain folder Keep. Tanda * bisa dipakai sebagai wildcard.',
    klEmpty: 'Daftarnya masih kosong.', klPick: 'Tambah folder...', klPathPh: 'atau ketik path, misal .ssh atau AppData\\Roaming\\Code\\User', add: 'Tambah', remove: 'Hapus',
    klMissing: 'folder ini belum ada', klSuggTitle: 'App di PC ini', klSuggText: 'Data app yang ditemukan di PC ini. Klik untuk menyimpannya (login dan pengaturannya tetap ada).',
    klNone: 'Tidak ada yang lain.', outsideHome: 'Hanya isi folder user kamu yang bisa masuk Keep List (drive lain memang tidak pernah disentuh).',
    vTitle: 'Vault', vIntro: 'Vault menyimpan snapshot terkunci dari app pilihanmu (login browser, app chat...). Setelah sign out, buka dengan password dan semuanya kembali.',
    vLimit: 'Catatan jujur: Windows mengunci login tersimpan ke user Windows kamu. Snapshot hanya bisa dipulihkan di PC ini dan user Windows ini, bukan di PC lain.',
    vPw: 'Password vault (minimal 12 karakter)', vPw2: 'Ulangi password', vPanic: 'Kata panik (boleh kosong)',
    vPanicText: 'Mengetik kata panik di kolom password langsung menghapus vault. Salah password 3 kali berturut-turut juga sama (Doomsday). Catat password kamu di tempat aman: tanpa itu vault tidak bisa dibuka selamanya.',
    vPanicFull: 'Kata panik juga mengosongkan folder Keep saya', vCreate: 'Buat vault', vMismatch: 'Kedua password tidak sama.',
    vAppsTitle: 'Isi vault', vAppsText: 'Pilih app yang mau disimpan. "Snapshot sekarang" menyimpannya (app ditutup sebentar). Tidak perlu password.',
    vSnap: 'Snapshot sekarang', vAddFolder: 'Tambah folder...', vNever: 'belum ada snapshot', vNotHere: 'belum terpasang di sini', vDelete: 'Hapus snapshot',
    vRestoreTitle: 'Pulihkan', vRestoreText: 'Mengembalikan semua app yang punya snapshot. Data app yang ada sekarang dipindah ke Temp dulu (terhapus saat sign out berikutnya).',
    vPwPh: 'Password vault', vRestore: 'Pulihkan', vRestored: function (n) { return 'Kembali: ' + n.join(', ') + '. Buka app-nya, kamu sudah login lagi.'; },
    vRestoreIssue: function (name, v) { return v === 'failed' ? name + ' tidak bisa dikembalikan (snapshot-nya tetap ada di vault).' : name + ': ' + v.split(':')[1] + ' file sedang dipakai dan dibiarkan seperti semula.'; },
    vOptions: 'Pilihan vault', vAuto: 'Snapshot otomatis saat sign out', vAutoText: 'App yang berubah disimpan tepat sebelum pembersihan (maksimal 60 detik).',
    vRemind: 'Ingatkan setelah login', vRemindText: 'Notifikasi setiap habis login: klik untuk memulihkan.',
    vDoom: 'Doomsday setelah 3 password salah', vDoomText: 'Tiga password salah berturut-turut menghapus vault selamanya. Mati = tanpa batas.',
    vChangePw: 'Ganti password', vOldPh: 'Password sekarang', vNewPh: 'Password baru (12+ karakter)', vChangePanic: 'Ganti kata panik', vPanicPh: 'Kata panik baru (kosong = tidak ada)',
    save: 'Simpan', saved: 'Tersimpan.', working: 'Sedang dikerjakan...', done: 'Selesai.',
    vSaved: function (t) { return 'Disimpan ' + t; },
    bTitle: 'Backup', bNeedVault: 'Backup dikunci dengan password vault, jadi buat vault dulu.',
    bText: 'Folder Keep, Keep List dan vault dalam satu file terkunci. Tidak perlu password di sini: dikunci dengan vault kamu. Untuk mengembalikan backup, pakai "Pindah ke PC baru" di bawah. Backup lama tidak pernah dihapus Amnesia.',
    bFolder: 'Folder atau flashdisk', bSsh: 'Server saya (SSH)',
    bFolderText: 'Flashdisk, drive lain, atau folder cloud (OneDrive, Google Drive for desktop). Folder di dalam folder user kamu akan ikut terhapus saat sign out.',
    bPick: 'Pilih folder...', bNoFolder: 'Belum ada folder.', bFolderGone: '(sedang tidak terpasang)',
    bSshText: 'user@server:/path/ke/folder. Pakai SSH key kamu (tanpa password). Amnesia menambahkan .ssh ke Keep List supaya key-nya tidak ikut terhapus.',
    bSshPh: 'user@server:/backups/amnesia', bPortPh: 'port', bTest: 'Tes', bTestOk: 'Koneksi berhasil.',
    bEvery: 'Backup otomatis', bOff: 'Mati', bDay: 'Setiap hari', bWeek: 'Setiap minggu', bNow: 'Backup sekarang',
    bLast: function (t) { return t ? 'Backup terakhir: ' + t : 'Belum pernah backup.'; }, bDone: function (w) { return 'Backup selesai: ' + w; },
    mTitle: 'Pindah ke PC baru', mText: 'Di PC baru: pasang Amnesia, pilih file backup, ketik password vault. Folder Keep, Keep List dan vault kembali. Amnesia tetap mati sampai kamu menyalakannya.',
    mPick: 'Pilih backup...', mRestore: 'Kembalikan', mNoFile: 'Pilih file backup dulu.', mDone: function (n) { return n + ' file kembali: folder Keep, Keep List dan vault (sesuai isi backup ini).'; },
    aIdle: 'Sign out saat tidak dipakai', aIdleText: 'Mouse dan keyboard diam beberapa lama? Amnesia menghitung mundur 60 detik, lalu mengunci, membersihkan dan sign out. Gerakkan mouse untuk membatalkan.',
    aIdleAfter: 'Sign out setelah', aNever: 'Tidak pernah',
    aQuick: 'Keluar cepat', aQuickText: 'Tombol pintas atau mencabut flashdisk kunci langsung mengunci layar, membersihkan dan sign out tanpa menunggu app lain. Pekerjaan yang belum disimpan hilang.',
    aHotkey: 'Tombol panik', aOff: 'Mati', aUsb: 'Flashdisk kunci', aUsbNone: 'Tidak ada', aUsbChoose: '(colok flashdisk-nya, lalu pilih di sini)',
    aUsbState: function (n, here) { return n ? 'Flashdisk kunci: ' + n + (here ? ' (terpasang: dicabut = sign out)' : ' (tidak terpasang)') : 'Belum ada flashdisk kunci.'; },
    aPanicNow: 'Sign out darurat sekarang', aPanicConfirm: 'Kunci, bersihkan dan sign out sekarang? Pekerjaan yang belum disimpan hilang.',
    hotkeyTaken: 'Tombol ini sudah dipakai app lain. Pilih yang lain.',
    aApps: 'Hapus app baru', aAppsSwitch: 'Hapus program yang dipasang setelah Amnesia dinyalakan',
    aAppsText: 'Program yang dipasang khusus untuk kamu (dan app Microsoft Store) setelah Amnesia dinyalakan dihapus saat sign out. Tekan Simpan untuk menyimpannya. Program untuk semua user butuh admin, jadi hanya didaftar. Hati-hati: app Microsoft Store yang kamu pasang setelah ini dinyalakan (Claude, WhatsApp...) ikut dihapus, kecuali kamu tekan Simpan.',
    aAppsEmpty: 'Belum ada program baru sejak dinyalakan.', aKeepAll: 'Simpan semua ini', keep: 'Simpan', uninstall: 'Uninstall', needsAdmin: 'untuk semua user: butuh admin',
    kUser: 'khusus kamu', kStart: 'menu Start', kRun: 'jalan saat Windows mulai', kAppx: 'Microsoft Store', kMachine: 'semua user', kReg: 'pengaturan di registry',
    aUsbAction: 'Saat USB key dicabut', aUsbSignOut: 'Bersihkan lalu sign out', aUsbShutdown: 'Bersihkan lalu matikan PC (seperti Tails)',
    pvTitle: 'Supaya Windows tidak mengingat', pvText: 'Pengaturan privasi bawaan Windows, khusus akun kamu (tanpa admin). Amnesia mencatat nilai lamanya, jadi Batalkan mengembalikan persis seperti sebelumnya.',
    pvTrack: 'Tanpa daftar app dan file yang baru dibuka (Start, Quick access, jump list).',
    pvClipboard: 'Tanpa riwayat clipboard (Win+V) dan tanpa sinkron clipboard ke perangkat lain.',
    pvSearch: 'Tanpa hasil web dan riwayat pencarian di Start.',
    pvTyping: 'Windows berhenti belajar dari yang kamu ketik, tulis dan ucapkan.',
    pvAds: 'Tanpa ID iklan, tips khusus atau saran app.',
    pvAi: 'Snapshot Recall, Click to Do dan Copilot mati untuk kamu.',
    pvUndo: 'Batalkan semua', pvMac: 'Tips (dari Tails): Wi-Fi → "Random hardware addresses" bikin PC kamu lebih sulit dikenali di jaringan umum.', pvWifi: 'Buka pengaturan Wi-Fi',
    loTitle: 'Cari sisa app', loText: 'Uninstaller sering meninggalkan folder di Program Files dan ProgramData, juga pengaturan di registry. Ini mendaftar yang sudah tidak dipakai program mana pun. Tidak ada yang dihapus sampai kamu centang dan tekan Hapus. Folder butuh admin (Windows minta sekali).',
    loScan: 'Cari sisa app', loDelete: 'Hapus yang dicentang', loNone: 'Tidak ada sisa app.', loScanning: 'Mencari... (bisa sampai semenit)',
    loLikely: 'kemungkinan aman', loCareful: 'ada program di dalamnya: hanya kalau kamu yakin', loEmpty: 'kosong', loKey: 'pengaturan registry',
    loDone: function (n) { return n + ' sisa app dihapus.'; },
    xlTitle: 'Daftar pembersihan tambahan', xlSwitch: 'Pakai daftar komunitas (Winapp2)',
    xlText: 'Winapp2 adalah daftar gratis tempat ~4.000 app menyimpan riwayat. Amnesia memakai bagian yang ada di folder yang sengaja disimpan (AppData\\Microsoft, app Store) dan registry kamu. Daftarnya diunduh dari GitHub, tidak ada yang dikirim.',
    xlDownload: 'Unduh / perbarui daftar', xlAbout: 'Tentang Winapp2',
    xlState: function (l) { return l.exists ? 'Daftar versi ' + (l.version || '?') + ', ' + l.entries + ' app, diunduh ' + l.date + '.' : 'Belum diunduh: tekan tombolnya dulu.'; },
    xlDone: 'Daftar sudah diunduh.', sbTitle: 'Windows sekali pakai', sbText: 'Membuka Windows Sandbox: Windows baru di dalam jendela. Coba file atau website yang mencurigakan di sana; semuanya hilang saat ditutup. Ide dari Sandboxie.',
    sbKeep: 'Tampilkan folder Keep di dalamnya (hanya baca)', sbNet: 'Internet di dalam sandbox', sbOpen: 'Buka Windows sekali pakai',
    sbMissing: 'Windows Sandbox belum aktif. Butuh Windows Pro atau Enterprise dan virtualisasi (di dalam VM sering tidak bisa). Aktifkan "Windows Sandbox" di Windows features, lalu restart.',
    sbFeatures: 'Buka Windows features',
    wfTitle: 'Hapus ruang kosong', wfText: 'File yang sudah dihapus kadang masih bisa dikembalikan dengan aplikasi recovery. Ini menjalankan "cipher /w" bawaan Windows di drive kamu: ruang kosongnya ditimpa. Lambat (bisa sejam) dan disk bekerja keras. Di SSD, Windows sudah melakukan sebagian besar ini sendiri.',
    wfRun: 'Hapus ruang kosong', wfConfirm: 'Mulai menimpa ruang kosong sekarang? Jendela hitam menampilkan progresnya. Kamu tetap bisa bekerja, tapi PC lebih lambat sampai selesai.', wfStarted: 'Sudah mulai di jendela terpisah.',
    adCopilot: 'Matikan Copilot untuk semua user.', adTelemetry: 'Kurangi data diagnostik Windows (telemetry) ke minimum. Mati total hanya di Enterprise dan Education.',
    adSysText: 'Sekali jalan: kosongkan folder jejak Windows di luar folder user kamu (Prefetch, Temp Windows, laporan crash, memory dump).',
    adSysClean: 'Bersihkan jejak Windows sekarang', adSysDone: 'Jejak Windows sudah dibersihkan.',
    aDyn: 'Dynamic Lock', aDynSwitch: 'Kunci saat HP saya menjauh',
    aDynText: 'Fitur bawaan Windows: pasangkan HP lewat Bluetooth, lalu Windows terkunci sendiri saat HP di luar jangkauan (sekitar semenit kemudian).',
    aBluetooth: 'Pasangkan HP (Bluetooth)',
    aAdmin: 'Perlindungan Windows (admin)', aAdminText: 'Pengaturan untuk seluruh PC. Windows minta izin admin sekali saat kamu tekan Terapkan.',
    adPagefile: 'Kosongkan page file setiap shut down (isi memori yang ditulis ke disk). Shut down jadi sedikit lebih lama.',
    adHiber: 'Matikan hibernasi (tidak ada salinan memori di disk).',
    adRecall: 'Hentikan Windows Recall menyimpan screenshot (PC Copilot+).',
    adActivity: 'Matikan riwayat aktivitas Windows.',
    adApply: 'Terapkan', adNo: 'Windows tidak mendapat izin admin, tidak ada yang berubah.',
    avTitle: 'Antivirus', avText: 'Amnesia menghapus banyak file saat sign out, jadi antivirus bisa curiga. Sejak v0.4 pembersihan jalan di dalam Amnesia.exe (tanpa PowerShell tersembunyi). Kalau ada yang memblok, Amnesia memberi tahu di Beranda.',
    cfaOn: 'Controlled folder access MENYALA. Izinkan Amnesia di sana, kalau tidak Documents, Desktop dan Pictures tidak dibersihkan.',
    cfaOff: 'Controlled folder access mati.', cfaUnknown: 'Pengaturan Windows Security tidak bisa dibaca (normal tanpa admin).',
    langTitle: 'Bahasa', langAuto: 'Sama dengan Windows',
    linksTitle: 'Jalan pintas ke Keep', shortcutTitle: 'Shortcut Keep di Desktop',
    shortcutText: 'Shortcut "Keep" di Desktop yang dibiarkan Amnesia saat sign out. Shortcut buatanmu sendiri tetap ikut terhapus seperti file lain.',
    pinTitle: 'Keep di sidebar Explorer',
    pinText: 'Menyematkan Keep ke Quick access di File Explorer. Windows melupakan sematan setiap sign out, jadi Amnesia menyematkannya lagi setelah setiap login.',
    linksNote: 'Hanya saat Amnesia menyala. Menu ikon tray (klik kanan) juga punya Buka folder Keep dan Nyalakan / Matikan.',
    upTitle: 'Update', upCheck: 'Cek sekarang', upAuto: 'Cek sekali sehari', upAutoText: 'Cuma menanyakan nomor versi terbaru ke GitHub. Kamu yang memutuskan kapan dipasang.',
    upInstall: 'Pasang update',
    upNone: function (c) { return 'Kamu sudah pakai versi terbaru (' + c + ').'; },
    upNo: function (c) { return 'Belum ada rilis Windows di GitHub. Versi kamu ' + c + '.'; },
    upNew: function (l, c) { return 'Amnesia ' + l + ' sudah keluar (punyamu ' + c + ').'; },
    upPortable: 'Salinan ini tidak dipasang lewat Setup.exe: unduh versi baru dari website.',
    upChecking: 'Sedang mengecek...', checksum: 'File unduhan tidak cocok dengan checksum-nya dan sudah dihapus. Coba lagi nanti.',
    logTitle: 'Kumpulkan log', logText: 'Ada yang tidak jalan? Ini membuat satu file teks (amnesia-log.txt di folder Keep kamu) lalu membukanya di Notepad. Isinya langkah Amnesia dan error Windows, tanpa nama file. Tidak ada yang dikirim.',
    logBtn: 'Kumpulkan log', logOpened: 'Log sedang dibuat, sebentar lagi Notepad terbuka.',
    tourTitle: 'Tur sambutan', tourText: 'Perkenalan singkat dari saat pertama dibuka.', tourBtn: 'Tampilkan lagi',
    unTitle: 'Uninstall', unText: 'Amnesia dimatikan dulu, jadi tidak ada yang dihapus lagi, lalu app-nya dihapus. Folder Keep kamu selalu aman.',
    unApp: 'Uninstall Amnesia', unAllTitle: 'Hapus juga pengaturan, Keep List dan vault',
    unAllText: 'Ikut menghapus %USERPROFILE%\\.amnesia, termasuk vault (tidak bisa kembali). Ketik HAPUS untuk konfirmasi.',
    unAll: 'Uninstall dan hapus semuanya', unWord: 'HAPUS', unConfirm: 'Uninstall Amnesia? Amnesia dimatikan dulu, folder Keep kamu tetap ada.', unBye: 'Amnesia sedang dihapus. Sampai jumpa!',
    site: 'Website Amnesia',
    tour: [
      ['Selamat datang di Amnesia', 'Setiap sign out, restart atau shut down, Amnesia membersihkan folder user kamu. Seperti akun tamu, tapi milikmu sendiri.'],
      ['Folder Keep kamu', 'Taruh yang mau disimpan di Keep (ada shortcut-nya di Desktop). Folder seperti .ssh atau pengaturan app masuk Keep List.'],
      ['Vault untuk login', 'Vault menyimpan snapshot terkunci dari browser dan app chat, jadi kamu tidak perlu login ulang terus.'],
      ['Coba dengan aman', 'Tekan "Lihat simulasi" dulu: isinya cuma daftar yang akan hilang. Tes di VM sebelum di PC asli.']
    ],
    tourNext: 'Lanjut', tourDone: 'Ayo mulai', tourSkip: 'Lewati',
    err: {
      'short-password': 'Password minimal 12 karakter.', 'panic-same': 'Kata panik tidak boleh sama dengan password.',
      'no-vault': 'Buat vault dulu.', 'nothing': 'Pilih minimal satu app yang ada di PC ini.', 'no-snapshot': 'Belum ada snapshot. Buat dulu.', 'restore-failed': 'Tidak ada yang bisa dikembalikan. Snapshot kamu tetap aman di vault. Tutup app-nya (juga di Task Manager), lalu coba lagi.',
      'doomsday': 'DOOMSDAY: vault sudah dihapus.', 'outside-home': 'Hanya folder di dalam folder user kamu.', 'backup-in-home': 'Folder itu ada di dalam folder user kamu dan akan terhapus saat sign out. Pilih flashdisk, drive lain, folder cloud atau folder di dalam Keep.',
      'hotkey-taken': 'Tombol ini sudah dipakai app lain. Pilih yang lain.', 'admin-no': 'Windows tidak mendapat izin admin, tidak ada yang berubah.',
      'checksum': 'File unduhan tidak cocok dengan checksum-nya dan sudah dihapus. Coba lagi nanti.', 'busy': 'Pekerjaan lain masih berjalan.', 'cancelled': 'Dihentikan.',
      'destination-missing': 'Folder backup tidak ada (flashdisk dicabut?).', 'no-destination': 'Pilih tempat backup dulu.',
      'no-file': 'Pilih file backup dulu.', 'not-a-backup': 'Itu bukan file backup Amnesia.', 'no-release': 'Belum ada rilis Windows di GitHub.',
      'offline': 'Tidak bisa terhubung ke GitHub. Cek koneksi internet.', 'list-bad': 'Daftar yang diunduh tidak terlihat benar dan tidak dipakai.', 'sandbox-missing': 'Windows Sandbox belum aktif.'
    },
    wrong: function (left) { return left < 0 ? 'Password salah.' : left === 1 ? 'Password salah. PERCOBAAN TERAKHIR: salah sekali lagi = vault DIHAPUS PERMANEN. Berhenti dulu dan cek catatan password kamu.' : 'Password salah. Sisa percobaan: ' + left; }
  };

  var L = EN, info = {};
  function setLang(lang) {
    L = lang === 'id' ? ID : EN;
    document.documentElement.lang = lang === 'id' ? 'id' : 'en';
    document.querySelectorAll('[data-t]').forEach(function (el) { var v = L[el.dataset.t]; if (typeof v === 'string') el.textContent = v; });
    document.querySelectorAll('[data-ph]').forEach(function (el) { var v = L[el.dataset.ph]; if (typeof v === 'string') el.placeholder = v; });
    document.querySelectorAll('[data-tip]').forEach(function (el) { var v = L[el.dataset.tip]; if (typeof v === 'string') { el.title = v; el.setAttribute('aria-label', v); } });
    $('unWord').placeholder = L.unWord;
    if (current) title(current);
    if (info && 'enabled' in info) show(info);
  }
  // turns "vault:wrong:2" and the other codes from C# into a sentence
  function errText(e) {
    var m = (e && e.message) || String(e);
    if (m.indexOf('vault:') === 0) { var p = m.split(':'); return p[1] === 'wrong' ? L.wrong(+p[2]) : (L.err[p[1]] || m); }
    return L.err[m] || m;
  }
  function size(b) {
    if (!b) return '0 MB';
    if (b < 1e9) return (b / 1e6).toFixed(b < 1e7 ? 1 : 0) + ' MB';
    return (b / 1e9).toFixed(1) + ' GB';
  }

  var $ = function (id) { return document.getElementById(id); };
  function el(tag, cls, text) { var e = document.createElement(tag); if (cls) e.className = cls; if (text !== undefined) e.textContent = text; return e; }
  function fill(ul, rows, cap) {
    ul.textContent = '';
    rows.slice(0, cap).forEach(function (r) {
      var li = el('li'); li.append(el('span', 'k', r.kind), el('span', '', r.path)); ul.append(li);
    });
    if (rows.length > cap) ul.append(el('li', '', L.more(rows.length - cap)));
  }
  function say(id, t, cls) { var e = $(id); e.textContent = t || ''; e.className = cls || 'muted'; }
  function progress(id, op) {
    var box = $(id);
    onProgress[op] = function (pct, step) { box.hidden = false; box.querySelector('i').style.width = Math.round(pct * 100) + '%'; box.querySelector('span').textContent = Math.round(pct * 100) + '%' + (step ? ' · ' + step : ''); };
    box.hidden = false; box.querySelector('i').style.width = '0';
    return function () { box.hidden = true; delete onProgress[op]; };
  }
  document.querySelectorAll('[data-cancel]').forEach(function (b) { b.addEventListener('click', function () { ask('cancel'); }); });
  document.querySelectorAll('[data-link]').forEach(function (b) { b.addEventListener('click', function () { ask('open', { target: b.dataset.link }); }); });

  // ---------- pages ----------
  // v0.6: like the Mac app: Home has tiles, every other page has a back button. Advanced lives inside Settings.
  var views = ['home', 'review', 'keep', 'vault', 'backup', 'settings', 'preview', 'history'];
  var titles = { review: 'tOut', keep: 'tabKeep', vault: 'tabVault', backup: 'tabBackup', settings: 'tabSettings', preview: 'previewTitle', history: 'histTitle' };
  var loaders = {}, current = null;
  function title(name) { $('pageTitle').textContent = L[titles[name]] || ''; }
  function go(name) {
    var sub = null;
    if (name === 'advanced') { name = 'settings'; sub = 'advGroup'; }
    if (views.indexOf(name) < 0) name = 'home';
    current = name;
    views.forEach(function (v) { $(v).hidden = v !== name; });
    $('homeHead').hidden = name !== 'home';
    $('pageHead').hidden = name === 'home';
    title(name);
    window.scrollTo(0, 0);
    if (loaders[name]) loaders[name]();
    if (sub) setTimeout(function () { $(sub).scrollIntoView(); }, 50);
  }
  $('back').addEventListener('click', function () { go('home'); });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && current !== 'home' && $('tour').hidden) go('home'); });
  document.querySelectorAll('[data-go]').forEach(function (b) { b.addEventListener('click', function () { go(b.dataset.go); }); });

  // v0.6: search in Settings. Looks at the English AND Indonesian text of each card, so either language works.
  function haystack(card) {
    if (!card._hay) {
      var t = [];
      card.querySelectorAll('[data-t]').forEach(function (e) { [EN, ID].forEach(function (D) { var v = D[e.dataset.t]; if (typeof v === 'string') t.push(v); }); });
      card.querySelectorAll('option').forEach(function (o) { t.push(o.textContent); });
      card._hay = t.join(' ').toLowerCase();
    }
    return card._hay;
  }
  $('setSearch').addEventListener('input', function () {
    var words = this.value.toLowerCase().split(/\s+/).filter(Boolean), any = false;
    document.querySelectorAll('#settings .sgroup').forEach(function (g) {
      var shown = 0;
      g.querySelectorAll(':scope > section.card').forEach(function (c) {
        var ok = words.every(function (w) { return haystack(c).indexOf(w) >= 0; });
        c.hidden = !ok; if (ok) shown++;
      });
      g.hidden = shown === 0; if (shown) any = true;
    });
    $('searchNone').hidden = any;
  });

  // switches that map 1:1 to a setting
  document.querySelectorAll('[data-set]').forEach(function (c) {
    c.addEventListener('change', function () {
      ask('set', { key: c.dataset.set, value: c.checked }).then(function (i) { show(i); if (c.dataset.set === 'removeNewApps') loaders.advanced(); })
        .catch(function (e) { c.checked = !c.checked; say('setMsg', errText(e), 'bad'); });
    });
  });

  function show(i) {
    info = i;
    var st = !i.enabled ? 'off' : i.paused ? 'paused' : 'on';
    $('status').dataset.state = st;
    $('stTitle').textContent = L[st + 'Title'];
    $('stText').textContent = L[st + 'Text'];
    $('offBox').hidden = i.enabled;
    $('onBox').hidden = !i.enabled;
    $('pause').textContent = i.paused ? L.resume : L.pause;
    $('pause').dataset.paused = i.paused ? '1' : '';
    $('tPauseT').textContent = i.paused ? L.resume : L.pause;
    $('tPauseS').textContent = i.enabled ? L.tPauseSub : L.tPauseOff;
    $('tPause').classList.toggle('dim', !i.enabled);
    $('off').textContent = L.turnOff;
    delete $('off').dataset.armed;
    if (i.restarting) { $('stText').textContent = L.restarting; $('onBox').hidden = true; }
    $('keepDir').textContent = i.keepDir || '';
    document.querySelectorAll('[data-set]').forEach(function (c) { if (c.dataset.set in i) c.checked = !!i[c.dataset.set]; });
    document.querySelectorAll('input[name=lang]').forEach(function (r) { r.checked = r.value === i.langSetting; });
    $('aIdleMin').value = String(i.idleMin || 0);
    $('aHotkey').value = i.panicHotkey || '';
    $('aUsbAction').value = i.usbAction || 'signout';
    $('aAppsBox').hidden = !i.removeNewApps;
    $('blockedCard').hidden = !i.lastBlocked;
    if (i.lastBlocked) $('blockedText').textContent = L.blocked(i.lastBlocked);
  }

  // ---------- Home ----------
  function loadHistory() {
    ask('history').then(function (h) {
      h = [].concat(h || []);
      $('histEmpty').hidden = h.length > 0;
      $('hist').hidden = h.length === 0;
      var f = { clean: L.hClean, paused: L.hPaused, snapshot: L.hSnapshot, restore: L.hRestore, backup: L.hBackup, doomsday: L.hDoom, quick: L.hQuick, apps: L.hApps, blocked: L.hBlocked, vault: L.hVault, leftovers: L.hLeft, sysclean: L.hSys, wipe: L.hWipe };
      fill($('hist'), h.map(function (x) { return { kind: x.time.slice(5, 16), path: f[x.kind] ? f[x.kind](x.data) : x.kind + ' ' + x.data }; }), 50);
    }).catch(function () { });
  }
  loaders.history = loadHistory;
  loaders.settings = function () { loaders.advanced(); };
  $('tPause').addEventListener('click', function () { if (info.enabled) $('pause').click(); else go('home'); });
  $('agree').addEventListener('change', function () { $('on').disabled = !this.checked; });
  $('on').addEventListener('click', function () { ask('turnOn').then(show).catch(function (e) { say('msg', errText(e), 'bad'); }); });
  $('pause').addEventListener('click', function () { ask(this.dataset.paused ? 'resume' : 'pause').then(function () { return ask('info'); }).then(show); });
  $('off').addEventListener('click', function () {
    var b = this;
    if (!b.dataset.armed) { b.dataset.armed = '1'; b.textContent = L.confirmOff; return; }
    ask('turnOff').then(function () { $('agree').checked = false; $('on').disabled = true; return ask('info'); }).then(show);
  });
  function preview(btn, msg, res, sum, list, keptList, appsBox, appsList) {
    if (btn) btn.disabled = true;
    say(msg, L.busy); $(res).hidden = true;
    return ask('preview').then(function (r) {
      say(msg, '');
      $(sum).textContent = L.sum(r.count);
      fill($(list), [].concat(r.items || []).map(function (x) { return { kind: L[x.kind] || x.kind, path: x.path }; }), 500);
      if (keptList) fill($(keptList), [].concat(r.kept || []).map(function (p) { return { kind: L.kept, path: p }; }), 500);
      if (appsBox) {
        var apps = [].concat(r.apps || []);
        $(appsBox).hidden = apps.length === 0;
        fill($(appsList), apps.map(function (a) { return { kind: L.app, path: a.name }; }), 200);
      }
      $(res).hidden = false;
    }).catch(function (e) { say(msg, errText(e), 'bad'); }).then(function () { if (btn) btn.disabled = false; });
  }
  $('run').addEventListener('click', function () { preview(this, 'msg', 'result', 'sum', 'items', 'kept'); });

  // ---------- Review and sign out ----------
  loaders.review = function () { preview(null, 'revMsg', 'revResult', 'revSum', 'revItems', null, 'revAppsBox', 'revApps'); };
  $('revSignOut').addEventListener('click', function () { this.disabled = true; ask('signOut'); });

  // ---------- Keep List ----------
  function showKeep(k) {
    $('keepDir').textContent = k.keepDir;
    var ul = $('klList'); ul.textContent = '';
    k.paths.forEach(function (p) {
      var li = el('li'), g = el('span', 'grow');
      g.append(el('span', '', p.path.replace(/\//g, '\\')));
      if (!p.exists) g.append(el('span', 'meta', L.klMissing));
      var b = el('button', 'btn ghost small', L.remove);
      b.addEventListener('click', function () { ask('keepRemove', { path: p.path }).then(showKeep); });
      li.append(g, b); ul.append(li);
    });
    $('klEmpty').hidden = k.paths.length > 0;
    var box = $('klSugg'); box.textContent = '';
    k.suggestions.forEach(function (s) {
      var c = el('button', 'chip', s.path.replace(/\//g, '\\'));
      c.title = s.name;
      c.addEventListener('click', function () { ask('keepAdd', { path: s.path }).then(showKeep); });
      box.append(c);
    });
    if (!k.suggestions.length) box.append(el('span', 'muted', L.klNone));
  }
  loaders.keep = function () { ask('keepList').then(showKeep); };
  $('openKeep').addEventListener('click', function () { ask('openKeep'); });
  $('klPick').addEventListener('click', function () { ask('keepAdd', { path: '' }).then(function (k) { showKeep(k); say('klMsg', ''); }).catch(function (e) { say('klMsg', errText(e), 'bad'); }); });
  $('klAdd').addEventListener('click', function () {
    var v = $('klPath').value.trim();
    if (!v) return;
    ask('keepAdd', { path: v }).then(function (k) { $('klPath').value = ''; showKeep(k); say('klMsg', L.saved); }).catch(function (e) { say('klMsg', errText(e), 'bad'); });
  });

  // ---------- Vault ----------
  function showVault(v) {
    $('vCreate').hidden = v.exists;
    $('vMain').hidden = !v.exists;
    if (!v.exists) return;
    var ul = $('vApps'); ul.textContent = '';
    v.apps.forEach(function (a) {
      var li = el('li'), cb = el('input'), g = el('span', 'grow');
      cb.type = 'checkbox'; cb.checked = a.chosen; cb.disabled = a.folder || !a.present && !a.chosen;
      cb.addEventListener('change', function () { ask('vaultChoose', { name: a.name, on: cb.checked }).then(showVault); });
      g.append(el('span', '', a.name), el('span', 'meta', (a.time ? L.vSaved(a.time) + (a.size ? ', ' + size(a.size) : '') : L.vNever) + (a.present ? '' : ' · ' + L.vNotHere)));
      li.append(cb, g);
      if (a.time) { var d = el('button', 'btn ghost small', L.vDelete); d.addEventListener('click', function () { ask('vaultDelete', { name: a.name }).then(showVault); }); li.append(d); }
      if (a.folder) { var r = el('button', 'btn ghost small', L.remove); r.addEventListener('click', function () { ask('vaultRemoveFolder', { name: a.name }).then(showVault); }); li.append(r); }
      ul.append(li);
    });
  }
  loaders.vault = function () { ask('vaultInfo').then(showVault); };
  $('vCreateBtn').addEventListener('click', function () {
    var p1 = $('vPw1').value, p2 = $('vPw2').value;
    if (p1 !== p2) return say('vCreateMsg', L.vMismatch, 'bad');
    var b = this; b.disabled = true; say('vCreateMsg', L.working);
    ask('vaultCreate', { password: p1, panic: $('vPanic').value, panicFull: $('vPanicFull').checked })
      .then(function (v) { $('vPw1').value = $('vPw2').value = $('vPanic').value = $('vRestorePw').value = ''; say('vCreateMsg', ''); say('vRestoreMsg', ''); say('vOptMsg', ''); say('vMsg', ''); showVault(v); return ask('info'); }).then(show)
      .catch(function (e) { say('vCreateMsg', errText(e), 'bad'); }).then(function () { b.disabled = false; });
  });
  $('vAddFolder').addEventListener('click', function () { ask('vaultAddFolder').then(showVault).catch(function (e) { say('vMsg', errText(e), 'bad'); }); });
  $('vSnap').addEventListener('click', function () {
    var b = this, stop = progress('vProg', 'vault'); b.disabled = true; say('vMsg', L.working);
    ask('vaultSnapshot').then(function (v) { showVault(v); say('vMsg', L.done, 'good'); }).catch(function (e) { say('vMsg', errText(e), 'bad'); })
      .then(function () { stop(); b.disabled = false; });
  });
  $('vRestore').addEventListener('click', function () {
    var b = this, stop = progress('vProg', 'vault'); b.disabled = true; say('vRestoreMsg', L.working);
    ask('vaultRestore', { password: $('vRestorePw').value }).then(function (v) { $('vRestorePw').value = ''; showVault(v); var pr = v.problems || {}, extra = Object.keys(pr).map(function (k) { return L.vRestoreIssue(k, pr[k]); }); say('vRestoreMsg', [L.vRestored(v.restored || [])].concat(extra).join(' '), extra.length ? 'warn' : 'good'); })
      .catch(function (e) { say('vRestoreMsg', errText(e), 'bad'); if (/doomsday/.test(e.message)) loaders.vault(); })
      .then(function () { stop(); b.disabled = false; });
  });
  $('vPwBtn').addEventListener('click', function () {
    ask('vaultPassword', { old: $('vOld').value, 'new': $('vNew').value }).then(function () { $('vOld').value = $('vNew').value = ''; say('vOptMsg', L.saved, 'good'); })
      .catch(function (e) { say('vOptMsg', errText(e), 'bad'); if (/doomsday/.test(e.message)) loaders.vault(); });
  });
  $('vPanicBtn').addEventListener('click', function () {
    ask('vaultPanic', { password: $('vPanicPw').value, word: $('vPanicNew').value, full: $('vPanicNewFull').checked })
      .then(function () { $('vPanicPw').value = $('vPanicNew').value = ''; say('vOptMsg', L.saved, 'good'); })
      .catch(function (e) { say('vOptMsg', errText(e), 'bad'); if (/doomsday/.test(e.message)) loaders.vault(); });
  });

  // ---------- Backup ----------
  var backupFile = '';
  function showBackup(b) {
    $('bNoVault').hidden = b.vault;
    $('bMain').hidden = !b.vault;
    document.querySelectorAll('input[name=bKind]').forEach(function (r) { r.checked = r.value === b.kind; });
    $('bFolderBox').hidden = b.kind !== 'folder';
    $('bSshBox').hidden = b.kind !== 'ssh';
    $('bFolderPath').textContent = b.folder ? b.folder + (b.folderThere ? '' : ' ' + L.bFolderGone) : L.bNoFolder;
    if (document.activeElement !== $('bSsh')) $('bSsh').value = b.ssh || '';
    if (document.activeElement !== $('bPort')) $('bPort').value = b.port || '22';
    $('bEvery').value = b.every;
    say('bLast', L.bLast(b.last));
    fill($('bList'), b.list.map(function (f) { return { kind: size(f.size), path: f.name }; }), 20);
    $('bList').hidden = !b.list.length;
  }
  loaders.backup = function () { ask('backupInfo').then(showBackup); };
  document.querySelectorAll('input[name=bKind]').forEach(function (r) {
    r.addEventListener('change', function () { ask('set', { key: 'backupKind', value: r.value }).then(loaders.backup); });
  });
  $('bPickFolder').addEventListener('click', function () { ask('backupFolder').then(showBackup).catch(function (e) { say('bMsg', errText(e), 'bad'); }); });
  $('bSshSave').addEventListener('click', function () {
    ask('set', { key: 'backupSsh', value: $('bSsh').value }).then(function () { return ask('set', { key: 'backupPort', value: $('bPort').value }); })
      .then(function () { say('bMsg', L.saved, 'good'); loaders.backup(); }).catch(function (e) { say('bMsg', errText(e), 'bad'); });
  });
  $('bTest').addEventListener('click', function () {
    say('bMsg', L.working);
    ask('backupTest').then(function (r) { say('bMsg', r.error ? r.error : L.bTestOk, r.error ? 'bad' : 'good'); });
  });
  $('bEvery').addEventListener('change', function () { ask('set', { key: 'backupEvery', value: this.value }).then(loaders.backup); });
  $('bNow').addEventListener('click', function () {
    var b = this, stop = progress('bProg', 'backup'); b.disabled = true; say('bMsg', L.working);
    ask('backupNow').then(function (r) { showBackup(r); say('bMsg', L.bDone(r.where), 'good'); }).catch(function (e) { say('bMsg', errText(e), 'bad'); })
      .then(function () { stop(); b.disabled = false; });
  });
  $('mPick').addEventListener('click', function () { ask('backupPick').then(function (r) { if (r.file) { backupFile = r.file; $('mFile').textContent = r.file; } }); });
  $('mRestore').addEventListener('click', function () {
    if (!backupFile) return say('mMsg', L.mNoFile, 'bad');
    var b = this, stop = progress('mProg', 'restore'); b.disabled = true; say('mMsg', L.working);
    ask('backupRestore', { file: backupFile, password: $('mPw').value }).then(function (r) { $('mPw').value = ''; say('mMsg', L.mDone(r.count), 'good'); return ask('info'); }).then(show)
      .catch(function (e) { say('mMsg', errText(e), 'bad'); }).then(function () { stop(); b.disabled = false; });
  });

  // ---------- Advanced ----------
  var kinds = { user: 'kUser', start: 'kStart', run: 'kRun', appx: 'kAppx', machine: 'kMachine', reg: 'kReg' };
  function showAdv(a) {
    var ul = $('aAppsList'); ul.textContent = '';
    a.apps.forEach(function (x) {
      var li = el('li'), g = el('span', 'grow');
      g.append(el('span', '', x.name), el('span', 'meta', x.kind === 'machine' ? L.needsAdmin : L[kinds[x.kind]]));
      li.append(g);
      if (x.canUninstall) { var u = el('button', 'btn ghost small', L.uninstall); u.addEventListener('click', function () { ask('appsUninstall', { id: x.id }); }); li.append(u); }
      var k = el('button', 'btn ghost small', L.keep); k.addEventListener('click', function () { ask('appsKeep', { id: x.id }).then(showAdv); }); li.append(k);
      ul.append(li);
    });
    $('aAppsEmpty').hidden = a.apps.length > 0;
    var s = $('aUsb'); s.textContent = '';
    var none = el('option', '', L.aUsbNone); none.value = ''; s.append(none);
    if (a.usbKey) { var cur = el('option', '', a.usbKey); cur.value = '=keep'; s.append(cur); }
    a.usb.forEach(function (d) { var o = el('option', '', d.label + ' (' + d.root + ')'); o.value = d.serial; o.dataset.name = d.label; s.append(o); });
    if (!a.usb.length && !a.usbKey) { var hint = el('option', '', L.aUsbChoose); hint.disabled = true; s.append(hint); }
    s.value = a.usbKey ? '=keep' : '';
    $('aUsbState').textContent = L.aUsbState(a.usbKey, a.usbPresent);
    $('aDynamic').checked = a.dynamicLock;
    $('adPagefile').checked = a.admin.pagefile; $('adHiber').checked = a.admin.hiber; $('adRecall').checked = a.admin.recall; $('adActivity').checked = a.admin.activity;
    $('adCopilot').checked = a.admin.copilot; $('adTelemetry').checked = a.admin.telemetry;
    document.querySelectorAll('[data-pv]').forEach(function (c) { c.checked = !!(a.privacy || {})[c.dataset.pv]; });
    $('xlState').textContent = L.xlState(a.list || {});
    $('sbReady').hidden = !a.sandbox; $('sbMissing').hidden = !!a.sandbox;
    $('avCfa').textContent = a.cfa === 'on' ? L.cfaOn : a.cfa === 'off' || a.cfa === 'audit' ? L.cfaOff : L.cfaUnknown;
    $('avCfa').className = a.cfa === 'on' ? 'warn' : 'muted';
  }
  loaders.advanced = function () { ask('advInfo').then(showAdv).catch(function (e) { say('aMsg', errText(e), 'bad'); }); };
  $('aIdleMin').addEventListener('change', function () { ask('set', { key: 'idleMin', value: this.value }).then(show); });
  $('aHotkey').addEventListener('change', function () { var s = this; ask('set', { key: 'panicHotkey', value: s.value }).then(show).catch(function (e) { s.value = ''; say('aMsg', errText(e), 'bad'); }); });
  $('aUsb').addEventListener('change', function () {
    var o = this.selectedOptions[0];
    if (this.value === '=keep') return;
    ask('usbSet', { serial: this.value, name: this.value ? o.dataset.name : '' }).then(showAdv);
  });
  $('aPanicNow').addEventListener('click', function () { if (confirm(L.aPanicConfirm)) ask('panicNow'); });
  $('aKeepAll').addEventListener('click', function () { ask('appsKeepAll').then(showAdv); });
  $('aDynamic').addEventListener('change', function () { ask('dynamicLock', { on: this.checked }).then(showAdv); });
  $('adApply').addEventListener('click', function () {
    var b = this; b.disabled = true; say('adMsg', L.working);
    ask('adminApply', { pagefile: $('adPagefile').checked, hiber: $('adHiber').checked, recall: $('adRecall').checked, activity: $('adActivity').checked, copilot: $('adCopilot').checked, telemetry: $('adTelemetry').checked })
      .then(function (a) { showAdv(a); say('adMsg', L.saved, 'good'); }).catch(function (e) { say('adMsg', errText(e), 'bad'); loaders.advanced(); })
      .then(function () { b.disabled = false; });
  });

  // v0.5: ideas from similar programs
  $('aUsbAction').addEventListener('change', function () { ask('set', { key: 'usbAction', value: this.value }).then(show); });
  $('pvApply').addEventListener('click', function () {
    var on = [], b = this; b.disabled = true;
    document.querySelectorAll('[data-pv]').forEach(function (c) { if (c.checked) on.push(c.dataset.pv); });
    ask('privacyApply', { groups: on }).then(function (a) { showAdv(a); say('pvMsg', L.saved, 'good'); }).catch(function (e) { say('pvMsg', errText(e), 'bad'); }).then(function () { b.disabled = false; });
  });
  $('pvUndo').addEventListener('click', function () { ask('privacyUndo').then(function (a) { showAdv(a); say('pvMsg', L.saved, 'good'); }).catch(function (e) { say('pvMsg', errText(e), 'bad'); }); });
  function showLeft(r) {
    var ul = $('loList'); ul.textContent = '';
    r.folders.forEach(function (f) {
      var li = el('li'), cb = el('input'), g = el('span', 'grow');
      cb.type = 'checkbox'; cb.dataset.folder = f.path; cb.checked = f.level === 'likely';
      g.append(el('span', '', f.path), el('span', 'meta', (f.empty ? L.loEmpty : size(f.size)) + ' · ' + (f.level === 'likely' ? L.loLikely : L.loCareful)));
      li.append(cb, g); ul.append(li);
    });
    r.keys.forEach(function (k) {
      var li = el('li'), cb = el('input'), g = el('span', 'grow');
      cb.type = 'checkbox'; cb.dataset.key = k;
      g.append(el('span', '', 'HKCU\\Software\\' + k), el('span', 'meta', L.loKey));
      li.append(cb, g); ul.append(li);
    });
    var n = r.folders.length + r.keys.length;
    $('loBox').hidden = n === 0;
    say('loMsg', n ? '' : L.loNone);
  }
  $('loScan').addEventListener('click', function () {
    var b = this; b.disabled = true; say('loMsg', L.loScanning);
    ask('leftScan').then(showLeft).catch(function (e) { say('loMsg', errText(e), 'bad'); }).then(function () { b.disabled = false; });
  });
  $('loDelete').addEventListener('click', function () {
    var folders = [], keys = [], b = this;
    document.querySelectorAll('#loList input:checked').forEach(function (c) { if (c.dataset.folder) folders.push(c.dataset.folder); else if (c.dataset.key) keys.push(c.dataset.key); });
    if (!folders.length && !keys.length) return;
    b.disabled = true; say('loMsg', L.working);
    ask('leftDelete', { folders: folders, keys: keys }).then(function (r) { showLeft(r); say('loMsg', L.loDone(folders.length + keys.length), 'good'); })
      .catch(function (e) { say('loMsg', errText(e), 'bad'); }).then(function () { b.disabled = false; });
  });
  $('xlDownload').addEventListener('click', function () {
    var b = this; b.disabled = true; say('xlMsg', L.working);
    ask('listDownload').then(function (a) { showAdv(a); say('xlMsg', L.xlDone, 'good'); }).catch(function (e) { say('xlMsg', errText(e), 'bad'); }).then(function () { b.disabled = false; });
  });
  $('sbOpen').addEventListener('click', function () { ask('sandbox', { shareKeep: $('sbKeep').checked, network: $('sbNet').checked }).then(function () { say('sbMsg', ''); }).catch(function (e) { say('sbMsg', errText(e), 'bad'); }); });
  $('wfRun').addEventListener('click', function () { if (confirm(L.wfConfirm)) ask('wipeFree').then(function () { say('wfMsg', L.wfStarted, 'good'); }).catch(function (e) { say('wfMsg', errText(e), 'bad'); }); });
  $('adSysClean').addEventListener('click', function () {
    var b = this; b.disabled = true; say('adMsg', L.working);
    ask('sysClean').then(function () { say('adMsg', L.adSysDone, 'good'); }).catch(function (e) { say('adMsg', errText(e), 'bad'); }).then(function () { b.disabled = false; });
  });

  // ---------- Settings ----------
  document.querySelectorAll('input[name=lang]').forEach(function (r) {
    r.addEventListener('change', function () { ask('set', { key: 'lang', value: r.value }).then(function (i) { setLang(i.lang); show(i); }); });
  });
  var release = null;
  $('upCheck').addEventListener('click', function () {
    var b = this; b.disabled = true; $('upText').textContent = L.upChecking; $('upBox').hidden = true;
    ask('updateCheck').then(function (r) {
      release = r;
      $('upText').textContent = !r.latest ? L.upNo(r.current) : r.newer ? L.upNew(r.latest, r.current) + (r.canInstall ? '' : ' ' + L.upPortable) : L.upNone(r.current);
      $('upBox').hidden = !r.newer;
      $('upInstall').textContent = r.canInstall ? L.upInstall : L.site;
    }).catch(function (e) { $('upText').textContent = errText(e); }).then(function () { b.disabled = false; });
  });
  $('upInstall').addEventListener('click', function () {
    if (!release || !release.canInstall) return ask('open', { target: 'releases' });
    var stop = progress('upProg', 'update'); this.disabled = true;
    ask('updateInstall').catch(function (e) { $('upText').textContent = errText(e); stop(); $('upInstall').disabled = false; });
  });
  $('collectLog').addEventListener('click', function () { ask('collectLog').then(function () { say('setMsg', L.logOpened); }).catch(function (e) { say('setMsg', errText(e), 'bad'); }); });
  $('tourAgain').addEventListener('click', function () { tour(0); });
  $('unApp').addEventListener('click', function () { if (confirm(L.unConfirm)) ask('uninstall', { all: false }).then(function () { say('setMsg', L.unBye); }); });
  $('unAll').addEventListener('click', function () {
    if ($('unWord').value.trim().toUpperCase() !== L.unWord) { $('unWord').focus(); return; }
    ask('uninstall', { all: true }).then(function () { say('setMsg', L.unBye); });
  });

  // ---------- welcome tour ----------
  var step = 0;
  function tour(n) {
    step = n;
    var t = L.tour[n];
    $('tour').hidden = false;
    $('tourHead').textContent = t[0]; $('tourBody').textContent = t[1];
    $('tourNext').textContent = n === L.tour.length - 1 ? L.tourDone : L.tourNext;
    var d = $('tourDots'); d.textContent = '';
    L.tour.forEach(function (_, i) { d.append(el('i', i === n ? 'on' : '')); });
    $('tourNext').focus();
  }
  function tourEnd() { $('tour').hidden = true; ask('set', { key: 'welcomeDone', value: true }); }
  $('tourNext').addEventListener('click', function () { if (step < L.tour.length - 1) tour(step + 1); else tourEnd(); });
  $('tourSkip').addEventListener('click', tourEnd);

  // ---------- start ----------
  setLang('en');
  ask('info').then(function (i) {
    $('ver').textContent = 'v' + i.version;
    $('win').textContent = i.windows;
    setLang(i.lang);
    show(i);
    go(i.view || 'home');
    if (!i.welcomeDone) tour(0);
    ask('encryption').then(function (e) {
      $('enc').textContent = { on: L.encOn, off: L.encOff, paused: L.encPaused }[e.state] || L.encUnknown;
      $('enc').className = e.state === 'on' ? 'good' : e.state === 'off' || e.state === 'paused' ? 'warn' : 'muted';
    }).catch(function () { $('enc').textContent = L.encUnknown; });
  }).catch(function (e) { say('msg', errText(e), 'bad'); });
})();
