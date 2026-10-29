"""Build the Google Play distribution with the real Billing SDK and merged dependencies."""
from pathlib import Path
import subprocess,sys
subprocess.run([sys.executable,str(Path(__file__).with_name("build-play-store.py"))],check=True)
