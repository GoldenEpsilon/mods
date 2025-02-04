local utf8 = require("utf8")
local LINE_HEIGHT = 20
local math = require('math')

local console = {
    logger = getLogger("dev_console"),
    log_level = "INFO",
    is_open = false,
    cmd = "> ",
    max_lines = love.graphics.getHeight() / LINE_HEIGHT,
    start_line_offset = 1,
    modifiers = {
        capslock = false,
        scrolllock = false,
        numlock = false,
        shift = false,
        ctrl = false,
        alt = false,
        meta = false,
    },
    toggle = function(self)
        self.is_open = not self.is_open
        love.keyboard.setKeyRepeat(self.is_open)  -- set key repeat to true when console is open
        if self.is_open then
            self.start_line_offset = self.max_lines - 1
            local oldTextInput = love.textinput
            love.textinput = function(character)
                self.cmd = self.cmd .. character
            end
        else
            love.textinput = nil
        end
    end,
    longestCommonPrefix = function(self, strings)
        if #strings == 0 then
            return ""
        end
        local prefix = strings[1]
        for i = 2, #strings do
            local str = strings[i]
            local j = 1
            while j <= #prefix and j <= #str and prefix:sub(j, j) == str:sub(j, j) do
                j = j + 1
            end
            prefix = prefix:sub(1, j - 1)
        end
        return prefix
    end,
    tryAutocomplete = function(self)
        local command = self.cmd:sub(3) -- remove the "> " prefix
        local cmd = {}
        -- split command into parts
        for part in command:gmatch("%S+") do
            table.insert(cmd, part)
        end
        if #cmd == 0 then
            -- no command typed, do nothing (no completions possible)
            logger:trace("No command typed")
            return nil
        end
        local completions = {}
        if #cmd == 1 then
            -- only one part, try to autocomplete the command
            -- find all commands that start with the typed string, then complete the characters until the next character is not a match
            for name, _ in pairs(_REGISTERED_COMMANDS) do
                if name:find(cmd[1], 1, true) == 1 then -- name starts with cmd[1]
                    table.insert(completions, name)
                end
            end
        else
            -- more than one part, try to autocomplete the arguments
            local commandName = cmd[1]
            local command = _REGISTERED_COMMANDS[commandName]
            if command then
                completions = command.autocomplete(cmd[#cmd]) or {}
            end
        end
        logger:trace("Autocomplete matches: " .. #completions .. " " .. table.concat(completions, ", "))
        if #completions == 0 then
            -- no completions found
            return nil
        elseif #completions == 1 then
            return completions[1]
        else
            -- complete until the common prefix of all matches
            return self:longestCommonPrefix(completions)
        end
    end,
    getMessageColor = function (self, message)
        if message.level == "PRINT" then
            return 1, 1, 1
        end
        if message.level == "INFO" then
            return 0, 0.9, 1
        end
        if message.level == "WARN" then
            return 1, 0.5, 0
        end
        if message.level == "ERROR" then
            return 1, 0, 0
        end
        if message.level == "DEBUG" then
            return 0.16, 0, 1
        end
        if message.level == "TRACE" then
            return 1, 1, 1
        end
        return 1, 1, 1
    end,
    getFilteredMessages = function(self)
        local filtered = {}
        for _, message in ipairs(ALL_MESSAGES) do
            if message.level_numeric >= self.logger.log_levels[self.log_level] then
                table.insert(filtered, message)
            end
        end
        return filtered
    end,
    getMessagesToDisplay = function(self)
        local text = {}
        local i = 1
        local textLength = 0
        local all_messages = self:getFilteredMessages()
        while textLength < self.max_lines do
            local index = #all_messages - i + self.start_line_offset
            if index < 1 then
                break
            end
            local message = all_messages[index]
            if message then
                table.insert(text, message)
                textLength = textLength + 1
            end
            i = i + 1
        end
        -- define locally to not pollute the global namespace scope
        local function reverse(tab)
            for i = 1, math.floor(#tab/2), 1 do
                tab[i], tab[#tab-i+1] = tab[#tab-i+1], tab[i]
            end
            return tab
        end
        text = reverse(text)
        -- pad text table so that we always have max_lines lines in there
        local nLinesToPad = #text - self.max_lines
        for i=1,nLinesToPad do
            table.insert(text, {text = "", level = "PRINT", name = "", time = 0, level_numeric = 1000, formatted = function() return "" end})
        end
        return text
    end,
    modifiersListener = function(self)
        -- disable text input if ctrl or cmd is pressed
        -- this is to fallback to love.keypressed when a modifier is pressed that can
        -- link to a command (like ctrl+c, ctrl+v, etc)
        self.logger:trace("modifiers", self.modifiers)
        if self.modifiers.ctrl or self.modifiers.meta then
            love.textinput = nil
        else
            love.textinput = function(character)
                self.cmd = self.cmd .. character
            end
        end
    end,
    typeKey = function (self, key_name)
        if key_name == "d" and self.modifiers.meta then
            self.logger:trace("offset= ", self.start_line_offset, "max= ", self.max_lines)
            return
        end
        if key_name == "a" and self.modifiers.meta then
            for i=1,100 do
                self.logger:trace("line ", i)
            end
            return
        end
        -- cmd+shift+C on mac, ctrl+shift+C on windows/linux
        if key_name == "c" and ((platform.is_mac and self.modifiers.meta and self.modifiers.shift) or (not platform.is_mac and self.modifiers.ctrl and self.modifiers.shift)) then
            local messages = self:getFilteredMessages()
            local text = ""
            for _, message in ipairs(messages) do
                text = text .. message:formatted() .. "\n"
            end
            love.system.setClipboardText(text)
            return
        end
        -- cmd+C on mac, ctrl+C on windows/linux
        if key_name == "c" and ((platform.is_mac and self.modifiers.meta) or (not platform.is_mac and self.modifiers.ctrl)) then
            if self.cmd:sub(3) == "" then
                -- do nothing if the buffer is empty
                return
            end
            love.system.setClipboardText(self.cmd:sub(3))
            return
        end
        -- cmd+V on mac, ctrl+V on windows/linux
        if key_name == "v" and ((platform.is_mac and self.modifiers.meta) or (not platform.is_mac and self.modifiers.ctrl)) then
            self.cmd = self.cmd .. love.system.getClipboardText()
            return
        end
        if key_name == "escape" then
            self:toggle()
            return
        end
        -- Delete the current command, on mac it's cmd+backspace
        if key_name == "delete" or (platform.is_mac and self.modifiers.meta and key_name == "backspace") then
            self.cmd = "> "
            return
        end
        if key_name == "end" or (platform.is_mac and key_name == "right" and self.modifiers.meta) then
            -- move text to the most recent (bottom)
            self.start_line_offset = self.max_lines
            return
        end
        if key_name == "home" or (platform.is_mac and key_name == "left" and self.modifiers.meta) then
            -- move text to the oldest (top)
            local messages = self:getFilteredMessages()
            self.start_line_offset = self.max_lines - #messages
            return
        end
        if key_name == "pagedown" or (platform.is_mac and key_name == "down" and self.modifiers.meta) then
            -- move text down by max_lines
            self.start_line_offset = math.min(self.start_line_offset + self.max_lines, self.max_lines)
            return
        end
        if key_name == "pageup"  or (platform.is_mac and key_name == "up" and self.modifiers.meta) then
            -- move text up by max_lines
            local messages = self:getFilteredMessages()
            self.start_line_offset = math.max(self.start_line_offset - self.max_lines, self.max_lines - #messages)
            return
        end
        if key_name == "up" then
            -- move up one line, but cap it at max_lines - number of messages + 1 (cause lua indices start at 1 urgh)
            local messages = self:getFilteredMessages()
            self.start_line_offset = math.max(self.start_line_offset - 1, self.max_lines - #messages + 1)
            return
        end
        if key_name == "down" then
            self.start_line_offset = math.min(self.start_line_offset + 1, self.max_lines)
            return
        end
        if key_name == "tab" then
            local completion = self:tryAutocomplete()
            if completion then
                -- get the last part of the console command
                local lastPart = self.cmd:match("%S+$")
                if lastPart == nil then -- cmd ends with a space, so we stop the completion
                    return
                end
                -- then replace the whole last part with the autocompleted command
                self.cmd = self.cmd:sub(1, #self.cmd - #lastPart) .. completion
            end
            return
        end
        if key_name == "lalt" or key_name == "ralt" then
            self.modifiers.alt = true
            self:modifiersListener()
            return
        end
        if key_name == "lctrl" or key_name == "rctrl" then
            self.modifiers.ctrl = true
            self:modifiersListener()
            return
        end
        if key_name == "lshift" or key_name == "rshift" then
            self.modifiers.shift = true
            self:modifiersListener()
            return
        end
        if key_name == "lgui" or key_name == "rgui" then
            -- windows key / meta / cmd key (on macos)
            self.modifiers.meta = true
            self:modifiersListener()
            return
        end
        if key_name == "backspace" then
            if #self.cmd > 2 then
                local byteoffset = utf8.offset(self.cmd, -1)
                if byteoffset then
                    -- remove the last UTF-8 character.
                    -- string.sub operates on bytes rather than UTF-8 characters, so we couldn't do string.sub(text, 1, -2).
                    self.cmd = string.sub(self.cmd, 1, byteoffset - 1)
                end
            end
            return
        end
        if key_name == "return" or key_name == "kpenter" then
            self.logger:print(self.cmd)
            local cmdName = self.cmd:sub(3)
            cmdName = cmdName:match("%S+")
            local args = {}
            local argString = self.cmd:sub(3 + #cmdName + 1)
            if argString then
                for arg in argString:gmatch("%S+") do
                    table.insert(args, arg)
                end
            end

            for _, mod in ipairs(mods) do
                if mod.on_command_sent then
                    mod.on_command_sent(cmdName, args)
                end
            end
            self.cmd = "> "
            return
        end
    end,
}

table.insert(mods,
    {
        mod_id = "dev_console",
        name = "Dev Console",
        version = "0.4.0",
        author = "sbordeyne & UwUDev",
        description = {
            "Press F2 to open/close the console",
            "Use command `help` for a list of ",
            "available commands and shortcuts",
        },
        enabled = true,
        on_enable = function()
            console.logger:debug("Dev Console enabled")

            registerCommand(
                "help",
                function()
                    console.logger:print("Available commands:")
                    for name, cmd in pairs(_REGISTERED_COMMANDS) do
                        if cmd.desc then
                            console.logger:print(name .. ": " .. cmd.desc)
                        end
                    end
                end,
                "Prints a list of available commands",
                function(current_arg)
                    local completions = {}
                    for name, _ in pairs(_REGISTERED_COMMANDS) do
                        if name:find(current_arg, 1, true) == 1 then
                            table.insert(completions, name)
                        end
                    end
                    return completions
                end,
                "Usage: help <command>"
            )

            registerCommand(
                "shortcuts",
                function()
                    console.logger:print("Available shortcuts:")
                    console.logger:print("F2: Open/Close the console")
                    console.logger:print("F4: Toggle debug mode")
                    if platform.is_mac then
                        console.logger:print("Cmd+C: Copy the current command to the clipboard.")
                        console.logger:print("Cmd+Shift+C: Copies all messages to the clipboard")
                        console.logger:print("Cmd+V: Paste the clipboard into the current command")
                    else
                        console.logger:print("Ctrl+C: Copy the current command to the clipboard.")
                        console.logger:print("Ctrl+Shift+C: Copies all messages to the clipboard")
                        console.logger:print("Ctrl+V: Paste the clipboard into the current command")
                    end
                end,
                "Prints a list of available shortcuts",
                function(current_arg)
                    return nil
                end,
                "Usage: shortcuts"
            )

            registerCommand(
                "clear",
                function()
                    ALL_MESSAGES = {}
                end,
                "Clear the console"
            )

            registerCommand(
                "exit",
                function()
                    console:toggle()
                end,
                "Close the console"
            )

            registerCommand(
                "give",
                function()
                    console.logger:error("Give command not implemented yet")
                end,
                "Give an item to the player"
            )

            registerCommand(
                "money",
                function(args)
                    if args[1] and args[2] then
                        local amount = tonumber(args[2])
                        if amount then
                            if args[1] == "add" then
                                ease_dollars(amount, true)
                                console.logger:info("Added " .. amount .. " money to the player")
                            elseif args[1] == "remove" then
                                ease_dollars(-amount, true)
                                console.logger:info("Removed " .. amount .. " money from the player")
                            elseif args[1] == "set" then
                                local currentMoney = G.GAME.dollars
                                local diff = amount - currentMoney
                                ease_dollars(diff, true)
                                console.logger:info("Set player money to " .. amount)
                            else
                                console.logger:error("Invalid operation, use add, remove or set")
                            end
                        else
                            console.logger:error("Invalid amount")
                        end
                    else
                        console.logger:warn("Usage: money <add/remove/set> <amount>")
                    end
                end,
                "Change the player's money"
            )

            registerCommand(
                "discards",
                function(args)
                    if args[1] and args[2] then
                        local amount = tonumber(args[2])
                        if amount then
                            if args[1] == "add" then
                                ease_discard(amount, true)
                                console.logger:info("Added " .. amount .. " discards to the player")
                            elseif args[1] == "remove" then
                                ease_discard(-amount, true)
                                console.logger:info("Removed " .. amount .. " discards from the player")
                            elseif args[1] == "set" then
                                local currentDiscards = G.GAME.current_round.discards_left
                                local diff = amount - currentDiscards
                                ease_discard(diff, true)
                                console.logger:info("Set player discards to " .. amount)
                            else
                                console.logger:error("Invalid operation, use add, remove or set")
                            end
                        else
                            console.logger:error("Invalid amount")
                        end
                    else
                        console.logger:warn("Usage: discards <add/remove/set> <amount>")
                    end
                end,
                "Change the player's discards"
            )

            registerCommand(
                "hands",
                function(args)
                    if args[1] and args[2] then
                        local amount = tonumber(args[2])
                        if amount then
                            if args[1] == "add" then
                                ease_hands_played(amount, true)
                                console.logger:info("Added " .. amount .. " hands to the player")
                            elseif args[1] == "remove" then
                                ease_hands_played(-amount, true)
                                console.logger:info("Removed " .. amount .. " hands from the player")
                            elseif args[1] == "set" then
                                local currentHands = G.GAME.current_round.hands_left
                                local diff = amount - currentHands
                                ease_hands_played(diff, true)
                                console.logger:info("Set player hands to " .. amount)
                            else
                                console.logger:error("Invalid operation, use add, remove or set")
                            end
                        else
                            console.logger:error("Invalid amount")
                        end
                    else
                        console.logger:warn("Usage: hands <add/remove/set> <amount>")
                    end
                end,
                "Change the player's remaining hands"
            )

        end,
        on_disable = function()
        end,
        on_key_pressed = function (key_name)
            if key_name == "f2" then
                console:toggle()
                return true
            end
            if console.is_open then
                console:typeKey(key_name)
                return true
            end

            if key_name == "f4" then
                G.DEBUG = not G.DEBUG
                if G.DEBUG then
                    console.logger:info("Debug mode enabled")
                else
                    console.logger:info("Debug mode disabled")
                end
            end
            return false
        end,
        on_post_render = function ()
            console.max_lines = math.floor(love.graphics.getHeight() / LINE_HEIGHT) - 5  -- 5 lines of bottom padding
            if console.is_open then
                love.graphics.setColor(0, 0, 0, 0.3)
                love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
                for i, message in ipairs(console:getMessagesToDisplay()) do
                    r, g, b = console:getMessageColor(message)
                    love.graphics.setColor(r, g, b, 1)
                    love.graphics.print(message:formatted(), 10, 10 + i * 20)
                end
                love.graphics.setColor(1, 1, 1, 1) -- white
                love.graphics.print(console.cmd, 10, love.graphics.getHeight() - 30)
            end
        end,
        on_key_released = function (key_name)
            if key_name == "capslock" then
                console.modifiers.capslock = not console.modifiers.capslock
                console:modifiersListener()
                return
            end
            if key_name == "scrolllock" then
                console.modifiers.scrolllock = not console.modifiers.scrolllock
                console:modifiersListener()
                return
            end
            if key_name == "numlock" then
                console.modifiers.numlock = not console.modifiers.numlock
                console:modifiersListener()
                return
            end
            if key_name == "lalt" or key_name == "ralt" then
                console.modifiers.alt = false
                console:modifiersListener()
                return false
            end
            if key_name == "lctrl" or key_name == "rctrl" then
                console.modifiers.ctrl = false
                console:modifiersListener()
                return false
            end
            if key_name == "lshift" or key_name == "rshift" then
                console.modifiers.shift = false
                console:modifiersListener()
                return false
            end
            if key_name == "lgui" or key_name == "rgui" then
                console.modifiers.meta = false
                console:modifiersListener()
                return false
            end
            return false
        end,
        on_mouse_pressed = function(x, y, button, touches)
            if console.is_open then
                return true  -- Do not press buttons through the console, this cancels the event
            end
        end,
        on_mouse_released = function(x, y, button)
            if console.is_open then
                return true -- Do not release buttons through the console, this cancels the event
            end
        end,
        on_command_sent = function(command, args)
            if _REGISTERED_COMMANDS[command] then
                _REGISTERED_COMMANDS[command].call(args)
            else
                console.logger:error("Command not found: " .. command)
            end
        end,
    }
)
