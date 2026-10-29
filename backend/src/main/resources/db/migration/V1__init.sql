CREATE TABLE users (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  full_name VARCHAR(120) NOT NULL,
  email VARCHAR(190) NOT NULL UNIQUE,
  phone VARCHAR(20) NULL,
  password_hash VARCHAR(100) NOT NULL,
  role ENUM('CUSTOMER','ADMIN') NOT NULL DEFAULT 'CUSTOMER',
  status ENUM('ACTIVE','LOCKED','DISABLED') NOT NULL DEFAULT 'ACTIVE',
  created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3)
);
CREATE TABLE bank_accounts (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  account_number CHAR(12) NOT NULL UNIQUE,
  customer_id BIGINT NOT NULL,
  account_type ENUM('SAVINGS','CURRENT') NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'USD',
  available_balance DECIMAL(19,4) NOT NULL DEFAULT 0,
  ledger_balance DECIMAL(19,4) NOT NULL DEFAULT 0,
  status ENUM('PENDING','ACTIVE','FROZEN','CLOSED') NOT NULL DEFAULT 'ACTIVE',
  created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  CONSTRAINT fk_acct_user FOREIGN KEY (customer_id) REFERENCES users(id),
  CONSTRAINT ck_nonneg CHECK (available_balance >= 0),
  INDEX idx_acct_customer (customer_id)
);
CREATE TABLE transactions (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  transaction_reference VARCHAR(40) NOT NULL UNIQUE,
  transaction_type ENUM('DEPOSIT','WITHDRAWAL','TRANSFER','REFUND','FEE') NOT NULL,
  status ENUM('PENDING','COMPLETED','FAILED','REVERSED') NOT NULL,
  description VARCHAR(255) NULL,
  created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  INDEX idx_tx_status_created (status, created_at)
);
CREATE TABLE transfers (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  transaction_id BIGINT NOT NULL UNIQUE,
  source_account_id BIGINT NOT NULL,
  destination_account_id BIGINT NOT NULL,
  amount DECIMAL(19,4) NOT NULL,
  fee DECIMAL(19,4) NOT NULL DEFAULT 0,
  idempotency_key VARCHAR(64) NOT NULL,
  initiated_by BIGINT NOT NULL,
  created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  completed_at TIMESTAMP(3) NULL,
  CONSTRAINT fk_tr_tx FOREIGN KEY (transaction_id) REFERENCES transactions(id),
  CONSTRAINT fk_tr_src FOREIGN KEY (source_account_id) REFERENCES bank_accounts(id),
  CONSTRAINT fk_tr_dst FOREIGN KEY (destination_account_id) REFERENCES bank_accounts(id),
  CONSTRAINT fk_tr_user FOREIGN KEY (initiated_by) REFERENCES users(id),
  CONSTRAINT ck_tr_amount CHECK (amount > 0),
  UNIQUE KEY uq_idem (initiated_by, idempotency_key)
);
CREATE TABLE ledger_entries (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  transaction_id BIGINT NOT NULL,
  account_id BIGINT NOT NULL,
  entry_type ENUM('DEBIT','CREDIT') NOT NULL,
  amount DECIMAL(19,4) NOT NULL,
  currency CHAR(3) NOT NULL,
  created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  CONSTRAINT fk_le_tx FOREIGN KEY (transaction_id) REFERENCES transactions(id),
  CONSTRAINT fk_le_acct FOREIGN KEY (account_id) REFERENCES bank_accounts(id),
  CONSTRAINT ck_le_amount CHECK (amount > 0),
  INDEX idx_le_acct_created (account_id, created_at)
);
-- Ledger is append-only: block updates and deletes.
CREATE TRIGGER ledger_no_update BEFORE UPDATE ON ledger_entries FOR EACH ROW
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ledger_entries is immutable';
CREATE TRIGGER ledger_no_delete BEFORE DELETE ON ledger_entries FOR EACH ROW
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ledger_entries is immutable';
CREATE TABLE deposits (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  transaction_id BIGINT NOT NULL UNIQUE,
  account_id BIGINT NOT NULL,
  amount DECIMAL(19,4) NOT NULL,
  funding_source VARCHAR(80) NOT NULL,
  verification_status ENUM('SIMULATED','PENDING','VERIFIED','REJECTED') NOT NULL DEFAULT 'SIMULATED',
  created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  FOREIGN KEY (transaction_id) REFERENCES transactions(id),
  FOREIGN KEY (account_id) REFERENCES bank_accounts(id)
);
CREATE TABLE withdrawals (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  transaction_id BIGINT NOT NULL UNIQUE,
  account_id BIGINT NOT NULL,
  amount DECIMAL(19,4) NOT NULL,
  payout_reference VARCHAR(80) NULL,
  status ENUM('SIMULATED','PENDING','PAID','REJECTED') NOT NULL DEFAULT 'SIMULATED',
  created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  FOREIGN KEY (transaction_id) REFERENCES transactions(id),
  FOREIGN KEY (account_id) REFERENCES bank_accounts(id)
);
CREATE TABLE audit_logs (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  actor_user_id BIGINT NULL,
  action VARCHAR(80) NOT NULL,
  entity_type VARCHAR(60) NOT NULL,
  entity_id VARCHAR(60) NULL,
  reason VARCHAR(255) NULL,
  outcome ENUM('SUCCESS','FAILURE') NOT NULL,
  created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  INDEX idx_audit_actor (actor_user_id, created_at),
  INDEX idx_audit_entity (entity_type, entity_id)
);
CREATE TABLE refresh_tokens (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT NOT NULL,
  token_hash CHAR(64) NOT NULL UNIQUE,
  expires_at TIMESTAMP(3) NOT NULL,
  revoked_at TIMESTAMP(3) NULL,
  created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  FOREIGN KEY (user_id) REFERENCES users(id),
  INDEX idx_rt_user (user_id)
);
CREATE TABLE password_reset_tokens (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT NOT NULL,
  token_hash CHAR(64) NOT NULL UNIQUE,
  expires_at TIMESTAMP(3) NOT NULL,
  used_at TIMESTAMP(3) NULL,
  created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  FOREIGN KEY (user_id) REFERENCES users(id)
);
CREATE TABLE notifications (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT NOT NULL,
  category VARCHAR(40) NOT NULL,
  message VARCHAR(255) NOT NULL,
  read_at TIMESTAMP(3) NULL,
  created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  FOREIGN KEY (user_id) REFERENCES users(id),
  INDEX idx_notif_user (user_id, read_at)
);
CREATE TABLE settings (
  setting_key VARCHAR(60) PRIMARY KEY,
  setting_value VARCHAR(120) NOT NULL
);
INSERT INTO settings VALUES ('transfer.max_amount','10000.00'),('transfer.daily_limit','25000.00');
