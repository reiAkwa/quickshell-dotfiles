import "../components"

Module {
  id: root

  property string title: ""

  text: title
  maxTextWidth: Theme.windowTextMaxWidth
  letterSpacing: 0.3
  moduleColor: Theme.window
}
