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
    // word by word: what's been said is solid, the word you're hearing glows, the rest waits its turn
    readonly property string karaoke: {
        if (!d.spoken || !d.spoken.words || d.spoken.words.length === 0) return "";
        const cur = d.live ? Brain.spokenIdx : 99999;
        const esc = t => String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        return d.spoken.words.map((w, i) => {
            const c = i < cur ? Theme.text : (i === cur ? Theme.accent : Theme.textTertiary);
            return '<span style="color:' + c + '">' + esc(w) + "</span>";
        }).join(" ");
    }
    // everything that wasn't spoken (details, code, lists) stays as normal formatted text below
    readonly property string rest: {
        let b = d.body;
        // only cut the spoken paragraphs out once they're actually being shown as speech
        const r = (d.karaoke.length > 0 && d.spoken.ranges) ? d.spoken.ranges : [];
        for (let k = r.length - 1; k >= 0; k--) b = b.slice(0, r[k][0]) + b.slice(r[k][1]);
        return b.trim();
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

        // ---------------------------------------------------------------- what Friday said out loud
        Text {
            visible: !d.isUser && d.karaoke.length > 0
            Layout.fillWidth: true
            text: d.karaoke
            textFormat: Text.RichText
            wrapMode: Text.Wrap
            font.family: Theme.sans
            font.pixelSize: 16
            lineHeight: 1.4
        }

        // ---------------------------------------------------------------- the answer
        Text {
            visible: !d.isUser && (d.karaoke.length > 0 ? d.rest.length > 0 : d.body.length > 0)
            Layout.fillWidth: true
            // headings read as shouting in a small panel: render them as bold lines
            text: (d.karaoke.length > 0 ? d.rest : d.body).replace(/^#{1,6}\s+(.+)$/gm, "**$1**")
            textFormat: Text.MarkdownText
            wrapMode: Text.Wrap
            color: Theme.text
            linkColor: Theme.accent
            font.family: Theme.sans
            font.pixelSize: 15
            lineHeight: 1.45
            onLinkActivated: link => Qt.openUrlExternally(link)
            HoverHandler { cursorShape: parent.hoveredLink.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor }
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
                        Brain.copy(d.body);
                        d.copied = true;
                        copiedTimer.restart();
                    }
                }
                Timer { id: copiedTimer; interval: 1400; onTriggered: d.copied = false }
            }
        }
    }
}
