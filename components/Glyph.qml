import QtQuick

// Qt's fallback for these Nerd Font private-use glyphs advances by a full
// em, while Pango advances them by half an em. Draw the glyph at full size but
// reserve only the half-em cell Waybar uses.
Item {
  id: root

  property string icon: ""
  property color color: Theme.foreground
  property int cellWidth: Math.round(Theme.fontSize / 2)

  implicitWidth: cellWidth
  implicitHeight: glyph.implicitHeight

  Text {
    id: glyph
    anchors.centerIn: parent
    text: root.icon
    color: root.color
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize
    textFormat: Text.PlainText
  }
}
