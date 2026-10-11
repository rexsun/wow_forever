local YUI=_G.YUI
if not YUI or not YUI.YBar or not (YUI.IsForever or YUI.IsRetail) then return end
local YBar=YUI.YBar
local libraries=YBar.LayoutLibraries
if not libraries then return end
libraries.Migration=libraries.MigrationFactory(libraries.Model)
local bridge=libraries.Bridge.New(YUI,libraries)
bridge:Install()
