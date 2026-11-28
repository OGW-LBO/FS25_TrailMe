# Spurfolger

Ein Fahrzeug folgt dem Spieler auf dessen eigener Spur.

Entstanden ist die Mod aus einer ganz praktischen Not im eigenen Team. Wir wollten ein zweites Fahrzeug mit zum Feld nehmen, mehr nicht - und dafür war uns AutoDrive zu viel des Guten. Ein Streckennetz anzulegen, zu pflegen und im Kopf zu behalten lohnt sich, wenn man es ausreizt; für "fahr mir einfach hinterher" ist es ein großer Apparat. Also macht diese Mod genau das eine, und sonst nichts.

**Sie ist kein Ersatz für AutoDrive.** Es gibt keine gespeicherten Strecken, keine Routenplanung, kein selbstständiges Fahren zum Hof und zurück, kein Be- oder Entladen, keine Aufträge. Nichts fährt ohne dich - du sitzt am Steuer, der Rest hängt sich an. Wer autonome Abläufe braucht, ist bei AutoDrive richtig und bleibt dort besser aufgehoben.

Ein Fahrzeug fährt deinem Fahrzeug automatisch hinterher - im Einzelspieler wie im Multiplayer.

So funktioniert es:
- Du sitzt selbst am Steuer und fährst an das Fahrzeug heran, das folgen soll
- STRG + H: Dieses Fahrzeug folgt dir ab sofort
- Mehrere gehen auch: Jedes weitere Fahrzeug hängt sich hinten an die Reihe und folgt dem Fahrzeug davor
- Steht kein freies Fahrzeug mehr in der Nähe, hält STRG + H den nächsten Folger an
- STRG + J: Gibt die ganze Reihe an einen Mitspieler ab, neben dem du stehst
- STRG + SHIFT + H: Alle Fahrzeuge, die dir folgen, halten an
- Steigst du in ein folgendes Fahrzeug ein, übernimmst du wieder selbst

Zur Tastenbelegung: STRG + H und STRG + SHIFT + H sind nur die Vorgabe. Nutzt eine andere Mod dieselbe Kombination, meldet das Spiel beim Start eine Doppelbelegung - dann in den Einstellungen unter Tastenbelegung nach "Spurfolger" suchen und eine freie Taste vergeben. Dasselbe gilt, wenn gar nichts passiert: hat die Aktion dort keine Taste, greift die Vorgabe aus der Mod nicht mehr und du musst einmal selbst belegen.

Das Gespann bleibt, wie du es vorbereitet hast. Anbaugeräte und Anhänger werden weder abgehängt noch eingeklappt oder angehoben - der Folger zieht sein komplettes Gespann mit. Für den Abstand wird die tatsächliche Länge beider Gespanne mitgerechnet, der eingestellte Wert ist also die Lücke zwischen dem Heck vor dir und der Front dahinter. Bei einem langen Häcksler oder Anhängerzug macht das mehrere Meter aus.

Das Fahrzeug fährt nicht auf Luftlinie, sondern auf deiner Spur: Es merkt sich deinen Weg und fährt ihn nach. Dadurch schneidet es keine Kurven durch Zäune oder Gebäude und fährt in der Feldeinfahrt dieselbe Linie wie du. Bleibst du stehen, bleibt es auch stehen. Gelenkt wird über dieselbe Spielfunktion, mit der auch die Helfer des Spiels fahren, deshalb nimmt es in engen Kurven von selbst Gas weg.

Einem Spieler zu Fuß folgt bewusst nichts - die Funktion lässt sich nur am Steuer auslösen.

Licht und Rundumleuchte macht der Folger an, wenn du deine anmachst - schaltest du für die Straße ein, leuchtet die ganze Reihe. Welche Scheinwerfer das sind, entscheidet das Fahrzeug selbst, genau wie bei den Helfern des Spiels. Wer es lieber an der Uhrzeit hat, stellt das Licht im Menü auf "bei Dunkelheit".

Eingestellt wird im Spielmenü unter Einstellungen - Allgemein, ganz unten im Abschnitt "Spurfolger": Abstand, Höchstgeschwindigkeit, Reichweite, Suchradius, Fahrzeuge je Reihe, Zeit bis zum Aufgeben, Wartezeit, Licht und Rundumleuchte. Im Multiplayer gelten die Werte für den ganzen Server; ändern darf sie dort nur, wer als Administrator angemeldet ist, bei allen anderen stehen die Zeilen grau. Dieselben Werte liegen weiterhin in "modSettings/FS25_TrailMe/settings.xml" und lassen sich über die Konsole setzen: "fmInfo" zeigt alle, "fmSet <name> <wert>" ändert einen, "fmStopp" hält alles an.

Multiplayer: Gefahren wird auf dem Server, alle Mitspieler sehen dasselbe. Jeder Spieler kann nur Fahrzeuge losschicken, auf die seine Farm Zugriff hat. Mit STRG + J gibst du deine ganze Reihe an einen Mitspieler ab, neben dem du stehst - praktisch, wenn er weiterfährt und du etwas anderes machst. Steigst du zwischendurch aus - Tor öffnen, tanken, kurz etwas anderes machen -, bleibt die Reihe stehen und wartet auf dich. Aufgelöst wird sie erst, wenn der Fahrer das Spiel verlassen hat. Serverbetreiber und Administratoren können mit dem Konsolenbefehl "fmStopp" alle Reihen auf einmal auflösen.

Hinweis: Es wird nur vorwärts gefahren und es findet keine Wegsuche statt - in sehr engen Hofeinfahrten kann ein Gespann hängen bleiben. Die Mod meldet sich, bevor etwas abreißt: wenn ein Folger nicht weiterkommt, wenn ihm der Sprit ausgeht, und wenn du ihm davonfährst. In den ersten beiden Fällen geht zusätzlich seine Rundumleuchte an, damit du siehst, welches Fahrzeug es ist. Wie lange er feststecken darf, bevor die Mod aufgibt, stellst du im Menü ein.

Wer mein Coworker HUD nutzt, sieht dort nebenbei, welches Fahrzeug gerade wem folgt. Nötig ist es nicht - die beiden Mods kennen sich nur, wenn ohnehin beide geladen sind.

Script-Mod, daher nur für PC und Mac.

## Installation

Die ZIP aus den [Releases](../../releases) herunterladen und in den
Mods-Ordner legen:

    Dokumente\My Games\FarmingSimulator2025\mods

Auf einem Dedicated Server gehoert sie in dessen Mods-Ordner.

## Update von 1.0.3.0

Ein neuer Spielstand ist nicht nötig, die Mod legt nichts im Savegame ab.
Bestehende Einstellungen bleiben erhalten; die vier neuen - Zeit bis zum
Aufgeben, Licht, Rundumleuchte und Spur einzeichnen - kommen mit ihrem
Vorgabewert dazu. Die Tasten sind unverändert, eine neuere Spielversion
braucht es nicht, und die ZIP heißt weiterhin `FS25_TrailMe.zip`, wird beim
Kopieren also überschrieben.

**Im Mehrspieler müssen Server und alle Mitspieler zusammen wechseln.** Es
sind zwei Netzwerk-Ereignisse dazugekommen - für die Einstellungen und für
die Hinweise -, und deren Kennungen vergibt der Server. Fährt jemand noch
1.0.3.0, schreibt sein Spiel Fehler ins Log und die Einstellungen kommen bei
ihm nicht an.

## Stand

Version 1.1.0.0, gebaut gegen descVersion 116.

## Discord

Fragen, Fehler und Ideen zur Mod am besten auf unserem Discord-Server
"Furchenpfuscher": https://discord.gg/vsAhgaf43w

## Lizenz

Alle Rechte vorbehalten, Einzelheiten in LICENSE.txt. Der Quelltext liegt
offen, damit man sieht, was die Mod tut - eine Freigabe zur
Weiterverwendung ist das nicht.
