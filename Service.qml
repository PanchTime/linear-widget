import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  readonly property string helper: {
    var url = String(Qt.resolvedUrl("linear.py") || "")
    if (url.indexOf("file://") === 0)
      url = decodeURIComponent(url.slice("file://".length))
    return url
  }
  readonly property int refreshIntervalSec: {
    var n = parseInt(String((settings && settings.refreshIntervalSec) || 90), 10)
    if (!isFinite(n)) n = 90
    if (n < 15) n = 15
    if (n > 3600) n = 3600
    return n
  }

  property var accounts: []
  property var teams: []
  property var projects: []
  property var rawIssues: []
  property var issues: []
  property int issueCount: 0
  property var prefs: ({ accountIds: [], teamIds: [], projectIds: [], scopes: ["assigned"], agentKind: "grok" })
  signal issuesReloaded()
  signal accountsReloaded()
  property var viewer: ({ name: "", email: "" })
  property string lastError: ""
  property string statusText: ""
  property bool loading: false
  property bool configured: accounts.length > 0

  readonly property var accountIds: prefs.accountIds || []
  readonly property var teamIds: prefs.teamIds || []
  readonly property var projectIds: prefs.projectIds || []
  readonly property var scopes: prefs.scopes || []
  readonly property string agentKind: String(prefs.agentKind || "")
  readonly property bool multiAccount: accountIds.length !== 1
  readonly property string accountName: {
    var names = []
    for (var i = 0; i < accounts.length; i++) {
      var id = String(accounts[i].id || "")
      for (var j = 0; j < accountIds.length; j++) {
        if (String(accountIds[j]) === id) names.push(String(accounts[i].name || id))
      }
    }
    if (names.length) return names.join(" + ")
    return configured ? "Linear" : "Linear"
  }

  property var _queue: []
  property bool _busy: false
  property string _herdrBusy: ""

  function enqueue(command, stdinText, onOk) {
    _queue.push({ command: command, stdinText: stdinText || "", onOk: onOk })
    pump()
  }

  function pump() {
    if (_busy || _queue.length === 0) return
    var job = _queue.shift()
    _busy = true
    loading = true
    runner.job = job
    runner.stdinEnabled = !!(job && job.stdinText)
    runner.command = job.command
    runner.running = false
    runner.running = true
    runnerWatchdog.restart()
  }

  function apply(raw, onOk) {
    var parsed = Model.parse(raw)
    if (!parsed.ok) {
      lastError = parsed.error || "Linear request failed"
      statusText = ""
      _herdrBusy = ""
      return
    }
    lastError = parsed.warning ? String(parsed.warning) : ""
    if (parsed.accounts) publishAccounts(parsed.accounts)
    if (parsed.prefs && parsed.teams === undefined && parsed.issues === undefined)
      prefs = parsed.prefs
    if (parsed.teams) teams = parsed.teams
    if (parsed.projects) projects = parsed.projects
    if (parsed.issues) {
      rawIssues = parsed.issues
      var shown = Model.filterIssues(parsed.issues, prefs)
      if ((!shown || !shown.length) && parsed.issues.length)
        shown = parsed.issues
      publishIssues(shown)
    }
    if (parsed.viewer) viewer = parsed.viewer
    if (parsed.count !== undefined && !parsed.issues) {}
    if (typeof onOk === "function") onOk(parsed)
  }

  function publishAccounts(next) {
    var copy = []
    var src = next || []
    for (var i = 0; i < src.length; i++) copy.push(src[i])
    accounts = []
    accounts = copy
    accountsReloaded()
  }

  function publishIssues(next) {
    var copy = []
    var src = next || []
    for (var i = 0; i < src.length; i++) copy.push(src[i])
    issues = copy
    issueCount = copy.length
    statusText = issueCount === 1 ? "1 issue" : issueCount + " issues"
    issuesReloaded()
  }

  function issueAt(index) {
    var i = Number(index)
    if (!issues || i < 0 || i >= issues.length) return null
    return issues[i]
  }

  function showFiltered() {
    var next = Model.filterIssues(rawIssues, prefs)
    if ((!next || !next.length) && rawIssues && rawIssues.length)
      next = rawIssues
    publishIssues(next)
  }

  function refreshAccounts() {
    enqueue(["python3", helper, "accounts"], "", function() {
      if (configured) {
        refreshMeta()
        refreshIssues()
      }
    })
  }

  function refreshMeta() {
    if (!configured) return
    enqueue(["python3", helper, "meta"], "", null)
  }

  function refreshIssues() {
    if (!configured) {
      publishIssues([])
      return
    }
    enqueue(["python3", helper, "issues"], "", function() {
      showFiltered()
    })
  }

  function refresh() {
    refreshAccounts()
  }

  function mergePrefs(patch) {
    var next = {
      accountIds: prefs.accountIds || [],
      teamIds: prefs.teamIds || [],
      projectIds: prefs.projectIds || [],
      scopes: prefs.scopes || [],
      agentKind: prefs.agentKind || ""
    }
    for (var key in patch) next[key] = patch[key]
    prefs = next
    return next
  }

  function persistPrefs(patch, refetch) {
    var args = ["python3", helper, "prefs", "set"]
    var keys = ["accountIds", "teamIds", "projectIds", "scopes", "agentKind"]
    for (var i = 0; i < keys.length; i++) {
      var key = keys[i]
      if (patch[key] === undefined) continue
      args.push("--" + key)
      var val = patch[key]
      if (val && typeof val !== "string" && typeof val.length === "number") {
        var parts = []
        for (var j = 0; j < val.length; j++) parts.push(String(val[j]))
        args.push(parts.join(","))
      } else {
        args.push(val === undefined || val === null ? "" : String(val))
      }
    }
    enqueue(args, "", function() {
      if (refetch) {
        refreshMeta()
        refreshIssues()
      } else {
        refreshMeta()
      }
    })
  }

  function setAccountIds(values) {
    mergePrefs({ accountIds: values || [], teamIds: [], projectIds: [] })
    showFiltered()
    persistPrefs({ accountIds: values || [], teamIds: [], projectIds: [] }, true)
  }

  function setTeamIds(values) {
    mergePrefs({ teamIds: values || [], projectIds: [] })
    showFiltered()
    persistPrefs({ teamIds: values || [], projectIds: [] }, false)
  }

  function setProjectIds(values) {
    mergePrefs({ projectIds: values || [] })
    showFiltered()
    persistPrefs({ projectIds: values || [] }, false)
  }

  function setScopes(values) {
    mergePrefs({ scopes: values || [] })
    showFiltered()
    persistPrefs({ scopes: values || [] }, true)
  }

  function setAgentKind(value) {
    mergePrefs({ agentKind: value || "" })
    persistPrefs({ agentKind: value || "" }, false)
  }

  function addAccount(name, token) {
    var ident = Model.slugId(name)
    enqueue(["python3", helper, "add", "--id", ident, "--name", name], String(token || "").trim() + "\n", function(parsed) {
      if (parsed && parsed.prefs) mergePrefs(parsed.prefs)
      mergePrefs({ teamIds: [], projectIds: [] })
      refreshMeta()
      refreshIssues()
    })
  }

  function removeAccount(id) {
    var keep = []
    var selected = []
    for (var i = 0; i < accounts.length; i++) {
      if (String(accounts[i].id) === String(id)) continue
      keep.push(accounts[i])
      selected.push(String(accounts[i].id))
    }
    publishAccounts(keep)
    mergePrefs({ accountIds: selected, teamIds: [], projectIds: [] })
    showFiltered()
    enqueue(["python3", helper, "remove", String(id || "")], "", function() {
      refreshMeta()
      refreshIssues()
    })
  }

  function openIssue(url) {
    var href = String(url || "").trim()
    if (!/^https:\/\//i.test(href)) return
    Quickshell.execDetached(["omarchy-launch-browser", href])
  }

  function openPr(issue) {
    if (!issue) return
    var url = String(issue.prUrl || "")
    if (!url) {
      statusText = "No MR/PR on " + String(issue.identifier || "issue")
      return
    }
    openIssue(url)
    statusText = (url.indexOf("merge_requests") >= 0 ? "MR · " : "PR · ") + String(issue.identifier || "")
  }

  signal herdrOpened(string label)
  signal editorOpened(string label)

  function openInEditor(issue) {
    if (!issue || !issue.identifier) return
    var ident = String(issue.identifier)
    var account = String(issue.accountId || "")
    var editCmd = ["python3", helper, "edit", ident]
    if (account) editCmd.push(account)
    enqueue(editCmd, "", function(parsed) {
      statusText = "Editor · " + String(parsed.identifier || ident)
      editorOpened(String(parsed.herdrLabel || ident))
    })
  }

  function openInHerdr(issue) {
    if (!issue || !issue.identifier) return
    var ident = String(issue.identifier)
    var account = String(issue.accountId || "")
    if (_herdrBusy) return
    _herdrBusy = ident
    var herdrCmd = ["python3", helper, "herdr", ident]
    if (account) herdrCmd.push(account)
    enqueue(herdrCmd, "", function(parsed) {
      _herdrBusy = ""
      var agent = String(parsed.agentKind || "")
      var action = String(parsed.agentAction || "")
      statusText = "Herdr · " + String(parsed.herdrLabel || ident)
      if (parsed.agentError) statusText += " · " + String(parsed.agentError)
      else if (agent && action === "continue") statusText += " · " + agent + " resumed"
      else if (agent && action === "focus") statusText += " · " + agent
      else if (agent && action === "start") statusText += " · " + agent + " started"
      herdrOpened(String(parsed.herdrLabel || ident))
    })
  }

  function refocusHerdr(label) {
    if (!label) return
    enqueue(["python3", helper, "focus", label], "", null)
  }

  Process {
    id: runner
    property var job: ({})
    property string outText: ""
    stdinEnabled: false
    stdout: StdioCollector {
      id: runnerOut
      waitForEnd: true
      onStreamFinished: runner.outText = String(text || "")
    }
    stderr: StdioCollector { id: runnerErr; waitForEnd: true }
    onStarted: {
      outText = ""
      if (job && job.stdinText) write(job.stdinText)
      Qt.callLater(function() { stdinEnabled = false })
    }
    onExited: function(exitCode) {
      runnerWatchdog.stop()
      stdinEnabled = false
      var raw = outText || String(runnerOut.text || "")
      outText = ""
      if (exitCode !== 0 && !String(raw).trim())
        raw = JSON.stringify({ ok: false, error: String(runnerErr.text || "Linear helper failed").trim() })
      root.apply(raw, job ? job.onOk : null)
      _busy = false
      loading = _queue.length > 0
      pump()
    }
  }

  Timer {
    id: runnerWatchdog
    interval: 25000
    repeat: false
    onTriggered: {
      if (runner.running) runner.running = false
    }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: root.configured
    repeat: true
    onTriggered: root.refreshIssues()
  }

  Component.onCompleted: refreshAccounts()
}
