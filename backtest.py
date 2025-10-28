#!/usr/bin/env python3
"""
Forex Trading Robot - Backtesting Framework
==========================================

This module provides comprehensive backtesting capabilities for the Forex trading robot,
including historical data analysis, performance metrics calculation, and Monte Carlo simulation.

Author: Forex Trading Robot
Date: 2024
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from datetime import datetime, timedelta
import yfinance as yf
try:
    import MetaTrader5 as mt5
    MT5_AVAILABLE = True
except ImportError:
    MT5_AVAILABLE = False
    print("WARNING: MetaTrader5 not available - will use alternative data sources")
import json
import os
from typing import Dict, List, Tuple, Optional
import warnings
warnings.filterwarnings('ignore')

class ForexBacktester:
    """
    Comprehensive backtesting framework for Forex trading strategies.
    """
    
    def __init__(self, config_file: str = "config.ini"):
        """
        Initialize the backtester with configuration.
        
        Args:
            config_file: Path to configuration file
        """
        self.config = self.load_config(config_file)
        self.trades = []
        self.equity_curve = []
        self.performance_metrics = {}
        
        # Strategy parameters
        self.risk_per_trade = self.config.get('RISK_PER_TRADE', 0.5)
        self.daily_loss_limit = self.config.get('DAILY_LOSS_LIMIT', 3.0)
        self.stop_loss_pips = self.config.get('STOP_LOSS_PIPS', 8)
        self.take_profit_pips = self.config.get('TAKE_PROFIT_PIPS', 12)
        self.initial_balance = self.config.get('BACKTEST_INITIAL_BALANCE', 10.0)
        
        # Trading pairs
        self.trading_pairs = self.config.get('TRADING_PAIRS', 'EURUSD,USDJPY,GBPUSD,AUDUSD').split(',')
        
        # Performance targets
        self.day1_target = self.config.get('DAY_1_TARGET', 900.0)
        self.day2_target = self.config.get('DAY_2_TARGET', 200.0)
        self.day3_plus_min = self.config.get('DAY_3_PLUS_TARGET_MIN', 2.0)
        self.day3_plus_max = self.config.get('DAY_3_PLUS_TARGET_MAX', 5.0)
        
    def load_config(self, config_file: str) -> Dict:
        """
        Load configuration from INI file.
        
        Args:
            config_file: Path to configuration file
            
        Returns:
            Dictionary containing configuration parameters
        """
        config = {}
        try:
            with open(config_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#') and '=' in line:
                        key, value = line.split('=', 1)
                        key = key.strip()
                        value = value.strip()
                        
                        # Convert numeric values
                        try:
                            if '.' in value:
                                config[key] = float(value)
                            else:
                                config[key] = int(value)
                        except ValueError:
                            config[key] = value
        except FileNotFoundError:
            print(f"Configuration file {config_file} not found. Using defaults.")
            
        return config
    
    def get_historical_data(self, symbol: str, start_date: str, end_date: str, timeframe: str = '5m') -> pd.DataFrame:
        """
        Get historical data for backtesting.
        
        Args:
            symbol: Trading symbol (e.g., 'EURUSD=X')
            start_date: Start date in 'YYYY-MM-DD' format
            end_date: End date in 'YYYY-MM-DD' format
            timeframe: Data timeframe ('1m', '5m', '1h', '1d')
            
        Returns:
            DataFrame with OHLCV data
        """
        # Try MetaTrader 5 first if available
        if MT5_AVAILABLE:
            try:
                if mt5.initialize():
                    rates = mt5.copy_rates_range(symbol, mt5.TIMEFRAME_M5, 
                                               datetime.strptime(start_date, '%Y-%m-%d'),
                                               datetime.strptime(end_date, '%Y-%m-%d'))
                    if rates is not None:
                        df = pd.DataFrame(rates)
                        df['time'] = pd.to_datetime(df['time'], unit='s')
                        df.set_index('time', inplace=True)
                        mt5.shutdown()
                        return df
            except Exception as e:
                print(f"MetaTrader 5 data unavailable: {e}")
        
        # Fallback to Yahoo Finance
        try:
            ticker = yf.Ticker(symbol)
            df = ticker.history(start=start_date, end=end_date, interval=timeframe)
            if df.empty:
                print(f"No data available for {symbol}")
                return pd.DataFrame()
            return df
        except Exception as e:
            print(f"Error fetching data for {symbol}: {e}")
            return pd.DataFrame()
    
    def calculate_indicators(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Calculate technical indicators for the strategy.
        
        Args:
            df: DataFrame with OHLCV data
            
        Returns:
            DataFrame with added indicator columns
        """
        if df.empty:
            return df
            
        # EMA calculations
        df['EMA_20'] = df['Close'].ewm(span=20).mean()
        df['EMA_200'] = df['Close'].ewm(span=200).mean()
        
        # Bollinger Bands
        df['BB_Middle'] = df['Close'].rolling(window=20).mean()
        bb_std = df['Close'].rolling(window=20).std()
        df['BB_Upper'] = df['BB_Middle'] + (bb_std * 2)
        df['BB_Lower'] = df['BB_Middle'] - (bb_std * 2)
        
        # RSI calculation
        delta = df['Close'].diff()
        gain = (delta.where(delta > 0, 0)).rolling(window=14).mean()
        loss = (-delta.where(delta < 0, 0)).rolling(window=14).mean()
        rs = gain / loss
        df['RSI'] = 100 - (100 / (1 + rs))
        
        # Bollinger Band position
        df['BB_Position'] = (df['Close'] - df['BB_Lower']) / (df['BB_Upper'] - df['BB_Lower'])
        
        return df
    
    def generate_signals(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Generate buy/sell signals based on the hybrid strategy.
        
        Args:
            df: DataFrame with OHLCV and indicator data
            
        Returns:
            DataFrame with signal columns
        """
        if df.empty:
            return df
            
        df['Buy_Signal'] = 0
        df['Sell_Signal'] = 0
        
        # Buy signal conditions
        buy_condition = (
            (df['Close'] > df['EMA_20']) &  # Price above fast EMA
            (df['Close'] > df['EMA_200']) &  # Price above slow EMA
            (df['EMA_20'] > df['EMA_200']) &  # Fast EMA above slow EMA
            (df['BB_Position'] < 0.3) &  # Price near lower Bollinger Band
            (df['RSI'] < 70)  # RSI not overbought
        )
        
        # Sell signal conditions
        sell_condition = (
            (df['Close'] < df['EMA_20']) &  # Price below fast EMA
            (df['Close'] < df['EMA_200']) &  # Price below slow EMA
            (df['EMA_20'] < df['EMA_200']) &  # Fast EMA below slow EMA
            (df['BB_Position'] > 0.7) &  # Price near upper Bollinger Band
            (df['RSI'] > 30)  # RSI not oversold
        )
        
        df.loc[buy_condition, 'Buy_Signal'] = 1
        df.loc[sell_condition, 'Sell_Signal'] = 1
        
        return df
    
    def calculate_position_size(self, balance: float, price: float, stop_loss_distance: float) -> float:
        """
        Calculate position size based on risk management.
        
        Args:
            balance: Current account balance
            price: Entry price
            stop_loss_distance: Stop loss distance in price units
            
        Returns:
            Position size in lots
        """
        risk_amount = balance * self.risk_per_trade / 100.0
        
        # Calculate lot size based on risk
        # Assuming 1 lot = 100,000 units of base currency
        lot_size = risk_amount / (stop_loss_distance * 100000)
        
        # Apply limits
        lot_size = max(lot_size, 0.01)  # Minimum lot size
        lot_size = min(lot_size, 1.0)   # Maximum lot size
        
        return round(lot_size, 2)
    
    def simulate_trades(self, df: pd.DataFrame, symbol: str) -> List[Dict]:
        """
        Simulate trades based on signals and strategy rules.
        
        Args:
            df: DataFrame with signals
            symbol: Trading symbol
            
        Returns:
            List of trade dictionaries
        """
        trades = []
        balance = self.initial_balance
        position = None
        consecutive_losses = 0
        daily_pnl = 0.0
        
        for i, row in df.iterrows():
            # Check daily loss limit
            if daily_pnl <= -balance * self.daily_loss_limit / 100.0:
                continue
                
            # Check consecutive losses limit
            if consecutive_losses >= 3:
                continue
            
            # Close existing position if conditions are met
            if position is not None:
                if self.should_close_position(position, row):
                    trade_result = self.close_position(position, row, balance)
                    trades.append(trade_result)
                    balance += trade_result['pnl']
                    
                    if trade_result['pnl'] < 0:
                        consecutive_losses += 1
                        daily_pnl += trade_result['pnl']
                    else:
                        consecutive_losses = 0
                        daily_pnl += trade_result['pnl']
                    
                    position = None
            
            # Open new position if signal exists
            if position is None:
                if row['Buy_Signal'] == 1:
                    position = self.open_position('BUY', row, symbol, balance)
                elif row['Sell_Signal'] == 1:
                    position = self.open_position('SELL', row, symbol, balance)
        
        return trades
    
    def open_position(self, direction: str, row: pd.Series, symbol: str, balance: float) -> Dict:
        """
        Open a new position.
        
        Args:
            direction: 'BUY' or 'SELL'
            row: Current market data row
            symbol: Trading symbol
            balance: Current balance
            
        Returns:
            Position dictionary
        """
        price = row['Close']
        pip_value = 0.0001 if 'JPY' not in symbol else 0.01
        
        stop_loss_distance = self.stop_loss_pips * pip_value
        take_profit_distance = self.take_profit_pips * pip_value
        
        if direction == 'BUY':
            stop_loss = price - stop_loss_distance
            take_profit = price + take_profit_distance
        else:
            stop_loss = price + stop_loss_distance
            take_profit = price - take_profit_distance
        
        lot_size = self.calculate_position_size(balance, price, stop_loss_distance)
        
        position = {
            'symbol': symbol,
            'direction': direction,
            'entry_price': price,
            'entry_time': row.name,
            'lot_size': lot_size,
            'stop_loss': stop_loss,
            'take_profit': take_profit,
            'status': 'OPEN'
        }
        
        return position
    
    def should_close_position(self, position: Dict, row: pd.Series) -> bool:
        """
        Check if position should be closed.
        
        Args:
            position: Position dictionary
            row: Current market data row
            
        Returns:
            True if position should be closed
        """
        price = row['Close']
        
        if position['direction'] == 'BUY':
            return price <= position['stop_loss'] or price >= position['take_profit']
        else:
            return price >= position['stop_loss'] or price <= position['take_profit']
    
    def close_position(self, position: Dict, row: pd.Series, balance: float) -> Dict:
        """
        Close a position and calculate P&L.
        
        Args:
            position: Position dictionary
            row: Current market data row
            balance: Current balance
            
        Returns:
            Trade result dictionary
        """
        exit_price = row['Close']
        exit_time = row.name
        
        if position['direction'] == 'BUY':
            pnl = (exit_price - position['entry_price']) * position['lot_size'] * 100000
        else:
            pnl = (position['entry_price'] - exit_price) * position['lot_size'] * 100000
        
        trade_result = {
            'symbol': position['symbol'],
            'direction': position['direction'],
            'entry_price': position['entry_price'],
            'exit_price': exit_price,
            'entry_time': position['entry_time'],
            'exit_time': exit_time,
            'lot_size': position['lot_size'],
            'pnl': pnl,
            'duration': exit_time - position['entry_time'],
            'status': 'CLOSED'
        }
        
        return trade_result
    
    def calculate_performance_metrics(self, trades: List[Dict]) -> Dict:
        """
        Calculate comprehensive performance metrics.
        
        Args:
            trades: List of completed trades
            
        Returns:
            Dictionary with performance metrics
        """
        if not trades:
            return {}
        
        df_trades = pd.DataFrame(trades)
        
        # Basic metrics
        total_trades = len(trades)
        winning_trades = len(df_trades[df_trades['pnl'] > 0])
        losing_trades = len(df_trades[df_trades['pnl'] < 0])
        
        total_profit = df_trades[df_trades['pnl'] > 0]['pnl'].sum()
        total_loss = abs(df_trades[df_trades['pnl'] < 0]['pnl'].sum())
        
        net_profit = df_trades['pnl'].sum()
        win_rate = winning_trades / total_trades * 100 if total_trades > 0 else 0
        profit_factor = total_profit / total_loss if total_loss > 0 else float('inf')
        
        # Risk metrics
        returns = df_trades['pnl'].values
        if len(returns) > 1:
            sharpe_ratio = np.mean(returns) / np.std(returns) * np.sqrt(252) if np.std(returns) > 0 else 0
        else:
            sharpe_ratio = 0
        
        # Drawdown calculation
        cumulative_returns = np.cumsum(returns)
        running_max = np.maximum.accumulate(cumulative_returns)
        drawdown = running_max - cumulative_returns
        max_drawdown = np.max(drawdown) if len(drawdown) > 0 else 0
        
        # Expectancy
        avg_win = total_profit / winning_trades if winning_trades > 0 else 0
        avg_loss = total_loss / losing_trades if losing_trades > 0 else 0
        expectancy = (win_rate / 100 * avg_win) - ((100 - win_rate) / 100 * avg_loss)
        
        metrics = {
            'total_trades': total_trades,
            'winning_trades': winning_trades,
            'losing_trades': losing_trades,
            'win_rate': win_rate,
            'net_profit': net_profit,
            'total_profit': total_profit,
            'total_loss': total_loss,
            'profit_factor': profit_factor,
            'max_drawdown': max_drawdown,
            'sharpe_ratio': sharpe_ratio,
            'expectancy': expectancy,
            'avg_win': avg_win,
            'avg_loss': avg_loss
        }
        
        return metrics
    
    def run_backtest(self, start_date: str, end_date: str) -> Dict:
        """
        Run complete backtest for all trading pairs.
        
        Args:
            start_date: Start date in 'YYYY-MM-DD' format
            end_date: End date in 'YYYY-MM-DD' format
            
        Returns:
            Dictionary with backtest results
        """
        print(f"Starting backtest from {start_date} to {end_date}")
        print(f"Initial balance: ${self.initial_balance}")
        
        all_trades = []
        pair_results = {}
        
        for symbol in self.trading_pairs:
            print(f"\nProcessing {symbol}...")
            
            # Get historical data
            df = self.get_historical_data(symbol, start_date, end_date)
            if df.empty:
                print(f"No data available for {symbol}")
                continue
            
            # Calculate indicators
            df = self.calculate_indicators(df)
            
            # Generate signals
            df = self.generate_signals(df)
            
            # Simulate trades
            trades = self.simulate_trades(df, symbol)
            all_trades.extend(trades)
            
            # Calculate metrics for this pair
            if trades:
                pair_metrics = self.calculate_performance_metrics(trades)
                pair_results[symbol] = pair_metrics
                print(f"{symbol} - Trades: {len(trades)}, Net P&L: ${pair_metrics.get('net_profit', 0):.2f}")
        
        # Calculate overall performance
        overall_metrics = self.calculate_performance_metrics(all_trades)
        
        # Calculate equity curve
        equity_curve = self.calculate_equity_curve(all_trades)
        
        results = {
            'overall_metrics': overall_metrics,
            'pair_results': pair_results,
            'all_trades': all_trades,
            'equity_curve': equity_curve,
            'config': self.config
        }
        
        return results
    
    def calculate_equity_curve(self, trades: List[Dict]) -> pd.DataFrame:
        """
        Calculate equity curve from trades.
        
        Args:
            trades: List of completed trades
            
        Returns:
            DataFrame with equity curve data
        """
        if not trades:
            return pd.DataFrame()
        
        df_trades = pd.DataFrame(trades)
        df_trades = df_trades.sort_values('exit_time')
        
        equity_curve = []
        balance = self.initial_balance
        
        for _, trade in df_trades.iterrows():
            balance += trade['pnl']
            equity_curve.append({
                'time': trade['exit_time'],
                'balance': balance,
                'trade_pnl': trade['pnl']
            })
        
        return pd.DataFrame(equity_curve)
    
    def generate_report(self, results: Dict, output_dir: str = "reports") -> None:
        """
        Generate comprehensive backtest report.
        
        Args:
            results: Backtest results dictionary
            output_dir: Output directory for reports
        """
        os.makedirs(output_dir, exist_ok=True)
        
        # Save trades to CSV
        if results['all_trades']:
            df_trades = pd.DataFrame(results['all_trades'])
            df_trades.to_csv(f"{output_dir}/trades.csv", index=False)
            print(f"Trades saved to {output_dir}/trades.csv")
        
        # Save equity curve to CSV
        if not results['equity_curve'].empty:
            results['equity_curve'].to_csv(f"{output_dir}/equity_curve.csv", index=False)
            print(f"Equity curve saved to {output_dir}/equity_curve.csv")
        
        # Save performance metrics to JSON
        with open(f"{output_dir}/performance_metrics.json", 'w') as f:
            json.dump(results['overall_metrics'], f, indent=2, default=str)
        print(f"Performance metrics saved to {output_dir}/performance_metrics.json")
        
        # Generate charts
        self.generate_charts(results, output_dir)
        
        # Print summary
        self.print_summary(results)
    
    def generate_charts(self, results: Dict, output_dir: str) -> None:
        """
        Generate performance charts.
        
        Args:
            results: Backtest results dictionary
            output_dir: Output directory for charts
        """
        plt.style.use('seaborn-v0_8')
        
        # Equity curve chart
        if not results['equity_curve'].empty:
            plt.figure(figsize=(12, 8))
            plt.plot(results['equity_curve']['time'], results['equity_curve']['balance'], 
                    linewidth=2, color='blue')
            plt.title('Equity Curve', fontsize=16, fontweight='bold')
            plt.xlabel('Date', fontsize=12)
            plt.ylabel('Account Balance ($)', fontsize=12)
            plt.grid(True, alpha=0.3)
            plt.tight_layout()
            plt.savefig(f"{output_dir}/equity_curve.png", dpi=300, bbox_inches='tight')
            plt.close()
            print(f"Equity curve chart saved to {output_dir}/equity_curve.png")
        
        # Performance metrics chart
        if results['overall_metrics']:
            metrics = results['overall_metrics']
            fig, axes = plt.subplots(2, 2, figsize=(15, 10))
            
            # Win rate pie chart
            axes[0, 0].pie([metrics['winning_trades'], metrics['losing_trades']], 
                          labels=['Winning Trades', 'Losing Trades'], 
                          autopct='%1.1f%%', colors=['green', 'red'])
            axes[0, 0].set_title('Win Rate Distribution')
            
            # Profit/Loss bar chart
            axes[0, 1].bar(['Total Profit', 'Total Loss'], 
                          [metrics['total_profit'], metrics['total_loss']], 
                          color=['green', 'red'])
            axes[0, 1].set_title('Profit vs Loss')
            axes[0, 1].set_ylabel('Amount ($)')
            
            # Monthly returns (if enough data)
            if len(results['all_trades']) > 30:
                df_trades = pd.DataFrame(results['all_trades'])
                df_trades['month'] = pd.to_datetime(df_trades['exit_time']).dt.to_period('M')
                monthly_pnl = df_trades.groupby('month')['pnl'].sum()
                
                axes[1, 0].bar(range(len(monthly_pnl)), monthly_pnl.values, 
                              color=['green' if x > 0 else 'red' for x in monthly_pnl.values])
                axes[1, 0].set_title('Monthly P&L')
                axes[1, 0].set_xlabel('Month')
                axes[1, 0].set_ylabel('P&L ($)')
            
            # Performance metrics table
            axes[1, 1].axis('off')
            metrics_text = f"""
            Total Trades: {metrics['total_trades']}
            Win Rate: {metrics['win_rate']:.1f}%
            Net Profit: ${metrics['net_profit']:.2f}
            Profit Factor: {metrics['profit_factor']:.2f}
            Max Drawdown: ${metrics['max_drawdown']:.2f}
            Sharpe Ratio: {metrics['sharpe_ratio']:.2f}
            Expectancy: ${metrics['expectancy']:.2f}
            """
            axes[1, 1].text(0.1, 0.5, metrics_text, fontsize=12, 
                           verticalalignment='center', fontfamily='monospace')
            axes[1, 1].set_title('Performance Summary')
            
            plt.tight_layout()
            plt.savefig(f"{output_dir}/performance_analysis.png", dpi=300, bbox_inches='tight')
            plt.close()
            print(f"Performance analysis chart saved to {output_dir}/performance_analysis.png")
    
    def print_summary(self, results: Dict) -> None:
        """
        Print backtest summary to console.
        
        Args:
            results: Backtest results dictionary
        """
        metrics = results['overall_metrics']
        
        print("\n" + "="*60)
        print("BACKTEST SUMMARY")
        print("="*60)
        print(f"Initial Balance: ${self.initial_balance:.2f}")
        print(f"Final Balance: ${self.initial_balance + metrics.get('net_profit', 0):.2f}")
        print(f"Total Return: {((self.initial_balance + metrics.get('net_profit', 0)) / self.initial_balance - 1) * 100:.2f}%")
        print(f"Net Profit: ${metrics.get('net_profit', 0):.2f}")
        print(f"Total Trades: {metrics.get('total_trades', 0)}")
        print(f"Win Rate: {metrics.get('win_rate', 0):.1f}%")
        print(f"Profit Factor: {metrics.get('profit_factor', 0):.2f}")
        print(f"Max Drawdown: ${metrics.get('max_drawdown', 0):.2f}")
        print(f"Sharpe Ratio: {metrics.get('sharpe_ratio', 0):.2f}")
        print(f"Expectancy: ${metrics.get('expectancy', 0):.2f}")
        print("="*60)
        
        # Performance vs targets
        total_return = ((self.initial_balance + metrics.get('net_profit', 0)) / self.initial_balance - 1) * 100
        print(f"\nPERFORMANCE vs TARGETS:")
        print(f"Day 1 Target: {self.day1_target}%")
        print(f"Day 2 Target: {self.day2_target}%")
        print(f"Day 3+ Target: {self.day3_plus_min}-{self.day3_plus_max}%")
        print(f"Actual Return: {total_return:.2f}%")
        
        if total_return >= self.day1_target:
            print("✅ EXCEEDED Day 1 target!")
        elif total_return >= self.day2_target:
            print("✅ EXCEEDED Day 2 target!")
        elif total_return >= self.day3_plus_min:
            print("✅ Met Day 3+ minimum target!")
        else:
            print("❌ Did not meet minimum targets")


def main():
    """
    Main function to run backtesting.
    """
    # Initialize backtester
    backtester = ForexBacktester()
    
    # Run backtest
    start_date = "2019-01-01"
    end_date = "2024-12-31"
    
    results = backtester.run_backtest(start_date, end_date)
    
    # Generate report
    backtester.generate_report(results)
    
    print("\nBacktesting completed successfully!")


if __name__ == "__main__":
    main()
