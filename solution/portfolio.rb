# frozen_string_literal: true

# Portfolio rebalancing.
#
# The question being answered: "given what I hold today and the distribution I
# want, how much money of each stock do I have to sell and buy?"
#
# Approach in one paragraph:
#   1. Take ONE snapshot of every price, so all numbers come from the same moment.
#   2. Value each position (shares * price) and add them up: that's the total.
#   3. The target value of a stock is total * target weight.
#   4. delta = target value - current value. Positive -> buy, negative -> sell.
#   Since there is no cash, the money raised by the sells is exactly the money
#   spent on the buys (the deltas add up to zero).
#
# See README.md for the assumptions and trade-offs behind these decisions.

require "bigdecimal"
require "bigdecimal/util"

# Money and weights go through BigDecimal: with floats, 0.1 + 0.2 != 0.3, and
# rounding errors would show up as buys that don't match the sells.
module Decimal
  module_function

  def from(value)
    case value
    when Rational then value.to_d(20)
    when Float then value.to_d
    else BigDecimal(value.to_s)
    end
  rescue ArgumentError, TypeError, FloatDomainError
    raise ArgumentError, "not a number: #{value.inspect}"
  end
end

# A stock knows its ticker and how to get its last available price.
#
# The price can be a fixed number or anything that responds to #call (a lambda
# that calls a market data API, for example). That keeps the Portfolio
# independent of where prices come from.
class Stock
  attr_reader :symbol

  def initialize(symbol, price)
    @symbol = symbol.to_s.upcase
    @price_source = price.respond_to?(:call) ? price : -> { price }
  end

  def current_price
    price = Decimal.from(@price_source.call)
    raise ArgumentError, "price of #{symbol} must be positive, got #{price.to_s('F')}" unless price.positive?

    price
  end
end

# One instruction from the rebalance: sell or buy `amount` money of `symbol`.
# `shares` is the same amount expressed in (fractional) shares at the price used.
Trade = Struct.new(:symbol, :action, :amount, :shares, keyword_init: true) do
  def to_s
    format("%-4s %-6s %12.2f  (%.4f shares)", action.to_s.upcase, symbol, amount, shares)
  end
end

class Portfolio
  # Weights must add up to 1 within this margin. It only absorbs rounding noise
  # (e.g. three weights of 1/3); a real mistake such as 0.5 + 0.4 is rejected.
  WEIGHT_TOLERANCE = BigDecimal("0.000001")

  # Differences smaller than one cent are not worth a trade.
  MIN_TRADE_AMOUNT = BigDecimal("0.01")

  # holdings:   { Stock => shares }. A stock may be held with 0 shares; that is
  #             how a position we don't own yet (but want to) gets its price.
  # allocation: { "META" => 0.4, "AAPL" => 0.6 }. A held stock missing from the
  #             allocation has a target of 0%, so it is sold completely.
  def initialize(holdings:, allocation:)
    @stocks = {}
    @shares = {}
    holdings.each { |stock, quantity| add_holding(stock, quantity) }
    @allocation = allocation.to_h { |symbol, weight| [symbol.to_s.upcase, Decimal.from(weight)] }
    validate_allocation!
  end

  def total_value(prices = current_prices)
    @shares.sum(BigDecimal("0")) { |symbol, quantity| quantity * prices.fetch(symbol) }
  end

  # Current weight of each stock, e.g. { "META" => 0.5556, "AAPL" => 0.4444 }.
  def weights(prices = current_prices)
    total = total_value(prices)
    return @shares.transform_values { BigDecimal("0") } if total.zero?

    @shares.to_h { |symbol, quantity| [symbol, quantity * prices.fetch(symbol) / total] }
  end

  # Returns the list of trades that turn the current portfolio into the target
  # allocation, sells first (in practice you sell to get the money to buy).
  # An already balanced portfolio returns an empty list.
  def rebalance
    prices = current_prices
    total = total_value(prices)

    trades = @shares.filter_map do |symbol, quantity|
      delta = total * target_weight(symbol) - quantity * prices.fetch(symbol)
      next if delta.abs < MIN_TRADE_AMOUNT

      Trade.new(
        symbol: symbol,
        action: delta.positive? ? :buy : :sell,
        amount: delta.abs,
        shares: delta.abs.div(prices.fetch(symbol), 20)
      )
    end

    trades.sort_by { |trade| [trade.action == :sell ? 0 : 1, trade.symbol] }
  end

  private

  def add_holding(stock, quantity)
    raise ArgumentError, "holdings keys must be Stock objects, got #{stock.inspect}" unless stock.is_a?(Stock)
    raise ArgumentError, "#{stock.symbol} appears more than once in holdings" if @stocks.key?(stock.symbol)

    quantity = Decimal.from(quantity)
    raise ArgumentError, "shares of #{stock.symbol} can't be negative" if quantity.negative?

    @stocks[stock.symbol] = stock
    @shares[stock.symbol] = quantity
  end

  def validate_allocation!
    raise ArgumentError, "allocation can't be empty" if @allocation.empty?

    @allocation.each do |symbol, weight|
      raise ArgumentError, "weight of #{symbol} can't be negative" if weight.negative?
      unless @stocks.key?(symbol)
        raise ArgumentError, "#{symbol} is in the allocation but not in holdings (add it with 0 shares)"
      end
    end

    sum = @allocation.values.sum(BigDecimal("0"))
    return if (sum - 1).abs <= WEIGHT_TOLERANCE

    raise ArgumentError, "allocation must add up to 100%, got #{(sum * 100).round(4).to_s('F')}%"
  end

  # Divides by the sum so tiny rounding leftovers (within WEIGHT_TOLERANCE) don't
  # leave a few fractions of a cent unbalanced between buys and sells.
  def target_weight(symbol)
    @allocation.fetch(symbol, BigDecimal("0")) / @allocation.values.sum(BigDecimal("0"))
  end

  # Prices are read once per operation, so a live price source that changes
  # between calls can't make one calculation mix two different moments.
  def current_prices
    @stocks.transform_values(&:current_price)
  end
end

# Demo: `ruby portfolio.rb`. Each scenario prints its trades and checks that
#   - buys and sells move the same amount of money (no cash involved), and
#   - after applying the trades, every weight equals its target.
if __FILE__ == $PROGRAM_NAME
  def check(condition, message)
    raise "FAILED: #{message}" unless condition
  end

  def weights_after(trades, portfolio, allocation)
    values = portfolio.weights.transform_values { |weight| weight * portfolio.total_value }
    trades.each do |trade|
      values[trade.symbol] += trade.action == :buy ? trade.amount : -trade.amount
    end
    total = values.values.sum(BigDecimal("0"))
    values.each do |symbol, value|
      target = Decimal.from(allocation.fetch(symbol, 0))
      check((value / total - target).abs < BigDecimal("0.000001"), "#{symbol} should end at #{target.to_s('F')}")
    end
  end

  def scenario(title, holdings:, allocation:)
    puts "\n== #{title}"
    portfolio = Portfolio.new(holdings: holdings, allocation: allocation)
    puts format("Total value: %.2f", portfolio.total_value)
    trades = portfolio.rebalance
    puts(trades.empty? ? "Already balanced, nothing to trade" : trades)

    sold = trades.select { |t| t.action == :sell }.sum(BigDecimal("0"), &:amount)
    bought = trades.select { |t| t.action == :buy }.sum(BigDecimal("0"), &:amount)
    check((sold - bought).abs < Portfolio::MIN_TRADE_AMOUNT, "sells (#{sold}) should fund buys (#{bought})")
    weights_after(trades, portfolio, allocation)
    trades
  end

  meta = Stock.new("META", 500)
  aapl = Stock.new("AAPL", 200)

  # META is worth 5000 (55.6%) and AAPL 4000 (44.4%) out of 9000; the target
  # is 3600 / 5400, so 1400 must move from META to AAPL.
  trades = scenario("Overweight META, target 40/60",
                    holdings: { meta => 10, aapl => 20 }, allocation: { "META" => 0.4, "AAPL" => 0.6 })
  check(trades.map { |t| [t.symbol, t.action, t.amount] } ==
        [["META", :sell, 1400], ["AAPL", :buy, 1400]], "expected sell 1400 META / buy 1400 AAPL")

  trades = scenario("Already balanced",
                    holdings: { meta => 4, aapl => 15 }, allocation: { "META" => 0.4, "AAPL" => 0.6 })
  check(trades.empty?, "a balanced portfolio needs no trades")

  trades = scenario("Held stock with no target is sold completely",
                    holdings: { meta => 10, aapl => 20, Stock.new("TSLA", 250) => 4 },
                    allocation: { "META" => 0.4, "AAPL" => 0.6 })
  check(trades.find { |t| t.symbol == "TSLA" }&.shares == 4, "all 4 TSLA shares should be sold")

  scenario("New position held with 0 shares",
           holdings: { meta => 10, aapl => 0 }, allocation: { "META" => 0.5, "AAPL" => 0.5 })

  scenario("Thirds (weights with rounding noise)",
           holdings: { meta => 10, aapl => 0, Stock.new("NVDA", 125) => 0 },
           allocation: { "META" => 1r / 3, "AAPL" => 1r / 3, "NVDA" => 1r / 3 })

  scenario("Live price source (lambda)",
           holdings: { Stock.new("META", -> { 512.37 }) => 3.5, aapl => 12 },
           allocation: { "META" => 0.25, "AAPL" => 0.75 })

  puts "\n== Invalid input is rejected"
  [
    ["weights add up to 90%", -> { Portfolio.new(holdings: { meta => 1, aapl => 1 }, allocation: { "META" => 0.5, "AAPL" => 0.4 }) }],
    ["allocated stock not in holdings", -> { Portfolio.new(holdings: { meta => 1 }, allocation: { "META" => 0.5, "AAPL" => 0.5 }) }],
    ["negative weight", -> { Portfolio.new(holdings: { meta => 1, aapl => 1 }, allocation: { "META" => 1.5, "AAPL" => -0.5 }) }],
    ["negative shares", -> { Portfolio.new(holdings: { meta => -1 }, allocation: { "META" => 1 }) }],
    ["non-positive price", -> { Portfolio.new(holdings: { Stock.new("BAD", 0) => 1 }, allocation: { "BAD" => 1 }).rebalance }]
  ].each do |label, action|
    action.call
    raise "FAILED: #{label} should raise ArgumentError"
  rescue ArgumentError => e
    puts "#{label}: #{e.message}"
  end

  puts "\nAll checks passed"
end
