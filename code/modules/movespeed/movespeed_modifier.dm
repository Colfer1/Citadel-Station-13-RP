/*! Movespeed modification datums.

	How move speed for mobs works

Move speed is now calculated by using modifier datums which are added to mobs. Some of them (nonvariable ones) are globally cached, the variable ones are instanced and changed based on need.

This gives us the ability to have multiple sources of movespeed, reliabily keep them applied and remove them when they should be

THey can have unique sources and a bunch of extra fancy flags that control behaviour

Previously trying to update move speed was a shot in the dark that usually meant mobs got stuck going faster or slower

Movespeed modification list is a simple key = datum system. Key will be the datum's ID if it is overridden to not be null, or type if it is not.

DO NOT override datum IDs unless you are going to have multiple types that must overwrite each other. It's more efficient to use types, ID functionality is only kept for cases where dynamic creation of modifiers need to be done.

When update movespeed is called, the list of items is iterated, according to flags priority and a bunch of conditions
this spits out a final calculated value which is used as a modifer to last_move + modifier for calculating when a mob
can next move

Key procs
* [add_movespeed_modifier](mob.html#proc/add_movespeed_modifier)
* [remove_movespeed_modifier](mob.html#proc/remove_movespeed_modifier)
* [has_movespeed_modifier](mob.html#proc/has_movespeed_modifier)
* [update_movespeed](mob.html#proc/update_movespeed)
*/

/datum/movespeed_modifier
	/// Whether or not this is a variable modifier. Variable modifiers can NOT be ever auto-cached. ONLY CHECKED VIA INITIAL(), EFFECTIVELY READ ONLY (and for very good reason)
	var/variable = FALSE

	/// Unique ID. You can never have different modifications with the same ID. By default, this SHOULD NOT be set. Only set it for cases where you're dynamically making modifiers/need to have two types overwrite each other. If unset, uses path (converted to text) as ID.
	var/id

	/// Determines order. Lower priorities are applied first.
	var/priority = MOVESPEED_PRIORITY_DEFAULT
	/// flags
	var/movespeed_modifier_flags = NONE

	/// calculation type
	var/calculation_type = MOVESPEED_CALCULATION_HYPERBOLIC

	//* HYPERBOLIC, HYPERBOLIC_BOOST calculations
	/// Multiplicative slowdown
	var/multiplicative_slowdown = 0

	//* MULTIPLY calculations
	/// multiply resulting speed by
	var/multiply_speed = 1

	//* HYPERBOLIC_BOOST, MULTIPLY calculations
	/// Absolute max tiles we can boost to
	var/absolute_max_tiles_per_second = INFINITY
	/// Max tiles per second we can boost
	var/max_tiles_per_second_boost = INFINITY

	/// Movetypes this applies to
	var/movement_type = ALL

	/// Movetypes this never applies to
	var/blacklisted_movetypes = NONE

	/// Other modification datums this conflicts with. Enum string.
	/// If there is, it prioritizes the highest slow *or* the highest speedup, with abs().
	var/conflicts_with

/datum/movespeed_modifier/New()
	. = ..()
	if(!id)
		id = "[type]" //We turn the path into a string.

/**
  * Returns new multiplicative movespeed after modification.
  *
  * The minimum move delay is always world.tick_lag. Attempting to go lower will result in the excess being cut.
  * This is so math doesn't break down when something attempts to break through the asymptote at 0 for move delay to speed.
  */
/datum/movespeed_modifier/proc/apply_multiplicative(existing, mob/target)
	// todo: we should max/min to ticklag rather than 0, but, we can't until everything is moved to modifiers.
	// todo: this is all shitty god we need to get rid of movement_delay() proper aaaa
	switch(calculation_type)
	/*
		if(MOVESPEED_CALCULATION_HYPERBOLIC)
			return max(world.tick_lag, existing + multiplicative_slowdown)
		if(MOVESPEED_CALCULATION_HYPERBOLIC_BOOST)
			var/current_tiles = 10 / max(existing, world.tick_lag)
			var/max_buff_to = max(existing + multiplicative_slowdown, 10 / absolute_max_tiles_per_second, 10 / (current_tiles + max_tiles_per_second_boost))
			return clamp(max_buff_to, world.tick_lag, existing)
		if(MOVESPEED_CALCULATION_MULTIPLY)
			var/current_tiles = 10 / max(world.tick_lag, existing)
			return 10 / (current_tiles * multiply_speed)
	*/
		if(MOVESPEED_CALCULATION_HYPERBOLIC)
			// going below 0 would fuck multipliers up pretty badly
			// return max(0, existing + multiplicative_slowdown)
			//! WE DO IT ANYWAYS - LEGACY
			return existing + multiplicative_slowdown
		if(MOVESPEED_CALCULATION_HYPERBOLIC_BOOST)
			var/current_tiles = 10 / max(existing, world.tick_lag)
			var/max_buff_to = max(existing + multiplicative_slowdown, 10 / absolute_max_tiles_per_second, 10 / (current_tiles + max_tiles_per_second_boost))
			return min(existing, max_buff_to)
		if(MOVESPEED_CALCULATION_MULTIPLY)
			if(existing > 0)
				var/current_tiles = 10 / existing
				return 10 / (current_tiles * multiply_speed)
			else
				var/current_tiles = 10 / config_legacy.run_speed
				return 10 / (current_tiles * multiply_speed)
		if(MOVESPEED_CALCULATION_LEGACY_MULTIPLY)
			target.cached_movespeed_multiply *= multiply_speed
			return existing
		else
			return existing

/**
 * applies from params
 */
/datum/movespeed_modifier/proc/parse(list/params)
	. = FALSE
	if(!isnull(params[MOVESPEED_PARAM_DELAY_MOD]))
		. = TRUE
		multiplicative_slowdown = params[MOVESPEED_PARAM_DELAY_MOD]
	if(!isnull(params[MOVESPEED_PARAM_MULTIPLY_SPEED]))
		. = TRUE
		multiply_speed = params[MOVESPEED_PARAM_MULTIPLY_SPEED]
	if(!isnull(params[MOVESPEED_PARAM_MAX_TILE_ABSOLUTE]))
		. = TRUE
		absolute_max_tiles_per_second = params[MOVESPEED_PARAM_MAX_TILE_ABSOLUTE]
	if(!isnull(params[MOVESPEED_PARAM_MAX_TILE_BOOST]))
		. = TRUE
		max_tiles_per_second_boost = params[MOVESPEED_PARAM_MAX_TILE_BOOST]

GLOBAL_LIST_EMPTY(movespeed_modification_cache)

/// Grabs a STATIC MODIFIER datum from cache. YOU MUST NEVER EDIT THESE DATUMS, OR IT WILL AFFECT ANYTHING ELSE USING IT TOO!
/proc/get_cached_movespeed_modifier(modtype)
	if(!ispath(modtype, /datum/movespeed_modifier))
		CRASH("[modtype] is not a movespeed modification typepath.")
	var/datum/movespeed_modifier/M = modtype
	if(initial(M.variable))
		CRASH("[modtype] is a variable modifier, and can never be cached.")
	M = GLOB.movespeed_modification_cache[modtype]
	if(!M)
		M = GLOB.movespeed_modification_cache[modtype] = new modtype
	return M

///Add a move speed modifier to a mob. If a variable subtype is passed in as the first argument, it will make a new datum. If ID conflicts, it will overwrite the old ID.
/mob/proc/add_movespeed_modifier(datum/movespeed_modifier/type_or_datum, update = TRUE)
	if(ispath(type_or_datum))
		if(!initial(type_or_datum.variable))
			type_or_datum = get_cached_movespeed_modifier(type_or_datum)
		else
			type_or_datum = new type_or_datum
	var/datum/movespeed_modifier/existing = LAZYACCESS(movespeed_modification, type_or_datum.id)
	if(existing)
		if(existing == type_or_datum)		//same thing don't need to touch
			return TRUE
		remove_movespeed_modifier(existing, FALSE)
	if(length(movespeed_modification))
		BINARY_INSERT(type_or_datum.id, movespeed_modification, /datum/movespeed_modifier, type_or_datum, priority, COMPARE_VALUE)
	LAZYSET(movespeed_modification, type_or_datum.id, type_or_datum)
	if(update)
		update_movespeed()
	return TRUE

/// Remove a move speed modifier from a mob, whether static or variable.
/mob/proc/remove_movespeed_modifier(datum/movespeed_modifier/type_id_datum, update = TRUE)
	var/key
	if(ispath(type_id_datum))
		key = initial(type_id_datum.id) || "[type_id_datum]"		//id if set, path set to string if not.
	else if(!istext(type_id_datum))		//if it isn't text it has to be a datum, as it isn't a type.
		key = type_id_datum.id
	else								//assume it's an id
		key = type_id_datum
	if(!LAZYACCESS(movespeed_modification, key))
		return FALSE
	LAZYREMOVE(movespeed_modification, key)
	if(update)
		update_movespeed(FALSE)
	return TRUE

/**
 * Used for variable slowdowns like hunger/health loss/etc, works somewhat like the old list-based modification adds. Returns the modifier datum if successful
 * How this SHOULD work is:
 * 1. Ensures type_id_datum one way or another refers to a /variable datum. This makes sure it can't be cached. This includes if it's already in the modification list.
 * 2. Instantiate a new datum if type_id_datum isn't already instantiated + in the list, using the type. Obviously, wouldn't work for ID only.
 * 3. Add the datum if necessary using the regular add proc
 * 4. If any of the rest of the args are not null (see: multiplicative slowdown), modify the datum
 * 5. Update if necessary
 */
/mob/proc/add_or_update_variable_movespeed_modifier(datum/movespeed_modifier/type_id_datum, update = TRUE, list/params)
	var/modified = FALSE
	var/inject = FALSE
	var/datum/movespeed_modifier/final
	if(istext(type_id_datum))
		final = LAZYACCESS(movespeed_modification, type_id_datum)
		if(!final)
			CRASH("Couldn't find existing modification when provided a text ID.")
	else if(ispath(type_id_datum))
		if(!initial(type_id_datum.variable))
			CRASH("Not a variable modifier")
		final = LAZYACCESS(movespeed_modification, initial(type_id_datum.id) || "[type_id_datum]")
		if(!final)
			final = new type_id_datum
			inject = TRUE
			modified = TRUE
	else
		if(!initial(type_id_datum.variable))
			CRASH("Not a variable modifier")
		final = type_id_datum
		if(!LAZYACCESS(movespeed_modification, final.id))
			inject = TRUE
			modified = TRUE
	if(final.parse(params))
		modified = TRUE
	if(inject)
		add_movespeed_modifier(final, FALSE)
	if(update && modified)
		update_movespeed(TRUE)
	return final

/// Handles the special case of editing the movement var
/mob/vv_edit_var(var_name, var_value)
	var/slowdown_edit = (var_name == NAMEOF(src, cached_multiplicative_slowdown))
	var/diff
	if(slowdown_edit && isnum(cached_multiplicative_slowdown) && isnum(var_value))
		remove_movespeed_modifier(/datum/movespeed_modifier/admin_varedit)
		diff = var_value - cached_multiplicative_slowdown
	. = ..()
	if(. && slowdown_edit && isnum(diff))
		add_or_update_variable_movespeed_modifier(/datum/movespeed_modifier/admin_varedit, params = list(MOVESPEED_PARAM_DELAY_MOD = diff))

///Is there a movespeed modifier for this mob
/mob/proc/has_movespeed_modifier(datum/movespeed_modifier/datum_type_id)
	var/key
	if(ispath(datum_type_id))
		key = initial(datum_type_id.id) || "[datum_type_id]"
	else if(istext(datum_type_id))
		key = datum_type_id
	else
		key = datum_type_id.id
	return LAZYACCESS(movespeed_modification, key)

/// Set or update the global movespeed config on a mob
/mob/proc/update_config_movespeed()
// todo: this
/*
	add_or_update_variable_movespeed_modifier(/datum/movespeed_modifier/mob_config_speedmod, multiplicative_slowdown = get_config_multiplicative_speed())
	add_or_update_variable_movespeed_modifier(/datum/movespeed_modifier/mob_config_speedmod_floating, multiplicative_slowdown = get_config_multiplicative_speed(TRUE))
*/

/// Get the global config movespeed of a mob by type
/mob/proc/get_config_multiplicative_speed(floating = FALSE)
// todo: refactor mobs to use movespeed mods
/*
	var/list/read = floating? GLOB.mob_config_movespeed_type_lookup_floating : GLOB.mob_config_movespeed_type_lookup
	if(!islist(read) || !read[type])
		return 0
	else
		return read[type]
*/
	return 0

/// Go through the list of movespeed modifiers and calculate a final movespeed. ANY ADD/REMOVE DONE IN UPDATE_MOVESPEED MUST HAVE THE UPDATE ARGUMENT SET AS FALSE!
/mob/proc/update_movespeed()
	. = 0
	var/list/conflict_tracker = list()
	//! TODO: LEGACY
	cached_movespeed_multiply = 1
	//! END
	for(var/datum/movespeed_modifier/M in get_movespeed_modifiers())
		if(!(M.movement_type & movement_type)) // We don't affect any of these move types, skip
			continue
		if(M.blacklisted_movetypes & movement_type) // There's a movetype here that disables this modifier, skip
			continue
		//! TODO: LEGACY - this should just check for floating
		if((M.movespeed_modifier_flags & MOVESPEED_MODIFIER_REQUIRES_GRAVITY) && !in_gravity)
			continue
		//! END
		var/conflict = M.conflicts_with
		var/amt = M.multiplicative_slowdown
		if(conflict)
			// Conflicting modifiers prioritize the larger slowdown or the larger speedup
			// We purposefuly don't handle mixing speedups and slowdowns on the same id
			if(abs(conflict_tracker[conflict]) < abs(amt))
				conflict_tracker[conflict] = amt
			else
				continue
		. = M.apply_multiplicative(., src)
	cached_multiplicative_slowdown = min(., 10 / MOVESPEED_ABSOLUTE_MINIMUM_TILES_PER_SECOND)
	if(!client)
		return
	var/diff = (last_move_time - move_delay) - cached_multiplicative_slowdown
	if(diff > 0)
		// your delay decreases, "give" the delay back to the client
		if(move_delay > world.time + 1.5)
			move_delay -= diff
#ifdef SMOOTH_MOVEMENT
		var/timeleft = world.time - move_delay
		var/elapsed = world.time - last_move_time
		var/glide_size_current = glide_size
		if((timeleft <= 0) || (elapsed > 20))
			SMOOTH_GLIDE_SIZE(src, 16, TRUE)
			return
		var/pixels_moved = glide_size_current * elapsed * (1 / world.tick_lag)
		// calculate glidesize needed to move to the next tile within timeleft deciseconds
		var/ticks_allowed = timeleft / world.tick_lag
		var/pixels_per_tick = pixels_moved / ticks_allowed
		SMOOTH_GLIDE_SIZE(src, pixels_per_tick * GLOB.glide_size_multiplier, TRUE)
#endif

/// Get the move speed modifier datums of this mob
/mob/proc/get_movespeed_modifiers()
	RETURN_TYPE(/list)
	. = list()
	for(var/id in movespeed_modification)
		if(id in movespeed_mod_immunities)
			continue
		. += movespeed_modification[id]

/// Get the movespeed modifier ids on this mob
/mob/proc/get_movespeed_modifier_ids()
	. = LAZYCOPY(movespeed_modification)
	for(var/id in movespeed_mod_immunities)
		. -= id

/// Calculate the total slowdown of all movespeed modifiers
/mob/proc/total_multiplicative_slowdown()
	. = 0
	for(var/id in get_movespeed_modifiers())
		var/datum/movespeed_modifier/M = movespeed_modification[id]
		. += M.multiplicative_slowdown

/**
  * Gets the movespeed modifier datum of a modifier on a mob. Returns null if not found.
  * DANGER: IT IS UP TO THE PERSON USING THIS TO MAKE SURE THE MODIFIER IS NOT MODIFIED IF IT HAPPENS TO BE GLOBAL/CACHED.
  */
/mob/proc/get_movespeed_modifier_datum(id)
	return movespeed_modification[id]

/// Checks if a move speed modifier is valid and not missing any data
/proc/movespeed_data_null_check(datum/movespeed_modifier/M)		//Determines if a data list is not meaningful and should be discarded.
	. = TRUE
	if(M.multiplicative_slowdown)
		. = FALSE
