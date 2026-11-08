-- QuestSync: compara las misiones de todos los miembros del grupo.
-- Cada miembro necesita tener el addon: al pulsar "Analizar" se pide a
-- todos su registro de misiones por el canal oculto de addons y se compara.
-- Cada jugador se identifica por su GUID (no por el nombre), así no hay duplicados.

local ADDON = ...
local PREFIX = "QSYNC2"     -- prefijo nuevo: la versión vieja no es compatible
local ESPERA = 2            -- segundos esperando las misiones de cada uno
local ESPERA2 = 1.5         -- segundos esperando quién ya completó qué
local MAX_CHUNK = 220       -- bytes por mensaje de addon (límite 255)

local db
local miGUID, miNombre
local peticionActual        -- id de la petición en curso
local datos = {}            -- datos[guid] = { nombre, quests = {[id] = {t, c, l}}, fin }
local remitenteAGuid = {}   -- "Nombre-Reino" tal como llega -> guid

local function msg(t) print("|cFF33CCFF[QuestSync]|r " .. t) end

---------------------------------------------------------------------------
-- Idiomas: inglés por defecto; español si el cliente está en español (esMX / esES).
-- Los títulos de las misiones vienen del juego, así que salen en el idioma de cada cliente.
---------------------------------------------------------------------------
local L = {
    title = "Group quests",
    yourGroup = "Your group",
    groupInfo = "(%d members, %d with the addon)",
    onlyYou = "Just you",
    noAddon = " (no addon)",
    boxDiff = "not everyone\nhas them",
    boxShared = "everyone\nhas them",
    boxReady = "ready to\nturn in",
    tabDiff = "Not everyone has",
    tabShared = "Everyone has",
    tabReady = "Ready to turn in",
    markDiff = "Missing:",
    markShared = "Have it:",
    markReady = "Ready for:",
    legDiff = "= that person is missing the quest",
    legShared = "= has the quest",
    legReady = "= can turn it in now",
    noteDone = "already turned in",
    noteReady = "ready",
    noteMissing = "doesn't have it",
    noteHas = "has it",
    nobody = "Nobody else in the group answered.",
    needAll = "Everyone needs QuestSync installed and enabled to compare.",
    allSame = "Everyone has exactly the same quests!",
    noneReady = "Nobody has quests ready to turn in yet.",
    noneShared = "There are no quests that everyone has.",
    ready = "ready: ",
    missing1 = "1 missing",
    missingN = "%d missing",
    ttHave = "Have it: ",
    ttReady = "Ready to turn in: ",
    ttDone = "Already turned in: ",
    ttMissing = "Don't have it: ",
    ttClick = "Click: view quest · Shift+click: link in chat",
    btnRescan = "Scan again",
    notInGroup = "You are not in a group.",
    invite = "Invite your friends and scan again.",
    loading1 = "Asking the group for their quests...",
    loading2 = "Checking which quests each member already turned in...",
    scannedAt = "Scanned at %s",
    launcher = "Quests",
    ttLaunch1 = "Click: view the group quest comparison",
    ttLaunch2 = "(to refresh it, use \"Scan again\")",
    ttDrag = "Drag: move the button",
    andWord = " and ",
    buttonShown = "Floating button visible.",
    buttonHidden = "Floating button hidden.",
    logCleared = "Log cleared.",
    debugOn = "Debug ON: you will see every message sent and received in chat, and a log is saved.",
    debugOff = "Debug OFF.",
    help = "Commands:",
    help1 = "  /questsync  — open the window (scans only the first time)",
    help2 = "  /questsync scan  — compare the group's quests again",
    help3 = "  /questsync button  — show or hide the floating button",
    help4 = "  /questsync debug  — turn debug mode and the log on or off",
}
if (GetLocale() or ""):sub(1, 2) == "es" then
    L = {
        title = "Misiones del grupo",
        yourGroup = "Tu grupo",
        groupInfo = "(%d miembros, %d con el addon)",
        onlyYou = "Solo tú",
        noAddon = " (sin addon)",
        boxDiff = "no las tienen\ntodos",
        boxShared = "las tienen\ntodos",
        boxReady = "listas para\nentregar",
        tabDiff = "No las tienen todos",
        tabShared = "Las tienen todos",
        tabReady = "Listas para entregar",
        markDiff = "Le falta a:",
        markShared = "La tienen:",
        markReady = "Lista para:",
        legDiff = "= a esa persona le falta la misión",
        legShared = "= tiene la misión",
        legReady = "= ya puede entregarla",
        noteDone = "ya la entregó",
        noteReady = "lista",
        noteMissing = "no la tiene",
        noteHas = "la tiene",
        nobody = "Nadie más del grupo respondió.",
        needAll = "Todos necesitan tener QuestSync instalado y activado para comparar.",
        allSame = "¡Todos tienen exactamente las mismas misiones!",
        noneReady = "Nadie tiene misiones listas para entregar todavía.",
        noneShared = "No hay misiones que tengan todos.",
        ready = "lista: ",
        missing1 = "falta 1",
        missingN = "faltan %d",
        ttHave = "La tienen: ",
        ttReady = "Lista para entregar: ",
        ttDone = "Ya la entregaron: ",
        ttMissing = "No la tienen: ",
        ttClick = "Clic: ver la misión · Shift+clic: enlazar en el chat",
        btnRescan = "Volver a analizar",
        notInGroup = "No estás en un grupo.",
        invite = "Invita a tus amigos y vuelve a analizar.",
        loading1 = "Pidiendo las misiones al grupo...",
        loading2 = "Comprobando qué misiones ya entregó cada uno...",
        scannedAt = "Analizado a las %s",
        launcher = "Misiones",
        ttLaunch1 = "Clic: ver la comparación de misiones del grupo",
        ttLaunch2 = "(para actualizarla, usa \"Volver a analizar\")",
        ttDrag = "Arrastrar: mover el botón",
        andWord = " y ",
        buttonShown = "Botón flotante visible.",
        buttonHidden = "Botón flotante oculto.",
        logCleared = "Log borrado.",
        debugOn = "Debug ON: verás en el chat cada mensaje enviado y recibido, y se guarda un log.",
        debugOff = "Debug OFF.",
        help = "Comandos:",
        help1 = "  /misiones  — abrir la ventana (analiza solo la primera vez)",
        help2 = "  /misiones analizar  — volver a comparar las misiones del grupo",
        help3 = "  /misiones boton  — mostrar u ocultar el botón flotante",
        help4 = "  /misiones debug  — activar o desactivar el modo debug y el log",
    }
end

---------------------------------------------------------------------------
-- Log: solo se guarda con /misiones debug activado, en QuestSyncDB.log
-- (WTF\...\SavedVariables\QuestSync.lua). El juego escribe ese archivo al hacer /reload o al salir.
---------------------------------------------------------------------------
local MAX_LOG = 400
local function dbg(t)
    if not db or not db.debug then return end
    db.log = db.log or {}
    table.insert(db.log, date("%H:%M:%S") .. string.format(".%03d ", (GetTime() * 1000) % 1000) .. t)
    while #db.log > MAX_LOG do table.remove(db.log, 1) end
    if db.debug then print("|cFF888888[QuestSync debug]|r " .. t) end
end

---------------------------------------------------------------------------
-- Leer mi registro de misiones
---------------------------------------------------------------------------
local function leerMisQuests()
    local quests = {}

    if GetQuestLogTitle and GetNumQuestLogEntries then
        -- API clásica. Los encabezados plegados ocultan misiones, así que
        -- los desplegamos un momento y luego los volvemos a plegar.
        local plegados = {}
        for i = 1, GetNumQuestLogEntries() do
            local titulo, _, _, esHeader, plegado = GetQuestLogTitle(i)
            if esHeader and plegado then plegados[titulo] = true end
        end
        if next(plegados) and ExpandQuestHeader then ExpandQuestHeader(0) end

        for i = 1, GetNumQuestLogEntries() do
            local titulo, nivel, _, esHeader, _, completa, _, id = GetQuestLogTitle(i)
            if not esHeader and id and id > 0 then
                quests[id] = { t = titulo, l = nivel or 0, c = (completa == 1 or completa == true) }
            end
        end

        if next(plegados) and CollapseQuestHeader then
            for i = GetNumQuestLogEntries(), 1, -1 do
                local titulo, _, _, esHeader = GetQuestLogTitle(i)
                if esHeader and plegados[titulo] then CollapseQuestHeader(i) end
            end
        end
    elseif C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID and info.questID > 0 then
                local completa = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID)
                quests[info.questID] = { t = info.title, l = info.level or 0, c = completa and true or false }
            end
        end
    end
    return quests
end

-- ¿Ya entregué esta misión alguna vez? (historial del personaje)
local function yaCompletada(id)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        return C_QuestLog.IsQuestFlaggedCompleted(id) and true or false
    elseif IsQuestFlaggedCompleted then
        return IsQuestFlaggedCompleted(id) and true or false
    end
    return false
end

---------------------------------------------------------------------------
-- Comunicación
---------------------------------------------------------------------------
local function canal()
    -- Grupo del buscador de mazmorras: PARTY no funciona, hay que usar INSTANCE_CHAT
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local function enviar(texto)
    local c = canal()
    if not c then return end
    local r = C_ChatInfo.SendAddonMessage(PREFIX, texto, c)
    dbg("Enviado por " .. c .. " (resultado: " .. tostring(r) .. "): " .. texto:sub(1, 80))
end

-- Quita los caracteres que usamos como separadores
local function limpiar(s) return (s or "?"):gsub("[~^#|]", "") end

-- Protocolo:
--   R#peticion#guid                  pedir misiones
--   S#peticion#guid#nombre           inicio de respuesta
--   Q#peticion#id^c^nivel^titulo~... misiones
--   E#peticion                       fin de respuesta
--   P#peticion#guid#id,id,...        "¿cuáles de estas ya completaron?"
--   H#peticion#id,id,...             "estas ya las completé"

-- Envía una lista de números troceada en varios mensajes si hace falta
local function enviarLista(cabecera, ids)
    local trozo = ""
    for _, id in ipairs(ids) do
        local s = tostring(id)
        if #trozo + #s + 1 > MAX_CHUNK then
            enviar(cabecera .. trozo)
            trozo = ""
        end
        trozo = (trozo == "") and s or (trozo .. "," .. s)
    end
    if trozo ~= "" then enviar(cabecera .. trozo) end
end

local function enviarMisQuests(idPeticion)
    enviar("S#" .. idPeticion .. "#" .. miGUID .. "#" .. limpiar(miNombre))
    local ok, quests = pcall(leerMisQuests)
    if not ok then
        dbg("Error leyendo misiones: " .. tostring(quests))
        quests = {}
    end
    local trozo = ""
    for id, q in pairs(quests) do
        local entrada = id .. "^" .. (q.c and "1" or "0") .. "^" .. (q.l or 0) .. "^" .. limpiar(q.t)
        if #trozo + #entrada + 1 > MAX_CHUNK then
            enviar("Q#" .. idPeticion .. "#" .. trozo)
            trozo = ""
        end
        trozo = (trozo == "") and entrada or (trozo .. "~" .. entrada)
    end
    if trozo ~= "" then enviar("Q#" .. idPeticion .. "#" .. trozo) end
    enviar("E#" .. idPeticion)
end


-- Lista de { guid, nombre, clase } de todo el grupo, incluido yo
local function miembrosDelGrupo()
    local lista = { { guid = miGUID, nombre = miNombre, clase = select(2, UnitClass("player")) } }
    local prefijo, total = "party", GetNumSubgroupMembers()
    if IsInRaid() then prefijo, total = "raid", GetNumGroupMembers() end
    for i = 1, total do
        local u = prefijo .. i
        local g = UnitGUID(u)
        if g and g ~= miGUID then
            table.insert(lista, { guid = g, nombre = UnitName(u) or "?", clase = select(2, UnitClass(u)) })
        end
    end
    return lista
end

---------------------------------------------------------------------------
-- Análisis: devuelve los datos ya ordenados; la ventana se encarga de dibujarlos
---------------------------------------------------------------------------
local VERDE, ROJO, GRIS, DORADO, FIN = "|cFF40FF40", "|cFFFF5555", "|cFF9D9D9D", "|cFFFFD100", "|r"

local function unir(t)
    if #t <= 1 then return t[1] or "" end
    return table.concat(t, ", ", 1, #t - 1) .. L.andWord .. t[#t]
end

-- Enlace de misión del juego: al hacer clic, Questie muestra su ficha
local function enlace(id, q)
    return "|cFFFFD100|Hquest:" .. id .. ":" .. (q.l or 0) .. "|h[" .. q.t .. "]|h|r"
end

-- Título de la misión en el idioma de mi cliente, si el juego lo tiene
local function tituloLocal(id)
    local f = C_QuestLog and C_QuestLog.GetTitleForQuestID
    if not f then return nil end
    local ok, t = pcall(f, id)
    if ok and type(t) == "string" and t ~= "" then return t end
end

local function analizar()
    local miembros, sinAddon, conAddon = {}, {}, {}
    for _, m in ipairs(miembrosDelGrupo()) do
        local d = datos[m.guid]
        if d then
            d.nombre = m.nombre -- usar el mismo nombre que la lista del grupo
            d.clase = m.clase
            table.insert(conAddon, m.guid)
            local n = 0
            for _ in pairs(d.quests) do n = n + 1 end
            table.insert(miembros, { nombre = m.nombre, clase = m.clase, addon = true, misiones = n, yo = m.guid == miGUID })
        else
            table.insert(sinAddon, m.nombre)
            table.insert(miembros, { nombre = m.nombre, clase = m.clase, addon = false })
        end
    end
    dbg("ANALISIS con=" .. #conAddon .. " sin=" .. table.concat(sinAddon, ","))

    -- Juntar todas las misiones de todos
    local todas = {}
    for _, g in ipairs(conAddon) do
        for id, q in pairs(datos[g].quests) do
            todas[id] = todas[id] or { id = id, t = tituloLocal(id) or q.t, l = q.l, quien = {}, completa = {} }
            todas[id].quien[g] = true
            if q.c then table.insert(todas[id].completa, datos[g].nombre) end
        end
    end

    local compartidas, distintas, listas = {}, {}, {}
    for _, q in pairs(todas) do
        q.estado = {} -- por miembro, en el orden del grupo: "tiene" | "lista" | "hecha" | "falta"
        q.tienen, q.faltan, q.hecha = {}, {}, {}
        local completas = {}
        for _, n in ipairs(q.completa) do completas[n] = true end
        for _, g in ipairs(conAddon) do
            local d = datos[g]
            local e
            if q.quien[g] then
                e = completas[d.nombre] and "lista" or "tiene"
                table.insert(q.tienen, d.nombre)
            elseif d.hechas and d.hechas[q.id] then
                e = "hecha" -- no la tiene porque ya la entregó
                table.insert(q.hecha, d.nombre)
            else
                e = "falta"
                table.insert(q.faltan, d.nombre)
            end
            table.insert(q.estado, { nombre = d.nombre, clase = d.clase, e = e })
        end
        if #q.completa > 0 then table.insert(listas, q) end
        table.insert(#q.faltan == 0 and compartidas or distintas, q)
    end
    local porNivel = function(a, b)
        if (a.l or 0) ~= (b.l or 0) then return (a.l or 0) < (b.l or 0) end
        return a.t < b.t
    end
    table.sort(compartidas, porNivel)
    table.sort(distintas, porNivel)
    table.sort(listas, porNivel)

    return {
        miembros = miembros, sinAddon = sinAddon, conAddon = #conAddon,
        distintas = distintas, compartidas = compartidas, listas = listas,
    }
end

---------------------------------------------------------------------------
-- Ventana
---------------------------------------------------------------------------
local ANCHO, ALTO = 620, 520
local ANCHO_CONT = ANCHO - 56
local ICONO_TIENE = "|TInterface\\RaidFrame\\ReadyCheck-Ready:13:13|t"
local ICONO_FALTA = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:13:13|t"
local ICONO_LISTA = "|TInterface\\GossipFrame\\ActiveQuestIcon:13:13|t"
local ICONO_HECHA = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:13:13|t"

local function colorClase(clase)
    local c = clase and ((C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(clase))
        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[clase]))
    if c then return string.format("|cFF%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end
    return "|cFFFFFFFF"
end

local function colorNivel(nivel)
    local f = GetQuestDifficultyColor or (C_QuestLog and C_QuestLog.GetQuestDifficultyColor)
    local ok, c = pcall(f or error, nivel or 0)
    if ok and c then return string.format("|cFF%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end
    return DORADO
end

local win = CreateFrame("Frame", "QuestSyncFrame", UIParent, "BasicFrameTemplateWithInset")
win:SetSize(ANCHO, ALTO)
win:SetPoint("CENTER")
win:SetMovable(true)
win:SetClampedToScreen(true)
win:EnableMouse(true)
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    if db then db.posVentana = { p, rp, x, y } end
end)
win:SetFrameStrata("DIALOG")
win:Hide()
tinsert(UISpecialFrames, "QuestSyncFrame") -- se cierra con Escape

win.titulo = win.TitleText or win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
win.titulo:SetPoint("TOP", 0, -5)
win.titulo:SetText("|cFF33CCFFQuestSync|r  ·  " .. L.title)

local function Panel(padre)
    local p = CreateFrame("Frame", nil, padre, "BackdropTemplate")
    p:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    p:SetBackdropColor(0, 0, 0, 0.35)
    p:SetBackdropBorderColor(1, 1, 1, 0.08)
    return p
end

-- Encabezado: miembros del grupo
local cab = Panel(win)
cab:SetPoint("TOPLEFT", 12, -30)
cab:SetPoint("TOPRIGHT", -12, -30)
cab:SetHeight(52)
cab.icono = cab:CreateTexture(nil, "ARTWORK")
cab.icono:SetSize(36, 36)
cab.icono:SetPoint("LEFT", 8, 0)
cab.icono:SetTexture("Interface\\Icons\\INV_Misc_Book_08")
cab.icono:SetTexCoord(0.07, 0.93, 0.07, 0.93)
cab.titulo = cab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
cab.titulo:SetPoint("TOPLEFT", cab.icono, "TOPRIGHT", 10, -1)
cab.titulo:SetText(L.yourGroup)
cab.miembros = cab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
cab.miembros:SetPoint("BOTTOMLEFT", cab.icono, "BOTTOMRIGHT", 10, 1)
cab.miembros:SetPoint("RIGHT", -10, 0)
cab.miembros:SetJustifyH("LEFT")
cab.miembros:SetWordWrap(false)

-- Tres recuadros con números
local function Recuadro(i, etiqueta, r, g, b)
    local t = Panel(win)
    local ancho = (ANCHO - 24 - 16) / 3
    t:SetSize(ancho, 46)
    t:SetPoint("TOPLEFT", cab, "BOTTOMLEFT", (i - 1) * (ancho + 8), -6)
    t.barra = t:CreateTexture(nil, "ARTWORK")
    t.barra:SetPoint("TOPLEFT")
    t.barra:SetPoint("BOTTOMLEFT")
    t.barra:SetWidth(3)
    t.barra:SetColorTexture(r, g, b, 1)
    t.num = t:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    t.num:SetPoint("LEFT", 12, 0)
    t.num:SetTextColor(r, g, b)
    t.txt = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t.txt:SetPoint("LEFT", t.num, "RIGHT", 10, 0)
    t.txt:SetPoint("RIGHT", -6, 0)
    t.txt:SetJustifyH("LEFT")
    t.txt:SetText(etiqueta)
    return t
end
local rDistintas = Recuadro(1, L.boxDiff, 1, 0.6, 0.2)
local rCompartidas = Recuadro(2, L.boxShared, 0.3, 0.85, 0.3)
local rListas = Recuadro(3, L.boxReady, 1, 0.82, 0)

-- Pestañas de filtro
local vista = "distintas"
local pestanas = {}
local function Pestana(clave, texto, x)
    local b = CreateFrame("Button", nil, win, "BackdropTemplate")
    b:SetSize(180, 24)
    b:SetPoint("TOPLEFT", rDistintas, "BOTTOMLEFT", x, -8)
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    b.txt = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.txt:SetPoint("CENTER")
    b.base = texto
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b:SetScript("OnClick", function()
        vista = clave
        win:Dibujar()
    end)
    pestanas[clave] = b
    return b
end
Pestana("distintas", L.tabDiff, 0)
Pestana("compartidas", L.tabShared, 186)
Pestana("listas", L.tabReady, 372)

-- Los recuadros de números también cambian de pestaña
for clave, r in pairs({ distintas = rDistintas, compartidas = rCompartidas, listas = rListas }) do
    r:EnableMouse(true)
    r:SetScript("OnMouseUp", function()
        vista = clave
        win:Dibujar()
    end)
end

-- Leyenda (abajo, sobre los botones)
local leyenda = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
leyenda:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 16, 44)
leyenda:SetPoint("RIGHT", win, "RIGHT", -14, 0)
leyenda:SetJustifyH("LEFT")

-- Lista con scroll
local marco = Panel(win)
marco:SetPoint("TOPLEFT", pestanas.distintas, "BOTTOMLEFT", 0, 0)
marco:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -12, 60)
local scroll = CreateFrame("ScrollFrame", "QuestSyncScroll", marco, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 6, -6)
scroll:SetPoint("BOTTOMRIGHT", -26, 6)
local contenido = CreateFrame("Frame", nil, scroll)
contenido:SetSize(ANCHO_CONT, 10)
scroll:SetScrollChild(contenido)

-- Mensaje central (cargando, sin grupo, etc.)
local aviso = marco:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
aviso:SetPoint("CENTER", 0, 20)
aviso:SetWidth(ANCHO - 80)
aviso:SetSpacing(4)
local carga = CreateFrame("StatusBar", nil, marco)
carga:SetSize(260, 10)
carga:SetPoint("TOP", aviso, "BOTTOM", 0, -12)
carga:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
carga:SetStatusBarColor(0.2, 0.8, 1)
carga:SetMinMaxValues(0, 1)
carga.fondo = carga:CreateTexture(nil, "BACKGROUND")
carga.fondo:SetAllPoints()
carga.fondo:SetColorTexture(0, 0, 0, 0.6)
carga:Hide()

-- Filas reutilizables: una por misión
local filas, usadas = {}, 0
local function NuevaFila()
    usadas = usadas + 1
    local f = filas[usadas]
    if f then return f end
    f = CreateFrame("Button", nil, contenido, "BackdropTemplate")
    f:SetHeight(40)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    f.franja = f:CreateTexture(nil, "ARTWORK")
    f.franja:SetPoint("TOPLEFT")
    f.franja:SetPoint("BOTTOMLEFT")
    f.franja:SetWidth(3)
    f.nivel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.nivel:SetPoint("LEFT", 10, 0)
    f.nivel:SetWidth(30)
    f.titulo = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.titulo:SetPoint("TOPLEFT", 46, -5)
    f.titulo:SetPoint("RIGHT", -10, 0)
    f.titulo:SetJustifyH("LEFT")
    f.titulo:SetWordWrap(false)
    f.quien = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.quien:SetPoint("BOTTOMLEFT", 46, 6)
    f.quien:SetPoint("RIGHT", -10, 0)
    f.quien:SetJustifyH("LEFT")
    f.quien:SetWordWrap(false)
    f:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- Clic = ficha de la misión (la de Questie si está instalado), Shift+clic = pegar el enlace en el chat
    f:SetScript("OnClick", function(self, boton)
        if not self.link then return end
        if IsShiftKeyDown() and ChatEdit_InsertLink then
            ChatEdit_InsertLink(self.link)
        else
            SetItemRef(self.hlink, self.link, boton)
        end
    end)
    f:SetScript("OnEnter", function(self)
        if not self.hlink then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not pcall(GameTooltip.SetHyperlink, GameTooltip, self.hlink) then
            GameTooltip:AddLine(self.q and self.q.t or "?")
        end
        if self.lineas then
            GameTooltip:AddLine(" ")
            for _, l in ipairs(self.lineas) do GameTooltip:AddLine(l, 1, 1, 1, true) end
        end
        GameTooltip:AddLine("|cFF9D9D9D" .. L.ttClick .. "|r")
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)
    filas[usadas] = f
    return f
end

local ultimo -- último resultado de analizar(); se conserva hasta el próximo análisis
local analizando = false
local abrir -- se define más abajo

-- Una sola marca por pestaña, según lo que muestra esa pestaña:
--   No las tienen todos  -> ✗ a quien le falta
--   Las tienen todos     -> ✓ a quien la tiene
--   Listas para entregar -> ? a quien ya puede entregarla
-- El resto va en gris, sin marca, solo como información.
local MARCA = {
    distintas   = { icono = ICONO_FALTA, cumple = { falta = true }, texto = L.markDiff },
    compartidas = { icono = ICONO_TIENE, cumple = { tiene = true, lista = true }, texto = L.markShared },
    listas      = { icono = ICONO_LISTA, cumple = { lista = true }, texto = L.markReady },
}
local LEYENDA = {
    distintas   = ICONO_FALTA .. " " .. L.legDiff,
    compartidas = ICONO_TIENE .. " " .. L.legShared,
    listas      = ICONO_LISTA .. " " .. L.legReady,
}

local function TextoEstado(q, v)
    local marca = MARCA[v] or MARCA.distintas
    local si, resto = {}, {}
    for _, s in ipairs(q.estado) do
        if marca.cumple[s.e] then
            si[#si + 1] = marca.icono .. " " .. colorClase(s.clase) .. s.nombre .. FIN
        else
            local nota = (s.e == "hecha" and L.noteDone) or (s.e == "lista" and L.noteReady) or (s.e == "falta" and L.noteMissing) or L.noteHas
            resto[#resto + 1] = s.nombre .. " (" .. nota .. ")"
        end
    end
    local txt = GRIS .. marca.texto .. FIN .. "  " .. table.concat(si, "   ")
    if #resto > 0 then txt = txt .. "    " .. GRIS .. "·  " .. table.concat(resto, ", ") .. FIN end
    return txt
end

local function MostrarAviso(texto, progreso)
    for i = 1, usadas do filas[i]:Hide() end
    usadas = 0
    contenido:SetHeight(10)
    aviso:SetText(texto)
    aviso:Show()
    if progreso then carga:Show() else carga:Hide() end
end

-- Barra de carga que avanza durante "segs" segundos
local function Cargando(texto, desde, hasta, segs)
    MostrarAviso(texto, true)
    local t0 = GetTime()
    carga:SetValue(desde)
    carga:SetScript("OnUpdate", function(self)
        local p = math.min((GetTime() - t0) / segs, 1)
        self:SetValue(desde + (hasta - desde) * p)
        if p >= 1 then self:SetScript("OnUpdate", nil) end
    end)
end

local function Miembros(r)
    local partes = {}
    for _, m in ipairs(r.miembros) do
        if m.addon then
            partes[#partes + 1] = colorClase(m.clase) .. m.nombre .. FIN .. GRIS .. " (" .. m.misiones .. ")" .. FIN
        else
            partes[#partes + 1] = GRIS .. m.nombre .. FIN .. ROJO .. L.noAddon .. FIN
        end
    end
    return table.concat(partes, "   ")
end

function win:Dibujar()
    local r = ultimo
    for clave, b in pairs(pestanas) do
        local n = r and #r[clave] or 0
        local sel = clave == vista
        b.txt:SetText(b.base .. "  " .. (sel and "|cFFFFFFFF" or GRIS) .. "(" .. n .. ")" .. FIN)
        b:SetBackdropColor(1, 0.7, 0.25, sel and 0.2 or 0.04)
        b:SetBackdropBorderColor(1, 0.7, 0.25, sel and 0.8 or 0.15)
    end
    rDistintas.num:SetText(r and #r.distintas or "–")
    rCompartidas.num:SetText(r and #r.compartidas or "–")
    rListas.num:SetText(r and #r.listas or "–")
    leyenda:SetText(LEYENDA[vista] or "")
    -- Mientras analiza, la lista muestra la barra de carga: no dibujo los datos viejos encima
    if not r or analizando then return end

    cab.titulo:SetText(L.yourGroup .. "  " .. GRIS .. string.format(L.groupInfo, #r.miembros, r.conAddon) .. FIN)
    cab.miembros:SetText(Miembros(r))

    if r.conAddon < 2 then
        MostrarAviso(ROJO .. L.nobody .. FIN .. "\n" .. GRIS .. L.needAll .. FIN)
        return
    end
    local lista = r[vista]
    if #lista == 0 then
        MostrarAviso((vista == "distintas" and (VERDE .. L.allSame .. FIN))
            or (vista == "listas" and (GRIS .. L.noneReady .. FIN))
            or (GRIS .. L.noneShared .. FIN))
        return
    end
    aviso:Hide()
    carga:Hide()
    for i = 1, usadas do filas[i]:Hide() end
    usadas = 0
    local y = 0
    for i, q in ipairs(lista) do
        local f = NuevaFila()
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", contenido, "TOPLEFT", 0, -y)
        f:SetWidth(ANCHO_CONT)
        f:SetBackdropColor(1, 1, 1, (i % 2 == 0) and 0.05 or 0.025)
        local faltan = #q.faltan
        if vista == "distintas" then
            f.franja:SetColorTexture(1, 0.6, 0.2, 1)
        elseif #q.completa > 0 then
            f.franja:SetColorTexture(1, 0.82, 0, 1)
        else
            f.franja:SetColorTexture(0.3, 0.85, 0.3, 1)
        end
        local cn = colorNivel(q.l)
        f.nivel:SetText(cn .. (q.l and q.l > 0 and q.l or "?") .. FIN)
        local extra = ""
        if vista == "listas" then
            f.franja:SetColorTexture(1, 0.82, 0, 1)
            extra = "   " .. DORADO .. L.ready .. unir(q.completa) .. FIN
        elseif vista == "distintas" then
            extra = "   " .. ROJO .. (faltan > 1 and string.format(L.missingN, faltan) or L.missing1) .. FIN
            if #q.completa > 0 then extra = extra .. "  " .. DORADO .. "· " .. L.ready .. unir(q.completa) .. FIN end
        elseif #q.completa > 0 then
            extra = "   " .. DORADO .. L.ready .. unir(q.completa) .. FIN
        end
        f.titulo:SetText(cn .. q.t .. FIN .. extra)
        f.quien:SetText(TextoEstado(q, vista))
        f.q = q
        f.hlink = "quest:" .. q.id .. ":" .. (q.l or 0)
        f.link = enlace(q.id, q)
        local lineas = {}
        if #q.tienen > 0 then lineas[#lineas + 1] = VERDE .. L.ttHave .. FIN .. unir(q.tienen) end
        if #q.completa > 0 then lineas[#lineas + 1] = DORADO .. L.ttReady .. FIN .. unir(q.completa) end
        if #q.hecha > 0 then lineas[#lineas + 1] = GRIS .. L.ttDone .. unir(q.hecha) .. FIN end
        if faltan > 0 then lineas[#lineas + 1] = ROJO .. L.ttMissing .. FIN .. unir(q.faltan) end
        f.lineas = lineas
        f:Show()
        y = y + 42
    end
    contenido:SetHeight(y + 4)
end

local function mostrar(texto, progreso)
    win:Show()
    if texto then MostrarAviso(texto, progreso) end
end

local btnAnalizar = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
btnAnalizar:SetSize(140, 24)
btnAnalizar:SetPoint("BOTTOMLEFT", 12, 12)
btnAnalizar:SetText(L.btnRescan)

local hora = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hora:SetPoint("BOTTOMRIGHT", -16, 18)

---------------------------------------------------------------------------
-- Flujo principal
---------------------------------------------------------------------------
local function iniciarAnalisis()
    if not canal() then
        ultimo = nil
        win:Dibujar()
        cab.titulo:SetText(L.yourGroup)
        cab.miembros:SetText(GRIS .. L.onlyYou .. FIN)
        mostrar(ROJO .. L.notInGroup .. FIN .. "\n" .. GRIS .. L.invite .. FIN)
        return
    end
    peticionActual = tostring(math.random(100000, 999999))
    wipe(datos)
    datos[miGUID] = { nombre = miNombre, quests = leerMisQuests(), fin = true }

    dbg("=== NUEVO ANALISIS id=" .. peticionActual .. " yo=[" .. miNombre .. "] " .. miGUID
        .. " canal=" .. tostring(canal()))
    for _, m in ipairs(miembrosDelGrupo()) do
        dbg("  miembro [" .. m.nombre .. "] " .. m.guid)
    end
    enviar("R#" .. peticionActual .. "#" .. miGUID)
    analizando = true
    btnAnalizar:Disable()
    win:Show()
    Cargando(L.loading1, 0, 0.6, ESPERA)

    local idEsta = peticionActual
    C_Timer.After(ESPERA, function()
        if idEsta ~= peticionActual then return end
        -- Fase 2: juntar todas las misiones y preguntar quién ya las completó
        local union, ids = {}, {}
        for g, d in pairs(datos) do
            local c = 0
            for id in pairs(d.quests) do
                c = c + 1
                if not union[id] then union[id] = true; table.insert(ids, id) end
            end
            dbg("  datos[" .. d.nombre .. "] " .. g .. " misiones=" .. c .. " fin=" .. tostring(d.fin))
        end
        -- Las mías las compruebo directamente
        local mias = datos[miGUID]
        mias.hechas = {}
        for _, id in ipairs(ids) do
            if not mias.quests[id] and yaCompletada(id) then mias.hechas[id] = true end
        end
        enviarLista("P#" .. peticionActual .. "#" .. miGUID .. "#", ids)
        Cargando(L.loading2, 0.6, 1, ESPERA2)

        C_Timer.After(ESPERA2, function()
            if idEsta ~= peticionActual then return end
            analizando = false
            ultimo = analizar()
            -- Me quedo en la pestaña que tenías; si quedó vacía y todos tienen lo mismo, paso a compartidas
            if #ultimo[vista] == 0 and #ultimo.distintas == 0 and #ultimo.compartidas > 0 then vista = "compartidas" end
            scroll:SetVerticalScroll(0)
            win:Dibujar()
            hora:SetText(string.format(L.scannedAt, date("%H:%M")))
            btnAnalizar:Enable()
        end)
    end)
end

btnAnalizar:SetScript("OnClick", iniciarAnalisis)
win:Dibujar()

-- Abrir la ventana: si ya hay un análisis, se muestra tal cual; solo se analiza la primera vez.
-- Para actualizar está el botón "Volver a analizar" (o /misiones analizar).
function abrir()
    win:Show()
    if analizando then return end
    if ultimo then
        win:Dibujar()
    else
        iniciarAnalisis()
    end
end

---------------------------------------------------------------------------
-- Botón flotante para abrir la ventana (arrastrable)
---------------------------------------------------------------------------
local lanzador = CreateFrame("Button", "QuestSyncLauncher", UIParent, "UIPanelButtonTemplate")
lanzador:SetSize(100, 24)
lanzador:SetText(L.launcher)
lanzador:SetMovable(true)
lanzador:SetClampedToScreen(true)
lanzador:RegisterForDrag("LeftButton")
do
    local icono = lanzador:CreateTexture(nil, "OVERLAY")
    icono:SetTexture("Interface\\Icons\\INV_Misc_Book_08")
    icono:SetSize(16, 16)
    icono:SetPoint("LEFT", 6, 0)
    icono:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local fs = lanzador:GetFontString()
    if fs then fs:ClearAllPoints() fs:SetPoint("LEFT", icono, "RIGHT", 4, 0) fs:SetPoint("RIGHT", -6, 0) end
end
lanzador:SetScript("OnDragStart", lanzador.StartMoving)
lanzador:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    db.pos = { p, rp, x, y }
end)
lanzador:SetScript("OnClick", function()
    if win:IsShown() then win:Hide() else abrir() end
end)
lanzador:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("|cFF33CCFFQuestSync|r")
    GameTooltip:AddLine(L.ttLaunch1, 1, 1, 1)
    GameTooltip:AddLine(L.ttLaunch2, 0.6, 0.6, 0.6)
    GameTooltip:AddLine(L.ttDrag, 1, 1, 1)
    GameTooltip:Show()
end)
lanzador:SetScript("OnLeave", GameTooltip_Hide)
---------------------------------------------------------------------------
-- Eventos
---------------------------------------------------------------------------
local function recibir(texto, canalMsg, remitente)
    dbg("Recibido de [" .. tostring(remitente) .. "] por " .. tostring(canalMsg) .. ": " .. tostring(texto):sub(1, 80))
    local tipo, id, resto = strsplit("#", texto, 3)

    if tipo == "R" then
        if resto == miGUID then return end -- es mi propia petición
        enviarMisQuests(id)
        return
    end
    if tipo == "P" then
        -- Alguien pregunta cuáles de estas misiones ya entregué
        local guid, lista = strsplit("#", resto or "", 2)
        if guid == miGUID or not lista then return end
        local hechas = {}
        for s in lista:gmatch("%d+") do
            local qid = tonumber(s)
            if yaCompletada(qid) then table.insert(hechas, qid) end
        end
        dbg("  P: de esa lista ya completé " .. #hechas)
        enviarLista("H#" .. id .. "#", hechas)
        return
    end
    if id ~= peticionActual then
        dbg("  IGNORADO: id " .. tostring(id) .. " no es mi peticion actual " .. tostring(peticionActual))
        return
    end

    if tipo == "S" then
        local guid, nombre = strsplit("#", resto or "", 2)
        if not guid or guid == "" or guid == miGUID then return end
        remitenteAGuid[remitente] = guid
        datos[guid] = { nombre = nombre or remitente, quests = {}, fin = false }
        return
    end

    local guid = remitenteAGuid[remitente]
    local d = guid and datos[guid]
    if not d then return end
    if tipo == "Q" and resto then
        for entrada in resto:gmatch("[^~]+") do
            local qid, c, nivel, t = strsplit("^", entrada, 4)
            qid = tonumber(qid)
            if qid then d.quests[qid] = { t = t or "?", l = tonumber(nivel) or 0, c = (c == "1") } end
        end
    elseif tipo == "E" then
        d.fin = true
    elseif tipo == "H" and resto then
        d.hechas = d.hechas or {}
        for s in resto:gmatch("%d+") do d.hechas[tonumber(s)] = true end
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:SetScript("OnEvent", function(self, event, a1, a2, a3, a4)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        QuestSyncDB = QuestSyncDB or {}
        db = QuestSyncDB
        if not db.debug then db.log = nil end -- sin debug no se guarda log
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        local p = db.pos
        if p then lanzador:SetPoint(p[1], UIParent, p[2], p[3], p[4])
        else lanzador:SetPoint("TOP", UIParent, "TOP", 0, -120) end
        if db.ocultarBoton then lanzador:Hide() end
        local pv = db.posVentana
        if pv then
            win:ClearAllPoints()
            win:SetPoint(pv[1], UIParent, pv[2], pv[3], pv[4])
        end
    elseif event == "PLAYER_LOGIN" then
        miGUID = UnitGUID("player")
        miNombre = UnitName("player")
    elseif event == "CHAT_MSG_ADDON" then
        -- prefix, mensaje, canal, remitente
        if a1 == PREFIX and miGUID then recibir(a2, a3, a4) end
    end
end)

---------------------------------------------------------------------------
-- Comandos: /qsync o /misiones
---------------------------------------------------------------------------
SLASH_QUESTSYNC1 = "/qsync"
SLASH_QUESTSYNC2 = "/misiones"
SLASH_QUESTSYNC3 = "/questsync"
SlashCmdList.QUESTSYNC = function(arg)
    arg = (arg or ""):lower():match("^%s*(.-)%s*$")
    if arg == "boton" or arg == "botón" or arg == "button" then
        db.ocultarBoton = not db.ocultarBoton
        if db.ocultarBoton then lanzador:Hide() else lanzador:Show() end
        msg(db.ocultarBoton and L.buttonHidden or L.buttonShown)
    elseif arg == "borrarlog" or arg == "clearlog" then
        db.log = {}
        msg(L.logCleared)
    elseif arg == "debug" then
        db.debug = not db.debug
        msg(db.debug and L.debugOn or L.debugOff)
    elseif arg == "ayuda" or arg == "help" then
        msg(L.help)
        print(L.help1)
        print(L.help2)
        print(L.help3)
        print(L.help4)
    elseif arg == "analizar" or arg == "scan" then
        win:Show()
        iniciarAnalisis()
    else
        abrir()
    end
end
