# 🚗 AI-Enabled Vehicle Document and Smart Assistance System

An intelligent full-stack mobile application that helps users manage vehicle documents, detect vehicle damage, predict maintenance needs, and simplify insurance claim processes.

---

# 📱 Features

## 📄 Vehicle Document Management

* Upload RC, Insurance, and PUC documents
* Supports both images and PDF files
* Automatic OCR-based text extraction
* Vehicle profile creation using RC

---

## 🤖 OCR & Data Extraction

* Extracts vehicle information using Tesseract OCR
* Handles scanned images and PDFs
* Automatically identifies document types

---

## 🚘 Damage Detection

* Upload or capture vehicle images
* Detects:

  * Scratches
  * Dents
  * Cracks
* Severity classification:

  * Low
  * Medium
  * High

---

## 🔧 Predictive Maintenance

* Uses mileage and service history
* Predicts upcoming maintenance needs
* Suggests next service schedules
* Alerts users about important components

---

## 📊 Smart Dashboard

* Displays:

  * Document expiry reminders
  * Maintenance alerts
  * Vehicle summaries
* Visual cards and quick overview sections

---

## 🛡 Insurance Claim Assistant

* Upload accident images and documents
* Step-by-step guided claim process
* Checklist for required documents
* Claim submission assistance

---

# 🏗 System Architecture

Flutter App
↓
Firebase Storage
↓
FastAPI Backend
↓
AI Processing Modules

* OCR Engine
* Damage Detection
* Maintenance Prediction

---

# 🛠 Technologies Used

## Frontend

* Flutter
* Dart

## Backend

* FastAPI
* Python

## AI / Processing

* Tesseract OCR
* PyMuPDF
* Regex Parsing

## Cloud & Storage

* Firebase Storage

---

# 📂 Project Structure

```bash
vehicle-ai-system/
│
├── lib/                  # Flutter frontend
├── backend/              # FastAPI backend
├── android/
├── ios/
├── pubspec.yaml
└── README.md
```

---

# 🚀 Installation

## Frontend

```bash
flutter pub get
flutter run
```

---

## Backend

```bash
cd backend

pip install -r requirements.txt

python -m uvicorn app.main:app --reload
```

---

# 📸 Screenshots

(Add your screenshots here)

* Garage Screen
* Vehicle Profile
* Upload Document Screen
* Dashboard
* Damage Detection Result

---

# 🔮 Future Enhancements

* AI chatbot assistant
* Real-time notifications
* Cloud database integration
* Advanced ML damage analysis
* Insurance API integration

---

# 👨‍💻 Author

Your Name

---

# 📄 License

This project is developed for academic and educational purposes.
