local logic = require("shadowrocket_rules_logic")

local M = {}

local DEFAULT_SETTINGS = {
  shortcut_mods = {"alt", "shift"},
  shortcut_key = "r",
  repo_owner = "EmporioBreak",
  repo_name = "Shadowrocket-cfg",
  repo_branch = "main",
  repo_rules_path = "myrules.list",
  default_policy = "PROXY",
}

local SETTINGS_KEY = "shadowrocket_rules_settings"
local MESSAGE_PORT = "shadowrocketRulesBuilder"
local CURSOR_OFFSET_X = 4
local CURSOR_OFFSET_Y = 4
local GITHUB_PROPAGATION_MAX_ATTEMPTS = 20
local GITHUB_PROPAGATION_INTERVAL_SEC = 1.0

local builderWebview = nil
local builderController = nil
local statusWebview = nil
local statusHideTimer = nil
local triggerHotkey = nil
local runningTasks = {}
local cachedGhPath = nil
local applyHotkey = nil

local RULE_TYPES = {
  "DOMAIN-SUFFIX",
  "DOMAIN",
  "DOMAIN-KEYWORD",
  "IP-CIDR",
  "URL-REGEX",
  "PROCESS-NAME",
}

local POLICIES = {
  "PROXY",
  "DIRECT",
  "REJECT",
}

local EXTRA_FLAGS = {
  {value = "", label = "Без флага"},
  {value = "no-resolve", label = "no-resolve"},
}

local normalizeSettings

local function trim(s)
  local text = tostring(s or "")
  text = text:gsub("^%s+", "")
  text = text:gsub("%s+$", "")
  return text
end

local function cloneList(items)
  local out = {}
  for _, item in ipairs(items or {}) do
    table.insert(out, item)
  end
  return out
end

local function cloneSettings(settings)
  local src = normalizeSettings(settings)
  return {
    shortcut_mods = cloneList(src.shortcut_mods),
    shortcut_key = src.shortcut_key,
    repo_owner = src.repo_owner,
    repo_name = src.repo_name,
    repo_branch = src.repo_branch,
    repo_rules_path = src.repo_rules_path,
    default_policy = src.default_policy,
  }
end

local function escapeHtml(s)
  return tostring(s or "")
    :gsub("&", "&amp;")
    :gsub("<", "&lt;")
    :gsub(">", "&gt;")
    :gsub('"', "&quot;")
    :gsub("'", "&#39;")
end

local function hideStatusPill()
  if statusHideTimer then
    statusHideTimer:stop()
    statusHideTimer = nil
  end
  if statusWebview then
    statusWebview:delete()
    statusWebview = nil
  end
end

local function showStatusPill(mousePos, text, seconds)
  hideStatusPill()

  local safeText = escapeHtml(text)
  local html = [[<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
  * { margin:0; padding:0; box-sizing:border-box; }
  html,body {
    background:transparent;
    width:100%;
    height:100%;
    display:flex;
    align-items:center;
    justify-content:center;
    overflow:visible;
  }
  .pill {
    display:inline-flex;
    align-items:center;
    gap:10px;
    min-width:180px;
    max-width:420px;
    padding:10px 14px;
    background:rgba(30,30,35,0.92);
    backdrop-filter:blur(20px) saturate(180%);
    -webkit-backdrop-filter:blur(20px) saturate(180%);
    border:1px solid rgba(255,255,255,0.12);
    border-radius:20px;
    box-shadow:0 2px 10px rgba(0,0,0,0.24), inset 0 1px 0 rgba(255,255,255,0.1);
    color:rgba(255,255,255,0.9);
    font-family:-apple-system,sans-serif;
    font-size:13px;
    line-height:1.35;
  }
  .dot {
    width:8px;
    height:8px;
    border-radius:999px;
    background:rgba(255,170,90,0.95);
    box-shadow:0 0 0 3px rgba(255,170,90,0.2);
    flex:0 0 auto;
  }
  .text {
    white-space:nowrap;
    overflow:hidden;
    text-overflow:ellipsis;
  }
</style></head><body>
  <div class="pill">
    <div class="dot"></div>
    <span class="text">]] .. safeText .. [[</span>
  </div>
</body></html>]]

  local width = 360
  local height = 64
  statusWebview = hs.webview.new({
    x = mousePos.x + CURSOR_OFFSET_X,
    y = mousePos.y + CURSOR_OFFSET_Y,
    w = width,
    h = height,
  })
  statusWebview:windowTitle("")
  statusWebview:allowTextEntry(false)
  statusWebview:transparent(true)
  statusWebview:shadow(false)
  statusWebview:windowStyle({"borderless", "nonactivating"})
  statusWebview:level(hs.drawing.windowLevels.floating)
  statusWebview:html(html)
  statusWebview:show()
  statusWebview:bringToFront(true)

  statusHideTimer = hs.timer.doAfter(seconds or 1.6, hideStatusPill)
end

normalizeSettings = function(settings)
  local src = type(settings) == "table" and settings or {}

  local normalized = {
    shortcut_mods = cloneList(src.shortcut_mods),
    shortcut_key = trim(src.shortcut_key):lower(),
    repo_owner = trim(src.repo_owner),
    repo_name = trim(src.repo_name),
    repo_branch = trim(src.repo_branch),
    repo_rules_path = trim(src.repo_rules_path),
    default_policy = trim(src.default_policy),
  }

  if #normalized.shortcut_mods == 0 then
    normalized.shortcut_mods = cloneList(DEFAULT_SETTINGS.shortcut_mods)
  end
  if normalized.shortcut_key == "" then
    normalized.shortcut_key = DEFAULT_SETTINGS.shortcut_key
  end
  if normalized.repo_owner == "" then
    normalized.repo_owner = DEFAULT_SETTINGS.repo_owner
  end
  if normalized.repo_name == "" then
    normalized.repo_name = DEFAULT_SETTINGS.repo_name
  end
  if normalized.repo_branch == "" then
    normalized.repo_branch = DEFAULT_SETTINGS.repo_branch
  end
  if normalized.repo_rules_path == "" then
    normalized.repo_rules_path = DEFAULT_SETTINGS.repo_rules_path
  end
  if normalized.default_policy == "" then
    normalized.default_policy = DEFAULT_SETTINGS.default_policy
  end

  return normalized
end

local function getSettings()
  local stored = hs.settings.get(SETTINGS_KEY)
  local normalized = normalizeSettings(stored)
  hs.settings.set(SETTINGS_KEY, normalized)
  return normalized
end

local function resolveGhPath()
  if cachedGhPath then return cachedGhPath end

  local candidates = {
    "/opt/homebrew/bin/gh",
    "/usr/local/bin/gh",
    "/usr/bin/gh",
  }
  for _, candidate in ipairs(candidates) do
    if hs.fs.attributes(candidate, "mode") then
      cachedGhPath = candidate
      return cachedGhPath
    end
  end

  local output, ok = hs.execute("command -v gh 2>/dev/null", true)
  if ok and trim(output) ~= "" then
    cachedGhPath = trim(output)
    return cachedGhPath
  end

  return nil
end

local function runCommand(commandPath, args, callback)
  local task
  task = hs.task.new(commandPath, function(exitCode, stdout, stderr)
    runningTasks[task] = nil
    callback(exitCode == 0, stdout or "", stderr or "", exitCode)
  end, args)

  if not task then
    callback(false, "", "Не удалось создать задачу hs.task", -1)
    return
  end

  runningTasks[task] = true
  if not task:start() then
    runningTasks[task] = nil
    callback(false, "", "Не удалось запустить задачу hs.task", -1)
  end
end

local function runGh(args, callback)
  local ghPath = resolveGhPath()
  if not ghPath then
    callback(false, "", "CLI gh не найден. Установи GitHub CLI и выполни авторизацию через `gh auth login`.", -1)
    return
  end
  runCommand(ghPath, args, callback)
end

local function buildRulesEndpoint(settings, withRef)
  local basePath = string.format(
    "repos/%s/%s/contents/%s",
    settings.repo_owner,
    settings.repo_name,
    settings.repo_rules_path
  )
  if withRef then
    return basePath .. "?ref=" .. settings.repo_branch
  end
  return basePath
end

local function fetchRulesFile(settings, callback)
  runGh({
    "api",
    buildRulesEndpoint(settings, true),
    "-H", "Accept: application/vnd.github+json",
  }, function(ok, stdout, stderr)
    if not ok then
      callback(false, nil, nil, trim(stderr) ~= "" and trim(stderr) or trim(stdout))
      return
    end

    local parsed = hs.json.decode(stdout)
    if type(parsed) ~= "table" then
      callback(false, nil, nil, "Не удалось разобрать ответ GitHub API")
      return
    end

    local sha = trim(parsed.sha)
    local contentEncoded = tostring(parsed.content or ""):gsub("%s+", "")
    local content = hs.base64.decode(contentEncoded)
    if type(content) ~= "string" then
      callback(false, nil, nil, "Не удалось декодировать содержимое rules-файла")
      return
    end
    if sha == "" then
      callback(false, nil, nil, "GitHub API вернул пустой sha для файла правил")
      return
    end

    callback(true, content, sha, nil)
  end)
end

local function updateRulesFile(settings, newContent, sha, commitMessage, callback)
  runGh({
    "api",
    buildRulesEndpoint(settings, false),
    "--method", "PUT",
    "-H", "Accept: application/vnd.github+json",
    "-f", "message=" .. commitMessage,
    "-f", "content=" .. hs.base64.encode(newContent),
    "-f", "sha=" .. sha,
    "-f", "branch=" .. settings.repo_branch,
  }, function(ok, stdout, stderr)
    if not ok then
      callback(false, trim(stderr) ~= "" and trim(stderr) or trim(stdout))
      return
    end
    callback(true, nil)
  end)
end

local function waitForRuleOnGitHub(settings, ruleLine, callback, attempt)
  local try = tonumber(attempt) or 1
  fetchRulesFile(settings, function(fetchOk, content, _, fetchErr)
    if fetchOk and logic.hasRuleLine(content, ruleLine) then
      callback(true, nil, try)
      return
    end

    if try >= GITHUB_PROPAGATION_MAX_ATTEMPTS then
      local errText = fetchErr
      if trim(errText) == "" then
        errText = "Правило не появилось в читаемом списке на GitHub за отведенное время"
      end
      callback(false, errText, try)
      return
    end

    hs.timer.doAfter(GITHUB_PROPAGATION_INTERVAL_SEC, function()
      waitForRuleOnGitHub(settings, ruleLine, callback, try + 1)
    end)
  end)
end

local function addRuleToGitHub(ruleLine, mousePos)
  local settings = getSettings()
  showStatusPill(mousePos, "Добавляю правило в GitHub…", 1.2)

  fetchRulesFile(settings, function(fetchOk, content, sha, fetchErr)
    if not fetchOk then
      showStatusPill(mousePos, "Ошибка GitHub: " .. tostring(fetchErr or "не удалось загрузить файл"), 2.4)
      return
    end

    local updatedContent, wasAdded = logic.appendUniqueRuleLine(content, ruleLine)
    if not wasAdded then
      showStatusPill(mousePos, "Такое правило уже есть в списке", 1.8)
      return
    end

    local commitMessage = "Add rule: " .. ruleLine
    updateRulesFile(settings, updatedContent, sha, commitMessage, function(updateOk, updateErr)
      if not updateOk then
        showStatusPill(mousePos, "Не удалось записать правило: " .. tostring(updateErr or ""), 2.4)
        return
      end
      showStatusPill(mousePos, "Коммит создан. Жду, пока правило появится в GitHub…", 2.2)

      waitForRuleOnGitHub(settings, ruleLine, function(visible, waitErr)
        if not visible then
          showStatusPill(mousePos, "Правило закоммичено, но подтверждение GitHub не получено: " .. tostring(waitErr or ""), 3.0)
          return
        end
        showStatusPill(mousePos, "Правило успешно добавлено в GitHub.", 2.0)
      end)
    end)
  end)
end

local function closeBuilder()
  local oldWebview = builderWebview
  builderWebview = nil
  if oldWebview then
    pcall(function()
      oldWebview:windowCallback(nil)
    end)
    oldWebview:delete()
  end

  local oldController = builderController
  builderController = nil
  if oldController then
    oldController:setCallback(nil)
  end
end

local function buildOptions(options, selectedValue)
  local html = {}
  for _, option in ipairs(options) do
    local value = option
    local label = option
    if type(option) == "table" then
      value = option.value
      label = option.label
    end
    local selected = (tostring(value) == tostring(selectedValue)) and " selected" or ""
    table.insert(html, "<option value=\"" .. escapeHtml(value) .. "\"" .. selected .. ">" .. escapeHtml(label) .. "</option>")
  end
  return table.concat(html, "\n")
end

local function showBuilderWindow(selectionText, mousePos)
  closeBuilder()

  local extractedValue = logic.extractRuleValueFromSelection(selectionText)
  local initialValue = extractedValue ~= "" and extractedValue or trim(selectionText)
  local settings = getSettings()
  local initialRuleType = "DOMAIN-SUFFIX"
  local initialPolicy = settings.default_policy
  local initialExtra = ""
  local initialPreview = logic.buildRuleLine(initialRuleType, initialValue, initialPolicy, initialExtra)
  local initialShortcut = logic.formatShortcut(settings.shortcut_mods, settings.shortcut_key)

  local html = [[<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
  * { margin:0; padding:0; box-sizing:border-box; }
  body {
    font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif;
    background:rgba(25,25,30,0.98);
    color:#fff; padding:20px;
    min-height:100vh;
  }
  h2 { font-size:16px; font-weight:600; margin-bottom:16px; color:rgba(255,255,255,0.9); }
  h3 { font-size:13px; font-weight:600; margin:20px 0 10px; color:rgba(255,255,255,0.6); text-transform:uppercase; letter-spacing:0.5px; }
  .form { display:flex; flex-direction:column; gap:8px; margin-top:8px; }
  .form-row { display:flex; flex-direction:column; gap:4px; }
  label { font-size:12px; color:rgba(255,255,255,0.5); }
  input, textarea, select {
    background:rgba(255,255,255,0.07);
    border:1px solid rgba(255,255,255,0.12);
    border-radius:8px; padding:7px 10px;
    color:#fff; font-size:13px;
    font-family:-apple-system,sans-serif; outline:none;
  }
  select option {
    color:#fff;
    background:rgba(30,30,35,1);
  }
  textarea {
    min-height:64px;
    resize:vertical;
  }
  input:focus, textarea:focus, select:focus { border-color:rgba(80,160,255,0.5); background:rgba(255,255,255,0.1); }
  .form-buttons { display:flex; gap:8px; margin-top:4px; }
  button {
    font-family:-apple-system,sans-serif; font-size:12px;
    border:none; border-radius:6px; padding:7px 12px; cursor:pointer; font-weight:500;
  }
  .btn-save { background:rgba(80,160,255,0.25); color:rgba(120,180,255,0.95); }
  .btn-save:hover { background:rgba(80,160,255,0.4); }
  .btn-cancel { background:rgba(255,255,255,0.08); color:rgba(255,255,255,0.6); }
  .btn-cancel:hover { background:rgba(255,255,255,0.15); }
  .hint { font-size:11px; color:rgba(255,255,255,0.38); margin-top:2px; }
  .shortcut-row { display:flex; gap:8px; align-items:center; }
  .shortcut-row input { flex:1 1 auto; }
  .hint.error { color:rgba(255,120,120,0.95); }
  .divider { height:1px; background:rgba(255,255,255,0.07); margin:16px 0; }
</style></head>
<body>
  <h2>Конструктор правил GitHub</h2>

  <div class="form">
    <div class="form-row">
      <label>Выделенный текст</label>
      <textarea id="selection" readonly>]] .. escapeHtml(selectionText) .. [[</textarea>
      <div class="hint">Используется как исходник для извлечения домена/значения</div>
    </div>
  </div>

  <div class="divider"></div>

  <h3>Параметры правила</h3>
  <div class="form" id="rule-form">
    <div class="form-row">
      <label>Тип правила</label>
      <select id="rule-type">]] .. buildOptions(RULE_TYPES, initialRuleType) .. [[</select>
    </div>
    <div class="form-row">
      <label>Значение</label>
      <input id="rule-value" value="]] .. escapeHtml(initialValue) .. [[" placeholder="example.com">
    </div>
    <div class="form-row">
      <label>Политика</label>
      <select id="policy">]] .. buildOptions(POLICIES, initialPolicy) .. [[</select>
    </div>
    <div class="form-row">
      <label>Формат (доп. флаг)</label>
      <select id="extra-flag">]] .. buildOptions(EXTRA_FLAGS, initialExtra) .. [[</select>
    </div>
    <div class="form-row">
      <label>Предпросмотр</label>
      <input id="preview" value="]] .. escapeHtml(initialPreview) .. [[" readonly>
    </div>
    <div class="form-buttons">
      <button type="button" class="btn-save" onclick="createRule()">Добавить в GitHub</button>
      <button type="button" class="btn-cancel" onclick="closeWindow()">Закрыть</button>
    </div>
  </div>

  <div class="divider"></div>

  <h3>Настройки скрипта</h3>
  <div class="form" id="script-form">
    <div class="form-row">
      <label>Шорткат конструктора</label>
      <div class="shortcut-row">
        <input id="s-shortcut" value="]] .. escapeHtml(initialShortcut) .. [[" readonly>
        <button type="button" id="btn-capture-shortcut" class="btn-cancel" onclick="startShortcutCapture()">Заменить шорткат</button>
      </div>
      <div class="hint" id="shortcut-status">Нажми кнопку и введи новую комбинацию клавиш</div>
    </div>
  </div>

<script>
  function sendAction(action, payload) {
    try {
      webkit.messageHandlers.]] .. MESSAGE_PORT .. [[.postMessage({
        action: action,
        payload: payload || {}
      });
    } catch (e) {
      console.log("bridge error:", e);
    }
  }

  function getRuleParts() {
    return {
      rule_type: document.getElementById("rule-type").value.trim(),
      rule_value: document.getElementById("rule-value").value.trim(),
      policy: document.getElementById("policy").value.trim(),
      extra_flag: document.getElementById("extra-flag").value.trim()
    };
  }

  function updatePreview() {
    var p = getRuleParts();
    var rule = [p.rule_type, p.rule_value, p.policy].join(",");
    if (p.extra_flag) rule += "," + p.extra_flag;
    document.getElementById("preview").value = rule;
  }

  function createRule() {
    var p = getRuleParts();
    if (!p.rule_type || !p.rule_value || !p.policy) {
      alert("Заполни тип, значение и политику");
      return;
    }
    sendAction("create_rule", p);
  }

  function closeWindow() {
    sendAction("close", {});
  }

  var captureActive = false;
  var captureTimer = null;

  function setCaptureState(active, statusText, tone) {
    var button = document.getElementById("btn-capture-shortcut");
    var status = document.getElementById("shortcut-status");
    if (button) {
      button.disabled = !!active;
      button.textContent = active ? "Нажми комбинацию..." : "Заменить шорткат";
    }
    if (status) {
      status.textContent = statusText || "";
      status.classList.toggle("error", tone === "error");
    }
  }

  function setShortcutValue(value) {
    var input = document.getElementById("s-shortcut");
    if (input) input.value = value || "";
  }

  function normalizeCapturedKey(event) {
    var code = event.code || "";
    if (code.indexOf("Key") === 0) return code.slice(3).toLowerCase();
    if (code.indexOf("Digit") === 0) return code.slice(5);
    if (code.indexOf("F") === 0 && /^F\d{1,2}$/.test(code)) return code.toLowerCase();

    var codeMap = {
      Space: "space",
      Enter: "return",
      Tab: "tab",
      Backspace: "delete",
      Escape: "escape",
      ArrowUp: "up",
      ArrowDown: "down",
      ArrowLeft: "left",
      ArrowRight: "right",
      Minus: "-",
      Equal: "=",
      BracketLeft: "[",
      BracketRight: "]",
      Backslash: "\\",
      Semicolon: ";",
      Quote: "'",
      Comma: ",",
      Period: ".",
      Slash: "/",
      Backquote: "`"
    };
    if (codeMap[code]) return codeMap[code];

    var key = (event.key || "").toLowerCase();
    if (key === " ") return "space";
    if (key === "esc") return "escape";
    if (key === "arrowup") return "up";
    if (key === "arrowdown") return "down";
    if (key === "arrowleft") return "left";
    if (key === "arrowright") return "right";
    if (key === "enter") return "return";
    if (key === "tab") return "tab";
    if (key === "backspace") return "delete";
    if (key.length === 1) return key;
    return "";
  }

  function buildShortcut(event) {
    var mods = [];
    if (event.metaKey) mods.push("cmd");
    if (event.altKey) mods.push("alt");
    if (event.ctrlKey) mods.push("ctrl");
    if (event.shiftKey) mods.push("shift");
    if (!mods.length) return "";

    var key = normalizeCapturedKey(event);
    if (!key || key === "meta" || key === "alt" || key === "control" || key === "shift") return "";
    return mods.join("+") + "+" + key;
  }

  function stopShortcutCapture(statusText, tone) {
    captureActive = false;
    if (captureTimer) {
      clearTimeout(captureTimer);
      captureTimer = null;
    }
    setCaptureState(false, statusText || "Нажми кнопку и введи новую комбинацию клавиш", tone || "info");
  }

  function handleCaptureKeyDown(event) {
    if (!captureActive) return;
    event.preventDefault();
    event.stopPropagation();

    if ((event.key || "").toLowerCase() === "escape") {
      stopShortcutCapture("Запись шортката отменена", "info");
      return;
    }

    var shortcut = buildShortcut(event);
    if (!shortcut) {
      setCaptureState(true, "Нужен хотя бы 1 модификатор и клавиша", "error");
      return;
    }

    setShortcutValue(shortcut);
    stopShortcutCapture("Сохраняю: " + shortcut, "info");
    sendAction("save_shortcut", { shortcut: shortcut });
  }

  function startShortcutCapture() {
    captureActive = true;
    if (captureTimer) clearTimeout(captureTimer);
    captureTimer = setTimeout(function() {
      stopShortcutCapture("Запись отменена: истекло время ожидания", "error");
    }, 8000);
    setCaptureState(true, "Ожидаю комбинацию клавиш...", "info");
  }

  document.getElementById("rule-type").addEventListener("change", updatePreview);
  document.getElementById("rule-value").addEventListener("input", updatePreview);
  document.getElementById("policy").addEventListener("change", updatePreview);
  document.getElementById("extra-flag").addEventListener("change", updatePreview);
  window.addEventListener("keydown", handleCaptureKeyDown, true);
</script>
</body></html>]]

  local screen = hs.screen.mainScreen():frame()
  local width = 520
  local height = 720
  local x = (screen.w - width) / 2
  local y = (screen.h - height) / 2

  builderController = hs.webview.usercontent.new(MESSAGE_PORT)
  local currentController = builderController
  builderController:setCallback(function(message)
    if type(message) ~= "table" then return end
    local body = type(message.body) == "table" and message.body or message
    local action = tostring(body.action or "")
    local payload = type(body.payload) == "table" and body.payload or {}

    if action == "close" then
      closeBuilder()
      return
    end

    if action == "save_shortcut" then
      local shortcut = trim(payload.shortcut)
      local mods, key, parseErr = logic.parseShortcut(shortcut)
      if parseErr then
        showStatusPill(mousePos, parseErr, 2.2)
        return
      end

      local current = getSettings()
      local previous = cloneSettings(current)
      local updated = cloneSettings(current)
      updated.shortcut_mods = cloneList(mods)
      updated.shortcut_key = key

      hs.settings.set(SETTINGS_KEY, normalizeSettings(updated))
      local hotkeyOk, hotkeyErr = applyHotkey()
      if not hotkeyOk then
        hs.settings.set(SETTINGS_KEY, normalizeSettings(previous))
        applyHotkey()
        showStatusPill(mousePos, "Не удалось применить шорткат: " .. tostring(hotkeyErr or ""), 2.4)
        return
      end

      showStatusPill(mousePos, "Шорткат сохранен: " .. logic.formatShortcut(mods, key), 1.8)
      return
    end

    if action == "create_rule" then
      local ruleType = trim(payload.rule_type)
      local ruleValue = trim(payload.rule_value)
      local policy = trim(payload.policy)
      local extraFlag = trim(payload.extra_flag)

      if ruleType == "" or ruleValue == "" or policy == "" then
        showStatusPill(mousePos, "Заполни тип, значение и политику", 2.0)
        return
      end

      local ruleLine = logic.buildRuleLine(ruleType, ruleValue, policy, extraFlag)
      if ruleLine == "" then
        showStatusPill(mousePos, "Не удалось сформировать правило", 2.0)
        return
      end

      closeBuilder()
      addRuleToGitHub(ruleLine, mousePos)
    end
  end)

  builderWebview = hs.webview.new({x = x, y = y, w = width, h = height}, builderController)
  local currentWebview = builderWebview
  builderWebview:windowTitle("Добавить правило")
  builderWebview:allowTextEntry(true)
  builderWebview:windowStyle({"titled", "closable", "resizable"})
  builderWebview:level(hs.drawing.windowLevels.floating)
  builderWebview:html(html)
  builderWebview:windowCallback(function(action)
    if action ~= "closing" then return end
    if builderWebview == currentWebview and builderController == currentController then
      closeBuilder()
    end
  end)
  builderWebview:show()
  builderWebview:bringToFront(true)
end

local function getSelectedTextAsync(callback)
  local focused = hs.uielement.focusedElement()
  if focused then
    local ok, value = pcall(function()
      return focused:selectedText()
    end)
    if ok and type(value) == "string" and trim(value) ~= "" then
      callback(value)
      return
    end
  end

  local snapshot = hs.pasteboard.readAllData()
  local changeBefore = hs.pasteboard.changeCount()
  hs.eventtap.keyStroke({"cmd"}, "c")

  hs.timer.doAfter(0.25, function()
    local changeAfter = hs.pasteboard.changeCount()
    local copiedText = hs.pasteboard.getContents()

    if type(snapshot) == "table" then
      pcall(function()
        hs.pasteboard.writeAllData(snapshot)
      end)
    end

    if changeAfter == changeBefore or trim(copiedText) == "" then
      callback(nil)
      return
    end

    callback(copiedText)
  end)
end

local function openBuilderFromSelection()
  local mousePos = hs.mouse.absolutePosition()
  getSelectedTextAsync(function(selectionText)
    if type(selectionText) ~= "string" or trim(selectionText) == "" then
      showStatusPill(mousePos, "Ничего не выделено: выдели ссылку или домен", 1.8)
      return
    end
    showBuilderWindow(selectionText, mousePos)
  end)
end

applyHotkey = function()
  local settings = getSettings()

  if triggerHotkey then
    triggerHotkey:delete()
    triggerHotkey = nil
  end

  local ok, err = pcall(function()
    triggerHotkey = hs.hotkey.bind(settings.shortcut_mods, settings.shortcut_key, openBuilderFromSelection)
  end)
  if not ok then
    return false, err
  end
  return true, nil
end

local ok, err = applyHotkey()
if not ok then
  hs.alert.show("Не удалось назначить шорткат конструктора правил")
  hs.printf("shadowrocket_rules hotkey error: %s", tostring(err))
end

M.openBuilderFromSelection = openBuilderFromSelection
M.applyHotkey = applyHotkey

return M
