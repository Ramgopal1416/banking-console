package com.bank.console.transfer;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.List;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;

/**
 * Atomic internal transfer. Rows are locked in ascending id order (prevents deadlocks),
 * ownership/status/balance are checked under the lock, and ledger entries are written
 * in the same DB transaction as the balance updates. Any exception rolls everything back.
 * NOTE: simulated internal transfer only - not a real payment.
 */
@Service
public class TransferService {

  public record TransferCommand(Long userId, Long sourceAccountId, String destinationAccountNumber,
                                BigDecimal amount, String description, String idempotencyKey) {}
  public record TransferResult(String reference, String status, boolean replayed) {}
  public static class TransferException extends RuntimeException {
    public TransferException(String m) { super(m); }
  }

  private record Acct(long id, long customerId, String number, String currency, BigDecimal available, String status) {}

  private final JdbcTemplate jdbc;
  private final BigDecimal maxAmount;

  public TransferService(JdbcTemplate jdbc, @Value("${app.transfer.max-amount}") BigDecimal maxAmount) {
    this.jdbc = jdbc;
    this.maxAmount = maxAmount;
  }

  @Transactional(isolation = Isolation.READ_COMMITTED)
  public TransferResult transfer(TransferCommand c) {
    BigDecimal amount = c.amount() == null ? null : c.amount().setScale(4, RoundingMode.HALF_EVEN);
    if (amount == null || amount.signum() <= 0) throw new TransferException("Amount must be greater than zero");
    if (amount.compareTo(maxAmount) > 0) throw new TransferException("Amount exceeds transfer limit");
    if (c.destinationAccountNumber() == null || !c.destinationAccountNumber().matches("\\d{12}"))
      throw new TransferException("Malformed account number");
    if (c.idempotencyKey() == null || c.idempotencyKey().isBlank()) throw new TransferException("Idempotency key required");

    // Idempotent replay: same user + key returns the original result.
    List<TransferResult> existing = jdbc.query(
        "SELECT t.transaction_reference, t.status FROM transfers f JOIN transactions t ON t.id=f.transaction_id " +
        "WHERE f.initiated_by=? AND f.idempotency_key=?",
        (rs, i) -> new TransferResult(rs.getString(1), rs.getString(2), true), c.userId(), c.idempotencyKey());
    if (!existing.isEmpty()) return existing.get(0);

    Long destId = jdbc.query("SELECT id FROM bank_accounts WHERE account_number=?",
        rs -> rs.next() ? rs.getLong(1) : null, c.destinationAccountNumber());
    if (destId == null) throw new TransferException("Destination account not found");
    if (destId.equals(c.sourceAccountId())) throw new TransferException("Source and destination must differ");

    // Lock both rows in id order.
    long lo = Math.min(destId, c.sourceAccountId()), hi = Math.max(destId, c.sourceAccountId());
    List<Acct> locked = jdbc.query(
        "SELECT id, customer_id, account_number, currency, available_balance, status FROM bank_accounts " +
        "WHERE id IN (?,?) ORDER BY id FOR UPDATE",
        (rs, i) -> new Acct(rs.getLong(1), rs.getLong(2), rs.getString(3), rs.getString(4),
            rs.getBigDecimal(5), rs.getString(6)), lo, hi);
    Acct src = locked.stream().filter(a -> a.id() == c.sourceAccountId()).findFirst()
        .orElseThrow(() -> new TransferException("Source account not found"));
    Acct dst = locked.stream().filter(a -> a.id() == destId).findFirst().orElseThrow();

    if (src.customerId() != c.userId()) throw new TransferException("Source account not found"); // no info leak
    if (!"ACTIVE".equals(src.status()) || !"ACTIVE".equals(dst.status()))
      throw new TransferException("Both accounts must be active");
    if (!src.currency().equals(dst.currency())) throw new TransferException("Currency mismatch");
    if (src.available().compareTo(amount) < 0) throw new TransferException("Insufficient funds");

    String ref = "TXN-" + UUID.randomUUID().toString().replace("-", "").substring(0, 16).toUpperCase();
    try {
      jdbc.update("INSERT INTO transactions (transaction_reference, transaction_type, status, description) VALUES (?, 'TRANSFER', 'COMPLETED', ?)",
          ref, c.description());
      Long txId = jdbc.queryForObject("SELECT id FROM transactions WHERE transaction_reference=?", Long.class, ref);
      jdbc.update("INSERT INTO transfers (transaction_id, source_account_id, destination_account_id, amount, idempotency_key, initiated_by, completed_at) VALUES (?,?,?,?,?,?,CURRENT_TIMESTAMP(3))",
          txId, src.id(), dst.id(), amount, c.idempotencyKey(), c.userId());
      jdbc.update("UPDATE bank_accounts SET available_balance=available_balance-?, ledger_balance=ledger_balance-? WHERE id=?", amount, amount, src.id());
      jdbc.update("UPDATE bank_accounts SET available_balance=available_balance+?, ledger_balance=ledger_balance+? WHERE id=?", amount, amount, dst.id());
      jdbc.update("INSERT INTO ledger_entries (transaction_id, account_id, entry_type, amount, currency) VALUES (?,?,'DEBIT',?,?)", txId, src.id(), amount, src.currency());
      jdbc.update("INSERT INTO ledger_entries (transaction_id, account_id, entry_type, amount, currency) VALUES (?,?,'CREDIT',?,?)", txId, dst.id(), amount, dst.currency());
    } catch (DuplicateKeyException e) {
      throw new TransferException("Duplicate request"); // concurrent replay lost the race; client retries and gets the replay
    }
    return new TransferResult(ref, "COMPLETED", false);
  }
}
