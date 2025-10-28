#!/usr/bin/env python3
"""
Forex Trading Robot - Installation Test
======================================

This script tests if all required dependencies are properly installed.

Author: Forex Trading Robot
Date: 2024
"""

import sys
import importlib

def test_import(module_name, package_name=None):
    """Test if a module can be imported."""
    try:
        if package_name:
            importlib.import_module(module_name, package_name)
        else:
            importlib.import_module(module_name)
        return True
    except ImportError:
        return False

def main():
    """Test all required dependencies."""
    print("="*60)
    print("FOREX TRADING ROBOT - DEPENDENCY TEST")
    print("="*60)
    
    # Required core modules
    core_modules = [
        ('pandas', 'pandas'),
        ('numpy', 'numpy'),
        ('matplotlib', 'matplotlib'),
        ('seaborn', 'seaborn'),
        ('yfinance', 'yfinance'),
        ('scipy', 'scipy'),
        ('configparser', 'configparser'),
    ]
    
    # Optional modules
    optional_modules = [
        ('MetaTrader5', 'MetaTrader5'),
    ]
    
    print("\nTesting core dependencies...")
    core_success = True
    for module, name in core_modules:
        if test_import(module):
            print(f"OK: {name}")
        else:
            print(f"ERROR: {name}")
            core_success = False
    
    print("\nTesting optional dependencies...")
    optional_success = True
    for module, name in optional_modules:
        if test_import(module):
            print(f"OK: {name}")
        else:
            print(f"WARNING: {name} (optional)")
            optional_success = False
    
    print("\n" + "="*60)
    if core_success:
        print("SUCCESS: ALL CORE DEPENDENCIES INSTALLED SUCCESSFULLY!")
        print("OK: The Forex Trading Robot is ready to use!")
        
        if not optional_success:
            print("\nWARNING: Some optional dependencies are missing:")
            print("   - MetaTrader5: Will use alternative data sources")
            print("   - This is normal and the system will work fine")
    else:
        print("ERROR: SOME CORE DEPENDENCIES ARE MISSING!")
        print("TIP: Try running: python setup.py")
        print("TIP: Or install manually: pip install pandas numpy matplotlib seaborn yfinance scipy")
    
    print("="*60)
    
    # Test our custom modules
    print("\nTesting custom modules...")
    try:
        from backtest import ForexBacktester
        print("OK: backtest.py")
    except ImportError as e:
        print(f"ERROR: backtest.py: {e}")
        core_success = False
    
    try:
        from monte_carlo import MonteCarloSimulator
        print("OK: monte_carlo.py")
    except ImportError as e:
        print(f"ERROR: monte_carlo.py: {e}")
        core_success = False
    
    try:
        from performance_reporter import PerformanceReporter
        print("OK: performance_reporter.py")
    except ImportError as e:
        print(f"ERROR: performance_reporter.py: {e}")
        core_success = False
    
    if core_success:
        print("\nSUCCESS: ALL MODULES LOADED SUCCESSFULLY!")
        print("READY: Run: python main.py")
    else:
        print("\nERROR: Some modules failed to load")
        print("TIP: Check the error messages above")
    
    return core_success

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
