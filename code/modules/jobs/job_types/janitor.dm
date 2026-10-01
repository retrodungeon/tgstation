/datum/job/janitor
	title = JOB_JANITOR
	description = "Clean up trash and blood, replace broken lights, slip people over."
	faction = FACTION_STATION
	total_positions = 2
	spawn_positions = 1
	supervisors = SUPERVISOR_HOP
	exp_granted_type = EXP_TYPE_CREW
	config_tag = "JANITOR"

	outfit = /datum/outfit/job/janitor
	plasmaman_outfit = /datum/outfit/plasmaman/janitor

	paycheck = PAYCHECK_CREW
	paycheck_department = ACCOUNT_SRV

	display_order = JOB_DISPLAY_ORDER_JANITOR
	departments_list = list(
		/datum/job_department/service,
		)

	family_heirlooms = list(/obj/item/mop, /obj/item/clothing/suit/caution, /obj/item/reagent_containers/cup/bucket, /obj/item/paper/fluff/stations/soap)

	mail_goodies = list(
		/obj/item/grenade/chem_grenade/cleaner = 30,
		/obj/item/storage/box/lights/mixed = 20,
		/obj/item/lightreplacer = 10
	)
	rpg_title = "Groundskeeper"
	job_flags = STATION_JOB_FLAGS

	job_tone = "slip"

/datum/outfit/job/janitor
	name = "Janitor"
	jobtype = /datum/job/janitor

	id_trim = /datum/id_trim/job/janitor
	uniform = /obj/item/clothing/under/rank/civilian/janitor
	belt = /obj/item/modular_computer/pda/janitor
	ears = /obj/item/radio/headset/headset_srv
	skillchips = list(/obj/item/skillchip/job/janitor, /obj/item/skillchip/disposals)
	backpack_contents = list(/obj/item/access_key)

	wintercoat = /obj/item/clothing/suit/hooded/wintercoat/janitor

/datum/outfit/job/janitor/pre_equip(mob/living/carbon/human/human_equipper, visuals_only)
	. = ..()
	if(check_holidays(GARBAGEDAY))
		backpack_contents += list(/obj/item/gun/ballistic/revolver)
		r_pocket = /obj/item/ammo_box/speedloader/c357

/datum/outfit/job/janitor/get_types_to_preload()
	. = ..()
	if(check_holidays(GARBAGEDAY))
		. += /obj/item/gun/ballistic/revolver
		. += /obj/item/ammo_box/speedloader/c357


/*
 * Autonomous Crew prototype
 *
 * Milestone 1: "Barry Walks"
 *
 * This intentionally lives in the already-included janitor job file while the
 * prototype is being validated. Once the controller is proven, move it into a
 * dedicated crew_npc module.
 */

#define BB_CREW_NPC_DESTINATION "crew_npc_destination"

/datum/bt_node/ai_behavior/move_to_crew_npc_destination
	parent_type = /datum/bt_node/ai_behavior/move_to_target
	target_key = BB_CREW_NPC_DESTINATION
	required_dist = 0
	finish_on_arrival = TRUE

/datum/ai_controller/crew_npc
	ai_movement = /datum/ai_movement/jps
	movement_delay = 0.2 SECONDS
	ai_traits = DEFAULT_AI_FLAGS | RUN_WHILE_UNWATCHED
	behavior_nodes = list(/datum/bt_node/ai_behavior/move_to_crew_npc_destination)

/datum/ai_controller/crew_npc/TryPossessPawn(atom/new_pawn)
	if(!ishuman(new_pawn))
		return AI_CONTROLLER_INCOMPATIBLE
	return ..()

/datum/ai_controller/crew_npc/proc/set_destination(atom/new_destination)
	if(QDELETED(new_destination))
		clear_blackboard_key(BB_CREW_NPC_DESTINATION)
		cancel_current_plan()
		return FALSE

	set_blackboard_key(BB_CREW_NPC_DESTINATION, new_destination)
	cancel_current_plan()
	return TRUE

/mob/living/carbon/human/crew_npc/janitor
	name = "Barry Johnson"
	real_name = "Barry Johnson"

/mob/living/carbon/human/crew_npc/janitor/Initialize(mapload, datum/species/species)
	. = ..()

	equipOutfit(/datum/outfit/job/janitor)

	var/datum/ai_controller/crew_npc/controller = new(src)

	// Temporary Milestone-1 diagnostic destination. Barry attempts to travel
	// seven tiles east immediately after being admin-spawned.
	var/turf/debug_destination = get_ranged_target_turf(src, EAST, 7)
	if(debug_destination)
		controller.set_destination(debug_destination)

#undef BB_CREW_NPC_DESTINATION


/*
 * Temporary admin verb for Autonomous Crew prototype testing.
 * Spawns Barry on the admin's current turf without relying on Spawn Panel indexing.
 */
ADMIN_VERB(spawn_barry_johnson, R_ADMIN, "Spawn Barry Johnson", "Spawn the Autonomous Crew janitor prototype at your current location.", ADMIN_CATEGORY_DEBUG)
	var/turf/spawn_turf = get_turf(user.mob)
	if(!spawn_turf)
		to_chat(user, span_warning("Unable to find a valid turf to spawn Barry on."))
		return

	var/mob/living/carbon/human/crew_npc/janitor/barry = new(spawn_turf)
	log_admin("[key_name(user)] spawned Autonomous Crew prototype [barry] at [AREACOORD(spawn_turf)].")
	message_admins("[key_name_admin(user)] spawned Autonomous Crew prototype [barry] at [ADMIN_VERBOSEJMP(spawn_turf)].")
