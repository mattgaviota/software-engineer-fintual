from typing import Literal
import math

from pydantic import BaseModel, Field, RootModel, model_validator
from typing_extensions import Self


class Stock(BaseModel):
    symbol: str
    current_price: float = Field(gt=0)


class Holding(BaseModel):
    stock: Stock
    amount: float = Field(gt=0)

    def current_balance(self) -> float:
        return self.stock.current_price * self.amount

    def __repr__(self) -> str:
        return f"\nStock: {self.stock.symbol} - Amount: {self.amount} - Value: ${self.current_balance():,.2f}\n"


class Allocation(BaseModel):
    stock: Stock
    percentage: float = Field(ge=0, le=1)

    def __repr__(self) -> str:
        return f"Stock: {self.stock.symbol} {self.percentage*100}%"

    def __str__(self) -> str:
        return f"Stock: {self.stock.symbol} {self.percentage*100}%"


class Target(RootModel):
    root: dict[str, Allocation]

    def __iter__(self):
        return iter(self.root)

    def __getitem__(self, symbol: str) -> Allocation | None:
        return self.root.get(symbol)

    def __str__(self) -> str:
        repr = "\n"
        for allocation in self.root.values():
            repr += f"{allocation}\n"
        return repr

    @model_validator(mode="after")
    def check_100_percentage(self) -> Self:
        total = sum([allocation.percentage for allocation in self.root.values()])
        if not math.isclose(total, 1, rel_tol=0.05):
            raise ValueError("Allocation must be 100%")
        return self


class Relocation(BaseModel):
    stock: Stock
    amount: float
    action: Literal["BUY", "SELL"]

    def __repr__(self) -> str:
        return f"{self.action} {self.amount} of {self.stock.symbol}"


class Portfolio(BaseModel):
    holdings: list[Holding]
    allocation: Target

    def rebalance(self) -> list[Relocation]:
        total_value = self.get_balance()
        result = []
        for holding in self.holdings:
            target_percentage = (
                self.allocation[holding.stock.symbol].percentage
                if self.allocation[holding.stock.symbol]
                else 0
            )
            target_value = (total_value * target_percentage) - holding.current_balance()
            action = "SELL"
            if target_value > 0:
                action = "BUY"
            action_amount = round(abs(target_value) / holding.stock.current_price, 2)
            result.append(
                Relocation(stock=holding.stock, amount=action_amount, action=action)
            )
        return result

    def allocated(self) -> Target:
        total_value = self.get_balance()
        allocation = {}
        for holding in self.holdings:
            allocation[holding.stock.symbol] = Allocation(
                stock=holding.stock,
                percentage=round(holding.current_balance() / total_value, 4),
            )
        return Target(allocation)

    def get_balance(self) -> float:
        balance = 0
        for stock in self.holdings:
            balance += stock.current_balance()
        return round(balance, 2)
