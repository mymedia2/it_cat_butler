-- Sends to the mentioned user the notification with message
local function notify(recipient, msg, ln)
	local text
	if msg.chat.username then
		local link = string.format('https://telegram.me/%s/%d', msg.chat.username, msg.message_id)
		text = lang[ln].notifications.mention1:compose(msg.from.first_name:mEscape(), link, msg.chat.title:mEscape())
	else
		text = lang[ln].notifications.mention2:compose(msg.from.first_name:mEscape(), msg.chat.title:mEscape())
	end
	local clue1 = api.sendMessage(recipient, text, true, nil, true)
	local clue2 = api.forwardMessage(recipient, msg.chat.id, msg.message_id, true)

	-- save IDs messages to allow the user to unsubscribe in private
	local hash = string.format('chat:%d:mentions', recipient)
	if clue1.ok and clue2.ok then
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
				notify(user_id, msg, msg.ln)
			end
		end
	end
	return msg
end

-- Subscribes the user and returns message text and flag of button "start me"
local function subscribe(mentions_source, customer, ln)
	local hash = string.format('chat:%d:subscribtions', mentions_source)
	local previous_state = db:hget(hash, customer)
	db:hset(hash, customer, 'on')

	local result = lang[ln].notifications.subscribe_success
	if previous_state == 'on' then
		result = lang[ln].notifications.subscribe_already
	elseif true then -- if user block the bot
		result = result .. '\n' .. lang[ln].notifications.reminder
		return result, true
	end
	return result, false
end

-- Unsubscribes the user and returns the text for answer
local function unsubscribe(mentions_source, customer, ln)
	local hash = string.format('chat:%d:subscribtions', mentions_source)
	local previous_state = db:hget(hash, customer)
	db:hset(hash, customer, 'off')
	local result = lang[ln].notifications.unscribe_already
	if previous_state == 'on' then
		result = lang[ln].notifications.unscribe_success
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
		local text, start_me = subscribe(msg.chat.id, msg.from.id, msg.ln)
		-- Button "start me" still isn't implemented
		--if start_me then
		--	misc.sendStartMe(msg.chat.id, text, msg.ln)
		--else
			api.sendMessage(msg.chat.id, text, true)
		--end
	end

	if blocks[1] == 'unscribe' or blocks[1] == 'unsubscribe' then
		if msg.chat.type == 'private' then
			local mentions_source = find_source(msg)
			local text
			if mentions_source then
				text = unsubscribe(mentions_source, msg.chat.id, msg.ln)
			else
				text = lang[msg.ln].notifications.help_unsubscribe
			end
			api.sendMessage(msg.chat.id, text, true)
		else
			local text = unsubscribe(msg.chat.id, msg.from.id, msg.ln)
			api.sendMessage(msg.chat.id, text, true)
		end
	end
end

return {
	on_each_msg = scan_mentions,
	action = control,
	triggers = {
		config.cmd..'(subscribe)$',
		config.cmd..'(unscribe)$',
		config.cmd..'(unsubscribe)$',
	}
}
