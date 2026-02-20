local function fail(msg)
  error(msg, 0)
end

package.loaded["shadowrocket_rules_logic"] = nil
local ok, logic = pcall(require, "shadowrocket_rules_logic")
if not ok then
  fail("failed to require shadowrocket_rules_logic: " .. tostring(logic))
end

if type(logic.extractRuleValueFromSelection) ~= "function" then
  fail("extractRuleValueFromSelection is missing")
end

if type(logic.buildRuleLine) ~= "function" then
  fail("buildRuleLine is missing")
end

if type(logic.appendUniqueRuleLine) ~= "function" then
  fail("appendUniqueRuleLine is missing")
end

if type(logic.hasRuleLine) ~= "function" then
  fail("hasRuleLine is missing")
end

if type(logic.parseShortcut) ~= "function" then
  fail("parseShortcut is missing")
end

if type(logic.formatShortcut) ~= "function" then
  fail("formatShortcut is missing")
end

local host = logic.extractRuleValueFromSelection("https://i.ytimg.com/vi/x/video.jpg")
if host ~= "i.ytimg.com" then
  fail("failed to extract host from URL")
end

local hostWithoutWww = logic.extractRuleValueFromSelection("https://www.github.com/EmporioBreak/Shadowrocket-cfg")
if hostWithoutWww ~= "github.com" then
  fail("failed to strip www prefix from URL host")
end

local fromMarkdown = logic.extractRuleValueFromSelection("[link](https://example.com/path)")
if fromMarkdown ~= "example.com" then
  fail("failed to extract host from markdown URL")
end

local plainDomain = logic.extractRuleValueFromSelection("sub.domain.com")
if plainDomain ~= "sub.domain.com" then
  fail("failed to keep plain domain")
end

local plainDomainWithoutWww = logic.extractRuleValueFromSelection("www.reddit.com")
if plainDomainWithoutWww ~= "reddit.com" then
  fail("failed to strip www prefix from plain domain")
end

local built = logic.buildRuleLine("DOMAIN-SUFFIX", "example.com", "PROXY", "")
if built ~= "DOMAIN-SUFFIX,example.com,PROXY" then
  fail("buildRuleLine produced unexpected value")
end

local builtNoResolve = logic.buildRuleLine("DOMAIN", "api.example.com", "DIRECT", "no-resolve")
if builtNoResolve ~= "DOMAIN,api.example.com,DIRECT,no-resolve" then
  fail("buildRuleLine should append extra flag")
end

local current = "DOMAIN-SUFFIX,example.com,PROXY\n"
local updated, added = logic.appendUniqueRuleLine(current, "DOMAIN-KEYWORD,claude,PROXY")
if not added then
  fail("appendUniqueRuleLine should mark added=true for new rule")
end

if updated ~= "DOMAIN-SUFFIX,example.com,PROXY\nDOMAIN-KEYWORD,claude,PROXY\n" then
  fail("appendUniqueRuleLine should append a new line with trailing newline")
end

local unchanged, addedDuplicate = logic.appendUniqueRuleLine(updated, "DOMAIN-KEYWORD,claude,PROXY")
if addedDuplicate then
  fail("appendUniqueRuleLine should not add duplicate rule")
end

if unchanged ~= updated then
  fail("appendUniqueRuleLine should keep content unchanged for duplicate rule")
end

if logic.hasRuleLine(updated, "DOMAIN-KEYWORD,claude,PROXY") ~= true then
  fail("hasRuleLine should detect existing rule")
end

if logic.hasRuleLine(updated, "DOMAIN-SUFFIX,missing.com,PROXY") ~= false then
  fail("hasRuleLine should return false for missing rule")
end

local mods, key, parseErr = logic.parseShortcut("alt+shift+r")
if parseErr ~= nil or type(mods) ~= "table" or #mods ~= 2 or mods[1] ~= "alt" or mods[2] ~= "shift" or key ~= "r" then
  fail("parseShortcut failed on valid shortcut")
end

local badMods, badKey, badErr = logic.parseShortcut("r")
if badMods ~= nil or badKey ~= nil or type(badErr) ~= "string" or badErr == "" then
  fail("parseShortcut should reject shortcuts without modifiers")
end

local formatted = logic.formatShortcut({"alt", "shift"}, "r")
if formatted ~= "alt+shift+r" then
  fail("formatShortcut returned unexpected output")
end

print("shadowrocket rules logic tests passed")
