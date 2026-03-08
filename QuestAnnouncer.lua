local QuestAnnouncer = CreateFrame("Frame")
QuestAnnouncer:RegisterEvent("QUEST_LOG_UPDATE")
QuestAnnouncer:RegisterEvent("QUEST_ACCEPTED")

local questProgress = {}
local knownQuests = {}  -- [title] = { level=N, isComplete=bool }
local initialized = false

local lastUpdate = 0

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
    if msg and msg ~= "" and GetNumPartyMembers() > 0 then
        SendChatMessage(msg, "PARTY")
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

    -- QUEST_ACCEPTED: announce immediately, before any objective progress
    if event == "QUEST_ACCEPTED" then
        for title, data in pairs(currentSnapshot) do
            if not knownQuests[title] then
                local questID = GetQuestIDByName(title)
                local link = MakeQuestLink(questID, title, data.level)
                Announce(link .. " - Quest started")
                knownQuests[title] = data
            end
        end
        initialized = true
        return
    end

    -- QUEST_LOG_UPDATE: initial snapshot load, abandon detection, fallback start detection
    if not initialized then
        knownQuests = currentSnapshot
        initialized = true
    else
        -- Detect quests that disappeared from the log
        local toRemove = {}
        for title in pairs(knownQuests) do
            if not currentSnapshot[title] then
                toRemove[#toRemove + 1] = title
            end
        end
        for _, title in ipairs(toRemove) do
            local data = knownQuests[title]
            if not data.isComplete then
                local questID = GetQuestIDByName(title)
                local link = MakeQuestLink(questID, title, data.level)
                Announce("Abandoned: " .. link)
            end
            ClearQuestProgress(title)
            knownQuests[title] = nil
        end

        -- Detect newly added quests (fallback if QUEST_ACCEPTED did not fire)
        for title, data in pairs(currentSnapshot) do
            if not knownQuests[title] then
                local questID = GetQuestIDByName(title)
                local link = MakeQuestLink(questID, title, data.level)
                Announce(link .. " - Quest started")
                knownQuests[title] = data
            end
        end
    end

    -- Keep isComplete state up to date for turn-in detection
    for title, data in pairs(currentSnapshot) do
        if knownQuests[title] then
            knownQuests[title].isComplete = data.isComplete
        end
    end

    -- Throttle objective progress scanning only
    if GetTime() - lastUpdate < 0.5 then return end
    lastUpdate = GetTime()

    local numEntries = GetNumQuestLogEntries()
    for i = 1, numEntries do
        local title, level, _, isHeader, _, isComplete = GetQuestLogTitle(i)
        if title and not isHeader then
            SelectQuestLogEntry(i)
            local numObjectives = GetNumQuestLeaderBoards()
            local allDone = true

            for j = 1, numObjectives do
                local desc, otype, done = GetQuestLogLeaderBoard(j)
                if desc then
                    local key = title .. j
                    local _, _, cur, total = string.find(desc, "(%d+)%s*/%s*(%d+)")
                    cur, total = tonumber(cur), tonumber(total)

                    if not done then
                        allDone = false
                    end

                    if cur and total then
                        if cur > 0 or done then
                            if questProgress[key] ~= desc then
                                questProgress[key] = desc
                                local questID = GetQuestIDByName(title)
                                local link = MakeQuestLink(questID, title, level)
                                Announce(link .. " - " .. desc)
                            end
                        elseif questProgress[key] == nil then
                            -- Initialize tracking without announcing (cur == 0)
                            questProgress[key] = desc
                        end
                    end
                end
            end

            if isComplete == 1 or (numObjectives > 0 and allDone) then
                if not questProgress[title .. "_COMPLETE"] then
                    questProgress[title .. "_COMPLETE"] = true
                    if knownQuests[title] then
                        knownQuests[title].isComplete = true
                    end
                    local questID = GetQuestIDByName(title)
                    local link = MakeQuestLink(questID, title, level)
                    Announce("Quest Complete: " .. link)
                end
            end
        end
    end
end)

SLASH_QUESTANNOUNCER1 = "/qa"
SlashCmdList["QUESTANNOUNCER"] = function(msg)
    msg = string.lower(msg or "")
    if msg == "test" then
        local questID = 99999
        local link = MakeQuestLink(questID, "Fake Quest", 10)
        Announce(link .. " started")
        Announce(link .. " - 3/10 Fake Mobs slain")
        Announce("Quest Complete: " .. link)
    else
        print("|cffffcc00QuestAnnouncer:|r available commands :")
        print(" - /qa test : test to verify that the addon works correctly in the party chat")
    end
end
