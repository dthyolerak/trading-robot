# Forex Trading Robot - Installation & Usage Guide
# ===============================================

## 🚀 Quick Installation

### Step 1: Download and Setup
```bash
# Download the project files
# Extract to your desired directory
cd forex-trading-robot

# Run the setup script
python setup.py
```

### Step 2: Install Dependencies
```bash
# Install Python packages
pip install -r requirements.txt

# Verify installation
python -c "import pandas, numpy, matplotlib, seaborn; print('✅ Dependencies installed successfully')"
```

### Step 3: Configure Settings
```bash
# Edit the configuration file
nano config.ini

# Key settings to review:
# - RISK_PER_TRADE: 0.5 (0.5% per trade)
# - DAILY_LOSS_LIMIT: 3.0 (3% daily limit)
# - TRADING_PAIRS: EURUSD,USDJPY,GBPUSD,AUDUSD
# - BACKTEST_START_DATE: 2019-01-01
# - BACKTEST_END_DATE: 2024-12-31
```

## 🎯 Running the System

### Complete System Execution
```bash
# Run everything (backtesting + Monte Carlo + reporting)
python main.py

# With custom parameters
python main.py --start-date 2020-01-01 --end-date 2024-12-31 --monte-carlo-runs 2000
```

### Individual Components
```bash
# Run backtesting only
python backtest.py

# Run Monte Carlo simulation only
python monte_carlo.py

# Generate performance reports only
python performance_reporter.py
```

### Advanced Options
```bash
# Skip certain components
python main.py --skip-monte-carlo --skip-walk-forward

# Use existing results
python main.py --skip-backtest

# Verbose output
python main.py --verbose
```

## 📊 Understanding the Results

### Key Performance Metrics
- **Total Return**: Overall percentage gain/loss
- **Win Rate**: Percentage of profitable trades
- **Profit Factor**: Ratio of gross profit to gross loss
- **Max Drawdown**: Largest peak-to-trough decline
- **Sharpe Ratio**: Risk-adjusted return measure
- **Expectancy**: Average expected return per trade

### Target Performance Evaluation
- **Day 1 Target**: 900% return (exceptional)
- **Day 2 Target**: 200% return (excellent)
- **Day 3+ Target**: 2-5% daily (good)
- **Break-even**: 0% return (acceptable)
- **Loss**: Negative return (poor)

### Risk Assessment
- **VaR (Value at Risk)**: Potential loss at confidence levels
- **Consecutive Losses**: Maximum losing streak
- **Daily Volatility**: Standard deviation of daily returns
- **Drawdown Duration**: Time spent in drawdown

## 🔧 MetaTrader 5 Integration

### Installing the Expert Advisor
1. **Copy EA File**:
   ```bash
   # Copy to MT5 Experts folder
   cp ForexRobot.mq5 /path/to/MT5/MQL5/Experts/
   ```

2. **Compile in MetaEditor**:
   - Open MetaEditor
   - Open `ForexRobot.mq5`
   - Press F7 or click Compile
   - Check for errors

3. **Attach to Chart**:
   - Open MT5 terminal
   - Open a chart (e.g., EURUSD M5)
   - Drag EA from Navigator to chart
   - Configure parameters
   - Enable AutoTrading

### EA Configuration
- **Enable Trading**: True
- **Risk Per Trade**: 0.5%
- **Daily Loss Limit**: 3.0%
- **Stop Loss Pips**: 8
- **Take Profit Pips**: 12
- **Trading Pairs**: EURUSD,USDJPY,GBPUSD,AUDUSD
- **Magic Number**: 123456

### Monitoring Live Trading
- Check Expert tab for EA messages
- Monitor account balance and equity
- Review trade history
- Watch for error messages
- Verify risk management is working

## 📈 Demo Trading Plan

### Phase 1: Initial Testing (30 days)
- **Goal**: Verify strategy performance
- **Focus**: Risk management compliance
- **Success Criteria**: Positive returns, controlled drawdown
- **Monitoring**: Daily P&L, win rate, trade frequency

### Phase 2: Extended Testing (60 days)
- **Goal**: Confirm consistency
- **Focus**: Performance stability
- **Success Criteria**: Consistent profitability
- **Monitoring**: Monthly returns, drawdown patterns

### Phase 3: Final Validation (90 days)
- **Goal**: Prepare for live trading
- **Focus**: Overall system reliability
- **Success Criteria**: Meets all targets
- **Monitoring**: Complete performance analysis

### Demo Success Criteria
- **Minimum Period**: 30 days
- **Minimum Win Rate**: 50%
- **Maximum Drawdown**: 15%
- **Consistent Profitability**: Required
- **Risk Management**: Fully compliant

## ⚠️ Risk Management Guidelines

### Pre-Trading Checklist
- [ ] Demo account tested for minimum period
- [ ] Risk parameters configured correctly
- [ ] Stop-loss and take-profit levels set
- [ ] Daily loss limits enabled
- [ ] Circuit breakers active
- [ ] News filter configured
- [ ] Time filters set

### During Trading Monitoring
- [ ] Monitor daily P&L
- [ ] Check win rate consistency
- [ ] Verify risk management adherence
- [ ] Monitor drawdown levels
- [ ] Track trade frequency
- [ ] Review strategy performance
- [ ] Check for system errors

### Emergency Procedures
- **Kill Switch**: Disable trading immediately
- **Daily Limit**: Stop trading for the day
- **Drawdown Limit**: Review and adjust strategy
- **System Error**: Check logs and restart
- **Broker Issues**: Switch to demo mode

## 🔍 Troubleshooting

### Common Issues and Solutions

#### 1. Import Errors
```bash
# Problem: Module not found
# Solution: Install missing packages
pip install pandas numpy matplotlib seaborn yfinance MetaTrader5 scipy
```

#### 2. Data Connection Issues
```bash
# Problem: No historical data
# Solution: Check internet connection and data sources
python -c "import yfinance; print(yfinance.download('EURUSD=X', period='1d'))"
```

#### 3. MetaTrader 5 Connection
```bash
# Problem: MT5 not available
# Solution: Ensure MT5 is running and logged in
python -c "import MetaTrader5 as mt5; print(mt5.initialize())"
```

#### 4. Configuration Errors
```bash
# Problem: Invalid configuration
# Solution: Check config.ini format
python -c "from backtest import ForexBacktester; ForexBacktester()"
```

#### 5. Permission Issues
```bash
# Problem: Cannot write files
# Solution: Check directory permissions
ls -la reports/
chmod 755 reports/
```

### Debug Mode
```bash
# Enable debug mode in config.ini
DEBUG_MODE=true
VERBOSE_LOGGING=true

# Run with verbose output
python main.py --verbose
```

### Log Files
- Check `logs/` directory for error messages
- Review console output for warnings
- Monitor MT5 Expert tab for EA messages

## 📚 Advanced Usage

### Custom Strategy Parameters
```ini
# Edit config.ini for custom settings
[STRATEGY_PARAMETERS]
EMA_FAST_PERIOD=20
EMA_SLOW_PERIOD=200
BB_PERIOD=20
BB_DEVIATION=2.0
RSI_PERIOD=14
RSI_OVERBOUGHT=70
RSI_OVERSOLD=30
```

### Custom Risk Management
```ini
# Adjust risk parameters
[RISK_MANAGEMENT]
RISK_PER_TRADE=0.5
DAILY_LOSS_LIMIT=3.0
MAX_DRAWDOWN_LIMIT=20.0
CONSECUTIVE_LOSS_LIMIT=3
```

### Custom Performance Targets
```ini
# Set custom targets
[PERFORMANCE_TARGETS]
DAY_1_TARGET=900.0
DAY_2_TARGET=200.0
DAY_3_PLUS_TARGET_MIN=2.0
DAY_3_PLUS_TARGET_MAX=5.0
```

### Batch Processing
```bash
# Run multiple backtests
for year in 2020 2021 2022 2023; do
    python main.py --start-date $year-01-01 --end-date $year-12-31 --output-dir reports_$year
done
```

## 📊 Performance Analysis

### Reading the Reports

#### 1. Performance Dashboard (`performance_dashboard.png`)
- **Equity Curve**: Account balance over time
- **Drawdown Chart**: Risk visualization
- **Win Rate**: Success percentage
- **Profit/Loss**: Gross profit vs loss
- **Monthly Returns**: Performance by month
- **Trade Duration**: Time analysis
- **P&L Distribution**: Statistical analysis
- **Performance Summary**: Key metrics
- **Target Performance**: Goal achievement

#### 2. Risk Analysis (`risk_analysis.png`)
- **Drawdown Over Time**: Risk progression
- **Risk-Return Scatter**: Efficiency analysis
- **Consecutive Wins/Losses**: Streak analysis
- **Value at Risk**: Potential losses

#### 3. CSV Reports
- **trades_detailed.csv**: Complete trade history
- **equity_curve_detailed.csv**: Balance progression
- **daily_performance.csv**: Daily analysis
- **monthly_performance.csv**: Monthly analysis

### Interpreting Results

#### Good Performance Indicators
- **Win Rate**: >50%
- **Profit Factor**: >1.5
- **Sharpe Ratio**: >1.0
- **Max Drawdown**: <15%
- **Consistent Returns**: Stable monthly performance

#### Warning Signs
- **Declining Win Rate**: Strategy degradation
- **Increasing Drawdown**: Risk escalation
- **Volatile Returns**: Unstable performance
- **Frequent Losses**: Strategy issues

## 🎯 Next Steps

### After Successful Demo
1. **Review Results**: Analyze all performance metrics
2. **Adjust Parameters**: Optimize based on results
3. **Extend Testing**: Run longer demo periods
4. **Prepare Live**: Set up live account
5. **Start Small**: Begin with minimum position sizes
6. **Monitor Closely**: Watch initial live performance

### Continuous Improvement
1. **Regular Backtesting**: Test with new data
2. **Parameter Optimization**: Adjust settings
3. **Strategy Refinement**: Improve entry/exit rules
4. **Risk Management**: Enhance safety measures
5. **Performance Monitoring**: Track live results

---

**Remember**: Always start with demo accounts and never risk more than you can afford to lose!
