local function scan_mentions(msg)
	--vardump(msg)
	if msg.chat.type == 'private' then return msg end

	if not msg.entities then return msg end
	for i, v in pairs(msg.entities) do
		if v.type == 'mention' then
			local username = msg.text:sub(v.offset + 1, v.offset + v.length)
			print('Name detected: '..username)
			local hash = string.format('bot:usernames:%d', msg.chat.id)
			local user_id = db:hget(hash, username)
			if user_id then
				hash = string.format('chat:%d:subscribes', msg.chat.id)
				if db:hget(hash, user_id) == 'yes' then
					local text
					if msg.chat.username then
						local link = string.format('https://telegram.me/%s/%d', msg.chat.username, msg.message_id)
						text = lang[msg.ln].notifications.mention1:compose(msg.from.first_name:mEscape(), link, msg.chat.title:mEscape())
					else
						text = lang[msg.ln].notifications.mention2:compose(msg.from.first_name:mEscape(), msg.chat.title:mEscape())
					end
					api.sendMessage(user_id, text, true, nil, true)
					api.forwardMessage(user_id, msg.chat.id, msg.message_id, true)
				end
			end
		end
	end
	return msg
end

local function control(msg, blocks)
	--vardump(msg)
	--vardump(blocks)
	local hash = string.format('chat:%d:subscribes', msg.chat.id)

	if blocks[1] == 'subscribe' then
		if msg.chat.type == 'private' then return end
		db:hset(hash, msg.from.id, 'yes')
		api.sendMessage(msg.chat.id, lang[ln].notifications.subscribe, true)
	end

	if blocks[1] == 'unscribe' then
		if msg.chat.type == 'private' then
			api.sendMessage(msg.chat.id, 'Not implemented')
		else
			db:hset(hash, msg.from.id, 'no')
			api.sendMessage(msg.chat.id, lang[ln].notifications.unscribe, true)
		end
	end
end

return {
	on_each_msg = scan_mentions,
	action = control,
	triggers = {
		config.cmd..'(subscribe)$',
		config.cmd..'(unscribe)$',
	}
}
