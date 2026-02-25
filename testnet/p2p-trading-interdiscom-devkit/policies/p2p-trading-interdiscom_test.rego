package deg.policy_test

import rego.v1

import data.deg.policy

# Shared buyer stub — includes utilityCustomerId for Rule 9a
_buyer := {"beckn:buyerAttributes": {
	"@type": "EnergyCustomer", "@context": _ctx,
	"meterId": "der://meter/BUYER-001",
	"utilityCustomerId": "UTIL-CUST-B001",
	"utilityId": "UTIL-B001",
}}

# Shared helper: full compliant order item (quantity, price INR, utilityCustomerId)
_compliant_item(dw_start, dw_end, buyer_mid, provider_mid) := {
	"beckn:acceptedOffer": {
		"beckn:offerAttributes": {"deliveryWindow": {
			"schema:startTime": dw_start,
			"schema:endTime": dw_end,
		}},
		"beckn:price": {
			"schema:priceCurrency": "INR",
			"applicableQuantity": {"unitQuantity": 20.0, "unitText": "kWh"},
		},
	},
	"beckn:quantity": {"unitQuantity": 10.0, "unitText": "kWh"},
	"beckn:orderItemAttributes": {"providerAttributes": {
		"@type": "EnergyCustomer", "@context": _ctx,
		"meterId": provider_mid,
		"utilityCustomerId": "UTIL-CUST-P001",
		"utilityId": "UTIL-P001",
	}},
}

# Required domain for Rule 13
_domain := "beckn.one:deg:p2p-trading-interdiscom:2.0.0"

# Required @context for Rules 15-17
_ctx := "https://raw.githubusercontent.com/beckn/protocol-specifications-v2/refs/heads/p2p-trading/schema/EnergyTrade/v0.3/context.jsonld"

# Simpler helper for meter-focused tests
_order_with_meters(buyer_mid, provider_mid) := {
	"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
	"message": {"order": {
		"beckn:buyer": {"beckn:buyerAttributes": {
			"@type": "EnergyCustomer", "@context": _ctx,
			"meterId": buyer_mid,
			"utilityCustomerId": "UTIL-CUST-B001",
			"utilityId": "UTIL-B001",
		}},
		"beckn:orderItems": [{
			"beckn:acceptedOffer": {
				"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}},
				"beckn:price": {
					"schema:priceCurrency": "INR",
					"applicableQuantity": {"unitQuantity": 20.0, "unitText": "kWh"},
				},
			},
			"beckn:quantity": {"unitQuantity": 10.0, "unitText": "kWh"},
			"beckn:orderItemAttributes": {"providerAttributes": {
				"@type": "EnergyCustomer", "@context": _ctx,
				"meterId": provider_mid,
				"utilityCustomerId": "UTIL-CUST-P001",
				"utilityId": "UTIL-P001",
			}},
		}],
	}},
}

# ===== Rule 1: Delivery lead time =====

# --- Compliant: delivery start is 8 hours after trade time, 1hr slot ---
test_compliant_delivery_window if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}},
			}],
		}},
	}
	count(result) == 0
}

# --- Compliant: exactly 4 hours lead time (boundary), 1hr slot ---
test_exactly_4_hours_is_compliant if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T04:00:00Z",
					"schema:endTime": "2026-01-09T05:00:00Z",
				}}},
			}],
		}},
	}
	count(result) == 0
}

# --- Non-compliant: only 2 hours lead time ---
test_insufficient_lead_time if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T02:00:00Z",
					"schema:endTime": "2026-01-09T03:00:00Z",
				}}},
			}],
		}},
	}
	count(result) == 1
}

# --- Non-compliant: multiple items, one violates lead time ---
test_mixed_items if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [
				{"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}}},
				{"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T01:00:00Z",
					"schema:endTime": "2026-01-09T02:00:00Z",
				}}}},
			],
		}},
	}
	count(result) == 1
}

# --- Non-compliant: all items violate lead time ---
test_all_items_violate if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T10:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [
				{"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T11:00:00Z",
					"schema:endTime": "2026-01-09T12:00:00Z",
				}}}},
				{"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T12:00:00Z",
					"schema:endTime": "2026-01-09T13:00:00Z",
				}}}},
			],
		}},
	}
	count(result) == 2
}

# --- Custom lead hours via config ---
test_custom_lead_hours if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T02:00:00Z",
					"schema:endTime": "2026-01-09T03:00:00Z",
				}}},
			}],
		}},
	}
		with data.config as {"minDeliveryLeadHours": "1"}
	count(result) == 0
}

# --- Handles beckn:timeWindow field name ---
test_beckn_time_window_field if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"beckn:timeWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}},
			}],
		}},
	}
	count(result) == 0
}

# --- No delivery window = no violation ---
test_no_delivery_window if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"pricingModel": "PER_KWH"}},
			}],
		}},
	}
	count(result) == 0
}

# ===== Rule 2: Validity window gap =====

# --- Compliant: validity ends 5 hours before delivery start ---
test_validity_window_compliant if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {
					"deliveryWindow": {
						"schema:startTime": "2026-01-09T09:00:00Z",
						"schema:endTime": "2026-01-09T10:00:00Z",
					},
					"validityWindow": {
						"schema:startTime": "2026-01-09T00:00:00Z",
						"schema:endTime": "2026-01-09T04:00:00Z",
					},
				}},
			}],
		}},
	}
	count(result) == 0
}

# --- Compliant: validity ends exactly 4 hours before delivery (boundary) ---
test_validity_window_exact_boundary if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {
					"deliveryWindow": {
						"schema:startTime": "2026-01-09T08:00:00Z",
						"schema:endTime": "2026-01-09T09:00:00Z",
					},
					"validityWindow": {
						"schema:startTime": "2026-01-09T00:00:00Z",
						"schema:endTime": "2026-01-09T04:00:00Z",
					},
				}},
			}],
		}},
	}
	count(result) == 0
}

# --- Non-compliant: validity ends only 2 hours before delivery start ---
test_validity_window_too_close if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {
					"deliveryWindow": {
						"schema:startTime": "2026-01-09T06:00:00Z",
						"schema:endTime": "2026-01-09T07:00:00Z",
					},
					"validityWindow": {
						"schema:startTime": "2026-01-09T00:00:00Z",
						"schema:endTime": "2026-01-09T04:00:00Z",
					},
				}},
			}],
		}},
	}
	count(result) == 1
}

# --- No validity window = no violation for rule 2 ---
test_no_validity_window if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}},
			}],
		}},
	}
	count(result) == 0
}

# --- Handles beckn:validityWindow field name ---
test_beckn_validity_window_field if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {
					"deliveryWindow": {
						"schema:startTime": "2026-01-09T09:00:00Z",
						"schema:endTime": "2026-01-09T10:00:00Z",
					},
					"beckn:validityWindow": {
						"schema:startTime": "2026-01-09T00:00:00Z",
						"schema:endTime": "2026-01-09T04:00:00Z",
					},
				}},
			}],
		}},
	}
	count(result) == 0
}

# ===== Rule 3: Delivery slot must be exactly 1 hour =====

# --- Non-compliant: 6-hour delivery window ---
test_delivery_window_too_long if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T14:00:00Z",
				}}},
			}],
		}},
	}
	count(result) == 1
}

# --- Non-compliant: 30-minute delivery window ---
test_delivery_window_too_short if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T08:30:00Z",
				}}},
			}],
		}},
	}
	count(result) == 1
}

# ===== Rule 4: Meter ID validation =====

# --- Compliant: different meter IDs ---
test_meter_ids_different if {
	result := policy.violations with input as _order_with_meters("der://meter/BUYER-001", "der://meter/SELLER-001")
	count(result) == 0
}

# --- Non-compliant: buyer meterId is empty ---
test_buyer_meter_id_empty if {
	result := policy.violations with input as _order_with_meters("", "der://meter/SELLER-001")
	count(result) == 1
}

# --- Non-compliant: buyer meterId is missing entirely ---
test_buyer_meter_id_missing if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": {"beckn:buyerAttributes": {
				"@type": "EnergyCustomer", "@context": _ctx,
				"utilityCustomerId": "UTIL-CUST-B001",
				"utilityId": "UTIL-B001",
			}},
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}},
				"beckn:orderItemAttributes": {"providerAttributes": {
					"@type": "EnergyCustomer", "@context": _ctx,
					"meterId": "der://meter/SELLER-001",
					"utilityCustomerId": "UTIL-CUST-P001",
					"utilityId": "UTIL-P001",
				}},
			}],
		}},
	}
	count(result) == 1
}

# --- Non-compliant: buyer and provider have the same meterId ---
test_same_meter_id if {
	result := policy.violations with input as _order_with_meters("der://meter/SAME-001", "der://meter/SAME-001")
	count(result) == 1
}

# --- Non-compliant: multiple items, one has same meterId as buyer ---
test_mixed_meter_ids if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": {"beckn:buyerAttributes": {
				"@type": "EnergyCustomer", "@context": _ctx,
				"meterId": "der://meter/BUYER-001",
				"utilityCustomerId": "UTIL-CUST-B001",
				"utilityId": "UTIL-B001",
			}},
			"beckn:orderItems": [
				{
					"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
						"schema:startTime": "2026-01-09T08:00:00Z",
						"schema:endTime": "2026-01-09T09:00:00Z",
					}}},
					"beckn:orderItemAttributes": {"providerAttributes": {
						"@type": "EnergyCustomer", "@context": _ctx,
						"meterId": "der://meter/SELLER-001",
						"utilityCustomerId": "UTIL-CUST-P001",
						"utilityId": "UTIL-P001",
					}},
				},
				{
					"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
						"schema:startTime": "2026-01-09T10:00:00Z",
						"schema:endTime": "2026-01-09T11:00:00Z",
					}}},
					"beckn:orderItemAttributes": {"providerAttributes": {
						"@type": "EnergyCustomer", "@context": _ctx,
						"meterId": "der://meter/BUYER-001",
						"utilityCustomerId": "UTIL-CUST-P002",
						"utilityId": "UTIL-P002",
					}},
				},
			],
		}},
	}
	# Only item [1] matches buyer meterId
	count(result) == 1
}

# --- No buyerAttributes at all = violation (missing meterId + utilityCustomerId) ---
test_no_buyer_attributes if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}},
			}],
		}},
	}
	# Rule 4a (missing meterId) + Rule 9a (missing utilityCustomerId) + Rule 9c (missing utilityId) + Rule 10a (missing @type)
	count(result) == 4
}

# Helper: full compliant order with controllable meters AND utility IDs
_order_with_ids(buyer_mid, provider_mid, buyer_uid, provider_uid) := {
	"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
	"message": {"order": {
		"beckn:buyer": {"beckn:buyerAttributes": {
			"@type": "EnergyCustomer", "@context": _ctx,
			"meterId": buyer_mid,
			"utilityCustomerId": "UTIL-CUST-B001",
			"utilityId": buyer_uid,
		}},
		"beckn:orderItems": [{
			"beckn:acceptedOffer": {
				"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}},
				"beckn:price": {
					"schema:priceCurrency": "INR",
					"applicableQuantity": {"unitQuantity": 20.0, "unitText": "kWh"},
				},
			},
			"beckn:quantity": {"unitQuantity": 10.0, "unitText": "kWh"},
			"beckn:orderItemAttributes": {"providerAttributes": {
				"@type": "EnergyCustomer", "@context": _ctx,
				"meterId": provider_mid,
				"utilityCustomerId": "UTIL-CUST-P001",
				"utilityId": provider_uid,
			}},
		}],
	}},
}


# ===== Rule 6: Quantity bounds =====

# --- Compliant: quantity within range ---
test_quantity_within_range if {
	result := policy.violations with input as _order_with_meters("der://meter/BUYER-001", "der://meter/SELLER-001")
	# _order_with_meters has qty=10, cap=20 → compliant
	count(result) == 0
}

# --- Non-compliant: negative quantity ---
test_quantity_negative if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {
					"beckn:offerAttributes": {"deliveryWindow": {
						"schema:startTime": "2026-01-09T08:00:00Z",
						"schema:endTime": "2026-01-09T09:00:00Z",
					}},
					"beckn:price": {
						"schema:priceCurrency": "INR",
						"applicableQuantity": {"unitQuantity": 20.0, "unitText": "kWh"},
					},
				},
				"beckn:quantity": {"unitQuantity": -5.0, "unitText": "kWh"},
			}],
		}},
	}
	count(result) == 1
}

# --- Non-compliant: quantity equals applicableQuantity (must be strictly less) ---
test_quantity_equals_cap if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {
					"beckn:offerAttributes": {"deliveryWindow": {
						"schema:startTime": "2026-01-09T08:00:00Z",
						"schema:endTime": "2026-01-09T09:00:00Z",
					}},
					"beckn:price": {
						"schema:priceCurrency": "INR",
						"applicableQuantity": {"unitQuantity": 20.0, "unitText": "kWh"},
					},
				},
				"beckn:quantity": {"unitQuantity": 20.0, "unitText": "kWh"},
			}],
		}},
	}
	count(result) == 1
}

# --- Non-compliant: quantity exceeds applicableQuantity ---
test_quantity_exceeds_cap if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {
					"beckn:offerAttributes": {"deliveryWindow": {
						"schema:startTime": "2026-01-09T08:00:00Z",
						"schema:endTime": "2026-01-09T09:00:00Z",
					}},
					"beckn:price": {
						"schema:priceCurrency": "INR",
						"applicableQuantity": {"unitQuantity": 20.0, "unitText": "kWh"},
					},
				},
				"beckn:quantity": {"unitQuantity": 25.0, "unitText": "kWh"},
			}],
		}},
	}
	count(result) == 1
}

# ===== Rule 7: Currency must be INR =====

# --- Non-compliant: USD currency ---
test_currency_not_inr if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {
					"beckn:offerAttributes": {"deliveryWindow": {
						"schema:startTime": "2026-01-09T08:00:00Z",
						"schema:endTime": "2026-01-09T09:00:00Z",
					}},
					"beckn:price": {
						"schema:priceCurrency": "USD",
						"applicableQuantity": {"unitQuantity": 20.0, "unitText": "kWh"},
					},
				},
				"beckn:quantity": {"unitQuantity": 10.0, "unitText": "kWh"},
			}],
		}},
	}
	count(result) == 1
}

# --- Compliant: INR currency ---
test_currency_inr if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {
					"beckn:offerAttributes": {"deliveryWindow": {
						"schema:startTime": "2026-01-09T08:00:00Z",
						"schema:endTime": "2026-01-09T09:00:00Z",
					}},
					"beckn:price": {
						"schema:priceCurrency": "INR",
						"applicableQuantity": {"unitQuantity": 20.0, "unitText": "kWh"},
					},
				},
				"beckn:quantity": {"unitQuantity": 10.0, "unitText": "kWh"},
			}],
		}},
	}
	count(result) == 0
}

# ===== Rule 8: Quantity unit must be kWh =====

# --- Non-compliant: MWh unit ---
test_quantity_unit_not_kwh if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {
					"beckn:offerAttributes": {"deliveryWindow": {
						"schema:startTime": "2026-01-09T08:00:00Z",
						"schema:endTime": "2026-01-09T09:00:00Z",
					}},
					"beckn:price": {
						"schema:priceCurrency": "INR",
						"applicableQuantity": {"unitQuantity": 20.0, "unitText": "kWh"},
					},
				},
				"beckn:quantity": {"unitQuantity": 10.0, "unitText": "MWh"},
			}],
		}},
	}
	count(result) == 1
}

# ===== Rule 9: utilityCustomerId validation =====

# --- Non-compliant: buyer utilityCustomerId missing ---
test_buyer_utility_cust_id_missing if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": {"beckn:buyerAttributes": {
				"@type": "EnergyCustomer", "@context": _ctx,
				"meterId": "der://meter/BUYER-001",
				"utilityId": "UTIL-B001",
			}},
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}},
			}],
		}},
	}
	count(result) == 1
}

# --- Non-compliant: buyer utilityCustomerId empty ---
test_buyer_utility_cust_id_empty if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": {"beckn:buyerAttributes": {
				"@type": "EnergyCustomer", "@context": _ctx,
				"meterId": "der://meter/BUYER-001",
				"utilityCustomerId": "",
				"utilityId": "UTIL-B001",
			}},
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}},
			}],
		}},
	}
	count(result) == 1
}

# --- Non-compliant: provider utilityCustomerId missing ---
test_provider_utility_cust_id_missing if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}},
				"beckn:orderItemAttributes": {"providerAttributes": {
					"@type": "EnergyCustomer", "@context": _ctx,
					"meterId": "der://meter/SELLER-001",
					"utilityId": "UTIL-P001",
				}},
			}],
		}},
	}
	count(result) == 1
}

# --- Non-compliant: provider utilityCustomerId empty ---
test_provider_utility_cust_id_empty if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}},
				"beckn:orderItemAttributes": {"providerAttributes": {
					"@type": "EnergyCustomer", "@context": _ctx,
					"meterId": "der://meter/SELLER-001",
					"utilityCustomerId": "",
					"utilityId": "UTIL-P001",
				}},
			}],
		}},
	}
	count(result) == 1
}

# ===== Combined: multiple rules fire together =====

# --- All rules violated on one item ---
test_all_rules_violated if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T10:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": {"beckn:buyerAttributes": {
				"meterId": "der://meter/SAME-001",
				"utilityCustomerId": "UTIL-CUST-B001",
			}},
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {
					"beckn:offerAttributes": {
						"deliveryWindow": {
							"schema:startTime": "2026-01-09T11:00:00Z",
							"schema:endTime": "2026-01-09T14:00:00Z",
						},
						"validityWindow": {
							"schema:startTime": "2026-01-09T09:00:00Z",
							"schema:endTime": "2026-01-09T10:30:00Z",
						},
					},
					"beckn:price": {
						"schema:priceCurrency": "USD",
						"applicableQuantity": {"unitQuantity": 5.0, "unitText": "kWh"},
					},
				},
				"beckn:quantity": {"unitQuantity": 10.0, "unitText": "MWh"},
				"beckn:orderItemAttributes": {"providerAttributes": {
					"meterId": "der://meter/SAME-001",
					"utilityCustomerId": "UTIL-CUST-P001",
				}},
			}],
		}},
	}
	# Rule 1: 1hr lead (need 4)
	# Rule 2: validity end 0.5hr before delivery start (need 4)
	# Rule 3: 3hr delivery window (need 1)
	# Rule 4b: same meterId
	# Rule 6b: qty 10 >= cap 5
	# Rule 7: USD not INR
	# Rule 8: MWh not kWh
	# Rule 9c: buyer utilityId missing
	# Rule 9d: provider utilityId missing
	# Rule 10a: buyer @type missing
	# Rule 10b: provider @type missing
	count(result) == 11
}

# ===== Rule 9c/9d: utilityId validation =====

# --- Non-compliant: buyer utilityId missing ---
test_buyer_utility_id_missing if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": {"beckn:buyerAttributes": {
				"@type": "EnergyCustomer", "@context": _ctx,
				"meterId": "der://meter/BUYER-001",
				"utilityCustomerId": "UTIL-CUST-B001",
			}},
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}},
			}],
		}},
	}
	count(result) == 1
}

# --- Non-compliant: buyer utilityId empty ---
test_buyer_utility_id_empty if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": {"beckn:buyerAttributes": {
				"@type": "EnergyCustomer", "@context": _ctx,
				"meterId": "der://meter/BUYER-001",
				"utilityCustomerId": "UTIL-CUST-B001",
				"utilityId": "",
			}},
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}},
			}],
		}},
	}
	count(result) == 1
}

# --- Non-compliant: provider utilityId missing ---
test_provider_utility_id_missing if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}},
				"beckn:orderItemAttributes": {"providerAttributes": {
					"@type": "EnergyCustomer", "@context": _ctx,
					"meterId": "der://meter/SELLER-001",
					"utilityCustomerId": "UTIL-CUST-P001",
				}},
			}],
		}},
	}
	count(result) == 1
}

# --- Non-compliant: provider utilityId empty ---
test_provider_utility_id_empty if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}},
				"beckn:orderItemAttributes": {"providerAttributes": {
					"@type": "EnergyCustomer", "@context": _ctx,
					"meterId": "der://meter/SELLER-001",
					"utilityCustomerId": "UTIL-CUST-P001",
					"utilityId": "",
				}},
			}],
		}},
	}
	count(result) == 1
}

# ===== Rule 10: EnergyCustomer @type validation =====

# --- Non-compliant: buyer @type missing ---
test_buyer_type_missing if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": {"beckn:buyerAttributes": {
				"meterId": "der://meter/BUYER-001",
				"utilityCustomerId": "UTIL-CUST-B001",
				"utilityId": "UTIL-B001",
			}},
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}},
			}],
		}},
	}
	count(result) == 1
}

# --- Non-compliant: buyer @type wrong value ---
test_buyer_type_wrong if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": {"beckn:buyerAttributes": {
				"@type": "Person",
				"meterId": "der://meter/BUYER-001",
				"utilityCustomerId": "UTIL-CUST-B001",
				"utilityId": "UTIL-B001",
			}},
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}},
			}],
		}},
	}
	count(result) == 1
}

# --- Non-compliant: provider @type missing ---
test_provider_type_missing if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}},
				"beckn:orderItemAttributes": {"providerAttributes": {
					"meterId": "der://meter/SELLER-001",
					"utilityCustomerId": "UTIL-CUST-P001",
					"utilityId": "UTIL-P001",
				}},
			}],
		}},
	}
	count(result) == 1
}

# --- Non-compliant: provider @type wrong value ---
test_provider_type_wrong if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}},
				"beckn:orderItemAttributes": {"providerAttributes": {
					"@type": "Organization",
					"meterId": "der://meter/SELLER-001",
					"utilityCustomerId": "UTIL-CUST-P001",
					"utilityId": "UTIL-P001",
				}},
			}],
		}},
	}
	count(result) == 1
}



# ===== Rule 13: Domain validation =====

# --- Compliant: correct domain ---
test_domain_correct if {
	result := policy.violations with input as _order_with_meters("der://meter/BUYER-001", "der://meter/SELLER-001")
	count(result) == 0
}

# --- Non-compliant: wrong domain ---
test_domain_wrong if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": "some:other:domain:1.0.0", "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}},
			}],
		}},
	}
	count(result) == 1
}

# --- Non-compliant: domain missing (also missing version → 2 violations) ---
test_domain_missing if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}},
			}],
		}},
	}
	count(result) == 1
}

# ===== Rule 14: Version validation =====

# --- Compliant: correct version (covered by _order_with_meters tests) ---
test_version_correct if {
	result := policy.violations with input as _order_with_meters("der://meter/BUYER-001", "der://meter/SELLER-001")
	count(result) == 0
}

# --- Non-compliant: wrong version ---
test_version_wrong if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "1.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}},
			}],
		}},
	}
	count(result) == 1
}

# --- Non-compliant: version missing ---
test_version_missing if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}},
			}],
		}},
	}
	count(result) == 1
}

# ===== Rule 15: EnergyCustomer @context validation =====

# --- Compliant: buyer and provider have correct @context (covered by helpers) ---
test_energy_customer_context_correct if {
	result := policy.violations with input as _order_with_meters("der://meter/BUYER-001", "der://meter/SELLER-001")
	count(result) == 0
}

# --- Non-compliant: buyer EnergyCustomer @context wrong ---
test_energy_customer_buyer_context_wrong if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": {"beckn:buyerAttributes": {
				"@type": "EnergyCustomer", "@context": "https://wrong.example.com/context.jsonld",
				"meterId": "der://meter/BUYER-001",
				"utilityCustomerId": "UTIL-CUST-B001",
				"utilityId": "UTIL-B001",
			}},
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}},
			}],
		}},
	}
	count(result) == 1
}

# --- Non-compliant: buyer EnergyCustomer @context missing ---
test_energy_customer_buyer_context_missing if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": {"beckn:buyerAttributes": {
				"@type": "EnergyCustomer",
				"meterId": "der://meter/BUYER-001",
				"utilityCustomerId": "UTIL-CUST-B001",
				"utilityId": "UTIL-B001",
			}},
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}},
			}],
		}},
	}
	count(result) == 1
}

# --- Non-compliant: provider EnergyCustomer @context wrong ---
test_energy_customer_provider_context_wrong if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}},
				"beckn:orderItemAttributes": {"providerAttributes": {
					"@type": "EnergyCustomer", "@context": "https://wrong.example.com/context.jsonld",
					"meterId": "der://meter/SELLER-001",
					"utilityCustomerId": "UTIL-CUST-P001",
					"utilityId": "UTIL-P001",
				}},
			}],
		}},
	}
	count(result) == 1
}

# --- Non-compliant: provider EnergyCustomer @context missing ---
test_energy_customer_provider_context_missing if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}},
				"beckn:orderItemAttributes": {"providerAttributes": {
					"@type": "EnergyCustomer",
					"meterId": "der://meter/SELLER-001",
					"utilityCustomerId": "UTIL-CUST-P001",
					"utilityId": "UTIL-P001",
				}},
			}],
		}},
	}
	count(result) == 1
}

# ===== Rule 16: EnergyTradeOrder @context validation =====

# --- Compliant: order has correct @context ---
test_energy_trade_order_context_correct if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"@type": "EnergyTradeOrder", "@context": _ctx,
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}},
			}],
		}},
	}
	count(result) == 0
}

# --- Non-compliant: order @context wrong ---
test_energy_trade_order_context_wrong if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"@type": "EnergyTradeOrder", "@context": "https://wrong.example.com/context.jsonld",
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}},
			}],
		}},
	}
	count(result) == 1
}

# --- Non-compliant: order @context missing ---
test_energy_trade_order_context_missing if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"@type": "EnergyTradeOrder",
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {"beckn:offerAttributes": {"deliveryWindow": {
					"schema:startTime": "2026-01-09T08:00:00Z",
					"schema:endTime": "2026-01-09T09:00:00Z",
				}}},
			}],
		}},
	}
	count(result) == 1
}

# --- No @type on order → rule doesn't fire ---
test_energy_trade_order_no_type_skips if {
	result := policy.violations with input as _order_with_meters("der://meter/BUYER-001", "der://meter/SELLER-001")
	count(result) == 0
}

# ===== Rule 17: EnergyTradeOffer @context validation =====

# --- Compliant: offer has correct @context ---
test_energy_trade_offer_context_correct if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {
					"@type": "EnergyTradeOffer", "@context": _ctx,
					"beckn:offerAttributes": {"deliveryWindow": {
						"schema:startTime": "2026-01-09T08:00:00Z",
						"schema:endTime": "2026-01-09T09:00:00Z",
					}},
				},
			}],
		}},
	}
	count(result) == 0
}

# --- Non-compliant: offer @context wrong ---
test_energy_trade_offer_context_wrong if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {
					"@type": "EnergyTradeOffer", "@context": "https://wrong.example.com/context.jsonld",
					"beckn:offerAttributes": {"deliveryWindow": {
						"schema:startTime": "2026-01-09T08:00:00Z",
						"schema:endTime": "2026-01-09T09:00:00Z",
					}},
				},
			}],
		}},
	}
	count(result) == 1
}

# --- Non-compliant: offer @context missing ---
test_energy_trade_offer_context_missing if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": _buyer,
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {
					"@type": "EnergyTradeOffer",
					"beckn:offerAttributes": {"deliveryWindow": {
						"schema:startTime": "2026-01-09T08:00:00Z",
						"schema:endTime": "2026-01-09T09:00:00Z",
					}},
				},
			}],
		}},
	}
	count(result) == 1
}

# --- No @type on offer → rule doesn't fire ---
test_energy_trade_offer_no_type_skips if {
	result := policy.violations with input as _order_with_meters("der://meter/BUYER-001", "der://meter/SELLER-001")
	count(result) == 0
}

# ===== Publish action: production network DISCOM validation =====

# --- Compliant: production network with approved DISCOM ---
test_publish_production_approved_discom if {
	result := policy.violations with input as {
		"context": {"action": "publish"},
		"message": {"catalog": {"beckn:Item": [{
			"network_id": "p2p-interdiscom-trading-pilot-network",
			"providerAttributes": {
				"meterId": "der://meter/SELLER-001",
				"utilityId": "TPDDL",
			},
		}]}},
	}
	count(result) == 0
}

# --- All three approved DISCOMs accepted on production ---
test_publish_production_all_three_discoms if {
	r1 := policy.violations with input as {
		"context": {"action": "publish"},
		"message": {"catalog": {"beckn:Item": [{
			"network_id": "p2p-interdiscom-trading-pilot-network",
			"providerAttributes": {"utilityId": "TPDDL", "meterId": "m1"},
		}]}},
	}
	count(r1) == 0

	r2 := policy.violations with input as {
		"context": {"action": "publish"},
		"message": {"catalog": {"beckn:Item": [{
			"network_id": "p2p-interdiscom-trading-pilot-network",
			"providerAttributes": {"utilityId": "PVVNL", "meterId": "m2"},
		}]}},
	}
	count(r2) == 0

	r3 := policy.violations with input as {
		"context": {"action": "publish"},
		"message": {"catalog": {"beckn:Item": [{
			"network_id": "p2p-interdiscom-trading-pilot-network",
			"providerAttributes": {"utilityId": "BRPL", "meterId": "m3"},
		}]}},
	}
	count(r3) == 0
}

# --- Non-compliant: production network with unapproved DISCOM ---
test_publish_production_unapproved_discom if {
	result := policy.violations with input as {
		"context": {"action": "publish"},
		"message": {"catalog": {"beckn:Item": [{
			"network_id": "p2p-interdiscom-trading-pilot-network",
			"providerAttributes": {
				"meterId": "der://meter/SELLER-001",
				"utilityId": "UNKNOWN_DISCOM",
			},
		}]}},
	}
	count(result) == 1
}

# --- Non-compliant: production network with missing providerAttributes ---
test_publish_production_missing_provider if {
	result := policy.violations with input as {
		"context": {"action": "publish"},
		"message": {"catalog": {"beckn:Item": [{
			"network_id": "p2p-interdiscom-trading-pilot-network",
		}]}},
	}
	count(result) == 1
}

# --- Multiple items: one compliant, one not ---
test_publish_production_mixed_items if {
	result := policy.violations with input as {
		"context": {"action": "publish"},
		"message": {"catalog": {"beckn:Item": [
			{
				"network_id": "p2p-interdiscom-trading-pilot-network",
				"providerAttributes": {"utilityId": "TPDDL", "meterId": "m1"},
			},
			{
				"network_id": "p2p-interdiscom-trading-pilot-network",
				"providerAttributes": {"utilityId": "BAD_DISCOM", "meterId": "m2"},
			},
		]}},
	}
	count(result) == 1
}

# ===== Publish action: non-production network test values =====

# --- Compliant: non-production with correct test values ---
test_publish_sandbox_correct_test_values if {
	result := policy.violations with input as {
		"context": {"action": "publish"},
		"message": {"catalog": {"beckn:Item": [{
			"network_id": "p2p-interdiscom-trading-sandbox",
			"providerAttributes": {
				"meterId": "TEST_METER_SELLER",
				"utilityId": "TEST_DISCOM_SELLER",
			},
		}]}},
	}
	count(result) == 0
}

# --- Non-compliant: non-production with real meter ---
test_publish_sandbox_real_meter if {
	result := policy.violations with input as {
		"context": {"action": "publish"},
		"message": {"catalog": {"beckn:Item": [{
			"network_id": "p2p-interdiscom-trading-sandbox",
			"providerAttributes": {
				"meterId": "der://meter/SELLER-001",
				"utilityId": "TEST_DISCOM_SELLER",
			},
		}]}},
	}
	count(result) == 1
}

# --- Non-compliant: non-production with real DISCOM ---
test_publish_sandbox_real_discom if {
	result := policy.violations with input as {
		"context": {"action": "publish"},
		"message": {"catalog": {"beckn:Item": [{
			"network_id": "p2p-interdiscom-trading-sandbox",
			"providerAttributes": {
				"meterId": "TEST_METER_SELLER",
				"utilityId": "TPDDL",
			},
		}]}},
	}
	count(result) == 1
}

# --- Non-compliant: non-production with both real values (2 violations) ---
test_publish_sandbox_both_real if {
	result := policy.violations with input as {
		"context": {"action": "publish"},
		"message": {"catalog": {"beckn:Item": [{
			"network_id": "p2p-interdiscom-trading-sandbox",
			"providerAttributes": {
				"meterId": "der://meter/SELLER-001",
				"utilityId": "TPDDL",
			},
		}]}},
	}
	count(result) == 2
}

# ===== Test ID consistency (non-publish actions) =====

# --- Compliant: all real IDs, no test consistency triggered ---
test_consistency_all_real_ids if {
	result := policy.violations with input as {
		"context": {"action": "select"},
		"message": {"order": {
			"beckn:buyer": {"beckn:buyerAttributes": {
				"@type": "EnergyCustomer", "@context": _ctx,
				"meterId": "der://meter/BUYER-001",
				"utilityCustomerId": "CUST-001",
				"utilityId": "TPDDL",
			}},
			"beckn:orderItems": [{
				"beckn:orderItemAttributes": {"providerAttributes": {
					"@type": "EnergyCustomer", "@context": _ctx,
					"meterId": "der://meter/SELLER-001",
					"utilityCustomerId": "CUST-002",
					"utilityId": "PVVNL",
				}},
			}],
		}},
	}
	count(result) == 0
}

# --- Compliant: all test IDs (both sides consistent) ---
test_consistency_all_test_ids if {
	result := policy.violations with input as {
		"context": {"action": "select"},
		"message": {"order": {
			"beckn:buyer": {"beckn:buyerAttributes": {
				"@type": "EnergyCustomer", "@context": _ctx,
				"meterId": "TEST_METER_BUYER",
				"utilityCustomerId": "CUST-001",
				"utilityId": "TEST_DISCOM_BUYER",
			}},
			"beckn:orderItems": [{
				"beckn:orderItemAttributes": {"providerAttributes": {
					"@type": "EnergyCustomer", "@context": _ctx,
					"meterId": "TEST_METER_SELLER",
					"utilityCustomerId": "CUST-002",
					"utilityId": "TEST_DISCOM_SELLER",
				}},
			}],
		}},
	}
	count(result) == 0
}

# --- Non-compliant: provider test meter but buyer has real IDs (2 violations) ---
test_consistency_provider_test_meter_buyer_real if {
	result := policy.violations with input as {
		"context": {"action": "select"},
		"message": {"order": {
			"beckn:buyer": {"beckn:buyerAttributes": {
				"@type": "EnergyCustomer", "@context": _ctx,
				"meterId": "der://meter/BUYER-001",
				"utilityCustomerId": "CUST-001",
				"utilityId": "TPDDL",
			}},
			"beckn:orderItems": [{
				"beckn:orderItemAttributes": {"providerAttributes": {
					"@type": "EnergyCustomer", "@context": _ctx,
					"meterId": "TEST_METER_SELLER",
					"utilityCustomerId": "CUST-002",
					"utilityId": "TPDDL",
				}},
			}],
		}},
	}
	# buyer meter not TEST_METER_BUYER + buyer discom not TEST_DISCOM_BUYER = 2
	count(result) == 2
}

# --- Non-compliant: provider test discom triggers consistency (2 violations) ---
test_consistency_provider_test_discom_buyer_real if {
	result := policy.violations with input as {
		"context": {"action": "init"},
		"message": {"order": {
			"beckn:buyer": {"beckn:buyerAttributes": {
				"@type": "EnergyCustomer", "@context": _ctx,
				"meterId": "der://meter/BUYER-001",
				"utilityCustomerId": "CUST-001",
				"utilityId": "TPDDL",
			}},
			"beckn:orderItems": [{
				"beckn:orderItemAttributes": {"providerAttributes": {
					"@type": "EnergyCustomer", "@context": _ctx,
					"meterId": "der://meter/SELLER-001",
					"utilityCustomerId": "CUST-002",
					"utilityId": "TEST_DISCOM_SELLER",
				}},
			}],
		}},
	}
	# provider discom starts with TEST_ → buyer must be test too: 2 violations
	count(result) == 2
}

# --- Test consistency also fires on confirm (alongside confirm rules) ---
test_consistency_on_confirm_action if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {"order": {
			"beckn:buyer": {"beckn:buyerAttributes": {
				"@type": "EnergyCustomer", "@context": _ctx,
				"meterId": "der://meter/BUYER-001",
				"utilityCustomerId": "CUST-001",
				"utilityId": "TPDDL",
			}},
			"beckn:orderItems": [{
				"beckn:acceptedOffer": {
					"beckn:offerAttributes": {"deliveryWindow": {
						"schema:startTime": "2026-01-09T08:00:00Z",
						"schema:endTime": "2026-01-09T09:00:00Z",
					}},
					"beckn:price": {
						"schema:priceCurrency": "INR",
						"applicableQuantity": {"unitQuantity": 20.0, "unitText": "kWh"},
					},
				},
				"beckn:quantity": {"unitQuantity": 10.0, "unitText": "kWh"},
				"beckn:orderItemAttributes": {"providerAttributes": {
					"@type": "EnergyCustomer", "@context": _ctx,
					"meterId": "TEST_METER_SELLER",
					"utilityCustomerId": "CUST-002",
					"utilityId": "TEST_DISCOM_SELLER",
				}},
			}],
		}},
	}
	# Test consistency: buyer meter (1) + buyer discom (1) = 2
	# Confirm rules pass (no time/quantity/schema violations)
	count(result) == 2
}

# --- Confirm rules do NOT fire on select action ---
test_confirm_rules_skip_on_select if {
	result := policy.violations with input as {
		"context": {"action": "select"},
		"message": {"order": {
			"beckn:buyer": {"beckn:buyerAttributes": {
				"@type": "EnergyCustomer", "@context": _ctx,
				"meterId": "der://meter/BUYER-001",
				"utilityCustomerId": "CUST-001",
				"utilityId": "TPDDL",
			}},
			"beckn:orderItems": [{
				"beckn:orderItemAttributes": {"providerAttributes": {
					"@type": "EnergyCustomer", "@context": _ctx,
					"meterId": "der://meter/SELLER-001",
					"utilityCustomerId": "CUST-002",
					"utilityId": "PVVNL",
				}},
			}],
		}},
	}
	# No confirm rules fire (no action==confirm), no test consistency (no TEST_ values)
	count(result) == 0
}

# --- Publish rules do NOT fire on confirm action ---
test_publish_rules_skip_on_confirm if {
	result := policy.violations with input as {
		"context": {"action": "confirm", "timestamp": "2026-01-09T00:00:00Z", "domain": _domain, "version": "2.0.0"},
		"message": {
			"order": {
				"beckn:buyer": _buyer,
				"beckn:orderItems": [{
					"beckn:acceptedOffer": {
						"beckn:offerAttributes": {"deliveryWindow": {
							"schema:startTime": "2026-01-09T08:00:00Z",
							"schema:endTime": "2026-01-09T09:00:00Z",
						}},
						"beckn:price": {
							"schema:priceCurrency": "INR",
							"applicableQuantity": {"unitQuantity": 20.0, "unitText": "kWh"},
						},
					},
					"beckn:quantity": {"unitQuantity": 10.0, "unitText": "kWh"},
					"beckn:orderItemAttributes": {"providerAttributes": {
						"@type": "EnergyCustomer", "@context": _ctx,
						"meterId": "der://meter/SELLER-001",
						"utilityCustomerId": "CUST-002",
						"utilityId": "TPDDL",
					}},
				}],
			},
			"catalog": {"beckn:Item": [{
				"network_id": "p2p-interdiscom-trading-pilot-network",
				"providerAttributes": {"utilityId": "UNKNOWN", "meterId": "x"},
			}]},
		},
	}
	# Even though catalog has bad data, publish rules don't fire on confirm
	count(result) == 0
}
