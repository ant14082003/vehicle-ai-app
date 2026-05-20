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
  <img width="483" height="825" alt="image" src="https://github.com/user-attachments/assets/14f7edd2-33a2-4a53-877a-a616855d8c90" />

* Vehicle Profile
  <img width="508" height="940" alt="image" src="https://github.com/user-attachments/assets/e997bcb9-00b7-4864-98ce-8f6f6ca44e4f" />

* Upload Document Screen
  <img width="508" height="940" alt="image" src="https://github.com/user-attachments/assets/c290475a-94a4-43b1-8e9e-b0e8d2482ec0" />
  
* Damage Detection
  <img width="508" height="951" alt="image" src="https://github.com/user-attachments/assets/521d2974-7b4a-4972-9d16-39826045bcc0" />

* Predictive Maintainance
  <img width="507" height="951" alt="image" src="https://github.com/user-attachments/assets/b7d8ad42-0e03-4c6b-9fe1-6f0085861c41" />
* AI Vehicle assistant
  <img width="464" height="879" alt="image" src="https://github.com/user-attachments/assets/a8750e60-7e84-4b18-88a8-03b0230c46c5" />

  
---

# 🔮 Future Enhancements

* Real-time notifications
* Cloud database integration
* Advanced ML damage analysis
* Insurance API integration

---

# 👨‍💻 Author

Anant Anveri

---

# 📄 License

This project is developed for academic and educational purposes.
