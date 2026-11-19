--
-- FolgeMirVehicle
--
-- Fahrzeug-Spezialisierung fuer "Folge Mir": Ein Fahrzeug faehrt dem Fahrzeug
-- hinterher, das der Spieler selbst steuert.
--
-- Grundprinzip: Es wird kein Luftlinien-Kurs gefahren, sondern eine Spur aus
-- Wegpunkten, die das vordere Fahrzeug hinter sich herzieht. Der Folger faehrt
-- also exakt dieselbe Linie nach und schneidet keine Kurven durch Zaeune oder
-- Gebaeude.
--
-- Angehaengt bleibt angehaengt: Die Mod ruft bewusst kein prepareForAIDriving
-- auf und fasst weder Anbaugeraete noch Anhaenger an. Das Gespann faehrt so
-- mit, wie der Spieler es vorbereitet hat. Fuer den Abstand wird die
-- tatsaechliche Laenge beider Gespanne mitgerechnet, damit zwischen Heck und
-- Front wirklich der eingestellte Abstand bleibt.
--
-- Gelenkt wird ueber AIVehicleUtil.driveToPoint - dieselbe Funktion, die das
-- Spiel in AIDrivable und AIFieldWorker benutzt. Sie rechnet den Lenkeinschlag
-- aus dem Kurvenradius und nimmt in engen Kurven von selbst Gas weg.
--
-- Gefahren wird ausschliesslich auf dem Server (im Einzelspieler ist der
-- Spieler selbst der Server). Clients halten den Zustand nur zur Anzeige.
--
-- Autor: OGW
--

FolgeMirVehicle = {}

FolgeMirVehicle.MOD_NAME  = g_currentModName
FolgeMirVehicle.SPEC_NAME = "folgeMir"
FolgeMirVehicle.LOG       = "[FolgeMir] "

-- Spur- und Regelparameter
FolgeMirVehicle.SPUR_ABSTAND = 2.5      -- m, Abstand zweier Wegpunkte
FolgeMirVehicle.SPUR_MAX     = 200      -- Wegpunkte maximal
FolgeMirVehicle.PUNKT_RADIUS = 3.0      -- m, ab hier gilt ein Wegpunkt als erreicht
FolgeMirVehicle.LOOKAHEAD    = 7.0      -- m, Vorausschau auf der Spur
FolgeMirVehicle.FEST_ZEIT    = 12000    -- ms Gas ohne Bewegung, dann abbrechen
FolgeMirVehicle.ANFAHR_TEMPO = 3        -- km/h Mindest-Fahrtempo
FolgeMirVehicle.LOSFAHR_PLUS = 3        -- m, die das Ziel sich entfernen muss, bevor
                                        -- ein haltendes Fahrzeug wieder anfaehrt
FolgeMirVehicle.MASS_TAKT    = 2000     -- ms, so oft werden die Gespannmasse geprueft
FolgeMirVehicle.MAX_TIEFE    = 8        -- maximale Anhaengerkette

-- ============================================================================
-- Kleine Helfer
-- ============================================================================

local function abstand2D(x1, z1, x2, z2)
    local dx, dz = x2 - x1, z2 - z1
    return math.sqrt(dx * dx + dz * dz)
end

--- Zustandswert "Tempomat aus". Die Konstante kommt aus Drivable.
local function tempomatAus()
    if Drivable ~= nil and Drivable.CRUISECONTROL_STATE_OFF ~= nil then
        return Drivable.CRUISECONTROL_STATE_OFF
    end

    return 0
end

--- Liefert den Scenegraph-Knoten eines Fahrzeugs.
local function getFahrzeugKnoten(fahrzeug)
    if fahrzeug == nil or fahrzeug.isDeleted == true then
        return nil
    end

    if fahrzeug.rootNode ~= nil and entityExists(fahrzeug.rootNode) then
        return fahrzeug.rootNode
    end

    if fahrzeug.components ~= nil and fahrzeug.components[1] ~= nil
        and fahrzeug.components[1].node ~= nil and entityExists(fahrzeug.components[1].node) then
        return fahrzeug.components[1].node
    end

    return nil
end

--- Knoten, von dem aus gemessen und gelenkt wird.
--- AIFieldWorker benutzt dafuer getAISteeringNode, deshalb hier genauso.
local function getLenkKnoten(fahrzeug)
    if fahrzeug.getAISteeringNode ~= nil then
        local knoten = fahrzeug:getAISteeringNode()

        if knoten ~= nil and entityExists(knoten) then
            return knoten
        end
    end

    if fahrzeug.components ~= nil and fahrzeug.components[1] ~= nil then
        return fahrzeug.components[1].node
    end

    return fahrzeug.rootNode
end

--- Ausdehnung eines kompletten Gespanns in Fahrtrichtung, gemessen gegen den
--- angegebenen Bezugsknoten. Liefert, wie weit das Gespann nach vorne und wie
--- weit es nach hinten ueber den Bezugsknoten hinausragt (beides in Metern).
--- Damit laesst sich der Abstand von Heck zu Front statt von Mitte zu Mitte
--- halten - bei einem langen Haecksler oder Anhaengerzug macht das mehrere
--- Meter aus.
local function gespannAusdehnung(fahrzeug, bezugsKnoten)
    if fahrzeug == nil or bezugsKnoten == nil or not entityExists(bezugsKnoten) then
        return 0, 0
    end

    local minZ, maxZ = 0, 0
    local besucht = {}

    local function erfasse(teil, tiefe)
        if teil == nil or tiefe > FolgeMirVehicle.MAX_TIEFE or besucht[teil] then
            return
        end

        besucht[teil] = true

        local knoten = getFahrzeugKnoten(teil)

        if knoten ~= nil then
            -- Front und Heck des Einzelfahrzeugs, wie das Spiel sie in
            -- AIAutomaticSteering ansetzt
            local vorne, hinten = 1.5, -1.5

            if teil.size ~= nil and teil.size.length ~= nil then
                local versatz = teil.size.lengthOffset or 0
                vorne  = versatz + teil.size.length * 0.5
                hinten = versatz - teil.size.length * 0.5
            end

            local _, _, z1 = localToLocal(knoten, bezugsKnoten, 0, 0, vorne)
            local _, _, z2 = localToLocal(knoten, bezugsKnoten, 0, 0, hinten)

            minZ = math.min(minZ, z1, z2)
            maxZ = math.max(maxZ, z1, z2)
        end

        if teil.getAttachedImplements ~= nil then
            local angehaengt = teil:getAttachedImplements()

            if angehaengt ~= nil then
                for _, eintrag in pairs(angehaengt) do
                    if eintrag ~= nil then
                        erfasse(eintrag.object, tiefe + 1)
                    end
                end
            end
        end
    end

    erfasse(fahrzeug, 1)

    -- nach vorne, nach hinten
    return maxZ, -minZ
end

-- ============================================================================
-- Registrierung
-- ============================================================================

function FolgeMirVehicle.prerequisitesPresent(specializations)
    -- Welche Fahrzeugtypen die Spezialisierung bekommen, entscheidet
    -- FolgeMirMain (nur drivable + motorized + enterable).
    return true
end

function FolgeMirVehicle.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad",                 FolgeMirVehicle)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete",               FolgeMirVehicle)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate",               FolgeMirVehicle)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream",           FolgeMirVehicle)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream",          FolgeMirVehicle)
    SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", FolgeMirVehicle)
end

function FolgeMirVehicle.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "fmGetDaten",    FolgeMirVehicle.fmGetDaten)
    SpecializationUtil.registerFunction(vehicleType, "fmStartFolgen", FolgeMirVehicle.fmStartFolgen)
    SpecializationUtil.registerFunction(vehicleType, "fmStoppFolgen", FolgeMirVehicle.fmStoppFolgen)
    SpecializationUtil.registerFunction(vehicleType, "fmFolgtGerade", FolgeMirVehicle.fmFolgtGerade)
    SpecializationUtil.registerFunction(vehicleType, "fmGetZiel",     FolgeMirVehicle.fmGetZiel)
    SpecializationUtil.registerFunction(vehicleType, "fmFahrTakt",    FolgeMirVehicle.fmFahrTakt)
end

-- ============================================================================
-- Datenhaltung pro Fahrzeug
-- ============================================================================

function FolgeMirVehicle:fmGetDaten()
    if self.fmDaten == nil then
        self.fmDaten = {
            aktiv          = false,
            ziel           = nil,     -- Fahrzeug, dem gefolgt wird
            spur           = {},      -- Liste {x=, y=, z=}
            haelt          = true,    -- true = Fahrzeug soll stehen bleiben
            zielTempo      = 0,       -- km/h, geschaetztes Tempo des Ziels
            letzteZielX    = nil,
            letzteZielZ    = nil,
            festTimer      = 0,
            massTimer      = 0,       -- bis zur naechsten Gespann-Messung
            zielHeck       = 0,       -- m, die das Zielgespann nach hinten ragt
            eigenFront     = 0,       -- m, die das eigene Gespann nach vorne ragt
            motorVorher    = nil,     -- gemerkt: stopMotorOnLeave
            motorLief      = nil,     -- lief der Motor schon vor dem Start?
            tempomatVorher = nil,     -- gemerkt: eingestellte Tempomat-Geschwindigkeit
            forceVorher    = nil,     -- gemerkt: forceIsActive
            letzterTakt    = nil,     -- g_updateLoopIndex des letzten Fahrtakts
            werte          = {},      -- letzte Messwerte fuer den Befehl fmDebug
            actionEvents   = {}       -- Tastenbelegung, solange man im Fahrzeug sitzt
        }
    end

    return self.fmDaten
end

function FolgeMirVehicle:fmFolgtGerade()
    return self:fmGetDaten().aktiv == true
end

function FolgeMirVehicle:fmGetZiel()
    return self:fmGetDaten().ziel
end

function FolgeMirVehicle:onLoad(savegame)
    self:fmGetDaten()
end

function FolgeMirVehicle:onDelete()
    local daten = self.fmDaten

    if daten ~= nil and daten.aktiv then
        daten.aktiv = false
        FolgeMirMain.merkeFolger(self, false)
    end
end

--- Fahrtakt im regulaeren Fahrzeug-Update. Das ist der richtige Zeitpunkt,
--- weil die Radphysik unmittelbar danach ausgewertet wird. Bekommt das
--- Fahrzeug kein eigenes Update - ein abgestelltes Fahrzeug ist nicht
--- zwangslaeufig aktiv -, springt FolgeMirMain als Ersatz ein.
function FolgeMirVehicle:onUpdate(dt)
    local daten = self.fmDaten

    if daten == nil or not daten.aktiv then
        return
    end

    if self.raiseActive ~= nil then
        self:raiseActive()
    end

    if self.isServer then
        self:fmFahrTakt(dt)
    end
end

-- ============================================================================
-- Tastenbelegung
--
-- Die Tasten werden bewusst hier und nicht global registriert: Ein
-- Aktionsereignis aus einem Mod-Listener erreicht den Fahrzeug-Kontext nicht,
-- die Taste bliebe am Steuer wirkungslos. Ueber onRegisterActionEvents legt
-- das Spiel die Belegung an, sobald der Spieler einsteigt, und raeumt sie
-- beim Aussteigen wieder weg. Damit taucht die Taste auch in der F1-Hilfe des
-- Fahrzeugs auf und wirkt genau da, wo sie wirken soll.
-- ============================================================================

function FolgeMirVehicle:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    if not self.isClient then
        return
    end

    if self.getIsEntered == nil or not self:getIsEntered() then
        return
    end

    local daten = self:fmGetDaten()

    if daten.actionEvents == nil then
        daten.actionEvents = {}
    end

    if self.clearActionEventsTable ~= nil then
        self:clearActionEventsTable(daten.actionEvents)
    end

    if not isActiveForInputIgnoreSelection then
        return
    end

    if InputAction == nil or self.addActionEvent == nil then
        return
    end

    if InputAction.FOLGEMIR_TOGGLE ~= nil then
        local _, eventId = self:addActionEvent(daten.actionEvents, InputAction.FOLGEMIR_TOGGLE,
            self, FolgeMirVehicle.actionEventUmschalten, false, true, false, true, nil)

        if eventId ~= nil then
            g_inputBinding:setActionEventText(eventId,
                FolgeMirMain.text("input_FOLGEMIR_TOGGLE", "Folge mir: Fahrzeug an/aus"))
            g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_LOW)
        end
    end

    if InputAction.FOLGEMIR_UEBERGABE ~= nil then
        local _, eventId = self:addActionEvent(daten.actionEvents, InputAction.FOLGEMIR_UEBERGABE,
            self, FolgeMirVehicle.actionEventUebergabe, false, true, false, true, nil)

        if eventId ~= nil then
            g_inputBinding:setActionEventText(eventId,
                FolgeMirMain.text("input_FOLGEMIR_UEBERGABE", "Folge mir: Reihe uebergeben"))
            g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_LOW)
            g_inputBinding:setActionEventTextVisibility(eventId, false)
        end
    end

    if InputAction.FOLGEMIR_STOPP ~= nil then
        local _, eventId = self:addActionEvent(daten.actionEvents, InputAction.FOLGEMIR_STOPP,
            self, FolgeMirVehicle.actionEventAlleStoppen, false, true, false, true, nil)

        if eventId ~= nil then
            g_inputBinding:setActionEventText(eventId,
                FolgeMirMain.text("input_FOLGEMIR_STOPP", "Folge mir: alle anhalten"))
            g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_LOW)
            g_inputBinding:setActionEventTextVisibility(eventId, false)
        end
    end
end

function FolgeMirVehicle.actionEventUmschalten(self, actionName, inputValue, callbackState, isAnalog)
    FolgeMirMain.aufUmschalten()
end

function FolgeMirVehicle.actionEventAlleStoppen(self, actionName, inputValue, callbackState, isAnalog)
    FolgeMirMain.aufAlleStoppen()
end

function FolgeMirVehicle.actionEventUebergabe(self, actionName, inputValue, callbackState, isAnalog)
    FolgeMirMain.aufUebergabe()
end

-- ============================================================================
-- Start und Stopp
-- ============================================================================

--- Startet das Folgen. Laeuft auf Server und Client; der Client haelt den
--- Zustand nur fuer HUD und Anzeige, gefahren wird allein auf dem Server.
function FolgeMirVehicle:fmStartFolgen(ziel, ohneEvent)
    if ziel == nil or ziel == self then
        return false
    end

    local daten = self:fmGetDaten()

    if ohneEvent and ziel == FolgeMirMain.getMeinFahrzeug() and not daten.aktiv then
        FolgeMirMain.meldung("fm_bekommen", "Dir folgt jetzt ein weiteres Fahrzeug.")
    end

    daten.aktiv       = true
    daten.ziel        = ziel
    daten.spur        = {}
    daten.haelt       = true
    daten.zielTempo   = 0
    daten.letzteZielX = nil
    daten.letzteZielZ = nil
    daten.festTimer   = 0
    daten.massTimer   = 0
    daten.leerTimer   = 0
    daten.fuehrerId   = nil

    if self.isServer then
        -- Ohne das hier lenkt das Fahrzeug nicht: WheelPhysics:serverUpdate
        -- rechnet rotatedTime nur dann in den Radwinkel um, wenn
        -- vehicle.isActive gesetzt ist (WheelPhysics.lua:801). Bei einem
        -- fahrerlosen Fahrzeug ist das sonst nicht der Fall - der Antrieb
        -- wirkt trotzdem, weil der ueber den Motor laeuft, nur die Lenkung
        -- bleibt auf dem letzten Wert stehen und es faehrt geradeaus.
        -- forceIsActive ist der dafuer vorgesehene Schalter (Vehicle.lua:995).
        if daten.forceVorher == nil then
            daten.forceVorher = self.forceIsActive == true
            self.forceIsActive = true
        end

        -- Der Motor darf beim Aussteigen nicht ausgehen, sonst rollt das
        -- Fahrzeug nur aus. Der urspruengliche Wert wird gemerkt.
        if self.spec_motorized ~= nil and daten.motorVorher == nil then
            daten.motorVorher = self.spec_motorized.stopMotorOnLeave
            self.spec_motorized.stopMotorOnLeave = false

            -- Lief der Motor schon, bevor wir losgeschickt haben? Dann wird
            -- er am Ende auch nicht von uns abgestellt.
            daten.motorLief = false

            if self.getIsMotorStarted ~= nil then
                daten.motorLief = self:getIsMotorStarted() == true
            end
        end

        -- driveToPoint deckelt das Tempo auf die eingestellte Tempomat-
        -- Geschwindigkeit. Stand die auf 10 km/h, kaeme das Fahrzeug nie
        -- schneller voran - deshalb merken und im Fahrtakt hochsetzen.
        if daten.tempomatVorher == nil and self.spec_drivable ~= nil
            and self.spec_drivable.cruiseControl ~= nil then
            daten.tempomatVorher = self.spec_drivable.cruiseControl.speed
        end
    end

    -- Erster Wegpunkt, damit die Spur nicht leer startet
    local knoten = getFahrzeugKnoten(ziel)

    if knoten ~= nil then
        local zx, zy, zz = getWorldTranslation(knoten)
        table.insert(daten.spur, { x = zx, y = zy, z = zz })
    end

    if self.raiseActive ~= nil then
        self:raiseActive()
    end

    FolgeMirMain.merkeFolger(self, true)

    if not ohneEvent then
        FolgeMirEvent.sende(self, ziel, 0)
    end

    return true
end

--- Beendet das Folgen und bremst das Fahrzeug ab.
--- grund groesser 0 ist ein Abbruch (siehe FolgeMirMain.gruende); der Spieler,
--- dessen Fahrzeug gefolgt wurde, bekommt dann eine Bildschirmmeldung.
function FolgeMirVehicle:fmStoppFolgen(ohneEvent, grund)
    local daten = self:fmGetDaten()

    if not daten.aktiv then
        -- Aufraeumen, falls ein Eintrag haengen geblieben ist
        FolgeMirMain.merkeFolger(self, false)
        return false
    end

    if grund ~= nil and grund > 0 then
        FolgeMirMain.meldungGrund(daten.ziel, grund)
    end

    -- Steht dieses Fahrzeug mitten in einer Kette, ruecken die dahinter auf
    -- sein Ziel nach. Das entscheidet der Server, damit nicht jeder Client
    -- fuer sich umhaengt.
    if self.isServer and daten.ziel ~= nil and FolgeMirMain.ketteSchliessen ~= nil then
        FolgeMirMain.ketteSchliessen(self, daten.ziel)
    end

    daten.aktiv = false
    daten.ziel  = nil
    daten.spur  = {}

    if self.isServer then
        if daten.forceVorher ~= nil then
            self.forceIsActive = daten.forceVorher
            daten.forceVorher = nil
        end

        if self.spec_motorized ~= nil and daten.motorVorher ~= nil then
            self.spec_motorized.stopMotorOnLeave = daten.motorVorher
            daten.motorVorher = nil
        end

        -- Tempomat zuruecksetzen. Ohne das bliebe er aktiv und das Fahrzeug
        -- wuerde weiterfahren beziehungsweise der naechste Fahrer saesse in
        -- einem Fahrzeug mit unerwartet gesetztem Tempomat.
        if daten.tempomatVorher ~= nil and self.setCruiseControlMaxSpeed ~= nil then
            self:setCruiseControlMaxSpeed(daten.tempomatVorher)
            daten.tempomatVorher = nil
        end

        if self.setCruiseControlState ~= nil then
            self:setCruiseControlState(tempomatAus(), true)
        end

        -- Anhalten: Handbremse ueber driveToPoint, zusaetzlich Bremspedal
        if AIVehicleUtil ~= nil and AIVehicleUtil.driveToPoint ~= nil then
            AIVehicleUtil.driveToPoint(self, 16, 0, false, true, 0, 1, 0, true)
        end

        if self.brake ~= nil then
            self:brake(1)
        end

        -- Nur zuruecknehmen, was die Mod selbst angestellt hat: War der
        -- Motor beim Losschicken aus und sitzt jetzt niemand drin, geht er
        -- wieder aus. Lief er vorher schon, bleibt er an - ob ein Fahrzeug
        -- ohne Fahrer laeuft, entscheidet der Spieler, nicht diese Mod.
        local besetzt = self.spec_enterable ~= nil and self.spec_enterable.isControlled == true

        if not besetzt and daten.motorLief ~= true
            and self.getIsMotorStarted ~= nil and self.stopMotor ~= nil then

            if self:getIsMotorStarted() then
                self:stopMotor()
            end
        end

        daten.motorLief = nil
    end

    FolgeMirMain.merkeFolger(self, false)

    if not ohneEvent then
        FolgeMirEvent.sende(self, nil, grund)
    end

    return true
end

-- ============================================================================
-- Spurverwaltung
-- ============================================================================

--- Haengt bei Bedarf einen neuen Wegpunkt an die Spur.
local function spurPflegen(daten, zx, zy, zz)
    local letzter = daten.spur[#daten.spur]

    if letzter == nil then
        table.insert(daten.spur, { x = zx, y = zy, z = zz })
        return
    end

    if abstand2D(letzter.x, letzter.z, zx, zz) >= FolgeMirVehicle.SPUR_ABSTAND then
        table.insert(daten.spur, { x = zx, y = zy, z = zz })
    end

    while #daten.spur > FolgeMirVehicle.SPUR_MAX do
        table.remove(daten.spur, 1)
    end
end

--- Entfernt alle Wegpunkte, die das Fahrzeug bereits erreicht hat. Es wird bis
--- zum letzten erreichten Punkt aufgeraeumt, damit eine Abkuerzung nicht dazu
--- fuehrt, dass ein alter Punkt die Spur blockiert.
local function spurAufraeumen(daten, fx, fz)
    local letzterTreffer = 0

    for i = 1, #daten.spur do
        local p = daten.spur[i]

        if abstand2D(p.x, p.z, fx, fz) <= FolgeMirVehicle.PUNKT_RADIUS then
            letzterTreffer = i
        end
    end

    for _ = 1, letzterTreffer do
        table.remove(daten.spur, 1)
    end
end

--- Restweg entlang der Spur: Fahrzeug zu Wegpunkten zu Ziel.
local function restweg(daten, fx, fz, zx, zz)
    local anzahl = #daten.spur

    if anzahl == 0 then
        return abstand2D(fx, fz, zx, zz)
    end

    local summe = abstand2D(fx, fz, daten.spur[1].x, daten.spur[1].z)

    for i = 1, anzahl - 1 do
        summe = summe + abstand2D(daten.spur[i].x, daten.spur[i].z,
                                  daten.spur[i + 1].x, daten.spur[i + 1].z)
    end

    return summe + abstand2D(daten.spur[anzahl].x, daten.spur[anzahl].z, zx, zz)
end

--- Punkt auf der Spur, der ungefaehr LOOKAHEAD Meter vor dem Fahrzeug liegt.
local function fahrpunkt(daten, fx, fz, zx, zy, zz)
    local anzahl = #daten.spur

    if anzahl == 0 then
        return zx, zy, zz
    end

    local strecke = abstand2D(fx, fz, daten.spur[1].x, daten.spur[1].z)
    local index   = 1

    while strecke < FolgeMirVehicle.LOOKAHEAD and index < anzahl do
        strecke = strecke + abstand2D(daten.spur[index].x, daten.spur[index].z,
                                      daten.spur[index + 1].x, daten.spur[index + 1].z)
        index = index + 1
    end

    local p = daten.spur[index]

    return p.x, p.y, p.z
end

-- ============================================================================
-- Fahrtakt (nur Server)
-- ============================================================================

function FolgeMirVehicle:fmFahrTakt(dt)
    local daten = self.fmDaten

    if daten == nil or not daten.aktiv or not self.isServer then
        return
    end

    if AIVehicleUtil == nil or AIVehicleUtil.driveToPoint == nil then
        return
    end

    -- Merken, in welchem Durchlauf zuletzt gefahren wurde. Daran erkennt
    -- FolgeMirMain, ob es als Ersatz einspringen muss.
    daten.letzterTakt = g_updateLoopIndex

    local einst = FolgeMirMain.einstellungen

    -- --- Abbruchgruende -----------------------------------------------------

    local zielKnoten = getFahrzeugKnoten(daten.ziel)

    if zielKnoten == nil then
        self:fmStoppFolgen(false, FolgeMirMain.GRUND_ZIEL_WEG)
        return
    end

    -- Steigt jemand ein, uebernimmt der Mensch das Steuer
    if self.spec_enterable ~= nil and self.spec_enterable.isControlled == true then
        self:fmStoppFolgen(false, FolgeMirMain.GRUND_BESETZT)
        return
    end

    if self.getCanMotorRun ~= nil and not self:getCanMotorRun() then
        self:fmStoppFolgen(false, FolgeMirMain.GRUND_MOTOR)
        return
    end

    -- Vorne am Steuer sollte jemand sitzen. Tut das gerade niemand, wird die
    -- Reihe NICHT gleich aufgeloest - der Spieler steigt vielleicht nur kurz
    -- aus, um ein Tor zu oeffnen oder zu tanken. (Im Stau sitzt er ohnehin
    -- weiter drin, das zaehlt hier gar nicht.) Es geht nur der Motor aus,
    -- damit nichts unnoetig laeuft; sobald es weitergeht, startet ihn der
    -- Fahrtakt von selbst wieder.
    -- Aufgeloest wird erst, wenn der Fahrer das Spiel verlassen hat.
    local wurzel  = FolgeMirMain.getWurzel(self)
    local besetzt = wurzel ~= nil and wurzel.spec_enterable ~= nil
                    and wurzel.spec_enterable.isControlled == true

    if besetzt then
        daten.leerTimer = 0

        -- Wer sitzt vorne? Beim Aussteigen setzt das Spiel die Kennung auf 0
        -- zurueck, deshalb jetzt merken und nicht erst hinterher fragen.
        local kennung = wurzel.spec_enterable.controllerUserId

        if kennung ~= nil and kennung ~= 0 then
            daten.fuehrerId = kennung
        end
    else
        -- Am Motor wird hier bewusst nichts gemacht. Ob ein Fahrzeug ohne
        -- Fahrer weiterlaeuft oder ausgeht, stellt der Spieler selbst ein -
        -- das ist nicht Sache dieser Mod.
        if FolgeMirMain.istNochImSpiel(daten.fuehrerId) then
            daten.leerTimer = 0
        else
            daten.leerTimer = (daten.leerTimer or 0) + dt

            if daten.leerTimer > einst.leerlaufSekunden * 1000 then
                self:fmStoppFolgen(false, FolgeMirMain.GRUND_VERWAIST)
                return
            end
        end
    end

    -- --- Positionen ---------------------------------------------------------

    local lenkKnoten = getLenkKnoten(self)

    if lenkKnoten == nil or not entityExists(lenkKnoten) then
        self:fmStoppFolgen(false, FolgeMirMain.GRUND_ZIEL_WEG)
        return
    end

    local fx, _,  fz = getWorldTranslation(lenkKnoten)
    local zx, zy, zz = getWorldTranslation(zielKnoten)

    local luftlinie = abstand2D(fx, fz, zx, zz)

    if luftlinie > einst.maxZielentfernung then
        self:fmStoppFolgen(false, FolgeMirMain.GRUND_ZU_WEIT)
        return
    end

    -- --- Gespannmasse -------------------------------------------------------
    -- Nicht jeden Frame: Anbaugeraete wechseln selten, die Messung laeuft
    -- ueber die ganze Anhaengerkette.

    daten.massTimer = daten.massTimer - dt

    if daten.massTimer <= 0 then
        daten.massTimer = FolgeMirVehicle.MASS_TAKT

        local _, zielHeck = gespannAusdehnung(daten.ziel, zielKnoten)
        local eigenFront  = gespannAusdehnung(self, lenkKnoten)

        daten.zielHeck   = zielHeck
        daten.eigenFront = eigenFront
    end

    -- --- Tempo des Ziels schaetzen ------------------------------------------
    -- Ueber die Positionsaenderung, geglaettet, sonst zappelt der Wert.

    local sekunden = dt / 1000

    if sekunden > 0 and daten.letzteZielX ~= nil then
        local strecke  = abstand2D(daten.letzteZielX, daten.letzteZielZ, zx, zz)
        local momentan = math.min((strecke / sekunden) * 3.6, 120)

        daten.zielTempo = daten.zielTempo * 0.85 + momentan * 0.15
    end

    daten.letzteZielX = zx
    daten.letzteZielZ = zz

    -- --- Spur pflegen -------------------------------------------------------

    spurPflegen(daten, zx, zy, zz)
    spurAufraeumen(daten, fx, fz)

    -- --- Sollwerte ----------------------------------------------------------
    -- Der eingestellte Abstand ist die Luecke zwischen dem Heck des vorderen
    -- Gespanns und der Front des eigenen. Beide Laengen kommen deshalb oben
    -- drauf, sonst waere der Abstand bei langen Gespannen viel zu knapp.

    local wunschAbstand = einst.abstand + daten.zielHeck + daten.eigenFront
    local maxTempo      = einst.maxTempo

    local rest = restweg(daten, fx, fz, zx, zz)

    -- Halten und Anfahren mit Hysterese: erst wenn sich das Ziel wieder ein
    -- Stueck entfernt hat, faehrt ein haltendes Fahrzeug an. Ohne das wechselt
    -- es im Grenzbereich staendig zwischen Gas und Bremse.
    if daten.haelt then
        if rest > wunschAbstand + FolgeMirVehicle.LOSFAHR_PLUS then
            daten.haelt = false
        end
    else
        if rest <= wunschAbstand then
            daten.haelt = true
        end
    end

    -- Luftlinie unter dem Sicherheitsabstand: unter allen Umstaenden halten.
    -- Faengt den Fall ab, dass das vordere Gespann wendet und ploetzlich quer
    -- vor dem Folger steht, die Spur aber noch einen langen Weg ausweist.
    if luftlinie <= (daten.zielHeck + daten.eigenFront + 2) then
        daten.haelt = true
    end

    local darfFahren = not daten.haelt
    local tempo      = 0

    if darfFahren then
        -- Grundtempo ist das Tempo des Ziels, dazu eine Korrektur ueber den
        -- Abstand. So haelt ein Konvoi mit, statt staendig hinterherzuhinken.
        local korrektur = (rest - wunschAbstand) * 0.8

        tempo = math.clamp(daten.zielTempo + korrektur,
                           FolgeMirVehicle.ANFAHR_TEMPO, maxTempo)
    end

    -- --- Motor und Tempomat -------------------------------------------------

    if darfFahren then
        if self.getIsMotorStarted ~= nil and self.startMotor ~= nil then
            if not self:getIsMotorStarted() then
                self:startMotor()
            end
        end

        -- driveToPoint begrenzt auf getCruiseControlSpeed, deshalb mitziehen
        if self.setCruiseControlMaxSpeed ~= nil then
            self:setCruiseControlMaxSpeed(maxTempo)
        end
    end

    -- --- Feststeck-Erkennung ------------------------------------------------

    if darfFahren then
        local tempoIst = math.abs(self.lastSpeedReal or 0) * 3600

        if tempoIst < 0.5 then
            daten.festTimer = daten.festTimer + dt

            if daten.festTimer > FolgeMirVehicle.FEST_ZEIT then
                self:fmStoppFolgen(false, FolgeMirMain.GRUND_FEST)
                return
            end
        else
            daten.festTimer = 0
        end
    else
        daten.festTimer = 0
    end

    -- --- Fahren -------------------------------------------------------------

    local px, py, pz = fahrpunkt(daten, fx, fz, zx, zy, zz)
    local tX, _, tZ  = worldToLocal(lenkKnoten, px, py, pz)

    if darfFahren then
        AIVehicleUtil.driveToPoint(self, dt, 1, true, true, tX, tZ, tempo, false)
    else
        -- Beim Halten nicht lenken, sonst schlaegt die Lenkung im Stand ein
        AIVehicleUtil.driveToPoint(self, dt, 0, false, true, tX, tZ, 0, true)
    end

    -- Messwerte fuer den Befehl fmDebug festhalten. Kostet nichts und erspart
    -- im Zweifel eine Runde Raten, wenn das Fahrverhalten nicht stimmt.
    local werte = daten.werte
    werte.tX         = tX
    werte.tZ         = tZ
    werte.rest       = rest
    werte.soll       = wunschAbstand
    werte.tempo      = tempo
    werte.darfFahren = darfFahren
    werte.spur       = #daten.spur
    werte.rotatedTime = self.rotatedTime
    werte.maxRotTime  = self.maxRotTime
    werte.minRotTime  = self.minRotTime
    werte.isActive    = self.isActive

    if self.getAISteeringSpeed ~= nil then
        werte.steeringSpeed = self:getAISteeringSpeed()
    end

    if self.raiseActive ~= nil then
        self:raiseActive()
    end
end

-- ============================================================================
-- Multiplayer: Ersteinstieg eines Clients
-- ============================================================================

function FolgeMirVehicle:onWriteStream(streamId, connection)
    local daten = self:fmGetDaten()

    local folgt = false
    if daten.aktiv and daten.ziel ~= nil then
        folgt = true
    end

    if streamWriteBool(streamId, folgt) then
        NetworkUtil.writeNodeObject(streamId, daten.ziel)
    end
end

function FolgeMirVehicle:onReadStream(streamId, connection)
    local daten = self:fmGetDaten()

    if streamReadBool(streamId) then
        local ziel = NetworkUtil.readNodeObject(streamId)

        -- Das Ziel kann beim Verbinden noch unbekannt sein, wenn der Folger
        -- vor dem vorderen Fahrzeug synchronisiert wird. Dann zeigt dieser
        -- Client das Folgen erst nach dem naechsten Zustandswechsel an -
        -- gefahren wird davon unabhaengig auf dem Server.
        if ziel ~= nil then
            self:fmStartFolgen(ziel, true)
        end
    end
end
