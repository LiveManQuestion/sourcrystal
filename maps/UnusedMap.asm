; Shared by the UNUSED_*_MAP placeholder maps (see constants/map_constants.asm).
; Nothing warps here.

UnusedMap_MapScripts:
	def_scene_scripts

	def_callbacks

UnusedMap_MapEvents:
	db 0, 0 ; filler

	def_warp_events

	def_coord_events

	def_bg_events

	def_object_events
