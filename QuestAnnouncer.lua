local QuestAnnouncer = CreateFrame("Frame")
QuestAnnouncer:RegisterEvent("QUEST_LOG_UPDATE")

local questProgress = {}
local knownQuests = {}  -- [title] = { level=N, isComplete=bool }
local initialized = false
local debugMode = false

local function DBG(msg)
    if debugMode then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[QA Debug]|r " .. tostring(msg))
    end
end

local function GetQuestIDByName(name)
    if not (pfDB and pfDB["quests"] and pfDB["quests"]["data"]) then
        return nil
    end
    for id, questData in pairs(pfDB["quests"]["data"]) do
        if questData and questData[1] == name then
            return id
        end
    end
    return nil
end

local function MakeQuestLink(id, title, level)
    if id then
        return string.format("|cffffff00|Hquest:%d:%d|h[%s]|h|r", id, level or 1, title)
    else
        return string.format("|cffffff00|Hquest:0:%d|h[%s]|h|r", level or 1, title)
    end
end

local function Announce(msg)
    if msg and msg ~= "" then
        if debugMode then
            DBG("Announce -> " .. msg .. " (party members: " .. GetNumPartyMembers() .. ")")
        end
        if GetNumPartyMembers() > 0 then
            SendChatMessage(msg, "PARTY")
        end
    end
end

local function BuildCurrentQuestSnapshot()
    local snapshot = {}
    local numEntries = GetNumQuestLogEntries()
    for i = 1, numEntries do
        local title, level, _, isHeader, _, isComplete = GetQuestLogTitle(i)
        if title and not isHeader then
            snapshot[title] = { level = level or 1, isComplete = (isComplete == 1) }
        end
    end
    return snapshot
end

local function ClearQuestProgress(title)
    questProgress[title .. "_COMPLETE"] = nil
    for j = 1, 20 do
        questProgress[title .. j] = nil
    end
end

QuestAnnouncer:SetScript("OnEvent", function()
    local currentSnapshot = BuildCurrentQuestSnapshot()

    if debugMode then
        DBG("QUEST_LOG_UPDATE fired | initialized=" .. tostring(initialized))
    end

    -- First event: silently initialize all state, no announcements
    if not initialized then
        knownQuests = currentSnapshot
        local numEntries = GetNumQuestLogEntries()
        for i = 1, numEntries do
            local title, _, _, isHeader, _, isComplete = GetQuestLogTitle(i)
            if title and not isHeader then
                SelectQuestLogEntry(i)
                local numObjectives = GetNumQuestLeaderBoards()
                for j = 1, numObjectives do
                    local desc = GetQuestLogLeaderBoard(j)
                    if desc then
                        questProgress[title .. j] = desc
                    end
                end
                if isComplete == 1 then
                    questProgress[title .. "_COMPLETE"] = true
                end
            end
        end
        if debugMode then
            local count = 0
            for _ in pairs(currentSnapshot) do count = count + 1 end
            DBG("Init: " .. count .. " quests loaded, questProgress silently initialized")
        end
        initialized = true
        return
    end

    -- Detect quests that disappeared from the log
    local toRemove = {}
    for title in pairs(knownQuests) do
        if not currentSnapshot[title] then
            table.insert(toRemove, title)
        end
    end
    for _, title in ipairs(toRemove) do
        local data = knownQuests[title]
        if debugMode then
            DBG("Quest removed: '" .. title .. "' isComplete=" .. tostring(data.isComplete) .. " progressComplete=" .. tostring(questProgress[title .. "_COMPLETE"] == true))
        end
        if not data.isComplete and not questProgress[title .. "_COMPLETE"] then
            local questID = GetQuestIDByName(title)
            local link = MakeQuestLink(questID, title, data.level)
            Announce("Abandoned: " .. link)
        end
        ClearQuestProgress(title)
        knownQuests[title] = nil
    end

    -- Detect newly added quests
    for title, data in pairs(currentSnapshot) do
        if not knownQuests[title] then
            if debugMode then
                DBG("New quest detected: '" .. title .. "' level=" .. tostring(data.level))
            end
            local questID = GetQuestIDByName(title)
            local link = MakeQuestLink(questID, title, data.level)
            Announce(link .. " - Quest started")
            knownQuests[title] = data
        end
    end

    -- Update isComplete (one-directional) and detect Quest Complete before scan
    for title, data in pairs(currentSnapshot) do
        if knownQuests[title] and data.isComplete then
            knownQuests[title].isComplete = true
        end
        if data.isComplete and not questProgress[title .. "_COMPLETE"] then
            questProgress[title .. "_COMPLETE"] = true
            if knownQuests[title] then
                knownQuests[title].isComplete = true
            end
            local questID = GetQuestIDByName(title)
            local link = MakeQuestLink(questID, title, data.level)
            if debugMode then
                DBG("Quest Complete (pre-scan): '" .. title .. "'")
            end
            Announce("Quest Complete: " .. link)
        end
    end

    -- Scan all quest objectives for progress updates (no throttle: questProgress guards prevent duplicates)
    local numEntries = GetNumQuestLogEntries()
    for i = 1, numEntries do
        local title, level, _, isHeader, _, isComplete = GetQuestLogTitle(i)
        if title and not isHeader then
            SelectQuestLogEntry(i)
            local numObjectives = GetNumQuestLeaderBoards()
            local allDone = (numObjectives > 0)

            if debugMode then
                DBG("Scanning '" .. title .. "': " .. numObjectives .. " objectives | isComplete=" .. tostring(isComplete))
            end
            for j = 1, numObjectives do
                local desc, otype, done = GetQuestLogLeaderBoard(j)
                if desc then
                    local key = title .. j
                    local _, _, cur, total = string.find(desc, "(%d+)%s*/%s*(%d+)")
                    cur, total = tonumber(cur), tonumber(total)
                    if debugMode then
                        DBG("  obj" .. j .. " type='" .. tostring(otype) .. "' done=" .. tostring(done) .. " cur=" .. tostring(cur) .. " total=" .. tostring(total) .. " desc='" .. tostring(desc) .. "'")
                    end

                    if not done then
                        allDone = false
                    end

                    -- Announce only if desc changed AND there is actual numeric progress
                    if questProgress[key] ~= desc then
                        questProgress[key] = desc
                        if cur and total and (cur > 0 or done) then
                            local questID = GetQuestIDByName(title)
                            local link = MakeQuestLink(questID, title, level)
                            Announce(link .. " - " .. desc)
                        end
                    end
                end
            end

            -- Fallback Quest Complete for quests where isComplete may lag behind allDone
            if (isComplete == 1 or allDone) and not questProgress[title .. "_COMPLETE"] then
                questProgress[title .. "_COMPLETE"] = true
                if knownQuests[title] then
                    knownQuests[title].isComplete = true
                end
                local questID = GetQuestIDByName(title)
                local link = MakeQuestLink(questID, title, level)
                if debugMode then
                    DBG("Quest Complete (scan fallback): '" .. title .. "'")
                end
                Announce("Quest Complete: " .. link)
            end
        end
    end
end)

local QUESTANNOUNCER_VERSION = "1.0.5"

SLASH_QUESTANNOUNCER1 = "/qa"
SlashCmdList["QUESTANNOUNCER"] = function(msg)
    msg = string.lower(msg or "")
    if msg == "test" then
        local questID = 99999
        local link = MakeQuestLink(questID, "Fake Quest", 10)
        Announce(link .. " started")
        Announce(link .. " - 3/10 Fake Mobs slain")
        Announce("Quest Complete: " .. link)
    elseif msg == "version" then
        print("|cffffcc00QuestAnnouncer:|r version " .. QUESTANNOUNCER_VERSION)
    elseif msg == "debug" then
        debugMode = not debugMode
        if debugMode then
            print("|cffffcc00QuestAnnouncer:|r |cff00ccffdebug ON|r - logs will appear in this chat frame")
        else
            print("|cffffcc00QuestAnnouncer:|r |cff888888debug OFF|r")
        end
    else
        print("|cffffcc00QuestAnnouncer:|r available commands :")
        print(" - /qa test : test to verify that the addon works correctly in the party chat")
        print(" - /qa version : display the current version")
        print(" - /qa debug : toggle debug mode (logs events to chat frame)")
    end
end
