#!/usr/bin/env python3
"""Show production purchase UI in an isolated XCTest-hosted local StoreKit fixture.
No production account, cloud verifier or new purchases. Use the QA finish button to exit.
"""
from pathlib import Path
import subprocess,sys
runner=Path(__file__).with_name('verify-sync-regressions.py')
raise SystemExit(subprocess.call([sys.executable,str(runner),'--purchase-preview',*sys.argv[1:]]))
