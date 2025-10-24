#!/usr/bin/env bash
set -euo pipefail

# Create workspace
mkdir -p ~/ai-trader
cd ~/ai-trader
git init -b main

# Ensure directories exist before writing heredocs
mkdir -p common common/schemas docs/RUNBOOKS out data/parquet logs services

# Write files (each heredoc corresponds to a file created above)
cat > common/config.yaml <<'EOF'
# common/config.yaml
# Template configuration for AI-Trader — do NOT put secrets here.
# Replace placeholders in .env (see .env.sample) and use env interpolation where required.

project:
  name: ai-trader
  root: /var/www/vhosts/snapdiscounts.nl/ai-trader
  venv: /var/www/vhosts/snapdiscounts.nl/ai-trader/.venv
  user: snapdiscounts
  group: psacln
  parquet_root: /var/www/vhosts/snapdiscounts.nl/ai-trader/data/parquet
  logs_root: /var/www/vhosts/snapdiscounts.nl/ai-trader/logs

redis:
  host: localhost
  port: 6379
  db: 0
  streams:
    ws_events_mini_ticker: ws_events:mini_ticker
    ws_events_bbo: ws_events:bbo
    ws_events_depth10: ws_events:depth10
    selection_out: selection.out
    features_out: features.out
    order_cmds: order_cmds
    risk_out: risk.out
    exec_events: exec.events
    fills_events: fills.events
    alerts: alerts

parquet:
  layout: "date=YYYY-MM-DD/symbol=SYMBOL/"
  required_tables:
    - mini_ticker.parquet
    - bbo.parquet
    - depth10.parquet
    - features.parquet

exchange:
  name: bitvavo
  operator_id: 1702
  sdk_package: python-bitvavo-api==1.4.3
  min_notional_eur: 5.0
  excluded_symbols:
    - BTC
    - ETH
    - SOL
    - USDT
    - USDC
    - DAI
    - TUSD
  canary_pairs:
    - FART-EUR
    - OPEN-EUR
    - ADA-EUR

risk:
  total_exposure_pct: 100
  per_symbol_exposure_pct: 25
  day_kill_threshold_pct: -5
  price_band_bps: 15
  exploration_cap_pct: 25
  liquidity_guards:
    turnover_eur_60m_min: 25000
    spread_bps_max: 20
    trades_per_min_min: 5
    depth_at_10bps_min_eur: 1000
    completeness_pct_min: 95

logging:
  format: json
  timestamp: utc_ms
  rotate_max_bytes: 104857600  # 100MB
  rotate_days: 7

ci:
  lint:
    - black
    - ruff
    - mypy
  test:
    - pytest
    - jsonschema

# End of config template
EOF

cat > common/schemas/events.json <<'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "AI-Trader Events v1",
  "type": "object",
  "oneOf": [
    {
      "properties": {
        "type": { "const": "mini_ticker" },
        "ts": { "type": "integer" },
        "symbol": { "type": "string" },
        "price": { "type": "number" },
        "volume": { "type": "number" },
        "raw": { "type": "object" }
      },
      "required": ["type", "ts", "symbol", "price"]
    },
    {
      "properties": {
        "type": { "const": "bbo" },
        "ts": { "type": "integer" },
        "symbol": { "type": "string" },
        "best_bid": { "type": "number" },
        "best_ask": { "type": "number" },
        "bid_size": { "type": "number" },
        "ask_size": { "type": "number" },
        "raw": { "type": "object" }
      },
      "required": ["type", "ts", "symbol", "best_bid", "best_ask"]
    },
    {
      "properties": {
        "type": { "const": "depth10" },
        "ts": { "type": "integer" },
        "symbol": { "type": "string" },
        "bids": {
          "type": "array",
          "items": {
            "type": "array",
            "minItems": 2,
            "maxItems": 2
          }
        },
        "asks": {
          "type": "array",
          "items": {
            "type": "array",
            "minItems": 2,
            "maxItems": 2
          }
        },
        "raw": { "type": "object" }
      },
      "required": ["type", "ts", "symbol", "bids", "asks"]
    },
    {
      "properties": {
        "type": { "const": "selection" },
        "ts": { "type": "integer" },
        "symbols": {
          "type": "array",
          "items": { "type": "string" }
        },
        "metrics": { "type": "object" }
      },
      "required": ["type", "ts", "symbols"]
    },
    {
      "properties": {
        "type": { "const": "features" },
        "ts": { "type": "integer" },
        "symbol": { "type": "string" },
        "features": { "type": "object" }
      },
      "required": ["type", "ts", "symbol", "features"]
    }
  ]
}
EOF

cat > common/schemas/db.sql <<'EOF'
-- common/schemas/db.sql
-- MariaDB DDL for AI-Trader (schema only). DO NOT store credentials here.
-- Run as a privileged DB user and create a DB user with secure password (replace placeholders).

CREATE DATABASE IF NOT EXISTS ai_trader
  DEFAULT CHARACTER SET = 'utf8mb4'
  DEFAULT COLLATE = 'utf8mb4_unicode_ci';

USE ai_trader;

-- Users/credentials: create externally; do not embed passwords here.
-- Example (replace <PASSWORD> before running):
-- CREATE USER 'ai_trader'@'localhost' IDENTIFIED BY '<PASSWORD>';
-- GRANT ALL PRIVILEGES ON ai_trader.* TO 'ai_trader'@'localhost';

-- Orders table
CREATE TABLE IF NOT EXISTS orders (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  client_order_id VARCHAR(64) NOT NULL UNIQUE,
  symbol VARCHAR(32) NOT NULL,
  side ENUM('buy','sell') NOT NULL,
  qty DECIMAL(30,12) NOT NULL,
  price DECIMAL(30,12) NULL,
  type ENUM('limit','market') DEFAULT 'limit',
  status VARCHAR(32) NOT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  meta JSON NULL,
  INDEX (symbol),
  INDEX (status)
) ENGINE=InnoDB;

-- Fills table
CREATE TABLE IF NOT EXISTS fills (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  order_id BIGINT NOT NULL,
  fill_id VARCHAR(64) NOT NULL,
  symbol VARCHAR(32) NOT NULL,
  side ENUM('buy','sell') NOT NULL,
  qty DECIMAL(30,12) NOT NULL,
  price DECIMAL(30,12) NOT NULL,
  fee DECIMAL(30,12) DEFAULT 0,
  ts DATETIME(6) NOT NULL,
  raw JSON NULL,
  FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
  INDEX (symbol),
  INDEX (ts)
) ENGINE=InnoDB;

-- Positions table
CREATE TABLE IF NOT EXISTS positions (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  symbol VARCHAR(32) NOT NULL UNIQUE,
  qty DECIMAL(30,12) NOT NULL,
  avg_entry DECIMAL(30,12) NOT NULL,
  unrealized_pnl DECIMAL(30,12) DEFAULT 0,
  realized_pnl DECIMAL(30,12) DEFAULT 0,
  updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  meta JSON NULL
) ENGINE=InnoDB;

-- Metrics / runs
CREATE TABLE IF NOT EXISTS runs (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  run_date DATE NOT NULL,
  metrics JSON NOT NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB;

-- Decisions table (AI decisions)
CREATE TABLE IF NOT EXISTS decisions (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  ts DATETIME(6) NOT NULL,
  symbol VARCHAR(32) NOT NULL,
  decision JSON NOT NULL,
  ai_version VARCHAR(64),
  explain_tag VARCHAR(128),
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB;

-- Alerts table
CREATE TABLE IF NOT EXISTS alerts (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  ts DATETIME(6) NOT NULL,
  alert_type VARCHAR(64) NOT NULL,
  severity VARCHAR(16) NOT NULL,
  message TEXT,
  meta JSON NULL,
  created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
) ENGINE=InnoDB;

-- End of DDL
EOF

cat > .env.sample <<'EOF'
# .env.sample — copy to .env and fill secrets. DO NOT COMMIT .env with secrets.
# Example:
# cp .env.sample .env
# Edit .env and secure with filesystem perms (owner:snapdiscounts group:psacln, 0600)

# LIVE flag controls whether real orders are placed. 0 = dry-run, 1 = live.
LIVE=0

# Bitvavo (live) — provide real keys only on secure host
BITVAVO_API_KEY_LIVE=
BITVAVO_API_SECRET_LIVE=

# Bitvavo (data-only) — optionally lower-permission keys
BITVAVO_API_KEY_DATA=
BITVAVO_API_SECRET_DATA=

# Database connection — replace placeholders; avoid embedding in repo
DB_HOST=localhost
DB_PORT=3306
DB_NAME=ai_trader
DB_USER=ai_trader
DB_PASS=<REDACTED_PASSWORD>

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_DB=0

# Paths (override if needed)
PROJECT_ROOT=/var/www/vhosts/snapdiscounts.nl/ai-trader
VENV_PATH=/var/www/vhosts/snapdiscounts.nl/ai-trader/.venv
PARQUET_ROOT=/var/www/vhosts/snapdiscounts.nl/ai-trader/data/parquet
LOGS_ROOT=/var/www/vhosts/snapdiscounts.nl/ai-trader/logs

# Other operational knobs
MIN_NOTIONAL_EUR=5.0
EXCLUDED_SYMBOLS=BTC,ETH,SOL,USDT,USDC,DAI,TUSD
OPERATOR_ID=1702

# End of sample
EOF

# Create runbook docs (only first two included here; rest follow same pattern)
mkdir -p docs/RUNBOOKS
cat > docs/RUNBOOKS/step00_foundation_buildplan.md <<'EOF'
# Step 00 — Foundation

Short title
- Foundation: project layout, configs, schemas, initial checks

Goal
- Create project skeleton, canonical config templates, JSON schema, DB DDL and .env.sample.
- Verify basic connectivity: Redis, MariaDB, writable Parquet dir.
- Prepare venv and basic Python deps list.

Inputs
- This build plan document.
- Server access as root (for system user/group creation) and as snapdiscounts user for file ownership.
- Access to install Python packages (internet).

Outputs / Deliverables
- Files:
  - .env.sample
  - common/config.yaml
  - common/schemas/events.json
  - common/schemas/db.sql
  - Directory tree:
    - data/parquet/.keep
    - logs/.keep
    - services/.keep
    - docs/RUNBOOKS/.keep
- Verification artifacts:
  - Redis PONG
  - DB SELECT 1
  - touch file in PARQUET_ROOT

Definition of Done (DoD)
- All files exist at project root.
- Redis responds to PING (PONG).
- MariaDB reachable with provided DB_USER (password configured out-of-band).
- PARQUET_ROOT writable by snapdiscounts:psacln.
- .venv path present and python -V returns 3.12.x when activated.

Required secrets / config
- DB credentials (configure in .env — placeholder in .env.sample only).
- Bitvavo keys NOT required for foundation.

Commands / Example actions
- Create dirs and .keep:
  - sudo mkdir -p /var/www/vhosts/snapdiscounts.nl/ai-trader/{data/parquet,logs,services,docs/RUNBOOKS}
  - sudo chown -R snapdiscounts:psacln /var/www/vhosts/snapdiscounts.nl/ai-trader
  - sudo -u snapdiscounts touch /var/www/vhosts/snapdiscounts.nl/ai-trader/data/parquet/.keep
  - sudo -u snapdiscounts touch /var/www/vhosts/snapdiscounts.nl/ai-trader/logs/.keep
- Verify Redis:
  - redis-cli -h ${REDIS_HOST:-localhost} -p ${REDIS_PORT:-6379} PING
- Verify DB:
  - mysql -h localhost -u ai_trader -p -e "SELECT 1;"
- Setup venv (as snapdiscounts):
  - python3.12 -m venv /var/www/vhosts/snapdiscounts.nl/ai-trader/.venv
  - source /var/www/vhosts/snapdiscounts.nl/ai-trader/.venv/bin/activate
  - pip install python-bitvavo-api==1.4.3 redis orjson pyarrow pyyaml jsonschema

Tests (unit / integration)
- Integration:
  - test_integration_redis_ping: assert redis.ping() == True
  - test_integration_db_connect: assert execute("SELECT 1") == [(1,)]
  - test_parquet_dir_writable: touch PARQUET_ROOT/testfile

# truncated for brevity in this script; full runbooks can be added similarly
EOF

# Create .keep files for expected directories
mkdir -p data/parquet logs services docs/RUNBOOKS out
touch data/parquet/.keep logs/.keep services/.keep docs/RUNBOOKS/.keep out/.keep

# Set ownership and permissions (adjust sudo usage if running on remote server)
# By default this sets ownership to current user:staff; on server change to snapdiscounts:psacln as needed.
sudo chown -R "$(whoami)":staff . || true
find . -type f -exec chmod 0644 {} \; || true
chmod 0600 .env.sample || true

# Commit to git
git add .
git commit -m "Add runbooks, schemas, and foundation templates for AI-Trader (no secrets)"

# Create zip
cd ..
zip -r ai-trader.zip ai-trader || true

echo "Repository created in ~/ai-trader and ai-trader.zip created in $(pwd)"
