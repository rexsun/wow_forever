
	----------------------------------------------------------------------
	-- Leatrix Plus Mute for Forever
	----------------------------------------------------------------------

	local void, Leatrix_Plus = ...
	local L = Leatrix_Plus.L

	----------------------------------------------------------------------
	-- Mute game sounds
	----------------------------------------------------------------------

	-- Create soundtable
	local muteTable = {

		-- Quad hooved
		-- sound/character/footsteps/hoovedmedium/mon_footstep_quadraped_hooved_

		-- Bipedal hooved
		-- sound/character/footsteps/hoovedmedium/mon_footstep_bipedal_hooved_

		----------------------------------------------------------------------
		-- General
		----------------------------------------------------------------------

		-- Chimes (sound/doodad/)
		["MuteChimes"] = {
			"belltollalliance.ogg#566564",
			"belltollhorde.ogg#565853",
			"belltollnightelf.ogg#566558",
			"belltolltribal.ogg#566027",
			"kharazahnbelltoll.ogg#566254",
			"dwarfhorn.ogg#566064",
		},

		-- Fizzle (sound/spells/fizzle/)
		["MuteFizzle"] = {

			"fizzlefirea.ogg#569773",
			"FizzleFrostA.ogg#569775",
			"FizzleHolyA.ogg#569772",
			"FizzleNatureA.ogg#569774",
			"FizzleShadowA.ogg#569776",
			"sound/spells/cast/holycast.ogg#569763",

		},

		-- Interface (sound/interface/)
		["MuteInterface"] = {

			"iUiInterfaceButtonA.ogg#567481",
			"uChatScrollButton.ogg#567407",
			"uEscapeScreenClose.ogg#567464",
			"uEscapeScreenOpen.ogg#567490",

		},

		-- Login
		["MuteLogin"] = {

			-- This is handled with the PLAYER_LOGOUT event

		},

		-- Ready (ready check) (sound/interface/)
		["MuteReady"] = {

			"levelup2.ogg#567478",
		},

		-- Trains
		["MuteTrains"] = {

			--[[Dwarf]]		"sound#539802", "sound#539881",
			--[[Gnome]]		"sound#540271", "sound#540275",
			--[[Human]]		"sound#540535", "sound#540734",
			--[[Night Elf]]	"sound#540870", "sound#540947", "sound#1316209", "sound#1304872",
			--[[Orc]]		"sound#541157", "sound#541239",
			--[[Tauren]]	"sound#542818", "sound#542896",
			--[[Troll]] 	"sound#543085", "sound#543093",
			--[[Undead]]	"sound#542526", "sound#542600",
			--[[Skyborne]]	"sound#7744921", "sound#7744513",

		},

		-- Vaults
		["MuteVaults"] = {

			-- Mechanical guild vault idle sound (such as those found in Booty Bay and Winterspring)
			"sound/doodad/guildvault_goblin_01stand.ogg#566289",

		},

		----------------------------------------------------------------------
		-- Toys
		----------------------------------------------------------------------

		-- Piccolo (Piccolo of the Flaming Fire) (sound/spells/)
		["MutePiccolo"] = {
			"sound/spells/seduction_state_head.ogg#568271",
		},

		----------------------------------------------------------------------
		-- Misc
		----------------------------------------------------------------------

		-- Yawns (sound/creature/tiger/)
		["MuteYawns"] = {
			"mtigerstand2a.ogg#562388",
		},

	}

	----------------------------------------------------------------------
	-- Mute mount sounds
	----------------------------------------------------------------------

	-- Create soundtable
	local mountTable = {

		----------------------------------------------------------------------
		-- Mounts
		----------------------------------------------------------------------

		-- Airships
		["MuteAirships"] = {

			-- sound/creature/allianceairship
			"mon_alliance_airship_engine_fly_loop_01.ogg#1659528",
			"mon_alliance_airship_engine_fly_loop_02.ogg#1659529",
			"mon_alliance_airship_engine_fly_loop_03.ogg#1659530",
			"mon_alliance_airship_engine_fly_loop_04.ogg#1659504",
			"mon_alliance_airship_engine_idle_loop_01.ogg#1659505",
			"mon_alliance_airship_engine_idle_loop_02.ogg#1659506",
			"mon_alliance_airship_engine_idle_loop_03.ogg#1659507",
			"mon_alliance_airship_engine_start_01.ogg#1659508",
			"mon_alliance_airship_engine_start_02.ogg#1659509",
			"mon_alliance_airship_engine_start_03.ogg#1659510",
			"mon_alliance_airship_engine_start_04.ogg#1659511",
			"mon_alliance_airship_enginestartlong_01.ogg#1686533",
			"mon_alliance_airship_enginestartlong_02.ogg#1686534",
			"mon_alliance_airship_enginestartlong_03.ogg#1686535",
			"mon_alliance_airship_enginestartlong_04.ogg#1686536",
			"mon_alliance_airship_gear_shift_01.ogg#1659512",
			"mon_alliance_airship_gear_shift_02.ogg#1659513",
			"mon_alliance_airship_gear_shift_03.ogg#1659514",
			"mon_alliance_airship_gearshiftlong_01.ogg#1686537",
			"mon_alliance_airship_gearshiftlong_02.ogg#1686538",
			"mon_alliance_airship_gearshiftlong_03.ogg#1686539",
			"mon_alliance_airship_impact_metal_wood_01.ogg#1659515",
			"mon_alliance_airship_impact_metal_wood_02.ogg#1659516",
			"mon_alliance_airship_impact_metal_wood_03.ogg#1659517",
			"mon_alliance_airship_land_01.ogg#1659518",
			"mon_alliance_airship_land_02.ogg#1659519",
			"mon_alliance_airship_mountspecial_01.ogg#1686540",
			"mon_alliance_airship_mountspecial_02.ogg#1686541",
			"mon_alliance_airship_turn_wood_stress_01.ogg#1659520",
			"mon_alliance_airship_turn_wood_stress_02.ogg#1659521",
			"mon_alliance_airship_turn_wood_stress_03.ogg#1659522",
			"mon_alliance_airship_turn_wood_stress_04.ogg#1659523",
			"mon_alliance_airship_turn_wood_stress_05.ogg#1659524",
			"mon_alliance_airship_turn_wood_stress_06.ogg#1659525",
			"mon_alliance_airship_turn_wood_stress_07.ogg#1659526",
			"mon_alliance_airship_turn_wood_stress_08.ogg#1659527",

			-- sound/vehicles/alliancegunship
			"alliancegunship.ogg#603149",

		},

		-- Horse footsteps
		["MuteHorsesteps"] = {

			-- sound/creature/horse/mfootstepshorse
			"dirt01.ogg#552083",
			"dirt02.ogg#552081",
			"dirt03.ogg#552072",
			"dirt04.ogg#552089",
			"dirt05.ogg#552078",
			"grass01.ogg#552087",
			"grass02.ogg#552085",
			"grass03.ogg#552062",
			"grass04.ogg#552071",
			"grass05.ogg#552079",
			"snow01.ogg#552065",
			"snow02.ogg#552084",
			"snow03.ogg#552058",
			"snow04.ogg#552073",
			"snow05.ogg#552077",
			"stone01.ogg#552090",
			"stone02.ogg#552068",
			"stone03.ogg#552070",
			"stone04.ogg#552082",
			"stone05.ogg#552060",
			"wood01.ogg#552086",
			"wood02.ogg#552075",
			"wood03.ogg#552076",
			"wood04.ogg#552066",
			"wood05.ogg#552063",

			-- Water is sound/character/footsteps/watersplash/footstepsmediumwater

		},

		-- Mechsteps (Mechanical mount foosteps)
		["MuteMechSteps"] = {

			-- Mechsuits (sound/creature/goblinshredder/footstep_goblinshreddermount_general_)
			"01.ogg#893935", "02.ogg#893937", "03.ogg#893939", "04.ogg#893941", "05.ogg#893943", "06.ogg#893945", "07.ogg#893947", "08.ogg#893949",

			-- Mechanostriders (sound/creature/gnomespidertank/)
			"gnomespidertankfootstepa.ogg#550507",
			"gnomespidertankfootstepb.ogg#550514",
			"gnomespidertankfootstepc.ogg#550501",
			"gnomespidertankfootstepd.ogg#550500",
			"gnomespidertankwoundd.ogg#550511",
			"gnomespidertankwounde.ogg#550504",
			"gnomespidertankwoundf.ogg#550498",

		},

		-- Mechstriders (Striders)
		["MuteStriders"] = {

			-- sound/creature/mechastrider/
			"mechastrideraggro.ogg#555127",
			"mechastriderattacka.ogg#555125",
			"smechastriderattackb.ogg#555123",
			"mechastriderattackc.ogg#555132",
			"mechastriderloop.ogg#555124",
			"mechastriderwounda.ogg#555128",
			"mechastriderwoundb.ogg#555129",
			"mechastriderwoundc.ogg#555130",
			"mechastriderwoundcrit.ogg#555131",

		},

		-- Zeppelins
		["MuteZeppelins"] = {

			-- sound/creature/hordezeppelin
			"mon_hordezeppelin_flight.ogg#1659491",
			"mon_hordezeppelin_flight_rocketblast01.ogg#1659492",
			"mon_hordezeppelin_flight_rocketblast02.ogg#1659493",
			"mon_hordezeppelin_flight_rocketblast03.ogg#1659494",
			"mon_hordezeppelin_flight_stand01.ogg#1659495",
			"mon_hordezeppelin_idle.ogg#1659496",
			"mon_hordezeppelin_mountspecial.ogg#1685499",
			"mon_hordezeppelin_rocket01.ogg#1659497",
			"mon_hordezeppelin_rocket02.ogg#1659498",
			"mon_hordezeppelin_rocket03.ogg#1659499",
			"mon_hordezeppelin_summon01.ogg#1659500",
			"mon_hordezeppelin_summon02.ogg#1659501",
			"mon_hordezeppelin_summon03.ogg#1659502",
			"mon_hordezeppelin_walk.ogg#1659503",

			-- sound/doodad
			"doodadcompression/zeppelinengineloop.ogg#567190",
			"go_fx_zeppelin_propeller_blades_loop.ogg#652796",
			"go_vfw_zeppelinwreckpropeller_stand.ogg#604805",
			"zeppelinheliuma.ogg#566604",
			"zeppelinheliumb.ogg#565623",
			"zeppelinheliumc.ogg#566258",
			"zeppelinheliumd.ogg#567042",

			-- sound/vehicles/hordegunship
			"hordegunship.ogg#603224",

		},

	}

	-- Create soundtable for PLAYER_LOGOUT for MuteLogin (these sounds are only muted or unmuted when logging out)
	local muteLogoutTable = {

		-- Game music (sound/ui/mus_1_0_maintitle_original_0_8176610.ogg#8176610) -- Update this with new expansion launches
		"8176610",

	}

	----------------------------------------------------------------------
	-- End
	----------------------------------------------------------------------

	Leatrix_Plus["muteTable"] = muteTable
	Leatrix_Plus["muteLogoutTable"] = muteLogoutTable
	Leatrix_Plus["mountTable"] = mountTable
