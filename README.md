# Portfolio rebalance

Solutions to the assignment in [`assignment.md`](assignment.md): a `Portfolio` that holds `Stock`s and a target allocation (e.g. 40% META, 60% AAPL), with a `rebalance` method that says what to sell and what to buy to match that allocation, and documentation of the thinking behind it.

There are two independent solutions. Each one has its own README with the details.

| | [`solution/`](solution/) | [`python-solution/`](python-solution/) |
| --- | --- | --- |
| Language | Ruby | Python |
| Models | Plain classes in a single file | pydantic models |
| Rebalance output | Money amount per stock (shares included for reference) | Number of shares per stock |
| Money math | `BigDecimal` | `float` |
| Validation | Explicit checks raising `ArgumentError` | pydantic field constraints and validators |
| Cash | None, sells pay for buys | None, sells pay for buys |
| Stock held but not in the allocation | Sold completely | Sold completely |
| Stock in the allocation but not held | Must be held with 0 shares to be bought | Not bought |
| Run | `ruby portfolio.rb` | `python demo.py` (needs a venv with pydantic) |

## Solutions

### Ruby: [`solution/`](solution/)

A single file, `portfolio.rb`, with the `Stock`, `Portfolio` and `Trade` classes plus a demo that checks its own results. The README explains the assumptions and trade-offs.

### Python: [`python-solution/`](python-solution/)

Written by hand, without AI help, to keep practicing and for fun. The models live in `schemas.py` and `demo.py` runs a portfolio of 5 stocks with random shares against an equally weighted allocation. The README has a mermaid diagram of the models.

## Both solutions share

- The rebalance only moves money between the stocks already in the portfolio. There are no deposits or withdrawals.
- Fractional shares are allowed.
- No fees, taxes or minimum order sizes.
