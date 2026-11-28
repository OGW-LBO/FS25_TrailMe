--
-- FolgeMirSettingsEvent
--
-- Haelt die Einstellungen im Mehrspieler zusammen. Gefahren wird auf dem
-- Server, also muessen Abstand, Tempo und die uebrigen Werte dort ankommen -
-- eine Einstellung, die nur in der eigenen settings.xml steht, wirkt im
-- Mehrspieler nicht.
--
--   mitWerten = true  -> der Traeger enthaelt alle Werte.
--                        Server empfaengt: uebernehmen und weiterverteilen.
--                        Client empfaengt: uebernehmen.
--   mitWerten = false -> ein Client fragt nach dem aktuellen Stand.
--
-- Aendern darf nur, wer auf dem Server sitzt oder dort als Administrator
-- angemeldet ist. Alle anderen bekommen ihren Vorschlag nicht uebernommen,
-- sondern den geltenden Stand zurueck.
--
-- Die Werte gehen ohne ihre Namen ueber die Leitung, in der Reihenfolge aus
-- FolgeMirMain.getNamen. Deshalb steht die Anzahl davor: passt sie nicht,
-- fahren Server und Client verschiedene Fassungen der Mod und der ganze
-- Datensatz wird verworfen, statt die Werte zu verschieben.
--
-- Autor: OGW
--

FolgeMirSettingsEvent = {}

local FolgeMirSettingsEvent_mt = Class(FolgeMirSettingsEvent, Event)

InitEventClass(FolgeMirSettingsEvent, "FolgeMirSettingsEvent")

function FolgeMirSettingsEvent.emptyNew()
    return Event.new(FolgeMirSettingsEvent_mt)
end

--- @param mitWerten boolean true = Werte mitschicken, false = nur nachfragen
function FolgeMirSettingsEvent.new(mitWerten)
    local self = FolgeMirSettingsEvent.emptyNew()

    self.mitWerten = (mitWerten == true)

    return self
end

function FolgeMirSettingsEvent:writeStream(streamId, connection)
    streamWriteBool(streamId, self.mitWerten)

    if not self.mitWerten then
        return
    end

    local namen = FolgeMirMain.getNamen()

    streamWriteUInt8(streamId, #namen)

    for _, name in ipairs(namen) do
        streamWriteFloat32(streamId, FolgeMirMain.einstellungen[name] or 0)
    end
end

--- Liest die Werte ein, ohne sie anzuwenden. Ob sie gelten, entscheidet run -
--- auf dem Server haengt das an der Berechtigung des Absenders.
function FolgeMirSettingsEvent:readStream(streamId, connection)
    self.mitWerten = streamReadBool(streamId)
    self.werte     = nil

    if not self.mitWerten then
        self:run(connection)
        return
    end

    local anzahl = streamReadUInt8(streamId)
    local namen  = FolgeMirMain.getNamen()

    if anzahl ~= #namen then
        -- Den Rest des Datenstroms trotzdem lesen, sonst geraet alles
        -- Folgende aus dem Takt.
        for _ = 1, anzahl do
            streamReadFloat32(streamId)
        end

        Logging.warning(FolgeMirMain.LOG ..
            "Einstellungen verworfen: Gegenseite schickt %d Werte, hier sind %d bekannt. " ..
            "Laeuft auf Server und Client dieselbe Fassung der Mod?", anzahl, #namen)

        self.mitWerten = false
        self:run(connection)
        return
    end

    local werte = {}

    for _, name in ipairs(namen) do
        werte[name] = streamReadFloat32(streamId)
    end

    self.werte = werte

    self:run(connection)
end

--- Uebernimmt die eingelesenen Werte. Was nur den eigenen Bildschirm
--- angeht, bleibt unberuehrt.
function FolgeMirSettingsEvent:anwenden()
    if self.werte == nil then
        return
    end

    for name, wert in pairs(self.werte) do
        if not FolgeMirMain.nurLokal[name] then
            FolgeMirMain.setzeWert(name, wert, true, true)
        end
    end
end

--- Darf der Absender die Einstellungen aendern? Der eigene Rechner darf es
--- immer, ein Mitspieler nur als angemeldeter Administrator.
local function darfAendern(connection)
    if g_currentMission == nil or g_currentMission.userManager == nil then
        return false
    end

    local user = g_currentMission.userManager:getUserByConnection(connection)

    if user == nil or user.getIsMasterUser == nil then
        return false
    end

    return user:getIsMasterUser() == true
end

function FolgeMirSettingsEvent:run(connection)
    -- connection:getIsServer() == true bedeutet: die Nachricht kam vom
    -- Server, wir sind also ein Client.
    local wirSindClient = connection:getIsServer()

    if wirSindClient then
        -- Vom Server kommt der geltende Stand, der wird uebernommen.
        self:anwenden()
        return
    end

    if not self.mitWerten then
        -- Nachfrage eines Clients: den geltenden Stand zurueckschicken.
        connection:sendEvent(FolgeMirSettingsEvent.new(true))
        return
    end

    if not darfAendern(connection) then
        -- Abgelehnt, und zwar bevor hier etwas gesetzt wird. Der Absender hat
        -- die Werte bei sich schon gesetzt und bekommt deshalb den geltenden
        -- Stand zurueck.
        connection:sendEvent(FolgeMirSettingsEvent.new(true))
        return
    end

    self:anwenden()

    FolgeMirMain.speichereEinstellungen()

    if g_server ~= nil then
        g_server:broadcastEvent(FolgeMirSettingsEvent.new(true), false, connection)
    end
end

--- Verteilt die eigenen Werte. Auf dem Server an alle, als Client als
--- Vorschlag an den Server.
function FolgeMirSettingsEvent.sende()
    if g_currentMission == nil or g_currentMission.getIsServer == nil then
        return
    end

    if g_currentMission:getIsServer() then
        if g_server ~= nil then
            g_server:broadcastEvent(FolgeMirSettingsEvent.new(true), false)
        end

        return
    end

    if g_client ~= nil and g_client:getServerConnection() ~= nil then
        g_client:getServerConnection():sendEvent(FolgeMirSettingsEvent.new(true))
    end
end

--- Fragt als Client den geltenden Stand ab. Auf dem Server gibt es nichts
--- abzufragen, dort gelten die eigenen Werte.
function FolgeMirSettingsEvent.frageAn()
    if g_currentMission == nil or g_currentMission.getIsServer == nil then
        return
    end

    if g_currentMission:getIsServer() then
        return
    end

    if g_client == nil or g_client:getServerConnection() == nil then
        return
    end

    g_client:getServerConnection():sendEvent(FolgeMirSettingsEvent.new(false))
end
