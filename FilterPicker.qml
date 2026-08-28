import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Window
import qs.Commons

Item {
  id: root

  property string label: ""
  property var values: []
  property var options: []
  property bool multiple: true
  property string emptyLabel: "Any"
  property color foreground: Color.popups.text
  property color background: Color.popups.background
  property color popupBorder: Color.popups.border
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property bool hasCursor: false
  property int rowHeight: Style.spacing.controlHeight
  property int popupRowHeight: Style.spacing.popupRowHeight
  property int currentIndex: 0

  readonly property var popupBorderSpec: Border.localOrSurfaceSpec("popups", "border", popupBorder, Color.popups.border, Style.normalBorderWidth)
  readonly property bool popupOpen: popup.opened

  signal changed(var values)
  signal hovered(bool isHovered)

  function arrayFrom(v) {
    if (!v || typeof v.length !== "number" || typeof v === "string") return []
    var out = []
    for (var i = 0; i < v.length; i++) out.push(v[i])
    return out
  }

  function optionValue(o) {
    return (o && typeof o === "object") ? String(o.value) : String(o)
  }

  function optionLabel(o) {
    return (o && typeof o === "object") ? String(o.label) : String(o)
  }

  function isSelected(value) {
    var want = String(value)
    var arr = arrayFrom(values)
    for (var i = 0; i < arr.length; i++)
      if (String(arr[i]) === want) return true
    return false
  }

  function selectionLabel() {
    var arr = arrayFrom(values)
    if (arr.length === 0) return ""
    var labels = []
    for (var i = 0; i < arr.length; i++) {
      var found = ""
      for (var j = 0; j < options.length; j++) {
        if (optionValue(options[j]) === String(arr[i])) {
          found = optionLabel(options[j])
          break
        }
      }
      labels.push(found || String(arr[i]))
    }
    if (labels.length <= 3) return labels.join(", ")
    return arr.length + " selected"
  }

  function open() {
    if (options.length === 0) return
    var arr = arrayFrom(values)
    currentIndex = 0
    if (arr.length > 0) {
      for (var i = 0; i < options.length; i++) {
        if (optionValue(options[i]) === String(arr[0])) {
          currentIndex = i
          break
        }
      }
    }
    popup.open()
  }

  function close() { popup.close() }
  function toggle() { popup.opened ? popup.close() : open() }

  function move(dy) {
    if (!popup.opened || options.length === 0) return
    currentIndex = Math.max(0, Math.min(options.length - 1, currentIndex + dy))
  }

  function toggleCurrent() {
    if (!popup.opened || currentIndex < 0 || currentIndex >= options.length) return
    toggleValue(optionValue(options[currentIndex]))
  }

  function toggleValue(value) {
    var v = String(value)
    var arr = arrayFrom(values)
    if (!multiple) {
      root.changed([v])
      return
    }
    var idx = -1
    for (var i = 0; i < arr.length; i++) {
      if (String(arr[i]) === v) { idx = i; break }
    }
    if (idx === -1) arr.push(v)
    else arr.splice(idx, 1)
    root.changed(arr)
  }

  implicitWidth: Style.spacing.dropdownWidth
  implicitHeight: label !== "" ? rowHeight + Style.spacing.huge : rowHeight

  Column {
    anchors.fill: parent
    spacing: Style.spacing.labelGap

    Text {
      visible: root.label !== ""
      text: root.label
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    Rectangle {
      id: trigger
      width: parent.width
      height: root.rowHeight
      radius: Style.cornerRadius

      readonly property bool _focused: trigger.activeFocus
      readonly property bool _hot: triggerHover.hovered || root.hasCursor

      color: Style.controlFill(trigger._focused, trigger._hot, root.foreground, root.accent)
      border.width: Style.normalBorderWidth
      border.color: trigger._focused || trigger._hot ? root.accent : root.popupBorder
      activeFocusOnTab: true

      HoverHandler {
        id: triggerHover
        onHoveredChanged: root.hovered(hovered)
      }

      Text {
        anchors.left: parent.left
        anchors.right: chevron.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.spacing.controlPaddingX
        anchors.rightMargin: Style.spacing.md
        text: root.selectionLabel() || root.emptyLabel
        color: root.selectionLabel() ? root.foreground : Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        id: chevron
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: Style.spacing.controlGap
        text: "󰅀"
        color: Qt.darker(root.foreground, 1.2)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          trigger.forceActiveFocus()
          root.toggle()
        }
      }

      QQC.Popup {
        id: popup
        parent: trigger.Window.window ? trigger.Window.window.contentItem : trigger
        property real _anchorX: 0
        property real _anchorY: 0
        function reposition() {
          if (!parent) return
          var p = trigger.mapToItem(parent, 0, trigger.height + Style.spacing.xxs)
          _anchorX = p.x
          _anchorY = p.y
        }
        x: _anchorX
        y: _anchorY
        width: trigger.width
        implicitHeight: Math.min(
          Math.max(1, root.options.length) * root.popupRowHeight + Math.max(0, root.options.length - 1) * Style.spacing.labelGap + Style.spacing.xxs,
          root.popupRowHeight * 8 + 7 * Style.spacing.labelGap + Style.spacing.xxs
        )
        padding: Style.spacing.hairline
        leftPadding: Border.left(root.popupBorderSpec) + Style.spacing.hairline
        rightPadding: Border.right(root.popupBorderSpec) + Style.spacing.hairline
        topPadding: Border.top(root.popupBorderSpec) + Style.spacing.hairline
        bottomPadding: Border.bottom(root.popupBorderSpec) + Style.spacing.hairline
        focus: false
        closePolicy: QQC.Popup.CloseOnPressOutside
        onOpened: reposition()

        background: Rectangle {
          color: root.background
          border.width: Style.normalBorderWidth
          border.color: root.popupBorder
          radius: Style.cornerRadius
        }

        contentItem: ListView {
          id: optionList
          spacing: Style.spacing.labelGap
          implicitHeight: contentHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: root.options
          currentIndex: root.currentIndex

          onCurrentIndexChanged: root.currentIndex = currentIndex

          delegate: Rectangle {
            required property var modelData
            required property int index
            readonly property bool selected: root.isSelected(root.optionValue(modelData))
            width: optionList.width
            height: root.popupRowHeight
            color: index === root.currentIndex
              ? Style.hoverFillFor(root.foreground, root.accent)
              : "transparent"

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.spacing.controlPaddingX
              anchors.rightMargin: Style.spacing.controlPaddingX
              spacing: Style.spacing.rowGap

              Rectangle {
                id: mark
                width: Style.space(16)
                height: Style.space(16)
                radius: Math.max(2, Style.cornerRadius / 2)
                anchors.verticalCenter: parent.verticalCenter
                color: selected ? Style.selectedFillFor(root.foreground, root.accent) : "transparent"
                border.width: Style.normalBorderWidth
                border.color: selected ? root.accent : root.popupBorder

                Text {
                  anchors.centerIn: parent
                  visible: selected
                  text: "✓"
                  color: Style.selectedStateColor(root.foreground, root.accent)
                  font.family: root.fontFamily
                  font.pixelSize: Math.round(mark.height * 0.85)
                  font.bold: true
                }
              }

              Text {
                width: parent.width - mark.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                text: root.optionLabel(modelData)
                color: index === root.currentIndex ? Style.hoverStateColor(root.foreground, root.accent) : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onPositionChanged: root.currentIndex = parent.index
              onClicked: root.toggleValue(root.optionValue(modelData))
            }
          }
        }
      }
    }
  }
}
