-- IKEMEN GO DOJO MODULE --------------------------------------------------
-- gametutorial.lua - the Game Tutorial's match script.
-- The `systemtutorial` main menu item points main.lua here.
-- 
-- Module developed by two4teezee
-- -------------------------------------------------------------------------
if type(tutorial) == 'table' and type(tutorial.f_gameTutorialRun) == 'function'
	and gameMode('tutorial') and tutorial.track == 'game' then
	tutorial.f_gameTutorialRun()
end
