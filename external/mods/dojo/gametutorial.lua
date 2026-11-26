-- IKEMEN GO DOJO MODULE --------------------------------------------------
-- gametutorial.lua - the Game Tutorial's match script.
-- The `systemtutorial` main menu item points main.lua here.
-- 
-- Module developed by two4teezee
-- -------------------------------------------------------------------------
if type(dojo) == 'table' and type(dojo.f_gameTutorialRun) == 'function'
	and gameMode('tutorial') and dojo.track == 'game' then
	dojo.f_gameTutorialRun()
end
