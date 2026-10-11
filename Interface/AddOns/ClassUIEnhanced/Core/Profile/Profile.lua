
local _
---@type string, private
local addonName, private = ...
---@type public
local public = private.public

---@class castbar_colors_profile : table
---@field use_class_color boolean  when true, overrides player cast bar casting/channeling fill with RAID_CLASS_COLORS entry
---@field casting number[]  {r, g, b, a} color for regular casts
---@field channeling number[]  {r, g, b, a} color for channeled casts
---@field finished number[]  {r, g, b, a} color when cast finishes
---@field non_interruptible number[]  {r, g, b, a} color for non-interruptible casts
---@field interrupted number[]  {r, g, b, a} color when cast is interrupted
---@field important number[]  {r, g, b, a} color for important casts
---@field empowered number[]  {r, g, b, a} color for empowered casts
---@field instant_cast number[]  {r, g, b, a} color for the GCD bar shown after instant casts
---@field background number[]  {r, g, b, a} color for cast bar background
---@field background_texture string  LibSharedMedia statusbar key for background texture ("" = solid color)

---@class health_gradient_colors_profile : table
---@field low number[]  {r, g, b, a} color at 0% health (critical)
---@field mid number[]  {r, g, b, a} color at 50% health (half)
---@field full number[]  {r, g, b, a} color at 100% health (full)

---@class resource_colors_profile : table
---@field use_class_color boolean  when true, resources use RAID_CLASS_COLORS; when false, use class_colors table
---@field class_colors table<string, number[]>  per-class {r, g, b, a} color overrides keyed by class filename

---@class primary_resource_colors_profile : table
---@field override_colors boolean  when true, uses custom power_colors; when false, uses default PowerBarColor
---@field power_colors table<string, number[]>  per-power-type {r, g, b, a} color overrides keyed by power token (e.g. "MANA", "RAGE")

---@class bar_border_profile : table
---@field enabled boolean  show a thin border around health, resource, and cast bars
---@field color number[]  {r, g, b, a} border color
---@field inside boolean  draw the border inside the frame bounds instead of outside
---@field size number  border thickness in pixels (1–5)

---@class icon_border_profile : table
---@field enabled boolean  show a thin border around tracker icons
---@field color number[]  {r, g, b, a} border color
---@field inside boolean  draw the border inside the icon bounds instead of outside
---@field size number  border thickness in pixels (1–5)

---@class component_background_profile : table
---@field enabled boolean  show a colored background behind all component container frames
---@field color number[]  {r, g, b, a} background fill color
---@field padding number  (legacy) pixels the background extends beyond the container on each side
---@field padding_h number  horizontal padding: pixels the background extends left and right (0–25)
---@field padding_v number  vertical padding: pixels the background extends top and bottom (0–25)
---@field rounded boolean  use rounded corners instead of sharp edges
---@field roundness number  corner roundness amount (1–16, only when rounded is true)
---@field border_style string  border style: "none", "plain", "slider", "tooltip", "dialog", "dialog_gold", "achievement_wood", "chat_bubble", "toast", or "party"
---@field border_color number[]  {r, g, b, a} border color (when border_style ~= "none")
---@field party_corners string  which corners are rounded for party border: "left", "right", "top", "bottom", "all", "tl", "tr", "bl", or "br"

---@class sharing_metadata : table
---@field semver string|nil  addon version the profile was created with (e.g. "1.0.11"); from sharing site
---@field url string|nil  sharing site URL (e.g. "https://wago.io/0x9uZS3OS/12"); from sharing site
---@field version number|nil  revision number on the sharing site

---@class additional_frame_profile : table
---@field id string  unique identifier ("af_1", "af_2", ...)
---@field name string  user-facing label for this frame
---@field frame_type string  "spells" (cooldown grid) or "buffs" (buff grid) or "bar" (vertical stack)
---@field enabled boolean
---@field visibility visibility_mode|nil  visibility override; nil = "inherit"
---@field visibility_rules visibility_rules_profile|nil  additive visibility rules; nil = no rules active
---@field alpha number  frame opacity 0.1–1.0; multiplied with inherited parent alpha via anchor chain; default 1.0
---@field frame_strata string|nil  WoW frame strata override ("BACKGROUND"..."TOOLTIP"); nil = "inherit" (walks anchor chain, root fallback "MEDIUM")
---@field assigned_spells (number|table)[]  ordered entries; array position = sort priority. An entry is a bare spellID (legacy) OR a {spellID, source} pair whose source is one of "Trinket"|"Consumable"|"Racial" (AdditionalFrameManager's ADDON_ICON_SOURCES), where the id is an equip slot / consumable category / racial spell owned by another component. Always read through AdditionalFrameManager.normalizeEntry, never by indexing.
---@field custom_spells? custom_spell_entry[]  user-managed spell entries folded into this frame's spell map and drawn by its own tracker
---@field aura_unit? table<number, string>  aura frames only; per-assigned-spell unit scope "player"|"target"; absent = "both"
---@field always_show_tracked? boolean  aura frames only; the always-show (slots) engine instead of the compacting groups one. Seeded once from Blizzard's "hide when inactive" by pm.MigrateHideWhenInactive (default false)
---@field desaturate_inactive? boolean  aura frames only, slots engine only; grey out a tracked icon while its aura is not up (or there is no target to hold it) (default false)
---@field missing_glow? table<number, number[]>  `buffs` frames only, slots engine only; per-spell {r, g, b, a} glow drawn while the aura is not up, keyed by spellID; an entry turns it on; written by the Tracking tab (no default table)
---@field background component_background_profile  optional background panel behind the component frame
---@field anchor_profile anchor_profile
---Icon-type fields: width, frame_size_mode, max_icons_per_row, icon_size, overflow_icon_size, overflow_direction, icon_offset, hide_cd_swipe, hide_active_swipe, active_swipe_excludes, spell_borders, hide_gcd_swipe, gcd_edge_charges, reverse_swipe, no_cd_overlay, no_cd_overlay_edge_only, no_desaturation, force_desaturation, no_range_tint, timer_font, stacks_font, keybind_font, icon_visibility_mode, hide_ready_blink, active_glow, pandemic_glow, proc_glow_style, cdm_glow_color
---Bar-type fields: bar_width, bar_height, bar_spacing, icon_size, icon_offset, icon_offset_x, icon_offset_y, growth_direction, bar_content, collapse, show_timer, bar_fill_color, spell_colors, name_font, duration_font, stacks_font
---@field tooltip_mode "always"|"out_of_combat"|"off"  per-AF tooltip visibility mode (default "off"); not inherited from source component
---@field tooltip_anchor "DEFAULT"|"CURSOR"|"RIGHT"|"TOP"  per-AF tooltip anchor relative to the icon (default "RIGHT")

---@class cdm_category_overrides : table
---@field cooldown table<number, number>  tracker key → 0 (Essential) | 1 (Utility) | -1 (hidden); applies only to entries whose DB2 default is Essential/Utility/HiddenActive
---@field aura table<number, number>      tracker key → 2 (TrackedBuff) | 3 (TrackedBar) | -2 (hidden); applies only to entries whose DB2 default is TrackedBuff/TrackedBar/HiddenPassive
---@field spec table<string, {cooldown: table<number, number>?, aura: table<number, number>?}>|nil  per-spec layer, keyed "CLASS-N"; wins over the two maps above (the all-specs layer) on that spec. Absent until the first spec-scoped move
---@field active {cooldown: table<number, true>?, aura: table<number, true>?}|nil  "Force active": tracker key → true, drawn although Blizzard's CDM counts the entry inactive; every spec. Absent until the first flag (TrackingModel.SetForceActive)

---@class profile : table
---@field auto_hide boolean  when true, PrimaryResources auto-hides for mana specs that do not benefit from a primary resource bar
---@field consumable_auto_hide boolean  when true, ConsumableTracker auto-hides mana potions for non-healer specs
---@field arcane_mana_bar boolean  when true, show the primary resource (mana) bar for Arcane mages even when auto_hide is enabled
---@field augmentation_ebon_might boolean  when true, show Ebon Might duration on the primary resource bar for Augmentation Evokers
---@field augmentation_ebon_might_show_stat boolean  when true, append the granted main-stat value to the Ebon Might bar text
---@field augmentation_ebon_might_crit_color_value number[]  RGBA color used for the crit-roll Ebon Might border glow
---@field augmentation_ebon_might_crit_glow boolean  when true, attach a pulsing border glow around the Ebon Might bar while a crit-roll Ebon Might is active
---@field augmentation_ebon_might_double_time_text boolean  when true, show the remaining Double Time duration next to the Ebon Might bar via the engine-bound aura tap
---@field augmentation_ebon_might_live_update boolean  when true, poll an ally's Ebon Might aura every 1s so the displayed stat value stays in sync with mid-buff intellect changes (trinket procs, gear swaps)
---@field augmentation_ebon_might_show_duplicates boolean  when true, show the remaining Duplicate duration on the Ebon Might bar as the engine-bound aura tap readout centered on the bar (hidden when no Duplicate is active)
---@field paladin_mana_bar boolean  when true, show the mana bar for Protection and Retribution Paladins even when auto_hide is enabled
---@field evoker_mana_bar boolean  when true, show the mana bar for Devastation Evokers even when auto_hide is enabled
---@field druid_mana_bar boolean  when true, show the mana bar for Guardian Druids even when auto_hide is enabled
---@field shaman_mana_bar boolean  when true, show the mana bar for Elemental and Enhancement Shamans (Elemental's Maelstrom now lives in the secondary bar) even when auto_hide is enabled
---@field balance_mana_bar boolean  when true, show the mana bar for Balance Druids (Astral Power now lives in the secondary bar) even when auto_hide is enabled
---@field priest_mana_bar boolean  when true, show the mana bar for Shadow Priests (Insanity now lives in the secondary bar) even when auto_hide is enabled
---@field cooldown_layout_sync boolean  when true, CooldownLayoutSync stores and restores CooldownViewer layouts per class
---@field cooldown_layouts table<string, string>  per-class CooldownViewer layout data keyed by class filename (e.g. "WARRIOR")
---@field cdm_auto_fetch boolean  when true (default), tracker spell maps auto-populate from the CDM configuration (resolved category sets); when false, only manually tracked spells (CustomSpells) apply — the manual list is always merged either way
---@field cdm_alerts boolean  when true (default), CUE re-implements a tracked key's Blizzard CDM alerts: visuals always, sounds only for a category whose Blizzard viewer is not currently shown — a no-op unless the user configured alerts in Blizzard's CDM settings
---@field cdm_target_sounds boolean  when true, keeps Blizzard's Cooldown Manager on and hidden (CDMDataSource.needsViewerChildren) so it plays its own alerts — the only source of an alert on the player's debuff on the target, since AddAuraSound fires for every source. Default false.
---@field _cooldown_layout_char table<string, string>  per-class tracking of which character last applied the layout (not exported)
---@field _sharing sharing_metadata|nil  optional metadata from sharing sites (wago.io, etc.); roundtripped on import/export, never created with defaults
---@field additional_frames table<string, additional_frame_profile>  user-created additional frames keyed by frame id
---@field icon_overrides table<number, number|string>  spellID → override texture (fileID or texture path); applied across all trackers
---@field spell_alerts table<number, table[]>  tracker key (spellID) → CUE's own alert list, Blizzard's `{ type, event, payload }` records (CooldownViewerAlert_Create); written by the Tracking tab's Alerts menu. An entry replaces the Cooldown Manager's alerts for that spell in CDMAlerts' replay, an empty list silences it, no entry follows the Cooldown Manager
---@field cdm_category_overrides cdm_category_overrides  CUE-side re-categorisation of CDM entries for CUE's four trackers only; Blizzard's own viewers/layout are untouched
---@field aura_name_cache table<string, table<number, true>>  spell name (client locale, exact) → every spell id carrying it; the one cache behind `by_name` custom auras, filled by SpellNameScan and pruned by CustomSpells to the names some entry still uses
---@field client_scope? string  the game client (ClientScope.CLIENT) whose aura_name_cache, components' custom_spells/tracked_spells and Additional Frames' assigned_spells/custom_spells sit at the ordinary keys (the frames themselves are shared); nil = not claimed yet. Not a default, not exported
---@field by_client? table<string, table>  the other clients' copies of those collections, parked by ClientScope.Swap; not a default, not exported
---@field components components_profile
---@field castbar_colors castbar_colors_profile
---@field resource_colors resource_colors_profile
---@field primary_resource_colors primary_resource_colors_profile
---@field health_gradient_colors health_gradient_colors_profile
---@field icon_zoom boolean  when true, zoom spell/item icons slightly to crop the default border edge
---@field icon_aspect_ratio boolean  when true, adjust texcoords on stretched icons to preserve the square aspect ratio
---@field button_press button_press_profile  show pressed overlay on tracker icons when keybinds are pressed
---@field bar_border bar_border_profile  optional thin border around health, resource, and cast bars
---@field icon_border icon_border_profile  optional thin border around tracker icons
---@field breakpoint_pips breakpoint_pips_profile  per-spec breakpoint pip markers on the primary resource bar and the continuous secondary bar
---@field debug_mode boolean  when true, private.printdebug() writes diagnostic messages to chat
---@field debug_log_size integer  ring buffer size for printdebug capture

---@class breakpoint_pip : table
---@field pct number  percentage value 0-100
---@field color number[]  {r, g, b, a}
---@field zone_enabled boolean|nil  whether this pip colors a background zone
---@field zone_color number[]|nil  {r, g, b, a} for the zone
---@field zone_direction string|nil  "previous" or "next"
---@field bar_color_enabled boolean|nil  whether this pip recolors the bar fill
---@field bar_color number[]|nil  {r, g, b, a} fill color at this threshold

---@class breakpoint_pips_profile : table
---@field enabled boolean  master toggle for breakpoint pips
---@field pip_width number  width of each pip line in pixels
---@field show_pip_line boolean  show overlay pip line (false = background strip only)
---@field zone_auto_hide boolean  hide zone when power reaches its threshold
---@field pip_mode string  "percent" or "absolute" (absolute uses raw power values instead of percentages)
---@field fill_interpolation string  "step" or "linear" (Enum.LuaCurveType)
---@field pips table<string, breakpoint_pip[]>  per-spec/bar pip lists keyed by "CLASSFILENAME-specIndex" (e.g. "WARRIOR-1"); the moved specs (Elemental/Balance/Shadow) key per bar instead: "-MANA" suffix for the primary bar, power-token suffix for the continuous secondary bar (e.g. "SHAMAN-1-MAELSTROM"). Plain keys for moved specs are legacy and re-keyed by ProfileManager.MigrateBreakpointPipKeys.
---@field per_spec_enabled table<string, boolean>  per-spec/bar override, same keying as pips; missing key = enabled

---@class resource_threshold : table
---@field value integer  segment index (1-based) that triggers the color
---@field color number[]  {r, g, b, a}
---@field mode string  "single" | "all_previous" | "all"
---@field resource string?  nil = the spec's primary resource (row 1); otherwise the
---  STACK_STRIPS `base` id of the extra row it scopes to ("shatter", "arcanesalvo", ...).
---  nil is also the legacy meaning, so profiles saved before this field need no migration.
---  Stack strips ignore `mode` — their count is secret, so the only implementable
---  semantic is "color pip i when i >= value". See Components/SecondaryResources.md.

---@class components_profile : table
---@field BuffTracker viewer_tracker_profile_main
---@field CooldownTracker viewer_tracker_profile_main
---@field TrinketTracker trinket_tracker_profile_main
---@field ConsumableTracker consumable_tracker_profile_main
---@field ConsumableBuffTracker consumable_buff_tracker_profile_main
---@field OutboundBuffTracker outbound_buff_tracker_profile_main
---@field RacialTracker racial_tracker_profile_main
---@field UtilitiesTracker viewer_tracker_profile_main
---@field PlayerCastBar castbar_component_profile_main
---@field TargetCastBar castbar_component_profile_main
---@field FocusCastBar castbar_component_profile_main
---@field GlobalCooldown globalcooldown_profile_main
---@field PrimaryResources primaryresources_profile_main
---@field PlayerHealthBar healthbar_profile_main
---@field SecondaryResources secondaryresources_profile_main

---@class anchor_profile : table
---@field frame_point string  raw SetPoint framePoint — used when anchor_parent = "none"
---@field frame_point_manual boolean?  true once the user picks Frame Point by hand: Trinket/Consumable Tracker's alignment sync then leaves frame_point alone. An Edit Mode drag clears it
---@field parent_point string  raw SetPoint relativePoint — used when anchor_parent = "none"
---@field relative_frame string  raw SetPoint frame name — used when anchor_parent = "none"
---@field xoff number  raw x offset — used when anchor_parent = "none"
---@field yoff number  raw y offset — used when anchor_parent = "none"
---@field anchor_parent string  component name or "none" for free-moving (falls back to raw SetPoint fields)
---@field anchor_side string  "top"|"bottom"|"left"|"right"|"topleft"|"topright"|"bottomleft"|"bottomright" — which side/corner of the parent to attach to
---@field anchor_offset_x number  horizontal pixel offset from anchor point (positive = right); raw WoW coordinate
---@field anchor_offset_y number  vertical pixel offset from anchor point (positive = up); raw WoW coordinate
---@field anchor_width_pct number  width as percentage of parent width; 100 = inherit full parent width
---@field anchor_width_mode string  "percent"|"absolute" — when "percent", use anchor_width_pct; when "absolute", use the component's width setting
---@field position_reference string?  component name to follow via screen position (no anchor chain); requires anchor_parent = "none"
---@field position_side string?  "top"|"bottom"|"left"|"right" — which side of the reference to position on
---@field position_offset number?  pixel gap from the reference frame edge

---@alias visibility_mode
---| "inherit"  # Follow anchor parent chain visibility (default)
---| "always"  # Always visible regardless of parent
---| "auto"  # Follow Blizzard's cooldown viewer availability (hidden in vehicles, pet battles, etc.)
---| "hide_when_mounted"  # Hidden while mounted, in vehicles, pet battles, and when cooldown viewer unavailable (legacy — migrated to rules)
---| "only_in_combat"  # Visible only during combat (legacy — migrated to rules)

---@alias visibility_rule_action false | "hide" | "fade"

---@class visibility_rules_profile : table
---@field fade_alpha number  percentage 10–90; opacity level when a fade rule is active (e.g. 30 = 30% opacity)
---@field mounted visibility_rule_action  action when mounted/vehicle/pet battle/taxi/client scene
---@field out_of_combat visibility_rule_action  action when not in combat
---@field no_target visibility_rule_action  action when no target selected

---@class component_profile_main : table
---@field enabled boolean
---@field visibility visibility_mode|nil  visibility override; nil = "inherit"
---@field visibility_rules visibility_rules_profile|nil  additive visibility rules; nil = no rules active
---@field alpha number  frame opacity 0.1–1.0; multiplied with inherited parent alpha via anchor chain; default 1.0
---@field frame_strata string|nil  WoW frame strata override ("BACKGROUND"..."TOOLTIP"); nil = "inherit" (walks anchor chain, root fallback "MEDIUM")
---@field width number
---@field height number
---@field background component_background_profile  optional background panel behind the component frame
---@field anchor_profile anchor_profile

---@class primaryresources_profile_main : component_profile_main
---@field texture string  LibSharedMedia "statusbar" key; empty string = default solid fill
---@field orientation string  "horizontal"|"vertical" — bar fill direction; vertical fills bottom→top
---@field value_font castbar_font_profile  font settings for the power value text (centered)
---@field text_format_mana string  "percent"|"current"|"both" — text format when the resource is mana
---@field text_format_other string  "percent"|"current"|"both" — text format for energy, rage, etc.
---@field bar_smoothing boolean  whether to smoothly animate power bar value changes instead of snapping instantly
---@field background_color number[]  {r, g, b, a} background color behind the power bar
---@field spend_prediction boolean  whether to show a spend prediction overlay on the mana bar during casts
---@field spend_prediction_color number[]  {r, g, b, a} color for the spend prediction overlay
---@field five_second_rule boolean  WoW Forever: a spark crosses the mana bar during the 5 s after mana is spent
---@field five_second_rule_size "full"|"top"|"bottom"  band of the bar the five-second-rule spark covers

---@class secondaryresources_profile_main : component_profile_main
---@field extra_row_height number  cross-axis size of each extra resource row; defaults to a third of `height`, which stays the primary row's, and the component grows by this per extra
---@field texture string  LibSharedMedia "statusbar" key; empty string = default solid fill
---@field orientation string  "horizontal"|"vertical" — bar fill direction per segment; vertical fills bottom→top
---@field background_color number[]  {r, g, b, a} background color for inactive resource bar segments
---@field use_static_background boolean  when true, always use background_color instead of deriving from active resource color
---@field show_value boolean  whether to show the current resource value as centered text
---@field bar_smoothing boolean  whether to smoothly animate bar value changes instead of snapping instantly
---@field sort_runes boolean  whether to sort rune bars so ready runes are on the left and regenerating runes on the right
---@field druid_cat_form boolean  whether to show combo points for non-Feral Druids when in Cat Form
---@field brewmaster_stagger boolean  whether to show a Stagger bar for Brewmaster Monks
---@field fire_blast_charges boolean  whether to show Fire Blast charge segments for Fire Mages
---@field skyriding_vigor boolean  whether to show vigor charges while on a skyriding mount
---@field skyriding_show_speed boolean  whether to show flight speed text while skyriding
---@field paladin_swing_timer boolean  whether to show Crusading Strikes swing timer fill on Holy Power segments
---@field paladin_swing_custom_color boolean  whether to use paladin_swing_color instead of auto-lightened resource color
---@field paladin_swing_color number[]  {r, g, b, a} custom color for swing timer fill
---@field paladin_divine_purpose boolean  whether to color-shift Holy Power bars when Divine Purpose is active
---@field paladin_divine_purpose_color number[]  {r, g, b, a} bar color used when Divine Purpose is active
---@field evoker_essence_burst boolean  whether to color-shift Essence bars when Essence Burst is active
---@field evoker_essence_burst_color number[]  {r, g, b, a} bar color used when Essence Burst is active
---@field evoker_essence_prediction boolean  whether to show the spender-prediction indicator on the leftmost essenceBurstCost slots
---@field warlock_spend_prediction boolean  whether to grey out Soul Shard segments during cast-time spenders
---@field warlock_shard_fragments boolean  whether to show Destruction Warlock Soul Shards as a fractional value
---@field builder_prediction boolean  whether to preview incoming resource on empty segments during cast-time builders
---@field builder_prediction_color number[]  {r, g, b, a} color for predicted-build overlay segments
---@field fire_blast_color number[]  {r, g, b, a} bar color for Fire Blast charge segments
---@field marksman_aimed_shot boolean  whether to show Aimed Shot charge segments for Marksmanship Hunters
---@field marksman_lock_and_load boolean  whether to color-shift Aimed Shot segments when Lock and Load is active
---@field marksman_aimed_shot_color number[]  {r, g, b, a} bar color for Aimed Shot charge segments
---@field marksman_lock_and_load_color number[]  {r, g, b, a} bar color when Lock and Load is active
---@field discipline_radiance_charges boolean  whether to show Power Word: Radiance charge segments for Discipline Priests
---@field discipline_radiance_color number[]  {r, g, b, a} bar color for Power Word: Radiance charge segments
---@field fury_whirlwind_color number[]  {r, g, b, a} bar color for Improved Whirlwind charge segments
---@field arms_sweeping_strikes boolean  toggle Sweeping Strikes stack segments for Arms Warriors
---@field arms_sweeping_strikes_color number[]  {r, g, b, a} bar color for Sweeping Strikes stack segments
---@field mistweaver_teachings boolean  toggle Teachings of the Monastery stack segments for Mistweaver Monks
---@field mistweaver_teachings_color number[]  {r, g, b, a} bar color for Teachings of the Monastery stack segments
---@field mage_shatter_stacks boolean  Frost Mage only: show a second row tracking Freezing (Shatter) stacks on the current target
---@field mage_shatter_color number[]  {r, g, b, a} bar color for the Shatter stack segments
---@field warlock_wild_imps boolean  Demonology Warlock only: show a second row tracking active Wild Imps
---@field warlock_wild_imps_color number[]  {r, g, b, a} bar color for the Wild Imp stack segments
---@field mage_arcane_salvo_stacks boolean  Arcane Mage only: show a second row tracking Arcane Salvo stacks
---@field mage_arcane_salvo_color number[]  {r, g, b, a} bar color for the Arcane Salvo stack segments
---@field evoker_unbound_flame boolean  Devastation Evoker only: show a second row tracking Unbound Flame casts left after Dragonrage
---@field evoker_unbound_flame_color number[]  {r, g, b, a} bar color for the Unbound Flame stack segments
---@field evoker_unbound_flame_expiry boolean  Devastation Evoker only: engine-drawn border while Unbound Flame is close to expiring
---@field evoker_unbound_flame_expiry_color number[]  {r, g, b, a} border color for the Unbound Flame expiry border
---@field dh_nearby_souls boolean  Demon Hunter (every spec): show a row tracking uncollected Soul Fragments lying nearby
---@field dh_nearby_souls_color number[]  {r, g, b, a} bar color for the nearby Soul Fragment stack segments
---@field dh_art_of_glaive_havoc boolean  Havoc Demon Hunter, Aldrachi Reaver only: show Art of the Glaive stacks as the spec's resource bar
---@field dh_art_of_glaive_vengeance boolean  Vengeance Demon Hunter, Aldrachi Reaver only: show a second row tracking Art of the Glaive stacks
---@field dh_art_of_glaive_devourer boolean  Devourer Demon Hunter, Aldrachi Reaver only: show a second row tracking Art of the Glaive stacks
---@field dh_art_of_glaive_color number[]  {r, g, b, a} bar color for the Art of the Glaive stack segments
---@field stack_strip_segmented boolean  draw stack strips (Sweeping Strikes, Teachings, Shatter, Wild Imps, Arcane Salvo, nearby Soul Fragments) as one segment per stack; off draws a single continuous fill bar instead
---@field survival_tots_color number[]  {r, g, b, a} bar color for Tip of the Spear stacks
---@field frost_icicles boolean  toggle Icicles bar for Frost Mages
---@field frost_icicles_color number[]  {r, g, b, a} bar color for Icicles
---@field guardian_ironfur boolean  toggle Ironfur bar for Guardian Druids
---@field guardian_ironfur_color number[]  {r, g, b, a} bar color for Ironfur
---@field soul_frag_veng_color number[]  {r, g, b, a} bar color for Vengeance Soul Fragment segments
---@field soul_frag_dev_color number[]  {r, g, b, a} bar color for Devourer Soul Fragment bar
---@field stagger_pips boolean  show pip marks and colored sections at 30%/60% stagger thresholds
---@field stagger_color_light number[]  {r, g, b, a} bar color for light Stagger level
---@field stagger_color_moderate number[]  {r, g, b, a} bar color for moderate Stagger level
---@field stagger_color_heavy number[]  {r, g, b, a} bar color for heavy Stagger level
---@field vitality_color number[]  {r, g, b, a} bar color for Vitality (Aspect of Harmony) bar
---@field vigor_color number[]  {r, g, b, a} bar color for Skyriding Vigor charges
---@field vigor_thrill_color number[]  {r, g, b, a} bar color for Skyriding Vigor during Thrill of the Skies
---@field charged_combo_color number[]  {r, g, b, a} bar color for charged (overloaded) combo points
---@field dk_blood_color number[]  {r, g, b, a} bar color for Blood Death Knight runes
---@field dk_frost_color number[]  {r, g, b, a} bar color for Frost Death Knight runes
---@field dk_unholy_color number[]  {r, g, b, a} bar color for Unholy Death Knight runes
---@field bar_spacing number  pixel gap between adjacent resource bar segments (default 2)
---@field value_font castbar_font_profile  font settings for the resource value text
---@field resource_thresholds_global_enabled boolean  global master toggle for threshold color overrides across every spec
---@field resource_thresholds_enabled table<string, boolean>  per-spec override toggle; missing key = enabled for that spec (honored only when global toggle is on)
---@field resource_thresholds table<string, resource_threshold[]>  per-spec threshold color overrides keyed by "CLASSFILENAME-specIndex"
---@field stack_strip_threshold_glow boolean  draw a pulsing border around a stack strip, one run per threshold, each revealed by the engine at exactly its stack count

---@class healthbar_profile_main : component_profile_main
---@field texture string  LibSharedMedia "statusbar" key; empty string = default DF health bar texture
---@field orientation string  "horizontal"|"vertical" — bar fill direction; vertical fills bottom→top
---@field value_font castbar_font_profile  font settings for the health value text (centered)
---@field text_format string  "percent"|"current"|"both" — controls what text is displayed on the bar
---@field color_mode string  "class"|"gradient" — class color or green→yellow→red health gradient
---@field background_color number[]  {r, g, b, a} background color behind the health bar
---@field show_shields boolean  when true, show the damage absorb shield overlay
---@field show_healing_prediction boolean  when true, show the incoming healing prediction overlay
---@field bar_smoothing boolean  whether to smoothly animate health bar value changes instead of snapping instantly

---@class castbar_font_profile : table
---@field font_face string  LibSharedMedia "font" key (e.g. "2002"); resolved via DF:SetFontFace
---@field font_size number  font size in pixels
---@field font_flags string  outline flags: "" (none), "OUTLINE", "THICKOUTLINE", etc.
---@field shadow_color? number[]  {r, g, b, a} shadow color; default {0, 0, 0, 1}
---@field shadow_offset_x? number  shadow X offset in pixels; default 1
---@field shadow_offset_y? number  shadow Y offset in pixels; default -1
---@field font_color? number[]  {r, g, b, a} text color; default {1, 1, 1, 1} (white)
---@field anchor_point? string  WoW anchor point for positioning (e.g. "CENTER", "LEFT"); nil = no position control (viewer-managed fonts)
---@field offset_x? number  horizontal pixel offset from anchor point
---@field offset_y? number  vertical pixel offset from anchor point

---@class globalcooldown_profile_main : component_profile_main
---@field texture string  LibSharedMedia "statusbar" key; "" = solid white fallback
---@field bar_color number[]  {r, g, b, a} color for the GCD bar
---@field latency_color number[]  {r, g, b, a} color for the latency overlay
---@field show_icon boolean  show the spell icon on the GCD bar; rendered square-sized to bar height, left-outside, zoom-cropped (matches cast bars)
---@field show_latency boolean  show the latency overlay on the right edge
---@field instant_only boolean  only show the GCD bar for instant casts (hide during cast bar spells)
---@field show_duration boolean  show remaining GCD time on the bar (default false)
---@field show_spell_name boolean  show spell name on bar for instant casts (default false)
---@field fill_direction string  "right" (left-to-right) or "left" (right-to-left) bar fill
---@field duration_font castbar_font_profile  font for duration text (rightText)
---@field spell_name_font castbar_font_profile  font for spell name text (leftText)

---@class castbar_component_profile_main : component_profile_main
---@field texture string  LibSharedMedia "statusbar" key; if found, applied via bar:SetTexture(path). Empty string or unregistered key falls back to bar.barTexture:SetColorTexture(1,1,1,1) (solid white).
---@field orientation string  "horizontal"|"vertical" — bar fill direction; vertical fills bottom→top
---@field show_icon boolean  show the spell icon on the cast bar (default true)
---@field show_channel_ticks boolean  show tick marks on the cast bar during channeled spells (default true)
---@field pushback_flash boolean  PlayerCastBar only: draw the progress a pushback took as a fading cutaway (key named for the flash it replaced) (default true)
---@field track_instant_casts boolean  PlayerCastBar only: briefly show the GCD as a backward-draining bar after instant casts (default false)
---@field show_latency boolean  PlayerCastBar only: show the latency overlay covering the end of the bar (default false)
---@field latency_color number[]  PlayerCastBar only: {r, g, b, a} color for the latency overlay
---@field cast_name_font castbar_font_profile  font settings for the spell name text (left-aligned)
---@field cast_time_font castbar_font_profile  font settings for the cast time text (right-aligned)

---@class bar_tracker_profile_main : component_profile_main
---@field layout_direction string  "vertical" (stack bars) or "horizontal" (bars side by side)
---@field layout_alignment string  vertical: "top"|"center"|"bottom"; horizontal: "left"|"center"|"right"
---@field bar_width number  width of each individual bar in pixels (default 220)
---@field icon_size number  square icon size on each bar item (default 30)
---@field bar_height number  height of each bar item in pixels (default 30)
---@field bar_spacing number  gap between bars in pixels (default 2)
---@field icon_offset number  horizontal gap between the icon and the progress bar in pixels (default 2)
---@field icon_offset_x number  horizontal offset of the bar icon in pixels; positive = right (default 0)
---@field icon_offset_y number  vertical offset of the bar icon in pixels; positive = up (default 0)
---@field growth_direction string  vertical: "up"|"down"; horizontal: "left"|"right"
---@field bar_content string  "IconAndName" | "IconOnly" | "NameOnly" | "BarOnlyNoName" | "IconAndBarNoName" — controls visible elements on each bar
---@field collapse boolean  when true and bar_content == "IconOnly", container width collapses to icon_size (overrides bar_width and anchor-inherited width); when false, IconOnly icons render inside the configured bar_width row
---@field show_timer boolean  show the remaining duration text on each bar
---@field show_totems boolean  append one bar per totem slot, the only display that can reach a summon (Dreadstalkers, Demonic Tyrant, a shaman totem) — those apply no aura, so no aura engine ever fills their row; works in both engines (the rows are a container of their own, chained onto the end of the run), and every slot is reserved whether occupied or not (default false)
---@field bar_fill_color number[]  {r, g, b, a} fill color for the status bar (default matches Blizzard's COOLDOWN_BAR_DEFAULT_COLOR orange)
---@field aura_unit table<number, string>  per-spell unit scope: "player" | "target"; absent = "both" (all three aura groups)
---@field always_show_tracked boolean  the always-show (slots) engine instead of the compacting groups one; slots is the only engine where per-spell features work. Seeded once from Blizzard's per-viewer "hide when inactive" by pm.MigrateHideWhenInactive (default false = groups)
---@field desaturate_inactive boolean  slots engine only; grey out a tracked icon while its aura is not up (or there is no target to hold it). The engine shows the slot button's full-colour copy while the aura is up, so no aura is read (default false)
---@field collapse_layout boolean  [EXPERIMENTAL] BuffTracker only; chain the slot buttons to each other with SetCollapsesLayout, spell-major across the player and target containers, so inactive ones close their own gap and player and target auras share one Tracking-tab order. One line, no wrap; ignored while always_show_tracked is on (default false)
---@field spell_colors table<number, number[]>  per-spell {r, g, b, a} bar fill override keyed by spellID; empty = use bar_fill_color for all spells
---@field active_glow boolean  show a persistent glow on bar items while their aura is active (default false)
---@field active_glow_color number[]  {r, g, b, a} active aura glow tint color (default green)
---@field pandemic_glow boolean  show Blizzard's pandemic bar glow when auras enter pandemic window (default false)
---@field pandemic_glow_style string  "blizzard"|"border"|"border_inside"|"ants"|"autocast"|"pixel" — pandemic glow visual style (default "border"; the aura trackers draw a static border and honour only the two border variants, the animated styles are Additional-Frame-only)
---@field pandemic_glow_color number[]  {r, g, b, a} pandemic glow color used when Urgency Colors is off; also the top (>= high threshold) urgency band (default green)
---@field pandemic_glow_thickness number  pixel thickness for "border"/"border_inside" (edge size) and "pixel"/"autocast" (LCG line width / shine scale) styles (1-6, default 2)
---@field pandemic_glow_excludes number[]  spellIDs excluded from pandemic glow (default empty)
---@field name_font castbar_font_profile  font settings for the spell name text on each bar
---@field duration_font castbar_font_profile  font settings for the remaining duration text on each bar
---@field stacks_font castbar_font_profile  font settings for the charge/stack count on each bar's icon
---@field priority_order? number[]  ordered tracker keys; array position = display order. Empty = Blizzard's CooldownViewer order. The all-specs order: read on a spec with no priority_order_spec entry of its own
---@field priority_order_spec? table<string, number[]>  per-spec icon orders keyed by the spec layer key ("CLASS-N"); a spec's own list wins over priority_order (Util.GetTrackerOrder). Made lazily by the Tracking tab, no default

---@class viewer_tracker_profile_main : component_profile_main
---@field layout_direction string  "horizontal" (rows of icons) or "vertical" (columns of icons)
---@field layout_alignment string  horizontal: "left"|"center"|"right"; vertical: "top"|"center"|"bottom"
---@field frame_size_mode string  "max_width" (overflow into rows/columns) | "max_per_row" (explicit per-row/column count) | "fixed_width" (dynamic square icons capped at dimension/4) | "fixed_width_spread" (icon_size spread evenly) | "fixed_width_stretch" (stretch along primary axis) | "chain_fit" (fixed_width sizing APPLIED to the collapsing chain's buttons; no longer offered, and only reachable from a profile saved while that prototype was enabled — every reader still treats it as fixed_width so such a profile stays correct); in vertical mode uses settings.height as constraint
---@field max_icons_per_row number  max icons per row (horizontal) or per column (vertical)
---@field min_width number  minimum container width in pixels when frame_size_mode is "max_per_row" or layout is vertical; 0 = no minimum
---@field icon_size number  explicit icon size in pixels (width = height); 0 = auto-computed from width and iconLimit
---@field icon_height number  explicit icon height override in pixels; 0 = use icon_size (square icons). Ignored in fixed_width_stretch mode.
---@field overflow_icon_size number  icon size for overflow lines; 0 = same as icon_size
---@field overflow_direction string  horizontal: "top"|"bottom"; vertical: "left"|"right"
---@field icon_offset number  additional pixel gap added to the viewer's native padding between icons (both horizontal and vertical); default 1
---@field timer_font castbar_font_profile  font settings for the cooldown countdown text on each icon
---@field stacks_font castbar_font_profile  font settings for the charge/stack count text on each icon
---@field priority_order? number[]  ordered tracker keys; array position = display order. Empty = Blizzard's CooldownViewer order. The all-specs order: read on a spec with no priority_order_spec entry of its own
---@field priority_order_spec? table<string, number[]>  per-spec icon orders keyed by the spec layer key ("CLASS-N", CDMDataSource.GetSpecLayerKey); a spec's own list wins over priority_order (Util.GetTrackerOrder). Made lazily by the Tracking tab, no default
---@field active_glow? boolean  show a persistent glow on icons while their aura is active (default false)
---@field active_glow_color? number[]  {r, g, b, a} active aura glow tint color (default green)
---@field pandemic_glow? boolean  show Blizzard's pandemic border glow on buff icons when aura enters pandemic window (default false)
---@field pandemic_glow_style? string  "blizzard"|"border"|"border_inside"|"ants"|"autocast"|"pixel" — pandemic glow visual style (default "border"; the aura trackers draw a static border and honour only the two border variants, the animated styles are Additional-Frame-only)
---@field pandemic_glow_color? number[]  {r, g, b, a} pandemic glow color used when Urgency Colors is off; also the top (>= high threshold) urgency band (default green)
---@field pandemic_glow_thickness? number  pixel thickness for "border"/"border_inside" (edge size) and "pixel"/"autocast" (LCG line width / shine scale) styles (1-6, default 2)
---@field pandemic_glow_excludes? number[]  spellIDs excluded from pandemic glow (default empty)
---@field hide_cd_swipe? boolean  hide the dark cooldown swipe overlay on icons when a spell is on cooldown (CooldownTracker/UtilitiesTracker/BuffTracker; default false)
---@field hide_active_swipe? boolean  OFF: while a tracked buff is active it takes the cooldown icon over — full colour, gold swipe, the buff's remaining time as the timer — as Blizzard's CDM did; ON: the icon only ever shows its cooldown (CooldownTracker/UtilitiesTracker only; default false)
---@field active_swipe_excludes? number[]  spellIDs the buff takeover leaves alone while hide_active_swipe is off; written by the Tracking tab (CooldownTracker/UtilitiesTracker and `spells` frames; default empty)
---@field spell_borders? table<number, number[]>  per-spell {r, g, b, a} icon border colour, keyed by spellID; an entry draws the border even while icon_border is off, size/inside stay global; written by the Tracking tab (every icon tracker and `spells`/`buffs` frame, not bars; no default table)
---@field missing_glow? table<number, number[]>  BuffTracker only, slots engine only; per-spell {r, g, b, a} glow drawn while the aura is not up, keyed by spellID; an entry turns it on; written by the Tracking tab (no default table)
---@field suppress_buff_icon_swap? boolean  prevent buff/aura effects from changing cooldown tracker icons (CooldownTracker/UtilitiesTracker only; default false)
---@field hide_gcd_swipe? boolean  hide the dark swipe overlay shown during the Global Cooldown on cooldown icons (CooldownTracker/UtilitiesTracker only; default false)
---@field gcd_edge_charges? boolean  show GCD as edge-only sweep on charge spells with remaining charges (default false)
---@field reverse_swipe? boolean  reverse the direction of cooldown and GCD swipe animations on icons (CooldownTracker/UtilitiesTracker only; default false)
---@field no_cd_overlay? boolean  do not dim the icon with a dark overlay when hide_active_swipe is on and the spell is on cooldown (CooldownTracker/UtilitiesTracker only; default false)
---@field no_cd_overlay_edge_only? boolean  when no_cd_overlay is on, show only the leading swipe edge instead of the tinted pie sweep (CooldownTracker/UtilitiesTracker only; default false)
---@field no_desaturation? boolean  keep icons fully saturated (colorful) even when on cooldown (default false)
---@field force_desaturation? boolean  grey the buff takeover's icon too, for the buff's whole duration — 2.13.4 greyed it only while on cooldown, which the takeover cannot read while auras are secret (CooldownTracker/UtilitiesTracker only; default false)
---@field no_range_tint? boolean  do not tint icons red (or shade them) while the target is out of the spell's range (CooldownTracker/UtilitiesTracker only; default false)
---@field hide_cd_text? boolean  hide all cooldown countdown numbers on icons (default false)
---@field hide_charge_cd_text? boolean  hide cooldown countdown text for charge spells while charges remain available (CooldownTracker only; default false)
---@field hide_zero_charges? boolean  hide the charge count text when all charges are depleted (CooldownTracker/UtilitiesTracker only; default false)
---@field proc_glow_style? string  "blizzard"|"border"|"border_inside"|"ants"|"autocast"|"pixel"|"none" — proc glow visual style (default "blizzard")
---@field proc_glow_color? number[]  {r, g, b, a} color tint for the proc glow (default white / no tint)
---@field proc_glow_alpha? number  opacity of the proc glow 0–100 (default 100)
---@field proc_glow_thickness? number  pixel thickness for "border"/"border_inside" (edge size) and "pixel"/"autocast" (LCG line width / shine scale) styles (1-6, default 2)
---@field rotation_highlight? boolean  show Blizzard rotation-helper ants animation on the tracker icon currently suggested by C_AssistedCombat.GetNextCastSpell (CooldownTracker/UtilitiesTracker only; default false)
---@field icon_visibility_mode? number  1=disabled, 2=hide-ready, 3=fade-ready, 4=hide-oncd, 5=fade-oncd (CooldownTracker/UtilitiesTracker/spells-type Additional Frames; default 1)
---@field hide_ready_blink? boolean  suppress the native end-of-cooldown blink (CooldownFlash) while keeping the icon fully visible; independent of icon_visibility_mode (CooldownTracker/UtilitiesTracker/spells-type Additional Frames; default false)
---@field icon_visibility_faded_alpha? number  target alpha (0..1) for the fade modes (3/5); icons faded to this value remain in layout. Default 0.3.
---@field icon_visibility_treat_charging_as_on_cd? boolean  charge-spell semantics for icon_visibility_mode: when true (default) a spell with any recharge in flight counts as on cooldown so hide/fade modes 4/5 trigger (and modes 2/3 stop treating it as ready); when false only the fully-depleted state (currentCharges == 0) counts as on cooldown. Applied symmetrically to hide/fade-when-ready and hide/fade-when-on-cd.
---@field show_skyriding_abilities? boolean  show skyriding ability cooldowns when Essential viewer is hidden during skyriding (CooldownTracker only; default true)
---@field show_vehicle_abilities? boolean  show vehicle action bar abilities (CooldownTracker only; default true)
---@field show_override_bar_abilities? boolean  show override action bar abilities (CooldownTracker only; default true)
---@field show_override_keybind_text? boolean  show keybind text on vehicle/override/skyriding ability icons (CooldownTracker only; default true)
---@field route_trinkets? boolean  show equipped on-use trinket icons inside CooldownTracker's grid (CooldownTracker only; default false)
---@field route_combat_potions? boolean  show combat potion icons inside CooldownTracker's grid (CooldownTracker only; default false)
---@field tooltip_mode "always"|"out_of_combat"|"off"  controls when hovering an icon shows the CUE tooltip; default "off"
---@field tooltip_anchor "DEFAULT"|"CURSOR"|"RIGHT"|"TOP"  anchor mode for the CUE tooltip relative to the hovered icon (default "RIGHT")
---@field custom_spells? custom_spell_entry[]  user-managed spell entries folded into this component's spell map and drawn by its own tracker
---@field show_totems? boolean  one icon per totem slot, in line before the player buffs — the only display that reaches a summon, which applies no aura; works in both engines (groups: empty slots collapse; always-show grid: fixed cells) (BuffTracker only; default false)

---@class custom_spell_entry : table
---@field spellID number  spell identifier rendered in the tracker
---@field restrict_to_player? boolean  hide the entry when the spell is not in the player's spellbook. Default on (nil = on); set explicit `false` to opt out for item-cast spells (Hearthstone, trinkets). Cooldown hosts only: an aura host ignores it and reads `specs`.
---@field specs? table<string, true>  aura hosts only: the specs ("CLASS-N", CDMDataSource.GetSpecLayerKey) the entry shows on. Stamped with the current spec on add; nil = every spec (entries from before the field, or added with the Tracking tab's "All specs" box); an empty table = none.
---@field ranks? "highest"  where the client has spell ranks (WoW Forever): draw the spell's highest learned rank, following it as ranks are learned. Written only by the Tracking tab for a cooldown host; absent = exactly `spellID` (an id typed in by hand is that explicit rank).
---@field by_name? true  aura hosts only: match every spell id carrying this spell's name (profile `aura_name_cache`), including ranks other players cast. Written only by the Tracking tab; absent = exactly `spellID`.

---@class glow_profile : table
---@field enabled boolean  master toggle for glow effects on this component
---@field combat_potions_only boolean  restrict flash/pulse/approaching glows to combat potions only (ConsumableTracker)
---@field flash_enabled boolean  play the transient flash when a cooldown ends in combat
---@field pulse_enabled boolean  show persistent pulsing glow after flash
---@field pulse_duration number  seconds to show persistent glow; 0 = until used or combat ends
---@field approaching_enabled boolean  show a subtle border glow when items are about to come off cooldown
---@field approaching_time number  seconds before cooldown ends to start the approaching glow; 0 = off
---@field low_health_enabled boolean  enable red border glow on health/healthstone icons when player HP is below threshold
---@field low_health_pct number  health percentage threshold for low health glow (e.g. 35 = 35%)
---@field active_enabled boolean  show a green border glow while the item's buff effect is active; duration auto-derived from spell description



---@class button_press_profile : table
---@field enabled boolean  show a pressed overlay on tracker icons when the corresponding action bar keybind is pressed

---@class trinket_tracker_profile_main : table
---@field enabled boolean
---@field alpha number  frame opacity 0.1–1.0; multiplied with inherited parent alpha via anchor chain; default 1.0
---@field width number  fallback width; at runtime, width is derived from icon_size and layout
---@field height number  fallback height; at runtime, height is derived from icon_size and layout
---@field icon_size number  square icon size in pixels
---@field icon_offset number  pixel gap between icons
---@field layout string  "horizontal" or "vertical"
---@field layout_alignment string  horizontal: "left"|"center"|"right"; vertical: "top"|"center"|"bottom"
---@field reserve_slots boolean  when true, always reserve space for 2 trinket slots even if fewer are active
---@field show_passive boolean  show proc trinkets that have no on-use effect; when false they are hidden and not counted toward the active slot count
---@field show_active_duration boolean  show the remaining buff duration while a trinket effect is active, switching to the cooldown when it expires
---@field show_slot_1 boolean  show trinket slot 13 (first trinket)
---@field show_slot_2 boolean  show trinket slot 14 (second trinket)
---@field excluded_trinkets table<number, boolean>  itemIDs to hide from the tracker
---@field glow glow_profile  glow/alert effect settings
---@field keybind_font castbar_font_profile  font settings for keybind text overlay (has enabled toggle)
---@field duration_font castbar_font_profile  font settings for the active buff duration timer text
---@field background component_background_profile  optional background panel behind the component frame
---@field anchor_profile anchor_profile

---@class racial_tracker_profile_main : table
---@field enabled boolean
---@field alpha number  frame opacity 0.1–1.0; multiplied with inherited parent alpha via anchor chain; default 1.0
---@field width number  fallback width; at runtime, width is derived from icon_size and layout
---@field height number  fallback height; at runtime, height is derived from icon_size and layout
---@field icon_size number  square icon size in pixels
---@field icon_offset number  pixel gap between icons
---@field layout string  "horizontal" or "vertical"
---@field hide_gcd_swipe? boolean  hide the dark swipe overlay shown during the Global Cooldown on racial icons (default false)
---@field reverse_swipe? boolean  reverse the direction of cooldown and GCD swipe animations on racial icons (default false)
---@field excluded_racials table<number, boolean>  spellIDs to hide from the tracker
---@field glow glow_profile  glow/alert effect settings
---@field keybind_font castbar_font_profile  font settings for keybind text overlay (has enabled toggle)
---@field duration_font castbar_font_profile  font settings for the active buff duration timer text
---@field background component_background_profile  optional background panel behind the component frame
---@field anchor_profile anchor_profile

---@class consumable_tracker_profile_main : table
---@field enabled boolean
---@field alpha number  frame opacity 0.1–1.0; multiplied with inherited parent alpha via anchor chain; default 1.0
---@field width number  fallback width; at runtime, width is derived from icon_size and layout
---@field height number  fallback height; at runtime, height is derived from icon_size and layout
---@field icon_size number  square icon size in pixels
---@field icon_offset number  pixel gap between icons
---@field layout string  "horizontal" or "vertical" or "block"
---@field block_direction string  "horizontal" (2 cols, fill left-to-right) or "vertical" (2 rows, fill top-to-bottom); only used when layout == "block"
---@field show_count boolean  when true, show item count overlay on each icon
---@field tracked_families table<string, boolean>  family key -> true if tracked
---@field tracked_categories table<string, boolean>  category key -> true if enabled
---@field keybind_font castbar_font_profile  font settings for keybind text overlay (has enabled toggle)
---@field count_font castbar_font_profile  font settings for the item count overlay text
---@field duration_font castbar_font_profile  font settings for the active buff duration timer text
---@field glow glow_profile  glow/alert effect settings
---@field background component_background_profile  optional background panel behind the component frame
---@field anchor_profile anchor_profile

---@class component_profile_secondary : table
---@field enabled boolean

---@type profile
local profile = {
    auto_hide = true,
    consumable_auto_hide = true,
    arcane_mana_bar = true,
    augmentation_ebon_might = true,
    augmentation_ebon_might_show_stat = true,
    augmentation_ebon_might_crit_color_value = {1.0, 0.95, 0.55, 1.0},
    augmentation_ebon_might_crit_glow = true,
    augmentation_ebon_might_double_time_text = true,
    augmentation_ebon_might_live_update = true,
    augmentation_ebon_might_show_duplicates = false,
    paladin_mana_bar = true,
    evoker_mana_bar = false,
    druid_mana_bar = false,
    shaman_mana_bar = false,
    balance_mana_bar = false,
    priest_mana_bar = false,
    icon_zoom = true,
    icon_aspect_ratio = true,
    debug_mode = false,
    debug_log_size = 10000,
    cooldown_layout_sync = true,
    cooldown_layouts = {},
    _cooldown_layout_char = {},
    cdm_auto_fetch = true,
    cdm_alerts = true,
    cdm_target_sounds = false,
    additional_frames = {},
    icon_overrides = {},
    spell_alerts = {},
    cdm_category_overrides = { cooldown = {}, aura = {} },
    aura_name_cache = {},
    button_press = {
        enabled = false,
    },
    castbar_colors = {
        use_class_color = false,
        casting = {1, 1, 0, 1},
        channeling = {0, 0.4, 1, 1},
        finished = {0, 1, 0, 1},
        non_interruptible = {.5, .5, .5, 1},
        interrupted = {1, .1, .1, 1},
        important = {.5, .0, .5, 1},
        empowered = {1, 0.886, 0, 1},
        instant_cast = {0.2, 0.6, 1, 1},
        background = {0.2, 0.2, 0.2, 0.8},
        background_texture = "",
    },
    resource_colors = {
        use_class_color = true,
        class_colors = {
            ROGUE = {1.00, 0.96, 0.41, 1},
            DRUID = {1.00, 0.49, 0.04, 1},
            PALADIN = {0.96, 0.55, 0.73, 1},
            MONK = {0.00, 1.00, 0.60, 1},
            WARLOCK = {0.53, 0.53, 0.93, 1},
            MAGE = {0.25, 0.78, 0.92, 1},
            DEATHKNIGHT = {0.77, 0.12, 0.23, 1},
            EVOKER = {0.20, 0.58, 0.50, 1},
        },
    },
    primary_resource_colors = {
        override_colors = false,
        power_colors = {
            MANA = {0.00, 0.00, 1.00, 1},
            RAGE = {1.00, 0.00, 0.00, 1},
            FOCUS = {1.00, 0.50, 0.25, 1},
            ENERGY = {1.00, 1.00, 0.00, 1},
            RUNIC_POWER = {0.00, 0.82, 1.00, 1},
            INSANITY = {0.40, 0.00, 0.80, 1},
            FURY = {0.79, 0.26, 0.99, 1},
            PAIN = {1.00, 0.61, 0.00, 1},
            LUNAR_POWER = {0.30, 0.52, 0.90, 1},
            MAELSTROM = {0.00, 0.50, 1.00, 1},
        },
    },
    health_gradient_colors = {
        low = {0.8, 0.1, 0.1, 1},
        mid = {0.8, 0.7, 0.15, 1},
        full = {0.2, 0.7, 0.2, 1},
    },
    bar_border = {
        enabled = false,
        color = {0, 0, 0, 1},
        inside = false,
        size = 1,
    },
    icon_border = {
        enabled = false,
        color = {0, 0, 0, 1},
        inside = false,
        size = 1,
    },
    breakpoint_pips = {
        enabled = false,
        pip_width = 2,
        pip_mode = "percent",
        show_pip_line = true,
        zone_auto_hide = true,
        fill_interpolation = "step",
        pips = {},
        per_spec_enabled = {},
    },
    components = {
        UtilitiesTracker = {
            enabled = true,
            alpha = 1,
            -- Empty = Blizzard's CooldownViewer order; the Tracking tab
            -- writes the whole list on the first reorder.
            priority_order = {},
            width = 400,
            height = 100,
            layout_direction = "horizontal",
            layout_alignment = "center",
            frame_size_mode = "max_width",
            max_icons_per_row = 8,
            min_width = 150,
            icon_size = 40,
            icon_height = 0,
            overflow_icon_size = 20,
            overflow_direction = "bottom",
            icon_offset = 1,
            hide_icon = false,
            hide_cd_swipe = false,
            hide_active_swipe = false,
            hide_gcd_swipe = false,
            gcd_edge_charges = false,
            reverse_swipe = false,
            no_cd_overlay = false,
            no_cd_overlay_edge_only = false,
            no_desaturation = false,
            force_desaturation = false,
            no_range_tint = false,
            hide_cd_text = false,
            hide_charge_cd_text = false,
            hide_zero_charges = false,
            active_glow = false,
            active_glow_color = {0.2, 0.8, 0.4, 1},
            pandemic_glow = false,
            pandemic_glow_style = "border",
            pandemic_glow_color = {0.2, 0.8, 0.4, 1},
            pandemic_glow_thickness = 2,
            pandemic_glow_excludes = {},
            custom_spells = {},
            proc_glow_style = "blizzard",
            proc_glow_color = {1, 1, 1, 1},
            proc_glow_alpha = 100,
            proc_glow_thickness = 2,
            rotation_highlight = false,
            cdm_glow_color = {1, 0.843, 0, 1},
            tooltip_mode = "off",
            tooltip_anchor = "RIGHT",
            suppress_buff_icon_swap = true,
            icon_visibility_mode = 1,
            hide_ready_blink = false,
            icon_visibility_faded_alpha = 0.3,
            icon_visibility_treat_charging_as_on_cd = true,
            timer_font = {
                font_face = "2002",
                font_size = 12,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "CENTER",
                offset_x = 0,
                offset_y = 0,
            },
            stacks_font = {
                font_face = "2002",
                font_size = 12,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "BOTTOMRIGHT",
                offset_x = -2,
                offset_y = 2,
            },
            keybind_font = {
                enabled = false,
                font_face = "2002",
                font_size = 12,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "BOTTOMLEFT",
                offset_x = 2,
                offset_y = 2,
            },
            background = {
                enabled = false,
                color = {0, 0, 0, 0.6},
                padding = 4,
                rounded = false,
                roundness = 8,
                border_color = {0, 0, 0, 0.8},
            },
            anchor_profile = {
                frame_point = "top",
                parent_point = "bottom",
                relative_frame = "PlayerCastBar",
                xoff = 0,
                yoff = -10,
                anchor_parent = "GlobalCooldown",
                anchor_side = "bottom",
                anchor_offset_x = 0,
                anchor_offset_y = -2,
                anchor_width_pct = 100,
                anchor_width_mode = "percent",
            },
        },

        BuffTracker = {
            enabled = true,
            alpha = 1,
            -- Empty = Blizzard's CooldownViewer order; the Tracking tab
            -- writes the whole list on the first reorder.  Slots and per-spell
            -- groups honour it; the plain compacting group cannot (Blizzard
            -- owns that flow) -- see Core/AuraContainer.lua.
            priority_order = {},
            -- Per-spell unit scope ("player"/"target"); absent = "both".
            aura_unit = {},
            -- The slots engine.  false = groups, the engine Blizzard's own
            -- "hide when inactive" (which ships ON) used to select; the player's
            -- Blizzard setting is copied in once by pm.MigrateHideWhenInactive.
            always_show_tracked = false,
            -- Grey icon while the aura is not up; slots engine only.
            desaturate_inactive = false,
            -- [EXPERIMENTAL] one aura group per spell — compaction WITH per-spell
            -- identity.  Only meaningful while the groups engine is in force.
            -- [EXPERIMENTAL] collapsing slot chain: player and target auras in
            -- one Tracking-tab order, on one line.  Off under always_show_tracked.
            -- See AuraIconTracker's CHAIN_ENABLED.
            collapse_layout = false,
            -- The icon twin of BuffTrackerBars' key: off by default and without
            -- settings of its own, for the same reason (Core/AuraTrackers.md).
            show_totems = false,
            width = 400,
            height = 100,
            layout_direction = "horizontal",
            layout_alignment = "center",
            frame_size_mode = "max_width",
            max_icons_per_row = 8,
            min_width = 150,
            icon_size = 40,
            icon_height = 0,
            overflow_icon_size = 20,
            overflow_direction = "top",
            icon_offset = 1,
            hide_cd_text = false,
            hide_cd_swipe = false,
            hide_icon = false,
            active_glow = false,
            active_glow_color = {0.2, 0.8, 0.4, 1},
            pandemic_glow = false,
            pandemic_glow_style = "border",
            pandemic_glow_color = {0.2, 0.8, 0.4, 1},
            pandemic_glow_thickness = 2,
            pandemic_glow_excludes = {},
            custom_spells = {},
            proc_glow_style = "blizzard",
            proc_glow_color = {1, 1, 1, 1},
            proc_glow_alpha = 100,
            proc_glow_thickness = 2,
            tooltip_mode = "off",
            tooltip_anchor = "RIGHT",
            timer_font = {
                font_face = "2002",
                font_size = 14,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "CENTER",
                offset_x = 0,
                offset_y = 0,
            },
            stacks_font = {
                font_face = "2002",
                font_size = 14,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "BOTTOMRIGHT",
                offset_x = -2,
                offset_y = 2,
            },
            background = {
                enabled = false,
                color = {0, 0, 0, 0.6},
                padding = 4,
                rounded = false,
                roundness = 8,
                border_color = {0, 0, 0, 0.8},
            },
            anchor_profile = {
                frame_point = "top",
                parent_point = "bottom",
                relative_frame = "CooldownTracker",
                xoff = 0,
                yoff = -10,
                anchor_parent = "CooldownTracker",
                anchor_side = "top",
                anchor_offset_x = 0,
                anchor_offset_y = 2,
                anchor_width_pct = 100,
                anchor_width_mode = "percent",
            },
        },

        BuffTrackerBars = {
            enabled = true,
            alpha = 1,
            -- See BuffTracker: empty = Blizzard's CooldownViewer order, and only
            -- the slots engine can honour it.
            priority_order = {},
            -- See BuffTracker: the slots engine; false = groups.
            always_show_tracked = false,
            -- See BuffTracker.
            desaturate_inactive = false,
            width = 250,
            height = 100,
            layout_direction = "vertical",
            layout_alignment = "center",
            bar_width = 220,
            icon_size = 30,
            bar_height = 30,
            bar_spacing = 2,
            icon_offset = 2,
            icon_offset_x = 0,
            icon_offset_y = 0,
            growth_direction = "up",
            bar_content = "IconAndName",
            collapse = false,
            show_timer = true,
            -- Off by default, and deliberately without settings of its own: the
            -- rows exist only until Blizzard gives AuraContainers a totem API,
            -- and every knob would be migration debt (Core/AuraTrackers.md).
            show_totems = false,
            bar_fill_color = {1, 0.5, 0.25, 1},
            spell_colors = {},
            -- Per-spell unit scope ("player"/"target"); absent = "both".
            aura_unit = {},
            active_glow = false,
            active_glow_color = {0.2, 0.8, 0.4, 1},
            pandemic_glow = false,
            pandemic_glow_style = "border",
            pandemic_glow_color = {0.2, 0.8, 0.4, 1},
            pandemic_glow_thickness = 2,
            pandemic_glow_excludes = {},
            -- "border" rather than the icon trackers' "blizzard": the proc atlas is
            -- square art stretched to the host rect, which reads wrong across a
            -- wide bar.  Every style stays selectable.
            proc_glow_style = "border",
            proc_glow_color = {1, 1, 1, 1},
            proc_glow_alpha = 100,
            proc_glow_thickness = 2,
            tooltip_mode = "off",
            tooltip_anchor = "RIGHT",
            custom_spells = {},
            name_font = {
                font_face = "2002",
                font_size = 12,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "LEFT",
                offset_x = 5,
                offset_y = 0,
            },
            duration_font = {
                font_face = "2002",
                font_size = 12,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "RIGHT",
                offset_x = -8,
                offset_y = 0,
            },
            stacks_font = {
                font_face = "2002",
                font_size = 12,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "BOTTOMRIGHT",
                offset_x = -5,
                offset_y = 5,
            },
            background = {
                enabled = false,
                color = {0, 0, 0, 0.6},
                padding = 4,
                rounded = false,
                roundness = 8,
                border_color = {0, 0, 0, 0.8},
            },
            anchor_profile = {
                frame_point = "top",
                parent_point = "center",
                relative_frame = "UIParent",
                xoff = -150,
                yoff = -140,
                anchor_parent = "CooldownTracker",
                anchor_side = "left",
                anchor_offset_x = -10,
                anchor_offset_y = 0,
                anchor_width_pct = 100,
                anchor_width_mode = "percent",
            },
        },

        CooldownTracker = {
            enabled = true,
            alpha = 1,
            -- Empty = Blizzard's CooldownViewer order; the Tracking tab
            -- writes the whole list on the first reorder.
            priority_order = {},
            width = 450,
            height = 150,
            layout_direction = "horizontal",
            layout_alignment = "center",
            frame_size_mode = "max_width",
            max_icons_per_row = 8,
            min_width = 150,
            icon_size = 50,
            icon_height = 0,
            overflow_icon_size = 30,
            overflow_direction = "top",
            icon_offset = 1,
            hide_icon = false,
            hide_cd_swipe = false,
            hide_active_swipe = false,
            hide_gcd_swipe = false,
            gcd_edge_charges = false,
            reverse_swipe = false,
            no_cd_overlay = false,
            no_cd_overlay_edge_only = false,
            no_desaturation = false,
            force_desaturation = false,
            no_range_tint = false,
            hide_cd_text = false,
            hide_charge_cd_text = false,
            hide_zero_charges = false,
            active_glow = false,
            active_glow_color = {0.2, 0.8, 0.4, 1},
            pandemic_glow = false,
            pandemic_glow_style = "border",
            pandemic_glow_color = {0.2, 0.8, 0.4, 1},
            pandemic_glow_thickness = 2,
            pandemic_glow_excludes = {},
            custom_spells = {},
            proc_glow_style = "blizzard",
            proc_glow_color = {1, 1, 1, 1},
            proc_glow_alpha = 100,
            proc_glow_thickness = 2,
            rotation_highlight = false,
            cdm_glow_color = {1, 0.843, 0, 1},
            show_skyriding_abilities = true,
            show_vehicle_abilities = false,
            show_override_bar_abilities = false,
            show_override_keybind_text = true,
            route_trinkets = false,
            route_combat_potions = false,
            suppress_buff_icon_swap = true,
            tooltip_mode = "off",
            tooltip_anchor = "RIGHT",
            icon_visibility_mode = 1,
            hide_ready_blink = false,
            icon_visibility_faded_alpha = 0.3,
            icon_visibility_treat_charging_as_on_cd = true,
            timer_font = {
                font_face = "2002",
                font_size = 20,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "CENTER",
                offset_x = 0,
                offset_y = 0,
            },
            stacks_font = {
                font_face = "2002",
                font_size = 14,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "BOTTOMRIGHT",
                offset_x = -2,
                offset_y = 2,
            },
            keybind_font = {
                enabled = false,
                font_face = "2002",
                font_size = 14,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "BOTTOMLEFT",
                offset_x = 2,
                offset_y = 2,
            },
            background = {
                enabled = false,
                color = {0, 0, 0, 0.6},
                padding = 4,
                rounded = false,
                roundness = 8,
                border_color = {0, 0, 0, 0.8},
            },
            anchor_profile = {
                frame_point = "top",
                parent_point = "center",
                relative_frame = "UIParent",
                xoff = 0,
                yoff = -140,
                anchor_parent = "none",
                anchor_side = "bottom",
                anchor_offset_x = 0,
                anchor_offset_y = -2,
                anchor_width_pct = 100,
                anchor_width_mode = "absolute",
            },
        },

        TrinketTracker = {
            enabled = true,
            alpha = 1,
            width = 110,
            height = 50,
            icon_size = 50,
            icon_height = 0,
            icon_offset = 2,
            layout = "horizontal",
            layout_alignment = "center",
            reserve_slots = false,
            show_passive = true,
            show_active_duration = true,
            no_desaturation = false,
            hide_cd_text = false,
            show_slot_1 = true,
            show_slot_2 = true,
            excluded_trinkets = {},
            tooltip_mode = "off",
            tooltip_anchor = "RIGHT",
            glow = {
                enabled = true,
                combat_potions_only = true,
                flash_enabled = true,
                pulse_enabled = true,
                pulse_duration = 15,
                approaching_enabled = true,
                approaching_time = 15,
                low_health_enabled = false,
                low_health_pct = 35,
                active_enabled = true,
                ready_in_mplus_enabled = false,
            },
            keybind_font = {
                enabled = false,
                font_face = "2002",
                font_size = 12,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "BOTTOMLEFT",
                offset_x = 2,
                offset_y = 2,
            },
            duration_font = {
                font_face = "2002",
                font_size = 12,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "CENTER",
                offset_x = 0,
                offset_y = 0,
            },
            background = {
                enabled = false,
                color = {0, 0, 0, 0.6},
                padding = 4,
                rounded = false,
                roundness = 8,
                border_color = {0, 0, 0, 0.8},
            },
            anchor_profile = {
                frame_point = "top",
                parent_point = "center",
                relative_frame = "UIParent",
                xoff = 0,
                yoff = 250,
                anchor_parent = "CooldownTracker",
                anchor_side = "right",
                anchor_offset_x = 2,
                anchor_offset_y = 0,
                anchor_width_pct = 100,
                anchor_width_mode = "percent",
            },
        },

        RacialTracker = {
            enabled = false,
            alpha = 1,
            width = 60,
            height = 50,
            icon_size = 50,
            icon_height = 0,
            icon_offset = 2,
            layout = "horizontal",
            hide_gcd_swipe = false,
            reverse_swipe = false,
            no_desaturation = false,
            hide_cd_text = false,
            excluded_racials = {},
            tooltip_mode = "off",
            tooltip_anchor = "RIGHT",
            glow = {
                enabled = true,
                flash_enabled = true,
                pulse_enabled = true,
                pulse_duration = 15,
                approaching_enabled = true,
                approaching_time = 15,
                low_health_enabled = false,
                low_health_pct = 35,
                active_enabled = false,
            },
            keybind_font = {
                enabled = false,
                font_face = "2002",
                font_size = 12,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "BOTTOMLEFT",
                offset_x = 2,
                offset_y = 2,
            },
            duration_font = {
                font_face = "2002",
                font_size = 12,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "CENTER",
                offset_x = 0,
                offset_y = 0,
            },
            background = {
                enabled = false,
                color = {0, 0, 0, 0.6},
                padding = 4,
                rounded = false,
                roundness = 8,
                border_color = {0, 0, 0, 0.8},
            },
            anchor_profile = {
                frame_point = "top",
                parent_point = "center",
                relative_frame = "UIParent",
                xoff = 0,
                yoff = 250,
                anchor_parent = "TrinketTracker",
                anchor_side = "right",
                anchor_offset_x = 2,
                anchor_offset_y = 0,
                anchor_width_pct = 100,
                anchor_width_mode = "percent",
            },
        },

        ConsumableTracker = {
            enabled = true,
            alpha = 1,
            width = 110,
            height = 50,
            icon_size = 40,
            icon_height = 0,
            icon_offset = 2,
            layout = "horizontal",
            layout_alignment = "left",
            block_direction = "horizontal",
            show_count = true,
            no_desaturation = false,
            hide_cd_text = false,
            tooltip_mode = "off",
            tooltip_anchor = "RIGHT",
            tracked_families = {
                lights_potential = true,
                draught_of_rampant_abandon = true,
                potion_of_recklessness = true,
                potion_of_zealotry = true,
                liquid_luster = true,
                alluring_nostrum = true,
                concentrated_silvermoon_health_potion = true,
                silvermoon_health_potion = true,
                refreshing_serum = true,
                amani_extract = true,
                potent_healing_potion = true,
                lightfused_mana_potion = true,
                healthstone = true,
                demonic_healthstone = true,
                void_touched_drums = true,
                emergency_soul_link = true,
            },
            tracked_categories = {
                combat = true,
                health = true,
                mana = true,
                healthstone = true,
                utility = true,
            },
            glow = {
                enabled = true,
                combat_potions_only = true,
                flash_enabled = true,
                pulse_enabled = true,
                pulse_duration = 15,
                approaching_enabled = true,
                approaching_time = 15,
                low_health_enabled = false,
                low_health_pct = 35,
                active_enabled = true,
                ready_in_mplus_enabled = false,
            },
            keybind_font = {
                enabled = false,
                font_face = "2002",
                font_size = 12,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "BOTTOMLEFT",
                offset_x = 2,
                offset_y = 2,
            },
            count_font = {
                font_face = "2002",
                font_size = 14,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "BOTTOMRIGHT",
                offset_x = -2,
                offset_y = 2,
            },
            duration_font = {
                font_face = "2002",
                font_size = 12,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "CENTER",
                offset_x = 0,
                offset_y = 0,
            },
            background = {
                enabled = false,
                color = {0, 0, 0, 0.6},
                padding = 4,
                rounded = false,
                roundness = 8,
                border_color = {0, 0, 0, 0.8},
            },
            anchor_profile = {
                frame_point = "top",
                parent_point = "center",
                relative_frame = "UIParent",
                xoff = 0,
                yoff = 250,
                anchor_parent = "CooldownTracker",
                anchor_side = "left",
                anchor_offset_x = -2,
                anchor_offset_y = 0,
                anchor_width_pct = 100,
                anchor_width_mode = "percent",
            },
        },

        ---@class consumable_buff_tracker_profile_main : table
        ---@field enabled boolean
        ---@field alpha number
        ---@field width number
        ---@field height number
        ---@field icon_size number
        ---@field icon_height number
        ---@field icon_offset number
        ---@field layout string
        ---@field layout_alignment string
        ---@field block_direction string
        ---@field show_duration boolean
        ---@field show_count boolean
        ---@field hide_when_applied boolean
        ---@field clickable boolean
        ---@field tracked_buffs table<string, boolean>
        ---@field tracked_categories table<string, boolean>
        ---@field imbue_last table<number, number>  weapon slot -> rank-1 spell ID of the last imbue seen there
        ---@field poison_last table<number, number>  weapon slot -> rank-1 item ID of the last poison seen there
        ---@field glow table
        ---@field count_font castbar_font_profile
        ---@field duration_font castbar_font_profile
        ---@field background component_background_profile
        ---@field anchor_profile anchor_profile
        ConsumableBuffTracker = {
            enabled = true,
            alpha = 1,
            width = 200,
            height = 50,
            icon_size = 40,
            icon_height = 0,
            icon_offset = 2,
            layout = "horizontal",
            layout_alignment = "left",
            block_direction = "horizontal",
            show_duration = true,
            show_count = true,
            hide_cd_text = false,
            hide_cd_swipe = false,
            hide_icon = false,
            hide_when_applied = false,
            clickable = false,
            show_in_challenge_mode = false,
            tracked_buffs = {},
            tooltip_mode = "off",
            tooltip_anchor = "RIGHT",
            tracked_categories = {
                flask = true,
                food = true,
                rune = true,
                oil = true,
                weapon_buff = true,
                imbue = true,
                poison = true,
            },
            imbue_last = {},
            poison_last = {},
            glow = {
                enabled = true,
                missing_enabled = true,
                expiring_enabled = true,
                expiring_time = 300,
            },
            count_font = {
                font_face = "2002",
                font_size = 14,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "BOTTOMRIGHT",
                offset_x = -2,
                offset_y = 2,
            },
            duration_font = {
                font_face = "2002",
                font_size = 12,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "CENTER",
                offset_x = 0,
                offset_y = 0,
            },
            background = {
                enabled = false,
                color = {0, 0, 0, 0.6},
                padding = 4,
                rounded = false,
                roundness = 8,
                border_color = {0, 0, 0, 0.8},
            },
            anchor_profile = {
                frame_point = "top",
                parent_point = "center",
                relative_frame = "UIParent",
                xoff = 0,
                yoff = 200,
                position_reference = "UtilitiesTracker",
                position_side = "bottom",
                position_offset = 30,
            },
        },

        ---@class raid_buff_tracker_profile_main : table
        ---@field enabled boolean
        ---@field alpha number
        ---@field width number
        ---@field height number
        ---@field icon_size number
        ---@field icon_height number
        ---@field icon_offset number
        ---@field layout string
        ---@field layout_alignment string
        ---@field block_direction string
        ---@field show_duration boolean
        ---@field show_all_buffs boolean
        ---@field hide_when_applied boolean
        ---@field clickable boolean
        ---@field tracked_buffs table<string, boolean>
        ---@field glow table
        ---@field duration_font castbar_font_profile
        ---@field background component_background_profile
        ---@field anchor_profile anchor_profile
        RaidBuffTracker = {
            enabled = true,
            alpha = 1,
            width = 200,
            height = 50,
            icon_size = 40,
            icon_height = 0,
            icon_offset = 2,
            layout = "horizontal",
            layout_alignment = "left",
            block_direction = "horizontal",
            show_duration = true,
            show_all_buffs = false,
            hide_cd_text = false,
            hide_cd_swipe = false,
            hide_icon = false,
            hide_when_applied = false,
            clickable = false,
            tracked_buffs = {},
            tooltip_mode = "off",
            tooltip_anchor = "RIGHT",
            glow = {
                enabled = true,
                missing_enabled = true,
            },
            duration_font = {
                font_face = "2002",
                font_size = 12,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "CENTER",
                offset_x = 0,
                offset_y = 0,
            },
            background = {
                enabled = false,
                color = {0, 0, 0, 0.6},
                padding = 4,
                rounded = false,
                roundness = 8,
                border_color = {0, 0, 0, 0.8},
            },
            anchor_profile = {
                frame_point = "top",
                parent_point = "center",
                relative_frame = "UIParent",
                xoff = 0,
                yoff = 170,
                position_reference = "ConsumableBuffTracker",
                position_side = "bottom",
                position_offset = 2,
            },
        },

        ---@class outbound_buff_tracker_profile_main : bar_tracker_profile_main
        ---@field tracked_spells number[]  list of spellIDs whose outbound casts (player → allies) are rendered as bars (default {410089} = Prescience)
        ---@field filter_self_cast boolean  when true, suppress bars for auras the player applied on themselves (default false)
        ---@field name_color_source string  "class" (class color) or "static" (name_color_static) — drives recipient name text color
        ---@field name_color_static number[]  {r, g, b, a} recipient name color when name_color_source = "static"
        ---@field sort_order string  "remaining_asc" | "remaining_desc" | "name_asc"
        ---@field max_bars number  maximum number of bars rendered simultaneously (default 8)
        ---@field overflow_hide boolean  when true, entries past max_bars are hidden; when false they render past the configured limit
        OutboundBuffTracker = {
            enabled = false,
            alpha = 1,
            width = 220,
            height = 20,
            layout_direction = "vertical",
            layout_alignment = "center",
            bar_width = 220,
            icon_size = 20,
            bar_height = 20,
            bar_spacing = 2,
            icon_offset = 2,
            icon_offset_x = 0,
            icon_offset_y = 0,
            growth_direction = "down",
            bar_content = "IconAndName",
            collapse = false,
            show_timer = true,
            bar_fill_color = {0.25, 0.78, 0.92, 1},
            spell_colors = {},
            tracked_spells = {410089},
            filter_self_cast = false,
            name_color_source = "class",
            name_color_static = {1, 1, 1, 1},
            sort_order = "remaining_asc",
            max_bars = 8,
            overflow_hide = true,
            tooltip_mode = "off",
            tooltip_anchor = "RIGHT",
            name_font = {
                font_face = "2002",
                font_size = 12,
                font_flags = "OUTLINE",
                offset_x = 0,
                offset_y = 0,
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
            },
            duration_font = {
                font_face = "2002",
                font_size = 12,
                font_flags = "OUTLINE",
                offset_x = 0,
                offset_y = 0,
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
            },
            stacks_font = {
                font_face = "2002",
                font_size = 12,
                font_flags = "OUTLINE",
                offset_x = 0,
                offset_y = 0,
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
            },
            background = {
                enabled = false,
                color = {0, 0, 0, 0.6},
                padding = 4,
                rounded = false,
                roundness = 8,
                border_color = {0, 0, 0, 0.8},
            },
            anchor_profile = {
                frame_point = "top",
                parent_point = "center",
                relative_frame = "UIParent",
                xoff = -150,
                yoff = -220,
                anchor_parent = "BuffTrackerBars",
                anchor_side = "top",
                anchor_offset_x = 0,
                anchor_offset_y = 4,
                anchor_width_pct = 100,
                anchor_width_mode = "percent",
            },
        },

        PlayerCastBar = {
            enabled = true,
            alpha = 1,
            width = 200,
            height = 20,
            texture = "",
            orientation = "horizontal",
            show_icon = true,
            show_spark = true,
            cast_text_format = "both",
            cast_time_style = "remaining",
            cast_name_max_width = 0,
            mass_disintegrate_glow = true,
            show_channel_ticks = true,
            pushback_flash = true,
            show_when_casting = false,
            hide_inactive_background = false,
            track_instant_casts = false,
            show_latency = false,
            latency_color = {1, 0, 0, 0.8},
            cast_name_font = {
                font_face = "2002",
                font_size = 12,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "LEFT",
                offset_x = 3,
                offset_y = 0,
            },
            cast_time_font = {
                font_face = "2002",
                font_size = 12,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "RIGHT",
                offset_x = -3,
                offset_y = 0,
            },
            background = {
                enabled = false,
                color = {0, 0, 0, 0.6},
                padding = 4,
                rounded = false,
                roundness = 8,
                border_color = {0, 0, 0, 0.8},
            },
            anchor_profile = {
                frame_point = "top",
                parent_point = "center",
                relative_frame = "UIParent",
                xoff = 0,
                yoff = -200,
                anchor_parent = "PrimaryResources",
                anchor_side = "bottom",
                anchor_offset_x = 0,
                anchor_offset_y = -2,
                anchor_width_pct = 100,
                anchor_width_mode = "percent",
            },
        },

        TargetCastBar = {
            enabled = false,
            alpha = 1,
            width = 200,
            height = 20,
            texture = "",
            orientation = "horizontal",
            show_icon = true,
            show_spark = true,
            show_shield = true,
            shield_scale = 1.0,
            shield_offset_x = 0,
            shield_offset_y = 0,
            cast_text_format = "both",
            cast_time_style = "remaining",
            cast_name_max_width = 0,
            cast_name_font = {
                font_face = "2002",
                font_size = 12,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "LEFT",
                offset_x = 3,
                offset_y = 0,
            },
            cast_time_font = {
                font_face = "2002",
                font_size = 12,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "RIGHT",
                offset_x = -3,
                offset_y = 0,
            },
            background = {
                enabled = false,
                color = {0, 0, 0, 0.6},
                padding = 4,
                rounded = false,
                roundness = 8,
                border_color = {0, 0, 0, 0.8},
            },
            anchor_profile = {
                frame_point = "top",
                parent_point = "center",
                relative_frame = "UIParent",
                xoff = 0,
                yoff = 200,
                anchor_parent = "none",
                anchor_side = "bottom",
                anchor_offset_x = 0,
                anchor_offset_y = -2,
                anchor_width_pct = 100,
                anchor_width_mode = "absolute",
            },
        },

        FocusCastBar = {
            enabled = false,
            alpha = 1,
            width = 200,
            height = 20,
            texture = "",
            orientation = "horizontal",
            show_icon = true,
            show_spark = true,
            show_shield = true,
            shield_scale = 1.0,
            shield_offset_x = 0,
            shield_offset_y = 0,
            cast_text_format = "both",
            cast_time_style = "remaining",
            cast_name_max_width = 0,
            cast_name_font = {
                font_face = "2002",
                font_size = 12,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "LEFT",
                offset_x = 3,
                offset_y = 0,
            },
            cast_time_font = {
                font_face = "2002",
                font_size = 12,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "RIGHT",
                offset_x = -3,
                offset_y = 0,
            },
            background = {
                enabled = false,
                color = {0, 0, 0, 0.6},
                padding = 4,
                rounded = false,
                roundness = 8,
                border_color = {0, 0, 0, 0.8},
            },
            anchor_profile = {
                frame_point = "top",
                parent_point = "center",
                relative_frame = "UIParent",
                xoff = 0,
                yoff = 230,
                anchor_parent = "none",
                anchor_side = "bottom",
                anchor_offset_x = 0,
                anchor_offset_y = -2,
                anchor_width_pct = 100,
                anchor_width_mode = "absolute",
            },
        },

        GlobalCooldown = {
            enabled = false,
            alpha = 1,
            width = 200,
            height = 8,
            texture = "",
            bar_color = {1, 1, 1, 1},
            latency_color = {1, 0, 0, 0.8},
            show_icon = false,
            show_latency = true,
            instant_only = false,
            show_duration = false,
            show_spell_name = false,
            fill_direction = "right",
            duration_font = {
                font_face = "2002",
                font_size = 12,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "RIGHT",
                offset_x = -3,
                offset_y = 0,
            },
            spell_name_font = {
                font_face = "2002",
                font_size = 12,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "LEFT",
                offset_x = 3,
                offset_y = 0,
            },
            show_queue_pip = false,
            queue_pip_color = {1, 1, 0, 0.8},
            hide_inactive_background = false,
            background = {
                enabled = false,
                color = {0, 0, 0, 0.6},
                padding = 2,
                rounded = false,
                roundness = 8,
                border_color = {0, 0, 0, 0.8},
            },
            anchor_profile = {
                frame_point = "top",
                parent_point = "center",
                relative_frame = "UIParent",
                xoff = 0,
                yoff = -200,
                anchor_parent = "PlayerCastBar",
                anchor_side = "bottom",
                anchor_offset_x = 0,
                anchor_offset_y = -2,
                anchor_width_pct = 100,
                anchor_width_mode = "percent",
            },
        },

        PlayerHealthBar = {
            enabled = false,
            alpha = 1,
            width = 200,
            height = 20,
            texture = "",
            orientation = "horizontal",
            text_format = "both",
            color_mode = "class",
            interactable = false,
            show_shields = true,
            show_healing_prediction = true,
            bar_smoothing = true,
            background_color = {0.2, 0.2, 0.2, 0.8},
            value_font = {
                font_face = "2002",
                font_size = 12,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "CENTER",
                offset_x = 0,
                offset_y = 0,
            },
            background = {
                enabled = false,
                color = {0, 0, 0, 0.6},
                padding = 4,
                rounded = false,
                roundness = 8,
                border_color = {0, 0, 0, 0.8},
            },
            anchor_profile = {
                frame_point = "top",
                parent_point = "center",
                relative_frame = "UIParent",
                xoff = 0,
                yoff = -175,
                anchor_parent = "SecondaryResources",
                anchor_side = "bottom",
                anchor_offset_x = 0,
                anchor_offset_y = -2,
                anchor_width_pct = 100,
                anchor_width_mode = "percent",
            },
        },

        PrimaryResources = {
            enabled = true,
            alpha = 1,
            width = 200,
            height = 20,
            texture = "",
            orientation = "horizontal",
            text_format_mana = "percent",
            text_format_other = "current",
            bar_smoothing = true,
            spend_prediction = false,
            spend_prediction_color = {0.8, 0.2, 0.2, 0.6},
            five_second_rule = true,
            five_second_rule_size = "full",
            background_color = {0.2, 0.2, 0.2, 0.8},
            value_font = {
                font_face = "2002",
                font_size = 12,
                font_flags = "",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "CENTER",
                offset_x = 0,
                offset_y = 0,
            },
            background = {
                enabled = false,
                color = {0, 0, 0, 0.6},
                padding = 4,
                rounded = false,
                roundness = 8,
                border_color = {0, 0, 0, 0.8},
            },
            anchor_profile = {
                frame_point = "top",
                parent_point = "center",
                relative_frame = "UIParent",
                xoff = 0,
                yoff = -165,
                anchor_parent = "PlayerHealthBar",
                anchor_side = "bottom",
                anchor_offset_x = 0,
                anchor_offset_y = -2,
                anchor_width_pct = 100,
                anchor_width_mode = "percent",
            },
        },

        SecondaryResources = {
            enabled = true,
            alpha = 1,
            width = 400,
            height = 25,
            extra_row_height = 8,
            texture = "",
            orientation = "horizontal",
            show_value = false,
            bar_smoothing = true,
            sort_runes = true,
            druid_cat_form = false,
            brewmaster_stagger = false,
            stagger_pips = false,
            brewmaster_vitality = false,
            mistweaver_vitality = true,
            mistweaver_teachings = false,
            fury_whirlwind = true,
            arms_sweeping_strikes = true,
            mage_shatter_stacks = false,
            warlock_wild_imps = false,
            mage_arcane_salvo_stacks = false,
            evoker_unbound_flame = false,
            evoker_unbound_flame_expiry = false,
            dh_nearby_souls = false,
            dh_art_of_glaive_havoc = false,
            dh_art_of_glaive_vengeance = false,
            dh_art_of_glaive_devourer = false,
            stack_strip_segmented = true,
            protection_ignore_pain = true,
            protection_ignore_pain_time_bar = false,
            protection_ignore_pain_pandemic = true,
            survival_tip_of_the_spear = true,
            frost_icicles = true,
            guardian_ironfur = true,
            enhancement_maelstrom_weapon = true,
            enhancement_mw_threshold = false,
            rogue_coup_de_grace = true,
            rogue_coup_de_grace_color = {0.6, 0.8, 1.0, 1},
            discipline_radiance_charges = false,
            discipline_radiance_color = {0.85, 0.95, 0.55, 1},
            fire_blast_charges = true,
            paladin_swing_timer = false,
            paladin_swing_custom_color = false,
            paladin_swing_color = {1, 0.9, 0.5, 1},
            paladin_swing_overflow = true,
            paladin_swing_overflow_glow = true,
            paladin_divine_purpose = true,
            paladin_divine_purpose_color = {1.0, 0.85, 0.45, 1},
            evoker_essence_burst = true,
            evoker_essence_burst_color = {1.0, 0.85, 0.45, 1},
            evoker_essence_prediction = false,
            warlock_spend_prediction = true,
            warlock_shard_fragments = false,
            builder_prediction = true,
            builder_prediction_color = {0.6, 0.6, 0.6, 0.7},
            fire_blast_color = {1.0, 0.4, 0.0, 1},
            marksman_aimed_shot = true,
            marksman_lock_and_load = true,
            marksman_aimed_shot_color = {0.8, 0.5, 0.1, 1},
            marksman_lock_and_load_color = {0.2, 0.8, 1.0, 1},
            fury_whirlwind_color = {0.78, 0.61, 0.43, 1},
            arms_sweeping_strikes_color = {0.70, 0.30, 0.30, 1},
            protection_ignore_pain_color = {0.86, 0.68, 0.22, 1},
            survival_tots_color = {0.67, 0.83, 0.45, 1},
            frost_icicles_color = {0.47, 0.78, 1.0, 1},
            guardian_ironfur_color = {0.35, 0.55, 0.75, 1},
            enhancement_mw_color = {0.00, 0.44, 0.87, 1},
            enhancement_mw_threshold_color = {0.30, 0.70, 1.0, 1},
            resource_thresholds_global_enabled = true,
            resource_thresholds_enabled = {},  -- per-spec "CLASSFILENAME-specIndex" → bool; missing key = enabled
            resource_thresholds = {},
            stack_strip_threshold_glow = false,
            soul_frag_veng_color = {0.64, 0.19, 0.79, 1},
            soul_frag_dev_color = {0.64, 0.19, 0.79, 1},
            devourer_reap_forecast = true,
            devourer_reap_forecast_show_text = true,
            devourer_reap_preview_color = {1.0, 0.85, 0.2, 0.55},
            devourer_reap_ammo_color = {1.0, 0.9, 0.3, 1.0},
            devourer_reap_pip_color = {0.9, 0.9, 0.9, 0.9},
            stagger_color_light = {0.52, 1.0, 0.52, 1},
            stagger_color_moderate = {1.0, 0.98, 0.72, 1},
            stagger_color_heavy = {1.0, 0.42, 0.42, 1},
            vitality_color = {0.94, 0.76, 0.24, 1},
            mistweaver_teachings_color = {0.16, 0.80, 0.58, 1},
            mage_shatter_color = {0.45, 0.78, 0.95, 1},
            warlock_wild_imps_color = {0.55, 0.85, 0.35, 1},
            mage_arcane_salvo_color = {0.80, 0.52, 1.0, 1},
            evoker_unbound_flame_color = {0.93, 0.26, 0.10, 1},
            evoker_unbound_flame_expiry_color = {1.0, 0.82, 0.25, 1},
            dh_nearby_souls_color = {0.62, 0.92, 0.86, 1},
            dh_art_of_glaive_color = {0.85, 0.27, 0.32, 1},
            vigor_color = {0.10, 0.38, 0.72, 1},
            vigor_thrill_color = {0.35, 0.70, 1.0, 1},
            charged_combo_color = {0.0, 0.44, 0.87, 1},
            dk_blood_color = {0.77, 0.12, 0.23, 1},
            dk_frost_color = {0.45, 0.72, 0.95, 1},
            dk_unholy_color = {0.35, 0.80, 0.25, 1},
            skyriding_vigor = false,
            skyriding_show_speed = true,
            bar_spacing = 2,
            background_color = {0.2, 0.2, 0.2, 0.8},
            use_static_background = false,
            value_font = {
                font_face = "2002",
                font_size = 12,
                font_flags = "OUTLINE",
                shadow_color = {0, 0, 0, 1},
                shadow_offset_x = 1,
                shadow_offset_y = -1,
                font_color = {1, 1, 1, 1},
                anchor_point = "CENTER",
                offset_x = 0,
                offset_y = 0,
            },
            background = {
                enabled = false,
                color = {0, 0, 0, 0.6},
                padding = 4,
                rounded = false,
                roundness = 8,
                border_color = {0, 0, 0, 0.8},
            },
            anchor_profile = {
                frame_point = "top",
                parent_point = "center",
                relative_frame = "UIParent",
                xoff = 0,
                yoff = -185,
                anchor_parent = "CooldownTracker",
                anchor_side = "bottom",
                anchor_offset_x = 0,
                anchor_offset_y = -2,
                anchor_width_pct = 100,
                anchor_width_mode = "percent",
            },
        },
    },
}

private.defaultSettings = {
    profile = profile,
    global = {
        minimap = { hide = false },
        options_panel_scale = 0,
        spec_profile_sync = {
            enabled = false,
            default_profile = nil,
            spec_mappings = {},
            role_mappings = {},
        },
    },
}
