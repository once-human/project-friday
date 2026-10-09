import QtQuick
import QtQuick.Layouts
import qs.services

// One turn. You: a quiet bubble on the right. Friday: plain conversational text, with what it did tucked above.
Item {
    id: d

    required property int index
    required property string role
    required property string body
    required property string stepsJson
    required property bool done
    required property string spokenJson

    // live speech: what Friday says out loud, sentence by sentence, lit up as you hear it
    readonly property var spoken: {
        if (!spokenJson) return null;
        try { return JSON.parse(spokenJson); } catch (e) { return null; }
    }
    readonly property bool live: Brain.speakingMsg === index
    // The answer in its own order: paragraphs Friday reads aloud light up word by word (said = solid, the word
    // you're hearing glows, the rest waits), and code, tables and anything unspoken stay normal formatted text.
    readonly property var segments: {
        const body = Brain.untag(d.body);
        const sp = d.spoken;
        if (!sp || !sp.ranges || sp.ranges.length === 0 || !sp.words || sp.words.length === 0)
            return body.length > 0 ? [{ rich: false, text: body }] : [];
        const cur = d.live ? Brain.spokenIdx : 999999;
        const esc = t => String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        const out = [];
        let at = 0;
        sp.ranges.forEach((r, k) => {
            const a = Math.max(at, Math.min(r[0], body.length)), b = Math.min(r[1], body.length);
            if (a > at && body.slice(at, a).trim().length > 0) out.push({ rich: false, text: body.slice(at, a).trim() });
            const g = sp.groups ? sp.groups[k] : (sp.ranges.length === 1 ? [0, sp.words.length] : null);
            if (g && g[1] > 0) {
                const html = sp.words.slice(g[0], g[0] + g[1]).map((w, n) => {
                    const i = g[0] + n;
                    const c = i < cur ? Theme.text : (i === cur ? Theme.accent : Theme.textTertiary);
                    return '<span style="color:' + c + '">' + esc(w) + "</span>";
                }).join(" ");
                out.push({ rich: true, text: html });
            } else if (b > a) {
                out.push({ rich: false, text: body.slice(a, b).trim() });
            }
            at = Math.max(at, b);
        });
        if (at < body.length && body.slice(at).trim().length > 0) out.push({ rich: false, text: body.slice(at).trim() });
        return out;
    }

    readonly property bool isUser: role === "user"
    readonly property bool isLast: ListView.view ? index === ListView.view.count - 1 : false
    readonly property var stepList: {
        try { return JSON.parse(stepsJson); } catch (e) { return []; }
    }
    readonly property int runningCount: stepList.filter(s => s.state === "run").length
    property bool expanded: false
    property bool copied: false

    width: ListView.view ? ListView.view.width : 640
    implicitHeight: col.implicitHeight
    height: implicitHeight

    HoverHandler { id: hov }

    ColumnLayout {
        id: col
        x: 24
        width: d.width - 48
        spacing: 10

        // ---------------------------------------------------------------- you
        Rectangle {
            visible: d.isUser
            Layout.alignment: Qt.AlignRight
            radius: 18
            color: Theme.userBubble
            implicitWidth: Math.min(userText.implicitWidth, col.width * 0.78 - 32) + 32
            implicitHeight: userText.implicitHeight + 20
            Text {
                id: userText
                x: 16
                y: 10
                width: Math.min(implicitWidth, col.width * 0.78 - 32)
                text: d.body
                wrapMode: Text.Wrap
                color: Theme.text
                font.family: Theme.sans
                font.pixelSize: 15
                lineHeight: 1.3
            }
        }

        // ---------------------------------------------------------------- what Friday did
        ColumnLayout {
            visible: !d.isUser && d.stepList.length > 0
            Layout.fillWidth: true
            spacing: 2

            // collapsed summary once finished
            Item {
                visible: d.done && !d.expanded
                Layout.fillWidth: true
                implicitHeight: 24
                Row {
                    spacing: 6
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: d.stepList.some(s => s.state === "error") ? "error" : "check"
                        font.family: Theme.icons
                        font.pixelSize: 16
                        color: d.stepList.some(s => s.state === "error") ? Theme.danger : Theme.textTertiary
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: d.stepList.length === 1 ? d.stepList[0].label : d.stepList.length + " steps"
                        font.family: Theme.sans
                        font.pixelSize: 13
                        color: sumMa.containsMouse ? Theme.textSecondary : Theme.textTertiary
                        Behavior on color { ColorAnimation { duration: Theme.fast } }
                    }
                    Text {
                        visible: d.stepList.length > 1
                        anchors.verticalCenter: parent.verticalCenter
                        text: "chevron_right"
                        font.family: Theme.icons
                        font.pixelSize: 16
                        color: Theme.textTertiary
                    }
                }
                MouseArea {
                    id: sumMa
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: d.stepList.length > 1
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: d.expanded = true
                }
            }

            // live (or expanded) list
            Repeater {
                model: (d.done && !d.expanded) ? [] : (d.done ? d.stepList : d.stepList.slice(-3))
                delegate: Item {
                    id: step
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 24
                    Row {
                        spacing: 8
                        anchors.verticalCenter: parent.verticalCenter
                        Item {
                            width: 16
                            height: 16
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                id: stepIcon
                                anchors.centerIn: parent
                                text: step.modelData.state === "run" ? "progress_activity"
                                    : step.modelData.state === "error" ? "error" : "check"
                                font.family: Theme.icons
                                font.pixelSize: 16
                                color: step.modelData.state === "run" ? Theme.accent
                                    : step.modelData.state === "error" ? Theme.danger : Theme.textTertiary
                                RotationAnimator on rotation {
                                    running: step.modelData.state === "run"
                                    from: 0
                                    to: 360
                                    duration: 900
                                    loops: Animation.Infinite
                                }
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: step.modelData.label
                            font.family: Theme.sans
                            font.pixelSize: 13
                            color: step.modelData.state === "run" ? Theme.textSecondary : Theme.textTertiary
                        }
                    }
                }
            }
        }

        // ---------------------------------------------------------------- thinking
        Text {
            id: thinking
            visible: !d.isUser && !d.done && d.body.length === 0 && d.runningCount === 0
            text: "Thinking"
            font.family: Theme.sans
            font.pixelSize: 15
            color: Theme.textSecondary
            SequentialAnimation on opacity {
                running: thinking.visible
                loops: Animation.Infinite
                NumberAnimation { to: 0.35; duration: 800; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
            }
        }

        // ---------------------------------------------------------------- the answer
        Repeater {
            model: d.isUser ? [] : d.segments
            delegate: Text {
                id: seg
                required property var modelData
                Layout.fillWidth: true
                // headings read as shouting in a small panel: render them as bold lines
                text: seg.modelData.rich ? seg.modelData.text : seg.modelData.text.replace(/^#{1,6}\s+(.+)$/gm, "**$1**")
                textFormat: seg.modelData.rich ? Text.RichText : Text.MarkdownText
                wrapMode: Text.Wrap
                color: Theme.text
                linkColor: Theme.accent
                font.family: Theme.sans
                font.pixelSize: seg.modelData.rich ? 16 : 15
                lineHeight: seg.modelData.rich ? 1.4 : 1.45
                onLinkActivated: link => Qt.openUrlExternally(link)
                HoverHandler { cursorShape: parent.hoveredLink.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor }
            }
        }

        // ---------------------------------------------------------------- quiet actions
        Row {
            visible: !d.isUser && d.done && d.body.length > 0
            spacing: 2
            opacity: (hov.hovered || d.isLast) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.fast } }
            Rectangle {
                width: copyRow.implicitWidth + 16
                height: 26
                radius: 8
                color: copyMa.containsMouse ? Theme.hover : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.fast } }
                Row {
                    id: copyRow
                    anchors.centerIn: parent
                    spacing: 5
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: d.copied ? "check" : "content_copy"
                        font.family: Theme.icons
                        font.pixelSize: 15
                        color: Theme.textTertiary
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: d.copied ? "Copied" : "Copy"
                        font.family: Theme.sans
                        font.pixelSize: 12
                        color: Theme.textTertiary
                    }
                }
                MouseArea {
                    id: copyMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Brain.copy(Brain.untag(d.body));
                        d.copied = true;
                        copiedTimer.restart();
                    }
                }
                Timer { id: copiedTimer; interval: 1400; onTriggered: d.copied = false }
            }
        }
    }
}
