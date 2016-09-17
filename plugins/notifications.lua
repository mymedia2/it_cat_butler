-- Sends to the mentioned user the notification with message
local function notify(recipient, msg)
	local text
	if msg.chat.username then
		local link = string.format('https://telegram.me/%s/%d', msg.chat.username, msg.message_id)
		text = _('%s [mentioned](%s) you in the group "%s"'):format(msg.from.first_name:escape(), link, msg.chat.title:escape())
	else
		text = _('%s mentioned you in the group "%s"'):format(msg.from.first_name:escape(), msg.chat.title:escape())
	end
	local clue1 = api.sendMessage(recipient, text, true, nil, true)
	local clue2 = api.forwardMessage(recipient, msg.chat.id, msg.message_id, true)

	-- save IDs messages to allow the user to unsubscribe in private
	local hash = string.format('chat:%d:mentions', recipient)
	if clue1 and clue2 then
		db:hset(hash, clue1.result.message_id, msg.chat.id)
		db:hset(hash, clue2.result.message_id, msg.chat.id)
	end
end

-- Examines for the presence of mentions
local function scan_mentions(msg)
	if msg.chat.type ~= 'private' and msg.mentions then
		for user_id in pairs(msg.mentions) do
			local hash = string.format('chat:%d:subscribtions', msg.chat.id)
			if msg.from.id ~= user_id and db:hget(hash, user_id) == 'on' then
				notify(user_id, msg)
			end
		end
	end
	return true
end

-- Subscribes the user and returns message text and flag of button "start me"
local function subscribe(mentions_source, customer)
	local hash = string.format('chat:%d:subscribtions', mentions_source)
	local previous_state = db:hget(hash, customer)
	db:hset(hash, customer, 'on')

	local result = _('_The subscribe to your mentions has activated successfully_')
	if previous_state == 'on' then
		result = _('_Your subscribe already activated_')
	elseif true then -- if user block the bot
		result = result .. '\n' .. _('Notifications will not come until you message me')
		return result, true
	end
	return result, false
end

-- Unsubscribes the user and returns the text for answer
local function unsubscribe(mentions_source, customer)
	local hash = string.format('chat:%d:subscribtions', mentions_source)
	local previous_state = db:hget(hash, customer)
	db:hset(hash, customer, 'off')
	local result = _('_The subscribe has deactivated successfully_')
	if previous_state ~= 'on' then
		result = _('_Your subscribe already deactivated_')
	end
	return result
end

-- Finds a group ID using reply message
local function find_source(msg)
	local hash = string.format('chat:%d:mentions', msg.chat.id)
	if not msg.reply then return false end
	local mentions_source = db:hget(hash, msg.reply.message_id)
	if not mentions_source then return false end
	return mentions_source
end

-- Processes control commands and sends answers
local function control(msg, blocks)
	if blocks[1] == 'subscribe' then
		if msg.chat.type == 'private' then return end
		local text, start_me = subscribe(msg.chat.id, msg.from.id)
		-- Button "start me" still isn't implemented
		--if start_me then
		--	misc.sendStartMe(msg.chat.id, text)
		--else
			api.sendMessage(msg.chat.id, text, true)
		--end
	end

	if blocks[1] == 'unscribe' or blocks[1] == 'unsubscribe' then
		if msg.chat.type == 'private' then
			local mentions_source = find_source(msg)
			local text
			if mentions_source then
				text = unsubscribe(mentions_source, msg.chat.id)
			else
				text = _('To unsubscribe, answer me to unwanted notification with command `/unscribe`')
			end
			api.sendMessage(msg.chat.id, text, true)
		else
			local text = unsubscribe(msg.chat.id, msg.from.id)
			api.sendMessage(msg.chat.id, text, true)
		end
	end
end

return {
	onmessage = scan_mentions,
	action = control,
	triggers = {
		config.cmd..'(subscribe)$',
		config.cmd..'(unscribe)$',
		config.cmd..'(unsubscribe)$',
	}
}
