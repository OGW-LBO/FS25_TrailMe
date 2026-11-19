--
-- FolgeMirMain
--
-- Klammer der Mod "Folge Mir":
--   * haengt die Spezialisierung an alle fahrbaren, motorisierten Fahrzeuge
--   * registriert die Tastenbelegung (wirkt nur am Steuer)
--   * waehlt aus, welches Fahrzeug folgen soll
--   * stoesst den Fahrtakt an (nur auf dem Server)
--   * kleine Bildschirmanzeige und Konsolenbefehle
--
-- Bedienung: Man sitzt selbst in einem Fahrzeug, faehrt an das Fahrzeug heran,
-- das folgen soll, und drueckt die Taste. Einem Spieler zu Fuss folgt nichts.
--
-- Autor: OGW
--

FolgeMirMain = {}

FolgeMirMain.MOD_NAME  = g_currentModName
FolgeMirMain.MOD_DIR   = g_currentModDirectory
FolgeMirMain.SPEC_NAME = "folgeMir"
FolgeMirMain.LOG       = "[FolgeMir] "

FolgeMirMain.befehleAktiv = false

-- Alle Fahrzeuge, die gerade folgen (Schluessel = Fahrzeug)
FolgeMirMain.folger = {}

-- Gruende, aus denen das Folgen von selbst endet. Der Code wird im
-- Multiplayer mitgeschickt, damit die Meldung beim richtigen Spieler landet.
FolgeMirMain.GRUND_ZIEL_WEG = 1
FolgeMirMain.GRUND_BESETZT  = 2
FolgeMirMain.GRUND_MOTOR    = 3
FolgeMirMain.GRUND_ZU_WEIT  = 4
FolgeMirMain.GRUND_FEST     = 5
FolgeMirMain.GRUND_VERWAIST = 6

FolgeMirMain.gruende = {
    [1] = { "fm_endeZielWeg", "Vorderes Fahrzeug nicht mehr vorhanden - Folgen beendet." },
    [2] = { "fm_endeBesetzt", "Fahrzeug wurde bestiegen - Folgen beendet." },
    [3] = { "fm_endeMotor",   "Motor kann nicht laufen - Folgen beendet." },
    [4] = { "fm_endeZuWeit",  "Zu weit entfernt - Folgen beendet." },
    [5] = { "fm_endeFest",    "Fahrzeug steckt fest - Folgen beendet." },
    [6] = { "fm_endeLeer",    "Fahrer ist nicht mehr im Spiel - Folgen beendet." }
}

FolgeMirMain.einstellungen = {
    abstand           = 10,    -- m Luecke zwischen Heck und Front der Gespanne
    maxTempo          = 40,    -- km/h Obergrenze fuer den Folger
    suchradius        = 20,    -- m, in dem ein Fahrzeug angesprochen wird
    maxZielentfernung = 250,   -- m, darueber bricht das Folgen ab
    maxFolger         = 4,     -- hoechstens so viele Fahrzeuge in einer Reihe
    leerlaufSekunden  = 120,   -- so lange darf der Fahrer weg sein, bevor
                               -- die Reihe sich aufloest (nur, wenn er das
                               -- Spiel verlassen hat)
    hudAnzeigen       = 1,     -- 0 = aus, 1 = oben rechts am Spiel-HUD,
                               -- 2 = frei ueber hudX und hudY
    hudX              = 0.015,
    hudY              = 0.30
}

-- Grenzen fuer die Konsolenbefehle: Name = {min, max}
FolgeMirMain.grenzen = {
    abstand           = { 3,    60 },
    maxTempo          = { 5,    90 },
    suchradius        = { 5,    60 },
    maxZielentfernung = { 50,  800 },
    maxFolger         = { 1,    10 },
    leerlaufSekunden  = { 10, 1800 },
    hudAnzeigen       = { 0,     2 },
    hudX              = { 0,     1 },
    hudY              = { 0,     1 }
}

-- ============================================================================
-- Texte und Meldungen
-- ============================================================================

--- Holt einen l10n-Text, faellt auf den mitgegebenen Text zurueck.
function FolgeMirMain.text(schluessel, ersatz)
    if g_i18n == nil or g_i18n.getText == nil then
        return ersatz
    end

    local wert = g_i18n:getText(schluessel)

    if wert ~= nil and wert ~= schluessel and string.find(wert, "issing") == nil then
        return wert
    end

    return ersatz
end

--- Bildschirmmeldung auf diesem Rechner.
function FolgeMirMain.meldung(schluessel, ersatz)
    if g_currentMission == nil or g_currentMission.addIngameNotification == nil then
        return
    end

    if FSBaseMission == nil or FSBaseMission.INGAME_NOTIFICATION_INFO == nil then
        return
    end

    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO,
        FolgeMirMain.text(schluessel, ersatz))
end

--- Abbruchmeldung, aber nur bei dem Spieler, dessen Fahrzeug gefolgt wurde.
function FolgeMirMain.meldungGrund(ziel, grund)
    if grund == nil or grund == 0 or ziel == nil then
        return
    end

    if ziel ~= FolgeMirMain.getMeinFahrzeug() then
        return
    end

    local eintrag = FolgeMirMain.gruende[grund]

    if eintrag ~= nil then
        FolgeMirMain.meldung(eintrag[1], eintrag[2])
    end
end

-- ============================================================================
-- Spezialisierung an die Fahrzeugtypen haengen
-- ============================================================================

function FolgeMirMain.erweitereFahrzeugtypen(typeManager)
    if typeManager == nil or typeManager.typeName ~= "vehicle" then
        return
    end

    local vollerName = string.format("%s.%s",
        tostring(FolgeMirMain.MOD_NAME), FolgeMirMain.SPEC_NAME)

    local anzahl = 0

    for typeName, typeEntry in pairs(typeManager:getTypes()) do
        if typeEntry ~= nil and typeEntry.specializationsByName ~= nil then
            local passt = typeEntry.specializationsByName["drivable"]  ~= nil
                      and typeEntry.specializationsByName["motorized"] ~= nil
                      and typeEntry.specializationsByName["enterable"] ~= nil

            -- Pferde und Zuege bleiben aussen vor
            if typeName == "horse" or typeName == "locomotive" then
                passt = false
            end

            if passt and typeEntry.specializationsByName[vollerName] == nil then
                if typeManager:addSpecialization(typeName, vollerName) then
                    anzahl = anzahl + 1
                end
            end
        end
    end

    Logging.info(FolgeMirMain.LOG .. "Spezialisierung an %d Fahrzeugtypen angehaengt.", anzahl)
end

if TypeManager ~= nil and TypeManager.validateTypes ~= nil then
    TypeManager.validateTypes = Utils.prependedFunction(TypeManager.validateTypes,
        FolgeMirMain.erweitereFahrzeugtypen)
else
    Logging.error(FolgeMirMain.LOG .. "TypeManager.validateTypes nicht gefunden - Mod bleibt wirkungslos.")
end

-- ============================================================================
-- Buchfuehrung ueber die folgenden Fahrzeuge
-- ============================================================================

function FolgeMirMain.merkeFolger(fahrzeug, folgt)
    if fahrzeug == nil then
        return
    end

    if folgt then
        FolgeMirMain.folger[fahrzeug] = true
    else
        FolgeMirMain.folger[fahrzeug] = nil
    end
end

--- Liefert alle Fahrzeuge, die dem angegebenen Fahrzeug folgen.
function FolgeMirMain.getFolgerVon(ziel)
    local liste = {}

    if ziel == nil then
        return liste
    end

    for fahrzeug, _ in pairs(FolgeMirMain.folger) do
        if fahrzeug ~= nil and fahrzeug.fmGetZiel ~= nil and fahrzeug:fmFolgtGerade() then
            if fahrzeug:fmGetZiel() == ziel then
                table.insert(liste, fahrzeug)
            end
        end
    end

    return liste
end

-- ============================================================================
-- Eigenes Fahrzeug und Fahrzeugauswahl
-- ============================================================================

--- Ist der Spieler mit dieser Kennung noch im Spiel? Ohne Kennung oder ohne
--- Benutzerverwaltung wird mit ja geantwortet - dann loest sich nie etwas von
--- selbst auf, und das ist die sichere Seite.
function FolgeMirMain.istNochImSpiel(kennung)
    if kennung == nil or kennung == 0 then
        return true
    end

    if g_currentMission == nil or g_currentMission.userManager == nil then
        return true
    end

    if g_currentMission.userManager.getUserByUserId == nil then
        return true
    end

    return g_currentMission.userManager:getUserByUserId(kennung) ~= nil
end

--- Darf dieser Spieler auch fremde Reihen aufloesen? Auf dem Server ja, im
--- Spiel nur als Administrator.
function FolgeMirMain.istAdmin()
    if g_currentMission == nil then
        return false
    end

    if g_currentMission.getIsServer ~= nil and g_currentMission:getIsServer() then
        return true
    end

    return g_currentMission.isMasterUser == true
end

--- Wie meldung, nur mit fertigem Text - fuer Meldungen mit Spielernamen.
function FolgeMirMain.meldungText(text)
    if g_currentMission == nil or g_currentMission.addIngameNotification == nil then
        return
    end

    if FSBaseMission == nil or FSBaseMission.INGAME_NOTIFICATION_INFO == nil then
        return
    end

    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, text)
end

--- Das vorderste Fahrzeug einer Reihe: dorthin, wo niemand mehr folgt. Das
--- ist das Fahrzeug, in dem der Spieler sitzt, der die Reihe anfuehrt.
function FolgeMirMain.getWurzel(fahrzeug)
    local aktuell = fahrzeug
    local tiefe   = 0

    while aktuell ~= nil and tiefe < 20 do
        if aktuell.fmFolgtGerade == nil or not aktuell:fmFolgtGerade() then
            return aktuell
        end

        local naechstes = aktuell:fmGetZiel()

        if naechstes == nil then
            return aktuell
        end

        aktuell = naechstes
        tiefe   = tiefe + 1
    end

    return aktuell
end

--- Die ganze Kette hinter einem Fahrzeug, von vorne nach hinten. Der erste
--- Eintrag folgt dem Fahrzeug selbst, der zweite dem ersten und so weiter.
function FolgeMirMain.getKette(ziel)
    local kette   = {}
    local aktuell = ziel
    local tiefe   = 0

    while aktuell ~= nil and tiefe < 20 do
        local folger = FolgeMirMain.getFolgerVon(aktuell)

        if #folger == 0 then
            break
        end

        aktuell = folger[1]
        table.insert(kette, aktuell)
        tiefe = tiefe + 1
    end

    return kette
end

--- Haengt das Fahrzeug ueber beliebig viele Glieder an diesem Ziel?
function FolgeMirMain.istInKette(fahrzeug, ziel)
    local aktuell = fahrzeug
    local tiefe   = 0

    while aktuell ~= nil and tiefe < 20 do
        if aktuell.fmGetZiel == nil or aktuell.fmFolgtGerade == nil then
            return false
        end

        if not aktuell:fmFolgtGerade() then
            return false
        end

        aktuell = aktuell:fmGetZiel()

        if aktuell == ziel then
            return true
        end

        tiefe = tiefe + 1
    end

    return false
end

--- Faellt ein Glied aus der Mitte heraus, bekommen die Fahrzeuge dahinter
--- dessen Ziel. Ohne das wuerden sie einem stehenden Fahrzeug folgen und die
--- Kette bliebe zerrissen.
function FolgeMirMain.ketteSchliessen(fahrzeug, neuesZiel)
    if fahrzeug == nil or neuesZiel == nil then
        return
    end

    for _, folger in ipairs(FolgeMirMain.getFolgerVon(fahrzeug)) do
        if folger ~= neuesZiel and folger.fmStartFolgen ~= nil then
            folger:fmStartFolgen(neuesZiel, false)
        end
    end
end

--- Das Fahrzeug, das der Spieler gerade selbst steuert - oder nil, wenn er zu
--- Fuss unterwegs ist. Auf einem Dedicated Server immer nil.
function FolgeMirMain.getMeinFahrzeug()
    if g_localPlayer == nil or g_localPlayer.getCurrentVehicle == nil then
        return nil
    end

    local fahrzeug = g_localPlayer:getCurrentVehicle()

    if fahrzeug == nil then
        return nil
    end

    -- Sitzt man in einem Anbaugeraet oder Aufbau, zaehlt das Zugfahrzeug
    if fahrzeug.rootVehicle ~= nil then
        fahrzeug = fahrzeug.rootVehicle
    end

    return fahrzeug
end

local function getPosition(objekt)
    if objekt == nil then
        return nil
    end

    local knoten = objekt.rootNode

    if knoten == nil and objekt.components ~= nil and objekt.components[1] ~= nil then
        knoten = objekt.components[1].node
    end

    if knoten == nil or not entityExists(knoten) then
        return nil
    end

    return getWorldTranslation(knoten)
end

--- Kann dieses Fahrzeug als Folger arbeiten?
local function istGeeignet(fahrzeug, meinFahrzeug)
    if fahrzeug == nil or fahrzeug == meinFahrzeug then
        return false
    end

    -- Nur Fahrzeuge mit der Spezialisierung, also fahrbar und motorisiert
    if fahrzeug.fmStartFolgen == nil or fahrzeug.isDeleted == true then
        return false
    end

    -- Es darf niemand darin sitzen
    if fahrzeug.spec_enterable ~= nil and fahrzeug.spec_enterable.isControlled == true then
        return false
    end

    -- Zugriffsrecht der eigenen Farm
    if g_currentMission ~= nil and g_currentMission.accessHandler ~= nil
        and g_currentMission.accessHandler.canFarmAccess ~= nil and g_localPlayer ~= nil then

        if not g_currentMission.accessHandler:canFarmAccess(g_localPlayer.farmId, fahrzeug, false) then
            return false
        end
    end

    return true
end

--- Verhindert Ringe (A folgt B, B folgt A).
local function bildetRing(fahrzeug, ziel)
    local aktuell = ziel
    local tiefe   = 0

    while aktuell ~= nil and tiefe < 20 do
        if aktuell == fahrzeug then
            return true
        end

        if aktuell.fmGetZiel == nil or aktuell.fmFolgtGerade == nil then
            return false
        end

        if not aktuell:fmFolgtGerade() then
            return false
        end

        aktuell = aktuell:fmGetZiel()
        tiefe   = tiefe + 1
    end

    return false
end

--- Sucht das naechstgelegene passende Fahrzeug um das eigene herum.
--- Gemessen wird gegen jedes Einzelfahrzeug, also auch gegen Anhaenger und
--- Anbaugeraete - man kann sich damit neben den Anhaenger stellen und trifft
--- trotzdem das Zugfahrzeug, das dann folgt.
--- nurFreie = true  -> nur Fahrzeuge, die noch nicht folgen
--- nurFreie = false -> nur Fahrzeuge, die mir bereits folgen
local function findeFahrzeug(meinFahrzeug, radius, nurFreie)
    if g_currentMission == nil or g_currentMission.vehicleSystem == nil then
        return nil
    end

    local mx, _, mz = getPosition(meinFahrzeug)

    if mx == nil then
        return nil
    end

    local bestes, besteEntfernung = nil, radius

    for _, teil in pairs(g_currentMission.vehicleSystem.vehicles) do
        local tx, _, tz = getPosition(teil)

        if tx ~= nil then
            local dx, dz = tx - mx, tz - mz
            local entfernung = math.sqrt(dx * dx + dz * dz)

            if entfernung < besteEntfernung then
                -- Vom getroffenen Teil zum Zugfahrzeug des Gespanns
                local kandidat = teil

                if kandidat.rootVehicle ~= nil then
                    kandidat = kandidat.rootVehicle
                end

                if istGeeignet(kandidat, meinFahrzeug) then
                    local folgt = kandidat.fmFolgtGerade ~= nil and kandidat:fmFolgtGerade()
                    local passt = false

                    if nurFreie then
                        passt = not folgt and not bildetRing(kandidat, meinFahrzeug)
                    else
                        -- Auch Fahrzeuge weiter hinten in der Kette, nicht
                        -- nur die, die unmittelbar mir folgen
                        passt = folgt and FolgeMirMain.istInKette(kandidat, meinFahrzeug)
                    end

                    if passt then
                        bestes          = kandidat
                        besteEntfernung = entfernung
                    end
                end
            end
        end
    end

    return bestes
end

-- ============================================================================
-- Tastendruck
-- ============================================================================

function FolgeMirMain.aufUmschalten()
    local meinFahrzeug = FolgeMirMain.getMeinFahrzeug()

    if meinFahrzeug == nil then
        FolgeMirMain.meldung("fm_nurImFahrzeug",
            "Dazu musst du selbst in einem Fahrzeug sitzen.")
        return
    end

    local radius = FolgeMirMain.einstellungen.suchradius

    -- Zuerst ein noch freies Fahrzeug anwerben
    local fahrzeug = findeFahrzeug(meinFahrzeug, radius, true)

    if fahrzeug ~= nil then
        -- Hinten anstellen: Das neue Fahrzeug folgt dem letzten Glied, nicht
        -- mir. Sonst wollten alle dieselbe Stelle hinter mir haben und wuerden
        -- sich gegenseitig schieben.
        local kette    = FolgeMirMain.getKette(meinFahrzeug)
        local vorNeuem = meinFahrzeug

        if #kette >= FolgeMirMain.einstellungen.maxFolger then
            FolgeMirMain.meldung("fm_zuViele",
                "Mehr Fahrzeuge nimmt die Reihe nicht auf.")
            return
        end

        if #kette > 0 then
            vorNeuem = kette[#kette]
        end

        fahrzeug:fmStartFolgen(vorNeuem, false)

        if #kette > 0 then
            FolgeMirMain.meldung("fm_startKette", "Fahrzeug haengt sich hinten an.")
        else
            FolgeMirMain.meldung("fm_start", "Fahrzeug folgt dir jetzt.")
        end

        return
    end

    -- Kein freies da: den naechsten eigenen Folger anhalten
    fahrzeug = findeFahrzeug(meinFahrzeug, radius, false)

    if fahrzeug ~= nil then
        fahrzeug:fmStoppFolgen(false, 0)
        FolgeMirMain.meldung("fm_stopp", "Fahrzeug folgt dir nicht mehr.")
        return
    end

    FolgeMirMain.meldung("fm_keins", "Kein passendes Fahrzeug in der Naehe.")
end

--- Sucht das naechste besetzte Fahrzeug in der Umgebung - also eines, in dem
--- ein Mitspieler sitzt. Dient der Uebergabe des eigenen Konvois.
local function findeMitspieler(meinFahrzeug, radius)
    if g_currentMission == nil or g_currentMission.vehicleSystem == nil then
        return nil
    end

    local mx, _, mz = getPosition(meinFahrzeug)

    if mx == nil then
        return nil
    end

    local bestes, besteEntfernung = nil, radius

    for _, teil in pairs(g_currentMission.vehicleSystem.vehicles) do
        local tx, _, tz = getPosition(teil)

        if tx ~= nil then
            local dx, dz = tx - mx, tz - mz
            local entfernung = math.sqrt(dx * dx + dz * dz)

            if entfernung < besteEntfernung then
                local kandidat = teil

                if kandidat.rootVehicle ~= nil then
                    kandidat = kandidat.rootVehicle
                end

                local besetzt = kandidat.spec_enterable ~= nil
                                and kandidat.spec_enterable.isControlled == true

                -- Nur ein fremdes, besetztes Fahrzeug, das nicht selbst in
                -- meiner Reihe haengt - sonst liefe die Kette im Kreis.
                if besetzt and kandidat ~= meinFahrzeug
                    and not FolgeMirMain.istInKette(kandidat, meinFahrzeug) then
                    bestes          = kandidat
                    besteEntfernung = entfernung
                end
            end
        end
    end

    return bestes
end

--- Gibt die eigene Reihe an den Mitspieler ab, neben dem man steht. Es wird
--- nur das erste Glied umgehaengt, der Rest haengt ja daran.
function FolgeMirMain.aufUebergabe()
    local meinFahrzeug = FolgeMirMain.getMeinFahrzeug()

    if meinFahrzeug == nil then
        FolgeMirMain.meldung("fm_nurImFahrzeug",
            "Dazu musst du selbst in einem Fahrzeug sitzen.")
        return
    end

    local kette = FolgeMirMain.getKette(meinFahrzeug)

    if #kette == 0 then
        FolgeMirMain.meldung("fm_keineFolger", "Dir folgt gerade kein Fahrzeug.")
        return
    end

    local ziel = findeMitspieler(meinFahrzeug, FolgeMirMain.einstellungen.suchradius)

    if ziel == nil then
        FolgeMirMain.meldung("fm_keinMitspieler",
            "Kein Mitspieler in der Naehe, dem du die Reihe geben koenntest.")
        return
    end

    kette[1]:fmStartFolgen(ziel, false)

    local name = ""

    if ziel.getControllerName ~= nil then
        name = ziel:getControllerName() or ""
    end

    if name ~= "" then
        FolgeMirMain.meldungText(
            FolgeMirMain.text("fm_uebergeben", "Reihe uebergeben an:") .. " " .. name)
    else
        FolgeMirMain.meldung("fm_uebergebenOhne", "Reihe uebergeben.")
    end
end

function FolgeMirMain.aufAlleStoppen()
    local meinFahrzeug = FolgeMirMain.getMeinFahrzeug()

    if meinFahrzeug == nil then
        FolgeMirMain.meldung("fm_nurImFahrzeug",
            "Dazu musst du selbst in einem Fahrzeug sitzen.")
        return
    end

    local liste = FolgeMirMain.getKette(meinFahrzeug)

    -- Von hinten nach vorne, dann muss kein Glied mehr umgehaengt werden
    for i = #liste, 1, -1 do
        liste[i]:fmStoppFolgen(false, 0)
    end

    if #liste > 0 then
        FolgeMirMain.meldung("fm_alleStopp", "Alle Fahrzeuge angehalten.")
    else
        FolgeMirMain.meldung("fm_keineFolger", "Dir folgt gerade kein Fahrzeug.")
    end
end

-- ============================================================================
-- Einstellungen (modSettings)
-- ============================================================================

function FolgeMirMain.getDateiname()
    if g_currentModSettingsDirectory == nil then
        return nil
    end

    if createFolder ~= nil then
        createFolder(g_currentModSettingsDirectory)
    end

    return g_currentModSettingsDirectory .. "settings.xml"
end

function FolgeMirMain.setzeWert(name, wert, ohneSpeichern)
    if FolgeMirMain.einstellungen[name] == nil or wert == nil then
        return false
    end

    local grenze = FolgeMirMain.grenzen[name]

    if grenze ~= nil then
        wert = math.clamp(wert, grenze[1], grenze[2])
    end

    FolgeMirMain.einstellungen[name] = wert

    if not ohneSpeichern then
        FolgeMirMain.speichereEinstellungen()
    end

    return true
end

function FolgeMirMain.ladeEinstellungen()
    local datei = FolgeMirMain.getDateiname()

    if datei == nil or XMLFile == nil or XMLFile.loadIfExists == nil then
        return
    end

    local xml = XMLFile.loadIfExists("FolgeMirSettings", datei)

    if xml == nil then
        return
    end

    for name, _ in pairs(FolgeMirMain.einstellungen) do
        local gelesen = xml:getFloat("folgeMir." .. name)

        if gelesen ~= nil then
            FolgeMirMain.setzeWert(name, gelesen, true)
        end
    end

    xml:delete()

    Logging.info(FolgeMirMain.LOG .. "Einstellungen geladen: %s", tostring(datei))
end

function FolgeMirMain.speichereEinstellungen()
    local datei = FolgeMirMain.getDateiname()

    if datei == nil or XMLFile == nil or XMLFile.create == nil then
        return
    end

    local xml = XMLFile.create("FolgeMirSettings", datei, "folgeMir")

    if xml == nil then
        return
    end

    for name, wert in pairs(FolgeMirMain.einstellungen) do
        xml:setFloat("folgeMir." .. name, wert)
    end

    xml:save()
    xml:delete()
end

-- ============================================================================
-- Konsolenbefehle
--
-- addConsoleCommand ruft die Funktion als ziel[name](ziel, ...) auf - der
-- erste Parameter ist deshalb immer das Zielobjekt und wird verworfen.
-- ============================================================================

--- Lesbarer Name eines Fahrzeugs fuer die Diagnoseausgabe.
local function fahrzeugName(fahrzeug)
    if fahrzeug == nil then
        return "-"
    end

    if fahrzeug.getFullName ~= nil then
        local name = fahrzeug:getFullName()

        if name ~= nil then
            return name
        end
    end

    if fahrzeug.getName ~= nil then
        local name = fahrzeug:getName()

        if name ~= nil then
            return name
        end
    end

    return "unbekannt"
end

function FolgeMirMain.befehlInfo(_)
    local zeilen = { FolgeMirMain.LOG .. "Einstellungen:" }
    local namen  = {}

    for name, _ in pairs(FolgeMirMain.einstellungen) do
        table.insert(namen, name)
    end

    table.sort(namen)

    for _, name in ipairs(namen) do
        table.insert(zeilen, string.format("  %-18s = %s", name,
            tostring(FolgeMirMain.einstellungen[name])))
    end

    -- Diagnose: damit laesst sich "Taste kommt nicht an" von "Mod findet
    -- nichts" unterscheiden, ohne im Dunkeln zu raten.
    table.insert(zeilen, FolgeMirMain.LOG .. "Zustand:")

    local tasteDa = InputAction ~= nil and InputAction.FOLGEMIR_TOGGLE ~= nil
    table.insert(zeilen, string.format("  Aktion FOLGEMIR_TOGGLE bekannt = %s", tostring(tasteDa)))

    local meinFahrzeug = FolgeMirMain.getMeinFahrzeug()
    table.insert(zeilen, string.format("  eigenes Fahrzeug   = %s", fahrzeugName(meinFahrzeug)))

    if meinFahrzeug ~= nil then
        local kandidat = findeFahrzeug(meinFahrzeug, FolgeMirMain.einstellungen.suchradius, true)
        table.insert(zeilen, string.format("  freier Kandidat    = %s", fahrzeugName(kandidat)))
    end

    local anzahl = 0

    for fahrzeug, _ in pairs(FolgeMirMain.folger) do
        if fahrzeug ~= nil and fahrzeug.fmFolgtGerade ~= nil and fahrzeug:fmFolgtGerade() then
            anzahl = anzahl + 1
        end
    end

    table.insert(zeilen, string.format("  folgende Fahrzeuge = %d", anzahl))

    return table.concat(zeilen, "\n")
end

--- Zeigt die Messwerte des zuletzt gefahrenen Folgers. Damit laesst sich ein
--- falsches Fahrverhalten an Zahlen festmachen statt am Gefuehl.
function FolgeMirMain.befehlDebug(_)
    local zeilen = {}

    for fahrzeug, _ in pairs(FolgeMirMain.folger) do
        if fahrzeug ~= nil and fahrzeug.fmFolgtGerade ~= nil and fahrzeug:fmFolgtGerade() then
            local daten = fahrzeug:fmGetDaten()
            local w     = daten.werte or {}

            table.insert(zeilen, string.format("%s%s:", FolgeMirMain.LOG, fahrzeugName(fahrzeug)))
            table.insert(zeilen, string.format(
                "  Ziel lokal tX=%.2f tZ=%.2f | Spur %d Punkte",
                w.tX or 0, w.tZ or 0, w.spur or 0))
            table.insert(zeilen, string.format(
                "  Rest %.1f m / Soll %.1f m | Tempo %.1f km/h | faehrt=%s",
                w.rest or 0, w.soll or 0, w.tempo or 0, tostring(w.darfFahren)))
            table.insert(zeilen, string.format(
                "  Laengen: vorne %.1f m, eigenes %.1f m",
                daten.zielHeck or 0, daten.eigenFront or 0))
            table.insert(zeilen, string.format(
                "  Lenkung: rotatedTime=%.3f (min %.3f / max %.3f), Tempo %.4f",
                w.rotatedTime or 0, w.minRotTime or 0, w.maxRotTime or 0,
                w.steeringSpeed or 0))
            table.insert(zeilen, string.format(
                "  isActive=%s forceIsActive=%s",
                tostring(w.isActive), tostring(fahrzeug.forceIsActive)))
        end
    end

    if #zeilen == 0 then
        return FolgeMirMain.LOG .. "Gerade folgt kein Fahrzeug."
    end

    return table.concat(zeilen, "\n")
end

--- Loest dasselbe aus wie der Tastendruck. Damit laesst sich pruefen, ob die
--- Funktion arbeitet, wenn die Taste nichts tut.
function FolgeMirMain.befehlFolge(_)
    FolgeMirMain.aufUmschalten()

    local meinFahrzeug = FolgeMirMain.getMeinFahrzeug()

    if meinFahrzeug == nil then
        return FolgeMirMain.LOG .. "Du sitzt in keinem Fahrzeug."
    end

    return string.format("%sausgeloest von: %s", FolgeMirMain.LOG, fahrzeugName(meinFahrzeug))
end

function FolgeMirMain.befehlSet(_, name, wert)
    if name == nil or wert == nil then
        return FolgeMirMain.LOG .. "Aufruf: fmSet <name> <wert> - Namen zeigt fmInfo."
    end

    local zahl = tonumber(wert)

    if zahl == nil then
        return FolgeMirMain.LOG .. "Der Wert muss eine Zahl sein."
    end

    if not FolgeMirMain.setzeWert(name, zahl) then
        return FolgeMirMain.LOG .. "Unbekannte Einstellung: " .. tostring(name)
    end

    return string.format("%s%s = %s", FolgeMirMain.LOG, name,
        tostring(FolgeMirMain.einstellungen[name]))
end

function FolgeMirMain.befehlStopp(_)
    local liste = {}

    if FolgeMirMain.istAdmin() then
        -- Server oder Administrator: alles, auch die Reihen anderer Hoefe
        for fahrzeug, _ in pairs(FolgeMirMain.folger) do
            table.insert(liste, fahrzeug)
        end
    else
        -- Sonst nur die eigene Reihe, von hinten nach vorne
        local kette = FolgeMirMain.getKette(FolgeMirMain.getMeinFahrzeug())

        for i = #kette, 1, -1 do
            table.insert(liste, kette[i])
        end
    end

    for _, fahrzeug in ipairs(liste) do
        if fahrzeug.fmStoppFolgen ~= nil then
            fahrzeug:fmStoppFolgen(false, 0)
        end
    end

    return string.format("%s%d Fahrzeuge angehalten.", FolgeMirMain.LOG, #liste)
end

function FolgeMirMain.registriereBefehle()
    if FolgeMirMain.befehleAktiv or addConsoleCommand == nil then
        return
    end

    addConsoleCommand("fmInfo",  "Zeigt Einstellungen und Zustand von Folge Mir", "befehlInfo", FolgeMirMain)
    addConsoleCommand("fmSet",   "Setzt eine Einstellung: fmSet <name> <wert>", "befehlSet", FolgeMirMain)
    addConsoleCommand("fmFolge", "Loest dasselbe aus wie die Taste", "befehlFolge", FolgeMirMain)
    addConsoleCommand("fmDebug", "Zeigt die Messwerte der folgenden Fahrzeuge", "befehlDebug", FolgeMirMain)
    addConsoleCommand("fmStopp", "Haelt alle folgenden Fahrzeuge an", "befehlStopp", FolgeMirMain)

    FolgeMirMain.befehleAktiv = true
end

-- ============================================================================
-- Mod-Lebenszyklus
-- ============================================================================

function FolgeMirMain:loadMap(name)
    FolgeMirMain.ladeEinstellungen()
    FolgeMirMain.registriereBefehle()

    -- Gefahren wird ueber AIVehicleUtil. Fehlt die Funktion nach einem
    -- Spielpatch, faehrt nichts mehr - das steht dann klar in der log.txt.
    if AIVehicleUtil == nil or AIVehicleUtil.driveToPoint == nil then
        Logging.error(FolgeMirMain.LOG ..
            "AIVehicleUtil.driveToPoint nicht gefunden - Fahrzeuge koennen nicht gesteuert werden.")
    end

    Logging.info(FolgeMirMain.LOG .. "geladen.")
end

function FolgeMirMain:deleteMap()
    FolgeMirMain.folger = {}

    -- Die Anzeige legt ihre Overlays erst beim ersten Zeichnen an. Das
    -- Aufraeumen haengt deshalb weiter unten an der Tabelle.
    if FolgeMirMain.anzeigeAufraeumen ~= nil then
        FolgeMirMain.anzeigeAufraeumen()
    end
end

function FolgeMirMain:mouseEvent(posX, posY, isDown, isUp, button)
end

function FolgeMirMain:keyEvent(unicode, sym, modifier, isDown)
end

--- Der Fahrtakt. Laeuft nur auf dem Server. Normalerweise faehrt jedes
--- Fahrzeug in seinem eigenen onUpdate; hier wird nur nachgeholt, wenn das
--- ausbleibt, weil ein abgestelltes Fahrzeug nicht zwangslaeufig aktiv ist.
local function fahrtakt(dt)
    if g_currentMission == nil or g_currentMission.getIsServer == nil then
        return
    end

    if not g_currentMission:getIsServer() then
        return
    end

    local liste = {}

    for fahrzeug, _ in pairs(FolgeMirMain.folger) do
        table.insert(liste, fahrzeug)
    end

    local durchlauf = g_updateLoopIndex

    for _, fahrzeug in ipairs(liste) do
        if fahrzeug ~= nil and fahrzeug.fmFolgtGerade ~= nil and fahrzeug:fmFolgtGerade() then
            -- Die Abfrage verhindert zugleich, dass ein Fahrzeug im selben
            -- Durchlauf zweimal einen Fahrbefehl bekommt.
            local letzter = fahrzeug.fmDaten.letzterTakt

            if durchlauf == nil or letzter == nil or (durchlauf - letzter) > 2 then
                fahrzeug:fmFahrTakt(dt)
            end
        else
            FolgeMirMain.folger[fahrzeug] = nil
        end
    end
end

function FolgeMirMain:update(dt)
    if g_currentMission == nil then
        return
    end

    fahrtakt(dt)
end

-- ============================================================================
-- Bildschirmanzeige
--
-- Die Zeile haengt unter der Info-Leiste des Spiels und sieht aus wie dessen
-- eigene Meldungen oben rechts. Masse und Lage kommen aus der Meldungsanzeige
-- selbst - so macht die Zeile jede HUD-Groesse und jedes Seitenverhaeltnis
-- mit, ohne dass hier Pixel nachgerechnet werden muessen.
-- ============================================================================

local meldungsanzeige = nil
local anzeigeGesucht  = false
local balken          = nil

--- Die Meldungsanzeige des Spiels, oben rechts unter der Info-Leiste.
local function getMeldungsanzeige()
    if meldungsanzeige ~= nil then
        return meldungsanzeige
    end

    if g_currentMission == nil or g_currentMission.hud == nil then
        return nil
    end

    local hud = g_currentMission.hud
    local sn  = hud.sideNotification

    if type(sn) == "table" and type(sn.notificationQueue) == "table" then
        meldungsanzeige = sn
        return sn
    end

    -- Der Feldname steht in keiner Dokumentation. Sollte er einmal anders
    -- heissen, lieber einmalig ueber den Inhalt suchen als aufgeben.
    if not anzeigeGesucht then
        anzeigeGesucht = true

        for _, wert in pairs(hud) do
            if type(wert) == "table" and type(wert.notificationQueue) == "table"
                    and type(wert.bgRight) == "table" then
                meldungsanzeige = wert
                break
            end
        end
    end

    return meldungsanzeige
end

--- Der Hintergrundbalken: zwei runde Kappen und ein dehnbares Mittelstueck,
--- dieselben Teile, aus denen das Spiel seine Meldungen zusammensetzt.
local function getBalken()
    if balken ~= nil then
        return balken
    end

    if g_overlayManager == nil or g_overlayManager.createOverlay == nil then
        return nil
    end

    -- Ist der Name nicht bekannt, kommt nil zurueck und es steht eine
    -- Warnung in der log.txt - dann zeichnet die Anzeige eben ohne Balken.
    local function hole(name)
        local teil = g_overlayManager:createOverlay(name, 0, 0, 0, 0)

        if type(teil) == "table" and teil.setPosition ~= nil then
            return teil
        end

        return nil
    end

    local links  = hole("gui.rectangle_left")
    local mitte  = hole("gui.rectangle_center")
    local rechts = hole("gui.rectangle_right")

    if links == nil or mitte == nil or rechts == nil then
        return nil
    end

    local r, g, b, a = 0, 0, 0, 0.75

    if HUD ~= nil and HUD.COLOR ~= nil and HUD.COLOR.BACKGROUND ~= nil then
        r, g, b, a = unpack(HUD.COLOR.BACKGROUND)
    end

    links:setColor(r, g, b, a)
    mitte:setColor(r, g, b, a)
    rechts:setColor(r, g, b, a)

    balken = { links = links, mitte = mitte, rechts = rechts }

    return balken
end

--- Was in der Zeile steht. Folgt nur ein Fahrzeug, steht sein Name dort -
--- eine blanke 1 sagt nicht, welches Gespann gerade unterwegs ist.
local function anzeigeText(liste)
    if #liste == 1 and liste[1] ~= nil and liste[1].getName ~= nil then
        local name = liste[1]:getName()

        if type(name) == "string" and name ~= "" then
            return string.format("%s %s",
                FolgeMirMain.text("fm_hudEiner", "Folgt dir:"), name)
        end
    end

    return string.format("%s %d", FolgeMirMain.text("fm_hud", "Folgen dir:"), #liste)
end

--- Zeile unter der Info-Leiste. Gibt false zurueck, wenn sich die Anzeige des
--- Spiels nicht fassen laesst - dann wird frei gezeichnet.
local function zeichneAmHud(text)
    local sn = getMeldungsanzeige()

    if sn == nil or sn.getPosition == nil or type(sn.bgRight) ~= "table" then
        return false
    end

    local rechtsX, obenY = sn:getPosition()

    if type(rechtsX) ~= "number" or type(obenY) ~= "number" then
        return false
    end

    local hoehe   = sn.bgRight.height
    local kappe   = sn.bgRight.width
    local groesse = sn.textSize

    if type(hoehe) ~= "number" or hoehe <= 0 or type(kappe) ~= "number"
            or type(groesse) ~= "number" or groesse <= 0 then
        return false
    end

    local luft  = sn.notificationOffsetY or 0
    local textY = sn.textOffsetY or 0

    -- So viele Zeilen tiefer, wie das Spiel gerade selbst belegt. Sonst liegt
    -- eine Meldung auf der Anzeige, und zwar ausgerechnet in dem Moment, in
    -- dem das Folgen beginnt und "Fahrzeug folgt dir jetzt" erscheint.
    local hoechstens = 3

    if SideNotification ~= nil
            and type(SideNotification.MAX_NOTIFICATIONS) == "number" then
        hoechstens = SideNotification.MAX_NOTIFICATIONS
    end

    local belegt = math.min(#sn.notificationQueue, hoechstens)

    if sn.isSaving == true then
        belegt = belegt + 1
    end

    local y = obenY - (belegt + 1) * (hoehe + luft)

    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_RIGHT)

    local breite = getTextWidth(groesse, text)
    local teile  = getBalken()

    if teile ~= nil then
        teile.rechts:setDimension(kappe, hoehe)
        teile.rechts:setPosition(rechtsX - kappe, y)
        teile.rechts:render()

        teile.mitte:setDimension(breite, hoehe)
        teile.mitte:setPosition(rechtsX - kappe - breite, y)
        teile.mitte:render()

        teile.links:setDimension(kappe, hoehe)
        teile.links:setPosition(rechtsX - kappe - breite - kappe, y)
        teile.links:render()
    else
        -- Ohne Balken braucht die Schrift einen Schatten, sonst verschwindet
        -- sie ueber hellem Himmel.
        setTextColor(0, 0, 0, 0.75)
        renderText(rechtsX - kappe + 0.0015, y + textY - 0.0015, groesse, text)
    end

    setTextColor(0.26, 0.90, 0.36, 1)
    renderText(rechtsX - kappe, y + textY, groesse, text)

    return true
end

--- Die alte freie Position, ueber hudX und hudY einstellbar.
local function zeichneFrei(text)
    local e = FolgeMirMain.einstellungen

    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_LEFT)

    setTextColor(0, 0, 0, 0.75)
    renderText(e.hudX + 0.0015, e.hudY - 0.0015, 0.016, text)

    setTextColor(0.15, 0.85, 0.25, 1)
    renderText(e.hudX, e.hudY, 0.016, text)
end

--- Beim Verlassen des Spielstands aufraeumen, damit beim naechsten Laden
--- nicht auf Overlays von vorhin gezeigt wird.
function FolgeMirMain.anzeigeAufraeumen()
    if balken ~= nil then
        for _, teil in pairs(balken) do
            if teil.delete ~= nil then
                teil:delete()
            end
        end
    end

    balken          = nil
    meldungsanzeige = nil
    anzeigeGesucht  = false
end

function FolgeMirMain:draw()
    -- Der Wert kommt aus der settings.xml und ist dort eine Kommazahl
    local modus = math.floor((FolgeMirMain.einstellungen.hudAnzeigen or 0) + 0.5)

    if modus ~= 1 and modus ~= 2 then
        return
    end

    if g_currentMission == nil then
        return
    end

    -- Nicht ins Menue hineinzeichnen
    if g_gui ~= nil and g_gui.currentGui ~= nil then
        return
    end

    -- Und nicht, wenn das Spiel-HUD ausgeblendet ist
    if g_currentMission.hud ~= nil and g_currentMission.hud.isVisible == false then
        return
    end

    local liste = FolgeMirMain.getKette(FolgeMirMain.getMeinFahrzeug())

    if #liste == 0 then
        return
    end

    local text = anzeigeText(liste)

    if modus == 2 or not zeichneAmHud(text) then
        zeichneFrei(text)
    end

    setTextColor(1, 1, 1, 1)
    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)
end

addModEventListener(FolgeMirMain)
