# Forex Trading Robot - Project Structure
# ======================================

## 📁 Project Directory Structure

```
forex-trading-robot/
├── 📄 README.md                    # Main project documentation
├── ⚙️ config.ini                   # Configuration file
├── 📋 requirements.txt             # Python dependencies
├── 🚀 setup.py                     # Setup script
├── 🎯 main.py                      # Main execution script
│
├── 🤖 ForexRobot.mq5               # MetaTrader 5 Expert Advisor
│
├── 🐍 Python Modules/
│   ├── 📊 backtest.py              # Backtesting framework
│   ├── 🎲 monte_carlo.py           # Monte Carlo simulation
│   └── 📈 performance_reporter.py  # Performance reporting
│
├── 📁 reports/                     # Generated reports (auto-created)
│   ├── 📊 trades_detailed.csv      # Detailed trade data
│   ├── 📈 equity_curve_detailed.csv # Equity curve data
│   ├── 📋 performance_metrics_detailed.json # Performance metrics
│   ├── 📅 daily_performance.csv    # Daily performance data
│   ├── 📆 monthly_performance.csv  # Monthly performance data
│   ├── 🎲 monte_carlo_simulation.csv # Monte Carlo results
│   ├── 📈 walk_forward_analysis.csv # Walk-forward analysis
│   ├── 📊 performance_dashboard.png # Performance charts
│   ├── ⚠️ risk_analysis.png         # Risk analysis charts
│   ├── 📋 comprehensive_summary.json # Complete summary
│   ├── 📋 demo_trading_plan.json   # Demo trading plan
│   └── ⚠️ risk_disclaimer.txt       # Risk disclaimer
│
├── 📁 data/                        # Historical data (auto-created)
├── 📁 logs/                        # Log files (auto-created)
├── 📁 backtest/                    # Backtest results (auto-created)
└── 📁 config/                      # Additional config files (auto-created)
```

## 🎯 Core Components

### 1. MetaTrader 5 Expert Advisor (`ForexRobot.mq5`)
- **Purpose**: Live trading automation
- **Strategy**: Hybrid momentum + mean reversion
- **Indicators**: EMA (20 & 200), Bollinger Bands, RSI(14)
- **Risk Management**: 0.5% per trade, 3% daily limit, circuit breakers
- **Features**: 
  - Automatic position sizing
  - Stop-loss and take-profit management
  - Time and news filters
  - Kill switch protection

### 2. Backtesting Framework (`backtest.py`)
- **Purpose**: Historical strategy testing
- **Data Sources**: MetaTrader 5, Yahoo Finance
- **Timeframe**: M5 (5-minute) data
- **Period**: 2019-2024 (configurable)
- **Features**:
  - Realistic spread and slippage simulation
  - Multiple trading pairs support
  - Performance metrics calculation
  - Equity curve generation

### 3. Monte Carlo Simulation (`monte_carlo.py`)
- **Purpose**: Statistical analysis of trading results
- **Runs**: 1000 simulations (configurable)
- **Analysis**: 
  - Confidence intervals
  - Target probability calculations
  - Risk assessment
  - Performance distribution analysis

### 4. Performance Reporting (`performance_reporter.py`)
- **Purpose**: Comprehensive performance analysis
- **Outputs**: 
  - CSV reports
  - JSON metrics
  - PNG charts
  - Summary reports
- **Features**:
  - Daily/monthly performance analysis
  - Risk metrics calculation
  - Target performance evaluation
  - Visual performance dashboard

### 5. Configuration System (`config.ini`)
- **Purpose**: Centralized parameter management
- **Sections**:
  - General settings
  - Risk management
  - Strategy parameters
  - Performance targets
  - Advanced settings

## 🚀 Quick Start Guide

### 1. Installation
```bash
# Clone or download the project
cd forex-trading-robot

# Run setup script
python setup.py

# Install dependencies
pip install -r requirements.txt
```

### 2. Configuration
```bash
# Edit configuration file
nano config.ini

# Key parameters to adjust:
# - RISK_PER_TRADE: 0.5 (0.5% per trade)
# - DAILY_LOSS_LIMIT: 3.0 (3% daily limit)
# - TRADING_PAIRS: EURUSD,USDJPY,GBPUSD,AUDUSD
# - BACKTEST_START_DATE: 2019-01-01
# - BACKTEST_END_DATE: 2024-12-31
```

### 3. Running the System
```bash
# Run complete system
python main.py

# Run individual components
python backtest.py
python monte_carlo.py
python performance_reporter.py
```

### 4. MetaTrader 5 Integration
```bash
# Copy EA to MT5
cp ForexRobot.mq5 /path/to/MT5/MQL5/Experts/

# Compile in MetaEditor
# Attach to chart with proper settings
```

## 📊 Performance Targets

### Daily Growth Schedule
- **Day 1**: $10 → $100 (900% target)
- **Day 2**: $100 → $300 (200% target)  
- **Day 3+**: Dynamic compounding (2-5% daily)

### Risk Management
- **Per Trade Risk**: 0.5% of equity
- **Daily Loss Limit**: 3% of equity
- **Max Drawdown Limit**: 20% of equity
- **Consecutive Loss Limit**: 3 trades
- **Position Sizing**: Automatic based on stop-loss

### Circuit Breakers
- **Kill Switch**: Auto-stop at 20% drawdown
- **Daily Loss**: Stop trading at 3% daily loss
- **Consecutive Losses**: Stop after 3 losses
- **News Filter**: Avoid high-impact news events
- **Time Filter**: Trading hours only

## 📈 Strategy Details

### Entry Conditions (Buy)
- Price above both EMA 20 and EMA 200
- EMA 20 above EMA 200 (uptrend)
- Price near lower Bollinger Band (oversold)
- RSI below 70 (not overbought)

### Entry Conditions (Sell)
- Price below both EMA 20 and EMA 200
- EMA 20 below EMA 200 (downtrend)
- Price near upper Bollinger Band (overbought)
- RSI above 30 (not oversold)

### Exit Conditions
- **Stop Loss**: 8 pips (configurable)
- **Take Profit**: 12 pips (configurable)
- **Minimum Ratio**: 1.2:1 (TP:SL)

## 🔧 Technical Specifications

### System Requirements
- **Python**: 3.8 or higher
- **MetaTrader 5**: Latest version
- **RAM**: Minimum 4GB
- **Storage**: 1GB free space
- **Internet**: Stable connection required

### Supported Brokers
- **Account Types**: Micro, Standard, ECN
- **Minimum Balance**: $10
- **Lot Sizes**: 0.01 (micro lots)
- **Execution**: Market orders
- **Slippage**: Configurable tolerance

### Data Requirements
- **Timeframe**: M5 (5-minute)
- **History**: 2+ years recommended
- **Pairs**: EUR/USD, USD/JPY, GBP/USD, AUD/USD
- **Quality**: Tick data preferred

## 📋 Output Files

### CSV Reports
- `trades_detailed.csv`: Complete trade history
- `equity_curve_detailed.csv`: Account balance over time
- `daily_performance.csv`: Daily P&L analysis
- `monthly_performance.csv`: Monthly performance
- `monte_carlo_simulation.csv`: Simulation results
- `walk_forward_analysis.csv`: Walk-forward results

### JSON Reports
- `performance_metrics_detailed.json`: Key performance indicators
- `monte_carlo_confidence_intervals.json`: Statistical confidence
- `monte_carlo_target_probabilities.json`: Target achievement probabilities
- `comprehensive_summary.json`: Complete analysis summary
- `demo_trading_plan.json`: Demo trading guidelines

### Visual Reports
- `performance_dashboard.png`: Complete performance overview
- `risk_analysis.png`: Risk metrics visualization
- `equity_curve.png`: Account balance chart
- `monte_carlo_distributions.png`: Statistical distributions

## ⚠️ Risk Disclaimer

**IMPORTANT**: This trading robot is for educational and research purposes only. Forex trading involves substantial risk of loss and is not suitable for all investors.

### Key Risks
- **High Risk**: Forex trading carries high risk
- **Capital Loss**: You may lose your entire investment
- **Leverage Risk**: Leverage can amplify losses
- **Market Volatility**: Markets can move against you quickly
- **Technical Risk**: System failures can occur
- **No Guarantees**: Past performance doesn't guarantee future results

### Recommendations
- Start with demo accounts
- Never risk more than you can afford to lose
- Understand all risks before trading live
- Monitor performance regularly
- Have proper risk management in place
- Consult financial advisors if needed

## 🆘 Support and Troubleshooting

### Common Issues
1. **Import Errors**: Run `pip install -r requirements.txt`
2. **Data Issues**: Check internet connection and data sources
3. **MT5 Connection**: Ensure MetaTrader 5 is running
4. **Configuration**: Verify `config.ini` settings
5. **Permissions**: Check file write permissions

### Getting Help
1. Check the logs in `logs/` directory
2. Review configuration in `config.ini`
3. Run individual components to isolate issues
4. Check system requirements
5. Verify data availability

## 📚 Additional Resources

### Documentation
- MetaTrader 5 documentation
- MQL5 programming guide
- Python pandas documentation
- Forex trading basics

### Educational Materials
- Risk management principles
- Technical analysis fundamentals
- Backtesting best practices
- Performance evaluation methods

---

**Remember**: Always start with demo accounts and never risk more than you can afford to lose!
