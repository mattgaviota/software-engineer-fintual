import random

import schemas


def setup() -> schemas.Portfolio:
    stocks = [
        schemas.Stock(symbol="NVDA", current_price=233.95),
        schemas.Stock(symbol="AAPL", current_price=333.69),
        schemas.Stock(symbol="MSFT", current_price=517.53),
        schemas.Stock(symbol="AMZN", current_price=251.52),
        schemas.Stock(symbol="GOOGL", current_price=343.50),
    ]
    holdings = [
        schemas.Holding(stock=stock, amount=random.randint(30, 150)) for stock in stocks
    ]
    allocation = {
        stock.symbol: schemas.Allocation(stock=stock, percentage=1.0 / len(stocks))
        for stock in stocks
    }
    return schemas.Portfolio(holdings=holdings, allocation=schemas.Target(allocation))


def main():
    portfolio = setup()
    print("Current Portfolio")
    print(f"Balance: ${portfolio.get_balance():,}")
    print(f"Holdings: {portfolio.holdings}")
    print(f"Allocated: {portfolio.allocated()}")
    print(f"Target Allocation: {portfolio.allocation}")
    print(f"Rebalance: {portfolio.rebalance()}")


if __name__ == "__main__":
    main()
