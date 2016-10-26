local plugin = {}

local function changeWarnSettings(chat_id, action)
    local current = tonumber(db:hget('chat:'..chat_id..':warnsettings', 'max')) or 3
    local new_val
    if action == 1 then
        if current > 12 then
            return _("The new value is too high ( > 12)")
        else
            new_val = db:hincrby('chat:'..chat_id..':warnsettings', 'max', 1)
            return current..'->'..new_val
        end
    elseif action == -1 then
        if current < 2 then
            return _("The new value is too low ( < 1)")
        else
            new_val = db:hincrby('chat:'..chat_id..':warnsettings', 'max', -1)
            return current..'->'..new_val
        end
    elseif action == 'status' then
        local status = (db:hget('chat:'..chat_id..':warnsettings', 'type')) or 'kick'
        if status == 'kick' then
            db:hset('chat:'..chat_id..':warnsettings', 'type', 'ban')
            return _("New action on max number of warns received: ban")
        elseif status == 'ban' then
            db:hset('chat:'..chat_id..':warnsettings', 'type', 'kick')
            return _("New action on max number of warns received: kick")
        end
    end
end

local function changeCharSettings(chat_id, field)
	local chars = {
		arab_kick = _("Senders of arab messages will be kicked"),
		arab_ban = _("Senders of arab messages will be banned"),
		arab_allow = _("Arab language allowed"),
		rtl_kick = _("The use of the RTL character will lead to a kick"),
		rtl_ban = _("The use of the RTL character will lead to a ban"),
		rtl_allow = _("RTL character allowed"),
	}

    local hash = 'chat:'..chat_id..':char'
    local status = db:hget(hash, field)
    local text
    if status == 'allowed' then
        db:hset(hash, field, 'kick')
        text = chars[field:lower()..'_kick']
    elseif status == 'kick' then
        db:hset(hash, field, 'ban')
        text = chars[field:lower()..'_ban']
    elseif status == 'ban' then
        db:hset(hash, field, 'allowed')
        text = chars[field:lower()..'_allow']
    else
        db:hset(hash, field, 'allowed')
        text = chars[field:lower()..'_allow']
    end

    return text
end

local function step(count, direction)
	assert(direction == -1 or direction == 1)
	if count <= 5 and direction == -1 then return 5 end
	if count >= 720 and direction == 1 then return 720 end

	local ex = {5, 10, 15, 20, 30, 45, 60, 120, 180, 300, 360, 480, 600, 720}
	local index
	for i, v in pairs(ex) do
		if v == count then
			index = i
			break
		end
	end
	if not index then return 10 end
	return ex[index + direction]
end

local function changeVotebanSetting(chat_id, action)
	local hash = string.format('chat:%d:voteban', chat_id)

	if action == 'DimDuration' or action == 'RaiseDuration' then
		local old_value = tonumber(db:hget(hash, 'duration') or config.chat_settings.voteban.duration)
		local direction = 1
		if action == 'DimDuration' then direction = -1 end
		local new_value = step(old_value / 60, direction) * 60
		db:hset(hash, 'duration', new_value)
		return old_value, new_value
	end

	if action == 'DimQuorum' or action == 'RaiseQuorum' then
		local old_value = tonumber(db:hget(hash, 'quorum') or config.chat_settings.voteban.quorum)
		local new_value = old_value + 1
		if action == 'DimQuorum' then
			new_value = old_value - 1
		end
		if new_value < 2 then new_value = old_value end
		db:hset(hash, 'quorum', new_value)
		return old_value, new_value
	end

	error('unreachable')
end

local function usersettings_table(settings, chat_id)
    local return_table = {}
    local icon_off, icon_on = '👤', '👥'
    for field, default in pairs(settings) do
        if field == 'Extra' or field == 'Rules' then
            local status = (db:hget('chat:'..chat_id..':settings', field)) or default
            if status == 'off' then
                return_table[field] = icon_off
            elseif status == 'on' then
                return_table[field] = icon_on
            end
        end
    end
    
    return return_table
end

local function adminsettings_table(settings, chat_id)
    local return_table = {}
    local icon_off, icon_on = '☑️', '✅'
    for field, default in pairs(settings) do
        if field ~= 'Extra' and field ~= 'Rules' and field ~= 'voteban' then
            local status = (db:hget('chat:'..chat_id..':settings', field)) or default
            if status == 'off' then
                return_table[field] = icon_off
            elseif status == 'on' then
                return_table[field] = icon_on
            end
        end
    end
    
    return return_table
end

local function charsettings_table(settings, chat_id)
    local return_table = {}
    local icon_allow, icon_not_allow = '✅', '🔐'
    for field, default in pairs(settings) do
        local status = (db:hget('chat:'..chat_id..':char', field)) or default
        if status == 'kick' or status == 'ban' then
            return_table[field] = icon_not_allow..' '..status
        elseif status == 'allowed' then
            return_table[field] = icon_allow
        end
    end
    
    return return_table
end

local function insert_voteban_section(keyboard, chat_id)
	local hash = string.format('chat:%d:settings', chat_id)
	local status = db:hget(hash, 'voteban') or config.chat_settings.voteban.status
	if status == 'off' then
		status = '👤'
	else
		status = '👥'
	end
	hash = string.format('chat:%d:voteban', chat_id)
	local duration = tonumber(db:hget(hash, 'duration')) or config.chat_settings.voteban.duration
	if duration < 70 * 60 then
		-- TRANSLATORS: this is an abbreviation for minutes
		duration = _("%d min"):format(duration / 60)
	else
		-- TODO: make plural forms
		duration = _("%d hours"):format(duration / 3600)
	end
	local quorum = db:hget(hash, 'quorum') or config.chat_settings.voteban.quorum

	table.insert(keyboard, {
		{text = _("Polls for ban"), callback_data='menu:alert:settings'},
		{text = status, callback_data='menu:voteban:'..chat_id},
	})
	table.insert(keyboard, {
		{text = _("Duration"), callback_data='menu:alert:values'},
		{text = '➖', callback_data='menu:DimDuration:'..chat_id},
		{text = tostring(duration), callback_data='menu:alert:values'},
		{text = '➕', callback_data='menu:RaiseDuration:'..chat_id},
	})
	table.insert(keyboard, {
		{text = _("Quorum"), callback_data='menu:alert:values'},
		{text = '➖', callback_data='menu:DimQuorum:'..chat_id},
		{text = tostring(quorum), callback_data='menu:alert:values'},
		{text = '➕', callback_data='menu:RaiseQuorum:'..chat_id},
	})
end

local function insert_settings_section(keyboard, settings_section, chat_id)
	local strings = {
		Welcome = _("Welcome"),
		Goodbye = _("Goodbye"),
		Extra = _("Extra"),
		Flood = _("Anti-flood"),
		Silent = _("Silent mode"),
		Rules = _("Rules"),
		Arab = _("Arab"),
		Rtl = _("RTL"),
		Antibot = _("Ban bots"),
		Welbut = _("Welcome + rules button"),
	}

    for key, icon in pairs(settings_section) do
        local current = {
            {text = strings[key] or key, callback_data = 'menu:alert:settings:'..chat_id},
            {text = icon, callback_data = 'menu:'..key..':'..chat_id}
        }
        table.insert(keyboard.inline_keyboard, current)
    end

    return keyboard
end

local function doKeyboard_menu(chat_id)
    local keyboard = {inline_keyboard = {}}
    
    local settings_section = adminsettings_table(config.chat_settings['settings'], chat_id)
    keyboad = insert_settings_section(keyboard, settings_section, chat_id)
    
    settings_section = usersettings_table(config.chat_settings['settings'], chat_id)
    keyboad = insert_settings_section(keyboard, settings_section, chat_id)
    
    settings_section = charsettings_table(config.chat_settings['char'], chat_id)
    keyboad = insert_settings_section(keyboard, settings_section, chat_id)
    
	insert_voteban_section(keyboard.inline_keyboard, chat_id)

    --warn
    local max = (db:hget('chat:'..chat_id..':warnsettings', 'max')) or config.chat_settings['warnsettings']['max']
    local action = (db:hget('chat:'..chat_id..':warnsettings', 'type')) or config.chat_settings['warnsettings']['type']
	if action == 'kick' then
		action = _("👞 kick")
	else
		action = _("🔨️ ban")
	end
    local warn = {
		{text = '➖', callback_data = 'menu:DimWarn:'..chat_id},
		{text = '#'..max, callback_data = 'menu:alert:warns:'..chat_id},
		{text = action, callback_data = 'menu:ActionWarn:'..chat_id},
		{text = '➕', callback_data = 'menu:RaiseWarn:'..chat_id},
    }
    table.insert(keyboard.inline_keyboard, warn)
    
    --back button
    table.insert(keyboard.inline_keyboard, {{text = '🔙', callback_data = 'config:back:'..chat_id}})
    
    return keyboard
end

function plugin.onCallbackQuery(msg, blocks)
    local chat_id = msg.target_id
	if not roles.is_admin_cached(chat_id, msg.from.id) then
		api.answerCallbackQuery(msg.cb_id, _("You're no longer admin"))
	else
	    if not chat_id then
	        api.sendAdmin('Not msg.target_id -> menu') return
	end

	local menu_first = _([[
Manage the settings of the group.
📘 _Short legenda_:

*Extra*:
• 👥: the bot will reply *in the group*, with everyone
• 👤: the bot will reply *in private* with normal users and in the group with admins

*Silent mode*:
If enabled, the bot won't send a confirmation message in the group when someone use /config or /dashboard.
It will just send the message in private.

*Polls for ban*:
You can activate this feature for democratic chats, and group members will be able to start voting for ban another member of a chat, otherwise only admins will be able to start such polls.
_Duration_ setting specifies the time after which the poll will be finished as having no decision of community.
_Quorum_ specifies the minimal needed number of votes from members for the decision.
If defendant has a sufficient number of votes (more then half), he will be automatically banned.
]])

    local keyboard, text
    
    if blocks[1] == 'config' then
        keyboard = doKeyboard_menu(chat_id)
            api.editMessageText(msg.chat.id, msg.message_id, menu_first, true, keyboard)
    else
	    if blocks[2] == 'alert' then
	        if blocks[3] == 'settings' then
                text = _("⚠️ Tap on an icon!")
            elseif blocks[3] == 'warns' then
                text = _("⚠️ Use the row below to change the warns settings!")
			elseif blocks[3] == 'values' then
				text = _("⚠️ Change the value via plus or minus!")
            end
            api.answerCallbackQuery(msg.cb_id, text or '')
            return
        end
        if blocks[2] == 'DimWarn' or blocks[2] == 'RaiseWarn' or blocks[2] == 'ActionWarn' then
            if blocks[2] == 'DimWarn' then
                text = changeWarnSettings(chat_id, -1)
            elseif blocks[2] == 'RaiseWarn' then
                text = changeWarnSettings(chat_id, 1)
            elseif blocks[2] == 'ActionWarn' then
                text = changeWarnSettings(chat_id, 'status')
            end
        elseif blocks[2] == 'Rtl' or blocks[2] == 'Arab' then
            text = changeCharSettings(chat_id, blocks[2])
		elseif blocks[2] == 'DimDuration' or blocks[2] == 'RaiseDuration'
			or blocks[2] == 'DimQuorum' or blocks[2] == 'RaiseQuorum' then
			text = string.format('%d → %d', changeVotebanSetting(chat_id, blocks[2]))
        else
            text = misc.changeSettingStatus(chat_id, blocks[2])
        end
        keyboard = doKeyboard_menu(chat_id)
            api.editMessageText(msg.chat.id, msg.message_id, menu_first, true, keyboard)
        if text then api.answerCallbackQuery(msg.cb_id, '⚙ '..text) end --workaround to avoid to send an error to users who are using an old inline keyboard
    end
    end
end

plugin.triggers = {
    onCallbackQuery = {
        '^###cb:(menu):(alert):(settings)',
    	'^###cb:(menu):(alert):(warns)',
    	
    	'^###cb:(menu):(.*):',
    	'^###cb:(config):menu:(-?%d+)$'
	}
}

return plugin
