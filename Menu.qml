import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  // Injected by omarchy-shell when this plugin is loaded/summoned
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  // Plugin state
  property bool opened: false
  property bool loading: false
  property string errorMessage: ""
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool userNavigatedList: false
  property var rawSessions: []
  property string renamingSessionName: ""

  // Reactive Omarchy color tokens with safe fallbacks and Qt.rgba(...)
  readonly property color colorBackground: (typeof Color !== "undefined" && Color.background) ? Color.background : Qt.rgba(0.06, 0.07, 0.08, 0.98)
  readonly property color colorForeground: (typeof Color !== "undefined" && Color.foreground) ? Color.foreground : Qt.rgba(0.92, 0.93, 0.94, 1.0)
  readonly property color colorAccent: (typeof Color !== "undefined" && Color.accent) ? Color.accent : Qt.rgba(0.40, 0.68, 0.98, 1.0)
  readonly property color colorUrgent: (typeof Color !== "undefined" && Color.urgent) ? Color.urgent : Qt.rgba(0.92, 0.33, 0.33, 1.0)
  readonly property color colorMuted: (typeof Color !== "undefined" && Color.muted) ? Color.muted : Qt.rgba(0.55, 0.58, 0.62, 1.0)

  // Surface tokens derived from Color.menu with foundational fallbacks
  readonly property color menuBackground: (typeof Color !== "undefined" && Color.menu && Color.menu.background) ? Color.menu.background : colorBackground
  readonly property color menuForeground: (typeof Color !== "undefined" && Color.menu && Color.menu.text) ? Color.menu.text : colorForeground
  readonly property color menuBorder: (typeof Color !== "undefined" && Color.menu && Color.menu.border) ? Color.menu.border : Qt.rgba(0.28, 0.31, 0.36, 0.6)
  readonly property color menuScrim: (typeof Color !== "undefined" && Color.menu && Color.menu.scrim) ? Color.menu.scrim : Qt.rgba(0.0, 0.0, 0.0, 0.55)
  readonly property color menuSelectedBg: (typeof Color !== "undefined" && Color.menu && Color.menu.selectedBackground) ? Color.menu.selectedBackground : Qt.rgba(1.0, 1.0, 1.0, 0.08)
  readonly property color menuSelectedFg: (typeof Color !== "undefined" && Color.menu && Color.menu.selectedText) ? Color.menu.selectedText : colorAccent
  readonly property color menuSelectedBorder: (typeof Color !== "undefined" && Color.menu && Color.menu.selectedBorder) ? Color.menu.selectedBorder : Qt.rgba(0.0, 0.0, 0.0, 0.0)

  // Typography & geometry specifications (widescreen 19:9 ratio)
  property string fontFamily: (typeof Style !== "undefined" && Style.font && Style.font.menuFamily) ? Style.font.menuFamily : "sans-serif"
  readonly property int cornerRadius: (typeof Style !== "undefined" && Style.cornerRadius !== undefined) ? Style.cornerRadius : 10
  property int contentMargin: (typeof Style !== "undefined" && Style.spacing && Style.spacing.panelPadding !== undefined) ? Style.spacing.panelPadding : 16
  property int contentSpacing: (typeof Style !== "undefined" && Style.spacing && Style.spacing.md !== undefined) ? Style.spacing.md : 10
  property int headerHeight: Math.max(44, (typeof Style !== "undefined" && Style.space) ? Style.space(44) : 44)
  property int inputSlotHeight: Math.max(42, (typeof Style !== "undefined" && Style.space) ? Style.space(42) : 42)
  property int rowHeight: Math.max(56, (typeof Style !== "undefined" && Style.space) ? Style.space(56) : 56)
  property int rowSpacing: (typeof Style !== "undefined" && Style.spacing && Style.spacing.xs !== undefined) ? Style.spacing.xs : 6
  property int footerHeight: Math.max(28, (typeof Style !== "undefined" && Style.space) ? Style.space(28) : 28)
  property int cardWidth: Math.min(800, panel.width - 48)
  property int cardHeight: Math.min(380, Math.round(cardWidth * 9 / 19))

  property var borderSpec: (typeof Border !== "undefined" && Border.surfaceSpec) ? Border.surfaceSpec("menu", "border", menuBorder, 1) : null
  property var selectedBorderSpec: (typeof Border !== "undefined" && Border.surfaceSpec) ? Border.surfaceSpec("menu", "selected-border", menuSelectedBorder, 1) : null

  onOpenedChanged: {
    if (root.opened) {
      Qt.callLater(function() {
        if (typeof sessionTextInput !== "undefined") {
          sessionTextInput.forceActiveFocus()
        }
      })
    }
  }

  // Lifecycle hooks called by omarchy-shell
  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.userNavigatedList = false
    root.selectedIndex = 0
    root.cursorActive = false
    root.renamingSessionName = ""
    if (typeof sessionTextInput !== "undefined") sessionTextInput.text = ""
    root.disarmPointer()
    root.fetchSessions()
    Qt.callLater(function() {
      if (typeof sessionTextInput !== "undefined") {
        sessionTextInput.forceActiveFocus()
      }
    })
  }

  function close() {
    root.opened = false
    root.filterText = ""
    root.userNavigatedList = false
    root.cursorActive = false
    root.renamingSessionName = ""
    if (typeof sessionTextInput !== "undefined") sessionTextInput.text = ""
  }

  function dismiss() {
    root.opened = false
    root.filterText = ""
    root.userNavigatedList = false
    root.cursorActive = false
    root.renamingSessionName = ""
    if (typeof sessionTextInput !== "undefined") sessionTextInput.text = ""
    if (root.shell && typeof root.shell.hide === "function") {
      root.shell.hide((root.manifest && root.manifest.id) || "juniorcorzo.herdr")
    }
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // Session query process
  function fetchSessions() {
    if (listProc.running) return
    root.loading = true
    root.errorMessage = ""
    listProc.command = ["herdr", "session", "list", "--json"]
    listProc.running = true
  }

  function handleListResult(exitCode, stdoutText, stderrText) {
    root.loading = false
    if (exitCode !== 0) {
      root.rawSessions = []
      root.errorMessage = String(stderrText || "Could not query Herdr sessions").trim()
      root.rebuildDisplay()
      return
    }

    var result
    try {
      result = JSON.parse(String(stdoutText || "{}"))
    } catch (e) {
      root.rawSessions = []
      root.errorMessage = "Failed to parse Herdr JSON response"
      root.rebuildDisplay()
      return
    }

    root.rawSessions = Array.isArray(result.sessions) ? result.sessions : []
    root.errorMessage = ""
    root.rebuildDisplay()
  }

  function sessionExists(name) {
    if (!name) return false
    var clean = name.trim().toLowerCase()
    for (var i = 0; i < root.rawSessions.length; i++) {
      if (String(root.rawSessions[i].name || "").trim().toLowerCase() === clean) {
        return true
      }
    }
    return false
  }

  // Filter matching
  function matchesFilter(session, tokens) {
    if (!tokens || tokens.length === 0) return true
    var searchCorpus = [
      session.name || "",
      session.running ? "running active" : "stopped idle",
      session.default ? "default primary" : "",
      session.session_dir || "",
      session.socket_path || ""
    ].join(" ").toLowerCase()

    for (var i = 0; i < tokens.length; i++) {
      if (searchCorpus.indexOf(tokens[i]) === -1) return false
    }
    return true
  }

  // Model synchronization
  function rebuildDisplay() {
    var rawQuery = (typeof sessionTextInput !== "undefined" ? sessionTextInput.text : root.filterText) || ""
    var query = rawQuery.trim()
    var tokens = query ? query.toLowerCase().split(/\s+/) : []
    displayModel.clear()

    var count = root.rawSessions.length
    for (var i = 0; i < count; i++) {
      var item = root.rawSessions[i]
      if (!root.matchesFilter(item, tokens)) continue
      displayModel.append({
        isAction: false,
        name: String(item.name || ""),
        isDefault: item.default === true,
        isRunning: item.running === true,
        sessionDir: String(item.session_dir || ""),
        socketPath: String(item.socket_path || "")
      })
    }

    // ONLY append Create action card when input text is NOT empty and NOT an exact match of an existing session
    if (query.length > 0 && !root.sessionExists(query)) {
      displayModel.append({
        isAction: true,
        name: '+ Create "' + query + '"',
        targetName: query,
        isDefault: false,
        isRunning: false,
        sessionDir: "Spawn and attach to new Herdr session",
        socketPath: ""
      })
    }

    if (root.renamingSessionName.length > 0 && !root.sessionExists(root.renamingSessionName)) {
      root.renamingSessionName = ""
    }

    root.selectedIndex = displayModel.count > 0
      ? Math.max(0, Math.min(root.selectedIndex, displayModel.count - 1))
      : 0
    if (!root.userNavigatedList) {
      root.cursorActive = false
    }
    root.disarmPointer()

    Qt.callLater(function() {
      if (displayModel.count > 0) {
        sessionListView.positionViewAtIndex(root.selectedIndex, ListView.Contain)
      }
    })
  }

  function setFilter(newFilter) {
    root.filterText = newFilter
    root.selectedIndex = 0
    root.userNavigatedList = false
    root.cursorActive = false
    root.rebuildDisplay()
  }

  function select(delta) {
    if (displayModel.count === 0) return
    if (!root.userNavigatedList) {
      root.cursorActive = true
      root.userNavigatedList = true
      root.selectedIndex = delta > 0 ? 0 : (displayModel.count - 1)
    } else {
      root.cursorActive = true
      root.userNavigatedList = true
      root.selectedIndex = (root.selectedIndex + delta + displayModel.count) % displayModel.count
    }
    root.disarmPointer()
    sessionListView.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function selectAbsolute(index) {
    if (displayModel.count === 0) return
    root.cursorActive = true
    root.userNavigatedList = true
    root.selectedIndex = Math.max(0, Math.min(index, displayModel.count - 1))
    root.disarmPointer()
    sessionListView.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.userNavigatedList = true
    root.selectedIndex = index
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  // Execution actions
  function attachSession(sessionName) {
    root.dismiss()
    var cmd = ["xdg-terminal-exec", "herdr", "session", "attach", sessionName]
    if (typeof Quickshell !== "undefined" && typeof Quickshell.execDetached === "function") {
      Quickshell.execDetached(cmd)
    } else {
      actionProc.command = cmd
      actionProc.running = true
    }
  }

  function activateIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var item = displayModel.get(index)
    if (item.isAction) {
      var target = (item.targetName || sessionTextInput.text.trim()).trim()
      if (target.length > 0) {
        root.attachSession(target)
      } else {
        sessionTextInput.forceActiveFocus()
        sessionTextInput.selectAll()
      }
    } else {
      root.attachSession(item.name)
    }
  }

  function startRename(name) {
    root.renamingSessionName = name
  }

  function cancelRename() {
    root.renamingSessionName = ""
    Qt.callLater(function() {
      if (typeof sessionTextInput !== "undefined") {
        sessionTextInput.forceActiveFocus()
      }
    })
  }

  function submitRename(oldName, newName) {
    if (!oldName || !newName || oldName === newName || oldName === "default") {
      root.cancelRename()
      return
    }
    var sanitized = newName.replace(/[^a-zA-Z0-9_\-]/g, "")
    if (!sanitized || sanitized === oldName) {
      root.cancelRename()
      return
    }
    if (root.sessionExists(sanitized)) {
      root.errorMessage = 'Session "' + sanitized + '" already exists'
      root.cancelRename()
      return
    }
    root.renameSession(oldName, sanitized)
  }

  function renameSession(oldName, newName) {
    if (!oldName || !newName || oldName === "default" || oldName === newName) {
      root.cancelRename()
      return
    }
    if (opProc.running) return
    root.loading = true
    opProc.callback = function(exitCode, stdoutText, stderrText) {
      root.loading = false
      root.renamingSessionName = ""
      root.fetchSessions()
    }
    opProc.command = [
      "sh", "-c",
      'if [ -e "$HOME/.config/herdr/sessions/$2" ]; then exit 1; fi; herdr session stop "$1" 2>/dev/null; mv "$HOME/.config/herdr/sessions/$1" "$HOME/.config/herdr/sessions/$2"',
      "_", oldName, newName
    ]
    opProc.running = true
  }

  function deleteSession(name) {
    if (!name || name === "default") return
    if (opProc.running) return
    root.loading = true
    root.cancelRename()
    opProc.callback = function(exitCode, stdoutText, stderrText) {
      root.loading = false
      root.fetchSessions()
    }
    opProc.command = [
      "sh", "-c",
      'herdr session stop "$1" 2>/dev/null; herdr session delete "$1" 2>/dev/null; rm -rf "$HOME/.config/herdr/sessions/$1"',
      "_", name
    ]
    opProc.running = true
  }

  ListModel { id: displayModel }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      id: listStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: listStderr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.handleListResult(exitCode, listStdout.text, listStderr.text)
    }
  }

  Process {
    id: actionProc
  }

  Process {
    id: opProc
    property var callback: null
    stdout: StdioCollector {
      id: opStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: opStderr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (callback) {
        var cb = callback
        callback = null
        cb(exitCode, opStdout.text, opStderr.text)
      } else {
        root.loading = false
        root.fetchSessions()
      }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-herdr"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // Background scrim
    Rectangle {
      anchors.fill: parent
      color: root.menuScrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    // Centered menu card (19:9 widescreen aspect ratio)
    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.menuBackground
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea {
        anchors.fill: parent
        onClicked: {
          if (root.renamingSessionName.length > 0) {
            root.cancelRename()
          }
          if (typeof sessionTextInput !== "undefined") {
            sessionTextInput.forceActiveFocus()
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        // Top Header
        Item {
          width: parent.width
          height: root.headerHeight

          Column {
            anchors.left: parent.left
            anchors.right: headerActionsRow.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Row {
              spacing: 10

              Image {
                id: omarchyLogo
                source: "file:///usr/share/omarchy/icon.png"
                width: 22
                height: 22
                fillMode: Image.PreserveAspectFit
                anchors.verticalCenter: parent.verticalCenter
                onStatusChanged: {
                  if (status === Image.Error && source.toString() !== "file:///usr/share/omarchy/logo.svg") {
                    source = "file:///usr/share/omarchy/logo.svg"
                  }
                }
              }

              Text {
                text: "Herdr Sessions"
                color: root.menuForeground
                font.family: root.fontFamily
                font.pixelSize: 18
                font.weight: Font.Bold
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Text {
              text: "Browse, filter, or create active environments"
              color: root.colorMuted
              font.family: root.fontFamily
              font.pixelSize: 12
              elide: Text.ElideRight
            }
          }

          // Header action buttons
          Row {
            id: headerActionsRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            // Reload shortcut hint
            Rectangle {
              height: 32
              width: 32
              radius: 6
              color: reloadMouse.containsMouse ? root.menuSelectedBg : "transparent"
              border.color: reloadMouse.containsMouse ? root.menuBorder : "transparent"
              border.width: 1

              Text {
                anchors.centerIn: parent
                text: "󰑐"
                color: reloadMouse.containsMouse ? root.colorAccent : root.colorMuted
                font.family: root.fontFamily
                font.pixelSize: 14
              }

              MouseArea {
                id: reloadMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.fetchSessions()
              }
            }
          }
        }

        // Permanent Session Name / Search Input Slot
        Rectangle {
          id: sessionInputSlot
          width: parent.width
          height: root.inputSlotHeight
          radius: 8
          color: root.menuBackground
          border.color: sessionTextInput.activeFocus ? root.colorAccent : root.menuBorder
          border.width: 1

          Item {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 8

            // Search icon
            Text {
              id: inputSlotIcon
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "󰍉"
              color: sessionTextInput.activeFocus ? root.colorAccent : root.colorMuted
              font.family: root.fontFamily
              font.pixelSize: 16
            }

            // Inline Create Button (shown when text is typed and NOT an exact match)
            Rectangle {
              id: createActionBtn
              visible: {
                var trimmed = sessionTextInput.text.trim()
                return trimmed.length > 0 && !root.sessionExists(trimmed)
              }
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              height: 28
              width: Math.min(260, createActionBtnRow.width + 16)
              radius: 6
              color: createActionBtnMouse.containsMouse ? root.colorAccent : Qt.rgba(root.colorAccent.r, root.colorAccent.g, root.colorAccent.b, 0.2)
              border.color: root.colorAccent
              border.width: 1

              Row {
                id: createActionBtnRow
                anchors.centerIn: parent
                spacing: 5

                Text {
                  text: "+ Create \"" + sessionTextInput.text.trim() + "\""
                  color: createActionBtnMouse.containsMouse ? root.colorBackground : root.colorAccent
                  font.family: root.fontFamily
                  font.pixelSize: 12
                  font.weight: Font.DemiBold
                  elide: Text.ElideRight
                  maximumLineCount: 1
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: "↵"
                  color: createActionBtnMouse.containsMouse ? root.colorBackground : root.colorAccent
                  font.family: root.fontFamily
                  font.pixelSize: 12
                  font.weight: Font.Bold
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                id: createActionBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  var name = sessionTextInput.text.trim()
                  if (name.length > 0) {
                    root.attachSession(name)
                  }
                }
              }
            }

            Item {
              anchors.left: inputSlotIcon.right
              anchors.leftMargin: 10
              anchors.right: createActionBtn.visible ? createActionBtn.left : parent.right
              anchors.rightMargin: createActionBtn.visible ? 10 : 4
              anchors.top: parent.top
              anchors.bottom: parent.bottom

              TextInput {
                id: sessionTextInput
                anchors.fill: parent
                verticalAlignment: TextInput.AlignVCenter
                color: root.menuForeground
                font.family: root.fontFamily
                font.pixelSize: 13
                clip: true
                selectByMouse: true
                selectionColor: root.colorAccent
                selectedTextColor: root.colorBackground

                onTextChanged: {
                  root.userNavigatedList = false
                  root.cursorActive = false
                  root.setFilter(text)
                }

                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    if (root.renamingSessionName.length > 0) {
                      root.cancelRename()
                    } else {
                      root.dismiss()
                    }
                    event.accepted = true
                  } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_R) {
                    root.fetchSessions()
                    event.accepted = true
                  } else if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_N || event.key === Qt.Key_T)) {
                    sessionTextInput.selectAll()
                    event.accepted = true
                  } else if (event.key === Qt.Key_Up) {
                    root.select(-1)
                    event.accepted = true
                  } else if (event.key === Qt.Key_Down) {
                    root.select(1)
                    event.accepted = true
                  } else if (event.key === Qt.Key_PageUp) {
                    root.select(-5)
                    event.accepted = true
                  } else if (event.key === Qt.Key_PageDown) {
                    root.select(5)
                    event.accepted = true
                  } else if (event.key === Qt.Key_Home) {
                    root.selectAbsolute(0)
                    event.accepted = true
                  } else if (event.key === Qt.Key_End) {
                    root.selectAbsolute(displayModel.count - 1)
                    event.accepted = true
                  } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    var trimmed = sessionTextInput.text.trim()
                    if (root.userNavigatedList && displayModel.count > 0 && root.selectedIndex >= 0 && root.selectedIndex < displayModel.count) {
                      root.activateIndex(root.selectedIndex)
                    } else if (displayModel.count > 0) {
                      root.activateIndex(0)
                    } else if (trimmed.length > 0) {
                      root.attachSession(trimmed)
                    }
                    event.accepted = true
                  }
                }

                Text {
                  anchors.fill: parent
                  verticalAlignment: Text.AlignVCenter
                  text: "Search sessions, or type a new name to create..."
                  color: root.colorMuted
                  font.family: root.fontFamily
                  font.pixelSize: 13
                  visible: !sessionTextInput.text && !sessionTextInput.inputMethodComposing
                }
              }
            }
          }
        }

        // Horizontal Separator
        Rectangle {
          width: parent.width
          height: 1
          color: Qt.rgba(root.menuBorder.r, root.menuBorder.g, root.menuBorder.b, 0.4)
        }

        // Sessions List Area
        Item {
          id: listContainer
          width: parent.width
          height: Math.max(80, parent.height - root.headerHeight - root.inputSlotHeight - root.footerHeight - 2 - (root.contentSpacing * 5))
          clip: true

          ListView {
            id: sessionListView
            anchors.fill: parent
            visible: !root.loading && !root.errorMessage && displayModel.count > 0
            model: displayModel
            clip: true
            spacing: root.rowSpacing
            boundsBehavior: Flickable.StopAtBounds

            delegate: BorderSurface {
              id: sessionRow
              required property int index
              required property bool isAction
              required property string name
              required property bool isDefault
              required property bool isRunning
              required property string sessionDir
              required property string socketPath

              readonly property bool hasCursor: root.cursorActive && sessionRow.index === root.selectedIndex
              readonly property bool isRenaming: root.renamingSessionName === sessionRow.name

              width: ListView.view.width
              height: root.rowHeight
              radius: 8
              color: sessionRow.hasCursor ? root.menuSelectedBg : "transparent"
              borderSpec: sessionRow.hasCursor ? root.selectedBorderSpec : Border.none()

              // Background clickable area for selecting or activating the row
              MouseArea {
                id: rowMouseArea
                anchors.fill: parent
                hoverEnabled: !sessionRow.isRenaming
                cursorShape: sessionRow.isRenaming ? Qt.ArrowCursor : Qt.PointingHandCursor
                onPositionChanged: function(mouse) {
                  if (!sessionRow.isRenaming) {
                    root.selectFromPointer(sessionRow.index, sessionRow, mouse)
                  }
                }
                onClicked: {
                  if (root.renamingSessionName.length > 0 && root.renamingSessionName !== sessionRow.name) {
                    root.cancelRename()
                    return
                  }
                  if (!sessionRow.isRenaming) {
                    root.cursorActive = true
                    root.userNavigatedList = true
                    root.selectedIndex = sessionRow.index
                    root.activateIndex(sessionRow.index)
                  }
                }
              }

              // Normal display content
              Item {
                id: normalDisplayContent
                visible: !sessionRow.isRenaming
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14

                // Icon indicator
                Rectangle {
                  id: statusIconRect
                  width: 36
                  height: 36
                  radius: 8
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  color: sessionRow.isAction
                    ? Qt.rgba(root.colorAccent.r, root.colorAccent.g, root.colorAccent.b, 0.12)
                    : (sessionRow.isRunning ? Qt.rgba(0.2, 0.8, 0.4, 0.12) : Qt.rgba(root.colorMuted.r, root.colorMuted.g, root.colorMuted.b, 0.12))

                  Text {
                    anchors.centerIn: parent
                    text: sessionRow.isAction ? "󰐕" : ""
                    color: sessionRow.isAction
                      ? root.colorAccent
                      : (sessionRow.isRunning ? Qt.rgba(0.25, 0.85, 0.45, 1.0) : root.colorMuted)
                    font.family: root.fontFamily
                    font.pixelSize: 17
                  }
                }

                // Middle Info details
                Column {
                  id: sessionInfoCol
                  anchors.left: statusIconRect.right
                  anchors.leftMargin: 12
                  anchors.right: rowActionsGroup.left
                  anchors.rightMargin: 12
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 2

                  Row {
                    spacing: 8
                    width: parent.width

                    Text {
                      text: sessionRow.name
                      color: sessionRow.hasCursor ? root.menuSelectedFg : root.menuForeground
                      font.family: root.fontFamily
                      font.pixelSize: 14
                      font.weight: Font.DemiBold
                      elide: Text.ElideRight
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    // Default session badge
                    Rectangle {
                      visible: sessionRow.isDefault
                      width: defaultTxt.width + 10
                      height: 18
                      radius: 4
                      color: Qt.rgba(root.colorAccent.r, root.colorAccent.g, root.colorAccent.b, 0.18)
                      anchors.verticalCenter: parent.verticalCenter

                      Text {
                        id: defaultTxt
                        anchors.centerIn: parent
                        text: "DEFAULT"
                        color: root.colorAccent
                        font.family: root.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                      }
                    }

                    // Status pill (running vs stopped)
                    Rectangle {
                      visible: !sessionRow.isAction
                      width: statusTxt.width + 10
                      height: 18
                      radius: 4
                      color: sessionRow.isRunning ? Qt.rgba(0.2, 0.8, 0.4, 0.15) : Qt.rgba(root.colorUrgent.r, root.colorUrgent.g, root.colorUrgent.b, 0.15)
                      anchors.verticalCenter: parent.verticalCenter

                      Text {
                        id: statusTxt
                        anchors.centerIn: parent
                        text: sessionRow.isRunning ? "RUNNING" : "STOPPED"
                        color: sessionRow.isRunning ? Qt.rgba(0.25, 0.85, 0.45, 1.0) : root.colorUrgent
                        font.family: root.fontFamily
                        font.pixelSize: 9
                        font.weight: Font.Bold
                      }
                    }
                  }

                  Text {
                    width: parent.width
                    text: sessionRow.sessionDir || sessionRow.socketPath || "Herdr environment"
                    color: sessionRow.hasCursor ? root.menuSelectedFg : root.colorMuted
                    opacity: sessionRow.hasCursor ? 0.85 : 1.0
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideMiddle
                  }
                }

                // Row action buttons (Rename, Delete, Attach)
                Row {
                  id: rowActionsGroup
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 6

                  // Rename button (for non-default, non-action sessions)
                  Rectangle {
                    visible: !sessionRow.isAction && !sessionRow.isDefault
                    height: 28
                    width: 28
                    radius: 6
                    color: renameBtnMouse.containsMouse ? root.menuSelectedBg : "transparent"
                    border.color: renameBtnMouse.containsMouse ? root.menuBorder : "transparent"
                    border.width: 1
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      anchors.centerIn: parent
                      text: "󰏫"
                      color: renameBtnMouse.containsMouse ? root.colorAccent : root.colorMuted
                      font.family: root.fontFamily
                      font.pixelSize: 14
                    }

                    MouseArea {
                      id: renameBtnMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: function(mouse) {
                        mouse.accepted = true
                        root.startRename(sessionRow.name)
                      }
                    }
                  }

                  // Delete button (for non-default, non-action sessions)
                  Rectangle {
                    visible: !sessionRow.isAction && !sessionRow.isDefault
                    height: 28
                    width: 28
                    radius: 6
                    color: deleteBtnMouse.containsMouse ? Qt.rgba(root.colorUrgent.r, root.colorUrgent.g, root.colorUrgent.b, 0.18) : "transparent"
                    border.color: deleteBtnMouse.containsMouse ? root.colorUrgent : "transparent"
                    border.width: 1
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      anchors.centerIn: parent
                      text: "󰩹"
                      color: deleteBtnMouse.containsMouse ? root.colorUrgent : root.colorMuted
                      font.family: root.fontFamily
                      font.pixelSize: 14
                    }

                    MouseArea {
                      id: deleteBtnMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: function(mouse) {
                        mouse.accepted = true
                        root.deleteSession(sessionRow.name)
                      }
                    }
                  }

                  // Attach / Action pill button
                  Rectangle {
                    id: attachBtnPill
                    anchors.verticalCenter: parent.verticalCenter
                    width: attachTxt.width + 20
                    height: 28
                    radius: 6
                    color: sessionRow.hasCursor ? root.colorAccent : Qt.rgba(1.0, 1.0, 1.0, 0.05)
                    border.color: sessionRow.hasCursor ? root.colorAccent : Qt.rgba(root.menuBorder.r, root.menuBorder.g, root.menuBorder.b, 0.3)
                    border.width: 1

                    Row {
                      anchors.centerIn: parent
                      spacing: 5

                      Text {
                        text: sessionRow.isAction ? "󰐕" : "󰌑"
                        color: sessionRow.hasCursor ? root.colorBackground : root.colorAccent
                        font.family: root.fontFamily
                        font.pixelSize: 11
                        anchors.verticalCenter: parent.verticalCenter
                      }

                      Text {
                        id: attachTxt
                        text: sessionRow.isAction ? "Create" : "Attach"
                        color: sessionRow.hasCursor ? root.colorBackground : root.colorAccent
                        font.family: root.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        anchors.verticalCenter: parent.verticalCenter
                      }
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: function(mouse) {
                        mouse.accepted = true
                        root.cursorActive = true
                        root.userNavigatedList = true
                        root.selectedIndex = sessionRow.index
                        root.activateIndex(sessionRow.index)
                      }
                    }
                  }
                }
              }

              // Inline Rename Editor (visible when sessionRow.isRenaming is true)
              Item {
                id: renameEditor
                visible: sessionRow.isRenaming
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14

                Row {
                  anchors.fill: parent
                  spacing: 12

                  // Edit Icon
                  Rectangle {
                    width: 36
                    height: 36
                    radius: 8
                    anchors.verticalCenter: parent.verticalCenter
                    color: Qt.rgba(root.colorAccent.r, root.colorAccent.g, root.colorAccent.b, 0.15)

                    Text {
                      anchors.centerIn: parent
                      text: "󰏫"
                      color: root.colorAccent
                      font.family: root.fontFamily
                      font.pixelSize: 17
                    }
                  }

                  // Rename Input Field
                  Rectangle {
                    id: renameFieldRect
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 36 - renameActionsRow.width - 24
                    height: 32
                    radius: 6
                    color: root.menuBackground
                    border.color: root.colorAccent
                    border.width: 1

                    TextInput {
                      id: inlineRenameInput
                      anchors.fill: parent
                      anchors.leftMargin: 10
                      anchors.rightMargin: 10
                      verticalAlignment: TextInput.AlignVCenter
                      color: root.menuForeground
                      font.family: root.fontFamily
                      font.pixelSize: 13
                      font.weight: Font.DemiBold
                      clip: true
                      selectByMouse: true
                      selectionColor: root.colorAccent
                      selectedTextColor: root.colorBackground
                      text: sessionRow.name

                      Connections {
                        target: root
                        function onRenamingSessionNameChanged() {
                          if (root.renamingSessionName === sessionRow.name) {
                            inlineRenameInput.text = sessionRow.name
                            Qt.callLater(function() {
                              inlineRenameInput.forceActiveFocus()
                              inlineRenameInput.selectAll()
                            })
                          }
                        }
                      }

                      Component.onCompleted: {
                        if (sessionRow.isRenaming) {
                          inlineRenameInput.text = sessionRow.name
                          Qt.callLater(function() {
                            inlineRenameInput.forceActiveFocus()
                            inlineRenameInput.selectAll()
                          })
                        }
                      }

                      Keys.priority: Keys.BeforeItem
                      Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Escape) {
                          root.cancelRename()
                          event.accepted = true
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                          root.submitRename(sessionRow.name, inlineRenameInput.text.trim())
                          event.accepted = true
                        }
                      }
                    }
                  }

                  // Confirm & Cancel Actions
                  Row {
                    id: renameActionsRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    // Save / Submit Button
                    Rectangle {
                      height: 30
                      width: saveTxt.width + 24
                      radius: 6
                      color: saveMouse.containsMouse ? root.colorAccent : Qt.rgba(root.colorAccent.r, root.colorAccent.g, root.colorAccent.b, 0.2)
                      border.color: root.colorAccent
                      border.width: 1

                      Row {
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                          text: "󰄬"
                          color: saveMouse.containsMouse ? root.colorBackground : root.colorAccent
                          font.family: root.fontFamily
                          font.pixelSize: 12
                          font.weight: Font.Bold
                          anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                          id: saveTxt
                          text: "Save"
                          color: saveMouse.containsMouse ? root.colorBackground : root.colorAccent
                          font.family: root.fontFamily
                          font.pixelSize: 12
                          font.weight: Font.DemiBold
                          anchors.verticalCenter: parent.verticalCenter
                        }
                      }

                      MouseArea {
                        id: saveMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.submitRename(sessionRow.name, inlineRenameInput.text.trim())
                      }
                    }

                    // Cancel Button
                    Rectangle {
                      height: 30
                      width: cancelTxt.width + 20
                      radius: 6
                      color: cancelMouse.containsMouse ? Qt.rgba(root.colorUrgent.r, root.colorUrgent.g, root.colorUrgent.b, 0.15) : "transparent"
                      border.color: cancelMouse.containsMouse ? root.colorUrgent : root.menuBorder
                      border.width: 1

                      Row {
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                          text: "󰅖"
                          color: cancelMouse.containsMouse ? root.colorUrgent : root.colorMuted
                          font.family: root.fontFamily
                          font.pixelSize: 12
                          anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                          id: cancelTxt
                          text: "Cancel"
                          color: cancelMouse.containsMouse ? root.colorUrgent : root.colorMuted
                          font.family: root.fontFamily
                          font.pixelSize: 12
                          anchors.verticalCenter: parent.verticalCenter
                        }
                      }

                      MouseArea {
                        id: cancelMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cancelRename()
                      }
                    }
                  }
                }
              }
            }
          }

          // Loading / Error / Empty state overlay
          Column {
            anchors.centerIn: parent
            width: parent.width - 48
            spacing: 12
            visible: root.loading || root.errorMessage || displayModel.count === 0

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: root.loading ? "󰑐" : (root.errorMessage ? "󰅙" : "")
              color: root.errorMessage ? root.colorUrgent : root.colorAccent
              font.family: root.fontFamily
              font.pixelSize: 32
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: root.loading
                ? "Querying Herdr sessions…"
                : (root.errorMessage
                   ? root.errorMessage
                   : (root.filterText ? "No sessions match \"" + root.filterText + "\"" : "No active Herdr sessions found"))
              color: root.errorMessage ? root.colorUrgent : root.menuForeground
              font.family: root.fontFamily
              font.pixelSize: 15
              font.weight: Font.Medium
              wrapMode: Text.Wrap
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              visible: !root.loading
              text: root.errorMessage ? "Press Ctrl+R to retry" : "Type a name to create a new session"
              color: root.colorMuted
              font.family: root.fontFamily
              font.pixelSize: 12
            }
          }
        }

        // Horizontal Separator
        Rectangle {
          width: parent.width
          height: 1
          color: Qt.rgba(root.menuBorder.r, root.menuBorder.g, root.menuBorder.b, 0.4)
        }

        // Footer status bar
        Item {
          width: parent.width
          height: root.footerHeight

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: {
              var sCount = root.rawSessions.length
              return sCount + (sCount === 1 ? " session configured" : " sessions configured")
            }
            color: root.colorMuted
            font.family: root.fontFamily
            font.pixelSize: 11
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: {
              if (root.renamingSessionName.length > 0) {
                return "Enter Save Name  ·  Esc Cancel Rename"
              }
              return sessionTextInput.text.trim().length > 0
                ? "Enter Create / Attach  ·  ↑↓ Select  ·  Esc Dismiss"
                : "Enter Attach  ·  ↑↓ Select  ·  Ctrl+R Refresh  ·  Esc Dismiss"
            }
            color: root.colorMuted
            font.family: root.fontFamily
            font.pixelSize: 11
          }
        }
      }
    }
  }
}
