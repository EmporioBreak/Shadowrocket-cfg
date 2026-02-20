local M = {}

local VALID_HOTKEY_MODS = {
  cmd = true,
  alt = true,
  shift = true,
  ctrl = true,
  fn = true,
}

local HOTKEY_MOD_ALIASES = {
  command = "cmd",
  ["⌘"] = "cmd",
  option = "alt",
  ["⌥"] = "alt",
  control = "ctrl",
  ["^"] = "ctrl",
  ["⌃"] = "ctrl",
  ["⇧"] = "shift",
}

local function trim(s)
  local text = tostring(s or "")
  text = text:gsub("^%s+", "")
  text = text:gsub("%s+$", "")
  return text
end

local function normalizeRuleLine(line)
  local raw = trim(line)
  if raw == "" then return "" end

  local out = {}
  for token in raw:gmatch("[^,]+") do
    table.insert(out, trim(token))
  end
  return table.concat(out, ",")
end

local function maybeExtractMarkdownUrl(text)
  local inline = text:match("%b[]%((.-)%)")
  if inline and inline ~= "" then
    return trim(inline)
  end
  return nil
end

local function stripWrappers(text)
  local value = trim(text)
  value = value:gsub("^<", ""):gsub(">$", "")
  value = value:gsub("^[\"']", ""):gsub("[\"']$", "")
  return value
end

local function extractHostLikeValue(raw)
  local value = stripWrappers(raw)
  if value == "" then return "" end

  value = value:gsub("^%w+://", "")
  value = value:gsub("^.-@", "")
  local host = value:match("^([^/%?#]+)") or ""
  host = host:lower()
  host = host:gsub(":%d+$", "")
  host = host:gsub("^www%.", "")
  return trim(host)
end

local function looksLikeDomainOrIp(value)
  if value == "" then return false end
  if value == "localhost" then return true end
  if value:match("^%d+%.%d+%.%d+%.%d+$") then return true end
  return value:match("^[-%w%.]+%.[%a%d%-]+$") ~= nil
end

function M.extractRuleValueFromSelection(selectionText)
  local text = trim(selectionText)
  if text == "" then return "" end

  local markdownUrl = maybeExtractMarkdownUrl(text)
  if markdownUrl then
    local host = extractHostLikeValue(markdownUrl)
    if looksLikeDomainOrIp(host) then
      return host
    end
  end

  local host = extractHostLikeValue(text)
  if looksLikeDomainOrIp(host) then
    return host
  end

  local firstToken = trim(text:match("^(%S+)") or "")
  local tokenHost = extractHostLikeValue(firstToken)
  if looksLikeDomainOrIp(tokenHost) then
    return tokenHost
  end

  return ""
end

function M.buildRuleLine(ruleType, ruleValue, policy, extraFlag)
  local parts = {
    trim(ruleType),
    trim(ruleValue),
    trim(policy),
  }

  local extra = trim(extraFlag)
  if extra ~= "" then
    table.insert(parts, extra)
  end

  return normalizeRuleLine(table.concat(parts, ","))
end

function M.appendUniqueRuleLine(currentContent, newRuleLine)
  local content = tostring(currentContent or "")
  local candidate = normalizeRuleLine(newRuleLine)
  if candidate == "" then
    return content, false
  end

  for line in (content .. "\n"):gmatch("(.-)\n") do
    if normalizeRuleLine(line) == candidate then
      return content, false
    end
  end

  local prefix = content
  if prefix ~= "" and not prefix:match("\n$") then
    prefix = prefix .. "\n"
  end

  return prefix .. candidate .. "\n", true
end

function M.hasRuleLine(content, ruleLine)
  local candidate = normalizeRuleLine(ruleLine)
  if candidate == "" then return false end

  local text = tostring(content or "")
  for line in (text .. "\n"):gmatch("(.-)\n") do
    if normalizeRuleLine(line) == candidate then
      return true
    end
  end
  return false
end

function M.formatShortcut(mods, key)
  local shortcutKey = trim(key):lower()
  if shortcutKey == "" then
    return ""
  end

  local outMods = {}
  for _, mod in ipairs(mods or {}) do
    local normalized = HOTKEY_MOD_ALIASES[trim(mod):lower()] or trim(mod):lower()
    if VALID_HOTKEY_MODS[normalized] then
      table.insert(outMods, normalized)
    end
  end

  if #outMods == 0 then
    return shortcutKey
  end
  return table.concat(outMods, "+") .. "+" .. shortcutKey
end

function M.parseShortcut(input)
  local text = trim(input):lower()
  if text == "" then
    return nil, nil, "Пустой шорткат"
  end

  local parts = {}
  for token in text:gmatch("[^%+]+") do
    local part = trim(token):lower()
    if part ~= "" then
      table.insert(parts, part)
    end
  end

  if #parts < 2 then
    return nil, nil, "Укажи хотя бы один модификатор и клавишу (пример: alt+shift+r)"
  end

  local key = trim(parts[#parts])
  if key == "" then
    return nil, nil, "Не удалось определить клавишу шортката"
  end

  local mods = {}
  local seen = {}
  for i = 1, (#parts - 1) do
    local mod = HOTKEY_MOD_ALIASES[parts[i]] or parts[i]
    if VALID_HOTKEY_MODS[mod] and not seen[mod] then
      table.insert(mods, mod)
      seen[mod] = true
    end
  end

  if #mods == 0 then
    return nil, nil, "Неверные модификаторы. Поддерживаются: cmd, alt, ctrl, shift, fn"
  end

  return mods, key, nil
end

return M
