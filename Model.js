function contains(arr, value) {
  var want = String(value)
  if (!arr || typeof arr.length !== "number") return false
  for (var i = 0; i < arr.length; i++)
    if (String(arr[i]) === want) return true
  return false
}

function filterIssues(items, prefs) {
  var src = items || []
  if (!src.length) return []
  var teams = (prefs && prefs.teamIds) || []
  var projects = (prefs && prefs.projectIds) || []
  var out = src
  if (teams.length) {
    var byTeam = []
    for (var i = 0; i < src.length; i++) {
      if (src[i] && contains(teams, src[i].teamId)) byTeam.push(src[i])
    }
    if (byTeam.length) out = byTeam
  }
  if (projects.length) {
    var byProject = []
    for (var j = 0; j < out.length; j++) {
      if (out[j] && contains(projects, out[j].projectId)) byProject.push(out[j])
    }
    if (byProject.length) out = byProject
  }
  return out
}

function lastJson(raw) {
  var text = String(raw || "").trim()
  var idx = text.lastIndexOf("\n{")
  if (idx >= 0) text = text.slice(idx + 1).trim()
  return text
}

function parse(raw) {
  var text = lastJson(raw)
  if (!text) return { ok: false, error: "Empty Linear response" }
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return { ok: false, error: "Invalid Linear response" }
    if (parsed.ok === false) return { ok: false, error: String(parsed.error || "Linear request failed") }
    parsed.ok = true
    return parsed
  } catch (e) {
    return { ok: false, error: "Invalid Linear JSON" }
  }
}

function optionList(items, valueKey, labelKey) {
  var out = []
  if (!items) return out
  for (var i = 0; i < items.length; i++) {
    var item = items[i]
    if (!item) continue
    var value = String(item[valueKey] || "")
    if (!value) continue
    out.push({
      value: value,
      label: String(item[labelKey] || item[valueKey] || "")
    })
  }
  return out
}

function accountOptions(accounts) {
  var out = []
  if (!accounts) return out
  for (var i = 0; i < accounts.length; i++) {
    var account = accounts[i]
    if (!account) continue
    out.push({ value: String(account.id || ""), label: String(account.name || account.id || "") })
  }
  return out
}

function scopeOptions() {
  return [
    { value: "assigned", label: "Assigned to me" },
    { value: "open", label: "Open" },
    { value: "active", label: "In progress" }
  ]
}

function agentOptions() {
  return [
    { value: "grok", label: "Grok" },
    { value: "claude", label: "Claude" },
    { value: "codex", label: "Codex" },
    { value: "gemini", label: "Gemini" },
    { value: "opencode", label: "OpenCode" },
    { value: "copilot", label: "Copilot" },
    { value: "cursor", label: "Cursor" },
    { value: "", label: "Off (Herdr only)" }
  ]
}

function priorityLabel(priority) {
  var n = Number(priority || 0)
  if (n === 1) return "Urgent"
  if (n === 2) return "High"
  if (n === 3) return "Medium"
  if (n === 4) return "Low"
  return ""
}

function relativeTime(iso) {
  if (!iso) return ""
  var then = Date.parse(iso)
  if (!isFinite(then)) return ""
  var delta = Math.max(0, Date.now() - then)
  var minutes = Math.floor(delta / 60000)
  if (minutes < 1) return "just now"
  if (minutes < 60) return minutes + "m"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h"
  var days = Math.floor(hours / 24)
  if (days < 14) return days + "d"
  return ""
}

function slugId(name) {
  var slug = String(name || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
  return slug.slice(0, 32) || "account"
}
