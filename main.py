#!/usr/bin/env python3
"""
Forex Trading Robot - Main Execution Script
==========================================

This is the main execution script that runs the complete Forex trading robot system,
including backtesting, Monte Carlo simulation, and performance reporting.

Author: Forex Trading Robot
Date: 2024
"""

import os
import sys
import argparse
from datetime import datetime, timedelta
import json
import warnings
warnings.filterwarnings('ignore')

# Import our custom modules
from backtest import ForexBacktester
from monte_carlo import MonteCarloSimulator
from performance_reporter import PerformanceReporter

def main():
    """
    Main execution function for the Forex trading robot system.
    """
    parser = argparse.ArgumentParser(description='Forex Trading Robot - Complete System')
    parser.add_argument('--config', default='config.ini', help='Configuration file path')
    parser.add_argument('--start-date', default='2019-01-01', help='Backtest start date (YYYY-MM-DD)')
    parser.add_argument('--end-date', default='2024-12-31', help='Backtest end date (YYYY-MM-DD)')
    parser.add_argument('--output-dir', default='reports', help='Output directory for reports')
    parser.add_argument('--monte-carlo-runs', type=int, default=1000, help='Number of Monte Carlo runs')
    parser.add_argument('--skip-backtest', action='store_true', help='Skip backtesting (use existing results)')
    parser.add_argument('--skip-monte-carlo', action='store_true', help='Skip Monte Carlo simulation')
    parser.add_argument('--skip-walk-forward', action='store_true', help='Skip walk-forward analysis')
    parser.add_argument('--verbose', action='store_true', help='Enable verbose output')
    
    args = parser.parse_args()
    
    print("="*80)
    print("FOREX TRADING ROBOT - COMPLETE SYSTEM")
    print("="*80)
    print(f"Start Date: {args.start_date}")
    print(f"End Date: {args.end_date}")
    print(f"Output Directory: {args.output_dir}")
    print(f"Monte Carlo Runs: {args.monte_carlo_runs}")
    print("="*80)
    
    # Create output directory
    os.makedirs(args.output_dir, exist_ok=True)
    
    # Initialize components
    backtester = ForexBacktester(args.config)
    monte_carlo = MonteCarloSimulator(args.config)
    reporter = PerformanceReporter(args.config)
    
    # Run backtesting
    backtest_results = None
    if not args.skip_backtest:
        print("\n🔄 Running Backtesting...")
        backtest_results = backtester.run_backtest(args.start_date, args.end_date)
        
        if backtest_results and backtest_results.get('all_trades'):
            print(f"✅ Backtesting completed: {len(backtest_results['all_trades'])} trades generated")
        else:
            print("❌ Backtesting failed or no trades generated")
            return
    else:
        print("\n⏭️ Skipping backtesting (using existing results)")
        # Try to load existing results
        backtest_results = load_existing_results(args.output_dir)
        if not backtest_results:
            print("❌ No existing results found. Please run backtesting first.")
            return
    
    # Run Monte Carlo simulation
    monte_carlo_results = None
    if not args.skip_monte_carlo and backtest_results:
        print("\n🎲 Running Monte Carlo Simulation...")
        monte_carlo.simulation_runs = args.monte_carlo_runs
        monte_carlo_results = monte_carlo.run_monte_carlo_simulation(backtest_results['all_trades'])
        
        if monte_carlo_results:
            print(f"✅ Monte Carlo simulation completed: {args.monte_carlo_runs} runs")
        else:
            print("❌ Monte Carlo simulation failed")
    
    # Run walk-forward analysis
    walk_forward_results = None
    if not args.skip_walk_forward and backtest_results:
        print("\n📈 Running Walk-Forward Analysis...")
        walk_forward_results = monte_carlo.run_walk_forward_analysis(backtest_results['all_trades'])
        
        if walk_forward_results and walk_forward_results.get('period_results'):
            print(f"✅ Walk-forward analysis completed: {len(walk_forward_results['period_results'])} periods")
        else:
            print("❌ Walk-forward analysis failed")
    
    # Generate comprehensive reports
    print("\n📊 Generating Comprehensive Reports...")
    reporter.generate_comprehensive_report(
        backtest_results, 
        monte_carlo_results, 
        walk_forward_results, 
        args.output_dir
    )
    
    # Generate individual component reports
    if backtest_results:
        print("\n📈 Generating Backtest Reports...")
        backtester.generate_report(backtest_results, args.output_dir)
    
    if monte_carlo_results:
        print("\n🎲 Generating Monte Carlo Reports...")
        monte_carlo.generate_monte_carlo_report(monte_carlo_results, args.output_dir)
    
    # Generate demo trading plan
    print("\n📋 Generating Demo Trading Plan...")
    generate_demo_plan(backtest_results, args.output_dir)
    
    # Generate risk disclaimer
    print("\n⚠️ Generating Risk Disclaimer...")
    generate_risk_disclaimer(args.output_dir)
    
    # Print final summary
    print_final_summary(backtest_results, monte_carlo_results, walk_forward_results)
    
    print(f"\n🎉 Complete system execution finished!")
    print(f"📁 All reports saved to: {args.output_dir}/")
    print("="*80)

def load_existing_results(output_dir: str) -> dict:
    """
    Load existing backtest results from files.
    
    Args:
        output_dir: Output directory containing existing results
        
    Returns:
        Dictionary with existing results or None if not found
    """
    try:
        # Try to load trades
        trades_file = f"{output_dir}/trades.csv"
        if os.path.exists(trades_file):
            import pandas as pd
            df_trades = pd.read_csv(trades_file)
            trades = df_trades.to_dict('records')
            
            # Try to load performance metrics
            metrics_file = f"{output_dir}/performance_metrics.json"
            metrics = {}
            if os.path.exists(metrics_file):
                with open(metrics_file, 'r') as f:
                    metrics = json.load(f)
            
            # Try to load equity curve
            equity_file = f"{output_dir}/equity_curve.csv"
            equity_curve = pd.DataFrame()
            if os.path.exists(equity_file):
                equity_curve = pd.read_csv(equity_file)
                equity_curve['time'] = pd.to_datetime(equity_curve['time'])
            
            return {
                'all_trades': trades,
                'overall_metrics': metrics,
                'equity_curve': equity_curve
            }
    except Exception as e:
        print(f"Error loading existing results: {e}")
    
    return None

def generate_demo_plan(backtest_results: dict, output_dir: str) -> None:
    """
    Generate demo trading plan based on backtest results.
    
    Args:
        backtest_results: Backtest results dictionary
        output_dir: Output directory for reports
    """
    if not backtest_results or not backtest_results.get('all_trades'):
        print("No backtest results available for demo plan generation")
        return
    
    # Calculate key metrics
    trades = backtest_results['all_trades']
    total_trades = len(trades)
    winning_trades = len([t for t in trades if t['pnl'] > 0])
    win_rate = (winning_trades / total_trades * 100) if total_trades > 0 else 0
    
    # Calculate average daily performance
    import pandas as pd
    df_trades = pd.DataFrame(trades)
    df_trades['exit_time'] = pd.to_datetime(df_trades['exit_time'])
    df_trades['date'] = df_trades['exit_time'].dt.date
    
    daily_pnl = df_trades.groupby('date')['pnl'].sum()
    avg_daily_trades = df_trades.groupby('date').size().mean()
    
    demo_plan = {
        'demo_trading_plan': {
            'phase_1_days': 30,
            'phase_2_days': 60,
            'phase_3_days': 90,
            'recommended_demo_period': '90 days',
            'minimum_demo_period': '30 days'
        },
        'performance_expectations': {
            'expected_win_rate': win_rate,
            'expected_daily_trades': avg_daily_trades,
            'expected_daily_pnl': daily_pnl.mean(),
            'risk_per_trade': '0.5%',
            'daily_loss_limit': '3%'
        },
        'demo_goals': {
            'day_1_target': '$10 to $100',
            'day_2_target': '$100 to $300',
            'day_3_plus_target': '2-5% daily growth',
            'demo_success_criteria': 'Consistent positive returns with controlled drawdown'
        },
        'monitoring_checklist': [
            'Monitor daily P&L',
            'Check win rate consistency',
            'Verify risk management adherence',
            'Monitor drawdown levels',
            'Track trade frequency',
            'Review strategy performance',
            'Check for any system errors'
        ],
        'live_trading_readiness': {
            'minimum_demo_period': '30 days',
            'minimum_win_rate': '50%',
            'maximum_drawdown': '15%',
            'consistent_profitability': 'Required',
            'risk_management_compliance': 'Required'
        }
    }
    
    # Save demo plan
    with open(f"{output_dir}/demo_trading_plan.json", 'w') as f:
        json.dump(demo_plan, f, indent=2, default=str)
    
    print(f"Demo trading plan saved to {output_dir}/demo_trading_plan.json")

def generate_risk_disclaimer(output_dir: str) -> None:
    """
    Generate risk disclaimer document.
    
    Args:
        output_dir: Output directory for reports
    """
    risk_disclaimer = {
        'risk_disclaimer': {
            'title': 'IMPORTANT RISK DISCLAIMER',
            'version': '1.0',
            'date': datetime.now().isoformat(),
            'disclaimer_text': """
            FOREX TRADING RISK DISCLAIMER
            
            IMPORTANT: This Forex trading robot is provided for educational and research purposes only. 
            Forex trading involves substantial risk of loss and is not suitable for all investors.
            
            RISK WARNINGS:
            
            1. HIGH RISK INVESTMENT: Forex trading carries a high level of risk and may not be suitable for all investors.
            
            2. PAST PERFORMANCE: Past performance does not guarantee future results. Historical backtesting results 
               are not indicative of future performance.
            
            3. CAPITAL LOSS: You may lose some or all of your invested capital, therefore you should not speculate 
               with capital that you cannot afford to lose.
            
            4. LEVERAGE RISK: Forex trading involves leverage, which can work both for and against you.
            
            5. MARKET VOLATILITY: Forex markets are highly volatile and can move against your position quickly.
            
            6. TECHNICAL RISKS: Technical failures, internet connectivity issues, and broker problems can affect trading.
            
            7. REGULATORY RISKS: Forex trading regulations vary by jurisdiction and may change.
            
            RECOMMENDATIONS:
            
            1. Start with demo accounts and paper trading
            2. Never risk more than you can afford to lose
            3. Understand all risks before trading live
            4. Monitor performance regularly
            5. Have proper risk management in place
            6. Consult with financial advisors if needed
            7. Keep detailed records of all trades
            
            NO GUARANTEES:
            
            This trading robot makes no guarantees about:
            - Future profitability
            - Risk of loss
            - Market conditions
            - Broker performance
            - System reliability
            
            USE AT YOUR OWN RISK:
            
            By using this trading robot, you acknowledge that you understand the risks involved 
            and agree to use it at your own risk. The developers and distributors of this software 
            are not responsible for any financial losses incurred.
            
            LEGAL NOTICE:
            
            This software is provided "as is" without warranty of any kind. The user assumes all 
            responsibility for the use of this software and any resulting financial outcomes.
            """,
            'acknowledgment': 'By using this software, you acknowledge that you have read, understood, and agree to this risk disclaimer.'
        }
    }
    
    # Save risk disclaimer
    with open(f"{output_dir}/risk_disclaimer.json", 'w') as f:
        json.dump(risk_disclaimer, f, indent=2, default=str)
    
    # Also save as text file
    with open(f"{output_dir}/risk_disclaimer.txt", 'w') as f:
        f.write(risk_disclaimer['risk_disclaimer']['disclaimer_text'])
    
    print(f"Risk disclaimer saved to {output_dir}/risk_disclaimer.json and {output_dir}/risk_disclaimer.txt")

def print_final_summary(backtest_results: dict, monte_carlo_results: dict, walk_forward_results: dict) -> None:
    """
    Print final execution summary.
    
    Args:
        backtest_results: Backtest results dictionary
        monte_carlo_results: Monte Carlo simulation results
        walk_forward_results: Walk-forward analysis results
    """
    print("\n" + "="*80)
    print("EXECUTION SUMMARY")
    print("="*80)
    
    # Backtest summary
    if backtest_results and backtest_results.get('overall_metrics'):
        metrics = backtest_results['overall_metrics']
        print(f"✅ BACKTESTING: {metrics.get('total_trades', 0)} trades, "
              f"{metrics.get('win_rate', 0):.1f}% win rate, "
              f"${metrics.get('net_profit', 0):.2f} net profit")
    else:
        print("❌ BACKTESTING: No results")
    
    # Monte Carlo summary
    if monte_carlo_results and monte_carlo_results.get('statistics'):
        stats = monte_carlo_results['statistics']
        print(f"✅ MONTE CARLO: {monte_carlo_results.get('simulation_data', pd.DataFrame()).shape[0]} simulations, "
              f"{stats.get('mean_total_return', 0):.1f}% mean return")
    else:
        print("❌ MONTE CARLO: No results")
    
    # Walk-forward summary
    if walk_forward_results and walk_forward_results.get('summary_statistics'):
        wf_stats = walk_forward_results['summary_statistics']
        print(f"✅ WALK-FORWARD: {wf_stats.get('total_periods', 0)} periods, "
              f"{wf_stats.get('profitable_period_rate', 0):.1f}% profitable periods")
    else:
        print("❌ WALK-FORWARD: No results")
    
    print("="*80)

if __name__ == "__main__":
    main()
