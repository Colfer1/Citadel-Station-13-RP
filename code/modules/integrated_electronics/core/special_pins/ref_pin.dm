// These pins only contain weakrefs or null.
/datum/integrated_io/ref
	name = "ref pin"

/datum/integrated_io/ref/ask_for_pin_data(mob/user) // This clears the pin.
	write_data_to_pin(null)

/datum/integrated_io/ref/write_data_to_pin(datum/new_data)
	if(isnull(new_data))
		data = new_data
		holder.on_data_written()
	else if(istype(new_data))
		data = WEAKREF(new_data)
		holder.on_data_written()

/datum/integrated_io/ref/display_pin_type()
	return IC_FORMAT_REF

/datum/integrated_io/ref/connect_pin(datum/integrated_io/pin)
	..(pin)
	if(istype(pin,/datum/integrated_io/selfref))
		write_data_to_pin(pin.data)

/datum/integrated_io/ref/disconnect_pin(datum/integrated_io/pin)
	..(pin)
	if(istype(pin,/datum/integrated_io/selfref))
		write_data_to_pin(null)
