import QtQuick
import QtQuick.Shapes
import qs.services

// Friday's presence mark. Still when idle; a single calm arc orbits while it thinks;
// amber while it waits on you. Restraint over spectacle.
Item {
    id: mark
    property bool busy: false
    property bool waiting: false
    implicitWidth: 30
    implicitHeight: 30

    readonly property color tone: waiting ? Theme.warn : Theme.accent

    Rectangle {                         // soft disc
        anchors.fill: parent
        radius: width / 2
        color: Qt.alpha(mark.tone, mark.busy || mark.waiting ? 0.20 : 0.14)
        Behavior on color { ColorAnimation { duration: Theme.base } }
    }

    Rectangle {                         // core
        id: core
        anchors.centerIn: parent
        width: 10
        height: 10
        radius: 5
        color: mark.tone
        Behavior on color { ColorAnimation { duration: Theme.base } }
        SequentialAnimation on scale {
            running: mark.busy || mark.waiting
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { to: 0.78; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
        }
    }

    Shape {                             // orbiting arc
        id: arc
        anchors.fill: parent
        opacity: mark.busy ? 1 : 0
        visible: opacity > 0
        layer.enabled: true
        layer.samples: 4
        Behavior on opacity { NumberAnimation { duration: Theme.base } }
        ShapePath {
            strokeColor: mark.tone
            strokeWidth: 2
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: arc.width / 2
                centerY: arc.height / 2
                radiusX: arc.width / 2 - 1.5
                radiusY: arc.height / 2 - 1.5
                startAngle: -90
                sweepAngle: 80
            }
        }
        RotationAnimator on rotation {
            running: arc.visible
            from: 0
            to: 360
            duration: 1100
            loops: Animation.Infinite
        }
    }
}
