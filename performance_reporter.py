#!/usr/bin/env python3
"""
Forex Trading Robot - Performance Reporting
==========================================

This module provides comprehensive performance reporting capabilities for the Forex trading robot,
including CSV exports, chart generation, and performance analysis.

Author: Forex Trading Robot
Date: 2024
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from datetime import datetime, timedelta
import json
import os
from typing import Dict, List, Tuple, Optional
import warnings
warnings.filterwarnings('ignore')

class PerformanceReporter:
    """
    Comprehensive performance reporting for Forex trading strategy.
    """
    
    def __init__(self, config_file: str = "config.ini"):
        """
        Initialize the performance reporter.
        
        Args:
            config_file: Path to configuration file
        """
        self.config = self.load_config(config_file)
        self.initial_balance = self.config.get('BACKTEST_INITIAL_BALANCE', 10.0)
        
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
    
    def generate_comprehensive_report(self, backtest_results: Dict, 
                                    monte_carlo_results: Dict = None,
                                    walk_forward_results: Dict = None,
                                    output_dir: str = "reports") -> None:
        """
        Generate comprehensive performance report.
        
        Args:
            backtest_results: Backtest results dictionary
            monte_carlo_results: Monte Carlo simulation results
            walk_forward_results: Walk-forward analysis results
            output_dir: Output directory for reports
        """
        os.makedirs(output_dir, exist_ok=True)
        
        print("Generating comprehensive performance report...")
        
        # Generate individual reports
        self.generate_trades_report(backtest_results, output_dir)
        self.generate_equity_curve_report(backtest_results, output_dir)
        self.generate_performance_metrics_report(backtest_results, output_dir)
        self.generate_daily_performance_report(backtest_results, output_dir)
        self.generate_monthly_performance_report(backtest_results, output_dir)
        
        # Generate charts
        self.generate_performance_charts(backtest_results, output_dir)
        self.generate_risk_analysis_charts(backtest_results, output_dir)
        
        # Generate Monte Carlo reports if available
        if monte_carlo_results:
            self.generate_monte_carlo_reports(monte_carlo_results, output_dir)
        
        # Generate walk-forward reports if available
        if walk_forward_results:
            self.generate_walk_forward_reports(walk_forward_results, output_dir)
        
        # Generate summary report
        self.generate_summary_report(backtest_results, monte_carlo_results, 
                                   walk_forward_results, output_dir)
        
        print(f"Comprehensive report generated in {output_dir}/")
    
    def generate_trades_report(self, backtest_results: Dict, output_dir: str) -> None:
        """
        Generate detailed trades report.
        
        Args:
            backtest_results: Backtest results dictionary
            output_dir: Output directory for reports
        """
        if not backtest_results.get('all_trades'):
            print("No trades data available for trades report")
            return
        
        df_trades = pd.DataFrame(backtest_results['all_trades'])
        
        # Add additional columns
        df_trades['duration_hours'] = df_trades['duration'].dt.total_seconds() / 3600
        df_trades['return_pct'] = (df_trades['pnl'] / self.initial_balance) * 100
        df_trades['win_loss'] = df_trades['pnl'].apply(lambda x: 'Win' if x > 0 else 'Loss')
        
        # Save detailed trades CSV
        df_trades.to_csv(f"{output_dir}/trades_detailed.csv", index=False)
        
        # Generate trades summary
        trades_summary = {
            'total_trades': len(df_trades),
            'winning_trades': len(df_trades[df_trades['pnl'] > 0]),
            'losing_trades': len(df_trades[df_trades['pnl'] < 0]),
            'avg_trade_duration_hours': df_trades['duration_hours'].mean(),
            'avg_winning_trade': df_trades[df_trades['pnl'] > 0]['pnl'].mean(),
            'avg_losing_trade': df_trades[df_trades['pnl'] < 0]['pnl'].mean(),
            'largest_win': df_trades['pnl'].max(),
            'largest_loss': df_trades['pnl'].min(),
            'avg_return_per_trade': df_trades['return_pct'].mean()
        }
        
        with open(f"{output_dir}/trades_summary.json", 'w') as f:
            json.dump(trades_summary, f, indent=2, default=str)
        
        print(f"Trades report saved to {output_dir}/trades_detailed.csv")
    
    def generate_equity_curve_report(self, backtest_results: Dict, output_dir: str) -> None:
        """
        Generate equity curve report.
        
        Args:
            backtest_results: Backtest results dictionary
            output_dir: Output directory for reports
        """
        if backtest_results.get('equity_curve') is None or backtest_results['equity_curve'].empty:
            print("No equity curve data available")
            return
        
        df_equity = backtest_results['equity_curve'].copy()
        
        # Calculate additional metrics
        df_equity['cumulative_return'] = (df_equity['balance'] / self.initial_balance - 1) * 100
        df_equity['daily_return'] = df_equity['balance'].pct_change() * 100
        
        # Calculate drawdown
        df_equity['running_max'] = df_equity['balance'].expanding().max()
        df_equity['drawdown'] = df_equity['balance'] - df_equity['running_max']
        df_equity['drawdown_pct'] = (df_equity['drawdown'] / df_equity['running_max']) * 100
        
        # Save equity curve CSV
        df_equity.to_csv(f"{output_dir}/equity_curve_detailed.csv", index=False)
        
        # Generate equity curve summary
        equity_summary = {
            'initial_balance': self.initial_balance,
            'final_balance': df_equity['balance'].iloc[-1],
            'total_return': df_equity['cumulative_return'].iloc[-1],
            'max_balance': df_equity['balance'].max(),
            'min_balance': df_equity['balance'].min(),
            'max_drawdown': df_equity['drawdown'].min(),
            'max_drawdown_pct': df_equity['drawdown_pct'].min(),
            'avg_daily_return': df_equity['daily_return'].mean(),
            'std_daily_return': df_equity['daily_return'].std(),
            'sharpe_ratio': df_equity['daily_return'].mean() / df_equity['daily_return'].std() * np.sqrt(252) if df_equity['daily_return'].std() > 0 else 0
        }
        
        with open(f"{output_dir}/equity_curve_summary.json", 'w') as f:
            json.dump(equity_summary, f, indent=2, default=str)
        
        print(f"Equity curve report saved to {output_dir}/equity_curve_detailed.csv")
    
    def generate_performance_metrics_report(self, backtest_results: Dict, output_dir: str) -> None:
        """
        Generate performance metrics report.
        
        Args:
            backtest_results: Backtest results dictionary
            output_dir: Output directory for reports
        """
        if not backtest_results.get('overall_metrics'):
            print("No performance metrics available")
            return
        
        metrics = backtest_results['overall_metrics']
        
        # Add target comparison
        total_return = metrics.get('net_profit', 0) / self.initial_balance * 100
        target_comparison = {
            'actual_return': total_return,
            'day1_target': self.day1_target,
            'day2_target': self.day2_target,
            'day3_plus_min_target': self.day3_plus_min,
            'day3_plus_max_target': self.day3_plus_max,
            'met_day1_target': total_return >= self.day1_target,
            'met_day2_target': total_return >= self.day2_target,
            'met_day3_min_target': total_return >= self.day3_plus_min,
            'target_performance': self.calculate_target_performance(total_return)
        }
        
        # Combine metrics with target comparison
        full_metrics = {**metrics, **target_comparison}
        
        # Save performance metrics
        with open(f"{output_dir}/performance_metrics_detailed.json", 'w') as f:
            json.dump(full_metrics, f, indent=2, default=str)
        
        print(f"Performance metrics report saved to {output_dir}/performance_metrics_detailed.json")
    
    def calculate_target_performance(self, actual_return: float) -> str:
        """
        Calculate target performance rating.
        
        Args:
            actual_return: Actual return percentage
            
        Returns:
            Performance rating string
        """
        if actual_return >= self.day1_target:
            return "EXCEPTIONAL - Exceeded Day 1 target"
        elif actual_return >= self.day2_target:
            return "EXCELLENT - Exceeded Day 2 target"
        elif actual_return >= self.day3_plus_max:
            return "VERY GOOD - Exceeded Day 3+ maximum target"
        elif actual_return >= self.day3_plus_min:
            return "GOOD - Met Day 3+ minimum target"
        elif actual_return >= 0:
            return "ACCEPTABLE - Positive return"
        else:
            return "POOR - Negative return"
    
    def generate_daily_performance_report(self, backtest_results: Dict, output_dir: str) -> None:
        """
        Generate daily performance report.
        
        Args:
            backtest_results: Backtest results dictionary
            output_dir: Output directory for reports
        """
        if not backtest_results.get('all_trades'):
            print("No trades data available for daily performance report")
            return
        
        df_trades = pd.DataFrame(backtest_results['all_trades'])
        df_trades['exit_time'] = pd.to_datetime(df_trades['exit_time'])
        df_trades['date'] = df_trades['exit_time'].dt.date
        
        # Group by date
        daily_performance = df_trades.groupby('date').agg({
            'pnl': ['sum', 'count', 'mean'],
            'symbol': 'nunique'
        }).round(2)
        
        daily_performance.columns = ['daily_pnl', 'num_trades', 'avg_trade_pnl', 'num_symbols']
        daily_performance['cumulative_pnl'] = daily_performance['daily_pnl'].cumsum()
        daily_performance['cumulative_return_pct'] = (daily_performance['cumulative_pnl'] / self.initial_balance) * 100
        
        # Add win/loss days
        daily_performance['winning_day'] = daily_performance['daily_pnl'] > 0
        daily_performance['daily_return_pct'] = (daily_performance['daily_pnl'] / self.initial_balance) * 100
        
        # Save daily performance CSV
        daily_performance.to_csv(f"{output_dir}/daily_performance.csv")
        
        # Generate daily performance summary
        daily_summary = {
            'total_days': len(daily_performance),
            'winning_days': daily_performance['winning_day'].sum(),
            'losing_days': (~daily_performance['winning_day']).sum(),
            'win_rate_days': daily_performance['winning_day'].mean() * 100,
            'avg_daily_pnl': daily_performance['daily_pnl'].mean(),
            'std_daily_pnl': daily_performance['daily_pnl'].std(),
            'best_day': daily_performance['daily_pnl'].max(),
            'worst_day': daily_performance['daily_pnl'].min(),
            'avg_trades_per_day': daily_performance['num_trades'].mean(),
            'max_trades_per_day': daily_performance['num_trades'].max()
        }
        
        with open(f"{output_dir}/daily_performance_summary.json", 'w') as f:
            json.dump(daily_summary, f, indent=2, default=str)
        
        print(f"Daily performance report saved to {output_dir}/daily_performance.csv")
    
    def generate_monthly_performance_report(self, backtest_results: Dict, output_dir: str) -> None:
        """
        Generate monthly performance report.
        
        Args:
            backtest_results: Backtest results dictionary
            output_dir: Output directory for reports
        """
        if not backtest_results.get('all_trades'):
            print("No trades data available for monthly performance report")
            return
        
        df_trades = pd.DataFrame(backtest_results['all_trades'])
        df_trades['exit_time'] = pd.to_datetime(df_trades['exit_time'])
        df_trades['year_month'] = df_trades['exit_time'].dt.to_period('M')
        
        # Group by month
        monthly_performance = df_trades.groupby('year_month').agg({
            'pnl': ['sum', 'count', 'mean'],
            'symbol': 'nunique'
        }).round(2)
        
        monthly_performance.columns = ['monthly_pnl', 'num_trades', 'avg_trade_pnl', 'num_symbols']
        monthly_performance['cumulative_pnl'] = monthly_performance['monthly_pnl'].cumsum()
        monthly_performance['monthly_return_pct'] = (monthly_performance['monthly_pnl'] / self.initial_balance) * 100
        monthly_performance['cumulative_return_pct'] = (monthly_performance['cumulative_pnl'] / self.initial_balance) * 100
        
        # Add win/loss months
        monthly_performance['winning_month'] = monthly_performance['monthly_pnl'] > 0
        
        # Save monthly performance CSV
        monthly_performance.to_csv(f"{output_dir}/monthly_performance.csv")
        
        # Generate monthly performance summary
        monthly_summary = {
            'total_months': len(monthly_performance),
            'winning_months': monthly_performance['winning_month'].sum(),
            'losing_months': (~monthly_performance['winning_month']).sum(),
            'win_rate_months': monthly_performance['winning_month'].mean() * 100,
            'avg_monthly_pnl': monthly_performance['monthly_pnl'].mean(),
            'std_monthly_pnl': monthly_performance['monthly_pnl'].std(),
            'best_month': monthly_performance['monthly_pnl'].max(),
            'worst_month': monthly_performance['monthly_pnl'].min(),
            'avg_trades_per_month': monthly_performance['num_trades'].mean(),
            'max_trades_per_month': monthly_performance['num_trades'].max()
        }
        
        with open(f"{output_dir}/monthly_performance_summary.json", 'w') as f:
            json.dump(monthly_summary, f, indent=2, default=str)
        
        print(f"Monthly performance report saved to {output_dir}/monthly_performance.csv")
    
    def generate_performance_charts(self, backtest_results: Dict, output_dir: str) -> None:
        """
        Generate performance analysis charts.
        
        Args:
            backtest_results: Backtest results dictionary
            output_dir: Output directory for charts
        """
        plt.style.use('seaborn-v0_8')
        
        # Create comprehensive performance dashboard
        fig = plt.figure(figsize=(20, 16))
        
        # 1. Equity Curve
        ax1 = plt.subplot(3, 3, 1)
        if backtest_results.get('equity_curve') is not None and not backtest_results['equity_curve'].empty:
            df_equity = backtest_results['equity_curve']
            ax1.plot(df_equity['time'], df_equity['balance'], linewidth=2, color='blue')
            ax1.set_title('Equity Curve', fontsize=14, fontweight='bold')
            ax1.set_xlabel('Date')
            ax1.set_ylabel('Account Balance ($)')
            ax1.grid(True, alpha=0.3)
        
        # 2. Drawdown Chart
        ax2 = plt.subplot(3, 3, 2)
        if backtest_results.get('equity_curve') is not None and not backtest_results['equity_curve'].empty:
            df_equity = backtest_results['equity_curve']
            df_equity['running_max'] = df_equity['balance'].expanding().max()
            df_equity['drawdown'] = df_equity['balance'] - df_equity['running_max']
            ax2.fill_between(df_equity['time'], df_equity['drawdown'], 0, 
                           color='red', alpha=0.3, label='Drawdown')
            ax2.set_title('Drawdown Chart', fontsize=14, fontweight='bold')
            ax2.set_xlabel('Date')
            ax2.set_ylabel('Drawdown ($)')
            ax2.grid(True, alpha=0.3)
        
        # 3. Win Rate Pie Chart
        ax3 = plt.subplot(3, 3, 3)
        if backtest_results.get('overall_metrics'):
            metrics = backtest_results['overall_metrics']
            winning_trades = metrics.get('winning_trades', 0)
            losing_trades = metrics.get('losing_trades', 0)
            if winning_trades + losing_trades > 0:
                ax3.pie([winning_trades, losing_trades], 
                       labels=['Winning Trades', 'Losing Trades'], 
                       autopct='%1.1f%%', colors=['green', 'red'])
                ax3.set_title('Win Rate Distribution', fontsize=14, fontweight='bold')
        
        # 4. Profit/Loss Bar Chart
        ax4 = plt.subplot(3, 3, 4)
        if backtest_results.get('overall_metrics'):
            metrics = backtest_results['overall_metrics']
            total_profit = metrics.get('total_profit', 0)
            total_loss = metrics.get('total_loss', 0)
            ax4.bar(['Total Profit', 'Total Loss'], [total_profit, total_loss], 
                   color=['green', 'red'])
            ax4.set_title('Profit vs Loss', fontsize=14, fontweight='bold')
            ax4.set_ylabel('Amount ($)')
        
        # 5. Monthly Returns
        ax5 = plt.subplot(3, 3, 5)
        if backtest_results.get('all_trades'):
            df_trades = pd.DataFrame(backtest_results['all_trades'])
            df_trades['exit_time'] = pd.to_datetime(df_trades['exit_time'])
            df_trades['year_month'] = df_trades['exit_time'].dt.to_period('M')
            monthly_pnl = df_trades.groupby('year_month')['pnl'].sum()
            
            colors = ['green' if x > 0 else 'red' for x in monthly_pnl.values]
            ax5.bar(range(len(monthly_pnl)), monthly_pnl.values, color=colors)
            ax5.set_title('Monthly P&L', fontsize=14, fontweight='bold')
            ax5.set_xlabel('Month')
            ax5.set_ylabel('P&L ($)')
        
        # 6. Trade Duration Distribution
        ax6 = plt.subplot(3, 3, 6)
        if backtest_results.get('all_trades'):
            df_trades = pd.DataFrame(backtest_results['all_trades'])
            df_trades['duration_hours'] = df_trades['duration'].dt.total_seconds() / 3600
            ax6.hist(df_trades['duration_hours'], bins=20, alpha=0.7, color='blue', edgecolor='black')
            ax6.set_title('Trade Duration Distribution', fontsize=14, fontweight='bold')
            ax6.set_xlabel('Duration (Hours)')
            ax6.set_ylabel('Frequency')
        
        # 7. P&L Distribution
        ax7 = plt.subplot(3, 3, 7)
        if backtest_results.get('all_trades'):
            df_trades = pd.DataFrame(backtest_results['all_trades'])
            ax7.hist(df_trades['pnl'], bins=30, alpha=0.7, color='purple', edgecolor='black')
            ax7.axvline(df_trades['pnl'].mean(), color='red', linestyle='--', 
                       label=f'Mean: ${df_trades["pnl"].mean():.2f}')
            ax7.set_title('P&L Distribution', fontsize=14, fontweight='bold')
            ax7.set_xlabel('P&L ($)')
            ax7.set_ylabel('Frequency')
            ax7.legend()
        
        # 8. Performance Metrics Table
        ax8 = plt.subplot(3, 3, 8)
        ax8.axis('off')
        if backtest_results.get('overall_metrics'):
            metrics = backtest_results['overall_metrics']
            metrics_text = f"""
            Total Trades: {metrics.get('total_trades', 0)}
            Win Rate: {metrics.get('win_rate', 0):.1f}%
            Net Profit: ${metrics.get('net_profit', 0):.2f}
            Profit Factor: {metrics.get('profit_factor', 0):.2f}
            Max Drawdown: ${metrics.get('max_drawdown', 0):.2f}
            Sharpe Ratio: {metrics.get('sharpe_ratio', 0):.2f}
            Expectancy: ${metrics.get('expectancy', 0):.2f}
            """
            ax8.text(0.1, 0.5, metrics_text, fontsize=12, 
                    verticalalignment='center', fontfamily='monospace')
            ax8.set_title('Performance Summary', fontsize=14, fontweight='bold')
        
        # 9. Target Performance
        ax9 = plt.subplot(3, 3, 9)
        if backtest_results.get('overall_metrics'):
            metrics = backtest_results['overall_metrics']
            total_return = metrics.get('net_profit', 0) / self.initial_balance * 100
            
            targets = [self.day1_target, self.day2_target, self.day3_plus_max, self.day3_plus_min]
            target_labels = ['Day 1', 'Day 2', 'Day 3+ Max', 'Day 3+ Min']
            
            bars = ax9.bar(target_labels, targets, color=['red', 'orange', 'yellow', 'green'], alpha=0.7)
            ax9.axhline(total_return, color='blue', linestyle='--', linewidth=2, 
                       label=f'Actual: {total_return:.1f}%')
            ax9.set_title('Target vs Actual Performance', fontsize=14, fontweight='bold')
            ax9.set_ylabel('Return (%)')
            ax9.legend()
            ax9.tick_params(axis='x', rotation=45)
        
        plt.tight_layout()
        plt.savefig(f"{output_dir}/performance_dashboard.png", dpi=300, bbox_inches='tight')
        plt.close()
        print(f"Performance dashboard saved to {output_dir}/performance_dashboard.png")
    
    def generate_risk_analysis_charts(self, backtest_results: Dict, output_dir: str) -> None:
        """
        Generate risk analysis charts.
        
        Args:
            backtest_results: Backtest results dictionary
            output_dir: Output directory for charts
        """
        plt.style.use('seaborn-v0_8')
        
        fig, axes = plt.subplots(2, 2, figsize=(15, 12))
        
        # 1. Drawdown Analysis
        ax1 = axes[0, 0]
        if backtest_results.get('equity_curve') is not None and not backtest_results['equity_curve'].empty:
            df_equity = backtest_results['equity_curve']
            df_equity['running_max'] = df_equity['balance'].expanding().max()
            df_equity['drawdown'] = df_equity['balance'] - df_equity['running_max']
            df_equity['drawdown_pct'] = (df_equity['drawdown'] / df_equity['running_max']) * 100
            
            ax1.plot(df_equity['time'], df_equity['drawdown_pct'], color='red', linewidth=2)
            ax1.fill_between(df_equity['time'], df_equity['drawdown_pct'], 0, 
                           color='red', alpha=0.3)
            ax1.set_title('Drawdown Percentage Over Time', fontsize=14, fontweight='bold')
            ax1.set_xlabel('Date')
            ax1.set_ylabel('Drawdown (%)')
            ax1.grid(True, alpha=0.3)
        
        # 2. Risk-Return Scatter
        ax2 = axes[0, 1]
        if backtest_results.get('all_trades'):
            df_trades = pd.DataFrame(backtest_results['all_trades'])
            df_trades['return_pct'] = (df_trades['pnl'] / self.initial_balance) * 100
            
            # Calculate rolling risk (standard deviation)
            window = min(20, len(df_trades))
            if window > 1:
                df_trades['rolling_risk'] = df_trades['return_pct'].rolling(window=window).std()
                df_trades['rolling_return'] = df_trades['return_pct'].rolling(window=window).mean()
                
                scatter = ax2.scatter(df_trades['rolling_risk'], df_trades['rolling_return'], 
                                    c=df_trades['pnl'], cmap='RdYlGn', alpha=0.6)
                ax2.set_title('Risk-Return Scatter Plot', fontsize=14, fontweight='bold')
                ax2.set_xlabel('Risk (Std Dev)')
                ax2.set_ylabel('Return (%)')
                plt.colorbar(scatter, ax=ax2, label='P&L ($)')
        
        # 3. Consecutive Wins/Losses
        ax3 = axes[1, 0]
        if backtest_results.get('all_trades'):
            df_trades = pd.DataFrame(backtest_results['all_trades'])
            df_trades['win'] = df_trades['pnl'] > 0
            
            # Calculate consecutive wins and losses
            consecutive_wins = []
            consecutive_losses = []
            current_wins = 0
            current_losses = 0
            
            for win in df_trades['win']:
                if win:
                    current_wins += 1
                    current_losses = 0
                    consecutive_wins.append(current_wins)
                    consecutive_losses.append(0)
                else:
                    current_losses += 1
                    current_wins = 0
                    consecutive_wins.append(0)
                    consecutive_losses.append(current_losses)
            
            df_trades['consecutive_wins'] = consecutive_wins
            df_trades['consecutive_losses'] = consecutive_losses
            
            ax3.hist(df_trades['consecutive_wins'], bins=range(1, df_trades['consecutive_wins'].max()+2), 
                    alpha=0.7, color='green', label='Consecutive Wins')
            ax3.hist(df_trades['consecutive_losses'], bins=range(1, df_trades['consecutive_losses'].max()+2), 
                    alpha=0.7, color='red', label='Consecutive Losses')
            ax3.set_title('Consecutive Wins/Losses Distribution', fontsize=14, fontweight='bold')
            ax3.set_xlabel('Consecutive Count')
            ax3.set_ylabel('Frequency')
            ax3.legend()
        
        # 4. Value at Risk (VaR)
        ax4 = axes[1, 1]
        if backtest_results.get('all_trades'):
            df_trades = pd.DataFrame(backtest_results['all_trades'])
            df_trades['return_pct'] = (df_trades['pnl'] / self.initial_balance) * 100
            
            # Calculate VaR at different confidence levels
            confidence_levels = [90, 95, 99]
            var_values = []
            
            for conf in confidence_levels:
                var = np.percentile(df_trades['return_pct'], 100 - conf)
                var_values.append(var)
            
            ax4.bar([f'{conf}%' for conf in confidence_levels], var_values, 
                   color=['green', 'orange', 'red'], alpha=0.7)
            ax4.set_title('Value at Risk (VaR)', fontsize=14, fontweight='bold')
            ax4.set_xlabel('Confidence Level')
            ax4.set_ylabel('VaR (%)')
            
            # Add VaR values as text
            for i, var in enumerate(var_values):
                ax4.text(i, var - 0.5, f'{var:.2f}%', ha='center', va='top', fontweight='bold')
        
        plt.tight_layout()
        plt.savefig(f"{output_dir}/risk_analysis.png", dpi=300, bbox_inches='tight')
        plt.close()
        print(f"Risk analysis chart saved to {output_dir}/risk_analysis.png")
    
    def generate_monte_carlo_reports(self, monte_carlo_results: Dict, output_dir: str) -> None:
        """
        Generate Monte Carlo simulation reports.
        
        Args:
            monte_carlo_results: Monte Carlo simulation results
            output_dir: Output directory for reports
        """
        if 'simulation_data' in monte_carlo_results:
            monte_carlo_results['simulation_data'].to_csv(f"{output_dir}/monte_carlo_simulation.csv", index=False)
            print(f"Monte Carlo simulation data saved to {output_dir}/monte_carlo_simulation.csv")
        
        if 'confidence_intervals' in monte_carlo_results:
            with open(f"{output_dir}/monte_carlo_confidence_intervals.json", 'w') as f:
                json.dump(monte_carlo_results['confidence_intervals'], f, indent=2, default=str)
            print(f"Monte Carlo confidence intervals saved to {output_dir}/monte_carlo_confidence_intervals.json")
        
        if 'target_probabilities' in monte_carlo_results:
            with open(f"{output_dir}/monte_carlo_target_probabilities.json", 'w') as f:
                json.dump(monte_carlo_results['target_probabilities'], f, indent=2, default=str)
            print(f"Monte Carlo target probabilities saved to {output_dir}/monte_carlo_target_probabilities.json")
    
    def generate_walk_forward_reports(self, walk_forward_results: Dict, output_dir: str) -> None:
        """
        Generate walk-forward analysis reports.
        
        Args:
            walk_forward_results: Walk-forward analysis results
            output_dir: Output directory for reports
        """
        if 'period_results' in walk_forward_results:
            df_walk_forward = pd.DataFrame(walk_forward_results['period_results'])
            df_walk_forward.to_csv(f"{output_dir}/walk_forward_analysis.csv", index=False)
            print(f"Walk-forward analysis saved to {output_dir}/walk_forward_analysis.csv")
        
        if 'summary_statistics' in walk_forward_results:
            with open(f"{output_dir}/walk_forward_summary.json", 'w') as f:
                json.dump(walk_forward_results['summary_statistics'], f, indent=2, default=str)
            print(f"Walk-forward summary saved to {output_dir}/walk_forward_summary.json")
    
    def generate_summary_report(self, backtest_results: Dict, 
                              monte_carlo_results: Dict = None,
                              walk_forward_results: Dict = None,
                              output_dir: str = "reports") -> None:
        """
        Generate comprehensive summary report.
        
        Args:
            backtest_results: Backtest results dictionary
            monte_carlo_results: Monte Carlo simulation results
            walk_forward_results: Walk-forward analysis results
            output_dir: Output directory for reports
        """
        summary = {
            'report_generated': datetime.now().isoformat(),
            'strategy_name': 'Forex Trading Robot - Hybrid Strategy',
            'backtest_period': '2019-2024',
            'initial_balance': self.initial_balance,
            'performance_targets': {
                'day1_target': self.day1_target,
                'day2_target': self.day2_target,
                'day3_plus_min_target': self.day3_plus_min,
                'day3_plus_max_target': self.day3_plus_max
            }
        }
        
        # Add backtest results
        if backtest_results.get('overall_metrics'):
            summary['backtest_results'] = backtest_results['overall_metrics']
            
            # Calculate target performance
            total_return = backtest_results['overall_metrics'].get('net_profit', 0) / self.initial_balance * 100
            summary['target_performance'] = self.calculate_target_performance(total_return)
        
        # Add Monte Carlo results
        if monte_carlo_results and 'statistics' in monte_carlo_results:
            summary['monte_carlo_results'] = monte_carlo_results['statistics']
        
        # Add walk-forward results
        if walk_forward_results and 'summary_statistics' in walk_forward_results:
            summary['walk_forward_results'] = walk_forward_results['summary_statistics']
        
        # Save summary report
        with open(f"{output_dir}/comprehensive_summary.json", 'w') as f:
            json.dump(summary, f, indent=2, default=str)
        
        print(f"Comprehensive summary report saved to {output_dir}/comprehensive_summary.json")
        
        # Print summary to console
        self.print_summary_to_console(summary)
    
    def print_summary_to_console(self, summary: Dict) -> None:
        """
        Print summary report to console.
        
        Args:
            summary: Summary dictionary
        """
        print("\n" + "="*80)
        print("COMPREHENSIVE PERFORMANCE REPORT SUMMARY")
        print("="*80)
        print(f"Report Generated: {summary['report_generated']}")
        print(f"Strategy: {summary['strategy_name']}")
        print(f"Backtest Period: {summary['backtest_period']}")
        print(f"Initial Balance: ${summary['initial_balance']:.2f}")
        
        if 'backtest_results' in summary:
            results = summary['backtest_results']
            print(f"\nBACKTEST RESULTS:")
            print(f"Final Balance: ${summary['initial_balance'] + results.get('net_profit', 0):.2f}")
            print(f"Total Return: {((summary['initial_balance'] + results.get('net_profit', 0)) / summary['initial_balance'] - 1) * 100:.2f}%")
            print(f"Net Profit: ${results.get('net_profit', 0):.2f}")
            print(f"Total Trades: {results.get('total_trades', 0)}")
            print(f"Win Rate: {results.get('win_rate', 0):.1f}%")
            print(f"Profit Factor: {results.get('profit_factor', 0):.2f}")
            print(f"Max Drawdown: ${results.get('max_drawdown', 0):.2f}")
            print(f"Sharpe Ratio: {results.get('sharpe_ratio', 0):.2f}")
            print(f"Expectancy: ${results.get('expectancy', 0):.2f}")
        
        if 'target_performance' in summary:
            print(f"\nTARGET PERFORMANCE: {summary['target_performance']}")
        
        if 'monte_carlo_results' in summary:
            mc_results = summary['monte_carlo_results']
            print(f"\nMONTE CARLO SIMULATION:")
            print(f"Mean Final Balance: ${mc_results.get('mean_final_balance', 0):.2f}")
            print(f"Mean Total Return: {mc_results.get('mean_total_return', 0):.2f}%")
            print(f"Worst Case Return: {mc_results.get('worst_case_return', 0):.2f}%")
            print(f"Best Case Return: {mc_results.get('best_case_return', 0):.2f}%")
        
        if 'walk_forward_results' in summary:
            wf_results = summary['walk_forward_results']
            print(f"\nWALK-FORWARD ANALYSIS:")
            print(f"Total Periods: {wf_results.get('total_periods', 0)}")
            print(f"Profitable Periods: {wf_results.get('profitable_periods', 0)}")
            print(f"Profitable Period Rate: {wf_results.get('profitable_period_rate', 0):.1f}%")
            print(f"Average Return per Period: {wf_results.get('avg_return_per_period', 0):.2f}%")
        
        print("="*80)


def main():
    """
    Main function to run performance reporting.
    """
    print("Performance reporting module loaded successfully!")
    print("Use this module with actual backtest results to generate comprehensive reports.")


if __name__ == "__main__":
    main()
