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
    searchPh: 'Search settings (also Advanced)', searchNone: 'Nothing found. Try another word.', gGeneral: 'App', gKeep: 'Keep', gProtect: 'What stays safe', oalSwitch: 'Show Amnesia after you sign in',
    advShow: 'Show advanced settings (sign out, privacy, programs, lab lock)', advHide: 'Hide advanced settings',
    advNote: 'For when you want more. All of these are off until you turn them on.',
    tabHome: 'Home', tabKeep: 'Keep List', tabVault: 'Vault', tabBackup: 'Backup', tabAdvanced: 'Advanced', tabSettings: 'Settings',
    agree: 'I understand: at every sign out, restart and shut down, everything outside my Keep folder and Keep List is deleted. I tried "Show preview" first.',
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
    fqPh: 'Search by name or path', fqFolderTip: 'Show one folder', fqSortTip: 'Sort', unWordTip: 'Type the word to confirm', fqAll: 'All folders', fqName: 'A to Z', fqSize: 'Biggest first', fqTop: 'User folder', fqSys: 'Windows history (registry, Recycle Bin...)',
    fqShown: function (n, t) { return n + ' of ' + t + ' shown'; }, fqNone: 'Nothing matches.',
    gHelp: 'Updates and help', gExit: 'Leaving the PC', gPrivacy: 'Privacy and Windows', gApps: 'Programs', gLocks: 'Locks',
    yes: 'Yes', no: 'No',
    encTitle: 'Disk encryption',
    encOn: 'BitLocker / device encryption is on. Good: your Keep folder is protected too when the PC is off.',
    encOff: 'BitLocker / device encryption is off, or the drive is encrypted but its protection is off (no key yet). Amnesia does not encrypt your Keep folder, so turn on encryption: Settings → Privacy & security → Device encryption (or BitLocker).',
    encPaused: 'BitLocker is paused. Turn it back on in Control Panel → BitLocker.',
    encUnknown: 'Amnesia could not read the encryption state. Check it yourself: Settings → Privacy & security → Device encryption, or Control Panel → BitLocker. (Often in a VM.)',
    histTitle: 'History', histEmpty: 'Nothing yet. After the first sign out with Amnesia on, it shows up here.',
    hClean: function (d) { var p = d.split(' '); return (p[0] === 'login' ? 'Sign in check' : p[0] === 'logout' ? 'Sign out' : 'Cleanup') + ': ' + (p[1] || 0) + ' items' + (+p[2] > 0 ? ', ' + size(+p[2]) : ''); },
    hPaused: function (d) { return 'Skipped (paused): ' + (d === 'login' ? 'sign in' : 'sign out'); },
    hSnapshot: function (d) { return (d.indexOf('auto:') === 0 ? 'Automatic snapshot: ' + d.slice(5) : 'Snapshot: ' + d); },
    hRestore: function (d) { return d === 'backup' ? 'Restored from a backup' : 'Restored: ' + d; },
    hBackup: function (d) { var p = d.split(' '); return 'Backup (' + (p[0] === 'ssh' ? 'server' : 'folder') + ')' + (p[1] ? ', ' + p[1] + ' file(s) in use left out' : ''); },
    hDoom: function (d) { return 'Doomsday: vault deleted' + (d === 'keep' ? ' + Keep emptied' : ''); },
    hQuick: function (d) { return 'Quick sign out (' + d + ')'; },
    hApps: function (d) { var p = d.split(' '); return 'Removed ' + p[1] + ' new app item(s)'; },
    hAppKeep: function (d) { var p = d.split(' '); return 'Kept ' + p[0] + ' new app(s), ' + (p[1] || 0) + ' folder(s) added to the Keep List'; },
    hLeft: function (d) { return d + ' leftover(s) deleted'; }, hSys: function () { return 'Windows traces cleaned (admin)'; }, hWipe: function (d) { return 'Free space wipe started on ' + d; },
    hBlocked: function (d) { return d + ' items blocked by Windows Security / antivirus'; },
    hVault: function () { return 'Vault created'; },
    // v0.8
    hPause: function () { return 'Paused for one session'; }, hResume: function () { return 'Pause cancelled'; },
    ksTitle: 'Keep is still locked', ksText: 'An old Amnesia version left its lock on your Keep folder, but the Keep lock is off now. Open it again here.',
    ksOpen: 'Open Keep', ksPw: 'Old Keep password', ksDone: 'Keep is open again.',
    suTitle: 'Amnesia will not start with Windows', suText: 'Its startup entry is switched off (Task Manager > Startup apps). Then nothing is wiped at the next sign in and the tray icon is gone. Switch it back on here.', suFix: 'Switch it back on',
    healthTitle: 'Health check', healthText: 'Can Amnesia do its job right now? Yellow and red lines tell you what to look at.', hlAgain: 'Check again',
    hlAllOk: 'All good', hlIssues: function (n) { return n + ' thing' + (n === 1 ? '' : 's') + ' to look at'; },
    hl: {
      on: { ok: 'Amnesia is on.', warn: 'Paused: the next sign in is skipped.', bad: 'Amnesia is off: nothing is wiped.' },
      startup: { ok: 'Starts with Windows.', bad: 'Startup is switched off in Windows. Press "Switch it back on" on the home page.', info: 'Not installed yet (turn it on first).' },
      lastClean: { ok: function (d) { return 'Last cleanup: ' + d + '.'; }, warn: 'No cleanup has run yet. Sign out once to test it.', info: 'No cleanup yet.' },
      trash: { ok: 'No files left behind.', warn: function (d) { return d + ' batch(es) of files Windows held open are still waiting. The next sign in tries again.'; } },
      blocked: { ok: 'Windows Security did not block anything.', warn: 'Windows Security or an antivirus blocked items in the last cleanup. See the home page card.' },
      cloud: { info: function (d) { return d ? 'Cloud folders left as they are (so the cloud keeps your files): ' + d + '.' : 'No cloud sync folders found (OneDrive, Dropbox, Google Drive... stay untouched when they are there).'; } },
      vm: { ok: 'Virtual machines and big disc images stay.', warn: 'Virtual machines are wiped like other files (Settings > Protection).' },
      keepLock: { ok: 'Keep is locked with a password.', info: 'Keep is not locked (optional, Settings > Locks).', bad: 'Keep is still locked by an old version. Open it on the home page.' },
      vault: { ok: function (d) { return 'Newest vault snapshot: ' + d + '.'; }, warn: 'The vault has no snapshot yet.', info: 'No vault (optional).' },
      backup: { ok: function (d) { return 'Last backup: ' + d + '.'; }, warn: 'No recent backup. If this PC breaks, Keep and the vault are gone too.', info: 'No backup set up (optional).' },
      hotkey: { ok: function (d) { return 'Panic hotkey: ' + d + '.'; }, info: 'No panic hotkey (optional, Settings).' },
      updates: { ok: 'Updates are checked with the developer\'s signature.', info: 'This copy has no update key: updates open the release page instead of installing by themselves.' }
    },
    limTitle: 'What Amnesia can\'t do', limText: 'Honest limits, so you know where you still need care.',
    lim: [
      'Windows keeps a few traces outside your user folder (Program Files, ProgramData, event logs, the list of programs you ran). Settings > Windows traces (admin) cleans part of it.',
      'A wipe moves files away and deletes them, it does not overwrite the disk. Without BitLocker or device encryption, tools can bring deleted files back. Turn device encryption on.',
      'Saved passwords in Credential Manager stay unless you switch on "Also wipe saved app passwords". Your Microsoft account, OneDrive and Office sign in always stay.',
      'Microsoft Store apps keep their data in Packages. It stays unless you switch on "Also wipe Store app data".',
      'Files Windows holds open at sign out are wiped at the next sign in instead.',
      'Explorer\'s thumbnail cache is cleaned at sign out and quick exit, not while you are signed in (that made the Desktop flicker).',
      'The vault and backups are as strong as your password. Doomsday deletes the vault on this PC, not a copy someone made before.',
      'Browser logins in a snapshot are locked to this Windows user. On a new PC you may have to sign in again.',
      'Amnesia has no paid code signing certificate, so SmartScreen can warn. Compare the SHA256 sums on the release page.'
    ],
    kaTitle: 'Keep an app', kaText: 'Pick an installed app: Amnesia keeps all the folders it saves its data in (logins, settings).', kaPh: 'Search apps', kaEmpty: 'No installed apps with their own data folders found.', kaKeep: 'Keep', kaKept: 'Kept', kaStore: 'Store app',
    protTitle: 'Protection', oalTitle: 'Open at login', oalText: 'Shows the tray icon after you sign in, also while Amnesia is off.',
    vmTitle: 'Keep virtual machines', vmText: 'VirtualBox, Hyper-V, VMware, WSL and Android emulator disks, plus disc images over 1 GB, stay where they are.',
    wsTitle: 'Also wipe Store app data', wsText: 'Off: Microsoft Store apps keep their data. On: their own data goes too (not Windows\' own apps, not ones on your Keep List).',
    wcTitle: 'Also wipe saved app passwords', wcText: 'Removes passwords apps saved in Credential Manager (git, some chat apps). Never your Microsoft account, OneDrive or Office.',
    cloudNote: 'Cloud folders (OneDrive, Dropbox, Google Drive, iCloud...) are never wiped: moving them would delete your files in the cloud too.',
    unPw: 'Keep password (Keep is locked)',
    unSafe: function (n) { return (n > 0 ? 'Your safe box still has ' + n + ' file(s).' : 'Your safe box still has files.') + ' Open it and move them first, or keep it: it opens again after you reinstall Amnesia. Uninstall anyway?'; },
    unSafeAll: function (n) { return (n > 0 ? 'Your safe box still has ' + n + ' file(s).' : 'Your safe box still has files.') + ' Deleting everything deletes the safe box too, for good. Open it and move them first. Go on anyway?'; },
    sbTitle: 'Safe box (experimental)', sbText: 'A locked folder inside Keep for your most private files. Closed, it is one locked file; open, it is Keep\\Safe. Amnesia closes it again at every sign out. Keep it small: closing packs everything again.',
    sbPwPh: 'Safe box password (at least 12 characters)', sbCreate: 'Create safe box', sbOpen: 'Open', sbShow: 'Show in Explorer', sbClose: 'Close and lock',
    sbNone: 'No safe box yet.', sbIsOpen: function (d) { return 'Open in ' + d + '. Closes by itself at sign out.'; }, sbIsClosed: function (n) { return 'Closed and locked (' + n + ').'; },
    sbOpened: function (n) { return n + ' file(s) unpacked.'; }, sbClosedNow: function (n) { return 'Locked again (' + n + ' file(s)).'; },
    vSuggText: 'Found on this PC, not in the vault yet. Click one to add its folder:',
    meter: ['Too short', 'Weak: a fast computer guesses this', 'OK, longer is better', 'Strong'],
    bSkipped: function (n) { return n + ' file(s) were in use and are not in this backup. Close the apps and back up again to get them.'; },
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
    vStep1: 'Pick the apps to save', vStep2: 'Save your logins now', vStep3: 'Bring them back after you sign in',
    vStep2Note: 'No password needed. The apps close for a moment.', vChange: 'Change...', vChangeDone: 'Done',
    vNoneChosen: 'No app picked yet.', vMore: function (n) { return ' and ' + n + ' more'; },
    vLastSaved: function (t, n, s) { return 'Last saved ' + t + ' · ' + n + ' saved' + (s ? ' · ' + s : ''); }, vNotSaved: 'Not saved yet. Sign in to your apps first, then press Snapshot now.',
    vMainTitle: 'Restore or save your logins', vMainText: 'Snapshot now saves the apps you picked (no password needed, they close for a moment). Restore puts them back; what an app has now is moved to Temp first.',
    vAppsFold: 'Pick apps and folders, see each snapshot', vOptsFold: 'Automatic snapshot, reminder, password, panic word',
    infoShow: 'Info', infoAbout: 'About: ',
    vSnap: 'Snapshot now', vAddFolder: 'Add a folder...', vNever: 'no snapshot yet', vNotHere: 'not installed here', vDelete: 'Delete snapshot',
    vRestoreTitle: 'Restore', vRestoreText: 'Puts every app with a snapshot back. What the app has now is moved to Temp first (wiped at the next sign out).',
    vPwPh: 'Vault password', vRestore: 'Restore', vRestored: function (n) { return 'Back: ' + n.join(', ') + '. Open the apps, you are signed in again.'; },
    vRestoreIssue: function (name, v) { return v === 'failed' ? name + ' could not be put back (its snapshot is still in the vault).' : name + ': ' + v.split(':')[1] + ' file(s) were in use and stayed as they were.'; },
    vOptions: 'Vault options', vAuto: 'Automatic snapshot', vAutoText: 'An app that changed is saved automatically after you close it, in the background (never while it runs). Sign out only cleans up, so it is quick.',
    vRemind: 'Remind me after sign in', vRemindText: 'A notification after each sign in: click it to restore.',
    vDoom: 'Doomsday after 3 wrong passwords', vDoomText: 'Three wrong passwords in a row delete the vault on this PC for good. Off = no limit. It can\'t stop someone who copied the vault file before, so a long password is what really protects it.',
    vChangePw: 'Change password', vOldPh: 'Current password', vNewPh: 'New password (12+ characters)', vChangePanic: 'Change panic word', vPanicPh: 'New panic word (empty = none)',
    save: 'Save', saved: 'Saved.', working: 'Working...', done: 'Done.',
    vSaved: function (t) { return 'Saved ' + t; },
    vRestorePrev: 'Use the snapshot before the newest one (if the newest looks wrong)',
    // v0.10 vault profiles
    vpLabel: 'Memory Recall: profile', vpEdit: 'Edit', vpNew: 'New profile', vpNewTitle: 'New profile', vpEditTitle: 'Edit profile', vpName: 'Name',
    vpAppsText: 'Tick the apps this profile brings back. Snapshots stay one per app, so an app can be in more than one profile.',
    vpDelete: 'Delete profile', vpDeleteAsk: function (n) { return 'Delete the profile "' + n + '"? The snapshots stay in the vault.'; },
    vpRestores: function (a) { return 'Restores: ' + a.join(', ') + '.'; }, vpEmpty: 'This profile has no apps yet. Click Edit to add some.',
    vpNoSnap: function (a) { return 'No snapshot yet: ' + a.join(', ') + '.'; }, vpNotHere: function (a) { return 'Not on this PC: ' + a.join(', ') + '.'; },
    vpShared: function (app, a, b) { return app + ' is in ' + a + ' and ' + b + '. One browser holds one set of logins, so restoring either profile brings back all of them. For personal use, a second browser (or a separate browser profile) keeps things apart.'; },
    vpFull: 'Retrograde Amnesia: logins are not saved at sign out. You can still restore a snapshot by hand.',
    vpIgnored: function (a) { return 'Skipped, not in the vault: ' + a.join(', ') + '.'; }, vpNoApps: 'No vault apps on this PC yet.',
    vpErr: { 'no-snapshot-profile': 'None of these apps has a snapshot yet.', 'profile-name': 'Give the profile a name of 1 to 40 characters.',
      'profile-name-reserved': 'That name is used for "Everything". Pick another one.', 'profile-name-taken': 'There is already a profile with that name.',
      'profile-too-many': 'You have 20 profiles, the most there can be. Delete one first.' },
    vPrev: function (t) { return 'previous: ' + t; }, vShrunk: 'much smaller than the previous one, check it', vSetup: 'browser setup was not finished in this snapshot',
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
    aKept: 'Kept. Its folders are on your Keep List now, so it keeps working after sign out.',
    aUninstalling: 'Waiting for the uninstaller to finish... The list updates by itself after.',
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
    xlDone: 'List downloaded.', sxTitle: 'Throwaway Windows', sxText: 'Opens Windows Sandbox: a fresh Windows in a window. Try a strange file or website there; everything inside is gone when you close it. Idea from Sandboxie.',
    sxKeep: 'Show my Keep folder inside (read only)', sxNet: 'Internet inside the sandbox', sxOpen: 'Open throwaway Windows',
    sxMissing: 'Windows Sandbox is not switched on. It needs Windows Pro or Enterprise and virtualization (inside a VM it often does not work). Switch on "Windows Sandbox" in Windows features, then restart.',
    sxFeatures: 'Open Windows features',
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
    linksOff: 'Amnesia is off right now, so these show up after Turn On.',
    klkTitle: 'Keep lock', klkText: 'Your Keep folder only opens through Amnesia, with its own password. It locks again when you lock the screen (Win+L), after the minutes you pick, at sign out and at sign in. While it is locked, no program can open or write files in Keep (test scripts neither), and Keep leaves Explorer\'s side bar until you open it.',
    klkHonest: 'Honest note: the files are not encrypted (use BitLocker for that), and their names stay visible while locked. Someone signed in as you who knows Windows well can still remove the lock in the folder\'s Properties. Forgot the password? Same way: Properties, Security, remove the "Deny" lines.',
    klkPwPh: 'Keep password', klkPw2Ph: 'Same password again', klkAfter: 'Lock again after', klkOn: 'Turn on Keep lock', klkNow: 'Lock now', klkOff: 'Turn off (password)',
    klkLocked: 'Keep is locked. Open it with Open Keep, the tray menu or the Desktop shortcut.', klkOpen: 'Keep is open right now. It locks again by itself.', klkAsk: 'Keep password',
    labTitle: 'Lab lock (for administrators)', labText: 'For a PC many people use, like a computer lab or a library. With a PIN, this Windows user can no longer turn Amnesia off, pause it, quit it, uninstall it or change its settings and Keep List. Turning it on or off asks for administrator rights once.',
    labHonest: 'Honest note: someone can still end Amnesia in Task Manager, but the check at the next sign in cleans anyway. Set your settings and Keep List first, they are locked as they are now.',
    labPinPh: 'PIN (at least 6 digits)', labPin2Ph: 'Same PIN again', labOn: 'Lock with this PIN', labUnlock: 'Unlock for 10 minutes', labSave: 'Save changes and lock again', labClose: 'Lock again now', labOff: 'Remove lab lock',
    labState: function (t) { return 'Locked by the administrator' + (t ? ' since ' + t : '') + '.'; }, labOpenNow: 'Unlocked with the PIN for 10 minutes. Change what you need, then press Save changes and lock again.',
    labBar: 'Locked by the administrator. You can look around; changes need the admin PIN (Settings → Lab lock).', pinMismatch: 'The two entries are not the same.',
    upTitle: 'Update', upCheck: 'Check now', upAuto: 'Check automatically', upAutoText: 'Only asks GitHub for the newest version number. You decide when to install.',
    upOff: 'Never (only when I press Check now)', upWeek: 'Every week', up2Weeks: 'Every 2 weeks', upMonth: 'Every month',
    upInstall: 'Install update',
    upNone: function (c) { return 'You have the newest version (' + c + ').'; },
    upNo: function (c) { return 'No Windows release on GitHub yet. You have ' + c + '.'; },
    upNew: function (l, c) { return 'Amnesia ' + l + ' is out (you have ' + c + ').'; },
    upPortable: 'This copy was not installed with Setup.exe: download the new version from the website.',
    upChecking: 'Checking...', checksum: 'The download did not match its checksum and was deleted. Try again later.',
    logTitle: 'Collect log', logText: 'Something not working? This writes one text file (amnesia-log.txt in your Keep folder) and opens it in Notepad. Amnesia\'s steps and Windows errors, no file names. Nothing is sent anywhere.',
    logBtn: 'Collect log', logOpened: 'Making the log, Notepad opens in a moment.',
    logBusy: 'Collecting the log... (can take up to a minute)', logDone: function (p) { return 'Done: ' + p + ' (opened in Notepad).'; }, logMissing: 'The log could not be written. Try again, or look in trace.log in %USERPROFILE%\\.amnesia.',
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
      ['Try it safely', 'Press "Show preview" first: it only lists what would go.']
    ],
    tourNext: 'Next', tourDone: 'Let\'s go', tourSkip: 'Skip',
    err: {
      'short-password': 'The password needs at least 12 characters.', 'panic-same': 'The panic word can\'t be the same as the password.',
      'lab-locked': 'Locked by the administrator. Unlock with the admin PIN in Settings → Lab lock first.', 'lab-pin-short': 'The PIN needs at least 6 digits.', 'lab-pin-wrong': 'Wrong PIN.', 'admin-no': 'Windows did not get administrator rights (the prompt was answered No).', 'keeplock-short': 'The Keep password needs at least 4 characters.', 'keeplock-wrong': 'Wrong Keep password.',
      'no-vault': 'Create the vault first.', 'nothing': 'Pick at least one app that is on this PC.', 'no-snapshot': 'No snapshot yet. Make one first.', 'restore-failed': 'Nothing could be put back. Your snapshots are still safe in the vault. Close the app (also in Task Manager) and try again.',
      'doomsday': 'DOOMSDAY: the vault was deleted.', 'outside-home': 'Only folders inside your user folder.', 'backup-in-home': 'That folder is inside your user folder and would be wiped at sign out. Pick a USB drive, another drive, a cloud folder or a folder inside Keep.',
      'hotkey-taken': 'Another app already uses this hotkey. Pick another one.', 'admin-no': 'Windows did not get admin rights, nothing changed.',
      'checksum': 'The download did not match its checksum and was deleted. Try again later.', 'busy': 'Another job is still running.', 'cancelled': 'Stopped.',
      'destination-missing': 'The backup folder is not there (USB drive unplugged?).', 'no-destination': 'Choose where backups go first.',
      'no-file': 'Choose a backup file first.', 'not-a-backup': 'That is not an Amnesia backup.', 'no-release': 'No Windows release on GitHub yet.',
      'offline': 'Could not reach GitHub. Check the internet connection.', 'list-bad': 'The downloaded list did not look right and was not used.', 'sandbox-missing': 'Windows Sandbox is not switched on.', 'no-safe': 'Create the safe box first.', 'safe-exists': 'There already is a safe box.',
      'keeplock-uninstall': 'Keep is locked. Type the Keep password above first: Amnesia unlocks Keep before it is removed.', 'pause-not-saved': 'The pause could not be saved. Try again.', 'backup-in-keep': 'Not inside Keep: every backup would then hold all the older ones. Pick a USB drive, another drive or a cloud folder.', 'keep-not-saved': 'That line did not get saved in the Keep List. Try again, or add the folder with Choose folder.', 'unsigned': 'This release has no developer signature, so it is not installed from the app. Open the release page instead.', 'bad-signature': 'The release signature does not match. Nothing was installed. Tell the developer (GitHub issue).'
    },
    wrong: function (left) { return left < 0 ? 'Wrong password.' : left === 1 ? 'Wrong password. LAST TRY: one more wrong password DELETES the vault for good. Stop and check your password notes first.' : 'Wrong password. Tries left: ' + left; },
    // v0.9 Care
    careTitle: 'Care', tCareSub: 'Free up space safely, with a preview first',
    careIntro: 'Free up space when you want, always with a list to check first. Amnesia already wipes most of your user folder at sign out, so Care mostly helps with your Keep folder, the apps you kept and big files from this session. Nothing risky is ticked for you, and links are never followed.',
    // v0.10 Amnesia modes
    mdTitle: 'Amnesia mode', mdText: 'How much your PC forgets at every sign out. You always see a preview first, and a new mode takes effect at the next sign out.',
    mdNames: { full: 'Retrograde Amnesia', balanced: 'Selective Amnesia (recommended)', light: 'Partial Amnesia', custom: 'Custom Amnesia' },
    mdSubs: {
      full: 'Like a brand-new account every time you sign in. Only your Keep folder and what Amnesia needs to work stay.',
      balanced: 'Your Keep folder stays, app logins come back from the vault, and your own Keep List lines stay.',
      light: 'Apps keep their settings and logins in place. Your files, Desktop, Documents and Downloads are wiped.',
      custom: 'Your own Keep List. Picked for you when you change the lines a mode added.'
    },
    mdLightNote: 'Partial Amnesia keeps all of AppData. Browsing history and cookies inside a browser\'s own folder stay too (Edge as well), and so do Temp files, recent file lists and PowerShell history, because they live inside AppData. Thumbnail and icon caches, notification history, the Recycle Bin, the clipboard and the registry\'s recent lists are still wiped.',
    mdNow: 'Now', mdFullVault: 'Retrograde Amnesia: logins are not saved at sign out. You can still restore a snapshot by hand.',
    msTitle: function (m) { return 'Switch to ' + m + '?'; }, msBusy: 'Looking at what the next sign out would do...',
    msWiped: 'Will now be wiped at sign out', msKept: 'Will now be kept', msIdle: 'Leaves the Keep List, nothing is wiped there', msOwn: 'Your own lines (not changed)', msStop: 'Also stop keeping this line',
    msCount: function (a, b) { return 'Next sign out: ' + a + ' items wiped (now ' + b + ').'; },
    msWarn: 'This mode wipes more than your current one. Move anything you still need into your Keep folder first.',
    msAutoOff: 'Auto snapshot at sign out is turned off. Your snapshots stay and you can still restore by hand.',
    msAutoOn: 'Auto snapshot at sign out is turned on again.',
    msWhen: 'It takes effect at the next sign out. Nothing is deleted now.',
    msToCustom: 'A line you ticked is part of this mode, so your Keep List becomes Custom Amnesia.',
    msSame: 'What gets wiped stays the same.', msLineK: 'line', msItemK: 'item',
    msPreset: function (m) { return 'The ' + m + ' preset could not be read, so your Keep List was not changed.'; },
    msSwitch: 'Switch mode', msDone: function (m) { return 'Mode is now ' + m + '. It takes effect at the next sign out.'; },
    mdErr: {
      'mode-broken': 'Your Keep List has a damaged mode section, so the mode was not changed. Fix or remove the lines that start with "# amnesia-mode".',
      'mode-stopped': 'Your Keep List could not be read, so the mode was not changed. Check the Keep List first.',
      'mode-lab': 'The lab lock is on, so only an administrator can change the Keep List.',
      'mode-changed': 'The Keep List changed since the preview. Look at the preview again.',
      'mode-rescan': 'The Keep List changed since the preview. Look at the preview again.',
      'mode-write': 'The Keep List could not be saved. Nothing was changed. Try again.', 'mode-unknown': 'Unknown mode.'
    },
    hMode: function (d) { var p = (d || '').split(' '); return 'Mode changed: ' + (EN.mdNames[p[1]] || p[1] || ''); },
    // v0.10 Ask an AI
    aiTitle: 'Ask an AI', tAiSub: 'Get advice without sharing your files',
    aiIntro: 'Amnesia makes a report about this PC with no file contents and no names of your files, plus a ready-made question. Paste both into the AI you choose. Then paste its answer below and tick the changes you want.',
    aiNever: 'Amnesia never sends anything. You choose where to paste it.',
    aiHide: 'Hide folder names', aiMake: 'Make the report again', aiCopy: 'Copy report and prompt', aiSave: 'Save to Keep folder',
    aiBusy: 'Making the report (this can take a minute)...', aiReady: 'Report ready. Look at what will be shared before you paste it.',
    aiCopied: 'Copied. Paste it into the AI you choose.', aiCopyFail: 'Could not copy. Open "Show what will be shared", select the text and copy it by hand.',
    aiSaved: function (p) { return 'Saved: ' + p; }, aiShow: 'Show what will be shared',
    aiPasteTitle: 'Paste the AI\'s answer', aiPasteText: 'Paste the whole answer. Amnesia only reads the amnesia-suggestion block and checks every line. Nothing changes until you confirm.',
    aiPastePh: 'Paste the AI\'s answer here', aiRead: 'Read the answer',
    aiErr: {
      'no-block': 'No amnesia-suggestion block found. Ask the AI to end its answer with the block from the prompt.',
      'bad-json': 'The block is not valid JSON. Ask the AI to write it again.',
      'not-object': 'The block should be one { ... } object. Ask the AI to write it again.',
      'too-big': 'That answer is too long (64 KB at most).'
    },
    aiNone: 'The answer suggests no changes.',
    aiMode: function (m) { return 'Switch mode to ' + m; }, aiAdd: function (p) { return 'Keep: ' + p; }, aiRemove: function (p) { return 'Stop keeping: ' + p; },
    aiProf: function (n, apps, upd) { return (upd ? 'Update vault profile ' : 'New vault profile ') + n + ': ' + (apps.length ? apps.join(', ') : '(no apps)'); },
    aiNotes: 'The AI\'s notes', aiNotUsed: 'Not used', aiIgnored: function (a) { return 'Apps that are not in the vault, ignored: ' + a.join(', '); },
    aiWhy: {
      'absolute': 'not inside your user folder', 'dots': 'has a .. or . part', 'amnesia': 'Amnesia\'s own folder', 'in-keep': 'already inside your Keep folder',
      'too-wide': 'too wide (only wildcards)', 'tag': 'not a path', 'control': 'odd characters', 'too-long': 'too long', 'empty': 'empty', 'not-text': 'not text',
      'already-kept': 'already kept', 'not-on-list': 'not on your Keep List', 'required': 'Amnesia needs it', 'unknown-mode': 'unknown mode',
      'reserved-name': 'that name is taken by "Everything"', 'bad-name': 'name is empty or too long', 'too-many': 'more than 10 profiles', 'duplicate': 'listed twice',
      'not-a-list': 'not a list', 'not-an-object': 'not a list of profiles'
    },
    aiApply: 'Review changes', aiNoTick: 'Tick at least one change first.',
    aiProfAsk: function (n) { return 'Save ' + n + ' vault profile(s)? Your Keep List does not change.'; },
    aiProfDone: function (n) { return n + ' vault profile(s) saved.'; }, aiProfFail: 'The vault profiles could not be saved.',
    aiApplied: 'Done. Keep List changes take effect at the next sign out.',
    cOvTitle: 'Disk overview', cOvText: 'What takes space on this PC. It only looks, nothing is deleted.', cLook: 'Look',
    cScan: 'Scan', cAgain: 'Scan again', cBusy: 'Looking... (30 seconds at most)', cWorking: 'Working on it...',
    cDisk: function (f, t) { return size(f) + ' free of ' + size(t); },
    cSizes: { keep: 'Keep folder', vault: 'Vault', atrash: 'Amnesia trash', bin: 'Recycle Bin', temp: 'Temp files', downloads: 'Downloads' },
    cFolders: 'Biggest folders', cFiles: 'Big files (200 MB and more)', cNoFiles: 'No files of 200 MB or more in Keep, Downloads or Desktop.',
    cOld: function (n, b) { return n + ' file(s) in Downloads not changed for 30 days (' + size(b) + '). They are wiped at the next sign out anyway, unless they are on the Keep List.'; },
    cShow: 'Show', cAtLeast: 'at least ',
    cQuickTitle: 'Clean now', cQuickText: 'Temp files older than a day, crash dumps, app caches and Amnesia\'s trash. Apps make their caches again when they need them. The Recycle Bin is listed, but never ticked for you.',
    cAppsTitle: 'Uninstall apps', cAppsText: 'Programs installed just for you run their own uninstaller, no admin password needed. Programs for everyone and Store apps open Windows Settings. Leftovers go to the Recycle Bin; your data in them only goes when you tick it.',
    cAppsBtn: 'Show programs', cAppsPh: 'Search programs', cKind: { user: 'just for you', machine: 'for everyone', store: 'Microsoft Store' },
    cUninstall: 'Uninstall', cOpenApps: 'Open Windows Settings', cNoPrograms: 'No programs found.',
    cUnConfirm: function (n) { return 'Run the uninstaller of ' + n + '? It may ask its own questions. Afterwards Amnesia looks for what it left behind.'; },
    cUnGone: function (n) { return n + ' was uninstalled.'; }, cUnStill: function (n) { return n + ' is still installed, so Amnesia did not look for leftovers.'; },
    cUnNoLeft: 'No leftovers found.', cUnLeft: 'It left these behind. Tick what should go:', cSkip: 'Keep them',
    cProjTitle: 'Project build folders', cProjText: 'node_modules, target, build, dist, bin, obj and more, in your project folders and Keep. They can be built again. Folders used in the last 7 days are not ticked; folders tracked by git or holding keys are left alone. They go to the Recycle Bin.',
    cInsTitle: 'Old installers', cInsText: '.msi and .msix files older than 14 days in Downloads, Desktop and Keep. Setup .exe and .zip files and disc images are listed but never ticked for you. Virtual machines and disk images are never listed. They go to the Recycle Bin.',
    cTuneTitle: 'Safe tune-ups', cTuneText: 'Small fixes that need no admin password.',
    cTuneExplorer: 'Restart Explorer', cTuneExplorerSub: 'Helps when the taskbar or Desktop is stuck. Open folder windows close.',
    cTuneRun: 'Run', cTuneNone: 'Tick a tune-up first.', cTuneAsk: 'Restart Explorer now? The taskbar disappears for a few seconds and open folder windows close.',
    cTuneRes: function (ok) { return 'Restart Explorer: ' + (ok ? 'done.' : 'skipped, it did not work.'); },
    cOpenStartup: 'Open Startup apps', cOpenStorage: 'Open Storage settings',
    cCat: { temp: 'Temp files', crash: 'Crash dumps', cache: 'App caches', atrash: 'Amnesia trash', bin: 'Recycle Bin', leftover: 'Leftovers', build: 'Build folders', installer: 'Installers' },
    cWhy: {
      'old-temp': 'not changed for a day', crash: 'crash report', cache: 'made again when needed', atrash: 'already wiped, waiting to be emptied',
      bin: 'emptied for good, can\'t be undone', keeplist: 'On your Keep List', 'leftover-data': 'settings and data, tick only if you are sure',
      'leftover-cache': 'cache', 'build-old': 'not used for 7 days or more', 'build-recent': 'used in the last 7 days', git: 'tracked by git',
      'nested-git': 'holds a git repo', secret: 'holds keys or certificates', unchecked: 'Could not check', cloud: 'in a cloud folder',
      'installer-old': 'older than 14 days', 'installer-new': 'newer than 14 days', 'setup-exe': 'a setup program, check it yourself',
      'setup-zip': 'looks like a setup, check it yourself', 'disc-image': 'a disc image, check it yourself', system: 'Windows needs it',
      amnesia: 'Amnesia\'s own', 'keep-root': 'protected', link: 'a link, never followed', gone: 'not there any more', outside: 'outside your user folder'
    },
    cTop: 'Other', cNothing: 'Nothing to clean here.', cSel: function (n, b) { return n + ' selected, ' + size(b); },
    cGo: { quick: 'Clean selected', apps: 'Move to Recycle Bin', projects: 'Move to Recycle Bin', installers: 'Move to Recycle Bin' },
    cWhere: { 'delete': 'Caches, Temp files and trash are deleted for good.', recycle: 'They go to the Recycle Bin.', bin: 'The Recycle Bin is emptied for good. That can\'t be undone.' },
    cConfirm: function (n, b) { return 'Go ahead with ' + n + ' item(s), ' + size(b) + '?'; },
    cFreed: function (b) { return 'Space freed +' + size(b); },
    cRes: function (c, d, f) { return c + ': ' + d + ' done' + (f ? ', ' + f + ' skipped (in use or changed)' : '') + '.'; },
    cChanged: function (n) { return n + ' item(s) changed since the scan and were left alone.'; },
    cCut: 'The scan stopped at its limit (30 seconds or 300 000 files). What it found so far is listed.',
    cErr: { 'care-rescan': 'The list is old. Scan again first.', 'care-gone': 'It is not there any more.', 'care-not-found': 'That program is not installed any more.', 'care-not-user': 'Only programs installed just for you can be uninstalled here.', 'keeplist-missing': 'The Keep List is missing, so Care stopped and deleted nothing. Open Keep List to check it.', 'keeplist-unreadable': 'The Keep List could not be read, so Care stopped and deleted nothing. Open Keep List to check it.' },
    cFeat: { quick: 'Clean now', apps: 'Uninstall apps', projects: 'Project build folders', installers: 'Old installers', tune: 'Safe tune-ups' },
    hCare: function (d) { var p = d.split(' '); return 'Care: ' + (L.cFeat[p[0]] || p[0]) + ': ' + (p[1] || 0) + ' items' + (+p[2] > 0 ? ', ' + size(+p[2] * 1024) + ' freed' : '') + (+p[3] > 0 ? ', ' + p[3] + ' failed' : ''); },
    hStopped: function () { return 'Cleanup stopped: the Keep List could not be read. Nothing was deleted.'; },
    hlDisk: {
      ok: function (d) { var p = d.split(' '); return 'Free space: ' + size(+p[0]) + ' of ' + size(+p[1]) + '.'; },
      warn: function (d) { var p = d.split(' '); return 'Little free space: ' + size(+p[0]) + ' of ' + size(+p[1]) + '. Care can help.'; },
      info: 'Couldn\'t check the free space.'
    },
    hlMemory: { ok: function (d) { return 'Memory: ' + d + '% in use.'; }, warn: function (d) { return 'Memory is almost full (' + d + '% in use). Closing apps helps.'; }, info: 'Couldn\'t check the memory.' },
    hlBattery: { info: function (d) { if (!d) return 'Couldn\'t check the battery.'; var p = d.split(' '); return 'Battery: ' + p[0] + '%' + (p[1] === '1' ? ', charging' : '') + '.'; } }
  };

  var ID = {
    tagline: 'PC kamu lupa semuanya, kecuali yang kamu pilih.', back: 'Kembali',
    tVaultSub: 'Login app kamu, terkunci', tOut: 'Cek & sign out', tOutSub: 'Lihat yang dihapus, lalu sign out',
    tPauseSub: 'Lewati 1 kali pembersihan', tPauseOff: 'Nyalakan Amnesia dulu', tKeepSub: 'Tidak pernah dihapus',
    tBackupSub: 'Ke flashdisk atau server', tHistSub: 'Pembersihan, snapshot, backup', tPrevSub: 'Simulasi sign out berikutnya',
    searchPh: 'Cari pengaturan (termasuk Lanjutan)', searchNone: 'Tidak ketemu. Coba kata lain.', gGeneral: 'App', gKeep: 'Keep', gProtect: 'Yang tetap aman', oalSwitch: 'Tampilkan Amnesia setelah login',
    advShow: 'Tampilkan pengaturan lanjutan (sign out, privasi, program, kunci lab)', advHide: 'Sembunyikan pengaturan lanjutan',
    advNote: 'Untuk yang mau lebih. Semua ini mati sampai kamu nyalakan.',
    tabHome: 'Beranda', tabKeep: 'Keep List', tabVault: 'Vault', tabBackup: 'Backup', tabAdvanced: 'Lanjutan', tabSettings: 'Pengaturan',
    agree: 'Saya paham: setiap sign out, restart dan shut down, semua di luar folder Keep dan Keep List dihapus. Saya sudah coba "Lihat simulasi".',
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
    fqPh: 'Cari nama atau path', fqFolderTip: 'Tampilkan satu folder', fqSortTip: 'Urutkan', unWordTip: 'Ketik katanya untuk konfirmasi', fqAll: 'Semua folder', fqName: 'A sampai Z', fqSize: 'Terbesar dulu', fqTop: 'Folder user', fqSys: 'Riwayat Windows (registry, Recycle Bin...)',
    fqShown: function (n, t) { return n + ' dari ' + t + ' ditampilkan'; }, fqNone: 'Tidak ada yang cocok.',
    gHelp: 'Update dan bantuan', gExit: 'Saat meninggalkan PC', gPrivacy: 'Privasi dan Windows', gApps: 'Program', gLocks: 'Kunci',
    yes: 'Ya', no: 'Tidak',
    encTitle: 'Enkripsi disk',
    encOn: 'BitLocker / enkripsi perangkat menyala. Bagus: folder Keep kamu ikut terlindungi saat PC mati.',
    encOff: 'BitLocker / enkripsi perangkat mati, atau drive sudah terenkripsi tapi perlindungannya mati (belum ada kunci). Amnesia tidak mengenkripsi folder Keep, jadi nyalakan enkripsi: Settings → Privacy & security → Device encryption (atau BitLocker).',
    encPaused: 'BitLocker sedang dijeda. Nyalakan lagi di Control Panel → BitLocker.',
    encUnknown: 'Amnesia tidak bisa membaca status enkripsi. Cek sendiri: Settings → Privacy & security → Device encryption, atau Control Panel → BitLocker. (Sering terjadi di VM.)',
    histTitle: 'Riwayat', histEmpty: 'Belum ada. Setelah sign out pertama dengan Amnesia menyala, riwayatnya muncul di sini.',
    hClean: function (d) { var p = d.split(' '); return (p[0] === 'login' ? 'Cek saat login' : p[0] === 'logout' ? 'Sign out' : 'Pembersihan') + ': ' + (p[1] || 0) + ' item' + (+p[2] > 0 ? ', ' + size(+p[2]) : ''); },
    hPaused: function (d) { return 'Dilewati (jeda): ' + (d === 'login' ? 'login' : 'sign out'); },
    hSnapshot: function (d) { return (d.indexOf('auto:') === 0 ? 'Snapshot otomatis: ' + d.slice(5) : 'Snapshot: ' + d); },
    hRestore: function (d) { return d === 'backup' ? 'Dipulihkan dari backup' : 'Dipulihkan: ' + d; },
    hBackup: function (d) { var p = d.split(' '); return 'Backup (' + (p[0] === 'ssh' ? 'server' : 'folder') + ')' + (p[1] ? ', ' + p[1] + ' file sedang dipakai tidak ikut' : ''); },
    hDoom: function (d) { return 'Doomsday: vault dihapus' + (d === 'keep' ? ' + Keep dikosongkan' : ''); },
    hQuick: function (d) { return 'Sign out cepat (' + d + ')'; },
    hApps: function (d) { var p = d.split(' '); return p[1] + ' app baru dihapus'; },
    hAppKeep: function (d) { var p = d.split(' '); return p[0] + ' app baru disimpan, ' + (p[1] || 0) + ' folder masuk Keep List'; },
    hLeft: function (d) { return d + ' sisa app dihapus'; }, hSys: function () { return 'Jejak Windows dibersihkan (admin)'; }, hWipe: function (d) { return 'Hapus ruang kosong dimulai di ' + d; },
    hBlocked: function (d) { return d + ' item diblok Windows Security / antivirus'; },
    hVault: function () { return 'Vault dibuat'; },
    // v0.8
    hPause: function () { return 'Dijeda untuk satu sesi'; }, hResume: function () { return 'Jeda dibatalkan'; },
    ksTitle: 'Folder Keep masih terkunci', ksText: 'Versi Amnesia yang lama meninggalkan kuncinya di folder Keep, padahal kunci Keep sudah mati. Buka lagi di sini.',
    ksOpen: 'Buka Keep', ksPw: 'Password Keep yang lama', ksDone: 'Keep sudah terbuka lagi.',
    suTitle: 'Amnesia tidak ikut menyala bersama Windows', suText: 'Startup-nya dimatikan (Task Manager > Startup apps). Akibatnya tidak ada yang dihapus saat login berikutnya dan ikon tray hilang. Nyalakan lagi di sini.', suFix: 'Nyalakan lagi',
    healthTitle: 'Cek kesehatan', healthText: 'Apakah Amnesia bisa bekerja sekarang? Baris kuning dan merah menunjukkan yang perlu dicek.', hlAgain: 'Cek lagi',
    hlAllOk: 'Semua aman', hlIssues: function (n) { return n + ' hal perlu dicek'; },
    hl: {
      on: { ok: 'Amnesia menyala.', warn: 'Dijeda: login berikutnya dilewati.', bad: 'Amnesia mati: tidak ada yang dihapus.' },
      startup: { ok: 'Ikut menyala bersama Windows.', bad: 'Startup dimatikan di Windows. Tekan "Nyalakan lagi" di halaman utama.', info: 'Belum terpasang (nyalakan dulu).' },
      lastClean: { ok: function (d) { return 'Pembersihan terakhir: ' + d + '.'; }, warn: 'Belum pernah ada pembersihan. Coba sign out sekali.', info: 'Belum ada pembersihan.' },
      trash: { ok: 'Tidak ada file yang tertinggal.', warn: function (d) { return d + ' kelompok file yang sempat dipakai Windows masih menunggu. Login berikutnya mencoba lagi.'; } },
      blocked: { ok: 'Windows Security tidak memblok apa pun.', warn: 'Windows Security atau antivirus memblok item di pembersihan terakhir. Lihat kartu di halaman utama.' },
      cloud: { info: function (d) { return d ? 'Folder cloud dibiarkan apa adanya (supaya file di cloud tetap aman): ' + d + '.' : 'Tidak ada folder sync cloud (OneDrive, Dropbox, Google Drive... tidak disentuh kalau ada).'; } },
      vm: { ok: 'Virtual machine dan image disk besar tetap aman.', warn: 'Virtual machine ikut dihapus seperti file lain (Pengaturan > Perlindungan).' },
      keepLock: { ok: 'Keep dikunci dengan password.', info: 'Keep tidak dikunci (opsional, Pengaturan > Kunci).', bad: 'Keep masih dikunci versi lama. Buka di halaman utama.' },
      vault: { ok: function (d) { return 'Snapshot vault terbaru: ' + d + '.'; }, warn: 'Vault belum punya snapshot.', info: 'Tidak ada vault (opsional).' },
      backup: { ok: function (d) { return 'Backup terakhir: ' + d + '.'; }, warn: 'Belum ada backup baru. Kalau PC ini rusak, Keep dan vault ikut hilang.', info: 'Backup belum diatur (opsional).' },
      hotkey: { ok: function (d) { return 'Tombol panik: ' + d + '.'; }, info: 'Belum ada tombol panik (opsional, Pengaturan).' },
      updates: { ok: 'Update dicek dengan tanda tangan developer.', info: 'Versi ini belum punya kunci update: update membuka halaman rilis, tidak terpasang sendiri.' }
    },
    limTitle: 'Yang tidak bisa dilakukan Amnesia', limText: 'Batasan jujur, supaya kamu tahu bagian mana yang masih perlu hati-hati.',
    lim: [
      'Windows menyimpan sedikit jejak di luar folder user (Program Files, ProgramData, event log, daftar program yang pernah dijalankan). Pengaturan > Jejak Windows (admin) membersihkan sebagian.',
      'Menghapus berarti memindahkan lalu menghapus file, bukan menimpa disk. Tanpa BitLocker atau enkripsi perangkat, file yang dihapus bisa dikembalikan dengan tools. Nyalakan enkripsi perangkat.',
      'Password tersimpan di Credential Manager tetap ada, kecuali kamu nyalakan "Hapus juga password app". Login akun Microsoft, OneDrive dan Office selalu tetap ada.',
      'App Microsoft Store menyimpan datanya di Packages. Data itu tetap ada, kecuali kamu nyalakan "Hapus juga data app Store".',
      'File yang sedang dipakai Windows saat sign out akan dihapus saat login berikutnya.',
      'Cache thumbnail Explorer dibersihkan saat sign out dan sign out cepat, bukan saat kamu sedang login (dulu bikin Desktop berkedip).',
      'Vault dan backup sekuat password kamu. Doomsday menghapus vault di PC ini, bukan salinan yang dibuat orang lain sebelumnya.',
      'Login browser di snapshot terkunci ke user Windows ini. Di PC baru mungkin kamu perlu login lagi.',
      'Amnesia tidak punya sertifikat code signing berbayar, jadi SmartScreen bisa memberi peringatan. Cocokkan SHA256 di halaman rilis.'
    ],
    kaTitle: 'Simpan sebuah app', kaText: 'Pilih app yang terpasang: Amnesia menyimpan semua folder tempat app itu menaruh datanya (login, pengaturan).', kaPh: 'Cari app', kaEmpty: 'Tidak ada app terpasang dengan folder data sendiri.', kaKeep: 'Simpan', kaKept: 'Disimpan', kaStore: 'App Store',
    protTitle: 'Perlindungan', oalTitle: 'Buka saat login', oalText: 'Menampilkan ikon tray setelah login, juga saat Amnesia mati.',
    vmTitle: 'Simpan virtual machine', vmText: 'Disk VirtualBox, Hyper-V, VMware, WSL dan emulator Android, juga image disk di atas 1 GB, tetap di tempatnya.',
    wsTitle: 'Hapus juga data app Store', wsText: 'Mati: app Microsoft Store tetap menyimpan datanya. Nyala: datanya ikut dihapus (bukan app bawaan Windows, bukan yang ada di Keep List).',
    wcTitle: 'Hapus juga password app', wcText: 'Menghapus password yang disimpan app di Credential Manager (git, beberapa app chat). Tidak pernah akun Microsoft, OneDrive atau Office.',
    cloudNote: 'Folder cloud (OneDrive, Dropbox, Google Drive, iCloud...) tidak pernah dihapus: memindahkannya akan ikut menghapus file kamu di cloud.',
    unPw: 'Password Keep (Keep sedang dikunci)',
    unSafe: function (n) { return (n > 0 ? 'Brankas kamu masih berisi ' + n + ' file.' : 'Brankas kamu masih berisi file.') + ' Buka dan pindahkan dulu, atau biarkan: brankas bisa dibuka lagi setelah kamu memasang Amnesia lagi. Tetap uninstall?'; },
    unSafeAll: function (n) { return (n > 0 ? 'Brankas kamu masih berisi ' + n + ' file.' : 'Brankas kamu masih berisi file.') + ' Menghapus semuanya juga menghapus brankas untuk selamanya. Buka dan pindahkan dulu. Tetap lanjut?'; },
    sbTitle: 'Brankas (eksperimen)', sbText: 'Folder terkunci di dalam Keep untuk file paling pribadi. Saat tertutup, isinya cuma satu file terkunci; saat dibuka, ada di Keep\\Safe. Amnesia menutupnya lagi setiap sign out. Isinya jangan terlalu besar: menutup berarti mengemas semuanya lagi.',
    sbPwPh: 'Password brankas (minimal 12 karakter)', sbCreate: 'Buat brankas', sbOpen: 'Buka', sbShow: 'Tampilkan di Explorer', sbClose: 'Tutup dan kunci',
    sbNone: 'Belum ada brankas.', sbIsOpen: function (d) { return 'Terbuka di ' + d + '. Tertutup sendiri saat sign out.'; }, sbIsClosed: function (n) { return 'Tertutup dan terkunci (' + n + ').'; },
    sbOpened: function (n) { return n + ' file dibuka.'; }, sbClosedNow: function (n) { return 'Terkunci lagi (' + n + ' file).'; },
    vSuggText: 'Ada di PC ini, belum masuk vault. Klik salah satu untuk menambah foldernya:',
    meter: ['Terlalu pendek', 'Lemah: komputer cepat bisa menebaknya', 'Lumayan, lebih panjang lebih baik', 'Kuat'],
    bSkipped: function (n) { return n + ' file sedang dipakai dan tidak masuk backup ini. Tutup app-nya lalu backup lagi.'; },
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
    vStep1: 'Pilih app yang disimpan', vStep2: 'Simpan login sekarang', vStep3: 'Kembalikan setelah login',
    vStep2Note: 'Tanpa password. App ditutup sebentar.', vChange: 'Ubah...', vChangeDone: 'Selesai',
    vNoneChosen: 'Belum ada app yang dipilih.', vMore: function (n) { return ' dan ' + n + ' lainnya'; },
    vLastSaved: function (t, n, s) { return 'Terakhir disimpan ' + t + ' · ' + n + ' tersimpan' + (s ? ' · ' + s : ''); }, vNotSaved: 'Belum disimpan. Login ke app dulu, lalu tekan Snapshot sekarang.',
    vMainTitle: 'Pulihkan atau simpan login', vMainText: 'Snapshot sekarang menyimpan app yang dipilih (tanpa password, app ditutup sebentar). Pulihkan mengembalikannya; data app yang ada sekarang dipindah ke Temp dulu.',
    vAppsFold: 'Pilih app dan folder, lihat tiap snapshot', vOptsFold: 'Snapshot otomatis, pengingat, password, kata panik',
    infoShow: 'Info', infoAbout: 'Tentang: ',
    vSnap: 'Snapshot sekarang', vAddFolder: 'Tambah folder...', vNever: 'belum ada snapshot', vNotHere: 'belum terpasang di sini', vDelete: 'Hapus snapshot',
    vRestoreTitle: 'Pulihkan', vRestoreText: 'Mengembalikan semua app yang punya snapshot. Data app yang ada sekarang dipindah ke Temp dulu (terhapus saat sign out berikutnya).',
    vPwPh: 'Password vault', vRestore: 'Pulihkan', vRestored: function (n) { return 'Kembali: ' + n.join(', ') + '. Buka app-nya, kamu sudah login lagi.'; },
    vRestoreIssue: function (name, v) { return v === 'failed' ? name + ' tidak bisa dikembalikan (snapshot-nya tetap ada di vault).' : name + ': ' + v.split(':')[1] + ' file sedang dipakai dan dibiarkan seperti semula.'; },
    vOptions: 'Pilihan vault', vAuto: 'Snapshot otomatis', vAutoText: 'App yang berubah disimpan otomatis setelah kamu menutupnya, di latar belakang (tidak pernah saat app masih jalan). Sign out cuma membersihkan, jadi cepat.',
    vRemind: 'Ingatkan setelah login', vRemindText: 'Notifikasi setiap habis login: klik untuk memulihkan.',
    vDoom: 'Doomsday setelah 3 password salah', vDoomText: 'Tiga password salah berturut-turut menghapus vault di PC ini selamanya. Mati = tanpa batas. Ini tidak bisa menghentikan orang yang sudah menyalin file vault sebelumnya, jadi password yang panjang adalah pelindung utamanya.',
    vChangePw: 'Ganti password', vOldPh: 'Password sekarang', vNewPh: 'Password baru (12+ karakter)', vChangePanic: 'Ganti kata panik', vPanicPh: 'Kata panik baru (kosong = tidak ada)',
    save: 'Simpan', saved: 'Tersimpan.', working: 'Sedang dikerjakan...', done: 'Selesai.',
    vSaved: function (t) { return 'Disimpan ' + t; },
    vRestorePrev: 'Pakai snapshot sebelum yang terbaru (kalau yang terbaru terlihat salah)',
    // v0.10 profil vault
    vpLabel: 'Memory Recall: profil', vpEdit: 'Ubah', vpNew: 'Profil baru', vpNewTitle: 'Profil baru', vpEditTitle: 'Ubah profil', vpName: 'Nama',
    vpAppsText: 'Centang app yang dikembalikan profil ini. Snapshot tetap satu per app, jadi satu app bisa ada di lebih dari satu profil.',
    vpDelete: 'Hapus profil', vpDeleteAsk: function (n) { return 'Hapus profil "' + n + '"? Snapshot-nya tetap ada di vault.'; },
    vpRestores: function (a) { return 'Dikembalikan: ' + a.join(', ') + '.'; }, vpEmpty: 'Profil ini belum punya app. Klik Ubah untuk menambahkan.',
    vpNoSnap: function (a) { return 'Belum ada snapshot: ' + a.join(', ') + '.'; }, vpNotHere: function (a) { return 'Tidak ada di PC ini: ' + a.join(', ') + '.'; },
    vpShared: function (app, a, b) { return app + ' ada di ' + a + ' dan ' + b + '. Satu browser menyimpan satu kumpulan login, jadi restore profil mana pun mengembalikan semuanya. Untuk pemakaian pribadi, browser kedua (atau profil browser terpisah) membuatnya terpisah.'; },
    vpFull: 'Retrograde Amnesia: login tidak disimpan saat sign out. Snapshot masih bisa di-restore manual.',
    vpIgnored: function (a) { return 'Dilewati, tidak ada di vault: ' + a.join(', ') + '.'; }, vpNoApps: 'Belum ada app vault di PC ini.',
    vpErr: { 'no-snapshot-profile': 'Belum ada snapshot untuk app-app ini.', 'profile-name': 'Beri profil nama 1 sampai 40 karakter.',
      'profile-name-reserved': 'Nama itu dipakai untuk "Semua". Pilih nama lain.', 'profile-name-taken': 'Sudah ada profil dengan nama itu.',
      'profile-too-many': 'Kamu sudah punya 20 profil, jumlah paling banyak. Hapus satu dulu.' },
    vPrev: function (t) { return 'sebelumnya: ' + t; }, vShrunk: 'jauh lebih kecil dari sebelumnya, coba cek', vSetup: 'setup browser belum selesai di snapshot ini',
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
    aKept: 'Disimpan. Folder-nya sudah masuk Keep List, jadi app-nya tetap jalan setelah sign out.',
    aUninstalling: 'Menunggu uninstaller selesai... Daftarnya diperbarui sendiri setelah itu.',
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
    xlDone: 'Daftar sudah diunduh.', sxTitle: 'Windows sekali pakai', sxText: 'Membuka Windows Sandbox: Windows baru di dalam jendela. Coba file atau website yang mencurigakan di sana; semuanya hilang saat ditutup. Ide dari Sandboxie.',
    sxKeep: 'Tampilkan folder Keep di dalamnya (hanya baca)', sxNet: 'Internet di dalam sandbox', sxOpen: 'Buka Windows sekali pakai',
    sxMissing: 'Windows Sandbox belum aktif. Butuh Windows Pro atau Enterprise dan virtualisasi (di dalam VM sering tidak bisa). Aktifkan "Windows Sandbox" di Windows features, lalu restart.',
    sxFeatures: 'Buka Windows features',
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
    linksOff: 'Amnesia sedang mati, jadi ini baru muncul setelah dinyalakan.',
    klkTitle: 'Kunci Keep', klkText: 'Folder Keep hanya bisa dibuka lewat Amnesia, dengan password sendiri. Terkunci lagi saat layar dikunci (Win+L), setelah menit yang kamu pilih, saat sign out dan saat sign in. Selama terkunci, tidak ada program yang bisa membuka atau menulis file di Keep (script tes juga tidak), dan Keep hilang dari sidebar Explorer sampai kamu membukanya.',
    klkHonest: 'Catatan jujur: file-nya tidak dienkripsi (pakai BitLocker untuk itu), dan nama file-nya tetap kelihatan saat terkunci. Orang yang login sebagai kamu dan paham Windows masih bisa melepas kunci lewat Properties folder. Lupa password? Caranya sama: Properties, Security, hapus baris "Deny".',
    klkPwPh: 'Password Keep', klkPw2Ph: 'Ulangi password', klkAfter: 'Kunci lagi setelah', klkOn: 'Nyalakan kunci Keep', klkNow: 'Kunci sekarang', klkOff: 'Matikan (password)',
    klkLocked: 'Keep terkunci. Buka lewat Buka Keep, menu tray, atau shortcut di Desktop.', klkOpen: 'Keep sedang terbuka. Nanti terkunci lagi sendiri.', klkAsk: 'Password Keep',
    labTitle: 'Kunci lab (untuk admin)', labText: 'Untuk PC yang dipakai banyak orang, seperti lab komputer atau perpustakaan. Dengan PIN, user Windows ini tidak bisa lagi mematikan, menjeda, menutup, meng-uninstall Amnesia, atau mengubah pengaturan dan Keep List. Menyalakan atau mematikannya minta izin admin sekali.',
    labHonest: 'Catatan jujur: orang masih bisa mematikan Amnesia di Task Manager, tapi cek saat sign in berikutnya tetap membersihkan. Atur pengaturan dan Keep List dulu, semuanya dikunci seperti sekarang.',
    labPinPh: 'PIN (minimal 6 angka)', labPin2Ph: 'Ulangi PIN', labOn: 'Kunci dengan PIN ini', labUnlock: 'Buka 10 menit', labSave: 'Simpan perubahan dan kunci lagi', labClose: 'Kunci lagi sekarang', labOff: 'Lepas kunci lab',
    labState: function (t) { return 'Dikunci admin' + (t ? ' sejak ' + t : '') + '.'; }, labOpenNow: 'Terbuka dengan PIN selama 10 menit. Ubah yang perlu, lalu tekan Simpan perubahan dan kunci lagi.',
    labBar: 'Dikunci admin. Kamu bisa melihat-lihat; perubahan butuh PIN admin (Pengaturan → Kunci lab).', pinMismatch: 'Kedua isian tidak sama.',
    upTitle: 'Update', upCheck: 'Cek sekarang', upAuto: 'Cek otomatis', upAutoText: 'Cuma menanyakan nomor versi terbaru ke GitHub. Kamu yang memutuskan kapan dipasang.',
    upOff: 'Tidak pernah (hanya saat tekan Cek sekarang)', upWeek: 'Tiap minggu', up2Weeks: 'Tiap 2 minggu', upMonth: 'Tiap bulan',
    upInstall: 'Pasang update',
    upNone: function (c) { return 'Kamu sudah pakai versi terbaru (' + c + ').'; },
    upNo: function (c) { return 'Belum ada rilis Windows di GitHub. Versi kamu ' + c + '.'; },
    upNew: function (l, c) { return 'Amnesia ' + l + ' sudah keluar (punyamu ' + c + ').'; },
    upPortable: 'Salinan ini tidak dipasang lewat Setup.exe: unduh versi baru dari website.',
    upChecking: 'Sedang mengecek...', checksum: 'File unduhan tidak cocok dengan checksum-nya dan sudah dihapus. Coba lagi nanti.',
    logTitle: 'Kumpulkan log', logText: 'Ada yang tidak jalan? Ini membuat satu file teks (amnesia-log.txt di folder Keep kamu) lalu membukanya di Notepad. Isinya langkah Amnesia dan error Windows, tanpa nama file. Tidak ada yang dikirim.',
    logBtn: 'Kumpulkan log', logOpened: 'Log sedang dibuat, sebentar lagi Notepad terbuka.',
    logBusy: 'Sedang mengumpulkan log... (bisa sampai semenit)', logDone: function (p) { return 'Selesai: ' + p + ' (sudah dibuka di Notepad).'; }, logMissing: 'Log-nya gagal dibuat. Coba lagi, atau lihat trace.log di %USERPROFILE%\\.amnesia.',
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
      ['Coba dengan aman', 'Tekan "Lihat simulasi" dulu: isinya cuma daftar yang akan hilang.']
    ],
    tourNext: 'Lanjut', tourDone: 'Ayo mulai', tourSkip: 'Lewati',
    err: {
      'short-password': 'Password minimal 12 karakter.', 'panic-same': 'Kata panik tidak boleh sama dengan password.',
      'lab-locked': 'Dikunci admin. Buka dulu dengan PIN admin di Pengaturan → Kunci lab.', 'lab-pin-short': 'PIN minimal 6 angka.', 'lab-pin-wrong': 'PIN salah.', 'admin-no': 'Windows tidak mendapat izin admin (pertanyaannya dijawab No).', 'keeplock-short': 'Password Keep minimal 4 karakter.', 'keeplock-wrong': 'Password Keep salah.',
      'no-vault': 'Buat vault dulu.', 'nothing': 'Pilih minimal satu app yang ada di PC ini.', 'no-snapshot': 'Belum ada snapshot. Buat dulu.', 'restore-failed': 'Tidak ada yang bisa dikembalikan. Snapshot kamu tetap aman di vault. Tutup app-nya (juga di Task Manager), lalu coba lagi.',
      'doomsday': 'DOOMSDAY: vault sudah dihapus.', 'outside-home': 'Hanya folder di dalam folder user kamu.', 'backup-in-home': 'Folder itu ada di dalam folder user kamu dan akan terhapus saat sign out. Pilih flashdisk, drive lain, folder cloud atau folder di dalam Keep.',
      'hotkey-taken': 'Tombol ini sudah dipakai app lain. Pilih yang lain.', 'admin-no': 'Windows tidak mendapat izin admin, tidak ada yang berubah.',
      'checksum': 'File unduhan tidak cocok dengan checksum-nya dan sudah dihapus. Coba lagi nanti.', 'busy': 'Pekerjaan lain masih berjalan.', 'cancelled': 'Dihentikan.',
      'destination-missing': 'Folder backup tidak ada (flashdisk dicabut?).', 'no-destination': 'Pilih tempat backup dulu.',
      'no-file': 'Pilih file backup dulu.', 'not-a-backup': 'Itu bukan file backup Amnesia.', 'no-release': 'Belum ada rilis Windows di GitHub.',
      'offline': 'Tidak bisa terhubung ke GitHub. Cek koneksi internet.', 'list-bad': 'Daftar yang diunduh tidak terlihat benar dan tidak dipakai.', 'sandbox-missing': 'Windows Sandbox belum aktif.', 'no-safe': 'Buat brankas dulu.', 'safe-exists': 'Brankas sudah ada.',
      'keeplock-uninstall': 'Keep sedang dikunci. Isi password Keep di atas dulu: Amnesia membuka kunci Keep sebelum dihapus.', 'pause-not-saved': 'Jeda gagal disimpan. Coba lagi.', 'backup-in-keep': 'Jangan di dalam Keep: setiap backup nanti ikut berisi semua backup lama. Pilih flashdisk, drive lain atau folder cloud.', 'keep-not-saved': 'Baris itu tidak tersimpan di Keep List. Coba lagi, atau tambahkan foldernya lewat Pilih folder.', 'unsigned': 'Rilis ini belum punya tanda tangan developer, jadi tidak dipasang dari app. Buka halaman rilis saja.', 'bad-signature': 'Tanda tangan rilis tidak cocok. Tidak ada yang dipasang. Kabari developer (GitHub issue).'
    },
    wrong: function (left) { return left < 0 ? 'Password salah.' : left === 1 ? 'Password salah. PERCOBAAN TERAKHIR: salah sekali lagi = vault DIHAPUS PERMANEN. Berhenti dulu dan cek catatan password kamu.' : 'Password salah. Sisa percobaan: ' + left; },
    // v0.9 Perawatan
    careTitle: 'Perawatan', tCareSub: 'Kosongkan ruang dengan aman, lihat daftarnya dulu',
    careIntro: 'Kosongkan ruang kapan saja, selalu dengan daftar untuk dicek dulu. Amnesia sudah menghapus sebagian besar folder user kamu saat sign out, jadi Perawatan paling berguna untuk folder Keep, app yang kamu simpan dan file besar dari sesi ini. Tidak ada yang berisiko dicentang untukmu, dan link tidak pernah diikuti.',
    // v0.10 Mode Amnesia
    mdTitle: 'Mode Amnesia', mdText: 'Seberapa banyak yang dilupakan PC kamu setiap sign out. Selalu ada pratinjau dulu, dan mode baru berlaku mulai sign out berikutnya.',
    mdNames: { full: 'Retrograde Amnesia', balanced: 'Selective Amnesia (disarankan)', light: 'Partial Amnesia', custom: 'Custom Amnesia' },
    mdSubs: {
      full: 'Seperti akun baru setiap sign in. Hanya folder Keep kamu dan yang dibutuhkan Amnesia yang tetap ada.',
      balanced: 'Folder Keep tetap ada, login app kembali dari vault, dan baris Keep List kamu sendiri tetap ada.',
      light: 'App tetap menyimpan pengaturan dan loginnya. File kamu, Desktop, Documents dan Downloads dihapus.',
      custom: 'Keep List buatan kamu sendiri. Dipilih otomatis saat kamu mengubah baris dari sebuah mode.'
    },
    mdLightNote: 'Partial Amnesia menyimpan seluruh AppData. Riwayat dan cookie browser di dalam folder browser itu sendiri juga tetap ada (Edge juga), begitu juga file Temp, daftar file terakhir dan riwayat PowerShell, karena semuanya ada di dalam AppData. Cache thumbnail dan ikon, riwayat notifikasi, Recycle Bin, clipboard dan daftar terakhir di registry tetap dihapus.',
    mdNow: 'Sekarang', mdFullVault: 'Retrograde Amnesia: login tidak disimpan saat sign out. Snapshot masih bisa di-restore manual.',
    msTitle: function (m) { return 'Ganti ke ' + m + '?'; }, msBusy: 'Sedang melihat apa yang dilakukan sign out berikutnya...',
    msWiped: 'Mulai sekarang dihapus saat sign out', msKept: 'Mulai sekarang disimpan', msIdle: 'Keluar dari Keep List, tidak ada yang dihapus di sana', msOwn: 'Baris kamu sendiri (tidak diubah)', msStop: 'Berhenti menyimpan baris ini juga',
    msCount: function (a, b) { return 'Sign out berikutnya: ' + a + ' item dihapus (sekarang ' + b + ').'; },
    msWarn: 'Mode ini menghapus lebih banyak dari mode sekarang. Pindahkan dulu yang masih kamu perlukan ke folder Keep.',
    msAutoOff: 'Snapshot otomatis saat sign out dimatikan. Snapshot kamu tetap ada dan masih bisa di-restore manual.',
    msAutoOn: 'Snapshot otomatis saat sign out dinyalakan lagi.',
    msWhen: 'Berlaku mulai sign out berikutnya. Sekarang tidak ada yang dihapus.',
    msToCustom: 'Baris yang kamu centang adalah bagian dari mode ini, jadi Keep List kamu menjadi Custom Amnesia.',
    msSame: 'Yang dihapus tetap sama.', msLineK: 'baris', msItemK: 'item',
    msPreset: function (m) { return 'Preset ' + m + ' tidak bisa dibaca, jadi Keep List kamu tidak diubah.'; },
    msSwitch: 'Ganti mode', msDone: function (m) { return 'Mode sekarang ' + m + '. Berlaku mulai sign out berikutnya.'; },
    mdErr: {
      'mode-broken': 'Bagian mode di Keep List kamu rusak, jadi mode tidak diganti. Perbaiki atau hapus baris yang diawali "# amnesia-mode".',
      'mode-stopped': 'Keep List kamu tidak bisa dibaca, jadi mode tidak diganti. Cek Keep List dulu.',
      'mode-lab': 'Kunci lab sedang aktif, jadi hanya administrator yang bisa mengubah Keep List.',
      'mode-changed': 'Keep List berubah sejak pratinjau. Lihat pratinjaunya lagi.',
      'mode-rescan': 'Keep List berubah sejak pratinjau. Lihat pratinjaunya lagi.',
      'mode-write': 'Keep List tidak bisa disimpan. Tidak ada yang diubah. Coba lagi.', 'mode-unknown': 'Mode tidak dikenal.'
    },
    hMode: function (d) { var p = (d || '').split(' '); return 'Mode diganti: ' + (ID.mdNames[p[1]] || p[1] || ''); },
    // v0.10 Tanya AI
    aiTitle: 'Tanya AI', tAiSub: 'Minta saran tanpa membagikan file kamu',
    aiIntro: 'Amnesia membuat laporan tentang PC ini tanpa isi file dan tanpa nama file kamu, plus pertanyaan siap pakai. Tempel keduanya ke AI pilihanmu. Lalu tempel jawabannya di bawah dan centang perubahan yang kamu mau.',
    aiNever: 'Amnesia tidak pernah mengirim apa pun. Kamu yang memilih mau ditempel ke mana.',
    aiHide: 'Sembunyikan nama folder', aiMake: 'Buat laporan lagi', aiCopy: 'Salin laporan dan prompt', aiSave: 'Simpan ke folder Keep',
    aiBusy: 'Sedang membuat laporan (bisa sampai semenit)...', aiReady: 'Laporan siap. Lihat dulu apa yang akan dibagikan sebelum kamu tempel.',
    aiCopied: 'Tersalin. Tempel ke AI pilihanmu.', aiCopyFail: 'Tidak bisa menyalin. Buka "Lihat apa yang akan dibagikan", pilih teksnya lalu salin manual.',
    aiSaved: function (p) { return 'Tersimpan: ' + p; }, aiShow: 'Lihat apa yang akan dibagikan',
    aiPasteTitle: 'Tempel jawaban AI', aiPasteText: 'Tempel seluruh jawabannya. Amnesia hanya membaca blok amnesia-suggestion dan mengecek setiap baris. Tidak ada yang berubah sampai kamu konfirmasi.',
    aiPastePh: 'Tempel jawaban AI di sini', aiRead: 'Baca jawabannya',
    aiErr: {
      'no-block': 'Blok amnesia-suggestion tidak ditemukan. Minta AI menutup jawabannya dengan blok dari prompt.',
      'bad-json': 'Bloknya bukan JSON yang benar. Minta AI menulisnya lagi.',
      'not-object': 'Bloknya harus satu objek { ... }. Minta AI menulisnya lagi.',
      'too-big': 'Jawabannya terlalu panjang (maksimal 64 KB).'
    },
    aiNone: 'Jawabannya tidak menyarankan perubahan apa pun.',
    aiMode: function (m) { return 'Ganti mode ke ' + m; }, aiAdd: function (p) { return 'Simpan: ' + p; }, aiRemove: function (p) { return 'Berhenti menyimpan: ' + p; },
    aiProf: function (n, apps, upd) { return (upd ? 'Ubah profil vault ' : 'Profil vault baru ') + n + ': ' + (apps.length ? apps.join(', ') : '(tanpa app)'); },
    aiNotes: 'Catatan dari AI', aiNotUsed: 'Tidak dipakai', aiIgnored: function (a) { return 'App yang tidak ada di vault, diabaikan: ' + a.join(', '); },
    aiWhy: {
      'absolute': 'tidak di dalam folder user kamu', 'dots': 'ada bagian .. atau .', 'amnesia': 'folder milik Amnesia', 'in-keep': 'sudah di dalam folder Keep',
      'too-wide': 'terlalu luas (hanya wildcard)', 'tag': 'bukan path', 'control': 'karakter aneh', 'too-long': 'terlalu panjang', 'empty': 'kosong', 'not-text': 'bukan teks',
      'already-kept': 'sudah disimpan', 'not-on-list': 'tidak ada di Keep List', 'required': 'dibutuhkan Amnesia', 'unknown-mode': 'mode tidak dikenal',
      'reserved-name': 'nama itu dipakai "Semua"', 'bad-name': 'nama kosong atau terlalu panjang', 'too-many': 'lebih dari 10 profil', 'duplicate': 'tertulis dua kali',
      'not-a-list': 'bukan daftar', 'not-an-object': 'bukan daftar profil'
    },
    aiApply: 'Tinjau perubahan', aiNoTick: 'Centang minimal satu perubahan dulu.',
    aiProfAsk: function (n) { return 'Simpan ' + n + ' profil vault? Keep List kamu tidak berubah.'; },
    aiProfDone: function (n) { return n + ' profil vault tersimpan.'; }, aiProfFail: 'Profil vault tidak bisa disimpan.',
    aiApplied: 'Selesai. Perubahan Keep List berlaku mulai sign out berikutnya.',
    cOvTitle: 'Ringkasan disk', cOvText: 'Apa yang memakan ruang di PC ini. Hanya dilihat, tidak ada yang dihapus.', cLook: 'Lihat',
    cScan: 'Pindai', cAgain: 'Pindai lagi', cBusy: 'Sedang mencari... (paling lama 30 detik)', cWorking: 'Sedang dikerjakan...',
    cDisk: function (f, t) { return size(f) + ' kosong dari ' + size(t); },
    cSizes: { keep: 'Folder Keep', vault: 'Vault', atrash: 'Tempat sampah Amnesia', bin: 'Recycle Bin', temp: 'File Temp', downloads: 'Downloads' },
    cFolders: 'Folder terbesar', cFiles: 'File besar (200 MB ke atas)', cNoFiles: 'Tidak ada file 200 MB ke atas di Keep, Downloads atau Desktop.',
    cOld: function (n, b) { return n + ' file di Downloads tidak berubah selama 30 hari (' + size(b) + '). File ini tetap terhapus saat sign out berikutnya, kecuali ada di Keep List.'; },
    cShow: 'Tampilkan', cAtLeast: 'minimal ',
    cQuickTitle: 'Bersihkan sekarang', cQuickText: 'File Temp yang lebih lama dari sehari, crash dump, cache app dan tempat sampah Amnesia. App membuat cache-nya lagi saat perlu. Recycle Bin ikut ditampilkan, tapi tidak pernah dicentang untukmu.',
    cAppsTitle: 'Hapus app', cAppsText: 'Program yang dipasang khusus untukmu menjalankan uninstaller-nya sendiri, tanpa password admin. Program untuk semua user dan app Store membuka Pengaturan Windows. Sisa app dipindah ke Recycle Bin; data kamu di dalamnya hanya ikut kalau kamu centang.',
    cAppsBtn: 'Tampilkan program', cAppsPh: 'Cari program', cKind: { user: 'khusus untukmu', machine: 'untuk semua user', store: 'Microsoft Store' },
    cUninstall: 'Uninstall', cOpenApps: 'Buka Pengaturan Windows', cNoPrograms: 'Tidak ada program.',
    cUnConfirm: function (n) { return 'Jalankan uninstaller ' + n + '? Mungkin ada pertanyaan dari uninstaller-nya. Setelah itu Amnesia mencari sisa yang ditinggalkan.'; },
    cUnGone: function (n) { return n + ' sudah di-uninstall.'; }, cUnStill: function (n) { return n + ' masih terpasang, jadi Amnesia tidak mencari sisanya.'; },
    cUnNoLeft: 'Tidak ada sisa yang ditemukan.', cUnLeft: 'Ini sisa yang ditinggalkan. Centang yang mau dibuang:', cSkip: 'Biarkan saja',
    cProjTitle: 'Folder build project', cProjText: 'node_modules, target, build, dist, bin, obj dan lainnya, di folder project dan Keep. Semuanya bisa dibuat ulang. Folder yang dipakai 7 hari terakhir tidak dicentang; folder yang dilacak git atau berisi kunci tidak disentuh. Dipindah ke Recycle Bin.',
    cInsTitle: 'Installer lama', cInsText: 'File .msi dan .msix yang lebih lama dari 14 hari di Downloads, Desktop dan Keep. File setup .exe dan .zip serta image disk ditampilkan tapi tidak pernah dicentang untukmu. Mesin virtual dan image disk tidak pernah ditampilkan. Dipindah ke Recycle Bin.',
    cTuneTitle: 'Perawatan ringan', cTuneText: 'Perbaikan kecil tanpa password admin.',
    cTuneExplorer: 'Mulai ulang Explorer', cTuneExplorerSub: 'Membantu kalau taskbar atau Desktop macet. Jendela folder yang terbuka ikut tertutup.',
    cTuneRun: 'Jalankan', cTuneNone: 'Centang salah satu dulu.', cTuneAsk: 'Mulai ulang Explorer sekarang? Taskbar hilang beberapa detik dan jendela folder yang terbuka tertutup.',
    cTuneRes: function (ok) { return 'Mulai ulang Explorer: ' + (ok ? 'selesai.' : 'dilewati, tidak berhasil.'); },
    cOpenStartup: 'Buka Startup apps', cOpenStorage: 'Buka pengaturan Storage',
    cCat: { temp: 'File Temp', crash: 'Crash dump', cache: 'Cache app', atrash: 'Tempat sampah Amnesia', bin: 'Recycle Bin', leftover: 'Sisa app', build: 'Folder build', installer: 'Installer' },
    cWhy: {
      'old-temp': 'tidak berubah selama sehari', crash: 'laporan crash', cache: 'dibuat lagi saat perlu', atrash: 'sudah dihapus, menunggu dikosongkan',
      bin: 'dikosongkan permanen, tidak bisa dibatalkan', keeplist: 'Ada di Keep List', 'leftover-data': 'pengaturan dan data, centang hanya kalau yakin',
      'leftover-cache': 'cache', 'build-old': 'tidak dipakai 7 hari atau lebih', 'build-recent': 'dipakai 7 hari terakhir', git: 'dilacak git',
      'nested-git': 'berisi repo git', secret: 'berisi kunci atau sertifikat', unchecked: 'Tidak bisa dicek', cloud: 'di folder cloud',
      'installer-old': 'lebih lama dari 14 hari', 'installer-new': 'lebih baru dari 14 hari', 'setup-exe': 'program setup, cek sendiri dulu',
      'setup-zip': 'sepertinya setup, cek sendiri dulu', 'disc-image': 'image disk, cek sendiri dulu', system: 'dibutuhkan Windows',
      amnesia: 'milik Amnesia', 'keep-root': 'dilindungi', link: 'link, tidak diikuti', gone: 'sudah tidak ada', outside: 'di luar folder user kamu'
    },
    cTop: 'Lainnya', cNothing: 'Tidak ada yang perlu dibersihkan di sini.', cSel: function (n, b) { return n + ' dipilih, ' + size(b); },
    cGo: { quick: 'Bersihkan yang dipilih', apps: 'Pindah ke Recycle Bin', projects: 'Pindah ke Recycle Bin', installers: 'Pindah ke Recycle Bin' },
    cWhere: { 'delete': 'Cache, file Temp dan tempat sampah dihapus permanen.', recycle: 'Semuanya dipindah ke Recycle Bin.', bin: 'Recycle Bin dikosongkan permanen. Tidak bisa dibatalkan.' },
    cConfirm: function (n, b) { return 'Lanjutkan dengan ' + n + ' item, ' + size(b) + '?'; },
    cFreed: function (b) { return 'Ruang kosong +' + size(b); },
    cRes: function (c, d, f) { return c + ': ' + d + ' selesai' + (f ? ', ' + f + ' dilewati (sedang dipakai atau berubah)' : '') + '.'; },
    cChanged: function (n) { return n + ' item berubah sejak dipindai, jadi tidak disentuh.'; },
    cCut: 'Pemindaian berhenti di batasnya (30 detik atau 300.000 file). Yang sudah ketemu ditampilkan.',
    cErr: { 'care-rescan': 'Daftarnya sudah lama. Pindai lagi dulu.', 'care-gone': 'Sudah tidak ada.', 'care-not-found': 'Program itu sudah tidak terpasang.', 'care-not-user': 'Hanya program yang dipasang khusus untukmu yang bisa di-uninstall di sini.', 'keeplist-missing': 'Keep List hilang, jadi Perawatan berhenti dan tidak menghapus apa pun. Buka Keep List untuk mengeceknya.', 'keeplist-unreadable': 'Keep List tidak bisa dibaca, jadi Perawatan berhenti dan tidak menghapus apa pun. Buka Keep List untuk mengeceknya.' },
    cFeat: { quick: 'Bersihkan sekarang', apps: 'Hapus app', projects: 'Folder build project', installers: 'Installer lama', tune: 'Perawatan ringan' },
    hCare: function (d) { var p = d.split(' '); return 'Perawatan: ' + (L.cFeat[p[0]] || p[0]) + ': ' + (p[1] || 0) + ' item' + (+p[2] > 0 ? ', ' + size(+p[2] * 1024) + ' dikosongkan' : '') + (+p[3] > 0 ? ', ' + p[3] + ' gagal' : ''); },
    hStopped: function () { return 'Pembersihan dihentikan: Keep List tidak bisa dibaca. Tidak ada yang dihapus.'; },
    hlDisk: {
      ok: function (d) { var p = d.split(' '); return 'Ruang kosong: ' + size(+p[0]) + ' dari ' + size(+p[1]) + '.'; },
      warn: function (d) { var p = d.split(' '); return 'Ruang kosong tinggal sedikit: ' + size(+p[0]) + ' dari ' + size(+p[1]) + '. Perawatan bisa membantu.'; },
      info: 'Tidak bisa mengecek ruang kosong.'
    },
    hlMemory: { ok: function (d) { return 'Memori: ' + d + '% terpakai.'; }, warn: function (d) { return 'Memori hampir penuh (' + d + '% terpakai). Menutup app membantu.'; }, info: 'Tidak bisa mengecek memori.' },
    hlBattery: { info: function (d) { if (!d) return 'Tidak bisa mengecek baterai.'; var p = d.split(' '); return 'Baterai: ' + p[0] + '%' + (p[1] === '1' ? ', sedang diisi' : '') + '.'; } }
  };

  var L = EN, info = {};
  function setLang(lang) {
    L = lang === 'id' ? ID : EN;
    document.documentElement.lang = lang === 'id' ? 'id' : 'en';
    document.querySelectorAll('[data-t]').forEach(function (el) { var v = L[el.dataset.t]; if (typeof v === 'string') el.textContent = v; });
    document.querySelectorAll('[data-ph]').forEach(function (el) { var v = L[el.dataset.ph]; if (typeof v === 'string') el.placeholder = v; });
    document.querySelectorAll('[data-tip]').forEach(function (el) { var v = L[el.dataset.tip]; if (typeof v === 'string') { el.title = v; el.setAttribute('aria-label', v); } });
    $('unWord').placeholder = L.unWord;
    advOpen(!!advIsOpen);
    if ($('vAppsBox')) vChange(!$('vAppsBox').hidden);
    if (infoCards.length) infoLabels(); else foldInfo();
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
    if (b < 1e6) return Math.max(1, Math.round(b / 1e3)) + ' KB';
    if (b < 1e9) return (b / 1e6).toFixed(b < 1e7 ? 1 : 0) + ' MB';
    return (b / 1e9).toFixed(1) + ' GB';
  }

  var $ = function (id) { return document.getElementById(id); };
  // v0.10 (item 197): a button that says only "Remove" or "Keep" in a list also tells a screen reader which row it is for
  function named(b, action, what) { b.setAttribute('aria-label', action + ': ' + what); return b; }
  function el(tag, cls, text) { var e = document.createElement(tag); if (cls) e.className = cls; if (text !== undefined) e.textContent = text; return e; }
  function fill(ul, rows, cap) {
    ul.textContent = '';
    rows.slice(0, cap).forEach(function (r) {
      var li = el('li'); li.append(el('span', 'k', r.kind), el('span', 'p', r.path)); if (r.size) li.append(el('span', 'sz', r.size)); ul.append(li);
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
  // v0.7.1: questions in the page instead of window.confirm (Windows' own box cut the text off in a small window)
  function confirmBox(text) {
    return new Promise(function (done) {
      $('cfText').textContent = text;
      $('cfYes').textContent = L.yes; $('cfNo').textContent = L.cancel;
      $('confirm').hidden = false; $('cfNo').focus();
      function end(v) { $('confirm').hidden = true; $('cfYes').onclick = $('cfNo').onclick = null; done(v); }
      $('cfYes').onclick = function () { end(true); };
      $('cfNo').onclick = function () { end(false); };
    });
  }
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && !$('confirm').hidden) { e.stopImmediatePropagation(); $('cfNo').click(); } }, true);
  document.querySelectorAll('[data-cancel]').forEach(function (b) { b.addEventListener('click', function () { ask('cancel'); }); });
  document.querySelectorAll('[data-link]').forEach(function (b) { b.addEventListener('click', function () { ask('open', { target: b.dataset.link }); }); });

  // ---------- pages ----------
  // v0.6: like the Mac app: Home has tiles, every other page has a back button. Advanced lives inside Settings.
  var views = ['home', 'review', 'keep', 'vault', 'backup', 'settings', 'preview', 'history', 'health', 'care', 'ai'];
  var titles = { review: 'tOut', keep: 'tabKeep', vault: 'tabVault', backup: 'tabBackup', settings: 'tabSettings', preview: 'previewTitle', history: 'histTitle', health: 'healthTitle', care: 'careTitle', ai: 'aiTitle' };
  var loaders = {}, current = null;
  function title(name) { $('pageTitle').textContent = L[titles[name]] || ''; }
  function go(name) {
    var sub = null;
    if (name === 'advanced') { name = 'settings'; sub = 'advGroup'; advOpen(true); }
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
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && current !== 'home' && $('tour').hidden && $('confirm').hidden) go('home'); });
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
  // v0.10 (item 195): Advanced is closed until you open it (or search, or come from an "Advanced" link)
  var advIsOpen = false;
  function advOpen(on) {
    advIsOpen = on;
    var searching = !!$('setSearch').value.trim();
    $('advWrap').hidden = !(on || searching);
    $('advToggle').hidden = searching;
    $('advToggle').textContent = on ? L.advHide : L.advShow;
    $('advToggle').setAttribute('aria-expanded', on ? 'true' : 'false');
  }
  $('advToggle').addEventListener('click', function () { advOpen(!advIsOpen); });

  // v0.10 (owner, 27 Oct): long explanations in Settings and Vault fold behind a small "Info" button per card.
  // A card keeps its title, switches and buttons; the grey help text shows after Info (or while searching).
  var infoCards = [];
  function foldInfo() {
    document.querySelectorAll('#settings section.card, #vault details.fold').forEach(function (card) {
      var items = card.querySelectorAll(':scope > p.muted:not([id]):not([role]), label.switch > span > span.muted');
      var h = card.querySelector('h2, summary > b');
      if (!items.length || !h || card.classList.contains('has-info')) return;
      items.forEach(function (x) { x.classList.add('finfo'); });
      card.classList.add('has-info');
      if (h.tagName === 'H2') h.classList.add('ihead');
      var b = el('button', 'infobtn'); b.type = 'button'; b.setAttribute('aria-expanded', 'false');
      b.addEventListener('click', function (e) {
        e.preventDefault(); e.stopPropagation();
        var on = card.classList.toggle('show-info');
        b.setAttribute('aria-expanded', on ? 'true' : 'false');
      });
      // in a fold the button sits at the top of the open part, not in the summary (a click there would close it)
      if (h.tagName === 'H2') h.after(b); else card.querySelector(':scope > summary').after(b);
      infoCards.push({ b: b, h: h });
    });
    infoLabels();
  }
  function infoLabels() {
    infoCards.forEach(function (c) {
      c.b.textContent = '\u24D8 ' + L.infoShow;
      c.b.setAttribute('aria-label', L.infoAbout + c.h.textContent);
    });
  }
  $('setSearch').addEventListener('input', function () {
    advOpen(advIsOpen);
    $('settings').classList.toggle('searching', !!this.value.trim()); // v0.10: explanations show while searching
    window.scrollTo(0, 0); // v0.10 (item 191): the first hit is at the top, not above the window
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
    $('labBar').hidden = !(i.labOn && !i.labOpen);
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
    $('linksOff').hidden = !!i.enabled;
    document.querySelectorAll('[data-set]').forEach(function (c) { if (c.dataset.set in i) c.checked = !!i[c.dataset.set]; });
    document.querySelectorAll('input[name=lang]').forEach(function (r) { r.checked = r.value === i.langSetting; });
    $('aIdleMin').value = String(i.idleMin || 0);
    $('upDays').value = String(i.updateDays);
    $('aHotkey').value = i.panicHotkey || '';
    $('aUsbAction').value = i.usbAction || 'signout';
    $('aAppsBox').hidden = !i.removeNewApps;
    $('blockedCard').hidden = !i.lastBlocked;
    if (i.lastBlocked) $('blockedText').textContent = L.blocked(i.lastBlocked);
    // v0.8
    $('startupCard').hidden = !i.startupDisabled;
    // v0.8.1: Keep still locked by an old version
    $('keepStaleCard').hidden = !i.keepStale; $('ksPw').hidden = !i.keepStalePw;
    $('unPwBox').hidden = !i.keepLocked;
  }
  $('suFix').addEventListener('click', function () {
    ask('enableStartup').then(function (i) { show(i); loadHealth(); }).catch(function (e) { say('suMsg', errText(e), 'bad'); });
  });
  $('ksOpen').addEventListener('click', function () {
    var b = this; b.disabled = true;
    ask('keepStaleOpen', { password: $('ksPw').value }).then(function (i) { $('ksPw').value = ''; show(i); loadHealth(); say('ksMsg', L.ksDone, 'good'); })
      .catch(function (e) { say('ksMsg', errText(e), 'bad'); }).then(function () { b.disabled = false; });
  });
  // v0.8.1: Task Manager can switch startup off while this window is open: look again on focus and every 30 s
  function refreshStartup() {
    if (document.hidden || !info) return;
    ask('startupState').then(function (x) {
      if (!!x.startupDisabled === !!info.startupDisabled) return;
      info.startupDisabled = x.startupDisabled;
      $('startupCard').hidden = !x.startupDisabled;
      loadHealth();
    }).catch(function () {});
  }
  window.addEventListener('focus', refreshStartup);
  setInterval(refreshStartup, 30000);

  // ---------- Health check (v0.8) ----------
  function hlLine(x) {
    var t = (L.hl[x.id] || {})[x.state];
    return typeof t === 'function' ? t(x.data || '') : t || x.id;
  }
  function loadHealth() {
    return ask('health').then(function (h) {
      h = [].concat(h || []);
      var ul = $('hlList'); ul.textContent = '';
      h.forEach(function (x) {
        var li = el('li', 'hl ' + x.state); li.append(el('i', 'dot ' + x.state), el('span', 'grow', hlLine(x))); ul.append(li);
      });
      var n = h.filter(function (x) { return x.state === 'warn' || x.state === 'bad'; }).length;
      $('healthSub').textContent = n ? L.hlIssues(n) : L.hlAllOk;
      $('healthSub').className = n ? 'warn' : '';
      var lim = $('limList'); lim.textContent = '';
      L.lim.forEach(function (t) { lim.append(el('li', '', t)); });
    }).catch(function () { });
  }
  loaders.health = loadHealth;
  $('hlAgain').addEventListener('click', loadHealth);

  // ---------- Home ----------
  function loadHistory() {
    ask('history').then(function (h) {
      h = [].concat(h || []);
      $('histEmpty').hidden = h.length > 0;
      $('hist').hidden = h.length === 0;
      var f = { clean: L.hClean, paused: L.hPaused, snapshot: L.hSnapshot, restore: L.hRestore, backup: L.hBackup, doomsday: L.hDoom, quick: L.hQuick, apps: L.hApps, appkeep: L.hAppKeep, blocked: L.hBlocked, vault: L.hVault, leftovers: L.hLeft, sysclean: L.hSys, wipe: L.hWipe, pause: L.hPause, resume: L.hResume, care: L.hCare, stopped: L.hStopped, mode: L.hMode };
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
      if (/^keeplist-/.test(r.skipped || '')) say(msg, L.hStopped(), 'warn'); // v0.9: say why the list is empty
      $(sum).textContent = L.sum(r.count);
      if (list === 'items') { pv = { items: [].concat(r.items || []), kept: [].concat(r.kept || []) }; pvFolders(); showPv(); }
      else fill($(list), [].concat(r.items || []).map(function (x) { return { kind: L[x.kind] || x.kind, path: x.path }; }), 500);
      if (appsBox) {
        var apps = [].concat(r.apps || []);
        $(appsBox).hidden = apps.length === 0;
        fill($(appsList), apps.map(function (a) { return { kind: L.app, path: a.name }; }), 200);
      }
      $(res).hidden = false;
    }).catch(function (e) { say(msg, errText(e), 'bad'); }).then(function () { if (btn) btn.disabled = false; });
  }
  $('run').addEventListener('click', function () { preview(this, 'msg', 'result', 'sum', 'items', 'kept'); });

  // v0.7.1 "What gets wiped": search (name or path, in both lists), one folder only, biggest first
  var pv = null;
  function pvGroup(p, kind, app) {
    if (app) return app; // v0.8: grouped by the app it belongs to
    if (kind === 'trace' && !/^AppData\\/i.test(p)) return L.fqSys;
    var s = p.split('\\');
    if (s.length === 1) return L.fqTop;
    return /^AppData$/i.test(s[0]) ? s.slice(0, Math.min(3, s.length - 1)).join('\\') : s[0];
  }
  function pvFolders() {
    var g = {}, sel = $('fqFolder'), was = sel.value;
    pv.items.forEach(function (x) { var k = pvGroup(x.path, x.kind, x.app); g[k] = g[k] || { n: 0, b: 0 }; g[k].n++; g[k].b += Math.max(0, x.size || 0); });
    sel.textContent = '';
    var all = el('option', '', L.fqAll); all.value = ''; sel.append(all);
    Object.keys(g).sort(function (a, b) { return a.toLowerCase() < b.toLowerCase() ? -1 : 1; }).forEach(function (k) {
      var o = el('option', '', k + ' (' + g[k].n + (g[k].b ? ', ' + size(g[k].b) : '') + ')'); o.value = k; sel.append(o);
    });
    sel.value = g[was] ? was : '';
  }
  function showPv() {
    if (!pv) return;
    var q = $('fqQ').value.trim().toLowerCase(), g = $('fqFolder').value, big = $('fqSort').value === 'size';
    function ok(p, kind, app) { return (!q || p.toLowerCase().indexOf(q) >= 0 || app && app.toLowerCase().indexOf(q) >= 0) && (!g || pvGroup(p, kind, app) === g); }
    var items = pv.items.filter(function (x) { return ok(x.path, x.kind, x.app); });
    if (big) items = items.slice().sort(function (a, b) { return (b.size || 0) - (a.size || 0); });
    fill($('items'), items.map(function (x) { return { kind: x.app || L[x.kind] || x.kind, path: x.path, size: x.size >= 0 ? size(x.size) : '' }; }), 500);
    var kept = pv.kept.filter(function (p) { return ok(p, 'kept'); });
    fill($('kept'), kept.map(function (p) { return { kind: L.kept, path: p }; }), 500);
    var filtered = q || g;
    $('fqShown').textContent = filtered ? (items.length ? L.fqShown(items.length, pv.items.length) : L.fqNone) : '';
  }
  ['fqQ', 'fqFolder', 'fqSort'].forEach(function (id) { $(id).addEventListener(id === 'fqQ' ? 'input' : 'change', showPv); });

  // ---------- Review and sign out ----------
  loaders.review = function () { preview(null, 'revMsg', 'revResult', 'revSum', 'revItems', null, 'revAppsBox', 'revApps'); };
  $('revSignOut').addEventListener('click', function () { this.disabled = true; ask('signOut'); });

  // ---------- Keep List ----------
  function showKeep(k) {
    $('keepDir').textContent = k.keepDir;
    var ul = $('klList'); ul.textContent = '';
    k.paths.forEach(function (p) {
      var li = el('li'), g = el('span', 'grow');
      // v0.8: the app's icon and name, the path under it
      li.append(appIcon(p.icon, p.app ? null : 'folder'));
      if (p.app) { g.append(el('span', '', p.app), el('span', 'meta', p.path.replace(/\//g, '\\'))); }
      else g.append(el('span', '', p.path.replace(/\//g, '\\')));
      if (!p.exists) g.append(el('span', 'meta', L.klMissing));
      var b = el('button', 'btn ghost small', L.remove);
      named(b, L.remove, p.app || p.path.replace(/\//g, '\\')); // v0.10 (197)
      b.addEventListener('click', function () { ask('keepRemove', { path: p.path }).then(showKeep); });
      li.append(g, b); ul.append(li);
    });
    $('klEmpty').hidden = k.paths.length > 0;
    var box = $('klSugg'); box.textContent = '';
    k.suggestions.forEach(function (s) {
      var c = el('button', 'chip', s.name);
      if (s.icon) c.prepend(appIcon(s.icon));
      // v0.8.1: one chip can keep the same app's folders in Local and Roaming together
      var paths = s.paths && s.paths.length ? s.paths : [s.path];
      c.title = paths.map(function (p) { return p.replace(/\//g, '\\'); }).join('\n');
      if (paths.length > 1) c.append(el('span', 'meta', ' (' + paths.map(function (p) { return p.split('/')[1]; }).join(' + ') + ')'));
      c.addEventListener('click', function () { (paths.length > 1 ? ask('keepAddApp', { paths: paths }) : ask('keepAdd', { path: s.path })).then(showKeep); });
      box.append(c);
    });
    if (!k.suggestions.length) box.append(el('span', 'muted', L.klNone));
    kaApps = [].concat(k.apps || []);
    showApps();
  }
  // v0.8 "Keep an app"
  var kaApps = [];
  function appIcon(src, kind) {
    var i = el('span', 'aicon' + (kind ? ' ' + kind : ''));
    if (src) { var img = el('img'); img.src = src; img.alt = ''; img.width = 20; img.height = 20; i.append(img); }
    return i;
  }
  function showApps() {
    var q = $('kaQ').value.trim().toLowerCase(), ul = $('kaList'); ul.textContent = '';
    var list = kaApps.filter(function (a) { return !q || a.name.toLowerCase().indexOf(q) >= 0; });
    list.slice(0, 200).forEach(function (a) {
      var li = el('li'), g = el('span', 'grow');
      g.append(el('span', '', a.name), el('span', 'meta', (a.store ? L.kaStore + ' · ' : '') + a.paths.map(function (p) { return p.replace(/\//g, '\\'); }).join(', ')));
      var b = el('button', 'btn ghost small', a.kept ? L.kaKept : L.kaKeep);
      named(b, a.kept ? L.kaKept : L.kaKeep, a.name); // v0.10 (197)
      b.disabled = a.kept;
      b.addEventListener('click', function () {
        b.disabled = true;
        ask('keepAddApp', { paths: a.paths }).then(function (k) { showKeep(k); say('klMsg', L.saved, 'good'); }).catch(function (e) { b.disabled = false; say('klMsg', errText(e), 'bad'); });
      });
      li.append(appIcon(a.icon), g, b); ul.append(li);
    });
    $('kaEmpty').hidden = kaApps.length > 0;
  }
  $('kaQ').addEventListener('input', showApps);
  // v0.8 Safe box
  function showSafe(x) {
    $('sbNew').hidden = x.exists; $('sbClosed').hidden = !x.exists || x.open; $('sbOpened').hidden = !x.open;
    $('sbState').textContent = !x.exists ? L.sbNone : x.open ? L.sbIsOpen(x.dir) : L.sbIsClosed(size(x.size));
  }
  function loadSafe() { ask('safeInfo').then(showSafe).catch(function () { }); }
  $('sbCreate').addEventListener('click', function () {
    var b = this; b.disabled = true;
    ask('safeCreate', { password: $('sbPw').value }).then(function (x) { $('sbPw').value = ''; showSafe(x); say('sbMsg', L.done, 'good'); })
      .catch(function (e) { say('sbMsg', errText(e), 'bad'); }).then(function () { b.disabled = false; });
  });
  $('sbOpen').addEventListener('click', function () {
    var b = this, stop = progress('sbProg', 'safe'); b.disabled = true; say('sbMsg', L.working);
    ask('safeOpen', { password: $('sbOpenPw').value }).then(function (x) { $('sbOpenPw').value = ''; showSafe(x); say('sbMsg', L.sbOpened(x.files), 'good'); })
      .catch(function (e) { say('sbMsg', errText(e), 'bad'); }).then(function () { stop(); b.disabled = false; });
  });
  $('sbClose').addEventListener('click', function () {
    var b = this, stop = progress('sbProg', 'safe'); b.disabled = true; say('sbMsg', L.working);
    ask('safeClose').then(function (x) { showSafe(x); say('sbMsg', L.sbClosedNow(x.files), 'good'); })
      .catch(function (e) { say('sbMsg', errText(e), 'bad'); }).then(function () { stop(); b.disabled = false; });
  });
  $('sbShow').addEventListener('click', function () { ask('safeShow'); });
  loaders.keep = function () { ask('keepList').then(showKeep); loadSafe(); };
  // v0.7: a locked Keep asks its password here
  function openKeep() {
    ask('openKeep').catch(function (e) {
      if (e.message !== 'keeplock-ask') return;
      var pw = window.prompt(L.klkAsk);
      if (pw) ask('openKeep', { password: pw }).catch(function (e2) { window.alert(errText(e2)); });
    });
  }
  $('openKeep').addEventListener('click', openKeep);
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
      cb.setAttribute('aria-label', a.name); // v0.10 (197)
      cb.addEventListener('change', function () { ask('vaultChoose', { name: a.name, on: cb.checked }).then(showVault); });
      g.append(el('span', '', a.name), el('span', 'meta', (a.time ? L.vSaved(a.time) + (a.size ? ', ' + size(a.size) : '') : L.vNever) + (a.prevTime ? ' · ' + L.vPrev(a.prevTime) : '') + (a.shrunk ? ' · ' + L.vShrunk : '') + (a.setup === 'unfinished' ? ' · ' + L.vSetup : '') + (a.present ? '' : ' · ' + L.vNotHere)));
      li.append(cb, g);
      if (a.time) { var d = el('button', 'btn ghost small', L.vDelete); named(d, L.vDelete, a.name); d.addEventListener('click', function () { ask('vaultDelete', { name: a.name }).then(showVault); }); li.append(d); }
      if (a.folder) { var r = el('button', 'btn ghost small', L.remove); named(r, L.remove, a.name); r.addEventListener('click', function () { ask('vaultRemoveFolder', { name: a.name }).then(showVault); }); li.append(r); }
      ul.append(li);
    });
    // v0.8: apps found on this PC that the vault does not know yet
    var sg = $('vSugg'); sg.textContent = '';
    [].concat(v.suggest || []).forEach(function (s) {
      var c = el('button', 'chip', s.name);
      if (s.icon) c.prepend(appIcon(s.icon));
      c.title = s.path.replace(/\//g, '\\');
      c.addEventListener('click', function () { ask('vaultAddFolder', { path: s.path }).then(showVault).catch(function (e) { say('vMsg', errText(e), 'bad'); }); });
      sg.append(c);
    });
    $('vSuggBox').hidden = !sg.childElementCount;
    // v0.11: step 1 says which apps are picked, step 2 when they were saved
    var chosen = v.apps.filter(function (a) { return a.chosen; }), saved = v.apps.filter(function (a) { return a.time; });
    var names = chosen.map(function (a) { return a.name; });
    $('vChosen').textContent = !names.length ? L.vNoneChosen : names.slice(0, 4).join(', ') + (names.length > 4 ? L.vMore(names.length - 4) : '');
    var last = saved.map(function (a) { return a.time; }).sort().pop(), bytes = saved.reduce(function (t, a) { return t + (a.size || 0); }, 0);
    $('vLast').textContent = last ? L.vLastSaved(last, saved.length, bytes ? size(bytes) : '') : L.vNotSaved;
    $('vSnap').disabled = !chosen.length;
    if (!names.length) vChange(true); // nothing picked yet: the list opens by itself
  }
  function vChange(on) {
    $('vAppsBox').hidden = !on;
    $('vChange').textContent = on ? L.vChangeDone : L.vChange;
    $('vChange').setAttribute('aria-expanded', on ? 'true' : 'false');
  }
  $('vChange').addEventListener('click', function () { vChange($('vAppsBox').hidden); });
  loaders.vault = function () { ask('vaultInfo').then(showVault); };
  // ---------- v0.10 vault profiles ----------
  // The Restore card gets a profile picker: Everything, or only the apps of one profile (Work, Personal...).
  var vp = { profiles: [], shared: {}, apps: [], editing: null };
  var showVaultBase = showVault;
  showVault = function (v) { showVaultBase(v); if (v.exists) loadProfiles(); else $('vpEditor').hidden = true; };
  function vpErr(e) { var m = (e && e.message) || '', k = m.indexOf('vault:') === 0 ? m.split(':')[1] : m; return L.vpErr[k] || errText(e); }
  function vpName(id) { var p = vp.profiles.filter(function (x) { return x.id === id; })[0]; return p ? p.name : id; }
  function vpSharedText(apps) {
    return Object.keys(vp.shared).filter(function (a) { return !apps || apps.indexOf(a) >= 0; }).map(function (a) {
      var ids = vp.shared[a]; return L.vpShared(a, ids.slice(0, -1).map(vpName).join(', '), vpName(ids[ids.length - 1]));
    }).join('\n');
  }
  function vpChoice() { return $('vpPick').hidden ? '' : $('vProfile').value; }
  function loadProfiles(keep) {
    return ask('profiles').then(function (r) {
      vp.profiles = r.profiles || []; vp.shared = r.shared || {}; vp.apps = r.apps || [];
      var sel = $('vProfile'), want = keep || sel.value || r.last || 'all';
      sel.textContent = '';
      vp.profiles.forEach(function (p) { var o = el('option', '', p.name); o.value = p.id; sel.append(o); });
      sel.value = vp.profiles.some(function (p) { return p.id === want; }) ? want : 'all';
      $('vpPick').hidden = false;
      $('vpFull').hidden = r.mode !== 'full';
      vpShow();
    }).catch(function () { $('vpPick').hidden = true; $('vpApps').hidden = true; $('vpShared').hidden = true; }); // older or locked: restore everything as before
  }
  function vpShow() {
    var id = $('vProfile').value, p = vp.profiles.filter(function (x) { return x.id === id; })[0];
    $('vpEdit').disabled = !p || id === 'all';
    if (!p) { $('vpApps').hidden = true; $('vpShared').hidden = true; return; }
    var parts = [], noSnap = p.apps.filter(function (a) { return p.snapshots.indexOf(a) < 0 && p.missing.indexOf(a) < 0; });
    if (!p.apps.length) parts.push(id === 'all' ? L.vpNoApps : L.vpEmpty);
    else parts.push(L.vpRestores(p.apps));
    if (noSnap.length) parts.push(L.vpNoSnap(noSnap));
    if (p.missing.length) parts.push(L.vpNotHere(p.missing));
    $('vpApps').textContent = parts.join(' '); $('vpApps').hidden = false;
    var sh = id === 'all' ? '' : vpSharedText(p.apps);
    $('vpShared').textContent = sh; $('vpShared').hidden = !sh;
  }
  $('vProfile').addEventListener('change', vpShow);
  function vpOpen(p) {
    vp.editing = p ? p.id : null;
    $('vpEdTitle').textContent = p ? L.vpEditTitle : L.vpNewTitle;
    $('vpName').value = p ? p.name : '';
    $('vpDelete').hidden = !p;
    var box = $('vpAppList'); box.textContent = '';
    var names = vp.apps.map(function (a) { return a.name; });
    (p ? p.apps : []).forEach(function (a) { if (names.indexOf(a) < 0) names.push(a); }); // an app that is not here any more can still be unticked
    names.forEach(function (n) {
      var a = vp.apps.filter(function (x) { return x.name === n; })[0], lab = el('label', 'check'), cb = el('input'), t = el('span', '', n);
      cb.type = 'checkbox'; cb.value = n; cb.checked = !!p && p.apps.indexOf(n) >= 0;
      if (!a || !a.present) t.append(el('span', 'meta', ' · ' + L.vNotHere)); else if (!a.snapshot) t.append(el('span', 'meta', ' · ' + L.vNever));
      lab.append(cb, t); box.append(lab);
    });
    if (!names.length) box.append(el('p', 'muted small', L.vpNoApps));
    $('vpEdShared').hidden = true; say('vpMsg', '');
    $('vpEditor').hidden = false; $('vpName').focus();
    $('vpEditor').scrollIntoView({ block: 'nearest' });
  }
  $('vpEdit').addEventListener('click', function () { var id = $('vProfile').value; vpOpen(vp.profiles.filter(function (x) { return x.id === id; })[0] || null); });
  $('vpNew').addEventListener('click', function () { vpOpen(null); });
  $('vpCancel').addEventListener('click', function () { $('vpEditor').hidden = true; });
  $('vpSave').addEventListener('click', function () {
    var apps = [].map.call($('vpAppList').querySelectorAll('input:checked'), function (c) { return c.value; });
    ask('profileSave', { id: vp.editing || '', name: $('vpName').value, apps: apps }).then(function (r) {
      return loadProfiles(r.saved).then(function () {
        var p = vp.profiles.filter(function (x) { return x.id === r.saved; })[0], sh = p ? vpSharedText(p.apps) : '';
        vp.editing = r.saved; $('vpEdTitle').textContent = L.vpEditTitle; $('vpDelete').hidden = false;
        $('vpEdShared').textContent = sh; $('vpEdShared').hidden = !sh;
        say('vpMsg', L.saved, 'good');
      });
    }).catch(function (e) { say('vpMsg', vpErr(e), 'bad'); });
  });
  $('vpDelete').addEventListener('click', function () {
    if (!vp.editing) return;
    var id = vp.editing;
    confirmBox(L.vpDeleteAsk(vpName(id))).then(function (yes) {
      if (!yes) return;
      ask('profileDelete', { id: id }).then(function () { $('vpEditor').hidden = true; return loadProfiles('all'); }).catch(function (e) { say('vpMsg', vpErr(e), 'bad'); });
    });
  });
  // v0.8: how hard the password is to guess (a rough guide, nothing is sent anywhere)
  function strength(p) {
    if (p.length < 12) return 0;
    var pool = (/[a-z]/.test(p) ? 26 : 0) + (/[A-Z]/.test(p) ? 26 : 0) + (/[0-9]/.test(p) ? 10 : 0) + (/[^a-zA-Z0-9]/.test(p) ? 33 : 0);
    var uniq = new Set(p.split('')).size;
    var bits = Math.min(p.length, uniq * 2) * Math.log2(Math.max(pool, 10));
    if (/^(.)\1+$/.test(p) || /(password|qwerty|123456|amnesia)/i.test(p)) bits = Math.min(bits, 30);
    return bits < 60 ? 1 : bits < 80 ? 2 : 3;
  }
  $('vPw1').addEventListener('input', function () {
    var v = this.value, s = strength(v);
    $('vMeter').dataset.s = v ? s : '';
    $('vMeterText').textContent = v ? L.meter[s] : '';
  });
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
    // v0.10: profile = only the apps of the chosen profile ('' or 'all' = everything, as before)
    ask('vaultRestore', { password: $('vRestorePw').value, previous: $('vRestorePrev').checked, profile: vpChoice() }).then(function (v) { $('vRestorePw').value = ''; showVault(v); var pr = v.problems || {}, extra = Object.keys(pr).map(function (k) { return L.vRestoreIssue(k, pr[k]); }); if (v.ignored && v.ignored.length) extra.push(L.vpIgnored(v.ignored)); say('vRestoreMsg', [L.vRestored(v.restored || [])].concat(extra).join(' '), extra.length ? 'warn' : 'good'); })
      .catch(function (e) { say('vRestoreMsg', vpErr(e), 'bad'); if (/doomsday/.test(e.message)) loaders.vault(); })
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
    ask('backupNow').then(function (r) { showBackup(r); say('bMsg', L.bDone(r.where) + (r.skipped ? ' ' + L.bSkipped(r.skipped) : ''), r.skipped ? 'warn' : 'good'); }).catch(function (e) { say('bMsg', errText(e), 'bad'); })
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
    showLocks(a);
    var ul = $('aAppsList'); ul.textContent = '';
    a.apps.forEach(function (x) {
      var li = el('li'), g = el('span', 'grow');
      // v0.8.1: one line per app; the meta line names every part of it (uninstall entry, Start menu, registry...)
      var parts = (x.kinds || [x.kind]).map(function (k) { return k === 'machine' ? L.needsAdmin : L[kinds[k]]; });
      g.append(el('span', '', x.name), el('span', 'meta', parts.join(' · ')));
      li.append(g);
      if (x.canUninstall) {
        var u = el('button', 'btn ghost small', L.uninstall);
        named(u, L.uninstall, x.name); // v0.10 (197)
        // v0.7.1: Amnesia waits for the uninstaller, then the list is loaded again
        u.addEventListener('click', function () {
          u.disabled = true; say('aAppsMsg', L.aUninstalling);
          ask('appsUninstall', { id: x.uninstallId || x.id }).then(function (a) { say('aAppsMsg', L.done, 'good'); showAdv(a); }).catch(function (e) { say('aAppsMsg', errText(e), 'bad'); u.disabled = false; });
        });
        li.append(u);
      }
      var k = el('button', 'btn ghost small', L.keep); named(k, L.keep, x.name); k.addEventListener('click', function () { k.disabled = true; ask('appsKeep', { id: x.id, ids: x.ids || [x.id] }).then(function (a) { say('aAppsMsg', L.aKept, 'good'); showAdv(a); }).catch(function (e) { say('aAppsMsg', errText(e), 'bad'); k.disabled = false; }); }); li.append(k);
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
    $('sxReady').hidden = !a.sandbox; $('sxMissing').hidden = !!a.sandbox;
    $('avCfa').textContent = a.cfa === 'on' ? L.cfaOn : a.cfa === 'off' || a.cfa === 'audit' ? L.cfaOff : L.cfaUnknown;
    $('avCfa').className = a.cfa === 'on' ? 'warn' : 'muted';
  }
  // v0.7 Keep lock + lab lock
  function showLocks(a) {
    var k = a.keepLock || {}, lb = a.lab || {};
    $('klkOffBox').hidden = !!k.on; $('klkOnBox').hidden = !k.on;
    $('klkState').textContent = k.locked ? L.klkLocked : L.klkOpen;
    $('klkMin').value = String(k.minutes || 15);
    $('labOffBox').hidden = !!lb.on; $('labOnBox').hidden = !lb.on;
    $('labState').textContent = lb.open ? L.labOpenNow : L.labState(lb.since);
    $('labOpenBox').hidden = !lb.open;
    $('labBar').hidden = !(lb.on && !lb.open);
  }
  function lockAsk(cmd, arg, msg, clear) {
    say(msg, L.working);
    return ask(cmd, arg).then(function (a) { clear.forEach(function (id) { $(id).value = ''; }); showAdv(a); say(msg, L.saved, 'good'); ask('info').then(show); })
      .catch(function (e) { say(msg, errText(e), 'bad'); });
  }
  $('klkOn').addEventListener('click', function () {
    if ($('klkPw').value !== $('klkPw2').value) return say('klkMsg', L.pinMismatch, 'bad');
    lockAsk('keepLockOn', { password: $('klkPw').value, minutes: $('klkMinNew').value }, 'klkMsg', ['klkPw', 'klkPw2']);
  });
  $('klkOff').addEventListener('click', function () { lockAsk('keepLockOff', { password: $('klkOffPw').value }, 'klkMsg', ['klkOffPw']); });
  $('klkNow').addEventListener('click', function () { lockAsk('keepLockNow', {}, 'klkMsg', []); });
  $('klkMin').addEventListener('change', function () { lockAsk('keepLockMin', { minutes: this.value }, 'klkMsg', []); });
  $('labOn').addEventListener('click', function () {
    if ($('labPin').value !== $('labPin2').value) return say('labMsg', L.pinMismatch, 'bad');
    lockAsk('labOn', { pin: $('labPin').value }, 'labMsg', ['labPin', 'labPin2']);
  });
  $('labUnlock').addEventListener('click', function () { lockAsk('labUnlock', { pin: $('labPinNow').value }, 'labMsg', ['labPinNow']); });
  $('labSave').addEventListener('click', function () { var p = window.prompt(L.labPinPh); if (p) lockAsk('labOn', { pin: p }, 'labMsg', []); });
  $('labClose').addEventListener('click', function () { lockAsk('labClose', {}, 'labMsg', []); });
  $('labOff').addEventListener('click', function () { var p = window.prompt(L.labPinPh); if (p) lockAsk('labOff', { pin: p }, 'labMsg', []); });
  loaders.advanced = function () { ask('advInfo').then(showAdv).catch(function (e) { say('aMsg', errText(e), 'bad'); }); };
  $('aIdleMin').addEventListener('change', function () { ask('set', { key: 'idleMin', value: this.value }).then(show); });
  $('upDays').addEventListener('change', function () { ask('set', { key: 'updateDays', value: this.value }).then(show); });
  $('aHotkey').addEventListener('change', function () { var s = this; ask('set', { key: 'panicHotkey', value: s.value }).then(show).catch(function (e) { s.value = ''; say('aMsg', errText(e), 'bad'); }); });
  $('aUsb').addEventListener('change', function () {
    var o = this.selectedOptions[0];
    if (this.value === '=keep') return;
    ask('usbSet', { serial: this.value, name: this.value ? o.dataset.name : '' }).then(showAdv);
  });
  $('aPanicNow').addEventListener('click', function () { confirmBox(L.aPanicConfirm).then(function (y) { if (y) ask('panicNow'); }); });
  $('aKeepAll').addEventListener('click', function () { ask('appsKeepAll').then(function (a) { say('aAppsMsg', L.aKept, 'good'); showAdv(a); }).catch(function (e) { say('aAppsMsg', errText(e), 'bad'); }); });
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
      cb.type = 'checkbox'; cb.dataset.folder = f.path; cb.checked = f.level === 'likely'; cb.setAttribute('aria-label', f.path);
      g.append(el('span', '', f.path), el('span', 'meta', (f.empty ? L.loEmpty : size(f.size)) + ' · ' + (f.level === 'likely' ? L.loLikely : L.loCareful)));
      li.append(cb, g); ul.append(li);
    });
    r.keys.forEach(function (k) {
      var li = el('li'), cb = el('input'), g = el('span', 'grow');
      cb.type = 'checkbox'; cb.dataset.key = k; cb.setAttribute('aria-label', 'HKCU\\Software\\' + k);
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
  // v0.8.1: the sandbox had the same ids as the Safe box (sbOpen, sbMsg), so the Safe box Open button opened the sandbox too
  $('sxOpen').addEventListener('click', function () { ask('sandbox', { shareKeep: $('sxKeep').checked, network: $('sxNet').checked }).then(function () { say('sxMsg', ''); }).catch(function (e) { say('sxMsg', errText(e), 'bad'); }); });
  $('wfRun').addEventListener('click', function () {
    confirmBox(L.wfConfirm).then(function (y) { if (y) ask('wipeFree').then(function () { say('wfMsg', L.wfStarted, 'good'); }).catch(function (e) { say('wfMsg', errText(e), 'bad'); }); });
  });
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
  // v0.7.1: shows that it works (it takes a while) and can't be started twice
  $('collectLog').addEventListener('click', function () {
    var b = this; b.disabled = true; say('logMsg', L.logBusy);
    ask('collectLog').then(function (r) { say('logMsg', r && r.ok ? L.logDone(r.path) : L.logMissing, r && r.ok ? 'good' : 'bad'); })
      .catch(function (e) { say('logMsg', errText(e), 'bad'); }).then(function () { b.disabled = false; });
  });
  $('tourAgain').addEventListener('click', function () { tour(0); });
  // v0.8.1: the locked Safe box can't be opened without Amnesia: warn while it still holds files
  function safeWarn(all) {
    return ask('safeInfo').then(function (x) {
      if (!x.exists || x.open || x.count === 0) return true;
      return confirmBox(all ? L.unSafeAll(x.count) : L.unSafe(x.count));
    }, function () { return true; });
  }
  // v0.8: with the Keep password when Keep is locked (else Keep would stay locked after uninstall)
  $('unApp').addEventListener('click', function () {
    safeWarn(false).then(function (go) { return go && confirmBox(L.unConfirm); }).then(function (y) { if (y) ask('uninstall', { all: false, password: $('unPw').value }).then(function () { say('setMsg', L.unBye); }).catch(function (e) { say('setMsg', errText(e), 'bad'); }); });
  });
  $('unAll').addEventListener('click', function () {
    if ($('unWord').value.trim().toUpperCase() !== L.unWord) { $('unWord').focus(); return; }
    if (info.keepLocked && !$('unPw').value) { say('setMsg', L.err['keeplock-uninstall'], 'bad'); $('unPw').focus(); return; }
    safeWarn(true).then(function (go) { if (go) ask('uninstall', { all: true, password: $('unPw').value }).then(function () { say('setMsg', L.unBye); }).catch(function (e) { say('setMsg', errText(e), 'bad'); }); });
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

  // ---------- Care (v0.9) ----------
  // scan -> list with sizes and checkboxes -> asked once more -> act -> result per category + space freed.
  // The page only sends back ids of the last scan; C# keeps the paths and checks every item again before acting.
  [EN, ID].forEach(function (D) {
    D.hl.disk = D.hlDisk; D.hl.memory = D.hlMemory; D.hl.battery = D.hlBattery;
    Object.keys(D.cErr).forEach(function (k) { D.err[k] = D.cErr[k]; });
  });
  // ---------- v0.10 Amnesia modes ----------
  // One choice for how much is forgotten at every sign out. A switch is always: preview (two dry runs in C#), then the
  // sheet below, then "Switch mode". C# keeps the previewed list and refuses when the Keep List changed meanwhile.
  [EN, ID].forEach(function (D) { Object.keys(D.mdErr).forEach(function (k) { D.err[k] = D.mdErr[k]; }); });
  var mdInfo = null, ms = null;
  var MODES = ['full', 'balanced', 'light', 'custom'];
  function mdName(id) { return L.mdNames[id] || id; }
  function mdKey(x) { return String(x).trim().replace(/\\/g, '/').replace(/^\/+|\/+$/g, '').toLowerCase(); }
  function loadMode() {
    return ask('modeInfo').then(function (m) { mdInfo = m; showModes(); return m; }).catch(function (e) { say('mdMsg', errText(e), 'bad'); });
  }
  function showModes() {
    var box = $('mdList'); box.textContent = '';
    if (!mdInfo) return;
    MODES.forEach(function (id) {
      var on = mdInfo.mode === id, b = el('button', 'mode' + (on ? ' on' : ''));
      b.type = 'button'; b.setAttribute('role', 'radio'); b.setAttribute('aria-checked', on ? 'true' : 'false');
      var t = el('span', 'mt'); t.append(el('b', '', mdName(id)));
      if (on) t.append(el('span', 'pill', L.mdNow));
      b.append(t, el('small', '', L.mdSubs[id]));
      b.disabled = !!mdInfo.lab;
      b.addEventListener('click', function () {
        if (mdInfo.mode === id) return;
        say('mdMsg', '');
        modeSheet(id, [], []).then(function (to) {
          if (!to) return;
          say('mdMsg', L.msDone(mdName(to)), 'good');
          ask('keepList').then(showKeep);
          ask('info').then(show);
        });
      });
      box.append(b);
    });
    var note = mdInfo.mode === 'light' ? L.mdLightNote : mdInfo.mode === 'full' ? L.mdFullVault : '';
    $('mdLight').textContent = note; $('mdLight').hidden = !note;
    if (mdInfo.lab) say('mdMsg', L.err['mode-lab']);
    else if (!mdInfo.blockOk) say('mdMsg', L.err['mode-broken'], 'warn');
  }
  // the mode card follows every change of the Keep List (removing a line of the mode makes it Custom)
  showKeep = (function (orig) { return function (k) { orig(k); loadMode(); }; })(showKeep);

  // the preview sheet. Resolves with the new mode after "Switch mode", or false.
  function modeSheet(mode, add, remove) {
    return new Promise(function (done) {
      ms = { mode: mode, add: [].concat(add || []), remove: [].concat(remove || []), done: done, p: null };
      $('msTitle').textContent = L.msTitle(mdName(mode));
      $('msOwn').textContent = ''; $('msOwnBox').hidden = true;
      $('modeSheet').hidden = false;
      $('msNo').focus();
      msLoad();
    });
  }
  function msEnd(v) { $('modeSheet').hidden = true; var d = ms && ms.done; ms = null; if (d) d(v); }
  function msFill(ul, rows, total) {
    ul.textContent = '';
    var shown = rows.slice(0, 200);
    shown.forEach(function (r) { var li = el('li'); li.append(el('span', 'k', r.kind), el('span', 'p', r.path)); ul.append(li); });
    if (total > shown.length) ul.append(el('li', '', L.more(total - shown.length)));
  }
  function msLoad() {
    var my = ms;
    if (!my) return;
    my.p = null;
    // v0.10: only the newest preview may be shown (and committed); the own-line boxes wait while one is being made
    var seq = my.seq = (my.seq || 0) + 1;
    function own(on) { [].forEach.call($('msOwn').querySelectorAll('input'), function (c) { c.disabled = !on; }); }
    own(false);
    $('msYes').disabled = true; $('msYes').className = 'btn';
    $('msBusy').hidden = false;
    ['msProblem', 'msWarn', 'msNote', 'msCount', 'msSettings', 'msWipedBox', 'msKeptBox'].forEach(function (id) { $(id).hidden = true; });
    ask('modePreview', { mode: my.mode, add: my.add, remove: my.remove }).then(function (p) {
      if (ms === my && my.seq === seq) msShow(my, p);
    }).catch(function (e) {
      if (ms !== my || my.seq !== seq) return;
      $('msBusy').hidden = true; $('msProblem').textContent = errText(e); $('msProblem').hidden = false;
      own(true);
    });
  }
  function msShow(my, p) {
    $('msBusy').hidden = true;
    $('msTitle').textContent = L.msTitle(mdName(p.mode));
    if (p.problem) {
      $('msProblem').textContent = p.problem === 'mode-preset' ? L.msPreset(mdName(p.asked)) : (L.err[p.problem] || p.problem);
      $('msProblem').hidden = false;
      $('msOwnBox').hidden = true;
      return; // nothing to switch to: "Switch mode" stays off
    }
    $('msWarn').hidden = !p.wipesMore;
    $('msNote').hidden = p.note !== 'to-custom';
    if (p.wipeAfter >= 0) {
      var same = !p.newlyWipedCount && !p.newlyKeptCount && !(p.added || []).length && !(p.removed || []).length;
      $('msCount').textContent = L.msCount(p.wipeAfter, p.wipeBefore) + (same ? ' ' + L.msSame : '');
      $('msCount').hidden = false;
    }
    var s = p.settings || {};
    var st = s.VAULT_AUTO === '0' ? L.msAutoOff : s.VAULT_AUTO === '1' ? L.msAutoOn : '';
    $('msSettings').textContent = st; $('msSettings').hidden = !st;
    function line(x) { return { kind: L.msLineK, path: String(x).replace(/\//g, '\\') }; }
    function item(x) { return { kind: L.msItemK, path: x }; }
    // v0.10 (item 190): a removed line where nothing is wiped is listed apart, not under "will now be wiped"
    var idle = [].concat(p.removedIdle || []);
    var removed = [].concat(p.removed || []).filter(function (x) { return idle.indexOf(x) < 0; }), added = [].concat(p.added || []);
    var wiped = removed.map(line).concat([].concat(p.newlyWiped || []).map(item));
    var kept = added.map(line).concat([].concat(p.newlyKept || []).map(item));
    msFill($('msWiped'), wiped, removed.length + (p.newlyWipedCount || 0));
    msFill($('msKept'), kept, added.length + (p.newlyKeptCount || 0));
    msFill($('msIdle'), idle.map(line), idle.length);
    $('msWipedBox').hidden = wiped.length === 0;
    $('msKeptBox').hidden = kept.length === 0;
    $('msIdleBox').hidden = idle.length === 0;
    // your own lines: they stay unless you tick them (unticked by default)
    var ul = $('msOwn'), own = [].concat(p.outside || []);
    ul.textContent = '';
    own.forEach(function (ln) {
      var li = el('li'), lab = el('label', 'check'), cb = el('input');
      cb.type = 'checkbox';
      cb.checked = my.remove.some(function (r) { return mdKey(r) === mdKey(ln); });
      var g = el('span', 'grow'); g.append(el('span', '', ln.replace(/\//g, '\\')), el('span', 'meta', L.msStop));
      cb.addEventListener('change', function () {
        my.remove = my.remove.filter(function (r) { return mdKey(r) !== mdKey(ln); });
        if (cb.checked) my.remove.push(ln);
        msLoad();
      });
      lab.append(cb, g); li.append(lab); ul.append(li);
    });
    $('msOwnBox').hidden = own.length === 0;
    my.p = p;
    $('msYes').className = 'btn' + (p.wipesMore ? ' mdanger' : '');
    $('msYes').disabled = false;
  }
  $('msYes').addEventListener('click', function () {
    var my = ms;
    if (!my || !my.p) return;
    this.disabled = true;
    ask('modeCommit', { mode: my.mode }).then(function (m) { mdInfo = m; showModes(); if (ms === my) msEnd(my.p.mode); })
      .catch(function (e) { if (ms !== my) return; $('msProblem').textContent = errText(e); $('msProblem').hidden = false; });
  });
  $('msNo').addEventListener('click', function () { msEnd(false); });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && !$('modeSheet').hidden && $('confirm').hidden) { e.stopImmediatePropagation(); msEnd(false); }
  }, true);

  // ---------- v0.10 Ask an AI ----------
  // The report and the prompt are made in C# (no file contents, no file names). The page only copies or saves them;
  // Amnesia sends nothing. The answer is pasted back, read by C#, and every change gets a checkbox.
  var aiRep = null, aiBusy = false, aiSug = null;
  function aiLang() { return L === ID ? 'id' : 'en'; }
  function aiWant() { return ($('aiHide').checked ? '1' : '0') + aiLang(); }
  function aiMakeReport() {
    if (aiBusy) return;
    aiBusy = true;
    var want = { hideNames: $('aiHide').checked, lang: aiLang() }, key = aiWant();
    $('aiCopy').disabled = $('aiSave').disabled = $('aiMake').disabled = true;
    say('aiMsg', L.aiBusy);
    ask('aiReport', want).then(function (r) {
      aiRep = { key: key, full: r.full };
      $('aiText').textContent = r.full; $('aiShowBox').hidden = false;
      say('aiMsg', L.aiReady);
      $('aiCopy').disabled = $('aiSave').disabled = false;
    }).catch(function (e) { say('aiMsg', errText(e), 'bad'); }).then(function () {
      aiBusy = false; $('aiMake').disabled = false;
      if (aiRep && aiRep.key !== aiWant()) aiMakeReport(); // the switch changed while it was busy
    });
  }
  loaders.ai = function () { if (!aiRep || aiRep.key !== aiWant()) aiMakeReport(); };
  $('aiHide').addEventListener('change', aiMakeReport);
  $('aiMake').addEventListener('click', aiMakeReport);
  function copyText(t) {
    function old() {
      var ta = el('textarea'); ta.value = t; ta.setAttribute('readonly', ''); ta.style.position = 'fixed'; ta.style.left = '-9999px';
      document.body.append(ta); ta.select();
      var ok = false; try { ok = document.execCommand('copy'); } catch (x) { ok = false; }
      ta.remove();
      return ok ? Promise.resolve() : Promise.reject(new Error('copy'));
    }
    if (navigator.clipboard && navigator.clipboard.writeText) return navigator.clipboard.writeText(t).catch(old);
    return old();
  }
  $('aiCopy').addEventListener('click', function () {
    if (!aiRep) return;
    copyText(aiRep.full).then(function () { say('aiMsg', L.aiCopied, 'good'); }, function () { say('aiMsg', L.aiCopyFail, 'warn'); $('aiShowBox').open = true; });
  });
  $('aiSave').addEventListener('click', function () {
    var b = this; b.disabled = true;
    ask('aiSave', { hideNames: $('aiHide').checked, lang: aiLang() }).then(function (r) { say('aiMsg', L.aiSaved(r.path), 'good'); })
      .catch(function (e) { say('aiMsg', errText(e), 'bad'); }).then(function () { b.disabled = false; });
  });
  $('aiRead').addEventListener('click', function () {
    var t = $('aiAnswer').value, b = this;
    $('aiSugg').hidden = true; aiSug = null;
    if (!t.trim()) { say('aiPMsg', L.aiErr['no-block'], 'warn'); return; }
    b.disabled = true;
    ask('aiParse', { text: t }).then(function (r) {
      if (!r.ok) { say('aiPMsg', L.aiErr[r.error] || r.error, 'bad'); return; }
      // the vault profiles you have, so a profile with the same name is updated instead of made twice
      return ask('profiles').catch(function () { return null; }).then(function (pr) { aiShow(r, pr); });
    }).catch(function (e) { say('aiPMsg', errText(e), 'bad'); }).then(function () { b.disabled = false; });
  });
  function aiShow(r, pr) {
    var have = pr && pr.profiles ? [].concat(pr.profiles) : [];
    var ul = $('aiChanges'), items = [];
    ul.textContent = '';
    function row(kind, value, text, on) {
      var li = el('li'), lab = el('label', 'check'), cb = el('input');
      cb.type = 'checkbox'; cb.checked = on;
      lab.append(cb, el('span', 'grow', text)); li.append(lab); ul.append(li);
      items.push({ kind: kind, value: value, cb: cb });
    }
    // ticked for you: new lines and profiles. Not ticked: a mode switch and lines to stop keeping.
    if (r.mode) row('mode', r.mode, L.aiMode(mdName(r.mode)), false);
    [].concat(r.keep_add || []).forEach(function (p) { row('add', p, L.aiAdd(p.replace(/\//g, '\\')), true); });
    [].concat(r.keep_remove || []).forEach(function (p) { row('remove', p, L.aiRemove(p.replace(/\//g, '\\')), false); });
    Object.keys(r.profiles || {}).forEach(function (n) {
      var ex = have.filter(function (x) { return x.id !== 'all' && String(x.name).toLowerCase() === n.toLowerCase(); })[0];
      var apps = [].concat(r.profiles[n] || []);
      row('profile', { name: n, apps: apps, id: ex ? ex.id : '' }, L.aiProf(n, apps, !!ex), true);
    });
    if (!items.length) ul.append(el('li', 'muted', L.aiNone));
    $('aiNotes').textContent = r.notes || ''; // plain text, never HTML
    $('aiNotesBox').hidden = !r.notes;
    var un = $('aiUnused'); un.textContent = '';
    [].concat(r.rejected || [], r.skipped || []).forEach(function (x) { un.append(el('li', '', L.aiNotUsed + ': ' + x.item + ' (' + (L.aiWhy[x.why] || x.why) + ')')); });
    if ((r.ignored_apps || []).length) un.append(el('li', '', L.aiIgnored(r.ignored_apps)));
    un.hidden = !un.childNodes.length;
    $('aiApply').disabled = !items.length;
    aiSug = items;
    $('aiSugg').hidden = false;
    say('aiPMsg', '');
  }
  function aiSaveProfiles(list) {
    var p = Promise.resolve();
    list.forEach(function (x) {
      p = p.then(function () { var a = { name: x.name, apps: x.apps }; if (x.id) a.id = x.id; return ask('profileSave', a); });
    });
    return p.catch(function (e) { throw new Error(L.aiProfFail + ' ' + errText(e)); });
  }
  $('aiApply').addEventListener('click', function () {
    if (!aiSug) return;
    var mode = null, add = [], rem = [], prof = [];
    aiSug.filter(function (x) { return x.cb.checked; }).forEach(function (x) {
      if (x.kind === 'mode') mode = x.value; else if (x.kind === 'add') add.push(x.value); else if (x.kind === 'remove') rem.push(x.value); else prof.push(x.value);
    });
    if (!mode && !add.length && !rem.length && !prof.length) { say('aiPMsg', L.aiNoTick, 'warn'); return; }
    var keep = !!(mode || add.length || rem.length);
    // Keep List changes go through the same preview and confirm as a mode switch
    var first = keep ? (mode ? Promise.resolve(mode) : ask('modeInfo').then(function (m) { return m.mode; })).then(function (m) { return modeSheet(m, add, rem); })
      : confirmBox(L.aiProfAsk(prof.length));
    first.then(function (ok) {
      if (!ok) return;
      return aiSaveProfiles(prof).then(function () {
        say('aiPMsg', keep ? L.aiApplied : L.aiProfDone(prof.length), 'good');
        aiSug = null; $('aiSugg').hidden = true; aiRep = null;
      });
    }).catch(function (e) { say('aiPMsg', errText(e), 'bad'); });
  });

  var careData = {}, careBusyOn = false;
  function careCard(f) { return document.querySelector('#care .care-f[data-feature="' + f + '"]'); }
  function careSay(card, t, cls) { var m = card.querySelector('.cMsg'); m.textContent = t || ''; m.className = (cls || 'muted') + ' cMsg'; }
  function careSize(b, cut) { return b < 0 ? '?' : (cut ? L.cAtLeast : '') + size(b); }
  function carePath(rel) { return (rel || '').replace(/\//g, '\\'); }
  // one job at a time: the shared progress line moves into the card that works
  function careRun(card, cmd, arg, working) {
    if (careBusyOn) return Promise.reject(new Error('busy'));
    careBusyOn = true;
    var prog = $('careProg');
    card.querySelector('.care-slot').append(prog);
    prog.querySelector('span').textContent = working ? L.cWorking : L.cBusy;
    prog.hidden = false;
    document.querySelectorAll('#care .cbtn').forEach(function (b) { b.disabled = true; });
    function end() { careBusyOn = false; prog.hidden = true; document.querySelectorAll('#care .cbtn').forEach(function (b) { b.disabled = false; }); }
    return ask(cmd, arg).then(function (r) { end(); return r; }, function (e) { end(); throw e; });
  }
  function careMeta(x) {
    var why = L.cWhy[x.reason] || x.reason;
    var parts = [];
    if (x.rel) parts.push(carePath(x.rel));
    parts.push(why);
    if (x.newest && x.cat === 'build') parts.push(x.newest);
    return parts.join(' · ');
  }
  function careSel(f) {
    var n = 0, b = 0;
    (careData[f] || []).forEach(function (x) { if (x.selected && !x.disabled) { n++; b += Math.max(0, x.bytes || 0); } });
    return { n: n, b: b };
  }
  function careGroup(f, x) { return f === 'quick' ? (L.cCat[x.cat] || x.cat) : x.group ? carePath(x.group) : L.cTop; }

  // the list of one scan, grouped (quick: by kind, apps: by app, projects: by project, installers: by folder)
  function careShow(card, f, items, cut, intro) {
    var out = card.querySelector('.cOut');
    out.textContent = ''; out.hidden = false;
    careData[f] = items;
    if (intro) out.append(el('p', '', intro));
    if (cut) out.append(el('p', 'warn small', L.cCut));
    if (!items.length) { out.append(el('p', 'muted', L.cNothing)); return; }
    var groups = {}, order = [];
    items.forEach(function (x) { var k = careGroup(f, x); if (!groups[k]) { groups[k] = []; order.push(k); } groups[k].push(x); });
    var sum = el('p', 'sum'), go = el('button', 'btn cbtn', L.cGo[f]);
    function update() { var s = careSel(f); sum.textContent = L.cSel(s.n, s.b); go.disabled = s.n === 0; }
    order.forEach(function (k) {
      var g = groups[k], on = g.filter(function (x) { return !x.disabled; });
      var box = el('div', 'care-group'), head = el('label', 'care-ghead'), all = el('input');
      all.type = 'checkbox'; all.disabled = on.length === 0;
      var total = 0, cut2 = false;
      g.forEach(function (x) { total += Math.max(0, x.bytes || 0); cut2 = cut2 || x.cut; });
      head.append(all, el('b', '', k), el('span', 'sz', careSize(total, cut2)));
      var ul = el('ul', 'list rows care-items');
      function sync() {
        var c = on.filter(function (x) { return x.selected; }).length;
        all.checked = c > 0 && c === on.length; all.indeterminate = c > 0 && c < on.length;
      }
      g.forEach(function (x) {
        var li = el('li', x.disabled ? 'off' : ''), cb = el('input');
        cb.type = 'checkbox'; cb.checked = !!x.selected && !x.disabled; cb.disabled = !!x.disabled;
        cb.setAttribute('aria-label', x.name);
        cb.addEventListener('change', function () { x.selected = cb.checked; sync(); update(); });
        var txt = el('span', 'grow');
        txt.append(el('span', '', x.cat === 'bin' ? L.cCat.bin : x.name), el('span', 'meta', careMeta(x)));
        li.append(cb, txt, el('span', 'sz', careSize(x.bytes, x.cut)));
        ul.append(li);
        x._cb = cb;
      });
      all.addEventListener('change', function () { on.forEach(function (x) { x.selected = all.checked; x._cb.checked = all.checked; }); update(); });
      sync();
      box.append(head, ul);
      out.append(box);
    });
    var row = el('div', 'row');
    row.append(go);
    if (f === 'apps') {
      var skip = el('button', 'btn ghost cbtn', L.cSkip);
      skip.addEventListener('click', function () { careAct(card, f, true); });
      row.append(skip);
    }
    go.addEventListener('click', function () { careAct(card, f, false); });
    out.append(sum, row);
    update();
  }

  function careAct(card, f, skip) {
    var sel = skip ? [] : (careData[f] || []).filter(function (x) { return x.selected && !x.disabled; });
    var s = careSel(f), where = {};
    sel.forEach(function (x) { where[x.where] = true; });
    var text = L.cConfirm(s.n, s.b) + ' ' + ['delete', 'recycle', 'bin'].filter(function (w) { return where[w]; }).map(function (w) { return L.cWhere[w]; }).join(' ');
    (skip ? Promise.resolve(true) : confirmBox(text)).then(function (ok) {
      if (!ok) return;
      careSay(card, '');
      careRun(card, 'careAct', { feature: f, ids: sel.map(function (x) { return x.id; }) }, true)
        .then(function (r) { careResult(card, f, r); if (f === 'apps') loadPrograms(); })
        .catch(function (e) { careSay(card, errText(e), 'bad'); });
    });
  }

  function careResult(card, f, r) {
    var out = card.querySelector('.cOut');
    out.textContent = ''; out.hidden = false;
    delete careData[f];
    var ul = el('ul', 'list rows care-res');
    [].concat(r.cats || []).forEach(function (c) { ul.append(el('li', c.failed ? 'warn' : '', L.cRes(L.cCat[c.cat] || c.cat, c.done, c.failed))); });
    if (ul.children.length) out.append(ul);
    if (r.changed) out.append(el('p', 'warn small', L.cChanged(r.changed)));
    out.append(el('p', 'sum good', L.cFreed(Math.max(0, r.bytes || 0))));
  }

  function careScan(card) {
    var f = card.dataset.feature;
    careSay(card, '');
    card.querySelector('.cOut').hidden = true;
    careRun(card, 'careScan', { feature: f }).then(function (r) {
      careShow(card, f, [].concat(r.items || []), r.cut);
      card.querySelector('.care-scan').textContent = L.cAgain;
    }).catch(function (e) { careSay(card, errText(e), 'bad'); });
  }
  ['quick', 'projects', 'installers'].forEach(function (f) {
    var card = careCard(f);
    card.querySelector('.care-scan').addEventListener('click', function () { careScan(card); });
  });

  // disk overview: read only, the buttons only show things in Explorer
  function careReveal(rel) {
    var b = el('button', 'btn ghost small', L.cShow);
    b.addEventListener('click', function () { ask('careReveal', { path: rel }).catch(function (e) { careSay(careCard('overview'), errText(e), 'bad'); }); });
    return b;
  }
  function careRow(ul, label, bytes, cut, rel) {
    var li = el('li'), t = el('span', 'grow');
    t.append(el('span', '', label));
    li.append(t, el('span', 'sz', careSize(bytes, cut)));
    if (rel && bytes !== 0) li.append(careReveal(rel));
    ul.append(li);
  }
  (function () {
    var card = careCard('overview');
    card.querySelector('.care-scan').addEventListener('click', function () {
      careSay(card, '');
      careRun(card, 'careOverview').then(function (o) {
        var out = card.querySelector('.cOut');
        out.textContent = ''; out.hidden = false;
        if (o.total > 0) {
          out.append(el('p', 'sum', L.cDisk(o.free, o.total)));
          var bar = el('div', 'care-disk'), used = el('i');
          used.style.width = Math.round((1 - o.free / o.total) * 100) + '%';
          bar.append(used); out.append(bar);
        }
        if (o.cut) out.append(el('p', 'warn small', L.cCut));
        var ul = el('ul', 'list rows care-ov');
        ['keep', 'vault', 'atrash', 'bin', 'temp', 'downloads'].forEach(function (k) {
          var e = o.sizes && o.sizes[k];
          if (e) careRow(ul, L.cSizes[k], e.bytes, e.cut, k === 'bin' || k === 'vault' ? null : e.rel);
        });
        out.append(ul);
        out.append(el('h3', '', L.cFolders));
        var fl = el('ul', 'list rows care-ov');
        [].concat(o.folders || []).forEach(function (e) { careRow(fl, carePath(e.rel), e.bytes, e.cut, e.rel); });
        out.append(fl);
        out.append(el('h3', '', L.cFiles));
        var files = [].concat(o.files || []);
        if (!files.length) out.append(el('p', 'muted small', L.cNoFiles));
        else {
          var bl = el('ul', 'list rows care-ov');
          files.forEach(function (e) { careRow(bl, carePath(e.rel), e.bytes, false, e.rel); });
          out.append(bl);
        }
        if (o.oldCount > 0) out.append(el('p', 'muted', L.cOld(o.oldCount, o.oldBytes)));
        card.querySelector('.care-scan').textContent = L.cAgain;
      }).catch(function (e) { careSay(card, errText(e), 'bad'); });
    });
  })();

  // uninstall apps: just-for-you programs run their own uninstaller, the rest open Windows Settings
  var programs = [];
  function showPrograms() {
    var q = $('cAppsQ').value.trim().toLowerCase(), ul = $('cAppsList');
    ul.textContent = '';
    var list = programs.filter(function (p) { return !q || p.name.toLowerCase().indexOf(q) >= 0 || (p.publisher || '').toLowerCase().indexOf(q) >= 0; });
    if (!list.length) { ul.append(el('li', 'muted', L.cNoPrograms)); return; }
    list.forEach(function (p) {
      var li = el('li'), t = el('span', 'grow');
      t.append(el('span', '', p.name), el('span', 'meta', [p.publisher, p.version, L.cKind[p.kind] || p.kind].filter(Boolean).join(' · ')));
      li.append(t);
      if (p.bytes > 0) li.append(el('span', 'sz', size(p.bytes)));
      var b;
      if (p.canUninstall) {
        b = el('button', 'btn ghost small cbtn', L.cUninstall);
        b.addEventListener('click', function () { careUninstall(p); });
      } else {
        b = el('button', 'btn ghost small', L.cOpenApps);
        b.addEventListener('click', function () { ask('careOpen', { target: 'appsfeatures' }); });
      }
      li.append(b);
      ul.append(li);
    });
  }
  function loadPrograms() {
    var card = careCard('apps');
    return ask('carePrograms').then(function (list) {
      programs = [].concat(list || []);
      $('cAppsBox').hidden = false;
      showPrograms();
    }).catch(function (e) { careSay(card, errText(e), 'bad'); });
  }
  function careUninstall(p) {
    var card = careCard('apps');
    confirmBox(L.cUnConfirm(p.name)).then(function (ok) {
      if (!ok) return;
      careSay(card, '');
      card.querySelector('.cOut').hidden = true;
      careRun(card, 'careUninstall', { id: p.id }, true).then(function (r) {
        if (!r.gone) { careSay(card, L.cUnStill(r.name), 'warn'); loadPrograms(); return; }
        var items = [].concat(r.items || []);
        if (!items.length) {
          careResult(card, 'apps', { cats: [], bytes: r.bytes || 0 });
          careSay(card, L.cUnGone(r.name) + ' ' + L.cUnNoLeft, 'good');
        } else careShow(card, 'apps', items, false, L.cUnGone(r.name) + ' ' + L.cUnLeft);
        loadPrograms();
      }).catch(function (e) { careSay(card, errText(e), 'bad'); loadPrograms(); });
    });
  }
  $('cAppsBtn').addEventListener('click', function () { careSay(careCard('apps'), L.cBusy); loadPrograms().then(function () { careSay(careCard('apps'), ''); }); });
  $('cAppsQ').addEventListener('input', showPrograms);

  // safe tune-ups
  $('cTuneRun').addEventListener('click', function () {
    var card = careCard('tune'), tasks = [];
    if ($('cTuneExplorer').checked) tasks.push('explorer');
    if (!tasks.length) { careSay(card, L.cTuneNone); return; }
    confirmBox(L.cTuneAsk).then(function (ok) {
      if (!ok) return;
      careRun(card, 'careTune', { tasks: tasks }, true).then(function (r) {
        careSay(card, [].concat(r.results || []).map(function (x) { return L.cTuneRes(x.ok); }).join(' '), r.failed ? 'warn' : 'good');
        $('cTuneExplorer').checked = false;
      }).catch(function (e) { careSay(card, errText(e), 'bad'); });
    });
  });
  document.querySelectorAll('[data-care-open]').forEach(function (b) { b.addEventListener('click', function () { ask('careOpen', { target: b.dataset.careOpen }); }); });

  // ---------- start ----------
  setLang('en');
  ask('info').then(function (i) {
    $('ver').textContent = 'v' + i.version;
    $('win').textContent = i.windows;
    setLang(i.lang);
    show(i);
    go(i.view || 'home');
    if (!i.welcomeDone) tour(0);
    loadHealth();
    ask('encryption').then(function (e) {
      $('enc').textContent = { on: L.encOn, off: L.encOff, paused: L.encPaused }[e.state] || L.encUnknown;
      $('enc').className = e.state === 'on' ? 'good' : e.state === 'off' || e.state === 'paused' ? 'warn' : 'muted';
    }).catch(function () { $('enc').textContent = L.encUnknown; });
  }).catch(function (e) { say('msg', errText(e), 'bad'); });
})();
