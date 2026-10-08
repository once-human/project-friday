pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Friday state + the bridge to ~/.local/share/friday/bin/friday-ask (which drives the Claude Code CLI).
Singleton {
    id: root

    property bool shown: false
    property bool cloaked: false                // briefly hide the overlay (screenshots)
    readonly property bool running: proc.running
    property string sessionId: ""               // Claude Code session, so follow-ups keep full context
    property var approval: null                 // {id, tool, command, reason, risk} while a card is up
    property string queued: ""
    property var ctx: ({})                      // live desktop snapshot from friday-context
    property var history: []                    // prompts, newest last (Up arrow in the input)
    property string authState: "unknown"        // unknown | ok | needed
    property string pendingAfterLogin: ""
    property double lastActivity: 0             // ms; drives "fresh chat on summon"
    property var archived: null                 // {items, sessionId, title}: the chat you can Resume
    readonly property bool resumable: archived !== null
    readonly property int staleMs: 3 * 60 * 1000
    property string selection: ""               // text highlighted elsewhere (Super+Shift+Space)
    property var usage: ({})                    // Claude plan limits from friday-usage
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
        // Siri-style: if you come back after a while, you get a clean slate (previous chat stays one key away).
        if (!root.shown && !proc.running && !root.approval && root.messages.count > 0
                && Date.now() - root.lastActivity > root.staleMs)
            root.archiveChat();
        root.shown = true;
        root.refreshContext();
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
            root.ask("There's an image on my clipboard. Save it with `mkdir -p /tmp/friday && wl-paste --type image/png > /tmp/friday/clip.png`, look at it, and tell me what it is and anything useful about it.", "What's in the image I copied?");
            return;
        }
        clipProc.running = true;
    }
    Process {
        id: clipProc
        command: ["bash", "-c", "wl-paste --no-newline 2>/dev/null | head -c 6000"]
        stdout: StdioCollector {
            id: clipOut
            onStreamFinished: root.withSelection(clipOut.text)
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
        root.shown = false;
        root.selection = "";
    }
    function toggle() { root.shown ? root.hide() : root.show(); }

    // ---------------------------------------------------------------- conversation
    function newChat() {
        root.queued = "";
        if (proc.running) proc.running = false;
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
            items.push({ role: m.role, body: m.body, stepsJson: m.stepsJson, done: true });
        }
        root.archived = { items: items, sessionId: root.sessionId, title: items.length > 0 ? items[0].body : "" };
        root.newChat();
    }
    function fresh() {                          // Ctrl+N / the new-chat button: keep the old one resumable
        if (proc.running) root.stop();
        if (root.messages.count > 0) root.archiveChat();
        else root.newChat();
    }
    function resume() {
        const a = root.archived;
        if (!a) return;
        root.archived = null;
        root.newChat();
        for (let i = 0; i < a.items.length; i++) root.messages.append(a.items[i]);
        root.sessionId = a.sessionId;
        root.lastActivity = Date.now();
    }
    function copy(text) { Quickshell.execDetached(["wl-copy", "--", String(text)]); }
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
        root.history = [...root.history.filter(h => h !== t), t].slice(-40);
        root.show();
        if (root.authState === "needed") {      // signed out: park the request, the sign-in card is showing
            root.pendingAfterLogin = t;
            return;
        }
        if (proc.running) {          // interrupt the current turn, then run the new one
            root.queued = t;
            proc.running = false;
            return;
        }
        root.start(t, label);
    }

    function start(t, label) {
        root.lastActivity = Date.now();
        root.messages.append({ role: "user", body: (label && label.length > 0) ? label : t, stepsJson: "[]", done: true });
        root.messages.append({ role: "assistant", body: "", stepsJson: "[]", done: false });
        root.assistantIndex = root.messages.count - 1;
        root.steps = [];
        root.gotText = false;
        proc.environment = ({
            "FRIDAY_PROMPT": t,
            "FRIDAY_SESSION": root.sessionId,
            "FRIDAY_SURFACE": "overlay"
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
                const cur = root.messages.get(root.assistantIndex)?.body ?? "";
                if (!cur.endsWith("\n\n")) root.addText("\n\n");
            } else if (se.type === "content_block_delta" && se.delta?.type === "text_delta" && se.delta.text) {
                root.gotText = true;
                root.addText(se.delta.text);
            }
        } else if (ev.type === "assistant") {
            const blocks = ev.message?.content ?? [];
            for (let i = 0; i < blocks.length; i++) {
                if (blocks[i].type !== "tool_use") continue;
                const d = root.describe(blocks[i]);
                root.pushStep(blocks[i].id, d[0], d[1]);
            }
        } else if (ev.type === "user") {
            const blocks = ev.message?.content;
            if (Array.isArray(blocks)) {
                for (let i = 0; i < blocks.length; i++)
                    if (blocks[i].type === "tool_result") root.finishStep(blocks[i].tool_use_id, !blocks[i].is_error);
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
                // Finished while you were elsewhere: tap you on the shoulder, like a real assistant would.
                const fin = root.messages.get(i);
                if (!root.shown && fin && fin.body.length > 0 && root.queued === "") {
                    const snippet = root.plain(fin.body);
                    Quickshell.execDetached(["notify-send", "-a", "Friday", "Friday", snippet.length > 160 ? snippet.slice(0, 160) + "…" : snippet]);
                }
            }
            root.lastActivity = Date.now();
            if (root.queued !== "") {
                const q = root.queued;
                root.queued = "";
                root.start(q);
            }
        }
    }

    // ---------------------------------------------------------------- approvals
    function requestApproval(payload) {
        try {
            root.approval = JSON.parse(payload);
        } catch (e) {
            console.log("[Friday] bad approval payload:", e);
            return;
        }
        root.show();
    }
    function resolveApproval(allow) {
        const a = root.approval;
        if (!a) return;
        root.approval = null;
        Quickshell.execDetached(["bash", "-c",
            "mkdir -p '" + root.runtimeDir + "/res' && printf %s " + (allow ? "allow" : "deny") + " > '" + root.runtimeDir + "/res/" + a.id + "'"]);
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
                try { root.ctx = JSON.parse(data); } catch (e) { }
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
    Timer {
        interval: 180000
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
        function withSelection(text: string): void { root.withSelection(text); }
        function approval(payload: string): void { root.requestApproval(payload); }
        function cloak(ms: int): void {
            root.cloaked = true;
            cloakTimer.interval = ms;
            cloakTimer.restart();
        }
    }
}
