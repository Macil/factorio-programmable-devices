function position_to_string(entity)
  local s = entity.position.x .. "," .. entity.position.y
  if entity.surface.name ~= "nauvis" then
    s = s .. "," .. entity.surface.name
  end
  return s
end

-- TODO
-- Add RCON commands for a game-backed key-value store for companion programs
-- to use.
-- Add RCON command to get signal changes from any watched combinator since
-- last command.
-- Add RCON command to subscribe to signal changes through file writes.

commands.add_command(
  "pd_get_combinator",
  "Prints the coordinates of the closest constant combinator for use with other commands",
  function(event)
    if event.player_index == nil then
      rcon.print("Error: This command is only available in-game")
      return
    end
    local player = game.players[event.player_index]
    local combinators = player.surface.find_entities_filtered{
      position = player.position,
      radius = 8,
      name = "constant-combinator"
    }
    local closest_combinator = player.surface.get_closest(player.position, combinators)
    if closest_combinator == nil then
      player.print("No constant combinator found near player")
    else
      player.print("Closest constant combinator is at " .. position_to_string(closest_combinator))
    end
  end
)

function rcon_respond(arg)
  rcon.print(game.table_to_json(arg))
end

local cmd_handlers = {
  getGameId = function(arg)
    if arg.suggestedId ~= nil then
      if string.len(arg.suggestedId) < 4 or string.len(arg.suggestedId) > 36 then
        return nil, {error = "Suggested game id must be between 4 and 36 characters"}
      end
      if global.game_id == nil then
        global.game_id = arg.suggestedId
      end
    end
    return {gameId = global.game_id}
  end,

  readCombinator = function(arg)
    local combinator = nil
    local surface = game.surfaces[arg.position.surface]
    if surface ~= nil then
      combinator = surface.find_entity("constant-combinator", arg.position)
    end
    local output = {}
    if combinator ~= nil then
      local control_behavior = combinator.get_or_create_control_behavior()
      output.combinator = {}
      if arg.fields.enabled then
        output.combinator.enabled = control_behavior.enabled
      end
      if arg.fields.parameters then
        output.combinator.parameters = {}
        for _, parameter in ipairs(control_behavior.parameters) do
          if parameter.signal.name ~= nil then
            table.insert(output.combinator.parameters, parameter)
          end
        end
      end
      if arg.fields.maxParameters then
        output.combinator.maxParameters = control_behavior.signals_count
      end
      if arg.fields.signals then
        -- TODO let user pass in a filter for the signals they want.
        -- The signals value here can be nil. Caller does need to handle this case.
        output.combinator.signals = combinator.get_merged_signals()
      end
    end
    return output
  end,

  setCombinator = function(arg)
    local combinator = nil
    local surface = game.surfaces[arg.position.surface]
    if surface ~= nil then
      combinator = surface.find_entity("constant-combinator", arg.position)
    end
    local output = {}
    if combinator ~= nil then
      local control_behavior = combinator.get_or_create_control_behavior()
      if arg.values.enabled ~= nil then
        control_behavior.enabled = arg.values.enabled
      end
      if arg.values.parameters ~= nil then
        control_behavior.parameters = arg.values.parameters
      end
      output.success = true
    else
      output.success = false
    end
    return output
  end,
}

commands.add_command(
  "pd_internal_cmd",
  "Internal Programmable Devices RCON command for the companion program",
  function(event)
    if event.player_index ~= nil then
      local player = game.players[event.player_index]
      player.print("Error: This command is only available via RCON")
      return
    end
    if event.parameter == nil then
      rcon_respond{error = "missing arg"}
      return
    end
    local arg = game.json_to_table(event.parameter)
    if arg == nil then
      rcon_respond{error = "arg is not valid JSON"}
      return
    end

    local responses = {}

    for _, cmd in ipairs(arg.cmds) do
      local handler = cmd_handlers[cmd.type]
      local output = nil
      if handler == nil then
        output = {type = "error", v = {error = "Unknown command type: " .. cmd.type}}
      else
        local result, error = handler(cmd.v)
        if error ~= nil then
          output = {type = "error", v = error}
        else
          output = {type = cmd.type, v = result}
        end
      end
      table.insert(responses, output)
    end

    rcon_respond{
      responses = responses,
      tick = game.tick,
    }
  end
)
