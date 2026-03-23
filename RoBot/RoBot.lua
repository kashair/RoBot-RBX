--[[
	RoBot — Template assistant with API backend.
	Requires the Node.js API server running on localhost:3000.
]]

-- Capture plugin reference (required for local plugins)
local plugin = plugin

local HttpService = game:GetService("HttpService")
local Selection = game:GetService("Selection")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")

-- =============================================================================
-- API Configuration
-- =============================================================================

-- ⚠️ IMPORTANT: Change this to your production API URL before distributing!
-- Local development: "http://localhost:3000/api"
-- Production example: "https://robot-api.up.railway.app/api"
local API_BASE_URL = "http://localhost:3000/api"
local TEMPLATES_CACHE = {}
local CACHE_LOADED = false

-- =============================================================================
-- API Client
-- =============================================================================

print("[+] RoBot Initialized")
print("[+] RoCore Database Loaded")
print("[+] Enjoy! Made by Kashairy")


local ApiClient = {}
ApiClient.__index = ApiClient

function ApiClient.new()
	return setmetatable({}, ApiClient)
end

function ApiClient:fetchTemplates()
	local ok, result = pcall(function()
		local url = API_BASE_URL .. "/templates"
		local response = HttpService:GetAsync(url)
		return HttpService:JSONDecode(response)
	end)
	
	if ok and result.success then
		return result.templates
	else
		warn("[RoBot] Failed to fetch templates: " .. tostring(result))
		return nil
	end
end

function ApiClient:searchTemplates(query)
	local ok, result = pcall(function()
		local encodedQuery = HttpService:UrlEncode(query)
		local url = API_BASE_URL .. "/search?q=" .. encodedQuery
		local response = HttpService:GetAsync(url)
		return HttpService:JSONDecode(response)
	end)
	
	if ok and result.success then
		return result.templates
	else
		warn("[RoBot] Search failed: " .. tostring(result))
		return nil
	end
end

function ApiClient:getTemplate(id)
	local ok, result = pcall(function()
		local url = API_BASE_URL .. "/templates/" .. id
		local response = HttpService:GetAsync(url)
		return HttpService:JSONDecode(response)
	end)
	
	if ok and result.success then
		return result.template
	else
		warn("[RoBot] Failed to get template: " .. tostring(result))
		return nil
	end
end

function ApiClient:healthCheck()
	local ok, result = pcall(function()
		local url = API_BASE_URL .. "/health"
		local response = HttpService:GetAsync(url)
		return HttpService:JSONDecode(response)
	end)
	return ok and result.status == "ok"
end

-- =============================================================================
-- Template Manager
-- =============================================================================

local TemplateManager = {}
TemplateManager.__index = TemplateManager

function TemplateManager.new()
	local self = setmetatable({}, TemplateManager)
	self.api = ApiClient.new()
	self.cache = {}
	self.cacheLoaded = false
	return self
end

function TemplateManager:loadCache()
	if self.cacheLoaded then
		return true
	end
	
	local templates = self.api:fetchTemplates()
	if templates then
		for _, template in ipairs(templates) do
			self.cache[template.id] = template
		end
		self.cacheLoaded = true
		print("[RoBot] Loaded " .. #templates .. " templates from API")
		return true
	end
	
	return false
end

function TemplateManager:getTemplate(id)
	-- Try cache first
	if self.cache[id] then
		return self.cache[id]
	end
	
	-- Fetch from API if not cached
	local template = self.api:getTemplate(id)
	if template then
		self.cache[id] = template
	end
	return template
end

function TemplateManager:search(query)
	-- Ensure cache is loaded
	self:loadCache()
	
	-- Search via API for best results
	local results = self.api:searchTemplates(query)
	if results and #results > 0 then
		return results
	end
	
	-- Fallback: local search in cache with improved matching
	local matches = {}
	local searchTerm = query:lower()
	
	-- Split query into words for better matching
	local searchWords = {}
	for word in searchTerm:gmatch("%w+") do
		table.insert(searchWords, word)
	end
	
	for id, template in pairs(self.cache) do
		local score = 0
		
		-- ID match
		if id:lower() == searchTerm then
			score = score + 100
		elseif id:lower():find(searchTerm, 1, true) then
			score = score + 50
		end
		
		-- Name match (skip if it's just template_X)
		local name = template.name or ""
		if not name:match("^template_%d+$") then
			if name:lower():find(searchTerm, 1, true) then
				score = score + 60
			end
		end
		
		-- ScriptName match (high priority - this is the readable name)
		local scriptName = template.scriptName or ""
		if scriptName:lower() == searchTerm then
			score = score + 150
		elseif scriptName:lower():find(searchTerm, 1, true) then
			score = score + 80
		end
		
		-- Keywords match (check for any word match)
		if template.keywords then
			for _, kw in ipairs(template.keywords) do
				local kwLower = kw:lower()
				if kwLower == searchTerm then
					score = score + 70
				elseif kwLower:find(searchTerm, 1, true) then
					score = score + 40
				end
				-- Also check individual words in multi-word keywords
				for _, word in ipairs(searchWords) do
					if kwLower:find(word, 1, true) then
						score = score + 25
					end
				end
			end
		end
		
		if score > 0 then
			table.insert(matches, { template = template, score = score })
		end
	end
	
	-- Sort by score
	table.sort(matches, function(a, b) return a.score > b.score end)
	
	-- Extract templates
	local templates = {}
	for _, match in ipairs(matches) do
		table.insert(templates, match.template)
	end
	
	return templates
end

function TemplateManager:getAllTemplates()
	self:loadCache()
	local templates = {}
	for _, template in pairs(self.cache) do
		table.insert(templates, template)
	end
	return templates
end

-- =============================================================================
-- ScriptManager
-- =============================================================================

local ScriptManager = {}
ScriptManager.__index = ScriptManager

local SUPPORTED_SCRIPT_CLASSES = {
	Script = true,
	LocalScript = true,
	ModuleScript = true,
}

local function isScriptInstance(instance)
	return instance and SUPPORTED_SCRIPT_CLASSES[instance.ClassName] == true
end

function ScriptManager.new()
	return setmetatable({}, ScriptManager)
end

function ScriptManager:getSelectedInstance()
	local selected = Selection:Get()
	return selected[1]
end

function ScriptManager:previewAction(action)
	if type(action) ~= "table" or action.action ~= "create_script" then
		return false, "Only create_script is supported"
	end
	return true,
		string.format(
			'Create %s "%s" in %s',
			tostring(action.type or "Script"),
			tostring(action.name or "Script"),
			tostring(action.parent or "ServerScriptService")
		)
end

function ScriptManager:applyAction(action)
	if action.action == "create_script" then
		return self:_createScript(action)
	end
	return false, "Unsupported action"
end

function ScriptManager:_resolveParent(parentName)
	if type(parentName) ~= "string" or parentName == "" then
		return ServerScriptService
	end
	if parentName == "Workspace" then
		return workspace
	end
	if parentName == "ServerScriptService" then
		return ServerScriptService
	end
	if parentName == "ReplicatedStorage" then
		return ReplicatedStorage
	end
	if parentName == "StarterGui" then
		return StarterGui
	end
	if parentName == "StarterPlayer" then
		return StarterPlayer
	end
	local inst = game:FindFirstChild(parentName, true)
	return inst
end

function ScriptManager:_createScript(action)
	local className = tostring(action.type or "Script")
	if not SUPPORTED_SCRIPT_CLASSES[className] then
		return false, "Invalid script type: " .. className
	end
	local parent = self:_resolveParent(action.parent)
	if not parent then
		return false, "Parent not found: " .. tostring(action.parent)
	end
	local newScript = Instance.new(className)
	newScript.Name = tostring(action.name or "RoBotScript")
	newScript.Source = tostring(action.code or "")
	newScript.Parent = parent
	return true, string.format("Created %s \"%s\" in %s", className, newScript.Name, parent:GetFullName())
end

-- =============================================================================
-- Template Utilities
-- =============================================================================

local function mergePlaceholders(template, userText)
	local values = {}
	for k, v in pairs(template.defaults or {}) do
		values[k] = v
	end
	return values
end

local function applyTemplateString(code, values)
	local result = code
	for key, value in pairs(values) do
		local pattern = "{{" .. key .. "}}"
		result = result:gsub(pattern, tostring(value))
	end
	return result
end

local function isPositiveMessage(text)
	local lower = text:lower()
	return lower:match("^yes") or lower:match("^sure") or lower:match("^ok") or lower:match("^create")
end

local function isNegativeMessage(text)
	local lower = text:lower()
	return lower:match("^no") or lower:match("^cancel") or lower:match("^skip") or lower:match("^nah")
end

-- =============================================================================
-- UI Class (Modern Dark Design)
-- =============================================================================

local UI = {}
UI.__index = UI

-- Dark Modern Color Palette
local COLORS = {
	bg = Color3.fromRGB(18, 18, 18),
	bgLight = Color3.fromRGB(28, 28, 28),
	bgLighter = Color3.fromRGB(38, 38, 38),
	bgCard = Color3.fromRGB(45, 45, 45),
	fg = Color3.fromRGB(240, 240, 240),
	fgDim = Color3.fromRGB(160, 160, 160),
	accent = Color3.fromRGB(88, 166, 255),
	red = Color3.fromRGB(248, 81, 73),
	green = Color3.fromRGB(35, 197, 94),
}

function UI.new(widget, plugin)
	local self = setmetatable({}, UI)
	self.widget = widget
	self.plugin = plugin
	self:_build()
	return self
end

function UI:_createCornerRadius(radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 6)
	return corner
end

function UI:_createStroke(parent, color, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or COLORS.bgLighter
	stroke.Thickness = thickness or 1
	stroke.Parent = parent
	return stroke
end

function UI:_build()
	local widget = self.widget

	local frame = Instance.new("Frame")
	frame.Name = "MainFrame"
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = COLORS.bg
	frame.BorderSizePixel = 0
	frame.Parent = widget

	-- Header
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 44)
	header.BackgroundColor3 = COLORS.bgLight
	header.BorderSizePixel = 0
	header.Parent = frame
	self:_createCornerRadius(0):Clone().Parent = header
	self:_createStroke(header, COLORS.bgLighter)

	local headerTitle = Instance.new("TextLabel")
	headerTitle.Name = "HeaderTitle"
	headerTitle.Position = UDim2.new(0, 16, 0, 0)
	headerTitle.Size = UDim2.new(1, -80, 1, 0)
	headerTitle.BackgroundTransparency = 1
	headerTitle.Text = "RoBot"
	headerTitle.TextColor3 = COLORS.fg
	headerTitle.Font = Enum.Font.BuilderSansBold
	headerTitle.TextSize = 20
	headerTitle.TextXAlignment = Enum.TextXAlignment.Left
	headerTitle.Parent = header

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Position = UDim2.new(0, 16, 0.55, 0)
	subtitle.Size = UDim2.new(1, -80, 0.4, 0)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "Early Access"
	subtitle.TextColor3 = COLORS.fgDim
	subtitle.Font = Enum.Font.BuilderSansMedium
	subtitle.TextSize = 11
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Parent = header

	-- Chat Scroll Area
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "ChatScroll"
	scroll.Position = UDim2.new(0, 12, 0, 52)
	scroll.Size = UDim2.new(1, -24, 1, -140)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 3
	scroll.ScrollBarImageColor3 = COLORS.fgDim
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.Parent = frame

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = scroll

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = scroll

	-- Input Container
	local inputContainer = Instance.new("Frame")
	inputContainer.Name = "InputContainer"
	inputContainer.Position = UDim2.new(0, 12, 1, -76)
	inputContainer.Size = UDim2.new(1, -24, 0, 44)
	inputContainer.BackgroundColor3 = COLORS.bgLight
	inputContainer.BorderSizePixel = 0
	inputContainer.Parent = frame
	self:_createCornerRadius(8):Clone().Parent = inputContainer
	self:_createStroke(inputContainer, COLORS.bgLighter)

	-- Input Box
	local inputBox = Instance.new("TextBox")
	inputBox.Name = "InputBox"
	inputBox.Position = UDim2.new(0, 12, 0, 4)
	inputBox.Size = UDim2.new(1, -88, 1, -8)
	inputBox.BackgroundTransparency = 1
	inputBox.Text = ""
	inputBox.PlaceholderText = "Describe what you need..."
	inputBox.TextColor3 = COLORS.fg
	inputBox.PlaceholderColor3 = COLORS.fgDim
	inputBox.Font = Enum.Font.BuilderSans
	inputBox.TextSize = 14
	inputBox.ClearTextOnFocus = false
	inputBox.Parent = inputContainer

	-- Send Button
	local sendButton = Instance.new("TextButton")
	sendButton.Name = "SendButton"
	sendButton.Position = UDim2.new(1, -68, 0.5, -16)
	sendButton.Size = UDim2.new(0, 56, 0, 32)
	sendButton.BackgroundColor3 = COLORS.accent
	sendButton.BorderSizePixel = 0
	sendButton.Text = ""
	sendButton.AutoButtonColor = true
	sendButton.Parent = inputContainer
	self:_createCornerRadius(6):Clone().Parent = sendButton

	local sendIcon = Instance.new("TextLabel")
	sendIcon.Name = "SendIcon"
	sendIcon.Size = UDim2.new(1, 0, 1, 0)
	sendIcon.BackgroundTransparency = 1
	sendIcon.Text = "→"
	sendIcon.TextColor3 = COLORS.fg
	sendIcon.Font = Enum.Font.BuilderSansBold
	sendIcon.TextSize = 18
	sendIcon.Parent = sendButton

	-- Action Preview Frame
	local actionFrame = Instance.new("Frame")
	actionFrame.Name = "ActionFrame"
	actionFrame.Position = UDim2.new(0, 12, 1, -118)
	actionFrame.Size = UDim2.new(1, -24, 0, 36)
	actionFrame.BackgroundColor3 = COLORS.bgLight
	actionFrame.BorderSizePixel = 0
	actionFrame.Visible = false
	actionFrame.Parent = frame
	self:_createCornerRadius(6):Clone().Parent = actionFrame
	self:_createStroke(actionFrame, COLORS.accent, 1)

	local actionIndicator = Instance.new("Frame")
	actionIndicator.Name = "Indicator"
	actionIndicator.Position = UDim2.new(0, 0, 0, 0)
	actionIndicator.Size = UDim2.new(0, 4, 1, 0)
	actionIndicator.BackgroundColor3 = COLORS.accent
	actionIndicator.BorderSizePixel = 0
	actionIndicator.Parent = actionFrame
	self:_createCornerRadius(0):Clone().Parent = actionIndicator

	local actionLabel = Instance.new("TextLabel")
	actionLabel.Name = "ActionLabel"
	actionLabel.Size = UDim2.new(1, -140, 1, 0)
	actionLabel.Position = UDim2.new(0, 12, 0, 0)
	actionLabel.BackgroundTransparency = 1
	actionLabel.Text = ""
	actionLabel.TextColor3 = COLORS.fg
	actionLabel.Font = Enum.Font.BuilderSans
	actionLabel.TextSize = 12
	actionLabel.TextWrapped = true
	actionLabel.TextXAlignment = Enum.TextXAlignment.Left
	actionLabel.Parent = actionFrame

	local confirmButton = Instance.new("TextButton")
	confirmButton.Name = "ConfirmButton"
	confirmButton.Position = UDim2.new(1, -120, 0.5, -12)
	confirmButton.Size = UDim2.new(0, 54, 0, 24)
	confirmButton.BackgroundColor3 = COLORS.bgLighter
	confirmButton.BorderSizePixel = 0
	confirmButton.Text = "Create"
	confirmButton.TextColor3 = COLORS.fg
	confirmButton.Font = Enum.Font.BuilderSansBold
	confirmButton.TextSize = 11
	confirmButton.AutoButtonColor = true
	confirmButton.Parent = actionFrame
	self:_createCornerRadius(4):Clone().Parent = confirmButton

	local cancelButton = Instance.new("TextButton")
	cancelButton.Name = "CancelButton"
	cancelButton.Position = UDim2.new(1, -60, 0.5, -12)
	cancelButton.Size = UDim2.new(0, 50, 0, 24)
	cancelButton.BackgroundColor3 = COLORS.bgLighter
	cancelButton.BorderSizePixel = 0
	cancelButton.Text = "Skip"
	cancelButton.TextColor3 = COLORS.fg
	cancelButton.Font = Enum.Font.BuilderSansBold
	cancelButton.TextSize = 11
	cancelButton.AutoButtonColor = true
	cancelButton.Parent = actionFrame
	self:_createCornerRadius(4):Clone().Parent = cancelButton

	-- Status Bar
	local statusBar = Instance.new("Frame")
	statusBar.Name = "StatusBar"
	statusBar.Position = UDim2.new(0, 0, 1, -22)
	statusBar.Size = UDim2.new(1, 0, 0, 22)
	statusBar.BackgroundColor3 = COLORS.bgLight
	statusBar.BorderSizePixel = 0
	statusBar.Parent = frame
	self:_createStroke(statusBar, COLORS.bgLighter)

	local statusText = Instance.new("TextLabel")
	statusText.Name = "StatusText"
	statusText.Size = UDim2.new(1, -16, 1, 0)
	statusText.Position = UDim2.new(0, 12, 0, 0)
	statusText.BackgroundTransparency = 1
	statusText.Text = "● Offline"
	statusText.TextColor3 = COLORS.red
	statusText.Font = Enum.Font.BuilderSans
	statusText.TextSize = 10
	statusText.TextXAlignment = Enum.TextXAlignment.Left
	statusText.Parent = statusBar

	self.scroll = scroll
	self.inputBox = inputBox
	self.sendButton = sendButton
	self.actionFrame = actionFrame
	self.actionLabel = actionLabel
	self.confirmButton = confirmButton
	self.cancelButton = cancelButton
	self.statusText = statusText
	self.isOnline = false
	self.busyIndicator = nil
	self.messageQueue = {}
	self.isProcessingQueue = false
end

function UI:addMessage(sender, text, isError)
	-- Add to queue instead of creating immediately
	table.insert(self.messageQueue, {sender = sender, text = text, isError = isError})
	self:processMessageQueue()
end

function UI:processMessageQueue()
	if self.isProcessingQueue or #self.messageQueue == 0 then
		return
	end
	
	self.isProcessingQueue = true
	
	-- Process first message in queue
	local msgData = table.remove(self.messageQueue, 1)
	self:createMessageBubble(msgData.sender, msgData.text, msgData.isError)
	
	-- Wait for animation to complete before processing next
	task.delay(0.4, function()
		self.isProcessingQueue = false
		self:processMessageQueue()
	end)
end

function UI:createMessageBubble(sender, text, isError)
	local isYou = sender == "You"
	
	-- Start with transparent/small for animation
	local bubble = Instance.new("Frame")
	bubble.Name = "MessageBubble"
	bubble.Size = UDim2.new(1, isYou and -12 or -8, 0, 0)
	bubble.Position = UDim2.new(isYou and 0 or 0, isYou and 12 or 8, 0, 0)
	bubble.BackgroundTransparency = 1
	bubble.AutomaticSize = Enum.AutomaticSize.Y
	bubble.LayoutOrder = #self.scroll:GetChildren()
	bubble.Parent = self.scroll
	bubble.Visible = false

	-- Delete button (top right of bubble)
	local deleteBtn = Instance.new("TextButton")
	deleteBtn.Name = "DeleteBtn"
	deleteBtn.Position = UDim2.new(1, -20, 0, isYou and 0 or 14)
	deleteBtn.Size = UDim2.new(0, 16, 0, 16)
	deleteBtn.BackgroundTransparency = 1
	deleteBtn.Text = "×"
	deleteBtn.TextColor3 = COLORS.fgDim
	deleteBtn.Font = Enum.Font.BuilderSansBold
	deleteBtn.TextSize = 14
	deleteBtn.Parent = bubble

	deleteBtn.MouseButton1Click:Connect(function()
		-- Fade out animation
		local fadeOut = TweenService:Create(
			bubble,
			TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{BackgroundTransparency = 1}
		)
		fadeOut:Play()
		fadeOut.Completed:Connect(function()
			bubble:Destroy()
		end)
	end)

	-- Sender label
	local senderLabel = Instance.new("TextLabel")
	senderLabel.Name = "Sender"
	senderLabel.Size = UDim2.new(1, -24, 0, 16)
	senderLabel.BackgroundTransparency = 1
	senderLabel.Text = isYou and "You" or (sender or "RoBot")
	senderLabel.TextColor3 = isYou and COLORS.fg or COLORS.accent
	senderLabel.Font = Enum.Font.BuilderSansBold
	senderLabel.TextSize = 11
	senderLabel.TextXAlignment = Enum.TextXAlignment.Left
	senderLabel.TextTransparency = 1
	senderLabel.Parent = bubble

	-- Message background
	local bg = Instance.new("Frame")
	bg.Name = "BubbleBg"
	bg.Position = UDim2.new(0, 0, 0, 18)
	bg.Size = UDim2.new(1, 0, 0, 0)
	bg.BackgroundColor3 = isYou and COLORS.bgCard or COLORS.bgLighter
	bg.BorderSizePixel = 0
	bg.BackgroundTransparency = 1
	bg.AutomaticSize = Enum.AutomaticSize.Y
	bg.Parent = bubble

	local cornerRadius = 6
	local corner = self:_createCornerRadius(cornerRadius)
	corner.Parent = bg

	-- Left accent line for both User and RoBot
	local leftAccent = Instance.new("Frame")
	leftAccent.Name = "Accent"
	leftAccent.Size = UDim2.new(0, 3, 1, 0)
	leftAccent.BackgroundColor3 = isYou and COLORS.fg or (isError and COLORS.red or COLORS.accent)
	leftAccent.BorderSizePixel = 0
	leftAccent.Parent = bg
	self:_createCornerRadius(0):Clone().Parent = leftAccent

	-- Message text
	local label = Instance.new("TextLabel")
	label.Name = "MessageText"
	label.Position = UDim2.new(0, 10, 0.2, 0)
	label.Size = UDim2.new(1, -14, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = COLORS.fg
	label.Font = Enum.Font.BuilderSans
	label.TextSize = 13
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Parent = bg

	-- Calculate proper size
	task.defer(function()
		local textHeight = label.TextBounds.Y + 16
		bg.Size = UDim2.new(1, 0, 0, textHeight)
		bubble.Size = UDim2.new(1, isYou and -12 or -8, 0, 18 + textHeight)
		bubble.Visible = true
		
		-- Animation: slide in from side and fade
		local startPos = isYou and UDim2.new(0.1, 12, 0, 0) or UDim2.new(-0.1, 8, 0, 0)
		local endPos = UDim2.new(isYou and 0 or 0, isYou and 12 or 8, 0, 0)
		bubble.Position = startPos
		
		-- Create tweens
		local posTween = TweenService:Create(
			bubble,
			TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{Position = endPos}
		)
		
		local fadeTween = TweenService:Create(
			bg,
			TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{BackgroundTransparency = 0}
		)
		
		local textFade = TweenService:Create(
			senderLabel,
			TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{TextTransparency = 0}
		)
		
		posTween:Play()
		fadeTween:Play()
		textFade:Play()
		
		self.scroll.CanvasPosition = Vector2.new(0, self.scroll.AbsoluteCanvasSize.Y)
	end)
end

function UI:setStatus(isOnline)
	self.isOnline = isOnline
	if isOnline then
		self.statusText.Text = "● Online"
		self.statusText.TextColor3 = COLORS.green
	else
		self.statusText.Text = "● Offline"
		self.statusText.TextColor3 = COLORS.red
	end
end

function UI:setBusy(busy)
	if busy then
		self.statusText.Text = "◌ Working..."
		self.statusText.TextColor3 = COLORS.accent
		self.inputBox.PlaceholderText = "Generating response..."
	else
		if self.isOnline then
			self.statusText.Text = "● Online"
			self.statusText.TextColor3 = COLORS.green
		else
			self.statusText.Text = "● Offline"
			self.statusText.TextColor3 = COLORS.red
		end
		self.inputBox.PlaceholderText = "Describe what you need..."
	end
end

function UI:clearChat()
	for _, child in ipairs(self.scroll:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

function UI:setActionPreview(previewText, action)
	self.actionLabel.Text = previewText or ""
	self.actionFrame.Visible = true
end

function UI:clearActionPreview()
	self.actionFrame.Visible = false
	self.actionLabel.Text = ""
end

-- =============================================================================
-- Entry Point
-- =============================================================================

local TOOLBAR_NAME = "RoBot"
local BUTTON_NAME = "Open Assistant"
local WIDGET_ID = "RoBotAssistantWidget"
local WIDGET_TITLE = "RoBot Assistant"

local ok, err = pcall(function()
	local toolbar = plugin:CreateToolbar(TOOLBAR_NAME)
	local openButton = toolbar:CreateButton(BUTTON_NAME, "Open RoBot — your AI assistant", "")
	openButton.ClickableWhenViewportHidden = true

	local widgetInfo = DockWidgetPluginGuiInfo.new(
		Enum.InitialDockState.Right,
		true,
		false,
		440,
		560,
		340,
		300
	)
	local widget = plugin:CreateDockWidgetPluginGuiAsync(WIDGET_ID, widgetInfo)
	widget.Title = WIDGET_TITLE

	local ui = UI.new(widget, plugin)
	local templateManager = TemplateManager.new()
	local scriptManager = ScriptManager.new()

	widget:GetPropertyChangedSignal("Enabled"):Connect(function()
		if widget.Enabled then
			ui.inputBox.Text = ""
			task.defer(function()
				templateManager:loadCache()
			end)
		end
	end)

	local pendingOffer = nil

	local function buildOfferAction(template, userText)
		local values = mergePlaceholders(template, userText)
		local code = applyTemplateString(template.code, values)
		return {
			action = "create_script",
			name = template.scriptName,
			type = template.scriptType,
			parent = template.parent,
			code = code,
		}
	end

	local function formatOfferQuestion(template)
		local base = template.name:gsub("%s+%b()", ""):gsub("^%s+", ""):gsub("%s+$", "")
		if base == "" or base:match("^template_%d+$") then
			base = template.scriptName or template.id
		end
		if string.match(base:lower(), "system%s*$") then
			return "Would you like to create a " .. base .. "?"
		end
		return "Would you like to create a " .. base .. " system?"
	end

	local function tryApplyPendingFromText(text)
		if not pendingOffer then
			return false
		end
		if isPositiveMessage(text) then
			local ok, msg = scriptManager:applyAction(pendingOffer.action)
			if ok then
				ui:addMessage("RoBot", msg, false)
			else
				ui:addMessage("RoBot", "Could not create: " .. msg, true)
			end
			ui:clearActionPreview()
			pendingOffer = nil
			return true
		end
		if isNegativeMessage(text) then
			ui:clearActionPreview()
			pendingOffer = nil
			ui:addMessage("RoBot", "Okay — offer cancelled. Ask again anytime.", false)
			return true
		end
		return false
	end

	local function sendPrompt(promptText)
		local message = (promptText or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if message == "" then
			return
		end

		ui.inputBox.Text = ""
		ui:addMessage("You", message, false)

		if tryApplyPendingFromText(message) then
			return
		end

		-- Check if API is available
		if not ui.isOnline then
			ui:addMessage(
				"RoBot",
				"Sorry, RoBot is currently unavailable at the moment.",
				false
			)
			return
		end

		ui:setBusy(true)
		task.defer(function()
			local templates = templateManager:search(message)
			local template = templates and templates[1]
			
			if not template then
				ui:addMessage(
					"RoBot",
					"I do not understand your request, please reformulate!",
					false
				)
				ui:setBusy(false)
				return
			end

			local action = buildOfferAction(template, message)
			local previewOk, previewText = scriptManager:previewAction(action)
			pendingOffer = { template = template, action = action }

			ui:addMessage(
				"RoBot",
				formatOfferQuestion(template)
					.. "\nReply yes or tap Create to add this as "
					.. template.scriptType
					.. " in "
					.. template.parent
					.. ", or no / Skip to cancel.",
				false
			)
			if previewOk then
				ui:setActionPreview(previewText, action)
			end
			ui:setBusy(false)
		end)
	end

	local function checkApiStatus()
		local isOnline = templateManager.api:healthCheck()
		ui:setStatus(isOnline)
		return isOnline
	end

	openButton.Click:Connect(function()
		widget.Enabled = not widget.Enabled
	end)

	widget:GetPropertyChangedSignal("Enabled"):Connect(function()
		if widget.Enabled then
			ui.inputBox.Text = ""
			task.defer(function()
				templateManager:loadCache()
				checkApiStatus()
			end)
		end
	end)

	ui.sendButton.MouseButton1Click:Connect(function()
		sendPrompt(ui.inputBox.Text)
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode ~= Enum.KeyCode.Return then
			return
		end
		if not (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)) then
			return
		end
		if not ui.inputBox:IsFocused() then
			return
		end
		sendPrompt(ui.inputBox.Text)
	end)

	ui.confirmButton.MouseButton1Click:Connect(function()
		if not pendingOffer then
			return
		end
		local ok, msg = scriptManager:applyAction(pendingOffer.action)
		if ok then
			ui:addMessage("RoBot", msg, false)
		else
			ui:addMessage("RoBot", "Could not create: " .. msg, true)
		end
		ui:clearActionPreview()
		pendingOffer = nil
	end)

	ui.cancelButton.MouseButton1Click:Connect(function()
		ui:clearActionPreview()
		pendingOffer = nil
		ui:addMessage("RoBot", "Cancelled. Ask again anytime.", false)
	end)

	task.defer(function()
		templateManager:loadCache()
	end)
end)

if not ok then
	warn("[RoBot] Plugin failed to load: " .. tostring(err))
end
