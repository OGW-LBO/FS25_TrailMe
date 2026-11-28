--
-- FolgeMirMeldungEvent
--
-- Ein Hinweis an den Spieler, dessen Fahrzeug gefolgt wird, ohne dass das
-- Folgen dabei endet. Gebraucht wird das, wenn ein Fahrzeug der Reihe
-- haengenbleibt: gemerkt hat es der Server, wissen muss es der Mensch am
-- Steuer des vorderen Fahrzeugs.
--
-- Verschickt wird an alle; wen der Hinweis angeht, entscheidet jeder
-- Empfaenger selbst anhand des mitgeschickten Fahrzeugs. Damit braucht es
-- keine Suche nach der richtigen Verbindung.
--
-- Autor: OGW
--

FolgeMirMeldungEvent = {}

local FolgeMirMeldungEvent_mt = Class(FolgeMirMeldungEvent, Event)

InitEventClass(FolgeMirMeldungEvent, "FolgeMirMeldungEvent")

function FolgeMirMeldungEvent.emptyNew()
    return Event.new(FolgeMirMeldungEvent_mt)
end

--- @param ziel  Fahrzeug, dem gefolgt wird
--- @param grund Eintrag aus FolgeMirMain.gruende
function FolgeMirMeldungEvent.new(ziel, grund)
    local self = FolgeMirMeldungEvent.emptyNew()

    self.ziel  = ziel
    self.grund = grund or 0

    return self
end

function FolgeMirMeldungEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.ziel)
    streamWriteUInt8(streamId, self.grund or 0)
end

function FolgeMirMeldungEvent:readStream(streamId, connection)
    self.ziel  = NetworkUtil.readNodeObject(streamId)
    self.grund = streamReadUInt8(streamId)

    self:run(connection)
end

function FolgeMirMeldungEvent:run(connection)
    if FolgeMirMain == nil or FolgeMirMain.meldungGrund == nil then
        return
    end

    FolgeMirMain.meldungGrund(self.ziel, self.grund)
end

--- Verschickt den Hinweis. Im Einzelspieler wird er gleich angezeigt.
function FolgeMirMeldungEvent.sende(ziel, grund)
    if ziel == nil or grund == nil or grund == 0 then
        return
    end

    if g_currentMission == nil or g_currentMission.getIsServer == nil then
        return
    end

    if not g_currentMission:getIsServer() then
        return
    end

    if g_server ~= nil then
        g_server:broadcastEvent(FolgeMirMeldungEvent.new(ziel, grund), false, nil, ziel)
    end

    -- Der Server selbst steht nicht in der Empfaengerliste. Im Einzelspieler
    -- sitzt der Spieler genau dort, deshalb hier noch einmal oertlich.
    FolgeMirMain.meldungGrund(ziel, grund)
end
