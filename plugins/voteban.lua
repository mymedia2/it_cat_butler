local function do_keyboard_vote(user_id)
	return {
		inline_keyboard = {
			{
				{text = _("Yes"), callback_data = string.format('voteban:increase:%d', user_id)},
				{text = _("No"), callback_data = string.format('voteban:decrease:%d', user_id)},
			},
			{
				{text = _("Revoke the vote"), callback_data = string.format('voteban:revoke:%d', user_id)},
				{text = _("Cancel the poll"), callback_data = string.format('voteban:cancel:%d', user_id)},
			},
		}
	}
end

-- return text of messages with current information about ballot
local function get_header(initiator, defendant, supports, oppositionists, quorum, expired, informative, previous_exists)
	assert(supports + oppositionists < quorum)
	assert(not informative or informative == 'against bot' or informative == 'against himself' or
		   informative == 'against admin' or informative == 'bot not admin')
	local lines = {}
	
	if previous_exists then
		table.insert(lines, _("This is _continuation_ of the previous poll."))
	end

	if initiator.id ~= defendant.id then
		table.insert(lines, _("%s suggests a ban %s. Ban him?\n"):format(users.full_name(initiator), users.full_name(defendant)))
	else
		table.insert(lines, _("%s suggests a ban himself. Ban him?\n"):format(users.full_name(initiator)))
	end

	-- TODO: make plural forms
	table.insert(lines, _("%d users voted *for ban*."):format(supports))
	table.insert(lines, _("%d users voted *against ban*."):format(oppositionists))
	table.insert(lines, _("Requires additional %d users."):format(quorum - supports - oppositionists))
	table.insert(lines, _("The poll will be closed in %d minutes"):format((expired - os.time()) / 60))

	if informative == 'against bot' then
		table.insert(lines, _("\n*Informative poll*. You can't vote for ban me."))
	end
	if informative == 'against himself' then
		table.insert(lines, _("\n*Informative poll*. You can't vote for ban yourself."))
	end
	if informative == 'against admin' then
		table.insert(lines, _("\n*Informative poll*. User won't banned because he is an admin."))
	end
	if informative == 'bot not admin' then
		-- TODO: add info about how to make the bot admin
		table.insert(lines, _("\n*Informative poll*. User won't banned because I'am not an admin."))
	end

	return table.concat(lines, '\n')
end

local function generate_poll(msg, defendant)
	if not defendant then
		api.sendMessage(msg.chat.id, _("Against whom do you vote?"))
		return false
	end

	local hash = string.format('chat:%d:voteban', msg.chat.id)
	local quorum = tonumber(db:hget(hash, 'quorum') or config.chat_settings.voteban.quorum)
	local duration = tonumber(db:hget(hash, 'duration') or config.chat_settings.voteban.duration)
	duration = duration * 60  -- convert to seconds

	-- Detect if previous poll was or not and set the initiator
	local hash = string.format('chat:%d:voteban:%d', msg.chat.id, defendant.id)
	local expired = tonumber(db:hget(hash, 'expired'))
	local initiator, was_active_previous
	if expired and os.time() < expired then
		db:hset(hash, 'initiator', msg.from.id)
		initiator = msg.from
		was_active_previous = true
	else
		local user_id = tonumber(db:hget(hash, 'initiator'))
		if not user_id or msg.from.id == user_id then
			db:hset(hash, 'initiator', msg.from.id)
			initiator = msg.from
		else
			initiator = api.getChat(user_id).result
		end
		was_active_previous = false
	end

	-- Detect informative poll
	local informative
	if defendant.id == bot.id then
		informative = 'against bot'
	elseif initiator.id == defendant.id then
		informative = 'against himself'
	elseif roles.is_admin_cached(msg.chat.id, defendant.id) then
		informative = 'against admin'
	elseif not roles.bot_is_admin(msg.chat.id) then
		informative = 'bot not admin'
	end

	-- Send the keyboard into the chat
	local supports = tonumber(db:scard(hash .. ':supports'))
	local oppositionists = tonumber(db:scard(hash .. ':oppositionists'))
	local keyboard = do_keyboard_vote(defendant.id)
	local text = get_header(initiator, defendant, supports, oppositionists,
							quorum, os.time() + duration, informative, was_active_previous)
	local res = api.sendKeyboard(msg.chat.id, text, keyboard, true)
	if not res then return false end

	-- Close previous poll if it exists
	if was_active_previous then
		local previous_id = tonumber(db:hget(hash, 'msg_id'))
		local text = _("The poll for ban of %s was closed because new poll was created"):format(users.full_name(defendant))
		api.editMessageText(msg.chat.id, previous_id, text, nil, true)
	end

	-- Store information about new poll
	db:hset(hash, 'expired', res.result.date + duration)
	db:hset(hash, 'msg_id', res.result.message_id)
	db:hset(hash, 'quorum', quorum)
	if informative then
		db:hset(hash, 'informative', informative)
	end
	if was_active_previous then
		db:hset(hash, 'was_active_previous', 'yes')
	end

	return true
end

-- edits the message which was associated with the poll
local function rebuild_poll_message(chat_id, user_id)
	local hash = string.format('chat:%d:voteban:%d', chat_id, user_id)
	local initiator = tonumber(db:hget(hash, 'initiator'))
	local expired = tonumber(db:hget(hash, 'expired'))
	local msg_id = tonumber(db:hget(hash, 'msg_id'))
	local quorum = tonumber(db:hget(hash, 'quorum'))
	local informative = db:hget(hash, 'informative')
	local was_active_previous = db:hget(hash, 'was_active_previous')

	local supports = tonumber(db:scard(hash .. ':supports'))
	local oppositionists = tonumber(db:scard(hash .. ':oppositionists'))

	initiator = api.getChat(initiator).result
	defendant = api.getChat(user_id).result

	local keyboard = do_keyboard_vote(defendant.id)
	local text = get_header(initiator, defendant, supports, oppositionists,
							quorum, expired, informative, was_active_previous)
	local res = api.editMessageText(chat_id, msg_id, text, keyboard, true)
end

-- disposes the vote and returns true if decision has changed
local function cast_vote(chat_id, defendant_id, voter_id, value)
	local hash = string.format('chat:%d:voteban:%d', chat_id, defendant_id)
	if value > 0 then
		db:srem(hash .. ':oppositionists', voter_id)
		return db:sadd(hash .. ':supports', voter_id) == 1
	elseif value < 0 then
		db:srem(hash .. ':supports', voter_id)
		return db:sadd(hash .. ':oppositionists', voter_id) == 1
	else
		return db:srem(hash .. ':supports', voter_id) == 1
			or db:srem(hash .. ':oppositionists', voter_id) == 1
	end
end

local function update()
	-- FIXME: they don't recommend use keys function
	for _, hash in pairs(db:keys('chat:*:voteban:*')) do
		local chat_id, user_id = hash:match('chat:(-?%d+):voteban:(-?%d+)')
		local expired = db:hget(hash, 'expired')
		local msg_id = db:hget(hash, 'msg_id')
		local defendant = api.getChat(user_id).result
		if expired < os.time() then
			-- Poll is finished
			local text = _("Poll was closed because not get enough number of people for ban %s"):format(users.full_name(defendant))
			api.editMessageText(chat_id, msg_id, text, nil, true)
			db:del(hash)
		else
			-- Poll is continue
			--local initiator = api.getChat(db:hget(hash, 'initiator')).result
			--local supports = tonumber(db:hget(hash, 'supports')) or 0
			--local oppositionists = tonumber(db:hget(hash, 'oppositionists')) or 0
			--local quorum = tonumber(db:hget(hash, 'quorum'))
			--local informative = db:hget(hash, 'informative')
			--local was_active_previous = db:hget(hash, 'was_active_previous')
			--local keyboard = do_keyboard_vote(chat_id, defendant.id)
			--local text = get_header(initiator, defendant, supports,
			--				  oppositionists, quorum, informative, was_active_previous)
			--api.editMessageText(chat_id, msg_id, text, keyboard, true)
		end
	end
end

-- counts of votes, edits message header and returns text for callback answer
local function change_votes_machinery(chat_id, user_id, from_id, value)
	local hash = string.format('chat:%d:voteban:%d', chat_id, user_id)
	local informative = db:hget(hash, 'informative')

	if from_id == defendant and informative ~= 'against himself' then
		return _("You can't vote about yourself")
	end

	local text, without_name
	if cast_vote(chat_id, user_id, from_id, value) then
		rebuild_poll_message(chat_id, user_id)

		if value > 0 then
			text = _("You have voted against %s")
		elseif value < 0 then
			text = _("You have voted for save %s")
		else
			text, without_name = _("You have revoked your vote"), true
		end
	elseif value > 0 then
		text = _("You already voted against %s")
	elseif value < 0 then
		text = _("You already voted for save %s")
	else
		text, without_name = _("You already revoked your vote"), true
	end

	if not without_name then
		text = text:format(users.full_name(api.getChat(user_id).result, true))
	end
	return text
end

local function action(msg, blocks)
	if blocks[1] == 'voteban' then
		local hash = string.format('chat:%d:voteban', msg.chat.id)
		local status = db:hget(hash, 'status') or config.chat_settings.voteban.status
		if status == 'off' and not roles.is_admin_cached(msg) then return end

		-- choose the hero
		vardump(blocks)
		local nominated
		if msg.mentions then
			nominated = next(msg.mentions)
			if next(msg.mentions, nominated) then
				api.sendMessage(msg.chat.id, _("*Warning*: Multiple mentions still isn't supported"), true)
			end
			-- FIXME: make that the follow variable would store the user object for decrease number of API queries
			nominated = api.getChat(nominated).result
		elseif msg.reply then
			nominated = msg.reply.from
		elseif tonumber(blocks[2]) then
			local res = api.getChatMember(msg.chat.id, blocks[2])
			-- theoretically we can vote for ban of left users
			if res and res.result.status ~= 'kicked' then
				nominated = res.result.user
			else
				api.sendMessage(msg.chat.id, _("This user isn't a chat member"))
				return
			end
		elseif blocks[2] and blocks[2]:byte(1) == string.byte('@') then
			-- FIXME: double call of getChat
			local user_id = misc.resolve_user(blocks[2])
			if not user_id then
				api.sendMessage(msg.chat.id, _("I've never seen this user before.\n"
					.. "If you want to teach me who is he, forward me a message from him"))
				return
			end
			-- FIXME: avoid copypaste
			local res = api.getChatMember(msg.chat.id, user_id)
			-- theoretically we can vote for ban of left users
			if res and res.result.status ~= 'kicked' then
				nominated = res.result.user
			else
				api.sendMessage(msg.chat.id, _("This user isn't a chat member"))
				return
			end
		end

		generate_poll(msg, nominated)
	end
	if msg.cb then
		local defendant = tonumber(blocks[2])
		local text
		if blocks[1] == 'increase' then
			text = change_votes_machinery(msg.chat.id, defendant, msg.from.id, 1)
		end
		if blocks[1] == 'decrease' then
			text = change_votes_machinery(msg.chat.id, defendant, msg.from.id, -1)
		end
		if blocks[1] == 'revoke' then
			text = change_votes_machinery(msg.chat.id, defendant, msg.from.id, 0)
		end
		if blocks[1] == 'cancel' then
			local hash = string.format('chat:%d:voteban:%d', msg.chat.id, defendant)
			local initiator = tonumber(db:hget(hash, 'initiator'))
			if msg.from.id == initiator then
				defendant = api.getChat(defendant).result
				local text = _("The poll against %s was closed by initiator"):format(users.full_name(defendant))
				api.editMessageText(msg.chat.id, msg.message_id, text, nil, true)
				db:del(hash, hash .. ':supports', hash .. ':oppositionists')
			elseif roles.is_admin_cached(msg.chat.id, msg.from.id) then
				api.editMessageText(msg.chat.id, msg.message_id, _("The poll was closed by administrator"))
				db:del(hash, hash .. ':supports', hash .. ':oppositionists')
			else
				text = _("Only administrators or initiator can close the poll")
			end
		end
		if text then
			api.answerCallbackQuery(msg.cb_id, text)
		end
	end
end

return {
	action = action,
	triggers = {
		config.cmd..'(voteban) ([^%s]*) ?(.*)',
		config.cmd..'(voteban)$',

		'^###cb:voteban:(increase):(-?%d+)$',
		'^###cb:voteban:(decrease):(-?%d+)$',
		'^###cb:voteban:(revoke):(-?%d+)$',
		'^###cb:voteban:(cancel):(-?%d+)$',
	}
}
