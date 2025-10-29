# EURUSDm Robot - Quick Start Guide

## 🚀 5-Minute Setup

### Step 1: Install
1. Copy `EURUSDm_Robot.mq5` to `MQL5/Experts/`
2. Open MetaEditor (F4)
3. Compile (F7) - should show "0 errors"
4. Restart MT5

### Step 2: Attach to Chart
1. Open EURUSDm M15 chart
2. Drag EA from Navigator to chart
3. Click OK (use defaults for first test)

### Step 3: Enable Trading
1. Enable AutoTrading button (toolbar)
2. Check Experts tab for "Robot ready" message
3. Wait for signals!

---

## ⚙️ Essential Settings

### Conservative (Recommended for Start)
```
Risk Percent: 0.5%
Max Open Trades: 1
Daily Loss Limit: 3.0%
Max Spread: 2.5 pips
Enable Trading: true
```

### Moderate
```
Risk Percent: 1.0%
Max Open Trades: 1-2
Daily Loss Limit: 5.0%
```

### Aggressive (Advanced Only)
```
Risk Percent: 1.5-2.0%
Max Open Trades: 2-3
Daily Loss Limit: 7.5%
```

---

## 📊 Quick Backtest

1. **Strategy Tester** (Ctrl+R)
2. **Settings:**
   - EA: EURUSDm_Robot
   - Symbol: EURUSDm
   - Period: M15
   - Dates: Last 6 months
   - Model: Every tick
   - Deposit: $1000
3. **Click Start**
4. **Review Results:** Net profit, drawdown, win rate

---

## 🔍 Monitoring

### What to Watch:
- **Experts Tab**: Entry/exit notifications
- **CSV Log**: `MQL5/Files/EURUSDm_Robot/trades_YYYY.MM.DD.csv`
- **Account**: Daily balance changes

### First Trade Checklist:
- ✅ EA shows "Robot ready" in Experts tab
- ✅ AutoTrading enabled
- ✅ Account balance sufficient
- ✅ Spread reasonable (< 2.5 pips)
- ✅ No error messages

---

## ⚠️ Important Notes

1. **Start on Demo**: Always test on demo account first!
2. **Minimum Balance**: Need at least $50-100 for micro lot trading
3. **Spread Matters**: High spreads = poor results on M15
4. **Be Patient**: Robot only trades when conditions are met
5. **Monitor Daily**: Check daily loss limit hasn't been hit

---

## 🆘 Troubleshooting

**No trades?**
- Check Experts tab for messages
- Verify spread < MaxSpread
- Ensure trading hours allowed
- Check daily loss limit

**Compilation errors?**
- Update MT5 to latest version
- Check file is in MQL5/Experts folder
- Recompile in MetaEditor

**Trades rejected?**
- Reduce Risk Percent
- Check margin requirements
- Increase Max Slippage

---

## 📈 Expected Performance

**Realistic Expectations:**
- Win Rate: 45-55%
- Profit Factor: 1.2-1.8
- Max Drawdown: 10-20%
- Trades per week: 2-10 (varies by market)

**Not Guaranteed!** Results vary based on market conditions.

---

**Ready to trade? Start with demo account and conservative settings!**

