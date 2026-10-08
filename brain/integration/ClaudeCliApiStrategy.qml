import QtQuick

// Installed into ii/services/ai/ by friday-integrate. Safe to delete (friday-integrate --revert).
ApiStrategy {
    property string pendingPrompt: ""
    property bool gotText: false
    property bool needBreak: false
    property string noise: ""

    function buildEndpoint(model) { return ""; }
    function buildAuthorizationHeader(apiKeyEnvVarName) { return ""; }

    // The sidebar is stateless on our side: we send the transcript, Friday answers.
    function buildRequestData(model, messages, systemPrompt, temperature, tools, filePath) {
        const turns = messages.filter(m => (m.rawContent ?? "").length > 0);
        let prompt = "";
        if (turns.length > 1) {
            prompt += "Earlier in this sidebar chat:\n\n";
            for (let i = 0; i < turns.length - 1; i++) {
                prompt += (turns[i].role === "user" ? "Onkar: " : "Friday: ") + turns[i].rawContent + "\n\n";
            }
            prompt += "Current message from Onkar:\n";
        }
        prompt += turns.length > 0 ? turns[turns.length - 1].rawContent : "";
        pendingPrompt = prompt;
        return {};
    }

    function finalizeScriptContent(scriptContent) {
        const eof = "__FRIDAY_EOF_7f3a91__";
        return "#!/usr/bin/env bash\n"
            + "unset FRIDAY_PROMPT FRIDAY_SESSION\n"
            + "export FRIDAY_SURFACE=sidebar\n"
            + "exec \"$HOME/.local/share/friday/bin/friday-ask\" <<'" + eof + "'\n"
            + pendingPrompt + "\n" + eof + "\n";
    }

    function describeTool(block) {
        const inp = block.input ?? {};
        let d = inp.command ?? inp.file_path ?? inp.pattern ?? inp.url ?? inp.query ?? "";
        d = String(d).replace(/\s+/g, " ").trim();
        if (d.length > 90) d = d.slice(0, 90) + "…";
        return d.length > 0 ? `${block.name}: \`${d}\`` : block.name;
    }

    function parseResponseLine(line, message) {
        const s = line.trim();
        if (s.length === 0) return {};
        let ev;
        try { ev = JSON.parse(s); } catch (e) { noise += s + "\n"; return {}; }

        if (ev.type === "stream_event") {
            const e = ev.event ?? {};
            if (e.type === "content_block_start" && e.content_block?.type === "text" && needBreak) {
                message.content += "\n\n";
                message.rawContent += "\n\n";
                needBreak = false;
            } else if (e.type === "content_block_delta" && e.delta?.type === "text_delta") {
                message.content += e.delta.text;
                message.rawContent += e.delta.text;
                gotText = true;
            }
            return {};
        }

        if (ev.type === "assistant") {
            const blocks = ev.message?.content ?? [];
            for (const b of blocks) {
                if (b.type === "tool_use") {
                    // Display only: keep tool chatter out of rawContent so it isn't fed back as history
                    message.content += `\n\n> ⚙ ${describeTool(b)}\n\n`;
                    needBreak = true;
                }
            }
            return {};
        }

        if (ev.type === "result") {
            if (ev.is_error || (!gotText && !(ev.result?.length > 0))) {
                let err = ev.result?.length > 0 ? ev.result : noise.trim();
                if (err.length === 0) err = "Friday returned nothing.";
                if (/login|authenticat|credential|401/i.test(err))
                    err += "\n\nRun `claude` once in a terminal and use `/login`.";
                message.content += `**Error**: ${err}`;
                message.rawContent += `**Error**: ${err}`;
            } else if (!gotText) {
                message.content += ev.result;
                message.rawContent += ev.result;
            }
            const u = ev.usage;
            if (u) {
                const i = (u.input_tokens ?? 0) + (u.cache_read_input_tokens ?? 0) + (u.cache_creation_input_tokens ?? 0);
                const o = u.output_tokens ?? 0;
                return { finished: true, tokenUsage: { input: i, output: o, total: i + o } };
            }
            return { finished: true };
        }
        return {};
    }

    function onRequestFinished(message) {
        if (!gotText && message.content.length === 0 && noise.trim().length > 0) {
            message.content += "**Error**: " + noise.trim();
        }
        return {};
    }

    function reset() {
        pendingPrompt = "";
        gotText = false;
        needBreak = false;
        noise = "";
    }
}
