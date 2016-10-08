local function do_keyboard_flood(chat_id)
    --no: enabled, yes: disabled
    local status = db:hget('chat:'..chat_id..':settings', 'Flood') or config.chat_settings['settings']['Flood'] --check (default: disabled)
    if status == 'on' then
        status = _("✅ | ON")
    elseif status == 'off' then
        status = _("❌ | OFF")
    end
    
    local hash = 'chat:'..chat_id..':flood'
    local action = (db:hget(hash, 'ActionFlood')) or config.chat_settings['flood']['ActionFlood']
    if action == 'kick' then
        action_label = _("⚡️ kick")
    elseif action == 'ban' then
        action_label = _("⛔ ️ban")
	elseif action == 'tempban' then
		action_label = _("🔑 tempban")
    end
    local num = (db:hget(hash, 'MaxFlood')) or config.chat_settings['flood']['MaxFlood']
    local keyboard
	if action ~= 'tempban' then
		keyboard = {
			inline_keyboard = {
				{
					{text = status, callback_data = 'flood:status:'..chat_id},
					{text = action_label, callback_data = 'flood:action:'..chat_id},
				},
				{
					{text = '➖', callback_data = 'flood:dim:'..chat_id},
					{text = num, callback_data = 'flood:alert:num'},
					{text = '➕', callback_data = 'flood:raise:'..chat_id},
				},
			}
		}
	else
		local ban_duration = db:hget(hash, 'TempBanDuration') or tostring(config.chat_settings.flood['TempBanDuration'])
		keyboard = {
			inline_keyboard = {
				{
					{text = status, callback_data = 'flood:status:'..chat_id},
					{text = action_label, callback_data = 'flood:action:'..chat_id},
				},
				{
					{text = _("Duration"), callback_data = 'flood:alert:num'},
					{text = '➖', callback_data = 'flood:reduce:'..chat_id},
					{text = ban_duration, callback_data = 'flood:alert:num'},
					{text = '➕', callback_data = 'flood:increase:'..chat_id},
				},
				{
					{text = _("Sensitivity"), callback_data = 'flood:alert:num'},
					{text = '➖', callback_data = 'flood:dim:'..chat_id},
					{text = num, callback_data = 'flood:alert:num'},
					{text = '➕', callback_data = 'flood:raise:'..chat_id},
				},
			}
		}
	end
    
	local order = { 'text', 'forward', 'image', 'gif', 'sticker', 'video' }
    local exceptions = {
		text = _("Texts"),
		forward = _("Forward"),
        sticker = _("Stickers"),
        image = _("Images"),
        gif = _("GIFs"),
        video = _("Videos"),
    }
    local hash = 'chat:'..chat_id..':floodexceptions'
    for i, media in pairs(order) do
		translation = exceptions[media]
        --ignored by the antiflood-> yes, no
        local exc_status = db:hget(hash, media) or config.chat_settings['floodexceptions'][media]
        if exc_status == 'yes' then
            exc_status = '✅'
        else
            exc_status = '❌'
        end
        local line = {
            {text = translation, callback_data = 'flood:alert:voice'},
            {text = exc_status, callback_data = 'flood:exc:'..media..':'..chat_id},
        }
        table.insert(keyboard.inline_keyboard, line)
    end
    
    --back button
    table.insert(keyboard.inline_keyboard, {{text = '🔙', callback_data = 'config:back:'..chat_id}})
    
    return keyboard
end

function step(count, direction)
	if 20 < count and count < 60 then
		return count + 10 * direction
	elseif 60 < count and count < 240 then
		return count + 30 * direction
	elseif 240 < count and count < 720 then
		return count + 60 * direction
	elseif 720 < count then
		return count + 720 * direction
	else
		local ex = {1, 2, 3, 5, 7, 10, 15, 20, 30, 50, 60, 90, 210, 240, 300, 660, 720, 1440}
		local index
		for i, v in pairs(ex) do
			if v == count then
				index = i
				break
			end
		end
		if index then
			return ex[index + direction]
		else
			return 10
		end
	end
end

function changeFloodSettings(chat_id, screm)
	local hash = 'chat:'..chat_id..':flood'
	if type(screm) == 'string' then
		if screm == 'kick' then
			db:hset(hash, 'ActionFlood', 'ban')
			return _("Now flooders will be banned")
        elseif screm == 'ban' then
			db:hset(hash, 'ActionFlood', 'tempban')
			return _("Now flooders will be temporary banned")
		elseif screm == 'tempban' then
        	db:hset(hash, 'ActionFlood', 'kick')
			return _("Now flooders will be kicked")
        end
    elseif type(screm) == 'number' then
    	local old = tonumber(db:hget(hash, 'MaxFlood')) or 5
    	local new
    	if screm > 0 then
    		new = db:hincrby(hash, 'MaxFlood', 1)
    		if new > 25 then
    			db:hincrby(hash, 'MaxFlood', -1)
				return _("%d is not a valid value!\n"):format(new)
						.. ("The value should be higher than 3 and lower then 26")
    		end
    	elseif screm < 0 then
    		new = db:hincrby(hash, 'MaxFlood', -1)
    		if new < 4 then
    			db:hincrby(hash, 'MaxFlood', 1)
				return _("%d is not a valid value!\n"):format(new)
						.. ("The value should be higher than 3 and lower then 26")
    		end
    	end
		return string.format('%d → %d', old, new)
    end 	
end

local function action(msg, blocks)
	if not msg.cb then return end
	local chat_id = msg.target_id or msg.chat.id
	if not roles.is_admin_cached(chat_id, msg.from.id) then
		api.answerCallbackQuery(msg.cb_id, _("You're no longer admin"))
		return
	end

	local header = _([[
You can manage the group flood settings from here.

*1st row*
• *ON/OFF*: the current status of the anti-flood
• *Kick/Ban*: what to do when someone is flooding

*2nd row*
• you can use *+/-* to change the current sensitivity of the antiflood system
• the number it's the max number of messages that can be sent in _5 seconds_
• max value: _25_, min value: _4_

*3rd row* and below
You can set some exceptions for the antiflood:
• ✅: the media will be ignored by the anti-flood
• ❌: the media won\'t be ignored by the anti-flood
• *Note*: in "_texts_" are included all the other types of media (file, audio...)
]])

    local text
        
        if blocks[1] == 'config' then
        text = _("Antiflood settings")
        end
        
        if blocks[1] == 'alert' then
            if blocks[2] == 'num' then
                text = _("⚖ Current sensitivity. Tap on the + or the -")
            elseif blocks[2] == 'voice' then
                text = _("⚠️ Tap on an icon!")
            end
            api.answerCallbackQuery(msg.cb_id, text)
            return
        end
        
        if blocks[1] == 'exc' then
            local media = blocks[2]
            local hash = 'chat:'..chat_id..':floodexceptions'
            local status = (db:hget(hash, media)) or 'no'
            if status == 'no' then
                db:hset(hash, media, 'yes')
                text = _("❎ [%s] will be ignored by the anti-flood"):format(media)
            else
                db:hset(hash, media, 'no')
                text = _("🚫 [%s] won't be ignored by the anti-flood"):format(media)
            end
        end
        
        local action
        if blocks[1] == 'action' or blocks[1] == 'dim' or blocks[1] == 'raise' then
            if blocks[1] == 'action' then
            action = db:hget('chat:'..chat_id..':flood', 'ActionFlood') or 'kick'
            elseif blocks[1] == 'dim' then
                action = -1
            elseif blocks[1] == 'raise' then
                action = 1
            end
            text = changeFloodSettings(chat_id, action)
		elseif blocks[1] == 'increase' then
			local hash = string.format('chat:%d:flood', chat_id)
			local old = tonumber(db:hget(hash, 'TempBanDuration')) or config.chat_settings.flood['TempBanDuration']
			local new = step(old, 1)
			db:hset(hash, 'TempBanDuration', new)
			text = string.format('📈 %dm → %dm', old, new)
		elseif blocks[1] == 'reduce' then
			local hash = string.format('chat:%d:flood', chat_id)
			local old = tonumber(db:hget(hash, 'TempBanDuration')) or config.chat_settings.flood['TempBanDuration']
			if old <= 1 then
				text = _("⚠️ Value must been positive")
			else
				local new = step(old, -1)
				db:hset(hash, 'TempBanDuration', new)
				text = string.format('📉 %dm → %dm', old, new)
			end
        end
        
        if blocks[1] == 'status' then
            local status = db:hget('chat:'..chat_id..':settings', 'Flood') or config.chat_settings['settings']['Flood']
            text = misc.changeSettingStatus(chat_id, 'Flood'):escape_hard()
        end
        
    local keyboard = do_keyboard_flood(chat_id)
        api.editMessageText(msg.chat.id, msg.message_id, header, keyboard, true)
        api.answerCallbackQuery(msg.cb_id, text)
end

return {
    action = action,
    triggers = {
        '^###cb:flood:(alert):(num)$',
        '^###cb:flood:(alert):(voice)$',
        '^###cb:flood:(status):(-?%d+)$',
        '^###cb:flood:(action):(-?%d+)$',
        '^###cb:flood:(dim):(-?%d+)$',
        '^###cb:flood:(raise):(-?%d+)$',
		'^###cb:flood:(reduce):(-?%d+)$',
		'^###cb:flood:(increase):(-?%d+)$',
        '^###cb:flood:(exc):(%a+):(-?%d+)$',
        
        '^###cb:(config):antiflood:'
    }
}
