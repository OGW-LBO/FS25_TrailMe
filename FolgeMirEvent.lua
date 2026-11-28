--
-- FolgeMirEvent
--
-- Synchronisiert den Folge-Zustand eines Fahrzeugs im Multiplayer.
--
-- Ablauf:
--   Der Client drueckt die Taste und schickt das Ereignis an den Server.
--   Der Server prueft die Berechtigung, setzt den Zustand und verteilt ihn an
--   alle uebrigen Clients, damit HUD und Anzeige ueberall stimmen.
--
-- Im Einzelspieler ist der Spieler selbst der Server; dann wird nur lokal
-- gesetzt und nichts verschickt.
--
-- Autor: OGW
--

FolgeMirEvent = {}

local FolgeMirEvent_mt = Class(FolgeMirEvent, Event)

InitEventClass(FolgeMirEvent, "FolgeMirEvent")

function FolgeMirEvent.emptyNew()
    return Event.new(FolgeMirEvent_mt)
end

function FolgeMirEvent.new(fahrzeug, ziel, grund)
    local self = FolgeMirEvent.emptyNew()

    self.fahrzeug = fahrzeug
    self.ziel     = ziel
    self.folgen   = ziel ~= nil
    self.grund    = grund or 0

    return self
end

function FolgeMirEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.fahrzeug)

    -- Bewusst ohne "and/or": ein false-Wert wuerde den Stream verschieben
    local folgen = false

    if self.folgen == true and self.ziel ~= nil then
        folgen = true
    end

    if streamWriteBool(streamId, folgen) then
        NetworkUtil.writeNodeObject(streamId, self.ziel)
    else
        streamWriteUInt8(streamId, self.grund or 0)
    end
end

function FolgeMirEvent:readStream(streamId, connection)
    self.fahrzeug = NetworkUtil.readNodeObject(streamId)
    self.folgen   = streamReadBool(streamId)
    self.ziel     = nil
    self.grund    = 0

    if self.folgen then
        self.ziel = NetworkUtil.readNodeObject(streamId)
    else
        self.grund = streamReadUInt8(streamId)
    end

    self:run(connection)
end

--- Prueft auf dem Server, ob der Absender ein Fahrzeug losschicken darf.
--- Die Farm wird aus der Verbindung des Absenders ermittelt und nicht aus den
--- mitgeschickten Fahrzeugen - nur so laesst sie sich von aussen nicht
--- vorgeben. Muster aus WashingStationEvent: getUserIdByConnection, dann
--- getFarmByUserId. Geprueft wird das Fahrzeug, das losfahren soll; wem es
--- folgt, darf auch ein Mitspieler aus einer anderen Farm sein.
local function darfBedienen(connection, fahrzeug)
    if g_currentMission == nil or g_currentMission.accessHandler == nil then
        return true
    end

    if g_currentMission.accessHandler.canFarmAccess == nil then
        return true
    end

    if g_currentMission.userManager == nil or g_farmManager == nil then
        return true
    end

    local userId = g_currentMission.userManager:getUserIdByConnection(connection)

    if userId == nil then
        return true
    end

    local farm = g_farmManager:getFarmByUserId(userId)

    if farm == nil or farm.farmId == nil then
        return true
    end

    return g_currentMission.accessHandler:canFarmAccess(farm.farmId, fahrzeug, false) == true
end

--- Administratoren duerfen jede Reihe aufloesen, auch die eines fremden Hofs.
--- Sonst gilt das uebliche Zugriffsrecht.
local function darfStoppen(connection, fahrzeug)
    if g_currentMission ~= nil and g_currentMission.userManager ~= nil then
        local user = g_currentMission.userManager:getUserByConnection(connection)

        if user ~= nil and user.getIsMasterUser ~= nil and user:getIsMasterUser() then
            return true
        end
    end

    return darfBedienen(connection, fahrzeug)
end

--- Wie viele Fahrzeuge haengen bereits an der Reihe, in die dieses hier soll?
local function reiheZuLang(ziel)
    if FolgeMirMain == nil or FolgeMirMain.getWurzel == nil then
        return false
    end

    local grenze = FolgeMirMain.einstellungen.maxFolger

    if grenze == nil or grenze <= 0 then
        return false
    end

    return #FolgeMirMain.getKette(FolgeMirMain.getWurzel(ziel)) >= grenze
end

function FolgeMirEvent:run(connection)
    if self.fahrzeug == nil or self.fahrzeug.fmStartFolgen == nil then
        return
    end

    -- connection:getIsServer() == true bedeutet: die Nachricht kam vom Server,
    -- wir sind also ein Client und uebernehmen den Zustand nur zur Anzeige.
    local istAnfrageVomClient = not connection:getIsServer()

    if istAnfrageVomClient and self.folgen
        and (not darfBedienen(connection, self.fahrzeug) or reiheZuLang(self.ziel)) then
        -- Abgelehnt: der Client hat den Zustand zur schnellen Rueckmeldung
        -- schon lokal gesetzt und muss ihn wieder zuruecknehmen.
        connection:sendEvent(FolgeMirEvent.new(self.fahrzeug, nil, 0))
        return
    end

    -- Auch das Beenden braucht ein Recht, sonst koennte jeder die Reihen
    -- anderer Hoefe anhalten. Der Absender hat lokal schon gestoppt, deshalb
    -- bekommt er den alten Zustand zurueck.
    if istAnfrageVomClient and not self.folgen and not darfStoppen(connection, self.fahrzeug) then
        local altesZiel = nil

        if self.fahrzeug.fmGetZiel ~= nil then
            altesZiel = self.fahrzeug:fmGetZiel()
        end

        if altesZiel ~= nil then
            connection:sendEvent(FolgeMirEvent.new(self.fahrzeug, altesZiel, 0))
        end

        return
    end

    if self.folgen and self.ziel ~= nil then
        self.fahrzeug:fmStartFolgen(self.ziel, true)
    else
        -- Der Grund wird noch gegen das alte Ziel geprueft, deshalb vor dem
        -- Zuruecksetzen melden.
        if self.grund ~= nil and self.grund > 0 and self.fahrzeug.fmGetZiel ~= nil then
            FolgeMirMain.meldungGrund(FolgeMirMain.getWurzel(self.fahrzeug), self.grund)
        end

        self.fahrzeug:fmStoppFolgen(true, 0)
    end

    -- Server: die Anfrage eines Clients an alle uebrigen weiterreichen
    if istAnfrageVomClient and g_server ~= nil then
        local weiter

        if self.folgen then
            weiter = FolgeMirEvent.new(self.fahrzeug, self.ziel, 0)
        else
            weiter = FolgeMirEvent.new(self.fahrzeug, nil, self.grund)
        end

        g_server:broadcastEvent(weiter, false, connection, self.fahrzeug)
    end
end

--- Bequemer Versand aus der Spiellogik heraus.
function FolgeMirEvent.sende(fahrzeug, ziel, grund)
    if fahrzeug == nil or g_currentMission == nil then
        return
    end

    if g_currentMission.getIsServer == nil then
        return
    end

    if g_currentMission:getIsServer() then
        if g_server ~= nil then
            g_server:broadcastEvent(FolgeMirEvent.new(fahrzeug, ziel, grund), false, nil, fahrzeug)
        end
    else
        if g_client ~= nil and g_client:getServerConnection() ~= nil then
            g_client:getServerConnection():sendEvent(FolgeMirEvent.new(fahrzeug, ziel, grund))
        end
    end
end
