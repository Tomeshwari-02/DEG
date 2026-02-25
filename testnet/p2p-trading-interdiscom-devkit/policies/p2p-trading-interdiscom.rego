package deg.policy

import rego.v1

# P2P Energy Trading – Delivery, Validity & Meter Policy
#
# Action-gated rules: the policy checks input.context.action to decide
# which rules apply.
#
# ── confirm action (order validation) ──
#
# 1. Delivery lead time: delivery window start must be at least
#    minDeliveryLeadHours after the trade timestamp (context.timestamp).
#
# 2. Validity-to-delivery gap: validity window end must be at least
#    minDeliveryLeadHours before delivery window start.
#
# 3. Delivery slot duration: delivery window must be exactly 1 hour.
#
# 4. Meter ID validation:
#    a. Buyer meterId must not be empty.
#    b. Buyer meterId must differ from each order item's provider meterId.
#
# 5. Quantity bounds: beckn:quantity.unitQuantity must be >= 0 and strictly
#    less than the offer's applicableQuantity.unitQuantity.
#
# 6. Currency: schema:priceCurrency must be "INR".
#
# 7. Quantity unit: beckn:quantity.unitText must be "kWh".
#
# 8. EnergyCustomer required fields: utilityCustomerId and utilityId must be
#    present and non-empty on both buyer and provider.
#
# 9. EnergyCustomer @type: beckn:buyerAttributes.@type and
#    providerAttributes.@type must be "EnergyCustomer".
#
# 10. Domain: context.domain must be "beckn.one:deg:p2p-trading-interdiscom:2.0.0".
#
# 11. Version: context.version must be "2.0.0".
#
# 12. EnergyCustomer @context: when @type is "EnergyCustomer", @context must
#     match the P2P energy trading JSON-LD context URL.
#
# 13. EnergyTradeOrder @context: when order @type is "EnergyTradeOrder",
#     @context must match the same URL.
#
# 14. EnergyTradeOffer @context: when offer @type is "EnergyTradeOffer",
#     @context must match the same URL.
#
# ── publish action (catalog item validation) ──
#
# P1. Production network items: providerAttributes must exist, utilityId must
#     be an approved DISCOM (TPDDL, PVVNL, BRPL).
# P2. Non-production network items: provider meterId must be TEST_METER_SELLER,
#     provider utilityId must be TEST_DISCOM_SELLER.
#
# ── non-publish actions (test ID consistency) ──
#
# T1. If any provider uses test identifiers (meterId or utilityId starting
#     with "TEST_"), the buyer must also use test values:
#     TEST_METER_BUYER and TEST_DISCOM_BUYER.
#
# Config:
#   data.config.minDeliveryLeadHours  - minimum hours of lead time (default: 4)

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

_confirm_violations contains msg if {
	input.context.domain
	input.context.domain != _required_domain

	msg := sprintf(
		"context.domain is %q; must be %q",
		[input.context.domain, _required_domain],
	)
}

_confirm_violations contains msg if {
	not input.context.domain

	msg := sprintf(
		"context.domain is missing; must be %q",
		[_required_domain],
	)
}

# Rule 14 – Version must be 2.0.0
_required_version := "2.0.0"

_confirm_violations contains msg if {
	input.context.version
	input.context.version != _required_version

	msg := sprintf(
		"context.version is %q; must be %q",
		[input.context.version, _required_version],
	)
}

_confirm_violations contains msg if {
	not input.context.version

	msg := sprintf(
		"context.version is missing; must be %q",
		[_required_version],
	)
}

# Rule 1 – Delivery lead time
_confirm_violations contains msg if {
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
_confirm_violations contains msg if {
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
_confirm_violations contains msg if {
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
_confirm_violations contains "buyer meterId is missing or empty" if {
	not _buyer_meter_id
}

_confirm_violations contains "buyer meterId is missing or empty" if {
	_buyer_meter_id == ""
}

# Rule 4b – Buyer meterId must differ from provider meterId on each order item
_confirm_violations contains msg if {
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


# Rule 6a – Ordered quantity must be >= 0
_confirm_violations contains msg if {
	item := input.message.order["beckn:orderItems"][i]
	qty := item["beckn:quantity"].unitQuantity
	qty < 0

	msg := sprintf(
		"order item [%d]: beckn:quantity.unitQuantity is %v; must be >= 0",
		[i, qty],
	)
}

# Rule 6b – Ordered quantity must be < applicableQuantity (offer cap)
_confirm_violations contains msg if {
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
_confirm_violations contains msg if {
	item := input.message.order["beckn:orderItems"][i]
	currency := item["beckn:acceptedOffer"]["beckn:price"]["schema:priceCurrency"]
	currency != "INR"

	msg := sprintf(
		"order item [%d]: schema:priceCurrency is %q; must be INR",
		[i, currency],
	)
}

# Rule 8 – Quantity unit must be kWh
_confirm_violations contains msg if {
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

_confirm_violations contains "buyer utilityCustomerId is missing or empty" if {
	not _buyer_utility_cust_id
}

_confirm_violations contains "buyer utilityCustomerId is missing or empty" if {
	_buyer_utility_cust_id == ""
}

# Rule 9b – Provider utilityCustomerId must be present and non-empty per order item
_confirm_violations contains msg if {
	item := input.message.order["beckn:orderItems"][i]
	provider := item["beckn:orderItemAttributes"].providerAttributes
	not provider.utilityCustomerId

	msg := sprintf(
		"order item [%d]: provider utilityCustomerId is missing",
		[i],
	)
}

_confirm_violations contains msg if {
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

_confirm_violations contains "buyer utilityId is missing or empty" if {
	not _buyer_utility_id
}

_confirm_violations contains "buyer utilityId is missing or empty" if {
	_buyer_utility_id == ""
}

# Rule 9d – Provider utilityId must be present and non-empty per order item
_confirm_violations contains msg if {
	item := input.message.order["beckn:orderItems"][i]
	provider := item["beckn:orderItemAttributes"].providerAttributes
	not provider.utilityId

	msg := sprintf(
		"order item [%d]: provider utilityId is missing",
		[i],
	)
}

_confirm_violations contains msg if {
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

_confirm_violations contains "buyer beckn:buyerAttributes @type is missing; must be EnergyCustomer" if {
	not _buyer_type
}

_confirm_violations contains msg if {
	_buyer_type
	_buyer_type != "EnergyCustomer"

	msg := sprintf(
		"buyer beckn:buyerAttributes @type is %q; must be EnergyCustomer",
		[_buyer_type],
	)
}

# Rule 10b – Provider attributes @type must be "EnergyCustomer" per order item
_confirm_violations contains msg if {
	item := input.message.order["beckn:orderItems"][i]
	provider := item["beckn:orderItemAttributes"].providerAttributes
	not provider["@type"]

	msg := sprintf(
		"order item [%d]: providerAttributes @type is missing; must be EnergyCustomer",
		[i],
	)
}

_confirm_violations contains msg if {
	item := input.message.order["beckn:orderItems"][i]
	provider := item["beckn:orderItemAttributes"].providerAttributes
	provider["@type"]
	provider["@type"] != "EnergyCustomer"

	msg := sprintf(
		"order item [%d]: providerAttributes @type is %q; must be EnergyCustomer",
		[i, provider["@type"]],
	)
}


# ===== JSON-LD @context validation =====

_required_context := "https://raw.githubusercontent.com/beckn/protocol-specifications-v2/refs/heads/p2p-trading/schema/EnergyTrade/v0.3/context.jsonld"

# Rule 15a – Buyer EnergyCustomer @context
_confirm_violations contains msg if {
	buyer_attrs := input.message.order["beckn:buyer"]["beckn:buyerAttributes"]
	buyer_attrs["@type"] == "EnergyCustomer"
	buyer_attrs["@context"] != _required_context

	msg := sprintf(
		"buyer EnergyCustomer @context is %q; must be %q",
		[buyer_attrs["@context"], _required_context],
	)
}

_confirm_violations contains msg if {
	buyer_attrs := input.message.order["beckn:buyer"]["beckn:buyerAttributes"]
	buyer_attrs["@type"] == "EnergyCustomer"
	not buyer_attrs["@context"]

	msg := sprintf(
		"buyer EnergyCustomer @context is missing; must be %q",
		[_required_context],
	)
}

# Rule 15b – Provider EnergyCustomer @context per order item
_confirm_violations contains msg if {
	item := input.message.order["beckn:orderItems"][i]
	provider := item["beckn:orderItemAttributes"].providerAttributes
	provider["@type"] == "EnergyCustomer"
	provider["@context"] != _required_context

	msg := sprintf(
		"order item [%d]: provider EnergyCustomer @context is %q; must be %q",
		[i, provider["@context"], _required_context],
	)
}

_confirm_violations contains msg if {
	item := input.message.order["beckn:orderItems"][i]
	provider := item["beckn:orderItemAttributes"].providerAttributes
	provider["@type"] == "EnergyCustomer"
	not provider["@context"]

	msg := sprintf(
		"order item [%d]: provider EnergyCustomer @context is missing; must be %q",
		[i, _required_context],
	)
}

# Rule 16 – EnergyTradeOrder @context
_confirm_violations contains msg if {
	order := input.message.order
	order["@type"] == "EnergyTradeOrder"
	order["@context"] != _required_context

	msg := sprintf(
		"EnergyTradeOrder @context is %q; must be %q",
		[order["@context"], _required_context],
	)
}

_confirm_violations contains msg if {
	order := input.message.order
	order["@type"] == "EnergyTradeOrder"
	not order["@context"]

	msg := sprintf(
		"EnergyTradeOrder @context is missing; must be %q",
		[_required_context],
	)
}

# Rule 17 – EnergyTradeOffer @context per order item
_confirm_violations contains msg if {
	item := input.message.order["beckn:orderItems"][i]
	offer := item["beckn:acceptedOffer"]
	offer["@type"] == "EnergyTradeOffer"
	offer["@context"] != _required_context

	msg := sprintf(
		"order item [%d]: EnergyTradeOffer @context is %q; must be %q",
		[i, offer["@context"], _required_context],
	)
}

_confirm_violations contains msg if {
	item := input.message.order["beckn:orderItems"][i]
	offer := item["beckn:acceptedOffer"]
	offer["@type"] == "EnergyTradeOffer"
	not offer["@context"]

	msg := sprintf(
		"order item [%d]: EnergyTradeOffer @context is missing; must be %q",
		[i, _required_context],
	)
}

# ===== Action-gated violations (public API) =====
#
# Rego determines which rules apply based on input.context.action.
# The Go plugin no longer filters by action — all actions are evaluated.

# Confirm action: all order-validation rules apply
violations contains msg if {
	input.context.action == "confirm"
	some msg in _confirm_violations
}

# Publish action: network-based catalog item validation
violations contains msg if {
	input.context.action == "publish"
	some msg in _publish_violations
}

# Non-publish actions (select, init, confirm, etc.): test ID consistency
violations contains msg if {
	input.context.action != "publish"
	some msg in _test_consistency_violations
}

# ===== Publish-action rules =====
#
# For publish (catalog) messages, each beckn:Item carries a network_id.
# - Production network: providerAttributes must exist with an approved DISCOM.
# - Non-production network: provider must use test identifiers.

_production_network_id := "p2p-interdiscom-trading-pilot-network"

# Approved DISCOMs for production network (extend this list as needed)
_allowed_utility_ids := {"TPDDL", "PVVNL", "BRPL"}

# Publish Rule 1 — Production: providerAttributes must exist
_publish_violations contains msg if {
	item := input.message.catalog["beckn:Item"][i]
	item.network_id == _production_network_id
	not item.providerAttributes

	msg := sprintf(
		"catalog item [%d]: providerAttributes is missing on production network item",
		[i],
	)
}

# Publish Rule 2 — Production: provider utilityId must be an approved DISCOM
_publish_violations contains msg if {
	item := input.message.catalog["beckn:Item"][i]
	item.network_id == _production_network_id
	item.providerAttributes
	not item.providerAttributes.utilityId in _allowed_utility_ids

	msg := sprintf(
		"catalog item [%d]: provider utilityId %q is not an approved DISCOM; must be one of %v",
		[i, item.providerAttributes.utilityId, _allowed_utility_ids],
	)
}

# Publish Rule 3 — Non-production: provider meterId must be TEST_METER_SELLER
_publish_violations contains msg if {
	item := input.message.catalog["beckn:Item"][i]
	item.network_id
	item.network_id != _production_network_id
	item.providerAttributes.meterId
	item.providerAttributes.meterId != "TEST_METER_SELLER"

	msg := sprintf(
		"catalog item [%d]: non-production network %q: provider meterId is %q; must be TEST_METER_SELLER",
		[i, item.network_id, item.providerAttributes.meterId],
	)
}

# Publish Rule 4 — Non-production: provider utilityId must be TEST_DISCOM_SELLER
_publish_violations contains msg if {
	item := input.message.catalog["beckn:Item"][i]
	item.network_id
	item.network_id != _production_network_id
	item.providerAttributes.utilityId
	item.providerAttributes.utilityId != "TEST_DISCOM_SELLER"

	msg := sprintf(
		"catalog item [%d]: non-production network %q: provider utilityId is %q; must be TEST_DISCOM_SELLER",
		[i, item.network_id, item.providerAttributes.utilityId],
	)
}

# ===== Test ID consistency (non-publish actions) =====
#
# If any provider on an order item uses a test identifier (meterId or utilityId
# starting with "TEST_"), the buyer must also use test identifiers:
#   - buyer meterId = TEST_METER_BUYER
#   - buyer utilityId = TEST_DISCOM_BUYER

_any_provider_is_test if {
	item := input.message.order["beckn:orderItems"][_]
	provider := item["beckn:orderItemAttributes"].providerAttributes
	startswith(provider.meterId, "TEST_")
}

_any_provider_is_test if {
	item := input.message.order["beckn:orderItems"][_]
	provider := item["beckn:orderItemAttributes"].providerAttributes
	startswith(provider.utilityId, "TEST_")
}

# Test consistency: buyer meterId must be TEST_METER_BUYER
_test_consistency_violations contains msg if {
	_any_provider_is_test
	buyer_mid := _buyer_meter_id
	buyer_mid != "TEST_METER_BUYER"

	msg := sprintf(
		"test consistency: provider uses test identifiers but buyer meterId is %q; must be TEST_METER_BUYER",
		[buyer_mid],
	)
}

# Test consistency: buyer utilityId must be TEST_DISCOM_BUYER
_test_consistency_violations contains msg if {
	_any_provider_is_test
	buyer_uid := _buyer_utility_id
	buyer_uid != "TEST_DISCOM_BUYER"

	msg := sprintf(
		"test consistency: provider uses test identifiers but buyer utilityId is %q; must be TEST_DISCOM_BUYER",
		[buyer_uid],
	)
}
