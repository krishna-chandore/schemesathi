@echo off
:: ─────────────────────────────────────────────────────────────────────────────
:: run_once.bat  – Run one scheme update cycle and exit (for testing)
:: ─────────────────────────────────────────────────────────────────────────────
cd /d "%~dp0"
call venv\Scripts\activate.bat
echo Running one scheme update cycle...
python scheme_updater_worker.py --once
echo Done. Exit code: %ERRORLEVEL%
pause
