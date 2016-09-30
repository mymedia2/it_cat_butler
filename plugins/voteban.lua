function do_keyboard_vote(chat_id, user_id)
	return {
		inline_keyboard = {
			{
				{text = _("Yes"), callback_data = string.format('voteban:increase:%d:%d', chat_id, user_id)},
				{text = _("No"), callback_data = string.format('voteban:decrease:%d:%d', chat_id, user_id)},
			},
			{
				{text = _("Revoke the vote"), callback_data = string.format('voteban:revoke:%d:%d', chat_id, user_id)},
				{text = _("Cancel the poll"), callback_data = string.format('voteban:cancel:%d:%d', chat_id, user_id)},
			},
		}
	}
end

function get_header(chat_id, initiator, defendant, score, max, previous_exists)
	local lines = {}
	
	if previous_exists then
		table.insert(lines, _("This is a continuation of the previous poll\n"))
	end

	table.insert(lines, _("%s suggests a ban %s. Ban him?"):format(users.full_name(initiator), users.full_name(defendant)))
	-- TODO: make plural forms
	table.insert(lines, _("%d users voted for ban. Requires an additional %d users."):format(score, max - score))

	if defendant.id == bot.id then
		table.insert(lines, _("\nInformative poll. You can't vote for ban me."))
	elseif initiator.id == defendant.id then
		table.insert(lines, _("\nInformative poll. You can't vote for yourself."))
	elseif roles.is_admin_cached({chat = {id = chat_id}, from = {id = defendant.id}}) then
		table.insert(lines, _("\nInformative poll. User won't banned because he is an admin."))
	elseif not roles.bot_is_admin(chat_id) then
		-- TODO: add info about how to make the bot admin
		table.insert(lines, _("\nInformative poll. User won't banned because I'am not an admin."))
	end

	return table.concat(lines, '\n')
end

function generate_poll(msg, defendant, tail)
	if not defendant then
		api.sendMessage(msg.chat.id, _("Against whom do you vote?"))
		return false
	end

	-- TODO: get previous poll, set settings of new poll: score, started time [or maybe stopped time],
	-- number of voted, informative or not and probably something else
	-- ...
	local hash = string.format('chat:%d:voteban', msg.chat.id)
	local quorum = db:hget(hash, 'quorum') or config.chat_settings.voteban.quorum
	local duration = db:hget(hash, 'duration') or config.chat_settings.voteban.duration

	-- Detect if previous poll was or not and set the initiator
	local hash = string.format('chat:%d:voteban:%d', msg.chat.id, defendant.id)
	local started = tonumber(db:hget(hash, 'started'))
	local initiator, was_active_previous
	if started and os.time() - started >= duration then
		db:hset(hash, 'initiator', msg.from.id)
		initiator = msg.from
		was_active_previous = true
	else
		local user_id = tonumber(db:hget(hash, 'initiator'))
		if not user_id or msg.from.id == user_id then
			initiator = msg.from
		else
			initiator = api.getChat(user_id).result
		end
		was_active_previous = false
	end

	-- Send the keyboard into the chat
	local score = tonumber(db:hget(hash, 'score')) or 0
	local keyboard = do_keyboard_vote(msg.chat.id, defendant.id)
	local text = get_header(msg.chat.id, initiator, defendant, score, quorum, was_active_previous) .. (tail or '')
	local res = api.sendKeyboard(msg.chat.id, text, keyboard, true)
	if not res then return false end

	-- Close previous poll if it exists
	if was_active_previous then
		local previous = tonumber(db:hget(hash, 'previous'))
		local text = _("This poll was closed because new poll was generated")
		api.editMessageText(msg.chat.id, previous, text, nil, true)
	end

	-- Store information about new poll
	db:hset(hash, 'started', res.result.date)
	db:hset(hash, 'previous', res.result.message_id)

	return true
end

function action(msg, blocks)
	if blocks[1] == 'voteban' then
		local hash = string.format('chat:%d:voteban', msg.chat.id)
		local status = db:hget(hash, 'status') or config.chat_settings.voteban.status
		if status == 'off' then
			if roles.is_admin_cached(msg) and not misc.is_silentmode_on(msg.chat.id) then
				api.sendMessage(msg.chat.id, _("Polls for bans are disabled"))
			end
			return
		end
		local nominated  -- stores the user id
		local tail

		-- choose the hero
		if msg.mentions then
			nominated = next(msg.mentions)
			if next(msg.mentions, nominated) then
				tail = '\n\n' .. _("*Warning*: Multiple mentions still isn't supported")
			end
			-- FIXME: make that the follow variable would store the user object for decrease API queries
			nominated = api.getChat(nominated).result
		elseif msg.reply then
			nominated = msg.reply.from
		elseif tonumber(blocks[2]) then
			nominated = api.getChat(blocks[2]).result
		end

		generate_poll(msg, nominated, tail)
	end
	if msg.cb then
		local chat_id = tonumber(blocks[2])
		local defendant = tonumber(blocks[3])
		if blocks[1] == 'increase' then
			-- ...
		end
		if blocks[1] == 'decrease' then
			-- ...
		end
		if blocks[1] == 'revoke' then
			-- ...
		end
		if blocks[1] == 'cancel' then
			-- ...
		end
	end
end

return {
	action = action,
	triggers = {
		config.cmd..'(voteban) (.*)',
		config.cmd..'(voteban)$',

		'^###cb:voteban:(increase):(-?%d+):(-?%d+)$',
		'^###cb:voteban:(decrease):(-?%d+):(-?%d+)$',
		'^###cb:voteban:(revoke):(-?%d+):(-?%d+)$',
		'^###cb:voteban:(cancel):(-?%d+):(-?%d+)$',
	}
}
