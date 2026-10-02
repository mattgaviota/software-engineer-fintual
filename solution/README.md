# Portfolio rebalance

A `Portfolio` holds `Stock`s and a target allocation (e.g. 40% META, 60% AAPL). `Portfolio#rebalance` tells you how much money of each stock to sell and to buy so the portfolio matches that allocation.

## Run

```bash
ruby portfolio.rb
```

Needs Ruby 3.x and nothing else (`bigdecimal` ships with Ruby). The demo at the bottom of the file runs several scenarios and checks every result, then prints `All checks passed`.

```ruby
meta = Stock.new("META", 500)
aapl = Stock.new("AAPL", 200)

portfolio = Portfolio.new(
  holdings:   { meta => 10, aapl => 20 },     # 5000 + 4000 = 9000
  allocation: { "META" => 0.4, "AAPL" => 0.6 } # target 3600 / 5400
)

portfolio.rebalance
# SELL META   1400.00  (2.8000 shares)
# BUY  AAPL   1400.00  (7.0000 shares)
```

## How it works

1. Read every price once (`current_prices`), so the whole calculation uses one moment in time.
2. Value each position at `shares * price` and add them up to get the total.
3. A stock's target value is `total * target weight`.
4. `delta = target value - current value`. A positive delta means buy and a negative one means sell. Differences under one cent are skipped.
5. Sells are listed first, because in practice you sell to raise the money for the buys.

There's no cash, so the deltas add up to zero and the sells pay exactly for the buys.

## Assumptions

- **No cash.** The portfolio's value is the value of its stocks. A rebalance only moves money between stocks; it never adds or withdraws any.
- **Fractional shares are allowed.** The output is an amount of money per stock, since investment apps commonly let you invest by amount rather than by share count. The share equivalent is included for reference.
- **Prices are one snapshot.** `Stock#current_price` returns the last available price. It can be a fixed number or a callable such as a lambda that calls a market data API.
- **No fees, taxes, spreads or minimum order sizes.**
- **A held stock that has no target weight is at 0%**, so it is sold completely. This is the natural reading of "the distribution the portfolio is aiming for".
- **A stock you want but don't own yet** must still be passed in `holdings` with 0 shares, because the portfolio needs its price to buy it. Leaving it out raises a clear error.

## Decisions and trade-offs

| Decision | Why | Trade-off |
| --- | --- | --- |
| Return amounts of money, not whole shares | Exact and simple. Brokers and robo-advisors buy by amount. | With whole shares only, you'd have to round and accept a small drift. That's not handled here. |
| Raise `ArgumentError` on invalid input (weights not adding up to 100%, negative weights or shares, non-positive prices, duplicate stocks, allocated stock missing from holdings) | A wrong allocation is a bug or a user mistake. Silently normalizing 50/40 into 55.6/44.4 would invest money in a way nobody asked for. | Callers have to send clean data. |
| Small tolerance (`0.000001`) on the weight sum, then divide by the sum | Weights like 1/3 + 1/3 + 1/3 can't be represented exactly. The tolerance accepts them, and dividing by the sum keeps buys equal to sells. | Errors smaller than the tolerance are absorbed instead of rejected. |
| `BigDecimal` for money and weights | Floats make 0.1 + 0.2 != 0.3, so buys and sells would stop matching. Amounts are rounded to cents only when printed. | A bit more verbose than floats. |
| Rebalance fully every time, skipping only sub-cent differences | It's what the assignment asks for. | Real systems use drift bands (e.g. only rebalance when a weight is more than 5% away from target) to avoid many small trades and their costs. That would be a `threshold:` parameter on `rebalance`. |
| A price source can be injected into `Stock` | Keeps `Portfolio` independent of where prices come from and easy to test. | None worth mentioning. |
| One file with a self-checking demo instead of a test suite | Matches the "simple" scope of the assignment and runs with no dependencies. | For production, the scenarios would move to Minitest/RSpec. |

## Possible extensions

- A cash position, to support deposits and withdrawals: a deposit is "buy only", a withdrawal is "sell only".
- Whole-share rounding, with a greedy pass to spend the leftover cash.
- Drift thresholds and minimum order sizes.
- Taking fees and taxes into account, e.g. prefer buying with new deposits over selling positions with gains.
