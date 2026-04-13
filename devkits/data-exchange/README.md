# Data Exchange Devkit

Beckn Protocol v2.0 devkit demonstrating **inline data delivery** via DDM's `DatasetItem` schema. Instead of downloading datasets from external URLs, data is embedded directly in beckn messages using the `dataPayload` attribute.

## Use Cases

| Use Case | BPP (Provider) | BAP (Consumer) | dataPayload | Description |
|----------|---------------|----------------|-------------|-------------|
| [usecase1](./usecase1/) | IntelliGrid AMI Services (AMISP) | BESCOM (discom) | `IES_Report` — 15-min kWh meter readings | AMI meter data exchange under existing contract |
| [usecase2](./usecase2/) | BESCOM (discom) | APERC (state regulator) | `IES_ARR_Filing` — cost line items, fiscal years | ARR filing submission under regulatory mandate |

Both use cases share the same Docker infrastructure, adapter configs, and test scripts.

## Key Schemas

**DatasetItem** from [DDM](https://github.com/beckn/DDM) provides `dataPayload` for inline data delivery and `accessMethod` to declare delivery mode (`INLINE`, `DOWNLOAD`, `DATA_ENCLAVE`, `OFF_CHANNEL`).

**IES_Report** from [India Energy Stack](https://github.com/India-Energy-Stack/ies-docs) carries meter telemetry in OpenADR 3.1.0 format.

**IES_ARR_Filing** from [India Energy Stack](https://github.com/India-Energy-Stack/ies-docs) carries Aggregate Revenue Requirement filings with fiscal year line items.

## Transaction Flow

```
BPP (Provider)      Catalog Service     Discovery Service       BAP (Consumer)
    |                     |                    |                      |
    |-- publish --------->|                    |                      |
    |   (DatasetItem      |                    |                      |
    |    catalog)         |                    |                      |
    |                     |<-- subscribe ------|                      |
    |                     |   (catalog updates)|                      |
    |                     |                    |                      |
    |                     |                    |<---- discover -------|
    |                     |                    |     (search datasets)|
    |                     |                    |---- on_discover ---->|
    |                     |                    |     (catalog results)|
    |                     |                    |                      |
    |---------------------+--------------------+----------------------|
    |                  Direct BAP <-> BPP negotiation                 |
    |                                                                 |
    |<---- select (choose dataset + offer) --------------------------|
    |---- on_select (terms) ---------------------------------------->|
    |                                                                 |
    |<---- init (details) -------------------------------------------|
    |---- on_init (ready) ------------------------------------------>|
    |                                                                 |
    |<---- confirm --------------------------------------------------|
    |---- on_confirm (active) -------------------------------------->|
    |                                                                 |
    |<---- status (check delivery) ----------------------------------|
    |---- on_status (PROCESSING) ----------------------------------->|
    |                                                                 |
    |  +- Delivery mode A: URL download -------------------------+  |
    |  | on_status (DELIVERY_COMPLETE)                            |  |
    |  |   dataset:downloadUrl + dataset:checksum                 | >|
    |  +----------------------------------------------------------+  |
    |                                                                 |
    |  +- Delivery mode B: Inline dataPayload --------------------+  |
    |  | on_status (DELIVERY_COMPLETE)                            |  |
    |  |   dataPayload: IES_Report / IES_ARR_Filing               | >|
    |  +----------------------------------------------------------+  |
    |                                                                 |
    |<---- cancel ---------------------------------------------------|
    |---- on_cancel ------------------------------------------------>|
```

## Prerequisites

- Git, Docker, Docker Compose
- Postman (optional, for manual testing)

## Quick Start

```bash
# 1. Start infrastructure (shared across both use cases)
cd install
docker compose -f docker-compose-adapter.yml up -d

# 2. Verify services
curl http://localhost:8081/health   # BAP adapter
curl http://localhost:8082/health   # BPP adapter
curl http://localhost:3001/api/health  # BAP sandbox
curl http://localhost:3002/api/health  # BPP sandbox

# 3. Run tests
cd ..
./scripts/test-workflow.sh all        # both use cases (30 steps)
./scripts/test-workflow.sh usecase1   # AMI meter data only (15 steps)
./scripts/test-workflow.sh usecase2   # ARR filing only (15 steps)
```

## Repository Structure

```
data-exchange/
├── config/                              # Shared Onix adapter configs
│   ├── local-simple-bap.yaml            #   BAP adapter (port 8081)
│   ├── local-simple-bpp.yaml            #   BPP adapter (port 8082)
│   └── local-simple-routing-*.yaml      #   Routing rules
├── install/
│   └── docker-compose-adapter.yml       # Shared Docker services
├── scripts/
│   ├── test-workflow.sh                 # Curl-based test runner
│   └── generate_postman_collection.py   # Postman collection generator
├── usecase1/                            # AMISP → Discom (AMI meter data)
│   ├── examples/                        #   15 beckn 2.0 JSON payloads
│   ├── postman/                         #   data-exchange-usecase1.{BAP,BPP}-DEG
│   └── workflows/                       #   Arazzo 1.0.1 workflow spec
└── usecase2/                            # Discom → Regulator (ARR filing)
    ├── examples/                        #   15 beckn 2.0 JSON payloads
    ├── postman/                         #   data-exchange-usecase2.{BAP,BPP}-DEG
    └── workflows/                       #   Arazzo 1.0.1 workflow spec
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
python3 scripts/generate_postman_collection.py --role BAP            # both use cases
python3 scripts/generate_postman_collection.py --role BPP            # both use cases
python3 scripts/generate_postman_collection.py --role BAP --usecase usecase1  # one use case
```

## Related

- [DDM DatasetItem Schema](https://github.com/beckn/DDM/tree/main/specification/schema/DatasetItem/v1) — `dataPayload` and `accessMethod`
- [IES Core Schemas](../../specification/external/schema/ies/core/) — IES_Report, IES_Program, IES_Policy (OpenADR 3.1.0)
- [IES ARR Schemas](../../specification/external/schema/ies/arr/) — IES_ARR_Filing, IES_ARR_FiscalYear, IES_ARR_LineItem
- [India Energy Stack](https://github.com/India-Energy-Stack/ies-docs) — Upstream IES documentation
- beckn/beckn-onix#655 — ONIX regex engine issue with OpenADR duration patterns
