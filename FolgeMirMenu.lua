--
-- FolgeMirMenu
--
-- Die Einstellungen im Spielmenue, unter Einstellungen - Allgemein, in einem
-- eigenen Abschnitt am Ende der Liste. Die Konsolenbefehle bleiben erhalten,
-- aber darauf angewiesen ist niemand mehr: Auf einem Mitspieler-Rechner ist
-- die Konsole gesperrt, Einstellungen waren dort bisher gar nicht erreichbar.
--
-- Gebaut wird durch Klonen der Zeilen, die das Spiel selbst benutzt. Dadurch
-- passt sich der Abschnitt von allein an Schriftgroesse, Auflanzung und
-- Farbgebung des Menues an, und es braucht keine eigene GUI-Datei.
-- Muster aus den laufenden Mods ProductionSpeed und NachbarFelder.
--
-- Wer im Mehrspieler nicht als Administrator angemeldet ist, sieht die
-- serverweiten Zeilen ausgegraut - aendern darf sie nur, wer auch den
-- Spielablauf aendern darf.
--
-- Autor: OGW
--

FolgeMirMenu = {}

FolgeMirMenu.gebaut  = false
FolgeMirMenu.zeilen  = {}
FolgeMirMenu.kopf    = nil
FolgeMirMenu.versuche = 0
FolgeMirMenu.MAX_VERSUCHE = 60

-- Die Zeilen in der Reihenfolge, in der sie im Menue stehen.
--
--   name    Einstellung in FolgeMirMain.einstellungen
--   werte   waehlbare Werte
--   einheit wird hinter die Zahl geschrieben
--   texte   feste Beschriftungen statt Zahlen (l10n-Schluessel)
FolgeMirMenu.AUFBAU = {
    {
        name   = "abstand",
        titel  = "fm_m_abstand",
        hilfe  = "fm_m_abstand_lang",
        werte  = { 3, 5, 8, 10, 12, 15, 20, 25, 30, 40, 50, 60 },
        einheit = "m"
    },
    {
        name   = "maxTempo",
        titel  = "fm_m_tempo",
        hilfe  = "fm_m_tempo_lang",
        werte  = { 5, 10, 15, 20, 25, 30, 40, 50, 60, 75, 90 },
        einheit = "km/h"
    },
    {
        name   = "festSekunden",
        titel  = "fm_m_fest",
        hilfe  = "fm_m_fest_lang",
        werte  = { 12, 20, 30, 45, 60, 120 },
        einheit = "s"
    },
    {
        name   = "leerlaufSekunden",
        titel  = "fm_m_leer",
        hilfe  = "fm_m_leer_lang",
        werte  = { 10, 30, 60, 120, 300, 600, 1800 },
        einheit = "s"
    },
    {
        name   = "maxFolger",
        titel  = "fm_m_folger",
        hilfe  = "fm_m_folger_lang",
        werte  = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }
    },
    {
        name   = "suchradius",
        titel  = "fm_m_radius",
        hilfe  = "fm_m_radius_lang",
        werte  = { 5, 10, 15, 20, 30, 40, 60 },
        einheit = "m"
    },
    {
        name   = "maxZielentfernung",
        titel  = "fm_m_reichweite",
        hilfe  = "fm_m_reichweite_lang",
        werte  = { 50, 100, 150, 250, 400, 600, 800 },
        einheit = "m"
    },
    {
        name   = "licht",
        titel  = "fm_m_licht",
        hilfe  = "fm_m_licht_lang",
        werte  = { 0, 1, 2 },
        texte  = { "fm_m_aus", "fm_m_wieVorn", "fm_m_auto" }
    },
    {
        name   = "warnleuchte",
        titel  = "fm_m_leuchte",
        hilfe  = "fm_m_leuchte_lang",
        werte  = { 0, 1, 2 },
        texte  = { "fm_m_aus", "fm_m_wieVorn", "fm_m_immer" }
    },
    {
        name   = "hudAnzeigen",
        titel  = "fm_m_hud",
        hilfe  = "fm_m_hud_lang",
        werte  = { 0, 1, 2 },
        texte  = { "fm_m_aus", "fm_m_amHud", "fm_m_frei" }
    },
    {
        name   = "spurZeigen",
        titel  = "fm_m_spur",
        hilfe  = "fm_m_spur_lang",
        werte  = { 0, 1 },
        texte  = { "fm_m_aus", "fm_m_an" }
    }
}

-- ============================================================================
-- Kleine Helfer
-- ============================================================================

local function t(schluessel, ersatz)
    return FolgeMirMain.text(schluessel, ersatz or schluessel)
end

--- Die Beschriftungen einer Zeile.
local function baueTexte(zeile)
    local liste = {}

    if zeile.texte ~= nil then
        for i, schluessel in ipairs(zeile.texte) do
            liste[i] = t(schluessel)
        end

        return liste
    end

    for i, wert in ipairs(zeile.werte) do
        if zeile.einheit ~= nil then
            liste[i] = string.format("%g %s", wert, zeile.einheit)
        else
            liste[i] = string.format("%g", wert)
        end
    end

    return liste
end

--- Welcher Eintrag passt zum gespeicherten Wert? Gesucht wird der naechste,
--- denn in der settings.xml kann durch die Konsole jede Zahl stehen.
local function findeIndex(zeile)
    local wert  = FolgeMirMain.einstellungen[zeile.name] or 0
    local beste = 1
    local nah   = math.huge

    for i, kandidat in ipairs(zeile.werte) do
        local weg = math.abs(kandidat - wert)

        if weg < nah then
            nah   = weg
            beste = i
        end
    end

    return beste
end

--- Neue, eindeutige Kennungen fuer die Tastatur- und Controller-Steuerung.
--- Geklonte Elemente bringen die des Vorbilds mit, und doppelte Kennungen
--- bringen den FocusManager durcheinander.
local function neueFokusIds(element)
    if element == nil then
        return
    end

    element.focusId = FocusManager:serveAutoFocusId()

    if element.elements ~= nil then
        for _, kind in ipairs(element.elements) do
            neueFokusIds(kind)
        end
    end
end

--- Im Mehrspieler darf nur der Administrator die serverweiten Werte setzen.
local function darfAendern()
    if FolgeMirMain.istAdmin ~= nil then
        return FolgeMirMain.istAdmin()
    end

    return true
end

-- ============================================================================
-- Aufbau
-- ============================================================================

--- Hangt die Abschnitts-Ueberschrift an, indem die des Spiels geklont wird.
local function baueUeberschrift(seite)
    if seite.generalSettingsLayout == nil then
        return
    end

    for _, element in ipairs(seite.generalSettingsLayout.elements) do
        if element.name == "sectionHeader" then
            local kopf = element:clone(seite.generalSettingsLayout)

            kopf.focusId = FocusManager:serveAutoFocusId()

            if seite.controlsList ~= nil then
                table.insert(seite.controlsList, kopf)
            end

            FolgeMirMenu.kopf = kopf

            return
        end
    end

    Logging.warning(FolgeMirMain.LOG .. "Keine Abschnitts-Ueberschrift zum Klonen gefunden.")
end

--- Die Ueberschrift sagt, woran man ist. Ohne diesen Zusatz sieht ein
--- Mitspieler ohne Anmeldung nur graue Zeilen und weiss nicht, warum.
local function setzeUeberschrift()
    local kopf = FolgeMirMenu.kopf

    if kopf == nil or kopf.setText == nil then
        return
    end

    local text = t("fm_m_abschnitt", "Spurfolger")

    if not darfAendern() then
        text = text .. "  (" .. t("fm_m_nurAdminKurz", "nur Administrator") .. ")"
    end

    kopf:setText(text)
end

--- Baut eine Zeile mit Auswahlfeld.
local function baueZeile(seite, zeile)
    local vorbild = seite.multiVolumeVoiceBox

    if vorbild == nil then
        return nil
    end

    local box = vorbild:clone(seite.generalSettingsLayout)

    neueFokusIds(box)

    box.id = "fm_" .. zeile.name .. "Box"

    local option = box.elements ~= nil and box.elements[1] or nil

    if option == nil then
        Logging.warning(FolgeMirMain.LOG .. "Zeile %s hat kein Auswahlfeld.", zeile.name)
        return nil
    end

    option.id = "fm_" .. zeile.name

    -- Der FocusManager vergleicht den Namen des Ziels mit dem der Seite und
    -- uebergeht alles, was nicht dazu passt.
    FolgeMirMenu.name = seite.name

    option.target = FolgeMirMenu

    -- Die Funktion direkt zuweisen und nicht ueber setCallback gehen:
    -- setCallback loest den Namen sofort auf und laesst hier erzeugte
    -- Funktionen ins Leere laufen. raiseCallback ruft ohnehin nur
    -- self[name](self.target, ...).
    option.onClickCallback = function(_, neuerStand)
        local wert = zeile.werte[neuerStand]

        if wert == nil then
            return
        end

        if not FolgeMirMain.nurLokal[zeile.name] and not darfAendern() then
            -- Nicht erlaubt: Anzeige auf den geltenden Wert zuruecksetzen.
            FolgeMirMenu.befuellen()
            FolgeMirMain.meldung("fm_m_nurAdmin",
                "Diese Einstellung darf nur der Administrator aendern.")
            return
        end

        FolgeMirMain.setzeWert(zeile.name, wert)
    end

    if option.setDisabled ~= nil then
        option:setDisabled(false)
    end

    if box.elements[2] ~= nil and box.elements[2].setText ~= nil then
        box.elements[2]:setText(t(zeile.titel))
    end

    if option.elements ~= nil and option.elements[1] ~= nil
        and option.elements[1].setText ~= nil then
        option.elements[1]:setText(t(zeile.hilfe))
    end

    if option.setTexts ~= nil then
        option:setTexts(baueTexte(zeile))
    end

    if seite.controlsList ~= nil then
        table.insert(seite.controlsList, box)
    end

    return { aufbau = zeile, box = box, option = option }
end

--- Traegt die gespeicherten Werte in die Auswahlfelder ein.
function FolgeMirMenu.befuellen()
    setzeUeberschrift()

    for _, eintrag in ipairs(FolgeMirMenu.zeilen) do
        local option = eintrag.option

        -- setState ohne zweites Argument: mit forceEvent wuerde das Spiel
        -- den Klick-Rueckruf ausloesen (MultiTextOptionElement.lua:347) und
        -- jedes Oeffnen des Menues wuerde die Werte neu setzen und im
        -- Mehrspieler verschicken.
        if option ~= nil and option.setState ~= nil then
            option:setState(findeIndex(eintrag.aufbau))
        end

        -- Gesperrt, solange ein Mitspieler nicht angemeldet ist. Es braucht
        -- beides: setDisabled graut die Zeile aus, haelt den Klick aber nicht
        -- auf - darueber entscheidet canChangeState
        -- (MultiTextOptionElement.lua:715).
        if option ~= nil then
            local sperren = not FolgeMirMain.nurLokal[eintrag.aufbau.name]
                            and not darfAendern()

            if option.setDisabled ~= nil then
                option:setDisabled(sperren)
            end

            if option.setCanChangeState ~= nil then
                option:setCanChangeState(not sperren)
            end
        end
    end
end

--- Meldet alle neuen Elemente beim FocusManager an, damit sie sich auch mit
--- Tastatur und Controller bedienen lassen.
local function meldeFokus(elemente)
    FocusManager.setGui = Utils.appendedFunction(FocusManager.setGui, function()
        for _, eintrag in ipairs(elemente) do
            local box   = eintrag.box
            local fehlt = box ~= nil and (box.focusId == nil
                or FocusManager.currentFocusData == nil
                or FocusManager.currentFocusData.idToElementMapping == nil
                or not FocusManager.currentFocusData.idToElementMapping[box.focusId])

            if fehlt then
                FocusManager:loadElementFromCustomValues(box, nil, nil, false, false)
            end
        end
    end)
end

function FolgeMirMenu.baueZeilen()
    if FolgeMirMenu.gebaut then
        return
    end

    local seite = nil

    if g_gui ~= nil and g_gui.screenControllers ~= nil and InGameMenu ~= nil then
        seite = g_gui.screenControllers[InGameMenu]

        if seite ~= nil then
            seite = seite.pageSettings
        end
    end

    if seite == nil or seite.generalSettingsLayout == nil then
        -- Das Menue ist noch nicht fertig. FolgeMirMain fasst nach.
        return
    end

    baueUeberschrift(seite)

    for _, zeile in ipairs(FolgeMirMenu.AUFBAU) do
        if FolgeMirMain.einstellungen[zeile.name] ~= nil then
            local eintrag = baueZeile(seite, zeile)

            if eintrag ~= nil then
                table.insert(FolgeMirMenu.zeilen, eintrag)
            end
        end
    end

    if #FolgeMirMenu.zeilen == 0 then
        Logging.warning(FolgeMirMain.LOG .. "Keine Einstellungszeile konnte gebaut werden.")
        return
    end

    if seite.generalSettingsLayout.invalidateLayout ~= nil then
        seite.generalSettingsLayout:invalidateLayout()
    end

    meldeFokus(FolgeMirMenu.zeilen)

    -- Beim Oeffnen die aktuellen Werte zeigen. Im Mehrspieler koennen sie
    -- sich zwischendurch geaendert haben, weil ein anderer Administrator
    -- daran war.
    if InGameMenuSettingsFrame ~= nil and InGameMenuSettingsFrame.onFrameOpen ~= nil then
        InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(
            InGameMenuSettingsFrame.onFrameOpen,
            function()
                FolgeMirMenu.befuellen()
            end)
    end

    FolgeMirMenu.befuellen()

    FolgeMirMenu.gebaut = true

    local istServer = g_currentMission ~= nil
                      and g_currentMission.getIsServer ~= nil
                      and g_currentMission:getIsServer() == true

    Logging.info(FolgeMirMain.LOG ..
        "%d Einstellungszeilen im Menue angelegt (Server = %s, " ..
        "angemeldet = %s, darf aendern = %s).",
        #FolgeMirMenu.zeilen,
        tostring(istServer),
        tostring(g_currentMission ~= nil and g_currentMission.isMasterUser == true),
        tostring(darfAendern()))
end

--- Nachfassen, falls das Menue beim ersten Anlauf noch nicht stand.
function FolgeMirMenu.nachfassen()
    if FolgeMirMenu.gebaut or g_dedicatedServer ~= nil then
        return
    end

    if FolgeMirMenu.versuche >= FolgeMirMenu.MAX_VERSUCHE then
        return
    end

    FolgeMirMenu.versuche = FolgeMirMenu.versuche + 1

    FolgeMirMenu.baueZeilen()
end
