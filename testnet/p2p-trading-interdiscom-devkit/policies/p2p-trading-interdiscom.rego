package deg.policy

import rego.v1

# P2P Energy Trading – Delivery, Validity & Meter Policy
#
# Rules enforced:
#
# 1. Delivery lead time: delivery window start must be at least
#    minDeliveryLeadHours after the trade timestamp (context.timestamp).
#
# 2. Validity-to-delivery gap: validity window end must be at least
#    minDeliveryLeadHours before delivery window start, ensuring the
#    offer is no longer valid well before energy must flow.
#
# 3. Delivery slot duration: delivery window must be exactly 1 hour
#    (standard time-block for P2P energy settlement).
#
# 4. Meter ID validation:
#    a. Buyer meterId must not be empty.
#    b. Buyer meterId must differ from each order item's provider meterId
#       (a prosumer cannot trade with themselves).
#
# 5. Production network test-ID guard: when productionNetworkId is configured,
#    reject placeholder meter IDs (TEST_BUYER_METER / TEST_SELLER_METER).
#
# 6. Quantity bounds: beckn:quantity.unitQuantity must be >= 0 and strictly
#    less than the offer's applicableQuantity.unitQuantity.
#
# 7. Currency: schema:priceCurrency must be "INR".
#
# 8. Quantity unit: beckn:quantity.unitText must be "kWh".
#
# 9. EnergyCustomer required fields: utilityCustomerId and utilityId must be
#    present and non-empty on both buyer and provider.
#
# 10. EnergyCustomer @type: beckn:buyerAttributes.@type and
#     providerAttributes.@type must be "EnergyCustomer".
#
# 11. Sandbox enforcement: when networkId is configured and differs from
#     productionNetworkId, require test identifiers: TEST_BUYER_METER,
#     TEST_SELLER_METER, TEST_BUYER_DISCOM, TEST_SELLER_DISCOM.
#
# 12. Production DISCOM whitelist: when on the production network, utilityId
#     (buyer and provider) must be one of: TPDDL, PVVNL, BRPL.
#
# 13. Domain: context.domain must be "beckn.one:deg:p2p-trading-interdiscom:2.0.0".
#
# 14. Version: context.version must be "2.0.0".
#
# Config:
#   data.config.minDeliveryLeadHours  - minimum hours of lead time (default: 4)
#   data.config.productionNetworkId   - if set, enables Rule 5
#   data.config.networkId             - current network ID; enables Rules 11 & 12
#                                       when combined with productionNetworkId

default min_lead_hours := 4

min_lead_hours := to_number(data.config.minDeliveryLeadHours) if {
	data.config.minDeliveryLeadHours
}

ns_per_hour := 1000 * 1000 * 1000 * 60 * 60

# Parse the trade timestamp from context
trade_time := time.parse_rfc3339_ns(input.context.timestamp)

# Helper: resolve delivery window from either field name convention
_delivery_window(offer_attrs) := object.get(offer_attrs, "deliveryWindow", object.get(offer_attrs, "beckn:timeWindow", null))

# Helper: resolve validity window from either field name convention
_validity_window(offer_attrs) := object.get(offer_attrs, "validityWindow", object.get(offer_attrs, "beckn:validityWindow", null))

# Rule 13 – Domain must match the P2P inter-DISCOM trading profile
_required_domain := "beckn.one:deg:p2p-trading-interdiscom:2.0.0"

violations contains msg if {
	input.context.domain
	input.context.domain != _required_domain

	msg := sprintf(
		"context.domain is %q; must be %q",
		[input.context.domain, _required_domain],
	)
}

violations contains msg if {
	not input.context.domain

	msg := sprintf(
		"context.domain is missing; must be %q",
		[_required_domain],
	)
}

# Rule 14 – Version must be 2.0.0
_required_version := "2.0.0"

violations contains msg if {
	input.context.version
	input.context.version != _required_version

	msg := sprintf(
		"context.version is %q; must be %q",
		[input.context.version, _required_version],
	)
}

violations contains msg if {
	not input.context.version

	msg := sprintf(
		"context.version is missing; must be %q",
		[_required_version],
	)
}

# Rule 1 – Delivery lead time
violations contains msg if {
	item := input.message.order["beckn:orderItems"][i]
	offer_attrs := item["beckn:acceptedOffer"]["beckn:offerAttributes"]

	dw := _delivery_window(offer_attrs)
	dw != null

	start_str := dw["schema:startTime"]
	delivery_start := time.parse_rfc3339_ns(start_str)

	lead_hours := (delivery_start - trade_time) / ns_per_hour
	lead_hours < min_lead_hours

	msg := sprintf(
		"order item [%d]: delivery window start (%s) is only %v hours after trade time (%s); minimum is %v hours",
		[i, start_str, lead_hours, input.context.timestamp, min_lead_hours],
	)
}

# Rule 2 – Validity window must end at least minDeliveryLeadHours before delivery start
violations contains msg if {
	item := input.message.order["beckn:orderItems"][i]
	offer_attrs := item["beckn:acceptedOffer"]["beckn:offerAttributes"]

	dw := _delivery_window(offer_attrs)
	dw != null
	vw := _validity_window(offer_attrs)
	vw != null

	delivery_start := time.parse_rfc3339_ns(dw["schema:startTime"])
	validity_end_str := vw["schema:endTime"]
	validity_end := time.parse_rfc3339_ns(validity_end_str)

	gap_hours := (delivery_start - validity_end) / ns_per_hour
	gap_hours < min_lead_hours

	msg := sprintf(
		"order item [%d]: validity window end (%s) is only %v hours before delivery start; minimum gap is %v hours",
		[i, validity_end_str, gap_hours, min_lead_hours],
	)
}

# Rule 3 – Delivery window must be exactly 1 hour
violations contains msg if {
	item := input.message.order["beckn:orderItems"][i]
	offer_attrs := item["beckn:acceptedOffer"]["beckn:offerAttributes"]

	dw := _delivery_window(offer_attrs)
	dw != null

	start_str := dw["schema:startTime"]
	end_str := dw["schema:endTime"]
	duration_hours := (time.parse_rfc3339_ns(end_str) - time.parse_rfc3339_ns(start_str)) / ns_per_hour

	duration_hours != 1

	msg := sprintf(
		"order item [%d]: delivery window (%s to %s) is %v hours; must be exactly 1 hour",
		[i, start_str, end_str, duration_hours],
	)
}

# Helper: extract buyer meterId
_buyer_meter_id := input.message.order["beckn:buyer"]["beckn:buyerAttributes"].meterId

# Rule 4a – Buyer meterId must not be empty
violations contains "buyer meterId is missing or empty" if {
	not _buyer_meter_id
}

violations contains "buyer meterId is missing or empty" if {
	_buyer_meter_id == ""
}

# Rule 4b – Buyer meterId must differ from provider meterId on each order item
violations contains msg if {
	buyer_mid := _buyer_meter_id
	buyer_mid != ""

	item := input.message.order["beckn:orderItems"][i]
	provider_mid := item["beckn:orderItemAttributes"].providerAttributes.meterId

	buyer_mid == provider_mid

	msg := sprintf(
		"order item [%d]: buyer meterId (%s) is the same as provider meterId; a prosumer cannot trade with themselves",
		[i, buyer_mid],
	)
}

# Rule 5 – Reject placeholder test meter IDs on the production/pilot network
# Only active when data.config.productionNetworkId is set and not on a sandbox network.

violations contains msg if {
	data.config.productionNetworkId
	not _is_sandbox

	buyer_mid := _buyer_meter_id
	buyer_mid == "TEST_BUYER_METER"

	msg := sprintf(
		"buyer meterId is the placeholder TEST_BUYER_METER; not allowed on network %s",
		[data.config.productionNetworkId],
	)
}

violations contains msg if {
	data.config.productionNetworkId
	not _is_sandbox

	item := input.message.order["beckn:orderItems"][i]
	provider_mid := item["beckn:orderItemAttributes"].providerAttributes.meterId
	provider_mid == "TEST_SELLER_METER"

	msg := sprintf(
		"order item [%d]: provider meterId is the placeholder TEST_SELLER_METER; not allowed on network %s",
		[i, data.config.productionNetworkId],
	)
}

# Rule 6a – Ordered quantity must be >= 0
violations contains msg if {
	item := input.message.order["beckn:orderItems"][i]
	qty := item["beckn:quantity"].unitQuantity
	qty < 0

	msg := sprintf(
		"order item [%d]: beckn:quantity.unitQuantity is %v; must be >= 0",
		[i, qty],
	)
}

# Rule 6b – Ordered quantity must be < applicableQuantity (offer cap)
violations contains msg if {
	item := input.message.order["beckn:orderItems"][i]
	qty := item["beckn:quantity"].unitQuantity
	cap := item["beckn:acceptedOffer"]["beckn:price"].applicableQuantity.unitQuantity
	qty >= cap

	msg := sprintf(
		"order item [%d]: beckn:quantity.unitQuantity (%v) must be less than applicableQuantity (%v)",
		[i, qty, cap],
	)
}

# Rule 7 – Currency must be INR
violations contains msg if {
	item := input.message.order["beckn:orderItems"][i]
	currency := item["beckn:acceptedOffer"]["beckn:price"]["schema:priceCurrency"]
	currency != "INR"

	msg := sprintf(
		"order item [%d]: schema:priceCurrency is %q; must be INR",
		[i, currency],
	)
}

# Rule 8 – Quantity unit must be kWh
violations contains msg if {
	item := input.message.order["beckn:orderItems"][i]
	unit := item["beckn:quantity"].unitText
	unit != "kWh"

	msg := sprintf(
		"order item [%d]: beckn:quantity.unitText is %q; must be kWh",
		[i, unit],
	)
}

# Rule 9a – Buyer utilityCustomerId must be present and non-empty
_buyer_utility_cust_id := input.message.order["beckn:buyer"]["beckn:buyerAttributes"].utilityCustomerId

violations contains "buyer utilityCustomerId is missing or empty" if {
	not _buyer_utility_cust_id
}

violations contains "buyer utilityCustomerId is missing or empty" if {
	_buyer_utility_cust_id == ""
}

# Rule 9b – Provider utilityCustomerId must be present and non-empty per order item
violations contains msg if {
	item := input.message.order["beckn:orderItems"][i]
	provider := item["beckn:orderItemAttributes"].providerAttributes
	not provider.utilityCustomerId

	msg := sprintf(
		"order item [%d]: provider utilityCustomerId is missing",
		[i],
	)
}

violations contains msg if {
	item := input.message.order["beckn:orderItems"][i]
	provider := item["beckn:orderItemAttributes"].providerAttributes
	provider.utilityCustomerId == ""

	msg := sprintf(
		"order item [%d]: provider utilityCustomerId is empty",
		[i],
	)
}

# Rule 9c – Buyer utilityId must be present and non-empty
_buyer_utility_id := input.message.order["beckn:buyer"]["beckn:buyerAttributes"].utilityId

violations contains "buyer utilityId is missing or empty" if {
	not _buyer_utility_id
}

violations contains "buyer utilityId is missing or empty" if {
	_buyer_utility_id == ""
}

# Rule 9d – Provider utilityId must be present and non-empty per order item
violations contains msg if {
	item := input.message.order["beckn:orderItems"][i]
	provider := item["beckn:orderItemAttributes"].providerAttributes
	not provider.utilityId

	msg := sprintf(
		"order item [%d]: provider utilityId is missing",
		[i],
	)
}

violations contains msg if {
	item := input.message.order["beckn:orderItems"][i]
	provider := item["beckn:orderItemAttributes"].providerAttributes
	provider.utilityId == ""

	msg := sprintf(
		"order item [%d]: provider utilityId is empty",
		[i],
	)
}

# Rule 10a – Buyer attributes @type must be "EnergyCustomer"
_buyer_type := input.message.order["beckn:buyer"]["beckn:buyerAttributes"]["@type"]

violations contains "buyer beckn:buyerAttributes @type is missing; must be EnergyCustomer" if {
	not _buyer_type
}

violations contains msg if {
	_buyer_type
	_buyer_type != "EnergyCustomer"

	msg := sprintf(
		"buyer beckn:buyerAttributes @type is %q; must be EnergyCustomer",
		[_buyer_type],
	)
}

# Rule 10b – Provider attributes @type must be "EnergyCustomer" per order item
violations contains msg if {
	item := input.message.order["beckn:orderItems"][i]
	provider := item["beckn:orderItemAttributes"].providerAttributes
	not provider["@type"]

	msg := sprintf(
		"order item [%d]: providerAttributes @type is missing; must be EnergyCustomer",
		[i],
	)
}

violations contains msg if {
	item := input.message.order["beckn:orderItems"][i]
	provider := item["beckn:orderItemAttributes"].providerAttributes
	provider["@type"]
	provider["@type"] != "EnergyCustomer"

	msg := sprintf(
		"order item [%d]: providerAttributes @type is %q; must be EnergyCustomer",
		[i, provider["@type"]],
	)
}

# ===== Network-aware rules =====
#
# Rules 11 and 12 activate only when BOTH data.config.networkId and
# data.config.productionNetworkId are configured. networkId identifies
# the current network; productionNetworkId is the reference production ID.

# Approved DISCOMs for production network (extend this list as needed)
_allowed_utility_ids := {"TPDDL", "PVVNL", "BRPL"}

# Helper: true when running on the production network
_is_production if {
	data.config.networkId
	data.config.productionNetworkId
	data.config.networkId == data.config.productionNetworkId
}

# Helper: true when running on a non-production (sandbox/test) network
_is_sandbox if {
	data.config.networkId
	data.config.productionNetworkId
	data.config.networkId != data.config.productionNetworkId
}

# Rule 11a — Sandbox: buyer meterId must be TEST_BUYER_METER
violations contains msg if {
	_is_sandbox
	buyer_mid := _buyer_meter_id
	buyer_mid != "TEST_BUYER_METER"

	msg := sprintf(
		"sandbox network: buyer meterId is %q; must be TEST_BUYER_METER",
		[buyer_mid],
	)
}

# Rule 11b — Sandbox: provider meterId must be TEST_SELLER_METER per order item
violations contains msg if {
	_is_sandbox
	item := input.message.order["beckn:orderItems"][i]
	provider_mid := item["beckn:orderItemAttributes"].providerAttributes.meterId
	provider_mid != "TEST_SELLER_METER"

	msg := sprintf(
		"order item [%d]: sandbox network: provider meterId is %q; must be TEST_SELLER_METER",
		[i, provider_mid],
	)
}

# Rule 11c — Sandbox: buyer utilityId must be TEST_BUYER_DISCOM
violations contains msg if {
	_is_sandbox
	buyer_uid := _buyer_utility_id
	buyer_uid != "TEST_BUYER_DISCOM"

	msg := sprintf(
		"sandbox network: buyer utilityId is %q; must be TEST_BUYER_DISCOM",
		[buyer_uid],
	)
}

# Rule 11d — Sandbox: provider utilityId must be TEST_SELLER_DISCOM per order item
violations contains msg if {
	_is_sandbox
	item := input.message.order["beckn:orderItems"][i]
	provider := item["beckn:orderItemAttributes"].providerAttributes
	provider.utilityId != "TEST_SELLER_DISCOM"

	msg := sprintf(
		"order item [%d]: sandbox network: provider utilityId is %q; must be TEST_SELLER_DISCOM",
		[i, provider.utilityId],
	)
}

# Rule 12a — Production: buyer utilityId must be an approved DISCOM
violations contains msg if {
	_is_production
	buyer_uid := _buyer_utility_id
	buyer_uid != ""
	not buyer_uid in _allowed_utility_ids

	msg := sprintf(
		"production network: buyer utilityId %q is not an approved DISCOM; must be one of %v",
		[buyer_uid, _allowed_utility_ids],
	)
}

# Rule 12b — Production: provider utilityId must be an approved DISCOM per order item
violations contains msg if {
	_is_production
	item := input.message.order["beckn:orderItems"][i]
	provider := item["beckn:orderItemAttributes"].providerAttributes
	provider.utilityId != ""
	not provider.utilityId in _allowed_utility_ids

	msg := sprintf(
		"order item [%d]: production network: provider utilityId %q is not an approved DISCOM; must be one of %v",
		[i, provider.utilityId, _allowed_utility_ids],
	)
}
