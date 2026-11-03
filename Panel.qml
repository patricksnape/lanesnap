import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons

// Snap-zone overlay and layout editor. Draws the current preset from
// ~/.config/lanesnap/layouts.json over the focused monitor at the real window
// positions. Click a zone or press its number to snap the active window (lanesnap);
// Tab cycles presets. E edits the current preset and N makes a new one: drag the
// dividers to resize, add or remove columns, name it, Enter to save.
//
// A preset is a row of column widths (lanesnap lays windows out in scrolling-layout
// columns). Zones are stored as [col, row, colspan, cols] with cols = 1000 for
// presets made here; width = colspan / cols.
//
// Drag mode (summoned by lanesnap-drag with {"drag": "start" | "drop" | "cancel"}): the
// overlay is click-through and never takes the keyboard. It polls the cursor, highlights the
// zone under it, and snaps the window picked at the start when the button is released.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property var config: ({ layouts: {}, order: [], "default": "" })
  property int layoutIndex: 0
  property int hovered: -1
  property string targetWindow: ""

  // Drag mode: polled cursor position (global coordinates).
  property bool dragMode: false

  // Editing: draft = { id, label, widths: [fractions summing to 1], isNew }; null when picking.
  property var draft: null
  property bool dragging: false
  readonly property bool editing: draft !== null

  // Match the compositor's gaps so the preview sits where windows will land.
  readonly property int gapOut: 10
  readonly property int gapIn: 10

  readonly property string layoutId: config.order.length > 0 ? config.order[layoutIndex] : ""
  readonly property var layout: config.layouts[layoutId] || { label: "", zones: [] }
  readonly property var previewZones: editing ? zonesFor(draft.widths) : layout.zones
  readonly property var monitor: Hyprland.focusedMonitor
  readonly property var reserved: (monitor && monitor.lastIpcObject && monitor.lastIpcObject.reserved) || [0, 0, 0, 0]

  readonly property color accent: Color.accent
  readonly property color fg: Color.foreground
  readonly property color bg: Color.background

  function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  // Zones for a row of column widths, rounded to per-mille so they sum to 1000.
  function zonesFor(widths) {
    var out = [], x = 0
    for (var i = 0; i < widths.length; i++) {
      var w = i === widths.length - 1 ? 1000 - x : Math.round(widths[i] * 1000)
      out.push([x, 0, w, 1000])
      x += w
    }
    return out
  }

  function widthsOf(zones) { return zones.map(function(z) { return z[2] / z[3] }) }

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    try { root.config = JSON.parse(zonesFile.text()) } catch (e) { console.warn("layouts.json:", e) }
    var drag = String(payload.drag || "")
    if (drag === "drop") { root.finishDrag(); return }
    if (drag === "cancel") { root.dismiss(); return }
    root.dragMode = drag === "start"
    root.targetWindow = String(payload.window || "")
    var wanted = String(payload.layout || root.config["default"] || "")
    root.layoutIndex = Math.max(0, root.config.order.indexOf(wanted))
    root.hovered = -1
    root.draft = null
    root.opened = true
    Qt.callLater(function() { if (root.opened) keyCatcher.forceActiveFocus() })
  }

  function close() { root.opened = false; root.draft = null; root.dragMode = false }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "psnape.lanesnap")
    else close()
  }

  // Button released: snap into the zone under the cursor, or cancel if there is none.
  function finishDrag() {
    if (!root.dragMode) return
    if (root.hovered >= 0) root.snap(root.hovered + 1)
    else root.dismiss()
  }

  // Map a polled cursor position ("x, y") to the zone under it.
  function onCursor(text) {
    var m = String(text).trim().split(/[ ,]+/)
    if (m.length < 2 || !root.monitor || !root.monitor.lastIpcObject) return
    var cx = parseFloat(m[0]) - root.monitor.lastIpcObject.x - area.x
    var cy = parseFloat(m[1]) - root.monitor.lastIpcObject.y - area.y
    var hit = -1
    if (cy >= 0 && cy <= area.height) {
      var zs = root.layout.zones
      for (var i = 0; i < zs.length; i++) {
        var l = zs[i][0] / zs[i][3] * area.width, r = (zs[i][0] + zs[i][2]) / zs[i][3] * area.width
        if (cx >= l && cx <= r) { hit = i; break }
      }
    }
    root.hovered = hit
  }

  Process {
    id: cursorProc
    command: ["hyprctl", "cursorpos"]
    stdout: StdioCollector { onStreamFinished: root.onCursor(text) }
  }

  Timer {
    interval: 33
    repeat: true
    running: root.opened && root.dragMode
    onTriggered: if (!cursorProc.running) cursorProc.running = true
  }

  // A release that never arrives (modifier let go first) must not strand the overlay.
  Timer {
    interval: 20000
    running: root.opened && root.dragMode
    onTriggered: root.dismiss()
  }

  // Selecting a preset also makes it the one CTRL+ALT+1..9 snap into.
  function select(index) {
    root.layoutIndex = index
    var id = root.config.order[index]
    if (id && root.config["default"] !== id) {
      var cfg = JSON.parse(JSON.stringify(root.config))
      cfg["default"] = id
      root.writeConfig(cfg)
    }
  }

  function cycle(step) {
    var n = root.config.order.length
    if (n > 0) root.select((root.layoutIndex + step + n) % n)
  }

  // Atomic write so lanesnap never reads a half-written file.
  function writeConfig(cfg) {
    root.config = cfg
    Quickshell.execDetached(["sh", "-c",
      "d=\"${XDG_CONFIG_HOME:-$HOME/.config}/lanesnap\"; mkdir -p \"$d\" && printf %s \"$1\" > \"$d/layouts.json.tmp\" && mv \"$d/layouts.json.tmp\" \"$d/layouts.json\"",
      "sh", JSON.stringify(cfg, null, 2)])
  }

  // Launch the snap before dismissing: hiding can unload this plugin, which
  // would drop the launch. The sleep lets focus settle back first.
  function snap(zone) {
    Quickshell.execDetached(["sh", "-c", "sleep 0.15; LANESNAP_WINDOW=\"$3\" exec lanesnap \"$1\" \"$2\"", "lanesnap", root.layoutId, String(zone), root.targetWindow])
    // The preset you snap with becomes the one the overlay opens on.
    if (root.config["default"] !== root.layoutId) {
      var cfg = JSON.parse(JSON.stringify(root.config))
      cfg["default"] = root.layoutId
      root.writeConfig(cfg)
    }
    root.dismiss()
  }

  function startEdit(isNew) {
    var zs = root.layout.zones
    root.draft = {
      id: isNew ? "" : root.layoutId,
      label: isNew ? "New layout" : root.layout.label,
      widths: zs.length >= 2 ? root.widthsOf(zs) : [0.5, 0.5],
      isNew: isNew
    }
    nameField.text = root.draft.label
    Qt.callLater(function() { nameField.forceActiveFocus(); nameField.selectAll() })
  }

  function setWidths(w) { root.draft = Object.assign({}, root.draft, { widths: w }) }

  // Move the divider between columns k and k+1 to fraction p of the width.
  function setBoundary(k, p) {
    var w = root.draft.widths.slice(), min = 0.05, left = 0
    for (var i = 0; i < k; i++) left += w[i]
    var right = left + w[k] + w[k + 1]
    p = Math.max(left + min, Math.min(right - min, p))
    w[k] = p - left
    w[k + 1] = right - p
    root.setWidths(w)
  }

  // Split the widest column in two.
  function addColumn() {
    var w = root.draft.widths.slice()
    if (w.length >= 9) return
    var i = w.indexOf(Math.max.apply(null, w))
    w.splice(i, 1, w[i] / 2, w[i] / 2)
    root.setWidths(w)
  }

  // Fold the narrowest column into its neighbour.
  function removeColumn() {
    var w = root.draft.widths.slice()
    if (w.length <= 2) return
    var i = w.indexOf(Math.min.apply(null, w)), j = i > 0 ? i - 1 : i + 1
    w[j] += w[i]
    w.splice(i, 1)
    root.setWidths(w)
  }

  function cancelEdit() {
    root.draft = null
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function slug(label, taken) {
    var base = label.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "layout"
    var id = base, n = 2
    while (taken.indexOf(id) >= 0) id = base + "-" + (n++)
    return id
  }

  function saveEdit() {
    var cfg = JSON.parse(JSON.stringify(root.config))
    var label = nameField.text.trim() || "Layout"
    var id = root.draft.id
    if (root.draft.isNew) {
      id = root.slug(label, cfg.order)
      cfg.order.push(id)
    }
    cfg.layouts[id] = { label: label, zones: root.zonesFor(root.draft.widths) }
    cfg["default"] = id
    root.writeConfig(cfg)
    root.layoutIndex = cfg.order.indexOf(id)
    root.cancelEdit()
  }

  function deleteLayout() {
    if (root.config.order.length < 2 || root.draft.isNew) return
    var cfg = JSON.parse(JSON.stringify(root.config))
    var id = root.draft.id
    delete cfg.layouts[id]
    cfg.order = cfg.order.filter(function(x) { return x !== id })
    cfg["default"] = cfg.order[0]
    root.writeConfig(cfg)
    root.layoutIndex = 0
    root.cancelEdit()
  }

  FileView {
    id: zonesFile
    path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/lanesnap/layouts.json"
    blockLoading: true
    watchChanges: true
    onFileChanged: reload()
  }

  component Chip: Rectangle {
    id: chip
    property string text: ""
    property bool active: false
    property bool danger: false
    signal clicked()
    implicitWidth: label.implicitWidth + Style.space(24)
    implicitHeight: label.implicitHeight + Style.space(12)
    radius: height / 2
    color: active ? root.withAlpha(root.accent, 0.30)
         : mouse.containsMouse ? root.withAlpha(root.fg, 0.12) : root.withAlpha(root.fg, 0.05)
    border.width: active ? 2 : 1
    border.color: active ? root.accent : root.withAlpha(root.fg, 0.25)
    Text {
      id: label
      anchors.centerIn: parent
      text: chip.text
      color: chip.danger ? Color.urgent : root.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.bold: chip.active
    }
    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.clicked()
    }
  }

  PanelWindow {
    visible: root.opened
    screen: Quickshell.screens.find(function(s) { return root.monitor && s.name === root.monitor.name }) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "lanesnap"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.dragMode ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
    // An empty input region makes the overlay click-through while dragging.
    mask: root.dragMode ? noInput : null
    Region { id: noInput }

    Rectangle {
      anchors.fill: parent
      color: root.withAlpha(root.bg, 0.55)
      MouseArea { anchors.fill: parent; onClicked: root.editing ? undefined : root.dismiss() }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.onEscapePressed: root.dismiss()
      Keys.onTabPressed: root.cycle(1)
      Keys.onBacktabPressed: root.cycle(-1)
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_E) { root.startEdit(false); event.accepted = true; return }
        if (event.key === Qt.Key_N) { root.startEdit(true); event.accepted = true; return }
        var n = event.key - Qt.Key_0
        if (n >= 1 && n <= root.layout.zones.length) {
          root.snap(n)
          event.accepted = true
        }
      }

      // The usable area, as the compositor sees it.
      Item {
        id: area
        x: root.reserved[0] + root.gapOut
        y: root.reserved[1] + root.gapOut
        width: parent.width - root.reserved[0] - root.reserved[2] - 2 * root.gapOut
        height: parent.height - root.reserved[1] - root.reserved[3] - 2 * root.gapOut

        Repeater {
          model: root.previewZones.length

          Rectangle {
            id: zone
            required property int index
            readonly property var zr: root.previewZones[index] || [0, 0, 1, 1]
            readonly property bool hot: !root.editing && root.hovered === index
            readonly property bool innerLeft: zr[0] > 0
            readonly property bool innerRight: zr[0] + zr[2] < zr[3]

            x: zr[0] / zr[3] * area.width + (innerLeft ? root.gapIn / 2 : 0)
            y: 0
            width: zr[2] / zr[3] * area.width - (innerLeft ? root.gapIn / 2 : 0) - (innerRight ? root.gapIn / 2 : 0)
            height: area.height
            radius: Style.cornerRadius
            color: root.withAlpha(root.accent, hot ? 0.28 : 0.10)
            border.width: hot ? 3 : 2
            border.color: root.withAlpha(root.accent, hot || root.editing ? 1.0 : 0.6)

            Behavior on color { ColorAnimation { duration: 90 } }
            Behavior on x { enabled: !root.dragging; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on width { enabled: !root.dragging; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

            Column {
              anchors.centerIn: parent
              spacing: Style.space(4)
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: String(zone.index + 1)
                color: root.fg
                opacity: zone.hot ? 1.0 : 0.7
                font.family: Style.font.family
                font.pixelSize: Math.min(zone.height, zone.width) * 0.3
                font.bold: true
              }
              Text {
                visible: root.editing
                anchors.horizontalCenter: parent.horizontalCenter
                text: Math.round(zone.zr[2] / zone.zr[3] * 100) + "%"
                color: root.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall * 1.6
              }
            }

            MouseArea {
              anchors.fill: parent
              enabled: !root.editing
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.hovered = zone.index
              onExited: if (root.hovered === zone.index) root.hovered = -1
              onClicked: root.snap(zone.index + 1)
            }
          }
        }

        // Dividers between neighbouring columns; dragging one trades width between the two.
        Repeater {
          model: root.editing ? root.draft.widths.length - 1 : 0

          Rectangle {
            id: handle
            required property int index
            // Boundary index into the preview zones: the right edge of zone `index`.
            readonly property var zr: root.previewZones[index] || [0, 0, 1, 1]
            width: Style.space(14)
            height: Style.space(96)
            radius: width / 2
            x: (zr[0] + zr[2]) / zr[3] * area.width - width / 2
            y: (area.height - height) / 2
            color: root.accent
            border.width: 2
            border.color: root.bg

            MouseArea {
              anchors.fill: parent
              anchors.margins: -Style.space(12)
              cursorShape: Qt.SizeHorCursor
              onPressed: root.dragging = true
              onReleased: root.dragging = false
              onPositionChanged: function(mouse) {
                if (!pressed) return
                root.setBoundary(handle.index, mapToItem(area, mouse.x, mouse.y).x / area.width)
              }
            }
          }
        }
      }

      // While dragging: just say what releasing does.
      Rectangle {
        visible: root.dragMode
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(40)
        width: dragHint.implicitWidth + Style.space(40)
        height: dragHint.implicitHeight + Style.space(20)
        radius: height / 2
        color: root.withAlpha(root.bg, 0.92)
        border.width: 1
        border.color: root.withAlpha(root.fg, 0.3)
        Text {
          id: dragHint
          anchors.centerIn: parent
          text: root.hovered >= 0 ? "Release to snap to zone " + (root.hovered + 1) + "  ·  " + root.layout.label
                                  : "Move over a zone  ·  release elsewhere to cancel"
          color: root.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }

      // Presets, actions and hints, centred along the bottom.
      Rectangle {
        visible: !root.dragMode
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(40)
        width: bar.implicitWidth + Style.space(40)
        height: bar.implicitHeight + Style.space(28)
        radius: Style.space(20)
        color: root.withAlpha(root.bg, 0.92)
        border.width: 1
        border.color: root.withAlpha(root.fg, 0.3)
        // Swallow clicks so the panel never counts as the scrim.
        MouseArea { anchors.fill: parent }

        ColumnLayout {
          id: bar
          anchors.centerIn: parent
          spacing: Style.space(10)

          // Picking: preset chips plus edit/new.
          RowLayout {
            visible: !root.editing
            Layout.alignment: Qt.AlignHCenter
            spacing: Style.space(8)
            Repeater {
              model: root.config.order
              Chip {
                required property string modelData
                required property int index
                text: (root.config.layouts[modelData] || { label: modelData }).label
                active: index === root.layoutIndex
                onClicked: root.select(index)
              }
            }
            Rectangle { width: 1; height: Style.space(20); color: root.withAlpha(root.fg, 0.3) }
            Chip { text: "Edit"; onClicked: root.startEdit(false) }
            Chip { text: "+ New"; onClicked: root.startEdit(true) }
          }

          // Editing: name, zone count, then delete / cancel / save.
          RowLayout {
            visible: root.editing
            Layout.alignment: Qt.AlignHCenter
            spacing: Style.space(8)

            Rectangle {
              implicitWidth: Style.space(180)
              implicitHeight: nameField.implicitHeight + Style.space(12)
              radius: height / 2
              color: root.withAlpha(root.fg, 0.08)
              border.width: nameField.activeFocus ? 2 : 1
              border.color: nameField.activeFocus ? root.accent : root.withAlpha(root.fg, 0.25)
              TextInput {
                id: nameField
                anchors.fill: parent
                anchors.leftMargin: Style.space(14)
                anchors.rightMargin: Style.space(14)
                verticalAlignment: TextInput.AlignVCenter
                color: root.fg
                selectionColor: root.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                clip: true
                onAccepted: root.saveEdit()
                Keys.onEscapePressed: root.cancelEdit()
              }
            }
            Chip { text: "−"; onClicked: root.removeColumn() }
            Text {
              text: root.editing ? root.draft.widths.length + " columns" : ""
              color: root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            Chip { text: "+"; onClicked: root.addColumn() }
            Chip {
              visible: root.editing && !root.draft.isNew && root.config.order.length > 1
              text: "Delete"
              danger: true
              onClicked: root.deleteLayout()
            }
            Chip { text: "Cancel"; onClicked: root.cancelEdit() }
            Chip { text: "Save"; active: true; onClicked: root.saveEdit() }
          }

          Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.editing
              ? "Drag the dividers  ·  Enter save  ·  Esc cancel"
              : "1–" + root.layout.zones.length + " snap  ·  Tab preset  ·  E edit  ·  N new  ·  Esc"
            color: root.withAlpha(root.fg, 0.6)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }
}
