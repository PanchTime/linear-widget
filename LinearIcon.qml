import QtQuick
import qs.Commons

Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property color accent: Color.accent
  property bool dimmed: false

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  // Linear-like folded hex: theme foreground outline, accent inner facet.
  Canvas {
    id: canvas
    anchors.fill: parent
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var s = width
      var pad = s * 0.08
      var x = [s * 0.50, s * 0.88, s * 0.88, s * 0.50, s * 0.12, s * 0.12]
      var y = [pad, s * 0.28, s * 0.72, s - pad, s * 0.72, s * 0.28]
      ctx.globalAlpha = root.dimmed ? 0.45 : 1.0

      ctx.beginPath()
      ctx.moveTo(x[0], y[0])
      for (var i = 1; i < 6; i++) ctx.lineTo(x[i], y[i])
      ctx.closePath()
      ctx.fillStyle = Qt.rgba(root.color.r, root.color.g, root.color.b, 0.16)
      ctx.fill()
      ctx.lineWidth = Math.max(1.2, s * 0.08)
      ctx.strokeStyle = root.color
      ctx.lineJoin = "round"
      ctx.stroke()

      ctx.beginPath()
      ctx.moveTo(x[0], y[0])
      ctx.lineTo(x[1], y[1])
      ctx.lineTo(s * 0.50, s * 0.50)
      ctx.closePath()
      ctx.fillStyle = root.accent
      ctx.globalAlpha = root.dimmed ? 0.35 : 0.95
      ctx.fill()
    }
  }

  Connections {
    target: root
    function onColorChanged() { canvas.requestPaint() }
    function onAccentChanged() { canvas.requestPaint() }
    function onDimmedChanged() { canvas.requestPaint() }
    function onIconSizeChanged() { canvas.requestPaint() }
  }

  Component.onCompleted: canvas.requestPaint()
}
