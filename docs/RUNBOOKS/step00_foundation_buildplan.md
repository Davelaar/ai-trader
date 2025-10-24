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
