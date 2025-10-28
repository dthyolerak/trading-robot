# Forex Trading Robot - MetaTrader 5 Expert Advisor

## 🎯 Project Overview

A fully automated Forex trading robot designed for MetaTrader 5 that implements a hybrid momentum + mean reversion strategy. The robot is optimized for small accounts starting from $10 and aims to compound safely toward $10,000 with dynamic daily growth targets.

## 📊 Strategy Details

- **Timeframe**: M5 (5 minutes)
- **Account Size**: Minimum $10 (micro-lot compatible)
- **Target Pairs**: EUR/USD, USD/JPY, GBP/USD, AUD/USD
- **Strategy Type**: Hybrid momentum + mean reversion
- **Indicators**: EMA (20 & 200), Bollinger Bands, RSI(14)
- **Risk per Trade**: 0.5% of equity (configurable)
- **Daily Max Loss**: 3% of equity (configurable)
- **Stop Loss**: 8 pips (configurable)
- **Take Profit**: 12 pips (configurable, minimum 1.2x SL)

## 🛡️ Risk Management Features

- **Position Sizing**: Automatic fractional lot sizing based on stop-loss pips × risk %
- **Circuit Breakers**: Stop trading after 3 consecutive losses or daily drawdown threshold
- **Kill Switch**: Auto stop if > 20% drawdown or critical error
- **News Filter**: Disable trading during high-impact news events
- **Demo Mode**: Auto-switch to demo if broker disconnects or slippage exceeds threshold
- **No Martingale**: Strictly prohibited grid doubling or averaging down

## 📈 Performance Targets

### Daily Growth Schedule
- **Day 1**: $10 → $100 (900% target)
- **Day 2**: $100 → $300 (200% target)
- **Day 3+**: Dynamic compounding (2-5% daily)

### Evaluation Metrics
- Net profit and win rate
- Profit factor and expectancy
- Maximum drawdown
- Sharpe ratio
- Monte Carlo simulation results
- Walk-forward test performance

## 🚀 Installation & Setup

### Prerequisites
- MetaTrader 5 platform
- Minimum $10 account balance
- Micro-lot trading enabled
- Stable internet connection

### Installation Steps
1. Copy `ForexRobot.mq5` to `MQL5/Experts/` folder
2. Copy `config.ini` to `MQL5/Files/` folder
3. Compile the EA in MetaEditor
4. Attach to chart with proper settings
5. Configure parameters in `config.ini`

### Configuration
Edit `config.ini` to customize:
- Risk percentage per trade
- Daily loss limits
- Trading pairs
- News filter settings
- Performance targets

## 📊 Backtesting

The robot includes comprehensive backtesting capabilities:
- **Historical Data**: 2+ years M5 data (2019-2024)
- **Realistic Conditions**: Spreads and slippage simulation
- **Performance Reports**: CSV exports and equity curve charts
- **Monte Carlo**: Statistical analysis of trading results
- **Walk-Forward**: Out-of-sample testing

## ⚠️ Risk Disclaimer

**IMPORTANT**: This trading robot is for educational and research purposes. Forex trading involves substantial risk of loss and is not suitable for all investors. Past performance does not guarantee future results. Always:

- Start with demo accounts
- Never risk more than you can afford to lose
- Understand all risks before trading live
- Monitor performance regularly
- Have proper risk management in place

## 📁 Project Structure

```
forex-trading-robot/
├── ForexRobot.mq5          # Main Expert Advisor
├── config.ini              # Configuration file
├── backtest/               # Backtesting results
├── reports/                # Performance reports
├── data/                   # Historical data
└── README.md              # This file
```

## 🔧 Technical Specifications

- **Language**: MQL5
- **Platform**: MetaTrader 5
- **Account Types**: Micro, Standard, ECN
- **Minimum Balance**: $10
- **Lot Sizes**: 0.01 (micro lots)
- **Execution**: Market orders with instant execution
- **Slippage**: Configurable tolerance

## 📞 Support

For questions or issues:
1. Check the configuration file
2. Review the backtesting results
3. Monitor demo performance
4. Consult the risk management settings

## 📄 License

This project is provided as-is for educational purposes. Use at your own risk.
