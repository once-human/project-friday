import QtQuick
import QtQuick.Effects
import qs.services

// The card's soft shadow. RectangularShadow needs Qt 6.9+, so FridayPanel loads this file through a Loader:
// on older Qt it simply doesn't appear, and the panel still works.
RectangularShadow {
    blur: 60
    spread: -6
    offset: Qt.vector2d(0, 20)
    color: Theme.shadow
}
