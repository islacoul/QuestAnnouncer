local QuestAnnouncer = CreateFrame("Frame")
QuestAnnouncer:RegisterEvent("QUEST_LOG_UPDATE")

local questProgress = {}
local questStarted = {}

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

QuestAnnouncer:SetScript("OnEvent", function()
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
                local desc, type, done = GetQuestLogLeaderBoard(j)
                if desc then
                    local key = title .. j
                    local _, _, cur, total = string.find(desc, "(%d+)%s*/%s*(%d+)")
                    cur, total = tonumber(cur), tonumber(total)

                    if not done then
                        allDone = false
                    end

                    if (type == "item" or type == "monster") and cur and total then
                        if cur == 0 and not questStarted[title] then
                            questStarted[title] = true
                            local questID = GetQuestIDByName(title)
                            local link = MakeQuestLink(questID, title, level)
                            Announce(link .. " started")
                        elseif cur > 0 or done then
                            if questProgress[key] ~= desc then
                                questProgress[key] = desc
                                local questID = GetQuestIDByName(title)
                                local link = MakeQuestLink(questID, title, level)
                                Announce(link .. " - " .. desc)
                            end
                        end
                    end
                end
            end

            if isComplete == 1 or (numObjectives > 0 and allDone) then
                if not questProgress[title .. "_COMPLETE"] then
                    questProgress[title .. "_COMPLETE"] = true
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
