local _, ns = ...

-- Who made this, and how to reach him.
--
-- An addon in beta on a client in beta will break in ways its author has not
-- seen, and the only way he hears about those is if saying so is easy. So the
-- name and the BattleTag are in two places: the last step of the welcome
-- wizard (Core/Install.lua), and a page in the settings that is still there
-- in three weeks when something actually goes wrong.

ns.INFO = {
  author    = "Solindius",
  battleTag = "Recounted#1297",
  client    = "World of Warcraft: Forever",
  release   = "6 November",
  beta      = true,
}

-- The addon's own words about itself. Kept here rather than spread through
-- the window and the page, so the two can never drift apart.
function ns.InfoLines()
  local info = ns.INFO
  return {
    hello = ("Hello. I'm %s, and I built this."):format(info.author),

    beta = ("ForeverUI is a beta, written for %s and for nothing else. It uses "
      .. "things only that client has, so it will not behave on retail or on "
      .. "ordinary Classic. Forever goes live on %s, and the plan is simple: "
      .. "have this steady by then."):format(info.client, info.release),

    broke = "If something breaks, I would rather hear it than not. There is no "
      .. "form and no tracker to learn -- add me and tell me what happened. "
      .. "\"The tank grid went blank when I zoned\" is a perfectly good bug "
      .. "report. What you were doing at the time is usually the whole clue.",

    tag = ("BattleTag: |cffffd100%s|r"):format(info.battleTag),

    chat = "Send a friend request if you just want to talk shop -- interfaces, "
      .. "healing, what Forever is doing to everything we thought we knew "
      .. "about addons. I am usually on.",

    thanks = "And thank you for running it this early. Everything in here got "
      .. "better because somebody said it was wrong.",
  }
end

-- Put the BattleTag where it can be copied. The chat box is the one field in
-- this game everyone already knows how to copy out of.
function ns.CopyBattleTag()
  local tag = ns.INFO.battleTag
  local box = ChatEdit_ChooseBoxForSend and ChatEdit_ChooseBoxForSend()
  if box and ChatEdit_ActivateChat then
    ChatEdit_ActivateChat(box)
    box:SetText(tag)
    box:HighlightText()
    ns.Print(("%s is in your chat box -- copy it, then press Escape."):format(tag))
    return true
  end
  ns.Print(("add me on Battle.net: |cffffd100%s|r"):format(tag))
  return false
end

---------------------------------------------------------------------------
-- The Info page
---------------------------------------------------------------------------

function ns.InfoSchema()
  local lines = ns.InfoLines()
  return {
    { type = "heading", label = "Info", subtitle = lines.hello, icon = "info" },
    { type = "note", label = lines.beta },

    { type = "heading", label = "Found a bug?", icon = "quote" },
    { type = "note", label = lines.broke },
    { type = "note", label = lines.tag },
    { type = "action", label = "Copy my BattleTag", width = 240, icon = "copy",
      desc = "Puts it in your chat box, ready to copy.",
      onClick = function() ns.CopyBattleTag() end },
    { type = "action", label = "Say hello", width = 240, icon = "social",
      desc = "Copies my BattleTag and says which key opens your friends list.",
      onClick = function()
        ns.CopyBattleTag()
        ns.Skin.OpenHint("friends")   -- never ToggleFriendsFrame from here: see OpenHint
      end },

    { type = "heading", label = "Talking shop", icon = "chat" },
    { type = "note", label = lines.chat },
    { type = "note", label = lines.thanks },

    { type = "heading", label = "This build", icon = "general" },
    { type = "note", label = ("ForeverUI %s, on %s."):format(
      ns.VERSION or "?", ns.Compat and ns.Compat.Describe and ns.Compat.Describe() or "this client") },
    { type = "action", label = "Show the welcome again", width = 240, icon = "reset",
      desc = "Opens the setup wizard. Your profile is kept.",
      onClick = function()
        if ns.ShowInstaller then ns.ShowInstaller(true) end
      end },
  }
end
