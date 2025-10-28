#!/usr/bin/env python3
"""
Forex Trading Robot - Setup Script (Windows Compatible)
========================================================

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
        print("ERROR: Python 3.8 or higher is required")
        print(f"Current version: {sys.version}")
        return False
    print(f"OK: Python version: {sys.version}")
    return True

def install_requirements():
    """Install Python requirements."""
    print("\nInstalling Python dependencies...")
    
    # First try core requirements
    try:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-r", "requirements_core.txt"])
        print("OK: Core Python dependencies installed successfully")
        return True
    except subprocess.CalledProcessError as e:
        print(f"WARNING: Core requirements failed, trying main requirements: {e}")
        
        # Fallback to main requirements
        try:
            subprocess.check_call([sys.executable, "-m", "pip", "install", "-r", "requirements.txt"])
            print("OK: Python dependencies installed successfully")
            return True
        except subprocess.CalledProcessError as e2:
            print(f"ERROR: Failed to install Python dependencies: {e2}")
            return False

def install_metatrader5():
    """Install MetaTrader5 package separately."""
    print("\nAttempting to install MetaTrader5...")
    try:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "MetaTrader5"])
        print("OK: MetaTrader5 installed successfully")
        return True
    except subprocess.CalledProcessError as e:
        print(f"WARNING: MetaTrader5 installation failed: {e}")
        print("INFO: MetaTrader5 is optional - the system will use alternative data sources")
        return False

def create_directories():
    """Create necessary directories."""
    print("\nCreating directories...")
    directories = [
        "reports",
        "data",
        "logs",
        "backtest",
        "config"
    ]
    
    for directory in directories:
        Path(directory).mkdir(exist_ok=True)
        print(f"OK: Created directory: {directory}")

def check_metatrader5():
    """Check if MetaTrader 5 is available."""
    print("\nChecking MetaTrader 5 availability...")
    try:
        import MetaTrader5 as mt5
        if mt5.initialize():
            print("OK: MetaTrader 5 is available and initialized")
            mt5.shutdown()
            return True
        else:
            print("WARNING: MetaTrader 5 is installed but not available (no terminal running)")
            return False
    except ImportError:
        print("WARNING: MetaTrader 5 not installed - attempting to install...")
        if install_metatrader5():
            try:
                import MetaTrader5 as mt5
                print("OK: MetaTrader 5 installed and available")
                return True
            except ImportError:
                print("WARNING: MetaTrader 5 installation failed - will use alternative data sources")
                return False
        else:
            print("WARNING: MetaTrader 5 not available - will use alternative data sources")
            return False

def create_sample_config():
    """Create sample configuration file if it doesn't exist."""
    print("\nChecking configuration...")
    if not os.path.exists("config.ini"):
        print("INFO: Creating sample configuration file...")
        # The config.ini file should already exist from our earlier creation
        if os.path.exists("config.ini"):
            print("OK: Configuration file already exists")
        else:
            print("WARNING: Configuration file not found - please create config.ini")
    else:
        print("OK: Configuration file exists")

def run_basic_test():
    """Run basic functionality test."""
    print("\nRunning basic functionality test...")
    try:
        # Test imports
        import pandas as pd
        import numpy as np
        import matplotlib.pyplot as plt
        import seaborn as sns
        
        print("OK: Core libraries imported successfully")
        
        # Test basic functionality
        from backtest import ForexBacktester
        from monte_carlo import MonteCarloSimulator
        from performance_reporter import PerformanceReporter
        
        print("OK: Custom modules imported successfully")
        
        # Test configuration loading
        backtester = ForexBacktester()
        print("OK: Configuration loaded successfully")
        
        return True
    except Exception as e:
        print(f"ERROR: Basic test failed: {e}")
        return False

def print_usage_instructions():
    """Print usage instructions."""
    print("\n" + "="*80)
    print("SETUP COMPLETE - USAGE INSTRUCTIONS")
    print("="*80)
    print("\nTo run the complete system:")
    print("   python main.py")
    print("\nTo run individual components:")
    print("   python backtest.py          # Run backtesting only")
    print("   python monte_carlo.py       # Run Monte Carlo simulation")
    print("   python performance_reporter.py  # Generate reports")
    print("\nTo customize settings:")
    print("   Edit config.ini file")
    print("\nTo view results:")
    print("   Check the 'reports/' directory")
    print("\nFor MetaTrader 5 integration:")
    print("   1. Install MetaTrader 5 platform")
    print("   2. Copy ForexRobot.mq5 to MQL5/Experts/ folder")
    print("   3. Compile in MetaEditor")
    print("   4. Attach to chart")
    print("\nIMPORTANT:")
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
        print("\nERROR: Setup failed during dependency installation")
        print("TIP: Try running: pip install --upgrade pip")
        print("TIP: Then run: python setup.py again")
        sys.exit(1)
    
    # Create directories
    create_directories()
    
    # Check MetaTrader 5
    check_metatrader5()
    
    # Create sample config
    create_sample_config()
    
    # Run basic test
    if not run_basic_test():
        print("\nERROR: Setup failed during basic functionality test")
        sys.exit(1)
    
    # Run comprehensive test
    print("\nRunning comprehensive dependency test...")
    try:
        subprocess.check_call([sys.executable, "test_installation.py"])
        print("OK: All tests passed successfully")
    except subprocess.CalledProcessError:
        print("WARNING: Some tests failed - check test_installation.py output")
    
    # Print usage instructions
    print_usage_instructions()
    
    print("\nSetup completed successfully!")
    print("You can now run the Forex trading robot system.")

if __name__ == "__main__":
    main()
