-- gzin pedo | Sem TP | Discord | Pula compra apos 10 tentativas
-- Abas, switches, listas com busca e regras por personagem.
-- Anti-AFK e automacao precisam ser validados no jogo.
-- Defeat Anime RNG: Auto Buy + Auto Roll + Anti-AFK
-- Compra 0.15s; pausa adicional entre rolagens 0s.
-- Repete compras e rolagens enquanto os controles estiverem ligados.
-- Configuracoes locais por conta/jogo. Contagem baseada na saida apos tentativa; sem verificacao de inventario.
-- Restaura os controles salvos. Anti-AFK tenta atuar ao ficar ocioso.

local player = game:GetService("Players").LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local COMPRA, VERIFICACAO, PAUSA_ROLAGEM = 0.15, 0.05, 0
local INTERVALO_COMPRA_PENDENTE, MAX_TENTATIVAS_COMPRA = 0.2, 10
local TIMEOUT_ROLAGEM = 6

local nomes = [[Ace|Ainz|Aizen|Akaza|Aki|Alucard|Aqua|Arima|Asta (Demon)|Asta|Bambietta|Broly|Byakuya|Choi Jong-In|Choso|Cid|Dabi|Deidara|Denji|Diablo|Diego|Dio (Heaven)|Dio (Vampire)|Dio|Enel|Eren|Erza|Esil|Fern|Frieren|Gaara|Gabimaru|Gilgamesh|Gogeta|Gojo (Awakened)|Gojo|Goku (Super)|Goku|Gon|Gray|Gremmy|Griffith (Dark)|Griffith (Light)|Griffith|Grimmjow|Guts (Berserk)|Guts|Gyro|Himmel|Hisoka|Ichigo (Chains)|Ichigo (Hollow)|Ichigo (Mugen)|Ichigo|Isagi (Ego)|Isagi|Itachi|Itadori|Jiji|Jinwoo (Monarch)|Jinwoo|Jiren|Johnny (Act 1)|Johnny (Act 2)|Johnny (Act 3)|Johnny (Act 4)|Joker|Jotaro (The World)|Jotaro|Juuzou|Kaiser|Kakashi|Kaneki (Centipede)|Kaneki (Investigator)|Kaneki|Kashimo|Kazuma|Kisame|Kobeni|Konan|Kuzan|Levi|Luffy (Joy)|Luffy|Madara|Makima|Maturo|Megumi|Megumin|Meliodas|Mikasa|Mikey|Miku|Mob (100%)|Mob|Naruto (Fox)|Naruto (SageMode)|Natsu|Nelliel|Ness|Power|Reze (Hybrid)|Reze|Rimuru|Rin|Ryusei|Sae|Sakura|Sanji|Sasuke (Susan)|Sasuke (Ts)|Sasuke|Shinra|Star|Stark|Sukuna (Heian)|Superstar|Teto|Toph|Touka|Ulqiorra|Unohana|Uryu|Valentine|Vegeta|Yamamoto|Yuno|Zeke|Zetsu]]
local catalogo = string.split(nomes, "|")
table.sort(catalogo)
local validos = {}
for _, nome in ipairs(catalogo) do validos[nome] = true end
local mutacoes = {"Normal", "Gold", "Diamond", "Blossom", "Genius", "Astral", "Honored", "Angelic", "Seraph"}

for _, nome in ipairs({"PainelCompraTeste", "PainelAutoBuy", "PainelCompraRolagem"}) do
    local antigo = pg:FindFirstChild(nome)
    if antigo then antigo:Destroy() end
end

local ativo, autoBuy, autoRoll, pequeno = true, false, false, false
local atual, compraPendente, rolagemPendente, ultimaFoto
local regras = {}
local observados = setmetatable({}, {__mode = "k"})
local enviados = setmetatable({}, {__mode = "k"})
local pulados = setmetatable({}, {__mode = "k"})
local ids = setmetatable({}, {__mode = "k"})
local proximoId, tentativas = 0, 0
local ultimaCompra, ultimaMudanca = -math.huge, os.clock()

local gui = Instance.new("ScreenGui")
gui.Name = "PainelCompraRolagem"
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000
gui.Parent = pg


-- Compact black/purple interface, with independent pages and searchable lists.
local UIS = game:GetService("UserInputService")
local white = Color3.fromRGB(241, 238, 255)
local muted = Color3.fromRGB(158, 151, 177)
local accent = Color3.fromRGB(161, 97, 255)
local stroke = Color3.fromRGB(77, 55, 102)
local connections = {}
local antiAfkEnabled = true
local autoReconnect = false
local webhookOn = false
local webhookUrl = ""
local webhookGeneration = 0
local history = {}
local currentPage = "Geral"
local draftCharacters, draftMutations = {}, {}
local pageFrames, tabButtons, switchRefresh = {}, {}, {}
local refreshRules, refreshDraft, closeList, updateUi
local saveConfig = function() end
local snapshotConfig, restoreConfig
local receivedCounts = {}
local savedConfig, storageIssue = {}, nil
local configReady = false
local configHttp = game:GetService("HttpService")
local configPath = "gzinpedo_" .. tostring(game.GameId or game.PlaceId or 0)
    .. "_" .. tostring(player.UserId) .. ".json"
local storageAvailable = type(readfile) == "function" and type(writefile) == "function"
local function validSet(input, allowed)
    local result = {}
    if type(input) == "table" then
        for name, value in pairs(input) do
            if allowed[name] and value == true then result[name] = true end
        end
    end
    return result
end
local mutationNames = {}
for _, mutation in ipairs(mutacoes) do mutationNames[mutation] = true end
if storageAvailable then
    local existsOk, exists = true, true
    if type(isfile) == "function" then existsOk, exists = pcall(isfile, configPath) end
    if existsOk and exists then
        local readOk, raw = pcall(readfile, configPath)
        if readOk then
            local decodedOk, decoded = pcall(function() return configHttp:JSONDecode(raw) end)
            if decodedOk and type(decoded) == "table" and decoded.version == 1 then
                savedConfig = decoded
            else storageIssue = "Arquivo de configuracao invalido; usando os padroes." end
        elseif type(isfile) == "function" then
            storageIssue = "Nao foi possivel ler as configuracoes salvas."
        end
    elseif not existsOk then storageIssue = "Nao foi possivel verificar as configuracoes salvas." end
else storageIssue = "Executor sem leitura/escrita de arquivos: configuracoes apenas nesta execucao." end
if type(savedConfig.rules) == "table" then
    for name, rule in pairs(savedConfig.rules) do
        if validos[name] then regras[name] = validSet(rule, mutationNames) end
    end
end
draftCharacters = validSet(savedConfig.characters, validos)
draftMutations = validSet(savedConfig.mutations, mutationNames)
if type(savedConfig.antiAfk) == "boolean" then antiAfkEnabled = savedConfig.antiAfk end
if type(savedConfig.counts) == "table" then
    for name, count in pairs(savedConfig.counts) do
        if validos[name] and type(count) == "number" and count >= 0 and count < 1e12 then
            receivedCounts[name] = math.floor(count)
        end
    end
end

local function criar(class, props, parent)
    local obj = Instance.new(class)
    for key, value in pairs(props) do obj[key] = value end
    obj.Parent = parent
    return obj
end
local function round(obj, radius)
    criar("UICorner", {CornerRadius = UDim.new(0, radius or 8)}, obj)
end
local function border(obj, transparency)
    criar("UIStroke", {Color = stroke, Thickness = 1, Transparency = transparency or 0.3}, obj)
end
local function label(parent, text, position, size, fontSize, color)
    return criar("TextLabel", {
        BackgroundTransparency = 1, Position = position, Size = size,
        Text = text, Font = Enum.Font.Gotham, TextSize = fontSize or 12,
        TextColor3 = color or white, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center, TextWrapped = true
    }, parent)
end
local function button(parent, text, position, size, purple)
    local b = criar("TextButton", {
        Position = position, Size = size, BackgroundColor3 = purple and accent or Color3.fromRGB(25, 21, 33),
        BackgroundTransparency = purple and 0.05 or 0.15, BorderSizePixel = 0,
        Text = text, TextColor3 = white, Font = Enum.Font.GothamMedium,
        TextSize = 12, TextWrapped = true, AutoButtonColor = true
    }, parent)
    round(b, 7)
    return b
end
local function padding(parent, left, right, top, bottom)
    criar("UIPadding", {PaddingLeft = UDim.new(0, left or 0), PaddingRight = UDim.new(0, right or 0),
        PaddingTop = UDim.new(0, top or 0), PaddingBottom = UDim.new(0, bottom or 0)}, parent)
end
local function vertical(parent, gap)
    criar("UIListLayout", {Padding = UDim.new(0, gap or 8), SortOrder = Enum.SortOrder.LayoutOrder}, parent)
end
local function scroller(parent, pos, size)
    return criar("ScrollingFrame", {
        Position = pos, Size = size, BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, ScrollBarImageColor3 = accent,
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y
    }, parent)
end
local function setCount(t)
    local n = 0
    for _, enabled in pairs(t) do if enabled then n = n + 1 end end
    return n
end
local function selectedMutations(rule)
    local names = {}
    for _, name in ipairs(mutacoes) do if rule and rule[name] then table.insert(names, name) end end
    return names
end

gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local painel = criar("Frame", {
    Name = "MainWindow", Size = UDim2.fromOffset(620, 420),
    BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.18,
    BorderSizePixel = 0, Active = true, ClipsDescendants = true
}, gui)
round(painel, 12)
border(painel, 0.1)
local uiScale = criar("UIScale", {Scale = 1}, painel)
local header = criar("Frame", {Name = "DragBar", Size = UDim2.new(1, 0, 0, 48),
    BackgroundTransparency = 1, Active = true}, painel)
local titulo = label(header, "gzin pedo", UDim2.fromOffset(16, 5), UDim2.new(1, -106, 0, 23), 17)
titulo.Font = Enum.Font.GothamBold
local subtitle = label(header, "DEFEAT ANIME RNG  /  CONTROLE", UDim2.fromOffset(16, 28), UDim2.new(1, -106, 0, 14), 9, muted)
local minimizar = button(header, "-", UDim2.new(1, -78, 0, 9), UDim2.fromOffset(29, 29))
local fechar = button(header, "X", UDim2.new(1, -42, 0, 9), UDim2.fromOffset(29, 29))
label(painel, "", UDim2.fromOffset(12, 48), UDim2.new(1, -24, 0, 1)).BackgroundColor3 = stroke
local divider = painel:GetChildren()[#painel:GetChildren()]
divider.BackgroundTransparency = 0.35

local corpo = criar("Frame", {Name = "Body", Position = UDim2.fromOffset(0, 54),
    Size = UDim2.new(1, 0, 1, -54), BackgroundTransparency = 1}, painel)
local sidebar = criar("Frame", {Position = UDim2.fromOffset(12, 7), Size = UDim2.fromOffset(124, 287),
    BackgroundColor3 = Color3.fromRGB(14, 10, 20), BackgroundTransparency = 0.22, BorderSizePixel = 0}, corpo)
round(sidebar, 9)
local nav = criar("Frame", {Position = UDim2.fromOffset(7, 10), Size = UDim2.new(1, -14, 0, 190),
    BackgroundTransparency = 1}, sidebar)
vertical(nav, 5)
local ruleBadge = label(sidebar, "0 personagens\n0 combinacoes", UDim2.fromOffset(10, 222), UDim2.new(1, -20, 0, 40), 11, muted)
label(sidebar, "COMPRA 0,15s\nPAUSA EXTRA 0s", UDim2.fromOffset(10, 258), UDim2.new(1, -20, 0, 25), 9, muted)

local function page(name, title, description)
    local p = criar("Frame", {Name = name, Position = UDim2.fromOffset(150, 7),
        Size = UDim2.new(1, -164, 0, 287), BackgroundTransparency = 1, Visible = false}, corpo)
    label(p, title, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 25), 17).Font = Enum.Font.GothamBold
    label(p, description, UDim2.fromOffset(0, 27), UDim2.new(1, 0, 0, 30), 11, muted)
    pageFrames[name] = p
    return p
end
local generalPage = page("Geral", "Automacao", "Ligue os controles abaixo. Fique perto da sua maquina.")
local buyPage = page("Compras", "Compras especificas", "Selecione personagens e mutacoes. As regras ficam salvas automaticamente neste dispositivo.")
local rulesPage = page("Regras", "Regras de compra", "Cada personagem pode ter suas proprias mutacoes. Toque em Editar para ajustar.")
local activityPage = page("Atividade", "Atividade", "Mensagens recentes e tentativas enviadas. A saida do boneco nao verifica o inventario.")
local discordPage = page("Discord", "Notificacoes no Discord", "Avisa quando o alvo sai da maquina apos a tentativa. Isso nao confirma a entrada no inventario.")
local configPage = page("Config", "Exportar / Importar", "Transfira suas configuracoes entre dispositivos. O codigo inclui seu webhook: mantenha-o privado.")
local function selectPage(name)
    currentPage = name
    saveConfig()
    if closeList then closeList() end
    for key, frame in pairs(pageFrames) do frame.Visible = key == name end
    for key, b in pairs(tabButtons) do
        b.BackgroundColor3 = key == name and accent or Color3.fromRGB(20, 16, 27)
        b.BackgroundTransparency = key == name and 0.15 or 1
        b.TextColor3 = key == name and white or muted
    end
end
nav.Size = UDim2.new(1, -14, 0, 211)
for i, name in ipairs({"Geral", "Compras", "Regras", "Atividade", "Discord", "Config"}) do
    local b = button(nav, name, UDim2.new(), UDim2.new(1, 0, 0, 31))
    b.LayoutOrder = i
    tabButtons[name] = b
    b.Activated:Connect(function() selectPage(name) end)
end

local footer = criar("Frame", {Position = UDim2.fromOffset(12, 305), Size = UDim2.new(1, -24, 0, 49),
    BackgroundColor3 = Color3.fromRGB(12, 8, 17), BackgroundTransparency = 0.15, BorderSizePixel = 0}, corpo)
round(footer, 8)
local status = label(footer, "Procurando sua maquina...", UDim2.fromOffset(10, 4), UDim2.new(1, -20, 0, 21), 10, muted)
local mensagem = label(footer, "Configure as compras na aba Compras.", UDim2.fromOffset(10, 27), UDim2.new(1, -20, 0, 18), 10)
mensagem.TextTruncate = Enum.TextTruncate.AtEnd
mensagem.TextWrapped = false

local logScroll = scroller(activityPage, UDim2.fromOffset(0, 63), UDim2.new(1, 0, 1, -63))
local logText = label(logScroll, "Nenhuma atividade ainda.", UDim2.new(), UDim2.new(1, -9, 0, 0), 11, muted)
logText.AutomaticSize = Enum.AutomaticSize.Y
logText.TextYAlignment = Enum.TextYAlignment.Top
local lastMessage
local function informar(text)
    if not ativo then return end
    mensagem.Text = text
    if text == lastMessage then return end
    lastMessage = text
    table.insert(history, os.date("%H:%M:%S") .. "  " .. text)
    while #history > 45 do table.remove(history, 1) end
    logText.Text = table.concat(history, "\n\n")
end

local function toggleRow(parent, y, name, description, getter, callback)
    local row = criar("Frame", {Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 49),
        BackgroundColor3 = Color3.fromRGB(20, 16, 27), BackgroundTransparency = 0.15, BorderSizePixel = 0}, parent)
    round(row, 8)
    label(row, name, UDim2.fromOffset(12, 3), UDim2.new(1, -86, 0, 19), 13).Font = Enum.Font.GothamMedium
    label(row, description, UDim2.fromOffset(12, 22), UDim2.new(1, -86, 0, 24), 10, muted)
    local track = button(row, "", UDim2.new(1, -57, 0, 5), UDim2.fromOffset(44, 24))
    round(track, 12)
    local knob = criar("Frame", {Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(3, 3),
        BackgroundColor3 = white, BorderSizePixel = 0}, track)
    round(knob, 9)
    local caption = label(row, "OFF", UDim2.new(1, -58, 0, 31), UDim2.fromOffset(46, 14), 9, muted)
    caption.TextXAlignment = Enum.TextXAlignment.Center
    local function refresh()
        local on = getter()
        track.BackgroundColor3 = on and accent or Color3.fromRGB(56, 50, 65)
        knob.Position = UDim2.fromOffset(on and 23 or 3, 3)
        caption.Text = on and "ON" or "OFF"
        caption.TextColor3 = on and accent or muted
    end
    track.Activated:Connect(callback)
    table.insert(switchRefresh, refresh)
    refresh()
end
local changeBuy, changeRoll
toggleRow(generalPage, 66, "Auto Buy", "Compra apenas as combinacoes das suas regras.", function() return autoBuy end,
    function() if changeBuy then changeBuy() end end)
toggleRow(generalPage, 121, "Auto Roll", "Rola depois de verificar os alvos e aguardar as compras.", function() return autoRoll end,
    function() if changeRoll then changeRoll() end end)
toggleRow(generalPage, 176, "Anti-AFK", "Tenta simular atividade quando voce fica inativo.", function() return antiAfkEnabled end,
    function()
        antiAfkEnabled = not antiAfkEnabled
        saveConfig()
        for _, refresh in ipairs(switchRefresh) do refresh() end
        informar(antiAfkEnabled and "Anti-AFK habilitado; aguardando inatividade." or "Anti-AFK desligado.")
    end)

toggleRow(generalPage, 231, "Auto Reconnect", "Tenta voltar ao jogo quando a conexao cai.", function() return autoReconnect end,
    function()
        autoReconnect = not autoReconnect
        saveConfig()
        for _, refresh in ipairs(switchRefresh) do refresh() end
        informar(autoReconnect and "Auto Reconnect ligado; aguardando queda de conexao." or "Auto Reconnect desligado.")
    end)

-- A URL e salva apenas no arquivo local do executor, nunca no codigo publicado.
local webhookInput = criar("TextBox", {
    Name = "WebhookInput", Position = UDim2.fromOffset(0, 66), Size = UDim2.new(1, 0, 0, 36),
    BackgroundColor3 = Color3.fromRGB(29, 23, 38), BorderSizePixel = 0,
    TextColor3 = white, PlaceholderText = "Cole a URL do webhook aqui", Text = "",
    Font = Enum.Font.Gotham, TextSize = 11, ClearTextOnFocus = false,
    TextXAlignment = Enum.TextXAlignment.Left
}, discordPage)
round(webhookInput, 7)
padding(webhookInput, 10, 10)
local applyWebhook = button(discordPage, "Aplicar URL", UDim2.fromOffset(0, 111), UDim2.new(0.34, -5, 0, 31), true)
local testWebhook = button(discordPage, "Testar envio", UDim2.new(0.34, 3, 0, 111), UDim2.new(0.34, -6, 0, 31))
local clearWebhook = button(discordPage, "Apagar URL", UDim2.new(0.68, 3, 0, 111), UDim2.new(0.32, -3, 0, 31))
local discordStatus = label(discordPage, "Sem webhook. Cole a URL e toque em Aplicar URL.\nO endereco sera salvo localmente no executor.",
    UDim2.fromOffset(0, 225), UDim2.new(1, 0, 0, 56), 10, muted)
local discordQueue, discordWorking = {}, false
local httpService = game:GetService("HttpService")

local function statusDiscord(text)
    if ativo then discordStatus.Text = text end
end
local function validateWebhook(value)
    local clean = value:match("^%s*(.-)%s*$")
    local base, query = clean:match("^([^?]+)%??(.*)$")
    if not base then return nil end
    local id, token
    for _, host in ipairs({"discord%.com", "discordapp%.com"}) do
        id, token = base:match("^https://" .. host .. "/api/webhooks/(%d+)/([%w_%-]+)$")
        if not id then id, token = base:match("^https://" .. host .. "/api/v%d+/webhooks/(%d+)/([%w_%-]+)$") end
        if id then break end
    end
    if not id then return nil end
    local thread
    if query ~= "" then
        for parameter in query:gmatch("[^&]+") do
            local key, v = parameter:match("^([^=]+)=(.*)$")
            if key == "thread_id" and v:match("^%d+$") then thread = v
            elseif key ~= "wait" or (v ~= "true" and v ~= "false") then return nil end
        end
    end
    return "https://discord.com/api/webhooks/" .. id .. "/" .. token
        .. "?wait=true" .. (thread and ("&thread_id=" .. thread) or "")
end
local function httpRequestFunction()
    local fn = request or http_request or (http and http.request) or (syn and syn.request)
    return type(fn) == "function" and fn or nil
end
local function startDiscordWorker()
    if discordWorking then return end
    discordWorking = true
    task.spawn(function()
        local workerOk = pcall(function()
            while ativo and #discordQueue > 0 do
                local item = table.remove(discordQueue, 1)
                if item.generation == webhookGeneration and (item.test or webhookOn) then
                    local req = httpRequestFunction()
                    if not req then
                        statusDiscord("Requisicao HTTP indisponivel no executor.")
                    else
                        local encodedOk, body = pcall(function()
                            return httpService:JSONEncode({
                                username = "gzin pedo", content = item.message,
                                allowed_mentions = {parse = {}}
                            })
                        end)
                        if not encodedOk then
                            statusDiscord("Nao foi possivel preparar a mensagem.")
                        else
                            for attempt = 1, 3 do
                                if not ativo or item.generation ~= webhookGeneration
                                    or (not item.test and not webhookOn) then break end
                                local ok, response = pcall(function()
                                    return req({Url = item.url, Method = "POST",
                                        Headers = {["Content-Type"] = "application/json"}, Body = body})
                                end)
                                if not ativo then break end
                                if item.generation ~= webhookGeneration then break end
                                -- Do not log the raw request/response: it may contain the URL token.
                                if not ok or type(response) ~= "table" then
                                    statusDiscord("Falha de rede no envio. Use Testar envio para conferir.")
                                    break
                                end
                                local code = tonumber(response.StatusCode or response.Status or response.status_code)
                                if code and code >= 200 and code < 300 then
                                    statusDiscord(item.test and "Teste enviado ao Discord." or "Aviso enviado ao Discord.")
                                    break
                                elseif code == 429 and attempt < 3 then
                                    local seconds = 1
                                    pcall(function()
                                        local decoded = httpService:JSONDecode(response.Body or "{}")
                                        seconds = tonumber(decoded.retry_after) or seconds
                                    end)
                                    if seconds > 60 then
                                        statusDiscord("Discord limitou os envios. Tente novamente mais tarde.")
                                        break
                                    end
                                    statusDiscord("Discord limitou os envios. Aguardando para tentar novamente.")
                                    task.wait(math.max(0.5, seconds) + 0.1)
                                else
                                    statusDiscord("Discord recusou o envio (HTTP " .. tostring(code or "desconhecido") .. "). Confira o webhook.")
                                    break
                                end
                            end
                        end
                    end
                    if ativo and #discordQueue > 0 then task.wait(0.6) end
                end
            end
        end)
        discordWorking = false
        if not workerOk and ativo then statusDiscord("Falha interna no envio. Teste o webhook novamente.") end
    end)
end
local function queueDiscord(message, isTest)
    if not ativo or webhookUrl == "" or (not isTest and not webhookOn) then return false end
    if #discordQueue >= 25 then statusDiscord("Fila de avisos cheia. Um novo aviso nao foi enfileirado."); return false end
    table.insert(discordQueue, {url = webhookUrl, generation = webhookGeneration,
        message = message, test = isTest == true})
    statusDiscord("Mensagem aguardando envio...")
    startDiscordWorker()
    return true
end
toggleRow(discordPage, 153, "Notificar alvos", "Avisa apos a saida de um alvo selecionado. Nao verifica inventario.", function() return webhookOn end,
    function()
        if not webhookOn and webhookUrl == "" then
            statusDiscord("Configure e aplique a URL primeiro.")
            return
        end
        webhookOn = not webhookOn
        saveConfig()
        for _, refresh in ipairs(switchRefresh) do refresh() end
        statusDiscord(webhookOn and "Notificacoes ligadas para os alvos selecionados." or "Notificacoes desligadas.")
    end)
applyWebhook.Activated:Connect(function()
    local validated = validateWebhook(webhookInput.Text)
    if not validated then
        statusDiscord("URL invalida. Use um webhook https://discord.com/api/webhooks/...")
        return
    end
    webhookGeneration = webhookGeneration + 1
    discordQueue = {}
    webhookUrl = validated
    saveConfig()
    webhookInput.Text = ""
    webhookInput.PlaceholderText = "Webhook configurado (URL oculta). Cole outra para trocar."
    statusDiscord("Webhook salvo neste dispositivo. Toque em Testar envio e ligue Notificar alvos.")
end)
testWebhook.Activated:Connect(function()
    if webhookUrl == "" then statusDiscord("Aplique a URL antes de testar."); return end
    queueDiscord("Teste do painel gzin pedo.\nO webhook recebeu uma mensagem de teste; nenhum personagem foi comprado por este teste.", true)
end)
clearWebhook.Activated:Connect(function()
    webhookGeneration = webhookGeneration + 1
    webhookUrl, webhookOn, discordQueue = "", false, {}
    saveConfig()
    webhookInput.Text = ""
    webhookInput.PlaceholderText = "Cole a URL do webhook aqui"
    for _, refresh in ipairs(switchRefresh) do refresh() end
    statusDiscord("Webhook apagado. Notificacoes desligadas.")
end)
local function notificarDiscord(pending)
    if pending.discordNotified then return end
    pending.discordNotified = true
    local details = pending.details
    if not details then return end
    receivedCounts[details.nome] = (receivedCounts[details.nome] or 0) + 1
    saveConfig()
    if not webhookOn then return end
    queueDiscord(table.concat({
        "Personagem: " .. details.nome,
        "Mutação: " .. details.mutacao,
        "Horário (Brasília): " .. os.date("!%d/%m/%Y %H:%M:%S", os.time() - 3 * 60 * 60),
        "Quantidade do personagem: " .. tostring(receivedCounts[details.nome])
    }, "\n"), false)
end
gui.Destroying:Connect(function()
    saveConfig()
    configReady = false
    webhookGeneration = webhookGeneration + 1
    webhookUrl, webhookOn, discordQueue = "", false, {}
end)

-- Searchable multi-select popup. No selections change until Concluir.
local overlay = criar("TextButton", {Name = "ListOverlay", Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35,
    Text = "", AutoButtonColor = false, BorderSizePixel = 0, ZIndex = 20, Visible = false}, painel)
local modal = criar("Frame", {Position = UDim2.fromOffset(145, 43), Size = UDim2.new(1, -159, 1, -57),
    BackgroundColor3 = Color3.fromRGB(12, 8, 18), BackgroundTransparency = 0.02,
    BorderSizePixel = 0, Active = true, ZIndex = 21}, overlay)
round(modal, 10)
border(modal, 0.1)
local modalTitle = label(modal, "Selecionar", UDim2.fromOffset(12, 8), UDim2.new(1, -63, 0, 24), 14)
modalTitle.ZIndex = 22
local modalCancel = button(modal, "X", UDim2.new(1, -39, 0, 7), UDim2.fromOffset(28, 27))
modalCancel.ZIndex = 22
local modalSearch = criar("TextBox", {Position = UDim2.fromOffset(12, 42), Size = UDim2.new(1, -24, 0, 33),
    BackgroundColor3 = Color3.fromRGB(29, 23, 38), BorderSizePixel = 0, TextColor3 = white,
    PlaceholderText = "Buscar na lista...", Text = "", TextSize = 12, Font = Enum.Font.Gotham,
    ClearTextOnFocus = false, ZIndex = 22}, modal)
round(modalSearch, 7)
local selectAll = button(modal, "Marcar todos", UDim2.fromOffset(12, 83), UDim2.new(0.5, -16, 0, 27))
local clearAll = button(modal, "Limpar", UDim2.new(0.5, 4, 0, 83), UDim2.new(0.5, -16, 0, 27))
selectAll.ZIndex, clearAll.ZIndex = 22, 22
local options = scroller(modal, UDim2.fromOffset(12, 118), UDim2.new(1, -24, 1, -171))
options.ZIndex = 22
vertical(options, 4)
local modalDone = button(modal, "Concluir", UDim2.new(0, 12, 1, -43), UDim2.new(1, -24, 0, 32), true)
modalDone.ZIndex = 22
local modalItems, modalRows, modalSelection, modalCommit = {}, {}, {}, nil
closeList = function()
    overlay.Visible = false
    modalCommit = nil
    modalSearch:ReleaseFocus()
end
local function paintOptions()
    local count = setCount(modalSelection)
    modalDone.Text = "Concluir  (" .. count .. " selecionados)"
    local query = modalSearch.Text:lower()
    for name, b in pairs(modalRows) do
        b.Text = (modalSelection[name] and "[x]  " or "[ ]  ") .. name
        b.BackgroundColor3 = modalSelection[name] and Color3.fromRGB(73, 39, 111) or Color3.fromRGB(25, 20, 33)
        b.Visible = name:lower():find(query, 1, true) ~= nil
    end
end
local function openList(title, items, selected, commit)
    modalTitle.Text, modalCommit = title, commit
    modalItems, modalSelection, modalRows = items, {}, {}
    for name, enabled in pairs(selected) do if enabled then modalSelection[name] = true end end
    for _, obj in ipairs(options:GetChildren()) do if obj:IsA("TextButton") then obj:Destroy() end end
    for i, name in ipairs(items) do
        local b = button(options, "", UDim2.new(), UDim2.new(1, -6, 0, 33))
        b.LayoutOrder, b.ZIndex = i, 23
        modalRows[name] = b
        b.TextXAlignment = Enum.TextXAlignment.Left
        padding(b, 10, 4)
        b.Activated:Connect(function()
            modalSelection[name] = not modalSelection[name]
            paintOptions()
        end)
    end
    modalSearch.Text = ""
    options.CanvasPosition = Vector2.zero
    overlay.Visible = true
    paintOptions()
end
modalSearch:GetPropertyChangedSignal("Text"):Connect(paintOptions)
modalCancel.Activated:Connect(closeList)
overlay.Activated:Connect(closeList)
selectAll.Activated:Connect(function()
    for _, name in ipairs(modalItems) do modalSelection[name] = true end
    paintOptions()
end)
clearAll.Activated:Connect(function() modalSelection = {}; paintOptions() end)
modalDone.Activated:Connect(function()
    local chosen, commit = {}, modalCommit
    for name, on in pairs(modalSelection) do if on then chosen[name] = true end end
    closeList()
    if commit then commit(chosen) end
end)

local charDropdown = button(buyPage, "Personagens  /  Abrir lista  v", UDim2.fromOffset(0, 66), UDim2.new(1, 0, 0, 39))
local mutationDropdown = button(buyPage, "Mutacoes  /  Abrir lista  v", UDim2.fromOffset(0, 114), UDim2.new(1, 0, 0, 39))
local draftSummary = label(buyPage, "Nenhuma combinacao selecionada.", UDim2.fromOffset(0, 162), UDim2.new(1, 0, 0, 30), 11, muted)
local applyRules = button(buyPage, "Salvar combinacoes", UDim2.fromOffset(0, 202), UDim2.new(0.64, -5, 0, 34), true)
local cancelDraft = button(buyPage, "Limpar selecao", UDim2.new(0.64, 5, 0, 202), UDim2.new(0.36, -5, 0, 34))
label(buyPage, "Salvar substitui as mutacoes dos personagens escolhidos. As outras regras continuam iguais.",
    UDim2.fromOffset(0, 244), UDim2.new(1, 0, 0, 38), 10, muted)
refreshDraft = function()
    local nc, nm = setCount(draftCharacters), setCount(draftMutations)
    local only
    for name, selected in pairs(draftCharacters) do if selected then only = name end end
    charDropdown.Text = "Personagens: " .. (nc == 1 and only or (nc .. " selecionados")) .. "   v"
    local list = selectedMutations(draftMutations)
    local desc = nm > 0 and table.concat(list, ", ") or "nenhuma"
    if #desc > 43 then desc = nm .. " selecionadas" end
    mutationDropdown.Text = "Mutacoes: " .. desc .. "   v"
    draftSummary.Text = nc .. " personagens x " .. nm .. " mutacoes = " .. nc * nm .. " combinacoes"
end
charDropdown.Activated:Connect(function()
    openList("Personagens (129)", catalogo, draftCharacters, function(chosen)
        draftCharacters = chosen
        saveConfig()
        refreshDraft()
    end)
end)
mutationDropdown.Activated:Connect(function()
    openList("Mutacoes", mutacoes, draftMutations, function(chosen)
        draftMutations = chosen
        saveConfig()
        refreshDraft()
    end)
end)
local rulesScroll = scroller(rulesPage, UDim2.fromOffset(0, 64), UDim2.new(1, 0, 1, -64))
vertical(rulesScroll, 7)
refreshRules = function()
    for _, obj in ipairs(rulesScroll:GetChildren()) do if obj:IsA("Frame") or obj:IsA("TextLabel") then obj:Destroy() end end
    local count = 0
    for i, name in ipairs(catalogo) do
        local muts = selectedMutations(regras[name])
        if #muts > 0 then
            count = count + 1
            local row = criar("Frame", {Size = UDim2.new(1, -7, 0, 69), LayoutOrder = i,
                BackgroundColor3 = Color3.fromRGB(24, 18, 32), BackgroundTransparency = 0.15, BorderSizePixel = 0}, rulesScroll)
            round(row, 7)
            label(row, name, UDim2.fromOffset(10, 5), UDim2.new(1, -133, 0, 22), 12).Font = Enum.Font.GothamMedium
            label(row, table.concat(muts, ", "), UDim2.fromOffset(10, 29), UDim2.new(1, -133, 0, 32), 10, muted)
            local edit = button(row, "Editar", UDim2.new(1, -116, 0, 9), UDim2.fromOffset(49, 48))
            local remove = button(row, "Excluir", UDim2.new(1, -61, 0, 9), UDim2.fromOffset(49, 48))
            edit.Activated:Connect(function()
                draftCharacters, draftMutations = {[name] = true}, {}
                for _, m in ipairs(mutacoes) do if regras[name] and regras[name][m] then draftMutations[m] = true end end
                refreshDraft()
                saveConfig()
                selectPage("Compras")
            end)
            remove.Activated:Connect(function()
                regras[name] = nil
                informar("Regra removida: " .. name)
                -- atualizar is defined below, so refresh through a shared callback.
                if updateUi then updateUi() end
            end)
        end
    end
    if count == 0 then
        local empty = label(rulesScroll, "Nenhuma regra salva. Abra a aba Compras para adicionar personagens e mutacoes.",
            UDim2.new(), UDim2.new(1, -10, 0, 65), 12, muted)
        empty.LayoutOrder = 1
    end
end

local function atualizar()
    local characters, combinations = 0, 0
    for _, rule in pairs(regras) do
        local n = #selectedMutations(rule)
        if n > 0 then characters, combinations = characters + 1, combinations + n end
    end
    ruleBadge.Text = characters .. " personagens\n" .. combinations .. " combinacoes"
    subtitle.Text = (autoBuy and "BUY ON" or "BUY OFF") .. "  /  " .. (autoRoll and "ROLL ON" or "ROLL OFF")
    for _, refresh in ipairs(switchRefresh) do refresh() end
    refreshRules()
    saveConfig()
end
updateUi = atualizar
applyRules.Activated:Connect(function()
    local nc, nm = setCount(draftCharacters), setCount(draftMutations)
    if nc == 0 or nm == 0 then informar("Escolha ao menos um personagem e uma mutacao."); return end
    for name, selected in pairs(draftCharacters) do
        if selected and validos[name] then
            local rule = {}
            for _, mutation in ipairs(mutacoes) do if draftMutations[mutation] then rule[mutation] = true end end
            regras[name] = rule
        end
    end
    atualizar()
    informar("Salvo: " .. nc .. " personagens / " .. nc * nm .. " combinacoes.")
    selectPage("Regras")
end)
cancelDraft.Activated:Connect(function()
    draftCharacters, draftMutations = {}, {}
    saveConfig()
    refreshDraft()
end)

-- Responsive scale and draggable header (mouse or touch).
local moved = false
local function viewport()
    local camera = workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(850, 500)
end
local function fit(center)
    local vp = viewport()
    local width, height = pequeno and 230 or 620, pequeno and 44 or 420
    local scale = math.min(1, (vp.X - 24) / width, (vp.Y - 24) / height)
    uiScale.Scale = math.max(0.1, scale)
    painel.Size = UDim2.fromOffset(width, height)
    local x, y = painel.Position.X.Offset, painel.Position.Y.Offset
    if center then x, y = (vp.X - width * uiScale.Scale) / 2, (vp.Y - height * uiScale.Scale) / 2 end
    painel.Position = UDim2.fromOffset(math.clamp(x, 8, math.max(8, vp.X - width * uiScale.Scale - 8)),
        math.clamp(y, 8, math.max(8, vp.Y - height * uiScale.Scale - 8)))
end
local dragging, dragStart, dragPosition, dragInput, endDragConnection
header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging, dragStart, dragPosition = true, input.Position, painel.Position
        dragInput = input.UserInputType == Enum.UserInputType.Touch and input or nil
        if endDragConnection then endDragConnection:Disconnect() end
        endDragConnection = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false; fit(false); saveConfig() end
        end)
    end
end)
table.insert(connections, UIS.InputChanged:Connect(function(input)
    if dragging and (input == dragInput or (not dragInput and input.UserInputType == Enum.UserInputType.MouseMovement)) then
        local delta = input.Position - dragStart
        painel.Position = UDim2.fromOffset(dragPosition.X.Offset + delta.X, dragPosition.Y.Offset + delta.Y)
        moved = true
    end
end))
local viewportConnection
local function watchCamera()
    if viewportConnection then viewportConnection:Disconnect() end
    local camera = workspace.CurrentCamera
    if camera then viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function() fit(not moved) end) end
    fit(not moved)
end
table.insert(connections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera))
minimizar.Activated:Connect(function()
    pequeno = not pequeno
    closeList()
    corpo.Visible = not pequeno
    subtitle.Visible = not pequeno
    titulo.Position = UDim2.fromOffset(16, pequeno and 10 or 5)
    minimizar.Text = pequeno and "+" or "-"
    fit(false)
    saveConfig()
end)
gui.Destroying:Connect(function()
    ativo, autoBuy, autoRoll = false, false, false
    for _, connection in ipairs(connections) do connection:Disconnect() end
    if viewportConnection then viewportConnection:Disconnect() end
    if endDragConnection then endDragConnection:Disconnect() end
end)
watchCamera()
refreshDraft()
selectPage("Geral")

local function maquina()
    local bases = workspace:FindFirstChild("Bases")
    if not bases then return nil end
    for _, base in ipairs(bases:GetChildren()) do
        local owner = base:FindFirstChild("Owner")
        if owner and owner:IsA("ValueBase") then
            local valor = owner.Value
            if valor == player or tostring(valor) == tostring(player.UserId)
                or tostring(valor) == player.Name then
                return base:FindFirstChild("RollStation")
            end
        end
    end
end
local function texto(modelo, campo)
    local head = modelo:FindFirstChild("Head")
    local holder = head and head:FindFirstChild(campo)
    local desc = holder and holder:FindFirstChild("Desc")
    if desc and (desc:IsA("TextLabel") or desc:IsA("TextButton")) then
        return desc.Text:gsub("<[^>]+>", ""):match("^%s*(.-)%s*$")
    end
    return ""
end
local function ler(modelo)
    if not modelo:IsA("Model") or not modelo:FindFirstChild("Head") then return nil end
    local nome = modelo:GetAttribute("UnitName")
    if type(nome) ~= "string" or nome == "" then
        if not validos[modelo.Name] then return nil end
        nome = modelo.Name
    end
    local mutacao = texto(modelo, "Mutation")
    local lower = mutacao:lower()
    if lower == "" or lower == "normal" or lower == "no mutation" then
        mutacao = "Normal"
    else
        for _, m in ipairs(mutacoes) do
            if m:lower() == lower then mutacao = m; break end
        end
    end
    local prompt
    for _, obj in ipairs(modelo:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and obj.Enabled then
            local acao = obj.ActionText:lower():match("^%s*(.-)%s*$")
            if acao == "collect" or acao == "coletar" then prompt = obj; break end
        end
    end
    local preco = texto(modelo, "Price")
    return {modelo = modelo, nome = nome, mutacao = mutacao, preco = preco, prompt = prompt,
        assinatura = table.concat({nome, mutacao, preco, tostring(modelo:GetAttribute("UnitId") or "")}, "|")}
end
local function selecionado(d)
    return regras[d.nome] and regras[d.nome][d.mutacao] == true
end
local function alvoAtivo(d)
    return selecionado(d) and not (pulados[d.modelo] and pulados[d.modelo][d.assinatura])
end
-- Observe the prompts that Roblox itself displays to this player.
-- Do not alter activation distances, Enabled, or warning prompts.
local promptsVisiveis = setmetatable({}, {__mode = "k"})
pcall(function()
    local service = game:GetService("ProximityPromptService")
    table.insert(connections, service.PromptShown:Connect(function(prompt)
        promptsVisiveis[prompt] = true
    end))
    table.insert(connections, service.PromptHidden:Connect(function(prompt)
        promptsVisiveis[prompt] = nil
    end))
end)
local function posicaoPrompt(prompt)
    local parent = prompt and prompt.Parent
    if not parent then return nil end
    if parent:IsA("Attachment") then return parent.WorldPosition end
    if parent:IsA("BasePart") then return parent.Position end
    if parent:IsA("Model") then
        if parent.PrimaryPart then return parent.PrimaryPart.Position end
        return parent:GetPivot().Position
    end
end
local function acessoPrompt(prompt)
    if not prompt then return false, "Botao Roll nao encontrado na sua maquina." end
    if not prompt.Enabled then return false, "Botao Roll desabilitado pelo jogo. Aguarde ou confira o aviso na tela." end
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local head = character and character:FindFirstChild("Head")
    if not root and not head then return false, "Aguarde seu personagem carregar." end
    if promptsVisiveis[prompt] then return true end
    local pos = posicaoPrompt(prompt)
    if not pos then return false, "Nao foi possivel localizar a posicao do botao Roll." end
    local distance = math.huge
    if root then distance = math.min(distance, (root.Position - pos).Magnitude) end
    if head then distance = math.min(distance, (head.Position - pos).Magnitude) end
    if distance <= prompt.MaxActivationDistance then return true end
    return false, string.format("Roll: distancia %.1f / alcance %.1f. Aproxime-se do botao.", distance, prompt.MaxActivationDistance)
end
local function perto(prompt)
    local ok = acessoPrompt(prompt)
    return ok
end
local function promptRolar(station)
    local best, bestScore
    for _, prompt in ipairs(station:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") then
            local action = prompt.ActionText:gsub("<[^>]+>", ""):lower():match("^%s*(.-)%s*$")
            local name = prompt.Name:lower()
            if (action == "roll" or action == "rolar") and not name:find("auto", 1, true) then
                local score = prompt.Enabled and 100 or 0
                if promptsVisiveis[prompt] then score = score + 1000 end
                if perto(prompt) then score = score + 20 end
                if name == "proximityprompt" then score = score + 2 end
                if not bestScore or score > bestScore then best, bestScore = prompt, score end
            end
        end
    end
    return best
end
local function estadoRolagem(station, foto)
    -- Some rolls reuse the same models. Machine counters are additional evidence.
    local counters = {}
    for _, branchName in ipairs({"pity", "Button"}) do
        local branch = station:FindFirstChild(branchName)
        if branch then
            for _, obj in ipairs(branch:GetDescendants()) do
                if (obj:IsA("TextLabel") or obj:IsA("TextButton"))
                    and (obj.Name == "CountLabel" or obj.Name == "LuckLabel") then
                    table.insert(counters, obj.Text)
                end
            end
        end
    end
    table.sort(counters)
    return foto .. "|CONTADORES|" .. table.concat(counters, "|")
end
changeBuy = function()
    if autoBuy then
        autoBuy, autoRoll = false, false
        rolagemPendente = nil
        informar("Auto Buy e Auto Roll desligados.")
        atualizar()
        return
    end
    if type(fireproximityprompt) ~= "function" then informar("Funcao de interacao indisponivel."); return end
    local temRegra = false
    for _, regra in pairs(regras) do
        for _, marcado in pairs(regra) do
            if marcado then temRegra = true end
        end
    end
    if not temRegra then informar("Marque uma mutacao de pelo menos um personagem."); return end
    autoBuy = true
    informar("Auto Buy ligado.")
    atualizar()
end
changeRoll = function()
    if autoRoll then
        autoRoll = false
        rolagemPendente = nil
        informar("Auto Roll desligado. Auto Buy permanece como estava.")
    elseif not autoBuy then informar("Ligue o Auto Buy primeiro."); return
    elseif compraPendente then informar("Aguarde a saida do boneco da compra pendente."); return
    else
        autoRoll = true
        ultimaMudanca = os.clock()
        informar("Auto Roll ligado. Fique proximo da maquina.")
    end
    atualizar()
end
-- Anti-AFK: uma tentativa de simular atividade ao receber Idled.
-- A permissao do VirtualUser depende do executor. Nao impede suspensao do app.
local conexaoAntiAfk
local antiAfkOcupado = false
local antiAfkEstado = "aguardando inatividade"
local antiAfkOk, antiAfkErro = pcall(function()
    local virtualUser = game:GetService("VirtualUser")
    conexaoAntiAfk = player.Idled:Connect(function()
        if not ativo or not antiAfkEnabled or antiAfkOcupado then return end
        antiAfkOcupado = true
        local sucesso, falha = pcall(function()
            virtualUser:CaptureController()
            virtualUser:ClickButton2(Vector2.new(0, 0))
        end)
        antiAfkOcupado = false
        if sucesso then
            antiAfkEstado = "atividade simulada"
        else
            antiAfkEstado = "falhou; veja console"
            warn("[Anti-AFK]", falha)
        end
    end)
end)
if not antiAfkOk then
    antiAfkEstado = "indisponivel"
    warn("[Anti-AFK]", antiAfkErro)
end
gui.Destroying:Connect(function()
    ativo, autoBuy, autoRoll = false, false, false
    if conexaoAntiAfk then conexaoAntiAfk:Disconnect() end
end)
fechar.Activated:Connect(function()
    gui:Destroy()
end)
-- Um mesmo formato atende o salvamento local e a transferencia entre dispositivos.
snapshotConfig = function()
    return {
        version = 1, rules = regras, characters = draftCharacters, mutations = draftMutations,
        autoBuy = autoBuy, autoRoll = autoRoll, antiAfk = antiAfkEnabled, autoReconnect = autoReconnect,
        webhookUrl = webhookUrl, webhookOn = webhookOn, counts = receivedCounts,
        page = currentPage, minimized = pequeno,
        position = {x = painel.Position.X.Offset, y = painel.Position.Y.Offset}
    }
end
saveConfig = function()
    if not configReady or not storageAvailable then return end
    local ok = pcall(function() writefile(configPath, configHttp:JSONEncode(snapshotConfig())) end)
    if not ok then
        storageIssue = "Falha ao salvar configuracoes no dispositivo."
        informar(storageIssue)
    end
end
restoreConfig = function(data)
    configReady = false
    autoBuy, autoRoll = false, false
    compraPendente, rolagemPendente, ultimaFoto = nil, nil, nil
    observados = setmetatable({}, {__mode = "k"})
    enviados = setmetatable({}, {__mode = "k"})
    pulados = setmetatable({}, {__mode = "k"})
    regras, receivedCounts = {}, {}
    for name, rule in pairs(type(data.rules) == "table" and data.rules or {}) do
        if validos[name] then regras[name] = validSet(rule, mutationNames) end
    end
    for name, count in pairs(type(data.counts) == "table" and data.counts or {}) do
        if validos[name] and type(count) == "number" and count >= 0 and count < 1e12 then
            receivedCounts[name] = math.floor(count)
        end
    end
    draftCharacters = validSet(data.characters, validos)
    draftMutations = validSet(data.mutations, mutationNames)
    antiAfkEnabled = data.antiAfk ~= false
    autoReconnect = data.autoReconnect == true
    webhookGeneration = webhookGeneration + 1
    discordQueue = {}
    webhookUrl = type(data.webhookUrl) == "string" and validateWebhook(data.webhookUrl) or ""
    webhookUrl = webhookUrl or ""
    webhookOn = data.webhookOn == true and webhookUrl ~= ""
    webhookInput.Text = ""
    webhookInput.PlaceholderText = webhookUrl ~= "" and "Webhook salvo (URL oculta). Cole outra para trocar."
        or "Cole a URL do webhook aqui"
    statusDiscord(webhookUrl ~= "" and ("Webhook restaurado. Notificacoes " .. (webhookOn and "ligadas." or "desligadas."))
        or "Sem webhook. Cole a URL e toque em Aplicar URL.")
    selectPage(pageFrames[data.page] and data.page or "Geral")
    pequeno = data.minimized == true
    corpo.Visible, subtitle.Visible = not pequeno, not pequeno
    titulo.Position = UDim2.fromOffset(16, pequeno and 10 or 5)
    minimizar.Text = pequeno and "+" or "-"
    local pos = data.position
    if type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number"
        and pos.x == pos.x and pos.y == pos.y and math.abs(pos.x) < 1e7 and math.abs(pos.y) < 1e7 then
        painel.Position = UDim2.fromOffset(pos.x, pos.y)
        moved = true
    end
    fit(false)
    refreshDraft()
    if data.autoBuy == true then changeBuy() end
    if data.autoRoll == true and autoBuy then changeRoll() end
    atualizar()
    configReady = true
end

local transferBox = criar("TextBox", {
    Name = "ConfigTransfer", Position = UDim2.fromOffset(0, 65), Size = UDim2.new(1, 0, 0, 112),
    BackgroundColor3 = Color3.fromRGB(29, 23, 38), BorderSizePixel = 0,
    TextColor3 = white, PlaceholderText = "Exporte ou cole aqui o codigo de configuracao...", Text = "",
    Font = Enum.Font.Gotham, TextSize = 10, ClearTextOnFocus = false, MultiLine = true,
    TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top
}, configPage)
round(transferBox, 7)
padding(transferBox, 8, 8, 6, 6)
local exportButton = button(configPage, "Exportar", UDim2.fromOffset(0, 187), UDim2.new(0.34, -5, 0, 33), true)
local importButton = button(configPage, "Importar", UDim2.new(0.34, 3, 0, 187), UDim2.new(0.34, -6, 0, 33))
local clearTransfer = button(configPage, "Limpar campo", UDim2.new(0.68, 3, 0, 187), UDim2.new(0.32, -3, 0, 33))
local transferStatus = label(configPage, "Importar substitui regras, contagens e controles atuais, incluindo os botoes ligados.",
    UDim2.fromOffset(0, 229), UDim2.new(1, 0, 0, 51), 10, muted)
exportButton.Activated:Connect(function()
    local ok, code = pcall(function()
        return configHttp:JSONEncode({format = "gzinpedo-config", version = 1,
            gameId = tostring(game.GameId or game.PlaceId or 0), settings = snapshotConfig()})
    end)
    if not ok then transferStatus.Text = "Nao foi possivel exportar as configuracoes."; return end
    transferBox.Text = code
    local copied = false
    if type(setclipboard) == "function" then copied = pcall(setclipboard, code) end
    transferStatus.Text = copied and "Codigo copiado! No outro dispositivo, cole neste campo e toque em Importar."
        or "Codigo gerado no campo acima. Copie manualmente e guarde em local privado."
end)
local function validateImport(code)
    if type(code) ~= "string" or #code == 0 or #code > 100000 then return nil end
    local ok, envelope = pcall(function() return configHttp:JSONDecode(code) end)
    if not ok or type(envelope) ~= "table" or envelope.format ~= "gzinpedo-config"
        or envelope.version ~= 1 or envelope.gameId ~= tostring(game.GameId or game.PlaceId or 0) then return nil end
    local data = envelope.settings
    if type(data) ~= "table" or data.version ~= 1 or type(data.rules) ~= "table"
        or type(data.characters) ~= "table" or type(data.mutations) ~= "table"
        or type(data.counts) ~= "table" then return nil end
    for _, key in ipairs({"autoBuy", "autoRoll", "antiAfk", "webhookOn", "minimized"}) do
        if type(data[key]) ~= "boolean" then return nil end
    end
    if type(data.webhookUrl) ~= "string" or (data.webhookUrl ~= "" and not validateWebhook(data.webhookUrl)) then return nil end
    if type(data.page) ~= "string" or not pageFrames[data.page] then return nil end
    if data.autoReconnect ~= nil and type(data.autoReconnect) ~= "boolean" then return nil end
    local pos = data.position
    if type(pos) ~= "table" then return nil end
    for _, key in ipairs({"x", "y"}) do
        local n = pos[key]
        if type(n) ~= "number" or n ~= n or math.abs(n) >= 1e7 then return nil end
    end
    for name, rule in pairs(data.rules) do
        if not validos[name] or type(rule) ~= "table" then return nil end
        for mutation, enabled in pairs(rule) do
            if not mutationNames[mutation] or type(enabled) ~= "boolean" then return nil end
        end
    end
    for _, pair in ipairs({{data.characters, validos}, {data.mutations, mutationNames}}) do
        for key, value in pairs(pair[1]) do
            if not pair[2][key] or type(value) ~= "boolean" then return nil end
        end
    end
    for name, count in pairs(data.counts) do
        if not validos[name] or type(count) ~= "number" or count ~= count
            or count < 0 or count >= 1e12 or count ~= math.floor(count) then return nil end
    end
    return data
end
importButton.Activated:Connect(function()
    local data = validateImport(transferBox.Text)
    if not data then
        transferStatus.Text = "Codigo invalido ou de outro jogo/versao. Nenhuma configuracao foi alterada."
        return
    end
    restoreConfig(data)
    saveConfig()
    transferBox.Text = ""
    transferStatus.Text = "Configuracoes importadas e aplicadas."
    informar(storageAvailable and not storageIssue and "Configuracoes importadas e salvas neste dispositivo."
        or "Configuracoes importadas; salvamento local indisponivel ou com falha.")
end)
clearTransfer.Activated:Connect(function()
    transferBox.Text = ""
    transferStatus.Text = "Campo limpo. Suas configuracoes continuam iguais."
end)
restoreConfig(savedConfig)
if storageIssue then informar(storageIssue)
elseif next(savedConfig) then informar("Configuracoes e contagens restauradas.")
else informar("Configuracoes serao salvas automaticamente neste dispositivo.") end

task.spawn(function()
    while ativo do
        local ok, erro = pcall(function()
            local station = maquina()
            if not station then status.Text = "Sua maquina nao foi localizada."; return end
            local agora = os.clock()
            local dadosLista, fotoPartes = {}, {}
            local combinacoes, incompletos = 0, false
            for _, modelo in ipairs(station:GetChildren()) do
                local d = ler(modelo)
                if d then
                    table.insert(dadosLista, d)
                    if not ids[modelo] then proximoId = proximoId + 1; ids[modelo] = proximoId end
                    table.insert(fotoPartes, ids[modelo] .. ":" .. d.assinatura)
                    local obs = observados[modelo]
                    if not obs or obs.assinatura ~= d.assinatura or obs.prompt ~= d.prompt then
                        obs = {assinatura = d.assinatura, prompt = d.prompt, desde = agora}
                        observados[modelo] = obs
                    end
                    local pulado = pulados[d.modelo] and pulados[d.modelo][d.assinatura]
                    if not pulado and (d.preco == "" or not d.prompt or agora - obs.desde < COMPRA) then incompletos = true end
                    if alvoAtivo(d) then combinacoes = combinacoes + 1 end
                elseif modelo:IsA("Model") and (validos[modelo.Name] or modelo:GetAttribute("UnitName")) then
                    incompletos = true
                end
            end
            table.sort(fotoPartes)
            local foto = table.concat(fotoPartes, ";")
            local fotoRolagem = estadoRolagem(station, foto)
            if foto ~= ultimaFoto then ultimaFoto, ultimaMudanca = foto, agora end
            status.Text = "Bonecos: " .. #dadosLista .. " | Combinacoes: " .. combinacoes
                .. " | Envios: " .. tentativas .. " | AFK: " .. (antiAfkEnabled and antiAfkEstado or "desligado")

            if compraPendente then
                local pendente = compraPendente
                if not pendente.modelo:IsDescendantOf(station) then
                    notificarDiscord(pendente)
                    compraPendente, ultimaMudanca = nil, agora
                    informar("Boneco saiu da maquina. Continuando.")
                else
                    local fresh = ler(pendente.modelo)
                    if fresh and (not selecionado(fresh) or fresh.assinatura ~= pendente.assinatura) then
                        -- An edited rule or replacement offer is not a receipt.
                        compraPendente = nil
                        informar("Alvo ou regra mudou. Reavaliando a maquina.")
                    elseif not autoBuy then
                        return
                    elseif agora - pendente.inicio + 0.000001 >= INTERVALO_COMPRA_PENDENTE then
                        if pendente.tentativas >= MAX_TENTATIVAS_COMPRA then
                            pulados[pendente.modelo] = pulados[pendente.modelo] or {}
                            pulados[pendente.modelo][pendente.assinatura] = true
                            compraPendente = nil
                            informar("Pulando " .. pendente.details.nome .. ": compra pendente apos 10 tentativas. Seguindo a maquina.")
                            return
                        end
                        pendente.inicio = agora
                        pendente.tentativas = pendente.tentativas + 1
                        if fresh and fresh.prompt and perto(fresh.prompt)
                            and fresh.assinatura == pendente.assinatura then
                            if not ativo or not autoBuy then return end
                            informar("Compra " .. pendente.tentativas .. "/10: " .. fresh.nome .. " / " .. fresh.mutacao)
                            tentativas = tentativas + 1
                            fireproximityprompt(fresh.prompt, fresh.prompt.HoldDuration)
                        else
                            informar("Compra " .. pendente.tentativas .. "/10: sem alcance ou botao ativo. Vai pular se continuar pendente.")
                        end
                        return
                    else
                        return
                    end
                end
            end
            if rolagemPendente then
                if not autoRoll or not autoBuy then
                    rolagemPendente = nil
                elseif fotoRolagem ~= rolagemPendente.antes then
                    rolagemPendente, ultimaMudanca = nil, agora
                    -- New roll: even reused model instances may be new offers.
                    enviados = setmetatable({}, {__mode = "k"})
                    pulados = setmetatable({}, {__mode = "k"})
                    observados = setmetatable({}, {__mode = "k"})
                    return
                elseif agora - rolagemPendente.inicio >= TIMEOUT_ROLAGEM then
                    local pending = rolagemPendente
                    pending.inicio = agora
                    local prompt = promptRolar(station)
                    local disponivel, motivo = acessoPrompt(prompt)
                    if disponivel and ativo and autoBuy and autoRoll then
                        pending.repeticoes = pending.repeticoes + 1
                        informar("Repetindo rolagem " .. pending.repeticoes .. ". Aguardando resposta da maquina.")
                        fireproximityprompt(prompt, prompt.HoldDuration)
                    else
                        informar((motivo or "Aguardando maquina.") .. " Auto Roll continua ligado.")
                    end
                    return
                else return end
            end
            if not autoBuy then return end
            local existeAlvo, candidato = false, nil
            for _, d in ipairs(dadosLista) do
                if alvoAtivo(d) then
                    existeAlvo = true
                    local obs = observados[d.modelo]
                    local jaEnviado = enviados[d.modelo] and enviados[d.modelo][d.assinatura]
                    if not jaEnviado and d.prompt and d.preco ~= ""
                        and agora - obs.desde >= COMPRA and perto(d.prompt) then
                        candidato = d
                        break
                    end
                end
            end
            if candidato and agora - ultimaCompra >= COMPRA then
                local d = ler(candidato.modelo)
                if not ativo or not autoBuy or not d or not selecionado(d)
                    or d.assinatura ~= candidato.assinatura or d.prompt ~= candidato.prompt
                    or not perto(d.prompt) or not d.modelo:IsDescendantOf(station) then return end
                enviados[d.modelo] = enviados[d.modelo] or {}
                enviados[d.modelo][d.assinatura] = true
                ultimaCompra = agora
                compraPendente = {modelo = d.modelo, inicio = agora, tentativas = 1, assinatura = d.assinatura,
                    details = {nome = d.nome, mutacao = d.mutacao, preco = d.preco}}
                informar("Compra 1/10: " .. d.nome .. " / " .. d.mutacao .. " / " .. d.preco)
                tentativas = tentativas + 1
                fireproximityprompt(d.prompt, d.prompt.HoldDuration)
                return
            end
            if existeAlvo then
                if not candidato then informar("Alvo presente. Aguardando dados ou aproximacao para comprar.") end
                return
            end
            if not autoRoll or incompletos or agora - ultimaMudanca < PAUSA_ROLAGEM then return end
            local prompt = promptRolar(station)
            local disponivel, motivo = acessoPrompt(prompt)
            if not disponivel then informar(motivo); return end
            if not ativo or not autoBuy or not autoRoll then return end
            rolagemPendente = {antes = fotoRolagem, inicio = agora, repeticoes = 0}
            if prompt.Name:lower():find("warning", 1, true) then
                informar("Interagindo com Roll. Se o jogo abrir um aviso, confirme na tela.")
            else
                informar("Solicitando rolagem: " .. prompt.Name)
            end
            fireproximityprompt(prompt, prompt.HoldDuration)
        end)
        if not ok and ativo then
            -- Recover transient object/replication failures without disabling toggles.
            informar("Falha temporaria; tentando novamente: " .. tostring(erro))
            if not compraPendente then task.wait(1) end
        end
        task.wait(VERIFICACAO)
    end
end)


-- Reconexao so para mensagens reconhecidas de perda de conexao.
-- Nao modifica a posicao do personagem nem os prompts da maquina.
do
    local teleportService, coreGui
    pcall(function() teleportService = game:GetService("TeleportService") end)
    pcall(function() coreGui = game:GetService("CoreGui") end)
    local nextAttempt, attempts, lastPrompt = nil, 0, nil
    local queuedResume = false
    local lastCheck, lastDetectionError = -math.huge, -math.huge
    local function connectionPrompt()
        if not coreGui then return nil end
        local root = coreGui:FindFirstChild("RobloxPromptGui")
        local overlay = root and root:FindFirstChild("promptOverlay")
        if not overlay or (overlay:IsA("GuiObject") and not overlay.Visible) then return nil end
        for _, prompt in ipairs(overlay:GetChildren()) do
            if prompt.Name == "ErrorPrompt" and prompt:IsA("GuiObject") and prompt.Visible then
                local parts = {}
                for _, obj in ipairs(prompt:GetDescendants()) do
                    if obj:IsA("TextLabel") then table.insert(parts, obj.Text) end
                end
                local text = table.concat(parts, " "):lower()
                local denied = text:find("267", 1, true) or text:find("268", 1, true)
                    or text:find("273", 1, true) or text:find("264", 1, true)
                    or text:find("266", 1, true) or text:find("kicked", 1, true)
                    or text:find("banned", 1, true) or text:find("expul", 1, true)
                    or text:find("banido", 1, true)
                local lost = text:find("277", 1, true) or text:find("279", 1, true)
                    or text:find("lost connection", 1, true) or text:find("connection lost", 1, true)
                    or text:find("internet connection", 1, true) or text:find("conexão perdida", 1, true)
                    or text:find("perdeu a conexão", 1, true) or text:find("conexao perdida", 1, true)
                if lost and not denied then return prompt end
            end
        end
    end
    local function queueResume()
        if queuedResume then return end
        local queue = queue_on_teleport or queueonteleport
            or (type(syn) == "table" and syn.queue_on_teleport)
        if type(queue) ~= "function" or not storageAvailable then
            informar("Reconectando; se o painel nao voltar, execute o loadstring novamente.")
            return
        end
        local resumeCode = string.format([=[
            if not game:IsLoaded() then game.Loaded:Wait() end
            local ok, settings = pcall(function()
                return game:GetService("HttpService"):JSONDecode(readfile(%q))
            end)
            if ok and type(settings) == "table" and settings.autoReconnect == true then
                local loaded = pcall(function()
                    loadstring(game:HttpGet("https://raw.githubusercontent.com/lucz1n0209-code/gzinpedo/main/Loader.lua"))()
                end)
                if not loaded then warn("[gzin pedo] Execute o loadstring novamente para reabrir o painel.") end
            end
        ]=], configPath)
        queuedResume = pcall(queue, resumeCode)
        if not queuedResume then informar("Nao foi possivel agendar o painel; execute o loadstring apos voltar.") end
    end
    if teleportService then
        pcall(function()
            table.insert(connections, teleportService.TeleportInitFailed:Connect(function(who)
                if ativo and autoReconnect and who == player and nextAttempt then
                    informar("Reconexao falhou; aguardando a proxima tentativa.")
                end
            end))
        end)
    end
    task.spawn(function()
        while ativo do
            local now = os.clock()
            if now - lastCheck >= 0.5 then
                lastCheck = now
                if not autoReconnect then
                    nextAttempt, attempts, lastPrompt = nil, 0, nil
                else
                    local readOk, prompt = pcall(connectionPrompt)
                    if not readOk or not coreGui or not teleportService then
                        if now - lastDetectionError >= 60 then
                            lastDetectionError = now
                            informar("Auto Reconnect sem acesso aos recursos de reconexao neste executor.")
                        end
                    elseif not prompt then
                        nextAttempt, attempts, lastPrompt = nil, 0, nil
                    else
                        if prompt ~= lastPrompt then
                            lastPrompt, attempts, nextAttempt = prompt, 0, now + 5
                            informar("Queda de conexao detectada. Tentando voltar em 5 segundos.")
                        end
                        if nextAttempt and now >= nextAttempt then
                            attempts = attempts + 1
                            local delay = math.min(60, 5 * 2 ^ math.min(attempts - 1, 4))
                            nextAttempt = now + delay
                            saveConfig()
                            queueResume()
                            informar("Tentativa de reconexao " .. attempts .. ".")
                            local ok = pcall(function() teleportService:Teleport(game.PlaceId, player) end)
                            if not ok then informar("Reconexao indisponivel agora; nova tentativa em " .. delay .. " segundos.") end
                        end
                    end
                end
            end
            task.wait(0.5)
        end
    end)
end
