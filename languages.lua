local langs = {} -- table with module functions

local strings = {} -- internal array with translated strings

local function eval(str)
	return load('return ' .. str)()
end

local function parse(filename)
	local state = 'ign_msgstr' -- states of finite state machine
	local msgid, msgstr
	local result = {}

	for line in io.lines(filename) do
		line = line:trim()
		local input, argument = line:match('^(%w*)%s*(".*")$')
		if line:match('^#,.*fuzzy') then
			input = 'fuzzy'
		end

		assert(state == 'msgid' or state == 'msgstr' or state == 'ign_msgid' or state == 'ign_msgstr')
		assert(input == nil or input == '' or input == 'msgid' or input == 'msgstr' or input == 'fuzzy')

		if state == 'msgid' and input == '' then
			msgid = msgid .. eval(argument)
		elseif state == 'msgid' and input == 'msgstr' then
			msgstr = eval(argument)
			state = 'msgstr'
		elseif state == 'msgstr' and input == '' then
			msgstr = msgstr .. eval(argument)
		elseif state == 'msgstr' and input == 'msgid' then
			if msgstr ~= '' then result[msgid] = msgstr end
			msgid = eval(argument)
			state = 'msgid'
		elseif state == 'msgstr' and input == 'fuzzy' then
			if msgstr ~= '' then result[msgid] = msgstr end
			state = 'ign_msgid'
		elseif state == 'ign_msgid' and input == 'msgstr' then
			state = 'ign_msgstr'
		elseif state == 'ign_msgstr' and input == 'msgid' then
			msgid = eval(argument)
			state = 'msgid'
		elseif state == 'ign_msgstr' and input == 'fuzzy' then
			state = 'ign_msgid'
		end
	end
	if state == 'msgstr' and msgstr ~= '' then
		result[msgid] = msgstr
	end

	return result
end

function langs.init(directory)
	directory = directory or "locales"

	for lang_code in pairs(config.available_languages) do
		strings[lang_code] = parse(string.format('%s/%s.po', directory, lang_code))
	end
end

function langs.translate(msgid, language)
	return strings[language][msgid] or msgid
end

_ = langs.translate

return langs
