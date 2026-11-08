# SchemeSathi — Civic AI Platform

<p align="center">
  <b>A comprehensive AI-powered civic platform connecting citizens to verified Central and State Government benefits, eligibility engines, and application workflows.</b>
</p>

---

## 🏛️ Overview

**SchemeSathi** simplifies government welfare access by providing:
1. **Dynamic Eligibility Engine**: Matches citizen demographics (age, education, caste, income, domicile) against hundreds of central and state schemes.
2. **Real-time Scheme Discovery & Scraper**: Extracts real-time scheme data, document checklists, step-by-step application procedures, and direct portal links.
3. **Personalized Citizen Profile**: Synchronized multilingual profile manager (6 Indian languages, 32+ States/UTs) with dynamic milestone reminders (Voter ID, PAN card, scholarships).
4. **Seamless Authentication**: Google Sign-In powered by Clerk.

---

## 📁 Repository Structure

```
apk/
├── schemesathi_app/             # Flutter Multiplatform Client (Android, Web, iOS)
│   ├── lib/
│   │   ├── auth/                # Clerk authentication & Google login
│   │   ├── citizen_form/        # Citizen setup form, state sync & AppPreferences
│   │   ├── home/                # Home dashboard, upcoming milestones & recommendations
│   │   ├── profile/             # Profile management, language & state selection
│   │   └── schemes/             # Scheme discovery, filter modals & application processes
│   ├── .env.example             # Flutter environment template
│   └── pubspec.yaml
│
├── schemesathi_backend/         # FastAPI Backend & Scraping Microservice
│   ├── main.py                  # API endpoints (schemes, eligibility, profiles)
│   ├── scraper.py               # MyScheme scraper with parallel prefetch & rich text parser
│   ├── scheme_updater_worker.py # Background cron daemon for scheme updates
│   ├── eligibility_engine.py    # Rule-based eligibility matching
│   ├── user_profile_service.py  # User profile CRUD & MongoDB persistence
│   ├── auth_security.py         # Clerk JWT validation & user token verification
│   ├── requirements.txt         # Python dependencies
│   └── .env.example             # Backend environment template
│
└── .gitignore                   # Global ignore preventing secret/artifact leaks
```

---

## 🚀 Getting Started

### 1. Prerequisites
- **Flutter SDK**: `^3.47.6` or later
- **Python**: `3.10+`
- **MongoDB**: MongoDB Atlas or local MongoDB instance
- **Clerk Account**: Free tier publishable and secret keys from [dashboard.clerk.com](https://dashboard.clerk.com/)

---

### 2. Backend Setup (`schemesathi_backend`)

1. Navigate to the backend directory and create a virtual environment:
   ```powershell
   cd schemesathi_backend
   python -m venv venv
   .\venv\Scripts\Activate.ps1
   pip install -r requirements.txt
   ```

2. Configure environment variables:
   ```powershell
   Copy-Item .env.example .env
   ```
   Open `.env` and fill in:
   - `MONGO_URI`: Your MongoDB connection string.
   - `CLERK_SECRET_KEY`: Your Clerk secret key (`sk_test_...`).
   - (Optional) `REDIS_URL`: If Redis caching is used.

3. Start the FastAPI server:
   ```powershell
   uvicorn main:app --reload --host 0.0.0.0 --port 8001
   ```
   API Docs available at: `http://localhost:8001/docs`

4. (Optional) Run the scraper to populate schemes:
   ```powershell
   python scheme_updater_worker.py --once --states "Madhya Pradesh,Goa,Delhi"
   ```

---

### 3. Flutter Client Setup (`schemesathi_app`)

1. Navigate to the app directory:
   ```powershell
   cd schemesathi_app
   ```

2. Configure environment variables:
   ```powershell
   Copy-Item .env.example .env
   ```
   Edit `.env`:
   - `CLERK_PUBLISHABLE_KEY`: `pk_test_...`
   - `BACKEND_URL`: For emulators/web use `http://127.0.0.1:8001`. For physical devices on local Wi-Fi, use your machine's IP (e.g., `http://10.154.62.106:8001`).

3. Install packages and verify:
   ```powershell
   flutter pub get
   flutter analyze
   ```

4. Launch the application:
   ```powershell
   flutter run
   ```

---

## 🔒 Security Best Practices

- **Never commit `.env` files**: All environment files are strictly ignored by `.gitignore`.
- **Client vs. Server Credentials**:
  - `schemesathi_app` **ONLY** uses the public `CLERK_PUBLISHABLE_KEY`.
  - Sensitive database connection strings (`MONGO_URI`), Redis credentials, and `CLERK_SECRET_KEY` are stored strictly in `schemesathi_backend/.env` on the server.
- **Dynamic Key Fallback**: The client loads environment variables at runtime via `flutter_dotenv` or compile-time `--dart-define`.

---

## 🧪 Testing & Verification

- **Flutter Analysis**:
  ```powershell
  cd schemesathi_app
  flutter analyze
  ```
- **Backend Tests**:
  ```powershell
  cd schemesathi_backend
  pytest
  ```

---

## 📄 License

This project is licensed under the Apache 2.0 License.
