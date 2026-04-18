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
    |                     |<-- subscribe ------|                      |
    |                     |   (catalog updates)|                      |
    |                     |                    |                      |
    |-- publish --------->|                    |                      |
    |   (DatasetItem      |                    |                      |
    |    catalog)         |                    |                      |
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

## Run end-to-end over the public internet

By default BAP and BPP talk to each other on the docker bridge using container
DNS names (`onix-bap`, `onix-bpp`). To prove the protocol works exactly the
same when the two adapters reach each other over the public internet, the
devkit ships an opt-in mode that exposes both adapters through a single ngrok
tunnel and a path-routing reverse proxy (Caddy).

Path layout under one public URL:

```
https://<public-host>/bap/*   →  beckn-router  →  onix-bap:8081
https://<public-host>/bpp/*   →  beckn-router  →  onix-bpp:8082
```

Beckn URIs become:

```
bapUri = https://<public-host>/bap/receiver
bppUri = https://<public-host>/bpp/receiver
```

Body-digest signing is unaffected by the URL change, so registry entries for
`bap.example.com` / `bpp.example.com` keep working as-is.

### One-time prerequisites

1. ngrok account + authtoken (free plan is enough).
2. Copy the ngrok config template and fill in your token:

   ```bash
   mkdir -p "$HOME/Library/Application Support/ngrok"
   cp install/ngrok.yml.example "$HOME/Library/Application Support/ngrok/ngrok.yml"
   # edit the file: paste your authtoken; optionally set `domain:` to your
   # reserved ngrok-free.dev subdomain for a stable URL across restarts.
   ```

   Validate: `ngrok config check`.

### Per-session steps

```bash
# 1. Start the standard testnet
cd install
docker compose -f docker-compose-adapter.yml up -d

# 2. Start the path-routing proxy (opt-in profile, listens on :9000)
docker compose -f docker-compose-adapter.yml --profile internet up -d beckn-router
curl -s http://localhost:9000   # → "beckn-router ok"

# 3. Open the tunnel (foreground in its own terminal, or backgrounded)
ngrok start --all
# Note the public URL printed by ngrok; export it:
export PUBLIC_URL=https://<your-subdomain>.ngrok-free.dev

# 4. Run the workflows over the public URL.
#    The script rewrites docker-DNS bapUri/bppUri in each payload on the fly,
#    so example files on disk stay untouched.
cd ..
PUBLIC_URL=$PUBLIC_URL ./scripts/test-workflow.sh usecase1
PUBLIC_URL=$PUBLIC_URL ./scripts/test-workflow.sh usecase2
PUBLIC_URL=$PUBLIC_URL ./scripts/test-workflow.sh all
```

### Verify the traffic really left the box

Open the ngrok inspector at `http://localhost:4040`. For each transactional
step you should see three rows recorded by the public tunnel:

| Direction | Path |
|---|---|
| your curl → BAP | `POST /bap/caller/<action>` |
| **BAP → BPP (over internet)** | `POST /bpp/receiver/<action>` |
| **BPP → BAP callback (over internet)** | `POST /bap/receiver/on_<action>` |

If the second and third rows appear, the BAP↔BPP hop is genuinely traversing
the public internet rather than the docker bridge.

### Notes and limitations

- The two URIs share a hostname and differ only by path prefix. From the beckn
  protocol's point of view they are still two distinct URIs and the test is
  valid. For two truly distinct hostnames, switch the tunnel to Cloudflare
  Tunnel (`cloudflared tunnel --url http://localhost:8081` and `:8082`, two
  free random `*.trycloudflare.com` URLs) or move ngrok to a paid plan.
- The `subscribe` and `discover` steps call out to external catalog/discovery
  services (`fabric.nfh.global`, `34.14.221.66.sslip.io`); their outcome is
  independent of the over-internet wiring tested here.
- The docker bridge between `onix-bap` and `onix-bpp` is still in place — it is
  the routing rule (`targetType: bpp`, which dereferences the context's
  `bppUri`) that keeps traffic on the public path. To make isolation airtight
  for a stricter test, split the compose into two projects on separate
  networks.

### Cleanup

```bash
# Stop the proxy and tunnel
cd install
docker compose -f docker-compose-adapter.yml --profile internet down
# kill the ngrok agent in its terminal (Ctrl-C) or:  pkill -f 'ngrok start'
```

## Regenerating Postman Collections

```bash
python3 scripts/generate_postman_collection.py --role BAP            # both use cases
python3 scripts/generate_postman_collection.py --role BPP            # both use cases
python3 scripts/generate_postman_collection.py --role BAP --usecase usecase1  # one use case
```

## Related

- [DDM DatasetItem Schema](https://github.com/beckn/DDM/tree/main/specification/schema/DatasetItem/v1) — `dataPayload` and `accessMethod`
- [IES Core Schemas](https://github.com/beckn/DEG/tree/ies-specs/specification/external/schema/ies/core) — IES_Report, IES_Program, IES_Policy (OpenADR 3.1.0)
- [IES ARR Schemas](https://github.com/beckn/DEG/tree/ies-specs/specification/external/schema/ies/arr) — IES_ARR_Filing, IES_ARR_FiscalYear, IES_ARR_LineItem
- [India Energy Stack (ies-docs)](https://github.com/India-Energy-Stack/ies-docs) — Upstream IES documentation
- beckn/beckn-onix#655 — ONIX regex engine issue with OpenADR duration patterns
