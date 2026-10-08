pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Friday's design tokens. Warm, quiet, Claude-like: ivory on charcoal, one terracotta accent.
// Light/dark follows illogical-impulse's generated scheme (by background luminance).
Singleton {
    id: root

    // ---------------------------------------------------------------- mode
    property bool light: false
    function luminance(hex) {
        const h = String(hex).replace("#", "");
        if (h.length < 6) return 0;
        const o = h.length === 8 ? 2 : 0;          // tolerate #AARRGGBB
        const r = parseInt(h.substr(o, 2), 16) / 255, g = parseInt(h.substr(o + 2, 2), 16) / 255, b = parseInt(h.substr(o + 4, 2), 16) / 255;
        return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    }
    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/quickshell/user/generated/colors.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const s = JSON.parse(text());
                if (s.background) root.light = root.luminance(s.background) > 0.5;
            } catch (e) { }
        }
    }
    function pick(dark, lightValue) { return root.light ? lightValue : dark; }

    // ---------------------------------------------------------------- surfaces
    readonly property color glass: pick(Qt.rgba(0.149, 0.145, 0.137, 0.80), Qt.rgba(0.980, 0.976, 0.961, 0.84))
    readonly property color raised: pick(Qt.rgba(1, 1, 1, 0.045), Qt.rgba(0, 0, 0, 0.035))
    readonly property color hover: pick(Qt.rgba(1, 1, 1, 0.065), Qt.rgba(0, 0, 0, 0.05))
    readonly property color selected: pick(Qt.rgba(1, 1, 1, 0.085), Qt.rgba(0, 0, 0, 0.065))
    readonly property color hairline: pick(Qt.rgba(1, 1, 1, 0.085), Qt.rgba(0, 0, 0, 0.08))
    readonly property color rim: pick(Qt.rgba(1, 1, 1, 0.13), Qt.rgba(1, 1, 1, 0.7))      // top-edge highlight
    readonly property color well: pick(Qt.rgba(0, 0, 0, 0.24), Qt.rgba(0, 0, 0, 0.045))     // code / command wells
    readonly property color userBubble: pick(Qt.rgba(1, 1, 1, 0.075), Qt.rgba(0, 0, 0, 0.055))
    readonly property color shadow: pick(Qt.rgba(0, 0, 0, 0.38), Qt.rgba(0, 0, 0, 0.16))

    // ---------------------------------------------------------------- text (all ≥ 4.5:1 on glass)
    readonly property color text: pick("#F4F3EE", "#1F1E1D")
    readonly property color textSecondary: pick("#B6B4AC", "#5C5B57")
    readonly property color textTertiary: pick("#8C8A83", "#8A8882")

    // ---------------------------------------------------------------- accent + states
    readonly property color accent: pick("#D97757", "#C2603E")
    readonly property color accentHover: pick("#E2876A", "#B05434")
    readonly property color accentInk: "#FFFFFF"
    readonly property color accentSoft: pick(Qt.rgba(0.851, 0.467, 0.341, 0.16), Qt.rgba(0.761, 0.376, 0.243, 0.11))
    readonly property color warn: pick("#E3A857", "#B7791F")
    readonly property color warnSoft: pick(Qt.rgba(0.89, 0.66, 0.34, 0.15), Qt.rgba(0.72, 0.47, 0.12, 0.12))
    readonly property color danger: pick("#EC6A5E", "#C8382C")
    readonly property color dangerSoft: pick(Qt.rgba(0.925, 0.416, 0.369, 0.15), Qt.rgba(0.784, 0.22, 0.172, 0.10))
    readonly property color success: pick("#8FBF8A", "#3F7F3A")

    // ---------------------------------------------------------------- type
    readonly property string sans: "Google Sans Flex"
    readonly property string serif: serifLoader.status === FontLoader.Ready ? serifLoader.name : "serif"
    readonly property string mono: "JetBrains Mono NF"
    readonly property string icons: "Material Symbols Rounded"
    readonly property string fontDir: Quickshell.env("HOME") + "/.config/quickshell/friday/assets/fonts/"
    FontLoader { id: serifLoader; source: "file://" + root.fontDir + "source-serif-4-latin-400-normal.woff" }
    FontLoader { source: "file://" + root.fontDir + "source-serif-4-latin-500-normal.woff" }
    FontLoader { source: "file://" + root.fontDir + "source-serif-4-latin-600-normal.woff" }
    FontLoader { source: "file://" + root.fontDir + "source-serif-4-latin-400-italic.woff" }

    // ---------------------------------------------------------------- motion (Apple's sheet curve)
    readonly property var curve: [0.32, 0.72, 0, 1, 1, 1]
    readonly property var curveIn: [0.4, 0, 1, 1, 1, 1]
    readonly property var spring: [0.16, 1, 0.3, 1, 1, 1]   // fast out, long soft settle (no overshoot)
    readonly property int fast: 140
    readonly property int base: 240
    readonly property int slow: 340
}
