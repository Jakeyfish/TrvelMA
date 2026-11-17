#!/usr/bin/env python3
"""Compile and run pure legacy-local policy fixtures; no StoreKit or user data."""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
output=Path(tempfile.mkdtemp(prefix='trvelma-legacy-policy-'))/'LegacyLocalAccessPolicyTests'
subprocess.run(['swiftc',str(root/'Wishlist/Models/LegacyLocalAccessPolicy.swift'),str(root/'scripts/tests/LegacyLocalAccessPolicyTests.swift'),'-o',str(output)],check=True)
subprocess.run([str(output)],check=True)
print(f'Artifacts: {output.parent}')
