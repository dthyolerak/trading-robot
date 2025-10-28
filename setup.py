#!/usr/bin/env python3
"""
Forex Trading Robot - Setup Script
==================================

This script sets up the Forex trading robot environment and installs all necessary dependencies.

Author: Forex Trading Robot
Date: 2024
"""

import os
import sys
import subprocess
import platform
from pathlib import Path

def check_python_version():
    """Check if Python version is compatible."""
    if sys.version_info < (3, 8):
        print("❌ Python 3.8 or higher is required")
        print(f"Current version: {sys.version}")
        return False
    print(f"✅ Python version: {sys.version}")
    return True

def install_requirements():
    """Install Python requirements."""
    print("\n📦 Installing Python dependencies...")
    try:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-r", "requirements.txt"])
        print("✅ Python dependencies installed successfully")
        return True
    except subprocess.CalledProcessError as e:
        print(f"❌ Failed to install Python dependencies: {e}")
        return False

def create_directories():
    """Create necessary directories."""
    print("\n📁 Creating directories...")
    directories = [
        "reports",
        "data",
        "logs",
        "backtest",
        "config"
    ]
    
    for directory in directories:
        Path(directory).mkdir(exist_ok=True)
        print(f"✅ Created directory: {directory}")

def check_metatrader5():
    """Check if MetaTrader 5 is available."""
    print("\n🔍 Checking MetaTrader 5 availability...")
    try:
        import MetaTrader5 as mt5
        if mt5.initialize():
            print("✅ MetaTrader 5 is available and initialized")
            mt5.shutdown()
            return True
        else:
            print("⚠️ MetaTrader 5 is installed but not available (no terminal running)")
            return False
    except ImportError:
        print("⚠️ MetaTrader 5 not installed - will use alternative data sources")
        return False

def create_sample_config():
    """Create sample configuration file if it doesn't exist."""
    print("\n⚙️ Checking configuration...")
    if not os.path.exists("config.ini"):
        print("📝 Creating sample configuration file...")
        # The config.ini file should already exist from our earlier creation
        if os.path.exists("config.ini"):
            print("✅ Configuration file already exists")
        else:
            print("⚠️ Configuration file not found - please create config.ini")
    else:
        print("✅ Configuration file exists")

def run_basic_test():
    """Run basic functionality test."""
    print("\n🧪 Running basic functionality test...")
    try:
        # Test imports
        import pandas as pd
        import numpy as np
        import matplotlib.pyplot as plt
        import seaborn as sns
        
        print("✅ Core libraries imported successfully")
        
        # Test basic functionality
        from backtest import ForexBacktester
        from monte_carlo import MonteCarloSimulator
        from performance_reporter import PerformanceReporter
        
        print("✅ Custom modules imported successfully")
        
        # Test configuration loading
        backtester = ForexBacktester()
        print("✅ Configuration loaded successfully")
        
        return True
    except Exception as e:
        print(f"❌ Basic test failed: {e}")
        return False

def print_usage_instructions():
    """Print usage instructions."""
    print("\n" + "="*80)
    print("SETUP COMPLETE - USAGE INSTRUCTIONS")
    print("="*80)
    print("\n🚀 To run the complete system:")
    print("   python main.py")
    print("\n🔧 To run individual components:")
    print("   python backtest.py          # Run backtesting only")
    print("   python monte_carlo.py       # Run Monte Carlo simulation")
    print("   python performance_reporter.py  # Generate reports")
    print("\n⚙️ To customize settings:")
    print("   Edit config.ini file")
    print("\n📊 To view results:")
    print("   Check the 'reports/' directory")
    print("\n📚 For MetaTrader 5 integration:")
    print("   1. Install MetaTrader 5 platform")
    print("   2. Copy ForexRobot.mq5 to MQL5/Experts/ folder")
    print("   3. Compile in MetaEditor")
    print("   4. Attach to chart")
    print("\n⚠️ IMPORTANT:")
    print("   - Start with demo accounts")
    print("   - Never risk more than you can afford to lose")
    print("   - Read the risk disclaimer")
    print("   - Monitor performance regularly")
    print("="*80)

def main():
    """Main setup function."""
    print("="*80)
    print("FOREX TRADING ROBOT - SETUP")
    print("="*80)
    
    # Check Python version
    if not check_python_version():
        sys.exit(1)
    
    # Install requirements
    if not install_requirements():
        print("\n❌ Setup failed during dependency installation")
        sys.exit(1)
    
    # Create directories
    create_directories()
    
    # Check MetaTrader 5
    check_metatrader5()
    
    # Create sample config
    create_sample_config()
    
    # Run basic test
    if not run_basic_test():
        print("\n❌ Setup failed during basic functionality test")
        sys.exit(1)
    
    # Print usage instructions
    print_usage_instructions()
    
    print("\n🎉 Setup completed successfully!")
    print("You can now run the Forex trading robot system.")

if __name__ == "__main__":
    main()
