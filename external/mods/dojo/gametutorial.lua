-- IKEMEN GO DOJO MODULE --------------------------------------------------
-- ---- gametutorial.lua - the Game Tutorial's match script.
-- ---- The `tutorialgame` main menu item points main.luaPath here, the way story mode points it at an
-- ---- arc's script: the engine runs this file in place of external/script/default.lua, and the
-- ---- lesson list and matches are run from dojo.lua.
-- ---- Every .lua file under external/mods is also loaded once at startup as a module, so the call is
-- ---- guarded: it only does anything while the Game Tutorial is the mode being played.
-- --
-- -- Module developed by two4teezee
-- -------------------------------------------------------------------------
if type(tutorial) == 'table' and type(tutorial.f_gameTutorialRun) == 'function'
	and gameMode('tutorial') and tutorial.track == 'game' then
	tutorial.f_gameTutorialRun()
end
