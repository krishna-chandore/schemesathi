@echo off
:: ─────────────────────────────────────────────────────────────────────────────
:: start_worker.bat  – Start the scheme updater worker (loops every 6 hours)
:: ─────────────────────────────────────────────────────────────────────────────
cd /d "%~dp0"
call venv\Scripts\activate.bat
echo Starting SchemeSathi scheme updater worker...
echo Logs will be written to: %~dp0logs\scheme_updater.log
python scheme_updater_worker.py
