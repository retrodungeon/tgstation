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
#define BB_CREW_NPC_PICKUP_TARGET "crew_npc_pickup_target"

/datum/bt_node/ai_behavior/move_to_crew_npc_destination
	parent_type = /datum/bt_node/ai_behavior/move_to_target
	target_key = BB_CREW_NPC_DESTINATION
	required_dist = 0
	finish_on_arrival = TRUE

/datum/ai_movement/jps/crew_npc
	// Crew NPCs are station-scale actors. Keep this local rather than increasing
	// AI_MAX_PATH_LENGTH for every generic AI controller on the server.
	maximum_length = 300
	max_pathing_attempts = 20

/datum/bt_node/ai_behavior/crew_npc_pick_up_target
	parent_type = /datum/bt_node/ai_behavior/pick_up
	target_key = BB_CREW_NPC_PICKUP_TARGET
	drop_held = FALSE

/datum/ai_controller/crew_npc
	ai_movement = /datum/ai_movement/jps/crew_npc
	movement_delay = 0.2 SECONDS
	ai_traits = DEFAULT_AI_FLAGS | RUN_WHILE_UNWATCHED
	behavior_nodes = list(/datum/bt_node/ai_behavior/move_to_crew_npc_destination)

/datum/ai_controller/crew_npc/TryPossessPawn(atom/new_pawn)
	if(!ishuman(new_pawn))
		return AI_CONTROLLER_INCOMPATIBLE
	return ..()

/datum/ai_controller/crew_npc/proc/pick_up_target(obj/item/target)
	if(QDELETED(target) || !isturf(target.loc))
		return FALSE

	var/mob/living/living_pawn = pawn
	if(!istype(living_pawn))
		return FALSE

	set_blackboard_key(BB_CREW_NPC_PICKUP_TARGET, target)

	// A previous destination task may still own the movement datum even after
	// its move loop has finished. Explicitly release it before starting a new
	// item-retrieval movement target.
	cancel_current_plan()
	ai_movement.stop_moving_towards(src)

	INVOKE_ASYNC(src, PROC_REF(run_pickup_test), target)
	return TRUE

/datum/ai_controller/crew_npc/proc/run_pickup_test(obj/item/target)
	if(QDELETED(target) || QDELETED(pawn))
		return

	// First walk adjacent using the normal station-scale movement datum.
	var/datum/move_loop/pickup_loop = ai_movement.start_moving_towards(src, target, 1)
	if(!pickup_loop && get_dist(pawn, target) > 1)
		return

	var/timeout = world.time + 30 SECONDS
	while(!QDELETED(target) && !QDELETED(pawn) && get_dist(pawn, target) > 1 && world.time < timeout)
		stoplag(2)

	ai_movement.stop_moving_towards(src)

	if(QDELETED(target) || QDELETED(pawn) || get_dist(pawn, target) > 1)
		return

	var/mob/living/living_pawn = pawn
	if(living_pawn.get_active_held_item())
		return

	// ai_interact ultimately uses the human pawn's normal ClickOn path.
	ai_interact(target, FALSE)

/datum/ai_controller/crew_npc/proc/find_nearest_loose_item(item_type, search_range = 7)
	var/mob/living/living_pawn = pawn
	if(!istype(living_pawn))
		return null

	var/obj/item/best_target
	var/best_distance = INFINITY
	for(var/obj/item/candidate in oview(search_range, living_pawn))
		if(!istype(candidate, item_type) || !isturf(candidate.loc))
			continue
		var/distance = get_dist(living_pawn, candidate)
		if(distance < best_distance)
			best_target = candidate
			best_distance = distance

	return best_target

/datum/ai_controller/crew_npc/proc/find_and_pick_up(item_type, search_range = 7)
	var/obj/item/target = find_nearest_loose_item(item_type, search_range)
	if(!target)
		return null
	if(!pick_up_target(target))
		return null
	return target

/datum/ai_controller/crew_npc/proc/find_nearest_moppable_mess(search_range = 7)
	var/mob/living/living_pawn = pawn
	if(!istype(living_pawn))
		return null

	var/obj/effect/decal/cleanable/best_mess
	var/best_distance = INFINITY
	for(var/obj/effect/decal/cleanable/mess in oview(search_range, living_pawn))
		if(!mess.is_mopped)
			continue
		var/distance = get_dist(living_pawn, mess)
		if(distance < best_distance)
			best_mess = mess
			best_distance = distance

	return best_mess

/datum/ai_controller/crew_npc/proc/find_nearest_mop_bucket(search_range = 7)
	var/mob/living/living_pawn = pawn
	if(!istype(living_pawn))
		return null

	var/obj/structure/mop_bucket/best_bucket
	var/best_distance = INFINITY
	for(var/obj/structure/mop_bucket/bucket in oview(search_range, living_pawn))
		if(!bucket.reagents?.total_volume)
			continue
		var/distance = get_dist(living_pawn, bucket)
		if(distance < best_distance)
			best_bucket = bucket
			best_distance = distance

	return best_bucket

/datum/ai_controller/crew_npc/proc/get_held_mop()
	var/mob/living/living_pawn = pawn
	if(!istype(living_pawn))
		return null
	return locate(/obj/item/mop) in living_pawn.held_items

/datum/ai_controller/crew_npc/proc/start_janitor_work(search_range = 7)
	INVOKE_ASYNC(src, PROC_REF(run_janitor_work), search_range)
	return TRUE

/datum/ai_controller/crew_npc/proc/janitor_debug(message)
	var/mob/living/living_pawn = pawn
	var/where = living_pawn ? AREACOORD(living_pawn) : "no pawn"
	log_game("CREW NPC - [living_pawn ? living_pawn : "UNKNOWN"]: [message] @ [where]")

/datum/ai_controller/crew_npc/proc/run_janitor_work(search_range)
	var/mob/living/living_pawn = pawn
	if(!istype(living_pawn))
		janitor_debug("ABORT: pawn is not a living mob")
		return

	janitor_debug("START clean task; range=[search_range]")
	cancel_current_plan()
	ai_movement.stop_moving_towards(src)

	var/obj/item/mop/mop = get_held_mop()
	janitor_debug("held mop=[mop || "none"]")
	if(!mop)
		janitor_debug("searching for loose mop")
		mop = find_nearest_loose_item(/obj/item/mop, search_range)
		janitor_debug("mop search result=[mop || "none"]")
		if(!mop)
			living_pawn.balloon_alert(living_pawn, "can't find a mop!")
			return
		pick_up_target(mop)
		var/pickup_timeout = world.time + 30 SECONDS
		while(!QDELETED(mop) && mop.loc != living_pawn && world.time < pickup_timeout)
			stoplag(2)
		if(QDELETED(mop) || mop.loc != living_pawn)
			living_pawn.balloon_alert(living_pawn, "couldn't get the mop!")
			return

	// Pickup normally leaves the mop in the active hand. If it somehow did not,
	// select whichever hand actually contains it rather than blindly toggling.
	if(mop != living_pawn.get_active_held_item())
		var/mop_hand = living_pawn.get_held_index_of_item(mop)
		if(mop_hand)
			living_pawn.swap_hand(mop_hand)
	janitor_debug("mop active=[mop == living_pawn.get_active_held_item()]; volume=[mop.reagents?.total_volume]")
	if(mop != living_pawn.get_active_held_item())
		living_pawn.balloon_alert(living_pawn, "can't ready the mop!")
		return

	if(mop.reagents.total_volume < 0.1)
		janitor_debug("mop dry; searching for bucket")
		var/obj/structure/mop_bucket/bucket = find_nearest_mop_bucket(search_range)
		janitor_debug("bucket search result=[bucket || "none"]; volume=[bucket?.reagents?.total_volume]")
		if(!bucket)
			living_pawn.balloon_alert(living_pawn, "mop is dry; no water nearby!")
			return
		ai_movement.stop_moving_towards(src)
		ai_movement.start_moving_towards(src, bucket, 1)
		var/bucket_timeout = world.time + 30 SECONDS
		while(!QDELETED(bucket) && get_dist(living_pawn, bucket) > 1 && world.time < bucket_timeout)
			stoplag(2)
		ai_movement.stop_moving_towards(src)
		if(QDELETED(bucket) || get_dist(living_pawn, bucket) > 1)
			living_pawn.balloon_alert(living_pawn, "can't reach the water!")
			return
		janitor_debug("at bucket; attempting right-click interaction")
		ai_interact(bucket, FALSE, list(RIGHT_CLICK = TRUE))
		stoplag(2)
		janitor_debug("after bucket interaction; mop volume=[mop.reagents.total_volume]")
		if(mop.reagents.total_volume < 0.1)
			living_pawn.balloon_alert(living_pawn, "couldn't wet the mop!")
			return

	var/cleaned_count = 0
	while(cleaned_count < 10)
		janitor_debug("searching for moppable mess; cleaned=[cleaned_count]")
		var/obj/effect/decal/cleanable/mess = find_nearest_moppable_mess(search_range)
		janitor_debug("mess search result=[mess || "none"]; dist=[mess ? get_dist(living_pawn, mess) : -1]")
		if(!mess)
			if(!cleaned_count)
				living_pawn.balloon_alert(living_pawn, "nothing to clean nearby!")
			break

		var/turf/mess_turf = get_turf(mess)
		ai_movement.stop_moving_towards(src)
		var/datum/move_loop/mess_loop = ai_movement.start_moving_towards(src, mess_turf, 1)
		janitor_debug("mess movement started=[!!mess_loop]; target=[AREACOORD(mess_turf)]")
		if(!mess_loop && get_dist(living_pawn, mess_turf) > 1)
			janitor_debug("ABORT: failed to create movement loop to mess")
			living_pawn.balloon_alert(living_pawn, "can't start path to mess!")
			break
		var/mess_timeout = world.time + 30 SECONDS
		while(!QDELETED(mess) && get_dist(living_pawn, mess_turf) > 1 && world.time < mess_timeout)
			stoplag(2)
		janitor_debug("mess movement ended; dist=[QDELETED(mess) ? -1 : get_dist(living_pawn, mess_turf)]; timed_out=[world.time >= mess_timeout]")
		ai_movement.stop_moving_towards(src)
		if(QDELETED(mess))
			continue
		if(get_dist(living_pawn, mess_turf) > 1)
			living_pawn.balloon_alert(living_pawn, "can't reach the mess!")
			break

		// Clicking the turf with the active mop triggers the mop's real cleaner
		// component, including do_after, reagent use, washing, and skill effects.
		janitor_debug("at mess turf; attempting mop interaction")
		ai_interact(mess_turf, FALSE)
		var/clean_timeout = world.time + 5 SECONDS
		while(!QDELETED(mess) && world.time < clean_timeout)
			stoplag(2)
		if(!QDELETED(mess))
			living_pawn.balloon_alert(living_pawn, "couldn't clean that!")
			break

		cleaned_count++
		janitor_debug("clean succeeded; cleaned=[cleaned_count]; mop volume=[mop.reagents.total_volume]")
		if(mop.reagents.total_volume < 0.1)
			living_pawn.balloon_alert(living_pawn, "mop ran dry!")
			break

/datum/ai_controller/crew_npc/proc/drop_active_item()
	var/mob/living/living_pawn = pawn
	if(!istype(living_pawn))
		return FALSE
	var/obj/item/held_item = living_pawn.get_active_held_item()
	if(!held_item)
		return FALSE
	return living_pawn.dropItemToGround(held_item)

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
#undef BB_CREW_NPC_PICKUP_TARGET


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


/*
 * Milestone-1 navigation test helper.
 * Sends an existing Autonomous Crew janitor to the admin's current turf,
 * allowing long-distance, door, corner, and access-path testing.
 */
ADMIN_VERB(call_barry_johnson, R_ADMIN, "Call Barry Johnson", "Send an existing Autonomous Crew janitor prototype to your current location.", ADMIN_CATEGORY_DEBUG)
	var/mob/living/carbon/human/crew_npc/janitor/barry
	for(var/mob/living/carbon/human/crew_npc/janitor/candidate in GLOB.mob_list)
		barry = candidate
		break

	if(!barry)
		to_chat(user, span_warning("No Autonomous Crew janitor prototype currently exists."))
		return

	var/turf/destination = get_turf(user.mob)
	if(!destination)
		to_chat(user, span_warning("Unable to find a valid destination turf."))
		return

	var/datum/ai_controller/crew_npc/controller = barry.ai_controller
	if(!controller)
		to_chat(user, span_warning("[barry] does not have an Autonomous Crew AI controller."))
		return

	if(!controller.set_destination(destination))
		to_chat(user, span_warning("Unable to set [barry]'s destination."))
		return

	log_admin("[key_name(user)] called Autonomous Crew prototype [barry] to [AREACOORD(destination)].")
	message_admins("[key_name_admin(user)] called Autonomous Crew prototype [barry] to [ADMIN_VERBOSEJMP(destination)].")
	to_chat(user, span_notice("Sending [barry] to your current location."))


/*
 * Milestone 2: "Barry Has Hands" test helpers.
 * These select a real world item, make the Crew NPC physically walk to it,
 * and use the normal AI interaction path to pick it up.
 */
ADMIN_VERB(barry_pick_up_item, R_ADMIN, "Barry Pick Up Item", "Order the Autonomous Crew janitor prototype to pick up a world item.", ADMIN_CATEGORY_DEBUG)
	VERB_ARG_TYPED(target, VERB_ARG_TYPE_OBJ, VERB_ARG_SOURCE_WORLD, /obj/item)

	var/mob/living/carbon/human/crew_npc/janitor/barry
	for(var/mob/living/carbon/human/crew_npc/janitor/candidate in GLOB.mob_list)
		barry = candidate
		break

	if(!barry)
		to_chat(user, span_warning("No Autonomous Crew janitor prototype currently exists."))
		return
	if(!target || !isturf(target.loc))
		to_chat(user, span_warning("Select an item that is currently lying on a turf."))
		return

	var/datum/ai_controller/crew_npc/controller = barry.ai_controller
	if(!controller || !controller.pick_up_target(target))
		to_chat(user, span_warning("Unable to order [barry] to pick up [target]."))
		return

	to_chat(user, span_notice("Ordering [barry] to retrieve [target]."))

ADMIN_VERB(barry_drop_item, R_ADMIN, "Barry Drop Held Item", "Order the Autonomous Crew janitor prototype to drop the item in their active hand.", ADMIN_CATEGORY_DEBUG)
	var/mob/living/carbon/human/crew_npc/janitor/barry
	for(var/mob/living/carbon/human/crew_npc/janitor/candidate in GLOB.mob_list)
		barry = candidate
		break

	if(!barry)
		to_chat(user, span_warning("No Autonomous Crew janitor prototype currently exists."))
		return

	var/datum/ai_controller/crew_npc/controller = barry.ai_controller
	if(!controller || !controller.drop_active_item())
		to_chat(user, span_warning("[barry] has no droppable item in their active hand."))
		return

	to_chat(user, span_notice("[barry] drops their active held item."))


ADMIN_VERB(barry_find_mop, R_ADMIN, "Barry Find Mop", "Order the Autonomous Crew janitor prototype to find and retrieve a nearby loose mop.", ADMIN_CATEGORY_DEBUG)
	var/mob/living/carbon/human/crew_npc/janitor/barry
	for(var/mob/living/carbon/human/crew_npc/janitor/candidate in GLOB.mob_list)
		barry = candidate
		break

	if(!barry)
		to_chat(user, span_warning("No Autonomous Crew janitor prototype currently exists."))
		return

	var/datum/ai_controller/crew_npc/controller = barry.ai_controller
	if(!controller)
		to_chat(user, span_warning("[barry] does not have an Autonomous Crew AI controller."))
		return

	var/obj/item/mop/target = controller.find_and_pick_up(/obj/item/mop, 7)
	if(!target)
		to_chat(user, span_warning("[barry] could not find a loose mop within seven tiles."))
		return

	to_chat(user, span_notice("[barry] found [target] and is going to retrieve it."))


ADMIN_VERB(barry_clean_nearby, R_ADMIN, "Barry Clean Nearby", "Order the Autonomous Crew janitor prototype to acquire a mop, wet it if needed, and clean nearby moppable messes.", ADMIN_CATEGORY_DEBUG)
	var/mob/living/carbon/human/crew_npc/janitor/barry
	for(var/mob/living/carbon/human/crew_npc/janitor/candidate in GLOB.mob_list)
		barry = candidate
		break

	if(!barry)
		to_chat(user, span_warning("No Autonomous Crew janitor prototype currently exists."))
		return

	var/datum/ai_controller/crew_npc/controller = barry.ai_controller
	if(!controller)
		to_chat(user, span_warning("[barry] does not have an Autonomous Crew AI controller."))
		return

	controller.start_janitor_work(7)
	to_chat(user, span_notice("Ordering [barry] to begin janitorial work nearby."))
