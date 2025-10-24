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
