#!/usr/bin/env python3
"""
Forex Trading Robot - Monte Carlo Simulation
==========================================

This module provides Monte Carlo simulation capabilities for the Forex trading robot,
including statistical analysis of trading results and walk-forward testing.

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
from scipy import stats
import warnings
warnings.filterwarnings('ignore')

class MonteCarloSimulator:
    """
    Monte Carlo simulation for Forex trading strategy analysis.
    """
    
    def __init__(self, config_file: str = "config.ini"):
        """
        Initialize the Monte Carlo simulator.
        
        Args:
            config_file: Path to configuration file
        """
        self.config = self.load_config(config_file)
        self.simulation_runs = self.config.get('MONTE_CARLO_RUNS', 1000)
        self.confidence_level = self.config.get('MONTE_CARLO_CONFIDENCE_LEVEL', 95.0)
        self.initial_balance = self.config.get('BACKTEST_INITIAL_BALANCE', 10.0)
        
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
    
    def run_monte_carlo_simulation(self, trades: List[Dict], num_runs: int = None) -> Dict:
        """
        Run Monte Carlo simulation on trading results.
        
        Args:
            trades: List of completed trades
            num_runs: Number of simulation runs (default from config)
            
        Returns:
            Dictionary with simulation results
        """
        if not trades:
            print("No trades provided for Monte Carlo simulation")
            return {}
        
        if num_runs is None:
            num_runs = self.simulation_runs
        
        print(f"Running Monte Carlo simulation with {num_runs} runs...")
        
        # Extract trade returns
        trade_returns = [trade['pnl'] for trade in trades]
        
        # Calculate statistics
        mean_return = np.mean(trade_returns)
        std_return = np.std(trade_returns)
        
        # Run simulations
        simulation_results = []
        
        for run in range(num_runs):
            # Randomly sample trades with replacement
            simulated_trades = np.random.choice(trade_returns, size=len(trade_returns), replace=True)
            
            # Calculate final balance
            final_balance = self.initial_balance + np.sum(simulated_trades)
            total_return = (final_balance / self.initial_balance - 1) * 100
            
            # Calculate other metrics
            winning_trades = np.sum(simulated_trades > 0)
            losing_trades = np.sum(simulated_trades < 0)
            win_rate = winning_trades / len(simulated_trades) * 100 if len(simulated_trades) > 0 else 0
            
            max_drawdown = self.calculate_max_drawdown(simulated_trades)
            
            simulation_results.append({
                'run': run,
                'final_balance': final_balance,
                'total_return': total_return,
                'win_rate': win_rate,
                'max_drawdown': max_drawdown,
                'net_profit': np.sum(simulated_trades)
            })
        
        # Calculate statistics
        results_df = pd.DataFrame(simulation_results)
        
        # Calculate confidence intervals
        alpha = (100 - self.confidence_level) / 100
        confidence_intervals = self.calculate_confidence_intervals(results_df, alpha)
        
        # Calculate probability of meeting targets
        target_probabilities = self.calculate_target_probabilities(results_df)
        
        simulation_results = {
            'simulation_data': results_df,
            'confidence_intervals': confidence_intervals,
            'target_probabilities': target_probabilities,
            'statistics': {
                'mean_final_balance': results_df['final_balance'].mean(),
                'std_final_balance': results_df['final_balance'].std(),
                'mean_total_return': results_df['total_return'].mean(),
                'std_total_return': results_df['total_return'].std(),
                'mean_win_rate': results_df['win_rate'].mean(),
                'mean_max_drawdown': results_df['max_drawdown'].mean(),
                'worst_case_return': results_df['total_return'].min(),
                'best_case_return': results_df['total_return'].max()
            }
        }
        
        return simulation_results
    
    def calculate_max_drawdown(self, returns: np.ndarray) -> float:
        """
        Calculate maximum drawdown from returns.
        
        Args:
            returns: Array of trade returns
            
        Returns:
            Maximum drawdown value
        """
        cumulative_returns = np.cumsum(returns)
        running_max = np.maximum.accumulate(cumulative_returns)
        drawdown = running_max - cumulative_returns
        return np.max(drawdown) if len(drawdown) > 0 else 0
    
    def calculate_confidence_intervals(self, results_df: pd.DataFrame, alpha: float) -> Dict:
        """
        Calculate confidence intervals for key metrics.
        
        Args:
            results_df: DataFrame with simulation results
            alpha: Significance level
            
        Returns:
            Dictionary with confidence intervals
        """
        confidence_intervals = {}
        
        metrics = ['final_balance', 'total_return', 'win_rate', 'max_drawdown']
        
        for metric in metrics:
            values = results_df[metric].values
            lower_percentile = (alpha / 2) * 100
            upper_percentile = (1 - alpha / 2) * 100
            
            confidence_intervals[metric] = {
                'lower': np.percentile(values, lower_percentile),
                'upper': np.percentile(values, upper_percentile),
                'mean': np.mean(values),
                'std': np.std(values)
            }
        
        return confidence_intervals
    
    def calculate_target_probabilities(self, results_df: pd.DataFrame) -> Dict:
        """
        Calculate probability of meeting various targets.
        
        Args:
            results_df: DataFrame with simulation results
            
        Returns:
            Dictionary with target probabilities
        """
        target_probabilities = {}
        
        # Day 1 target (900%)
        day1_target = 900.0
        day1_prob = np.sum(results_df['total_return'] >= day1_target) / len(results_df) * 100
        target_probabilities['day1_target'] = {
            'target': day1_target,
            'probability': day1_prob
        }
        
        # Day 2 target (200%)
        day2_target = 200.0
        day2_prob = np.sum(results_df['total_return'] >= day2_target) / len(results_df) * 100
        target_probabilities['day2_target'] = {
            'target': day2_target,
            'probability': day2_prob
        }
        
        # Day 3+ minimum target (2%)
        day3_min_target = 2.0
        day3_min_prob = np.sum(results_df['total_return'] >= day3_min_target) / len(results_df) * 100
        target_probabilities['day3_min_target'] = {
            'target': day3_min_target,
            'probability': day3_min_prob
        }
        
        # Break-even probability
        breakeven_prob = np.sum(results_df['total_return'] >= 0) / len(results_df) * 100
        target_probabilities['breakeven'] = {
            'target': 0.0,
            'probability': breakeven_prob
        }
        
        # Loss probability
        loss_prob = np.sum(results_df['total_return'] < 0) / len(results_df) * 100
        target_probabilities['loss'] = {
            'target': 0.0,
            'probability': loss_prob
        }
        
        return target_probabilities
    
    def run_walk_forward_analysis(self, trades: List[Dict], 
                                period_months: int = 12, 
                                step_months: int = 1) -> Dict:
        """
        Run walk-forward analysis on trading results.
        
        Args:
            trades: List of completed trades
            period_months: Period length in months
            step_months: Step size in months
            
        Returns:
            Dictionary with walk-forward results
        """
        if not trades:
            print("No trades provided for walk-forward analysis")
            return {}
        
        print(f"Running walk-forward analysis...")
        
        # Convert trades to DataFrame
        df_trades = pd.DataFrame(trades)
        df_trades['exit_time'] = pd.to_datetime(df_trades['exit_time'])
        df_trades = df_trades.sort_values('exit_time')
        
        # Get date range
        start_date = df_trades['exit_time'].min()
        end_date = df_trades['exit_time'].max()
        
        walk_forward_results = []
        
        current_date = start_date
        period_num = 0
        
        while current_date + pd.DateOffset(months=period_months) <= end_date:
            period_start = current_date
            period_end = current_date + pd.DateOffset(months=period_months)
            
            # Filter trades for this period
            period_trades = df_trades[
                (df_trades['exit_time'] >= period_start) & 
                (df_trades['exit_time'] < period_end)
            ]
            
            if len(period_trades) > 0:
                # Calculate metrics for this period
                period_metrics = self.calculate_period_metrics(period_trades)
                period_metrics['period'] = period_num
                period_metrics['start_date'] = period_start
                period_metrics['end_date'] = period_end
                period_metrics['num_trades'] = len(period_trades)
                
                walk_forward_results.append(period_metrics)
            
            # Move to next period
            current_date += pd.DateOffset(months=step_months)
            period_num += 1
        
        # Calculate overall statistics
        if walk_forward_results:
            results_df = pd.DataFrame(walk_forward_results)
            
            walk_forward_summary = {
                'period_results': walk_forward_results,
                'summary_statistics': {
                    'total_periods': len(walk_forward_results),
                    'avg_trades_per_period': results_df['num_trades'].mean(),
                    'avg_return_per_period': results_df['total_return'].mean(),
                    'std_return_per_period': results_df['total_return'].std(),
                    'avg_win_rate': results_df['win_rate'].mean(),
                    'avg_profit_factor': results_df['profit_factor'].mean(),
                    'avg_max_drawdown': results_df['max_drawdown'].mean(),
                    'profitable_periods': len(results_df[results_df['total_return'] > 0]),
                    'profitable_period_rate': len(results_df[results_df['total_return'] > 0]) / len(results_df) * 100
                }
            }
        else:
            walk_forward_summary = {'period_results': [], 'summary_statistics': {}}
        
        return walk_forward_summary
    
    def calculate_period_metrics(self, period_trades: pd.DataFrame) -> Dict:
        """
        Calculate performance metrics for a specific period.
        
        Args:
            period_trades: DataFrame with trades for the period
            
        Returns:
            Dictionary with period metrics
        """
        if len(period_trades) == 0:
            return {}
        
        total_trades = len(period_trades)
        winning_trades = len(period_trades[period_trades['pnl'] > 0])
        losing_trades = len(period_trades[period_trades['pnl'] < 0])
        
        total_profit = period_trades[period_trades['pnl'] > 0]['pnl'].sum()
        total_loss = abs(period_trades[period_trades['pnl'] < 0]['pnl'].sum())
        
        net_profit = period_trades['pnl'].sum()
        win_rate = winning_trades / total_trades * 100 if total_trades > 0 else 0
        profit_factor = total_profit / total_loss if total_loss > 0 else float('inf')
        
        # Calculate return percentage
        total_return = (net_profit / self.initial_balance) * 100
        
        # Calculate max drawdown
        returns = period_trades['pnl'].values
        max_drawdown = self.calculate_max_drawdown(returns)
        
        metrics = {
            'total_trades': total_trades,
            'winning_trades': winning_trades,
            'losing_trades': losing_trades,
            'win_rate': win_rate,
            'net_profit': net_profit,
            'total_return': total_return,
            'profit_factor': profit_factor,
            'max_drawdown': max_drawdown
        }
        
        return metrics
    
    def generate_monte_carlo_report(self, simulation_results: Dict, output_dir: str = "reports") -> None:
        """
        Generate Monte Carlo simulation report.
        
        Args:
            simulation_results: Simulation results dictionary
            output_dir: Output directory for reports
        """
        os.makedirs(output_dir, exist_ok=True)
        
        # Save simulation data
        if 'simulation_data' in simulation_results:
            simulation_results['simulation_data'].to_csv(f"{output_dir}/monte_carlo_simulation.csv", index=False)
            print(f"Monte Carlo simulation data saved to {output_dir}/monte_carlo_simulation.csv")
        
        # Save confidence intervals
        with open(f"{output_dir}/monte_carlo_confidence_intervals.json", 'w') as f:
            json.dump(simulation_results['confidence_intervals'], f, indent=2, default=str)
        print(f"Confidence intervals saved to {output_dir}/monte_carlo_confidence_intervals.json")
        
        # Save target probabilities
        with open(f"{output_dir}/monte_carlo_target_probabilities.json", 'w') as f:
            json.dump(simulation_results['target_probabilities'], f, indent=2, default=str)
        print(f"Target probabilities saved to {output_dir}/monte_carlo_target_probabilities.json")
        
        # Generate charts
        self.generate_monte_carlo_charts(simulation_results, output_dir)
        
        # Print summary
        self.print_monte_carlo_summary(simulation_results)
    
    def generate_monte_carlo_charts(self, simulation_results: Dict, output_dir: str) -> None:
        """
        Generate Monte Carlo simulation charts.
        
        Args:
            simulation_results: Simulation results dictionary
            output_dir: Output directory for charts
        """
        plt.style.use('seaborn-v0_8')
        
        if 'simulation_data' not in simulation_results:
            return
        
        results_df = simulation_results['simulation_data']
        
        # Create figure with subplots
        fig, axes = plt.subplots(2, 2, figsize=(15, 12))
        
        # Final balance distribution
        axes[0, 0].hist(results_df['final_balance'], bins=50, alpha=0.7, color='blue', edgecolor='black')
        axes[0, 0].axvline(results_df['final_balance'].mean(), color='red', linestyle='--', 
                          label=f'Mean: ${results_df["final_balance"].mean():.2f}')
        axes[0, 0].set_title('Final Balance Distribution')
        axes[0, 0].set_xlabel('Final Balance ($)')
        axes[0, 0].set_ylabel('Frequency')
        axes[0, 0].legend()
        axes[0, 0].grid(True, alpha=0.3)
        
        # Total return distribution
        axes[0, 1].hist(results_df['total_return'], bins=50, alpha=0.7, color='green', edgecolor='black')
        axes[0, 1].axvline(results_df['total_return'].mean(), color='red', linestyle='--', 
                         label=f'Mean: {results_df["total_return"].mean():.1f}%')
        axes[0, 1].set_title('Total Return Distribution')
        axes[0, 1].set_xlabel('Total Return (%)')
        axes[0, 1].set_ylabel('Frequency')
        axes[0, 1].legend()
        axes[0, 1].grid(True, alpha=0.3)
        
        # Win rate distribution
        axes[1, 0].hist(results_df['win_rate'], bins=30, alpha=0.7, color='orange', edgecolor='black')
        axes[1, 0].axvline(results_df['win_rate'].mean(), color='red', linestyle='--', 
                          label=f'Mean: {results_df["win_rate"].mean():.1f}%')
        axes[1, 0].set_title('Win Rate Distribution')
        axes[1, 0].set_xlabel('Win Rate (%)')
        axes[1, 0].set_ylabel('Frequency')
        axes[1, 0].legend()
        axes[1, 0].grid(True, alpha=0.3)
        
        # Max drawdown distribution
        axes[1, 1].hist(results_df['max_drawdown'], bins=30, alpha=0.7, color='red', edgecolor='black')
        axes[1, 1].axvline(results_df['max_drawdown'].mean(), color='blue', linestyle='--', 
                          label=f'Mean: ${results_df["max_drawdown"].mean():.2f}')
        axes[1, 1].set_title('Max Drawdown Distribution')
        axes[1, 1].set_xlabel('Max Drawdown ($)')
        axes[1, 1].set_ylabel('Frequency')
        axes[1, 1].legend()
        axes[1, 1].grid(True, alpha=0.3)
        
        plt.tight_layout()
        plt.savefig(f"{output_dir}/monte_carlo_distributions.png", dpi=300, bbox_inches='tight')
        plt.close()
        print(f"Monte Carlo distributions chart saved to {output_dir}/monte_carlo_distributions.png")
        
        # Confidence intervals chart
        if 'confidence_intervals' in simulation_results:
            self.plot_confidence_intervals(simulation_results['confidence_intervals'], output_dir)
    
    def plot_confidence_intervals(self, confidence_intervals: Dict, output_dir: str) -> None:
        """
        Plot confidence intervals for key metrics.
        
        Args:
            confidence_intervals: Confidence intervals dictionary
            output_dir: Output directory for charts
        """
        metrics = ['final_balance', 'total_return', 'win_rate', 'max_drawdown']
        metric_labels = ['Final Balance ($)', 'Total Return (%)', 'Win Rate (%)', 'Max Drawdown ($)']
        
        fig, ax = plt.subplots(figsize=(12, 8))
        
        x_pos = np.arange(len(metrics))
        means = [confidence_intervals[metric]['mean'] for metric in metrics]
        lowers = [confidence_intervals[metric]['lower'] for metric in metrics]
        uppers = [confidence_intervals[metric]['upper'] for metric in metrics]
        
        # Calculate error bars
        lower_errors = [means[i] - lowers[i] for i in range(len(metrics))]
        upper_errors = [uppers[i] - means[i] for i in range(len(metrics))]
        
        # Plot bars with error bars
        bars = ax.bar(x_pos, means, yerr=[lower_errors, upper_errors], 
                     capsize=5, alpha=0.7, color=['blue', 'green', 'orange', 'red'])
        
        # Add value labels on bars
        for i, (bar, mean) in enumerate(zip(bars, means)):
            ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + upper_errors[i] + 0.1,
                   f'{mean:.2f}', ha='center', va='bottom', fontweight='bold')
        
        ax.set_xlabel('Metrics', fontsize=12)
        ax.set_ylabel('Values', fontsize=12)
        ax.set_title(f'Monte Carlo Confidence Intervals ({self.confidence_level}%)', fontsize=14, fontweight='bold')
        ax.set_xticks(x_pos)
        ax.set_xticklabels(metric_labels, rotation=45, ha='right')
        ax.grid(True, alpha=0.3)
        
        plt.tight_layout()
        plt.savefig(f"{output_dir}/monte_carlo_confidence_intervals.png", dpi=300, bbox_inches='tight')
        plt.close()
        print(f"Confidence intervals chart saved to {output_dir}/monte_carlo_confidence_intervals.png")
    
    def print_monte_carlo_summary(self, simulation_results: Dict) -> None:
        """
        Print Monte Carlo simulation summary.
        
        Args:
            simulation_results: Simulation results dictionary
        """
        if 'statistics' not in simulation_results:
            return
        
        stats = simulation_results['statistics']
        target_probs = simulation_results['target_probabilities']
        
        print("\n" + "="*60)
        print("MONTE CARLO SIMULATION SUMMARY")
        print("="*60)
        print(f"Number of Simulations: {self.simulation_runs}")
        print(f"Confidence Level: {self.confidence_level}%")
        print(f"Initial Balance: ${self.initial_balance:.2f}")
        print()
        print("STATISTICS:")
        print(f"Mean Final Balance: ${stats['mean_final_balance']:.2f}")
        print(f"Std Final Balance: ${stats['std_final_balance']:.2f}")
        print(f"Mean Total Return: {stats['mean_total_return']:.2f}%")
        print(f"Std Total Return: {stats['std_total_return']:.2f}%")
        print(f"Mean Win Rate: {stats['mean_win_rate']:.1f}%")
        print(f"Mean Max Drawdown: ${stats['mean_max_drawdown']:.2f}")
        print(f"Worst Case Return: {stats['worst_case_return']:.2f}%")
        print(f"Best Case Return: {stats['best_case_return']:.2f}%")
        print()
        print("TARGET PROBABILITIES:")
        print(f"Day 1 Target ({target_probs['day1_target']['target']}%): {target_probs['day1_target']['probability']:.1f}%")
        print(f"Day 2 Target ({target_probs['day2_target']['target']}%): {target_probs['day2_target']['probability']:.1f}%")
        print(f"Day 3+ Min Target ({target_probs['day3_min_target']['target']}%): {target_probs['day3_min_target']['probability']:.1f}%")
        print(f"Break-even (0%): {target_probs['breakeven']['probability']:.1f}%")
        print(f"Loss (<0%): {target_probs['loss']['probability']:.1f}%")
        print("="*60)


def main():
    """
    Main function to run Monte Carlo simulation.
    """
    # This would typically be called with actual trade data
    # For demonstration, we'll create sample data
    print("Monte Carlo simulation module loaded successfully!")
    print("Use this module with actual trade data from backtesting.")


if __name__ == "__main__":
    main()
