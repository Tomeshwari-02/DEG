# Energy Data Exchange Devkit

Beckn Protocol v2.0 devkit demonstrating **inline energy data delivery** via DDM's `DatasetItem` schema. Instead of downloading datasets from external URLs, data (e.g., Verifiable Credentials) is embedded directly in beckn messages using the `dataPayload` attribute.

## Use Case

**BESCOM** (Bangalore Electricity Supply Company) publishes a catalog of utility customer credential datasets. **GridSync Analytics** (a demand-response aggregator) discovers, negotiates, pays for, and receives the data — all within the beckn protocol message flow. The `on_status` response delivers a `UtilityCustomerCredential` inline via `dataPayload`.

## Key Schema: DatasetItem (DDM)

`DatasetItem` from the [DDM](https://github.com/beckn/DDM) repository includes `dataPayload` for optional inline data delivery and `accessMethod` to declare how the dataset is delivered (`INLINE`, `DOWNLOAD`, `DATA_ENCLAVE`, `OFF_CHANNEL`). The `@context` URL in `dataPayload` resolves to the schema describing the payload structure (e.g., `UtilityCustomerCredential` from DEG).

```
DatasetItem (DDM)
  ├── dataPayload: { @context, @type, ...credential data }
  └── accessMethod: INLINE | DOWNLOAD | DATA_ENCLAVE | OFF_CHANNEL
```

## Transaction Flow

```
BPP (BESCOM)        Catalog Service     Discovery Service       BAP (GridSync)
    │                     │                    │                      │
    │── publish ─────────►│                    │                      │
    │   (DatasetItem      │                    │                      │
    │    catalog)         │                    │                      │
    │                     │◄── subscribe ──────│                      │
    │                     │   (catalog updates)│                      │
    │                     │                    │                      │
    │                     │                    │◄──── discover ───────│
    │                     │                    │     (search datasets)│
    │                     │                    │──── on_discover ────►│
    │                     │                    │     (catalog results)│
    │                     │                    │                      │
    ├─────────────────────┼────────────────────┼──────────────────────┤
    │                  Direct BAP ◄─► BPP negotiation                │
    │                                                                │
    │◄──── select (choose dataset + offer) ──────────────────────────│
    │──── on_select (pricing terms) ────────────────────────────────►│
    │                                                                │
    │◄──── init (billing details) ───────────────────────────────────│
    │──── on_init (ready for payment) ──────────────────────────────►│
    │                                                                │
    │◄──── confirm (payment completed) ──────────────────────────────│
    │──── on_confirm (contract active) ─────────────────────────────►│
    │                                                                │
    │◄──── status (check delivery) ──────────────────────────────────│
    │──── on_status (PROCESSING) ──────────────────────────────────►│
    │                                                                │
    │  ┌─ Delivery mode A: URL download ─────────────────────────┐  │
    │  │ on_status (DELIVERY_COMPLETE)                            │  │
    │  │   dataset:downloadUrl + dataset:checksum                 │ ►│
    │  └─────────────────────────────────────────────────────────┘  │
    │                                                                │
    │  ┌─ Delivery mode B: Inline dataPayload ───────────────────┐  │
    │  │ on_status (DELIVERY_COMPLETE)                            │  │
    │  │   dataPayload: UtilityCustomerCredential                 │ ►│
    │  └─────────────────────────────────────────────────────────┘  │
    │                                                                │
    │◄──── cancel ───────────────────────────────────────────────────│
    │──── on_cancel (refund) ──────────────────────────────────────►│
```

## Prerequisites

- Git, Docker, Docker Compose
- Postman (optional, for manual testing)

## Quick Start

```bash
# 1. Start infrastructure
cd install
docker compose -f docker-compose-adapter.yml up -d

# 2. Verify services
curl http://localhost:8081/health   # BAP adapter
curl http://localhost:8082/health   # BPP adapter
curl http://localhost:3001/api/health  # BAP sandbox
curl http://localhost:3002/api/health  # BPP sandbox

# 3. Import Postman collections from postman/ directory
```

## Repository Structure

```
energy-data-exchange-devkit/
├── config/                          # Onix adapter configs
│   ├── local-simple-bap.yaml        # BAP adapter (port 8081)
│   ├── local-simple-bpp.yaml        # BPP adapter (port 8082)
│   └── local-simple-routing-*.yaml  # Routing rules (domain: nfh.global/testnet-deg)
├── examples/v2/                     # Beckn 2.0 example payloads
│   ├── publish-catalog.json         # BPP publishes DatasetItem catalog
│   ├── subscribe-catalog.json       # BAP subscribes to catalog updates
│   ├── discover-request.json        # BAP discovers datasets
│   ├── select-request.json          # BAP selects dataset
│   ├── on-select-response.json      # BPP responds with terms
│   ├── init-request.json            # BAP provides billing info
│   ├── on-init-response.json        # BPP confirms readiness
│   ├── confirm-request.json         # BAP confirms with payment
│   ├── on-confirm-response.json     # BPP acknowledges
│   ├── status-request.json          # BAP checks status
│   ├── on-status-response-processing.json      # BPP: processing
│   ├── on-status-response-ready-url.json       # BPP: delivers via URL download
│   ├── on-status-response-ready-inline.json    # BPP: delivers via inline dataPayload ★
│   ├── cancel-request.json          # BAP cancels
│   └── on-cancel-response.json      # BPP confirms cancellation + refund
├── install/
│   └── docker-compose-adapter.yml   # Docker services
├── postman/                         # Generated Postman collections
│   ├── energy-data-exchange.BAP-DEG.postman_collection.json
│   └── energy-data-exchange.BPP-DEG.postman_collection.json
├── scripts/
│   └── generate_postman_collection.py  # Regenerate Postman from examples
└── workflows/
    └── energy-data-exchange.arazzo.yaml  # Arazzo workflow spec
```

## Network Configuration

| Parameter | Value |
|-----------|-------|
| Network ID | `nfh.global/testnet-deg` |
| BAP ID | `bap.example.com` |
| BPP ID | `bpp.example.com` |
| BAP Adapter | `http://localhost:8081/bap/caller` |
| BPP Adapter | `http://localhost:8082/bpp/caller` |

## Regenerating Postman Collections

```bash
python3 scripts/generate_postman_collection.py --role BAP
python3 scripts/generate_postman_collection.py --role BPP
```

## Related

- [DDM DatasetItem Schema](https://github.com/beckn/DDM/tree/main/specification/schema/DatasetItem/v1) — The DatasetItem schema with `dataPayload` and `accessMethod`
- [UtilityCustomerCredential](../../specification/schema/UtilityCustomerCredential/v2.0/) — The credential type used in the dataPayload example
- [DDM rain-probability-devkit](https://github.com/beckn/DDM/tree/feat/v2-migration-ameet/testnet/rain-probability-devkit) — Reference devkit pattern
