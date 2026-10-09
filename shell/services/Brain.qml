pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Friday state + the bridge to ~/.local/share/friday/bin/friday-ask (which drives the Claude Code CLI).
Singleton {
    id: root

    property bool shown: false
    property bool cloaked: false                // briefly hide the overlay (screenshots)
    readonly property bool running: proc.running || localProc.running
    property string sessionId: ""               // Claude Code session, so follow-ups keep full context
    property var approval: null                 // {id, tool, command, reason, risk} while a card is up
    property string queued: ""
    property var ctx: ({})                      // live desktop snapshot from friday-context
    property string ctxRaw: ""
    property var promptHistory: []              // prompts, newest last
    property string authState: "unknown"        // unknown | ok | needed
    property string pendingAfterLogin: ""
    property double lastActivity: 0             // ms; drives "fresh chat on summon"
    // chat history: your last 10 conversations, newest first, kept across restarts
    property var history: []                    // [{id, title, sessionId, updated, count, items}]
    readonly property bool resumable: root.history.length > 0
    readonly property var archived: root.history.length > 0 ? root.history[0] : null
    property bool historyDirty: false
    readonly property string historyPath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/friday/history.json"
    property string selection: ""               // text highlighted elsewhere (Super+Shift+Space)
    property var usage: ({})                    // Claude plan limits from friday-usage
    property var sessions: []                   // your latest Claude Code sessions (friday-sessions)

    // voice ("Hey Friday"): state mirrors the friday-voice daemon
    property string voiceState: "off"           // off | unavailable | idle | muted | listening | transcribing | speaking
    property string voicePartial: ""            // live words while you talk
    property real voiceLevel: 0                 // mic level 0..1 while listening
    property bool voiceTurn: false              // the current request was spoken -> speak the answer
    property bool wakeEnabled: false            // "Hey Friday" listening; off by default, remembered across restarts
    property bool voiceBooted: false            // wait for that setting before starting the voice process
    property bool voiceSession: false           // this panel was opened by voice: tidy it away when the exchange ends
    property bool expectReply: false            // keep the conversation open after Friday speaks
    property bool endAfterSpeaking: false
    property string lastTag: ""       // Friday decided the conversation is over: close once it's said its bit
    // live speech: sentences are spoken as they stream in, and the one being heard is highlighted
    property int speakingMsg: -1                // message index being read aloud (-1: none)
    property int spokenIdx: -1                  // sentence currently being heard
    property var speechParts: []                // sentences sent to the voice, in order
    property var speechRanges: []               // [start, end) spans of the message body they came from
    property int speechFed: 0                   // how far into the answer has been sent to the voice
    property int speechChars: 0
    property int speechBase: 0                  // words already spoken in earlier utterances of this answer
    property var speechWords: []                // exactly the words Friday says, for word-by-word highlighting
    property var speechGroups: []               // [first word, word count] for each spoken range, in body order
    readonly property string restState: root.wakeEnabled ? "idle" : "muted"
    readonly property string wakeFile: (Quickshell.env("XDG_STATE_HOME") || (root.home + "/.local/state")) + "/friday/wake"
    readonly property bool voiceOn: ["idle", "listening", "transcribing", "speaking"].indexOf(root.voiceState) >= 0
    readonly property bool hearing: root.voiceState === "listening" || root.voiceState === "transcribing"
    property var focus: ({})                    // active focus session from friday-focus
    property double now: Date.now()             // ticks while something on screen is counting down
    readonly property bool focusActive: !!(root.focus && root.focus.ends && root.focus.ends * 1000 > root.now)
    readonly property string binDir: home + "/.local/share/friday/bin/"
    readonly property bool loginRunning: loginProc.running

    readonly property ListModel messages: ListModel {}
    property int assistantIndex: -1
    property var steps: []
    property bool gotText: false

    readonly property string home: Quickshell.env("HOME")
    readonly property string askBin: home + "/.local/share/friday/bin/friday-ask"
    readonly property string ctxBin: home + "/.local/share/friday/bin/friday-context"
    readonly property string doBin: home + "/.local/share/friday/bin/friday-do"
    readonly property string loginBin: home + "/.local/share/friday/bin/friday-login"
    readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/friday"

    // ---------------------------------------------------------------- visibility
    function show() {
        // A chat that finished while you were away is filed into History; you open to a fresh one.
        if (!root.shown && !proc.running && !root.approval && root.messages.count > 0) root.archiveChat();
        root.shown = true;
        root.refreshContext();
        if (!sessionsProc.running) sessionsProc.running = true;
        if (!musicRowProc.running) musicRowProc.running = true;
        if (root.authState === "unknown") root.checkAuth();
    }
    function withSelection(text) {
        root.selection = String(text ?? "").trim();
        if (root.messages.count > 0 && !proc.running) root.archiveChat();
        root.show();
    }
    // clipboard -> selection mode (text), or ask about the image
    function useClipboard(kind) {
        if (kind === "image") {
            root.ask("There's an image on my clipboard. Save it with `friday-clip image \"$FRIDAY_SCRATCH/clip.png\"`, look at it, and tell me what it is and anything useful about it.", "What's in the image I copied?");
            return;
        }
        clipProc.running = true;
    }
    Process {
        id: clipProc
        command: [root.binDir + "friday-clip", "get", "--max", "6000"]
        stdout: StdioCollector {
            id: clipOut
            onStreamFinished: root.withSelection(clipOut.text)
        }
    }

    function continueSession(s) {
        Quickshell.execDetached([root.binDir + "friday-continue", s.id, s.cwd]);
        root.hide();
    }
    Process {
        id: sessionsProc
        command: [root.binDir + "friday-sessions", "-n", "3"]
        stdout: StdioCollector {
            id: sessionsOut
            onStreamFinished: {
                try { root.sessions = JSON.parse(sessionsOut.text); } catch (e) { return; }
                // give fresh sessions a proper name in the background (cached, so this runs once per session)
                if (root.sessions.some(x => !x.named) && !namerProc.running) namerProc.running = true;
            }
        }
    }
    Process {
        id: namerProc
        command: [root.binDir + "friday-sessions", "-n", "3", "--name"]
        stdout: StdioCollector {
            id: namerOut
            onStreamFinished: { try { root.sessions = JSON.parse(namerOut.text); } catch (e) { } }
        }
    }

    // the music row: "For you" + your top picks from FRIDAY_MUSIC (friday-music row)
    property var musicRow: [
        { k: "for you", t: "For you" }, { k: "chill house", t: "Chill house" }, { k: "lofi", t: "Lofi" },
        { k: "pop hits", t: "Pop hits" }, { k: "indie", t: "Indie" }
    ]
    Process {
        id: musicRowProc
        command: [root.binDir + "friday-music", "row"]
        stdout: StdioCollector {
            id: musicRowOut
            onStreamFinished: {
                try {
                    const r = JSON.parse(musicRowOut.text);
                    if (Array.isArray(r) && r.length > 0 && JSON.stringify(r) !== JSON.stringify(root.musicRow)) root.musicRow = r;
                } catch (e) { }
            }
        }
    }
    function playVibe(kind) {
        Quickshell.execDetached([root.binDir + "friday-music", kind]);
        root.hide();
    }

    function startFocus(minutes, task) {
        Quickshell.execDetached([root.binDir + "friday-focus", "start", String(minutes), task ?? "Focus"]);
        focusPoke.restart();
    }
    function stopFocus() {
        Quickshell.execDetached([root.binDir + "friday-focus", "stop"]);
        focusPoke.restart();
    }
    function fmtLeft(epochSec) {
        if (!epochSec) return "";
        const s = Math.round(epochSec - root.now / 1000);
        if (s <= 0) return "";
        const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
        if (d > 0) return d + "d " + h + "h";
        if (h > 0) return h + "h " + (m < 10 ? "0" : "") + m + "m";
        return m + "m";
    }

    function hide() {
        if (root.approval) root.resolveApproval(false);
        if (root.hearing || root.voiceState === "speaking") root.voiceCmd("cancel");
        root.voiceSession = false;
        root.expectReply = false;
        root.endAfterSpeaking = false;
        closeTimer.stop();
        dismissTimer.stop();
        root.shown = false;
        root.selection = "";
        root.voiceTurn = false;                 // dismissed: whatever is still coming in isn't read aloud
        // Closing ends the chat. If Friday is still working, it finishes in the background (you get a
        // notification) and the chat is filed into History the moment it's done.
        if (proc.running) root.archiveWhenDone = true;
        else if (root.messages.count > 0) root.archiveChat();
        console.log("[Friday] hidden; chat " + (proc.running ? "files itself when the answer finishes" : "filed, next open is fresh"));
    }
    function toggle() { root.shown ? root.hide() : root.show(); }

    // ---------------------------------------------------------------- conversation
    property string chatId: ""                  // set when you reopen a chat from History, so it's updated in place
    property bool archiveWhenDone: false        // closed mid-answer: file the chat as soon as it finishes
    function newChat() {
        root.chatId = "";
        root.archiveWhenDone = false;
        root.speakingMsg = -1;
        root.spokenIdx = -1;
        root.queued = "";
        if (proc.running) proc.running = false;
        root.localPending = "";
        if (localProc.running) localProc.running = false;
        root.localNotes = [];
        root.messages.clear();
        root.sessionId = "";
        root.steps = [];
        root.assistantIndex = -1;
    }

    function archiveChat() {
        if (root.messages.count === 0 || proc.running) return;
        const items = [];
        for (let i = 0; i < root.messages.count; i++) {
            const m = root.messages.get(i);
            items.push({ role: m.role, body: m.body, stepsJson: m.stepsJson, done: true, spokenJson: m.spokenJson ?? "" });
        }
        const first = items.find(x => x.role === "user");
        const title = String(first ? first.body : "Chat").split("\n")[0].replace(/\s+/g, " ").trim();
        const entry = {
            id: root.chatId || (Date.now().toString(36) + Math.random().toString(36).slice(2, 6)),
            title: title.length > 70 ? title.slice(0, 70) + "…" : title,
            sessionId: root.sessionId,
            updated: Date.now(),
            count: items.filter(x => x.role === "user").length,
            items: items
        };
        root.history = [entry, ...root.history.filter(h => h.id !== entry.id)].slice(0, 10);
        root.saveHistory();
        root.newChat();
    }
    function openHistory(id) {
        const h = root.history.find(x => x.id === id);
        if (!h) return;
        if (proc.running) root.stop();
        if (root.messages.count > 0) root.archiveChat();
        root.newChat();
        for (let i = 0; i < h.items.length; i++) root.messages.append(h.items[i]);
        root.sessionId = h.sessionId;          // Claude remembers the whole conversation: just keep talking
        root.chatId = h.id;
        root.lastActivity = Date.now();
    }
    function deleteHistory(id) {
        root.history = root.history.filter(h => h.id !== id);
        root.saveHistory();
    }
    function clearHistory() {
        root.history = [];
        root.saveHistory();
    }
    function saveHistory() {
        if (historyWriter.running) { root.historyDirty = true; return; }
        root.historyDirty = false;
        historyWriter.stdinEnabled = true;
        historyWriter.running = true;
    }
    Process {
        id: historyWriter
        command: ["bash", "-c", "mkdir -p \"$(dirname \"$1\")\" && cat > \"$1.tmp\" && mv -f \"$1.tmp\" \"$1\"", "_", root.historyPath]
        onRunningChanged: {
            if (historyWriter.running) {
                historyWriter.write(JSON.stringify(root.history));
                stdinEnabled = false;
            }
        }
        onExited: if (root.historyDirty) root.saveHistory()
    }
    FileView {
        path: root.historyPath
        onLoaded: { try { root.history = JSON.parse(text()); } catch (e) { root.history = []; } }
    }
    function fresh() {                          // Ctrl+N / the new-chat button: keep the old one resumable
        if (proc.running) root.stop();
        if (root.messages.count > 0) root.archiveChat();
        else root.newChat();
    }
    function resume() {                          // the most recent chat
        if (root.history.length > 0) root.openHistory(root.history[0].id);
    }
    function copy(text) { Quickshell.execDetached([root.binDir + "friday-clip", "set", String(text)]); }
    function plain(md) {
        return String(md).replace(/```[\s\S]*?```/g, "[code]").replace(/[*_`#>]/g, "").replace(/\[(.*?)\]\(.*?\)/g, "$1").replace(/\s+/g, " ").trim();
    }

    function stop() {
        root.queued = "";
        if (proc.running) proc.running = false;
    }

    function ask(text, label) {
        const t = (text ?? "").trim();
        if (t.length === 0) return;
        root.promptHistory = [...root.promptHistory.filter(h => h !== t), t].slice(-40);
        root.show();
        if (localProc.running) {     // still answering the last one on-device: drop that, take this
            localProc.running = false;
            root.localPending = "";
            if (root.assistantIndex >= 0 && root.messages.count >= 2 && root.messages.get(root.assistantIndex).body.length === 0) {
                root.messages.remove(root.messages.count - 2, 2);
                root.assistantIndex = -1;
            }
        }
        if (proc.running) {          // interrupt the current turn, then run the new one
            root.voiceTurn = false;
            root.queued = t;
            proc.running = false;
            return;
        }
        // Everyday things (time, timers, volume, apps, music…) are done on this laptop with no Claude usage and
        // no internet; only what friday-local declines goes to Claude. Rows and highlighted-text tools are
        // always Claude jobs.
        const local = !(label && label.length > 0) && root.selection.length === 0 && root.localEnabled;
        if (!local && root.authState === "needed") {      // signed out: park the request, the sign-in card is showing
            root.pendingAfterLogin = t;
            return;
        }
        root.start(t, label, local);
    }

    // ---------------------------------------------------------------- on-device skills (friday-local)
    property bool localEnabled: true
    property string localPending: ""
    property var localNotes: []                 // what was handled on-device since Claude last spoke, for context
    property int clearSpokenAfter: -1           // on-device answers: show the neat text once it's been said
    function tryLocal(t) {
        root.localPending = t;
        const flags = [];
        if (root.voiceTurn) flags.push("--voice");
        if (root.sessionId.length > 0) flags.push("--in-chat");
        localProc.command = [root.binDir + "friday-local", ...flags, "--", t];
        localProc.running = true;
        localGuard.restart();
    }
    Process {
        id: localProc
        stdout: StdioCollector {
            id: localOut
            onStreamFinished: root.onLocal(localOut.text)
        }
    }
    Timer {                                     // never let a stuck skill (weather on bad Wi-Fi) hold you up
        id: localGuard
        interval: 8000
        onTriggered: {
            if (!localProc.running) return;
            localProc.running = false;
            root.onLocal("");
        }
    }
    function onLocal(out) {
        localGuard.stop();
        const t = root.localPending;
        if (t.length === 0) return;
        root.localPending = "";
        let r = null;
        try { r = JSON.parse(String(out ?? "").trim().split("\n").pop()); } catch (e) { r = null; }
        if (!r || !r.handled) {
            if (root.authState === "needed") {      // needs Claude, and you're signed out
                root.messages.remove(root.messages.count - 2, 2);
                root.assistantIndex = -1;
                root.pendingAfterLogin = t;
                return;
            }
            root.launch(t);
            return;
        }
        const i = root.assistantIndex;
        if (i < 0 || i >= root.messages.count) return;
        const text = String(r.text ?? "");
        root.messages.setProperty(i, "body", text);
        root.messages.setProperty(i, "done", true);
        root.localNotes = [...root.localNotes, "User: " + t + "\nFriday (on-device): " + text].slice(-6);
        root.lastActivity = Date.now();
        if (root.voiceTurn && root.shown) {
            root.speechRanges = [[0, text.length]];
            root.saveSpoken();
            root.clearSpokenAfter = i;
            root.expectReply = !!r.listen;           // "how are you" keeps talking; "volume up" is done
            root.endAfterSpeaking = !r.listen;
            root.voiceCmd("stop");
            root.voiceCmd("say+ " + JSON.stringify({ text: String(r.say || text), id: 0 }));
            root.voiceCmd("say-end");
        }
        root.voiceTurn = false;
        console.log("[Friday] on-device: " + r.intent);
    }

    function start(t, label, local) {
        root.lastActivity = Date.now();
        root.messages.append({ role: "user", body: (label && label.length > 0) ? label : t, stepsJson: "[]", done: true, spokenJson: "" });
        root.messages.append({ role: "assistant", body: "", stepsJson: "[]", done: false, spokenJson: "" });
        root.assistantIndex = root.messages.count - 1;
        if (root.voiceTurn) {
            root.voiceCmd("stop");
            root.speakingMsg = root.assistantIndex;
            root.spokenIdx = -1;
            root.speechParts = [];
            root.speechRanges = [];
            root.speechFed = 0;
            root.speechChars = 0;
            root.speechBase = 0;
            root.speechWords = [];
            root.speechGroups = [];
        }
        root.steps = [];
        root.gotText = false;
        if (local) root.tryLocal(t);
        else root.launch(t);
    }
    function launch(t) {
        root.steps = [];
        root.gotText = false;
        // anything Friday handled on-device just before goes along as context, so follow-ups make sense
        const prompt = root.localNotes.length > 0
            ? "[Just before this, handled on-device without you, for context:]\n" + root.localNotes.join("\n") + "\n\n[Now:]\n" + t
            : t;
        root.localNotes = [];
        proc.environment = ({
            "FRIDAY_PROMPT": prompt,
            "FRIDAY_SESSION": root.sessionId,
            "FRIDAY_SURFACE": "overlay",
            "FRIDAY_VOICE": root.voiceTurn ? "1" : ""
        });
        proc.command = [root.askBin];
        proc.running = true;
    }

    function addText(s) {
        const i = root.assistantIndex;
        if (i < 0) return;
        root.messages.setProperty(i, "body", root.messages.get(i).body + s);
    }
    function syncSteps() {
        if (root.assistantIndex >= 0)
            root.messages.setProperty(root.assistantIndex, "stepsJson", JSON.stringify(root.steps));
    }
    function pushStep(id, label, icon) {
        root.steps = [...root.steps, { id: id, label: label, icon: icon, state: "run" }];
        root.syncSteps();
    }
    function finishStep(id, ok) {
        root.steps = root.steps.map(s => s.id === id ? Object.assign({}, s, { state: ok ? "done" : "error" }) : s);
        root.syncSteps();
    }

    // ---------------------------------------------------------------- describing tool calls for humans
    function base(p) { return String(p ?? "").split("/").pop(); }
    function describeBash(c) {
        const rules = [
            [/friday-screen|grim/, "Looking at your screen", "visibility"],
            [/friday-windows|hyprctl (clients|activewindow|workspaces)/, "Checking your windows", "grid_view"],
            [/hyprctl dispatch/, "Controlling the desktop", "tune"],
            [/playerctl/, "Controlling media", "music_note"],
            [/wpctl|pactl/, "Adjusting audio", "volume_up"],
            [/brightnessctl/, "Adjusting brightness", "brightness_6"],
            [/pacman|paru|yay|flatpak/, "Checking packages", "inventory_2"],
            [/\bgit\b/, "Inspecting git", "commit"],
            [/nmcli|\bip \b|\bss\b|curl|wget/, "Using the network", "wifi"],
            [/systemctl|journalctl/, "Checking services", "settings"],
            [/\badb\b|fastboot/, "Talking to your phone", "smartphone"],
            [/friday-open|gtk-launch|xdg-open/, "Opening an app", "open_in_new"],
            [/notify-send|friday-notify/, "Sending a notification", "notifications"],
            [/\bdf\b|\bdu\b|lsblk|\bfree\b|lscpu|sensors|\bps\b/, "Reading system stats", "monitor_heart"]
        ];
        for (let i = 0; i < rules.length; i++)
            if (rules[i][0].test(c)) return [rules[i][1], rules[i][2]];
        return ["Running " + (c.length > 46 ? c.slice(0, 46) + "…" : c), "terminal"];
    }
    function describe(b) {
        const n = b.name, inp = b.input ?? {};
        if (n === "Bash") return root.describeBash(String(inp.command ?? ""));
        if (n === "Read") return ["Reading " + root.base(inp.file_path), "description"];
        if (n === "Glob" || n === "Grep") return ["Searching files", "search"];
        if (n === "WebSearch") return ["Searching the web", "travel_explore"];
        if (n === "WebFetch") return ["Reading a web page", "public"];
        if (n === "Edit" || n === "Write" || n === "MultiEdit") return ["Editing " + root.base(inp.file_path), "edit"];
        if (n === "Task") return ["Delegating a sub-task", "account_tree"];
        return [n, "bolt"];
    }

    // ---------------------------------------------------------------- stream-json from `claude -p`
    function handleLine(line) {
        stallWatch.restart();
        const clean = line.trim();
        if (clean.length === 0) return;
        let ev;
        try {
            ev = JSON.parse(clean);
        } catch (e) {
            root.addText(line + "\n");        // plain CLI output / errors
            return;
        }
        if (ev.session_id && (ev.type === "system" || ev.type === "result")) root.sessionId = ev.session_id;

        if (ev.type === "stream_event") {
            const se = ev.event ?? {};
            if (se.type === "content_block_start" && se.content_block?.type === "text" && root.gotText) {
                root.feedSpeech(true);                         // the previous text block is complete: say the rest of it
                const cur = root.messages.get(root.assistantIndex)?.body ?? "";
                if (!cur.endsWith("\n\n")) root.addText("\n\n");
            } else if (se.type === "content_block_delta" && se.delta?.type === "text_delta" && se.delta.text) {
                root.gotText = true;
                root.addText(se.delta.text);
                root.feedSpeech(false);
            }
        } else if (ev.type === "assistant") {
            const blocks = ev.message?.content ?? [];
            for (let i = 0; i < blocks.length; i++) {
                if (blocks[i].type !== "tool_use") continue;
                const d = root.describe(blocks[i]);
                root.pushStep(blocks[i].id, d[0], d[1]);
                root.openTools++;
            }
        } else if (ev.type === "user") {
            const blocks = ev.message?.content;
            if (Array.isArray(blocks)) {
                for (let i = 0; i < blocks.length; i++)
                    if (blocks[i].type === "tool_result") { root.finishStep(blocks[i].tool_use_id, !blocks[i].is_error); root.openTools = Math.max(0, root.openTools - 1); }
            }
        } else if (ev.type === "result") {
            if (ev.is_error) {
                let msg = String(ev.result ?? "Something went wrong.");
                if (!root.gotText && /log ?in|authenticat|credential|api key|401|not logged/i.test(msg) && !/not found/i.test(msg)) {
                    // signed out: drop this half-turn, show the sign-in card, retry automatically afterwards
                    const last = root.messages.get(root.messages.count - 2);
                    root.pendingAfterLogin = last ? last.body : "";
                    root.messages.remove(root.messages.count - 1);
                    root.messages.remove(root.messages.count - 1);
                    root.assistantIndex = -1;
                    root.authState = "needed";
                    return;
                }
                root.addText((root.gotText ? "\n\n" : "") + "**Error:** " + msg);
            } else if (!root.gotText && ev.result) {
                root.addText(String(ev.result));
            }
        }
    }

    Process {
        id: proc
        stdout: SplitParser {
            onRead: data => root.handleLine(data)
        }
        onExited: (exitCode, exitStatus) => {
            const i = root.assistantIndex;
            if (i >= 0 && i < root.messages.count) {
                const m = root.messages.get(i);
                if (m && m.body.length === 0 && exitCode !== 0 && root.queued === "")
                    root.addText("**Error:** Friday exited with code " + exitCode + ".");
                root.messages.setProperty(i, "done", true);
                const raw = root.messages.get(i).body;
                const tag = root.replyTag(raw);
                if (tag.length > 0 || raw !== root.untag(raw)) root.messages.setProperty(i, "body", root.untag(raw));
                root.lastTag = tag;
                // Finished while you were elsewhere: tap you on the shoulder, like a real assistant would.
                const fin = root.messages.get(i);
                if (!root.shown && fin && fin.body.length > 0 && root.queued === "") {
                    const snippet = root.plain(fin.body);
                    Quickshell.execDetached(["notify-send", "-a", "Friday", "Friday", snippet.length > 160 ? snippet.slice(0, 160) + "…" : snippet]);
                }
            }
            // A spoken question gets a spoken answer, already playing sentence by sentence; close it out.
            if (root.voiceTurn && root.shown && root.queued === "" && i >= 0 && i < root.messages.count) {
                root.feedSpeech(true);
                // Friday decides: keep listening for your reply, or wrap up ("Goodnight!") and close.
                // No tag means it didn't say, so it listens; a few seconds of silence still ends it.
                root.expectReply = root.lastTag !== "end";
                root.endAfterSpeaking = root.lastTag === "end";
                if (root.speechParts.length > 0) root.voiceCmd("say-end");   // everything readable is already queued
                else root.afterSpeaking();                                   // nothing to say (only code, say)
            }
            if (root.queued === "") root.voiceTurn = false;
            root.lastActivity = Date.now();
            if (root.queued !== "") {
                const q = root.queued;
                root.queued = "";
                root.start(q, undefined, root.localEnabled && root.selection.length === 0);
            } else if (root.archiveWhenDone && !root.shown) {
                root.archiveChat();                    // you closed the panel while it worked: file it now
            }
            root.archiveWhenDone = false;
        }
    }

    // ---------------------------------------------------------------- approvals
    property var approvalQueue: []              // more requests while one is on screen wait their turn
    function requestApproval(payload) {
        let a;
        try {
            a = JSON.parse(payload);
        } catch (e) {
            console.log("[Friday] bad approval payload:", e);
            return;
        }
        // friday-approve makes ids with uuid4().hex; anything else didn't come from it
        if (!a || !/^[0-9a-f]{32}$/.test(String(a.id ?? ""))) {
            console.log("[Friday] ignored an approval request with a malformed id");
            return;
        }
        if (root.approval) {                        // never swap the card you're looking at
            root.approvalQueue = [...root.approvalQueue, a];
            return;
        }
        root.approval = a;
        root.show();
        // In a spoken conversation, ask out loud and listen for the answer.
        if (root.voiceTurn || root.voiceSession) root.askApprovalAloud(false);
    }
    function askApprovalAloud(again) {
        const a = root.approval;
        if (!a) return;
        const why = String(a.reason ?? "").replace(/\.$/, "");
        const q = a.risk === "high"
            ? (again ? "This one's high risk, so say confirm if you want me to do it." : "Heads up, this one's high risk: " + why + ". Say confirm to go ahead, or no to skip it.")
            : (again ? "Sorry, should I go ahead? Yes or no." : "I need your okay for this: " + why + ". Should I go ahead?");
        root.expectReply = true;
        root.voiceCmd("say+ " + JSON.stringify(q));
        root.voiceCmd("say-end");
    }
    function resolveApproval(allow) {
        const a = root.approval;
        if (!a) return;
        root.approval = null;
        if (/^[0-9a-f]{32}$/.test(String(a.id))) {
            // arguments, not a pasted-together command line: nothing in the request can become shell code
            Quickshell.execDetached(["bash", "-c", 'umask 077; mkdir -p "$1/res" && printf %s "$2" > "$1/res/$3"',
                                     "friday", root.runtimeDir, allow ? "allow" : "deny", String(a.id)]);
        }
        if (root.approvalQueue.length > 0) {        // the next one, if any
            const next = root.approvalQueue[0];
            root.approvalQueue = root.approvalQueue.slice(1);
            root.requestApproval(JSON.stringify(next));
        }
    }

    // ---------------------------------------------------------------- live context + instant controls
    function refreshContext() { if (!ctxProc.running) ctxProc.running = true; }
    function act(name) {
        Quickshell.execDetached([root.doBin, name]);
        ctxDelay.restart();
    }
    Process {
        id: ctxProc
        command: [root.ctxBin]
        stdout: SplitParser {
            onRead: data => {
                if (data === root.ctxRaw) return;      // nothing changed: don't rebuild the UI
                try {
                    root.ctx = JSON.parse(data);
                    root.ctxRaw = data;
                } catch (e) { }
            }
        }
    }
    Timer { id: ctxDelay; interval: 350; onTriggered: root.refreshContext() }
    Timer { interval: 5000; repeat: true; running: root.shown; onTriggered: root.refreshContext() }

    // ---------------------------------------------------------------- sign-in
    function checkAuth() { if (!authProc.running) authProc.running = true; }
    function startLogin() { if (!loginProc.running) loginProc.running = true; }
    function resumeAfterLogin() {
        root.authState = "ok";
        const p = root.pendingAfterLogin;
        root.pendingAfterLogin = "";
        if (p.length > 0) root.ask(p);
    }
    Process {
        id: authProc
        command: [root.loginBin, "--check"]
        stdout: SplitParser {
            onRead: data => {
                const v = data.trim();
                if (v === "no") root.authState = "needed";
                else if (v === "ok" || v === "unknown") {
                    if (root.authState === "needed") root.resumeAfterLogin();
                    else root.authState = "ok";
                }
            }
        }
    }
    Process {
        id: loginProc
        command: [root.loginBin]
        onExited: root.checkAuth()
    }

    // ---------------------------------------------------------------- plan usage, focus, clock
    Process { id: usageProc; command: [root.binDir + "friday-usage"]; onExited: usageFile.reload() }
    Timer {                                     // every 3 min while you're looking, every 15 min otherwise
        interval: root.shown ? 180000 : 900000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!usageProc.running) usageProc.running = true
    }
    FileView {
        id: usageFile
        path: root.runtimeDir + "/usage.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.usage = JSON.parse(text()); } catch (e) { } }
    }
    FileView {
        id: focusFile
        path: root.runtimeDir + "/focus.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.focus = JSON.parse(text()); } catch (e) { root.focus = ({}); } }
        onLoadFailed: root.focus = ({})
    }
    Timer { id: focusPoke; interval: 400; onTriggered: focusFile.reload() }
    Timer {
        interval: 1000
        running: root.shown || root.focusActive
        repeat: true
        onTriggered: root.now = Date.now()
    }
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            root.now = Date.now();
            focusFile.reload();
            usageFile.reload();
        }
    }

    // ---------------------------------------------------------------- voice
    function voiceCmd(c) { if (voiceProc.running) voiceProc.write(c + "\n"); }
    function listen() {
        root.show();
        if (root.voiceState === "unavailable" || root.voiceState === "off") return;
        root.voiceCmd(root.hearing ? "cancel" : "listen");
    }
    function toggleWake() {
        root.wakeEnabled = !root.wakeEnabled;
        root.voiceCmd(root.wakeEnabled ? "unmute" : "mute");
        Quickshell.execDetached(["bash", "-c", "mkdir -p \"$(dirname \"$1\")\" && echo \"$2\" > \"$1\"", "_", root.wakeFile, root.wakeEnabled ? "on" : "off"]);
    }
    // The conversational bit: what happens when Friday finishes talking.
    function afterSpeaking() {
        if (root.endAfterSpeaking) {               // "goodnight": say it, then get out of the way
            root.endAfterSpeaking = false;
            root.expectReply = false;
            if (root.shown) closeTimer.restart();
            return;
        }
        if (root.expectReply && root.shown) {
            root.expectReply = false;
            root.voiceCmd("listen followup");      // no wake word needed: it just asked you something
        } else if (root.voiceSession) {
            dismissTimer.restart();                // like Siri: step out of the way when the exchange is done
        }
    }
    Timer {
        id: closeTimer
        interval: 1200
        onTriggered: if (!root.hearing && !root.running && !root.approval && root.voiceState !== "speaking") root.hide()
    }
    Timer {
        id: dismissTimer
        interval: 9000
        onTriggered: {
            if (root.voiceSession && !root.hearing && !root.running && !root.approval && root.voiceState !== "speaking")
                root.hide();
        }
    }
    FileView {
        path: root.wakeFile
        onLoaded: { root.wakeEnabled = text().trim() === "on"; root.voiceBooted = true; }
        onLoadFailed: root.voiceBooted = true      // never set: wake word stays off
    }
    // Read the whole answer aloud, paragraph by paragraph, each one sent the moment it's complete (whole
    // paragraphs sound natural; half sentences don't). Only code blocks and tables are screen-only.
    function feedSpeech(final) {
        if (!root.voiceTurn || root.speakingMsg !== root.assistantIndex || root.assistantIndex < 0) return;
        const body = root.messages.get(root.assistantIndex)?.body ?? "";
        let pos = root.speechFed;
        while (pos < body.length) {
            while (pos < body.length && /\s/.test(body[pos])) pos++;
            if (pos >= body.length) break;
            if (body.startsWith("```", pos)) {               // code: shown, never read out
                const close = body.indexOf("```", pos + 3);
                if (close < 0) { if (final) pos = body.length; break; }
                pos = close + 3;
                continue;
            }
            let end = body.indexOf("\n\n", pos);
            const fence = body.indexOf("```", pos);
            if (fence >= 0 && (end < 0 || fence < end)) end = fence;
            if (end < 0) {
                if (!final) break;                           // this paragraph is still being written
                end = body.length;
            }
            const said = root.speakable(body.slice(pos, end));
            if (said.length > 0 && root.speechChars < 6000) {
                root.speechChars += said.length;
                root.speechParts = [...root.speechParts, said];
                root.speechRanges = [...root.speechRanges, [pos, end]];
                root.saveSpoken();
                root.voiceCmd("say+ " + JSON.stringify({ text: said, id: root.speechRanges.length - 1 }));
            }
            pos = end;
        }
        root.speechFed = pos;
    }
    function saveSpoken() {
        if (root.speakingMsg < 0 || root.speakingMsg >= root.messages.count) return;
        root.messages.setProperty(root.speakingMsg, "spokenJson",
            JSON.stringify({ words: root.speechWords, ranges: root.speechRanges, groups: root.speechGroups }));
    }

    // Voice replies end with a hidden [[listen]] / [[end]] tag: Claude's call on whether you'll answer.
    // (Also hides a half-streamed "[[li" at the very end.)
    function untag(t) { return String(t ?? "").replace(/\s*\[\[(listen|end)\]\]\s*$/i, "").replace(/\s*\[\[[a-z]{0,6}\]?$/i, ""); }
    function replyTag(t) {
        const m = String(t ?? "").match(/\[\[(listen|end)\]\]\s*$/i);
        return m ? m[1].toLowerCase() : "";
    }
    // Markdown -> what you'd actually say: no code, no tables, list items and headings become sentences.
    function speakable(md) {
        let t = root.untag(String(md ?? "").replace(/\[\[(listen|end)\]\]/gi, ""));
        t = t.replace(/```[\s\S]*?```/g, " ").replace(/```[\s\S]*$/, " ").replace(/^\*\*Error:\*\*/, "Sorry, something went wrong.");
        t = t.split("\n")
            .filter(l => !/^\s*\|/.test(l) && !/^\s*[-=*_]{3,}\s*$/.test(l))
            .map(l => {
                const listy = /^\s*([-•*+]|\d+[.)]|#{1,6})\s+/.test(l);
                let x = l.replace(/^\s*#{1,6}\s+/, "").replace(/^\s*([-•*+]|\d+[.)])\s+/, "").trim();
                if (listy && x.length > 0 && !/[.!?:;,…]["')\]]*$/.test(x)) x += ".";
                return x;
            })
            .join("\n");
        return t.replace(/`([^`]*)`/g, "$1").replace(/[*_#>|]/g, "").replace(/\[(.*?)\]\(.*?\)/g, "$1").replace(/\s+/g, " ").trim();
    }
    function onVoiceEvent(line) {
        let e;
        try { e = JSON.parse(line); } catch (err) { return; }
        voiceWatch.restart();
        switch (e.ev) {
        case "hello": break;
        case "ready": root.voiceState = root.restState; break;
        case "muted": root.voiceState = "muted"; break;
        case "unavailable": root.voiceState = "unavailable"; break;
        case "prewake":
            closeTimer.stop();
            if (!root.shown) root.voiceSession = true;
            dismissTimer.stop();
            root.show();
            root.voiceState = "listening";
            root.voicePartial = "";
            root.voiceLevel = 0;
            break;
        case "wake":
            closeTimer.stop();
            root.endAfterSpeaking = false;
            if (!root.shown) root.voiceSession = true;
            dismissTimer.stop();
            root.show();
            root.voiceState = "listening";
            root.voicePartial = "";
            root.voiceLevel = 0;
            break;
        case "level": root.voiceLevel = e.v; break;
        case "words":
            if (root.speakingMsg >= 0) {
                if (typeof e.id === "number" && e.id >= 0) {
                    const g = root.speechGroups.slice();
                    g[e.id] = [root.speechWords.length, (e.words ?? []).length];
                    root.speechGroups = g;
                }
                root.speechWords = [...root.speechWords, ...(e.words ?? [])];
                root.saveSpoken();
            }
            break;
        case "word": root.spokenIdx = root.speechBase + e.i; break;
        case "partial": root.voicePartial = e.text; break;
        case "transcribing": root.voiceState = "transcribing"; root.voiceLevel = 0; break;
        case "final": {
            root.voiceState = root.restState;
            const t = String(e.text ?? "").trim();
            root.voicePartial = "";
            if (t.length === 0) break;
            if (root.approval) {                 // answer an approval card out loud
                const high = root.approval.risk === "high";
                // Only a short, clear answer counts: "yes", "go ahead", "confirm". A "yes" buried in a longer
                // sentence (or in a video playing nearby) doesn't approve anything.
                const short = t.split(/\s+/).length <= 5;
                if (/^\W*(no|nope|nah|don'?t|do not|deny|stop|cancel|wait|hold on|not now|skip)\b/i.test(t)) {
                    root.resolveApproval(false);
                    root.voiceCmd("say " + JSON.stringify("Okay, skipped."));
                } else if (high && short && /^\W*(confirm(ed)?|yes,? confirm|i'?m sure|yes,? i'?m sure)\b/i.test(t)) {
                    root.resolveApproval(true);
                } else if (!high && short && /^\W*(yes|yeah|yep|yup|sure|okay|ok|allow( it)?|approve( it)?|go ahead|do it|run it|go for it|proceed|haan|confirm)\b/i.test(t)) {
                    root.resolveApproval(true);
                } else {
                    root.askApprovalAloud(true);           // didn't catch a clear yes/no: ask again
                }
                break;
            }
            // Little phrases a person would just say, handled like a person would.
            if (/^(never ?mind|cancel|forget it|nothing|that'?s all|that'?s it|stop)\W*$/i.test(t)) { root.hide(); break; }
            if (/^(thanks?|thank you|cool|perfect|great|nice|awesome|got it),?( friday)?\W*$/i.test(t)) {
                root.voiceCmd("say " + JSON.stringify("Anytime."));
                root.expectReply = false;
                root.endAfterSpeaking = true;
                break;
            }
            if (/^(new chat|start over|fresh start)\W*$/i.test(t)) { root.fresh(); break; }
            root.voiceTurn = true;
            root.ask(t);
            break;
        }
        case "cancel":
            root.voiceState = root.restState;
            root.voicePartial = "";
            root.voiceLevel = 0;
            if (e.reason === "false wake" && root.voiceSession && root.messages.count === 0) { root.hide(); break; }
            if (root.voiceSession) dismissTimer.restart();   // you went quiet: let it go
            break;
        case "speaking":
            root.voiceState = e.on ? "speaking" : root.restState;
            if (!e.on) {
                if (root.clearSpokenAfter >= 0 && root.clearSpokenAfter < root.messages.count)
                    root.messages.setProperty(root.clearSpokenAfter, "spokenJson", "");
                root.clearSpokenAfter = -1;
                root.speechBase = root.speechWords.length;
                if (!root.running) {
                    // done talking: the answer goes back to its normal formatting (bullets, bold…)
                    if (root.speakingMsg >= 0 && root.speakingMsg < root.messages.count)
                        root.messages.setProperty(root.speakingMsg, "spokenJson", "");
                    root.spokenIdx = 9999;
                    root.speakingMsg = -1;
                }
            }
            if (!e.on) root.afterSpeaking();
            break;
        case "error":
            console.log("[Friday voice]", e.msg);
            break;
        }
    }
    Process {
        id: voiceProc
        command: [root.binDir + "friday-voice"]
        environment: ({ "FRIDAY_WAKE": root.wakeEnabled ? "on" : "off" })
        stdinEnabled: true
        running: root.voiceBooted
        stdout: SplitParser { onRead: data => root.onVoiceEvent(data) }
        onExited: (code, status) => {
            if (root.voiceState !== "unavailable") {
                root.voiceState = "off";
                voiceRestart.restart();          // crashed? come back in a few seconds
            }
        }
    }
    Timer { id: voiceRestart; interval: 4000; onTriggered: voiceProc.running = true }
    // Watchdogs, so Friday can never sit frozen on your screen:
    //  * voice: listening/transcribing/speaking with no word from the voice process for 45 s -> cancel, then restart it
    //  * a turn: no output at all for 3 minutes (and no approval card waiting on you) -> stop it and say so
    Timer {
        id: voiceWatch
        interval: 60000
        onTriggered: {
            if (!(root.hearing || root.voiceState === "speaking")) return;
            console.log("[Friday] voice went quiet in state " + root.voiceState + "; cancelling");
            root.voiceCmd("cancel");
            root.voiceState = root.restState;
            root.voiceSession = false;
            root.expectReply = false;
            root.endAfterSpeaking = false;
            voiceKick.restart();
        }
    }
    Timer {
        id: voiceKick                            // still no sign of life after the cancel: restart the voice process
        interval: 6000
        onTriggered: if (voiceProc.running && voiceWatch.running === false) { voiceProc.running = false; voiceRestart.restart(); }
    }
    property int openTools: 0                   // tool calls started but not finished (a long build is not "stuck")
    Timer {
        id: stallWatch
        interval: 180000
        repeat: true
        running: proc.running
        onRunningChanged: if (running) root.openTools = 0
        onTriggered: {
            if (!proc.running || root.approval || root.openTools > 0) return;
            console.log("[Friday] no output for 3 min; stopping the turn");
            proc.running = false;
            root.addText((root.gotText ? "\n\n" : "") + "_That got stuck (nothing back for 3 minutes), so I stopped it. Try again?_");
        }
    }
    // When the voice code is updated, restart it so the shell and the voice never speak different protocols.
    FileView {
        path: root.home + "/.local/share/friday/voice/friday_voice.py"
        watchChanges: true
        onFileChanged: voiceReload.restart()
    }
    Timer {
        id: voiceReload
        interval: 1500
        onTriggered: {
            if (voiceProc.running) {
                voiceProc.running = false;           // onExited brings it back with the new code
            } else {
                voiceProc.running = true;
            }
        }
    }

    Timer {
        id: cloakTimer
        onTriggered: root.cloaked = false
    }

    IpcHandler {
        target: "friday"

        function toggle(): void { root.toggle(); }
        function show(): void { root.show(); }
        function hide(): void { root.hide(); }
        function ask(text: string): void {
            // From the Super search: a new question is a new topic. The previous chat stays resumable.
            if (!proc.running && root.messages.count > 0) root.archiveChat();
            root.ask(text);
        }
        function resume(): void { root.show(); root.resume(); }
        function newChat(): void { root.fresh(); }
        function ping(): string { return "pong"; }
        function listen(): void { root.listen(); }
        function toggleWake(): void { root.toggleWake(); }
        function stopSpeaking(): void { root.voiceCmd("stop"); }
        function withSelection(text: string): void { root.withSelection(text); }
        function approval(payload: string): void { root.requestApproval(payload); }
        // Say something out loud (reminders and timers use this). Never talks over you while you're speaking.
        function announce(text: string): void {
            if (!root.hearing && root.voiceState !== "unavailable" && root.voiceState !== "off")
                root.voiceCmd("say " + JSON.stringify(text));
        }
        function cloak(ms: int): void {
            root.cloaked = true;
            cloakTimer.interval = ms;
            cloakTimer.restart();
        }
    }
}
