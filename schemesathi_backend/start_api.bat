@echo off
:: ─────────────────────────────────────────────────────────────────────────────
:: start_api.bat  – Start the SchemeSathi FastAPI server
:: ─────────────────────────────────────────────────────────────────────────────
cd /d "%~dp0"
call venv\Scripts\activate.bat
uvicorn main:app --host 0.0.0.0 --port 8001 --reload
