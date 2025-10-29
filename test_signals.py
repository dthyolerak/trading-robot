#!/usr/bin/env python3
"""
Test script to debug signal generation
"""

from backtest import ForexBacktester

def test_signals():
    print("Testing signal generation...")
    
    # Initialize backtester
    bt = ForexBacktester()
    
    # Get data for EURUSD
    print("Getting data for EURUSD...")
    df = bt.get_historical_data('EURUSD=X', '2023-01-01', '2024-01-01')
    print(f"Data shape: {df.shape}")
    
    if df.empty:
        print("No data available!")
        return
    
    # Calculate indicators
    print("Calculating indicators...")
    df = bt.calculate_indicators(df)
    
    # Generate signals
    print("Generating signals...")
    df = bt.generate_signals(df)
    
    # Check signals
    buy_signals = df['Buy_Signal'].sum()
    sell_signals = df['Sell_Signal'].sum()
    
    print(f"Buy signals: {buy_signals}")
    print(f"Sell signals: {sell_signals}")
    
    # Show sample data
    print("\nSample data:")
    print(df[['Close', 'EMA_20', 'EMA_200', 'BB_Position', 'RSI', 'Buy_Signal', 'Sell_Signal']].tail(10))
    
    # Show signal conditions
    print("\nSignal analysis:")
    print(f"Price above EMA20: {(df['Close'] > df['EMA_20']).sum()}")
    print(f"Price above EMA200: {(df['Close'] > df['EMA_200']).sum()}")
    print(f"EMA20 above EMA200: {(df['EMA_20'] > df['EMA_200']).sum()}")
    print(f"BB Position < 0.3: {(df['BB_Position'] < 0.3).sum()}")
    print(f"RSI < 70: {(df['RSI'] < 70).sum()}")

if __name__ == "__main__":
    test_signals()
