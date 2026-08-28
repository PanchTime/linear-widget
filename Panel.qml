import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "grigorip.linear"
  ipcTarget: "grigorip.linear"
  manageIpc: false

  property string focusSection: "filters"
  property int filterIndex: 0
  property int issueIndex: 0
  property bool cursorActive: false
  property bool addingAccount: false
  property bool accountsOpen: false
  property bool filtersOpen: false
  property string draftName: ""
  property string draftToken: ""

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property bool dropdownOpen: accountPicker.popupOpen || teamPicker.popupOpen || projectPicker.popupOpen || scopePicker.popupOpen || agentPicker.popupOpen
  readonly property bool formOpen: addingAccount
  readonly property int filterCount: linear.configured ? 5 : 1
  readonly property bool headerHasCursor: cursorActive && focusSection === "header"
  readonly property color barIconColor: linear.configured ? barForeground : Qt.darker(barForeground, 1.55)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Service {
    id: linear
    settings: root.settings
  }

  Connections {
    target: linear
    function onHerdrOpened(label) {
      root.close()
      herdrFocusTimer.label = label
      herdrFocusTimer.restart()
    }
    function onEditorOpened(label) {
      root.close()
    }
    function onIssuesReloaded() {
      root.ensureCursor()
    }
    function onAccountsReloaded() {
      if (root.addingAccount && linear.lastError === "") {
        root.addingAccount = false
        nameField.text = ""
        tokenField.text = ""
      }
    }
  }

  Timer {
    id: herdrFocusTimer
    property string label: ""
    interval: 200
    repeat: false
    onTriggered: linear.refocusHerdr(label)
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { linear.refresh(); return "ok" }
  }

  readonly property string heroMeta: {
    if (!linear.configured) return "Connect a Linear API token"
    if (linear.lastError) return linear.lastError
    if (linear.loading && linear.issueCount === 0) return "Loading issues"
    var bits = [linear.accountName]
    if (linear.statusText) bits.push(linear.statusText)
    return bits.join(" · ")
  }

  function filterKeys() {
    var keys = ["accounts"]
    if (accountsOpen) {
      if (linear.configured) keys.push("accountPicker")
      keys.push("addAccount")
      if (addingAccount) keys.push("saveAccount")
    }
    if (linear.configured) {
      keys.push("filters")
      if (filtersOpen) {
        keys.push("team")
        keys.push("project")
        keys.push("scope")
        keys.push("agent")
      }
    }
    return keys
  }

  function filterCursorCount() {
    return filterKeys().length
  }

  function filterKeyAt(index) {
    var keys = filterKeys()
    if (index < 0 || index >= keys.length) return ""
    return keys[index]
  }

  function ensureCursor() {
    if (focusSection === "issues" && linear.issueCount === 0) focusSection = "filters"
    if (filterIndex >= filterCursorCount()) filterIndex = Math.max(0, filterCursorCount() - 1)
    if (issueIndex >= linear.issueCount) issueIndex = Math.max(0, linear.issueCount - 1)
  }

  function activePicker() {
    var key = filterKeyAt(filterIndex)
    if (key === "accountPicker") return accountPicker
    if (key === "team") return teamPicker
    if (key === "project") return projectPicker
    if (key === "scope") return scopePicker
    if (key === "agent") return agentPicker
    return null
  }

  function closePickers() {
    accountPicker.close()
    teamPicker.close()
    projectPicker.close()
    scopePicker.close()
    agentPicker.close()
  }

  function closeAccounts() {
    closePickers()
    addingAccount = false
    accountsOpen = false
    hoverFilterKey("accounts")
    ensureCursor()
  }

  function toggleAccounts() {
    cursorActive = true
    focusSection = "filters"
    if (accountsOpen) closeAccounts()
    else {
      accountsOpen = true
      hoverFilterKey("accounts")
    }
  }

  function closeFilters() {
    closePickers()
    filtersOpen = false
    hoverFilterKey("filters")
    ensureCursor()
  }

  function toggleFilters() {
    cursorActive = true
    focusSection = "filters"
    if (filtersOpen) closeFilters()
    else {
      filtersOpen = true
      hoverFilterKey("filters")
    }
  }

  function collapseFolds() {
    closePickers()
    addingAccount = false
    accountsOpen = false
    filtersOpen = false
    ensureCursor()
  }

  function hoverFilterKey(key) {
    if (root.dropdownOpen) return
    cursorActive = true
    focusSection = "filters"
    var keys = filterKeys()
    for (var i = 0; i < keys.length; i++) {
      if (keys[i] === key) { filterIndex = i; return }
    }
  }

  function openCurrentFilter() {
    cursorActive = true
    focusSection = "filters"
    if (!filtersOpen) {
      filtersOpen = true
      Qt.callLater(function() {
        var keys = filterKeys()
        for (var i = 0; i < keys.length; i++) {
          if (keys[i] === "team") { filterIndex = i; teamPicker.open(); return }
        }
      })
      return
    }
    var picker = activePicker()
    if (picker) picker.open()
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (root.dropdownOpen) {
      if (dy !== 0) {
        var openPicker = activePicker()
        if (openPicker && openPicker.move) openPicker.move(dy)
      }
      return
    }
    if (focusSection === "header") {
      if (dy > 0) { focusSection = "filters"; filterIndex = 0 }
      return
    }
    if (focusSection === "filters") {
      if (dy < 0) {
        if (filterIndex === 0) { focusSection = "header"; return }
        filterIndex = Math.max(0, filterIndex - 1)
        return
      }
      if (dy > 0) {
        if (filterIndex < filterCursorCount() - 1) {
          filterIndex += 1
          return
        }
        if (linear.issues.length > 0) { focusSection = "issues"; issueIndex = 0; scrollIssueIntoView() }
      }
      return
    }
    if (focusSection === "issues") {
      if (dy < 0 && issueIndex === 0) {
        focusSection = "filters"
        return
      }
      issueIndex = Math.max(0, Math.min(linear.issues.length - 1, issueIndex + dy))
      scrollIssueIntoView()
    }
  }

  function selectedIssue() {
    if (linear.issues.length === 0) return null
    var idx = Math.max(0, Math.min(issueIndex, linear.issues.length - 1))
    return linear.issues[idx]
  }

  function openSelectedInHerdr() {
    var issue = selectedIssue()
    if (!issue) return
    linear.openInHerdr(issue)
  }

  function openSelectedInBrowser() {
    var issue = selectedIssue()
    if (issue) linear.openIssue(issue.url)
  }

  function openSelectedPr() {
    var issue = selectedIssue()
    if (issue) linear.openPr(issue)
  }

  function openSelectedInEditor() {
    var issue = selectedIssue()
    if (!issue) return
    linear.openInEditor(issue)
  }

  function activateCursor() {
    cursorActive = true
    if (root.dropdownOpen) {
      var picker = activePicker()
      if (picker && picker.toggleCurrent) picker.toggleCurrent()
      return
    }
    if (focusSection === "header") { linear.refresh(); return }
    if (focusSection === "issues") {
      openSelectedInHerdr()
      return
    }
    var key = filterKeyAt(filterIndex)
    if (key === "accounts") { toggleAccounts(); return }
    if (key === "filters") { toggleFilters(); return }
    if (key === "addAccount") { addingAccount = !addingAccount; if (addingAccount) accountsOpen = true; return }
    if (key === "saveAccount") { submitAccount(); return }
    openCurrentFilter()
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function grabKeys() {
    if (keyCatcher) keyCatcher.forceActiveFocus()
  }

  function open() {
    openFromHotkey()
  }

  function openFromHotkey() {
    root.controller.show()
    linear.refresh()
    cursorActive = true
    focusSection = linear.issueCount > 0 ? "issues" : "filters"
    if (!linear.configured) accountsOpen = true
    issueIndex = 0
    filterIndex = 0
    Qt.callLater(function() {
      if (!root.opened) return
      setCenterHoverRevealSuppressed(true)
      grabKeys()
      focusRetry.restart()
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  Timer {
    id: focusRetry
    interval: 90
    repeat: false
    onTriggered: if (root.opened) grabKeys()
  }

  function submitAccount() {
    var name = String(nameField.text || draftName || "").trim()
    var token = String(tokenField.text || draftToken || "").trim()
    if (!name || !token) return
    linear.addAccount(name, token)
  }

  function scrollIssueIntoView() {
    if (issueList && issueIndex >= 0 && issueIndex < issueList.count)
      issueList.positionViewAtIndex(issueIndex, ListView.Contain)
    if (!panelFlick || !issueList || !issueList.visible) return
    Qt.callLater(function() {
      if (!panelFlick || !issueList) return
      var margin = Style.space(8)
      var point = issueList.mapToItem(column, 0, 0)
      var top = point.y
      var bottom = top + issueList.height
      var viewTop = panelFlick.contentY
      var viewH = panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - viewH)
      if (viewH <= 0) return
      if (top < viewTop + margin)
        panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewTop + viewH - margin)
        panelFlick.contentY = Math.min(maxY, Math.max(0, bottom + margin - viewH))
    })
  }

  onOpenedChanged: if (opened) {
    addingAccount = !linear.configured
    if (panelFlick) panelFlick.contentY = 0
    grabKeys()
    focusRetry.restart()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        LinearIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: root.barIconColor
          accent: Color.accent
          dimmed: !linear.configured
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) linear.refresh()
      else root.toggle()
    }

    Rectangle {
      visible: linear.issueCount > 0
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.rightMargin: Style.space(2)
      anchors.topMargin: Style.space(1)
      width: countLabel.implicitWidth + Style.space(6)
      height: Math.max(Style.space(12), countLabel.implicitHeight + Style.space(2))
      radius: height / 2
      color: Style.selectedFillFor(root.barForeground, Color.accent)

      Text {
        id: countLabel
        anchors.centerIn: parent
        text: linear.issueCount > 9 ? "9+" : String(linear.issueCount)
        color: root.barForeground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: nameField.activeFocus || tokenField.activeFocus
      onMoveRequested: function(dx, dy) {
        root.moveCursor(dx, dy)
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: {
        if (root.dropdownOpen) root.closePickers()
        else if (root.accountsOpen || root.filtersOpen || root.addingAccount) root.collapseFolds()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var key = String(t || "")
        if (key === "[") root.toggleFilters()
        else if (key === "]") {
          if (root.dropdownOpen) root.closePickers()
          else root.collapseFolds()
        }
        else if (key.toLowerCase() === "r") linear.refresh()
        else if (key.toLowerCase() === "a") root.toggleAccounts()
        else if (key.toLowerCase() === "o") root.openSelectedInBrowser()
        else if (key.toLowerCase() === "p") root.openSelectedPr()
        else if (key.toLowerCase() === "e") root.openSelectedInEditor()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Linear"
            meta: root.heroMeta
            detail: {
              if (!linear.configured) return ""
              var bits = []
              if (linear.scopes && linear.scopes.length) bits.push(linear.scopes.join("+"))
              if (linear.agentKind) bits.push(linear.agentKind)
              return bits.join(" · ")
            }
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: linear.configured ? 1.0 : 0.55
            iconComponent: Component {
              LinearIcon {
                iconSize: Style.font.display
                color: root.foreground
                accent: Color.accent
                dimmed: !linear.configured
              }
            }
          }

          Text {
            visible: linear.lastError !== ""
            width: parent.width
            text: linear.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          FoldHeader {
            title: "Accounts"
            open: root.accountsOpen
            hasCursor: root.cursorActive && root.focusSection === "filters" && root.filterKeyAt(root.filterIndex) === "accounts"
            onClicked: root.toggleAccounts()
          }

          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: root.accountsOpen

            FilterPicker {
              id: accountPicker
              width: parent.width
              label: "Show"
              values: linear.accountIds
              options: Model.accountOptions(linear.accounts)
              emptyLabel: "None"
              foreground: root.foreground
              fontFamily: root.fontFamily
              visible: linear.configured
              hasCursor: root.cursorActive && root.focusSection === "filters" && root.filterKeyAt(root.filterIndex) === "accountPicker"
              onChanged: function(v) { linear.setAccountIds(v) }
              onHovered: function(on) { if (on) root.hoverFilterKey("accountPicker") }
            }

            Button {
              text: addingAccount ? "Cancel" : (linear.configured ? "Add account" : "Connect Linear")
              iconText: addingAccount ? "" : "+"
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusSection === "filters" && root.filterKeyAt(root.filterIndex) === "addAccount"
              onClicked: addingAccount = !addingAccount
              onHovered: function(on) { if (on) root.hoverFilterKey("addAccount") }
            }

            Column {
              visible: addingAccount
              width: parent.width
              spacing: Style.space(8)

              Text {
                width: parent.width
                text: "Paste a Linear personal API token. Create one at linear.app/settings/account/security."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }

              TextField {
                id: nameField
                width: parent.width
                placeholderText: "Account name (Personal, Work)"
                foreground: root.foreground
                hasCursor: root.cursorActive && root.focusSection === "filters" && root.filterKeyAt(root.filterIndex) === "saveAccount" && !tokenField.activeFocus
                onAccepted: tokenField.forceActiveFocus()
              }

              TextField {
                id: tokenField
                width: parent.width
                placeholderText: "lin_api_…"
                password: true
                foreground: root.foreground
                onAccepted: root.submitAccount()
              }

              Button {
                text: "Save token"
                foreground: root.foreground
                accent: Color.accent
                bordered: true
                fontFamily: root.fontFamily
                hasCursor: root.cursorActive && root.focusSection === "filters" && root.filterKeyAt(root.filterIndex) === "saveAccount"
                onClicked: root.submitAccount()
              }
            }

            Repeater {
              id: accountRepeater
              model: linear.accounts
              delegate: RowLayout {
                required property var modelData
                width: column.width
                spacing: Style.space(8)
                visible: linear.accounts.length > 0 && !addingAccount

                Text {
                  Layout.fillWidth: true
                  text: String(modelData.name || modelData.id)
                  color: {
                    var id = String(modelData.id || "")
                    var ids = linear.accountIds || []
                    for (var i = 0; i < ids.length; i++)
                      if (String(ids[i]) === id) return root.foreground
                    return root.dim
                  }
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }

                PanelActionButton {
                  iconText: "×"
                  tooltipText: "Remove account"
                  foreground: root.dim
                  hoverColor: root.urgent
                  onClicked: linear.removeAccount(modelData.id)
                }
              }
            }
          }

          FoldHeader {
            title: "Filters"
            open: root.filtersOpen
            visible: linear.configured
            hasCursor: root.cursorActive && root.focusSection === "filters" && root.filterKeyAt(root.filterIndex) === "filters"
            onClicked: root.toggleFilters()
          }

          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: linear.configured && root.filtersOpen

            FilterPicker {
              id: teamPicker
              width: parent.width
              label: "Team"
              values: linear.teamIds
              options: Model.optionList(linear.teams, "id", "name")
              emptyLabel: "Any"
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusSection === "filters" && root.filterKeyAt(root.filterIndex) === "team"
              onChanged: function(v) { linear.setTeamIds(v) }
              onHovered: function(on) { if (on) root.hoverFilterKey("team") }
            }

            FilterPicker {
              id: projectPicker
              width: parent.width
              label: "Project"
              values: linear.projectIds
              options: Model.optionList(linear.projects, "id", "name")
              emptyLabel: "Any"
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusSection === "filters" && root.filterKeyAt(root.filterIndex) === "project"
              onChanged: function(v) { linear.setProjectIds(v) }
              onHovered: function(on) { if (on) root.hoverFilterKey("project") }
            }

            FilterPicker {
              id: scopePicker
              width: parent.width
              label: "Scope"
              values: linear.scopes
              options: Model.scopeOptions()
              emptyLabel: "Any"
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusSection === "filters" && root.filterKeyAt(root.filterIndex) === "scope"
              onChanged: function(v) { linear.setScopes(v) }
              onHovered: function(on) { if (on) root.hoverFilterKey("scope") }
            }

            FilterPicker {
              id: agentPicker
              width: parent.width
              label: "Agent"
              multiple: false
              values: linear.agentKind ? [linear.agentKind] : [""]
              options: Model.agentOptions()
              emptyLabel: "Off"
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusSection === "filters" && root.filterKeyAt(root.filterIndex) === "agent"
              onChanged: function(v) { linear.setAgentKind(v && v.length ? v[v.length - 1] : "") }
              onHovered: function(on) { if (on) root.hoverFilterKey("agent") }
            }
          }

          PanelSectionHeader {
            visible: linear.configured
            text: "TASKS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            visible: linear.configured && !linear.loading && linear.issueCount === 0 && linear.lastError === ""
            width: parent.width
            text: "No issues match these filters."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          ListView {
            id: issueList
            width: parent.width
            visible: linear.issueCount > 0
            clip: true
            spacing: Style.space(6)
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            interactive: contentHeight > height
            keyNavigationEnabled: false
            highlightMoveDuration: 0
            model: linear.issueCount
            currentIndex: root.focusSection === "issues" ? root.issueIndex : -1
            height: Math.min(contentHeight, Style.space(420))
            delegate: IssueRow {
              required property int index
              width: issueList.width
              issue: linear.issueAt(index)
              rowIndex: index
            }
            onCurrentIndexChanged: {
              if (currentIndex >= 0)
                positionViewAtIndex(currentIndex, ListView.Contain)
            }
          }
        }
      }
    }
  }

  component IssueRow: CursorSurface {
    id: issueRow
    property var issue: null
    property int rowIndex: 0
    hasCursor: root.cursorActive && root.focusSection === "issues" && root.issueIndex === rowIndex
    foreground: root.foreground

    implicitHeight: issueInner.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        root.focusSection = "issues"
        root.issueIndex = issueRow.rowIndex
        keyCatcher.forceActiveFocus()
      }
      onPressed: function(mouse) {
        if (!issueRow.issue) return
        mouse.accepted = true
        if (mouse.button === Qt.MiddleButton) linear.openPr(issueRow.issue)
        else if (mouse.button === Qt.RightButton) linear.openIssue(issueRow.issue.url)
        else linear.openInHerdr(issueRow.issue)
      }
    }

    Column {
      id: issueInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(3)

      RowLayout {
        width: parent.width
        spacing: Style.space(8)

        Text {
          visible: linear.multiAccount && issue && issue.accountName
          text: issue ? String(issue.accountName || "") : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          text: issue ? String(issue.identifier || "") : ""
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }

        Text {
          Layout.fillWidth: true
          text: issue ? String(issue.state || "") : ""
          color: issue && issue.stateColor ? issue.stateColor : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Text {
          visible: issue && Number(issue.priority || 0) > 0 && Number(issue.priority) <= 2
          text: Model.priorityLabel(issue ? issue.priority : 0)
          color: Number(issue && issue.priority) === 1 ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          text: Model.relativeTime(issue ? issue.updatedAt : "")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        width: parent.width
        text: issue ? String(issue.title || "") : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        wrapMode: Text.NoWrap
      }

      Text {
        visible: issue && (issue.teamKey || issue.projectName || issue.herdrLabel || issue.prUrl)
        width: parent.width
        text: {
          if (!issue) return ""
          var bits = []
          if (issue.worktree) bits.push(issue.herdrLabel || "Herdr")
          else bits.push("no worktree")
          if (issue.prUrl)
            bits.push(String(issue.prUrl).indexOf("merge_requests") >= 0 ? "MR" : "PR")
          if (issue.teamKey) bits.push(issue.teamKey)
          if (issue.projectName) bits.push(issue.projectName)
          return bits.join(" · ")
        }
        color: issue && issue.worktree ? root.dim : root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }

  component FoldHeader: Item {
    id: fold
    property string title: ""
    property bool open: false
    property bool hasCursor: false
    signal clicked()

    width: parent ? parent.width : 0
    implicitHeight: foldRow.implicitHeight + Style.space(6)
    height: implicitHeight

    RowLayout {
      id: foldRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(8)

      Text {
        text: fold.title.toUpperCase()
        color: fold.hasCursor ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        height: 1
        color: Qt.darker(root.foreground, 1.8)
      }

      Text {
        text: fold.open ? "󰅃" : "󰅀"
        color: fold.hasCursor ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      hoverEnabled: true
      onClicked: fold.clicked()
    }
  }
}
