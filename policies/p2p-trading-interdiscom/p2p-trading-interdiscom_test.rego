package deg.policy_test

import rego.v1

import data.deg.policy

# Shared buyer stub — includes utilityCustomerId for Rule 9a
_buyer := {"beckn:buyerAttributes": {
	"@type": "EnergyCustomer",
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
		"@type": "EnergyCustomer",
		"meterId": provider_mid,
		"utilityCustomerId": "UTIL-CUST-P001",
		"utilityId": "UTIL-P001",
	}},
}

# Simpler helper for meter-focused tests
_order_with_meters(buyer_mid, provider_mid) := {
	"context": {"timestamp": "2026-01-09T00:00:00Z"},
	"message": {"order": {
		"beckn:buyer": {"beckn:buyerAttributes": {
			"@type": "EnergyCustomer",
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
				"@type": "EnergyCustomer",
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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
		"context": {"timestamp": "2026-01-09T10:00:00Z"},
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
		"message": {"order": {
			"beckn:buyer": {"beckn:buyerAttributes": {
				"@type": "EnergyCustomer",
				"utilityCustomerId": "UTIL-CUST-B001",
				"utilityId": "UTIL-B001",
			}},
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

# --- Non-compliant: buyer and provider have the same meterId ---
test_same_meter_id if {
	result := policy.violations with input as _order_with_meters("der://meter/SAME-001", "der://meter/SAME-001")
	count(result) == 1
}

# --- Non-compliant: multiple items, one has same meterId as buyer ---
test_mixed_meter_ids if {
	result := policy.violations with input as {
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
		"message": {"order": {
			"beckn:buyer": {"beckn:buyerAttributes": {
				"@type": "EnergyCustomer",
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
						"@type": "EnergyCustomer",
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
						"@type": "EnergyCustomer",
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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

# ===== Rule 5: Production network test-ID guard =====

_prod_config := {"productionNetworkId": "p2p-interdiscom-trading-pilot-network"}

# --- Compliant: real meter IDs on production network ---
test_prod_network_real_meters if {
	result := policy.violations with input as _order_with_meters("der://meter/BUYER-001", "der://meter/SELLER-001")
		with data.config as _prod_config
	count(result) == 0
}

# --- Non-compliant: TEST_BUYER_METER on production network ---
test_prod_network_test_buyer_meter if {
	result := policy.violations with input as _order_with_meters("TEST_BUYER_METER", "der://meter/SELLER-001")
		with data.config as _prod_config
	count(result) == 1
}

# --- Non-compliant: TEST_SELLER_METER on production network ---
test_prod_network_test_seller_meter if {
	result := policy.violations with input as _order_with_meters("der://meter/BUYER-001", "TEST_SELLER_METER")
		with data.config as _prod_config
	count(result) == 1
}

# --- Non-compliant: both test meter IDs on production network ---
test_prod_network_both_test_meters if {
	result := policy.violations with input as _order_with_meters("TEST_BUYER_METER", "TEST_SELLER_METER")
		with data.config as _prod_config
	# Rule 5 buyer + Rule 5 seller = 2
	count(result) == 2
}

# --- No productionNetworkId config = rule 5 is inactive ---
test_no_prod_config_allows_test_meters if {
	result := policy.violations with input as _order_with_meters("TEST_BUYER_METER", "TEST_SELLER_METER")
	count(result) == 0
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
		"message": {"order": {
			"beckn:buyer": {"beckn:buyerAttributes": {
				"@type": "EnergyCustomer",
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
		"message": {"order": {
			"beckn:buyer": {"beckn:buyerAttributes": {
				"@type": "EnergyCustomer",
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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
		"context": {"timestamp": "2026-01-09T10:00:00Z"},
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
		"message": {"order": {
			"beckn:buyer": {"beckn:buyerAttributes": {
				"@type": "EnergyCustomer",
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
		"message": {"order": {
			"beckn:buyer": {"beckn:buyerAttributes": {
				"@type": "EnergyCustomer",
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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
				}},
			}],
		}},
	}
	count(result) == 1
}

# --- Non-compliant: provider utilityId empty ---
test_provider_utility_id_empty if {
	result := policy.violations with input as {
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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
		"context": {"timestamp": "2026-01-09T00:00:00Z"},
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
