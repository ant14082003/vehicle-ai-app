from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional
from datetime import datetime, timedelta
import requests
import pytesseract
from PIL import Image
from io import BytesIO
import re
import fitz
from groq import Groq
import os
import hashlib
import base64
import platform
import pytesseract
import shutil
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch, cm
from reportlab.lib import colors
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, HRFlowable
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT
from fastapi.responses import FileResponse
import tempfile
import os as _os

print("CURRENT OS:", platform.system())

if platform.system() == "Windows":
    pytesseract.pytesseract.tesseract_cmd = (
        r"C:\Program Files\Tesseract-OCR\tesseract.exe"
    )
else:
    tesseract_path = shutil.which("tesseract")
    print("FOUND TESSERACT:", tesseract_path)

    if tesseract_path:
        pytesseract.pytesseract.tesseract_cmd = tesseract_path

print("FINAL TESSERACT CMD:", pytesseract.pytesseract.tesseract_cmd)
# ─────────────────────────────────────────────
#  CONFIG
# ─────────────────────────────────────────────
GROQ_KEY            = os.environ.get("GROQ_KEY", "")
SUREPASS_TOKEN      = os.environ.get("SUREPASS_TOKEN", "YOUR_SUREPASS_TOKEN_HERE")
UNSPLASH_ACCESS_KEY = os.environ.get("UNSPLASH_ACCESS_KEY", "")
print("UNSPLASH ENABLED =", bool(UNSPLASH_ACCESS_KEY))
print("UNSPLASH KEY LENGTH =", len(UNSPLASH_ACCESS_KEY))
GOOGLE_API_KEY      = os.environ.get("GOOGLE_API_KEY", "")
GOOGLE_CX           = os.environ.get("GOOGLE_CX", "")

CHUNK_SIZE    = 800
CHUNK_OVERLAP = 100
TOP_K_CHUNKS  = 6

# ─────────────────────────────────────────────
#  In-memory DB
# ─────────────────────────────────────────────
_user_vehicles = {}
_user_knowledge = {}
_user_chat = {}

def get_user_vehicles(user_id: str):
    if user_id not in _user_vehicles:
        _user_vehicles[user_id] = []
    return _user_vehicles[user_id]


def get_user_knowledge(user_id: str):
    if user_id not in _user_knowledge:
        _user_knowledge[user_id] = {}
    return _user_knowledge[user_id]


def get_user_chat(user_id: str):
    if user_id not in _user_chat:
        _user_chat[user_id] = {}
    return _user_chat[user_id]

app = FastAPI()
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

import os
import platform
if platform.system() == "Windows":
    pytesseract.pytesseract.tesseract_cmd = r"C:\Program Files\Tesseract-OCR\tesseract.exe"
# On Linux (Railway), tesseract is installed automatically via nixpacks
groq_client = Groq(api_key=GROQ_KEY)


# ─────────────────────────────────────────────
#  Request Models
# ─────────────────────────────────────────────
class RCUploadRequest(BaseModel):
    imageUrl: str
    userId: str = ""

class DocumentUploadRequest(BaseModel):
    imageUrls: list[str]
    vehicleNumber: str
    docType: str
    userId: str = ""

class ManualVehicleRequest(BaseModel):
    vehicle_number: str
    userId: str = ""

class ServiceBillRequest(BaseModel):
    imageUrl: str
    vehicleNumber: str
    userId: str = ""

class ManualUploadRequest(BaseModel):
    imageUrl: str
    vehicleNumber: str
    userId: str = ""

class ChatRequest(BaseModel):
    vehicleNumber: str
    question: str
    targetVehicleNumber: Optional[str] = None
    userId: str = ""
class DamageDetectionRequest(BaseModel):
    imageUrl: str
    vehicleNumber: str
    userId: str = ""

class MaintenanceRequest(BaseModel):
    vehicleNumber: str
    currentMileage: Optional[int] = None
    userId: str = ""

class InsuranceClaimRequest(BaseModel):
    vehicleNumber: str
    accidentDescription: str
    imageUrls: list[str]
    documentUrls: Optional[list[str]] = []
    userId: str = ""

class ClaimReportRequest(BaseModel):
    vehicleNumber: str
    accidentDescription: str
    claimReference: str
    damageSummary: Optional[str] = ""
    checklist: Optional[list] = []
    ownerName: Optional[str] = ""
    insuranceStatus: Optional[str] = ""
    photosSubmitted: Optional[int] = 0
    submittedAt: Optional[str] = ""
    userId: str = ""


# ─────────────────────────────────────────────
#  PDF / Image Loading
# ─────────────────────────────────────────────
def load_images_from_url(url: str) -> list[Image.Image]:
    response     = requests.get(url, timeout=15)
    content_type = response.headers.get("Content-Type", "").lower()
    is_pdf       = ".pdf" in url.lower() or "application/pdf" in content_type
    if is_pdf:
        pdf    = fitz.open(stream=response.content, filetype="pdf")
        images = []
        for page_num in range(min(len(pdf), 3)):
            pix = pdf.load_page(page_num).get_pixmap(dpi=200)
            images.append(Image.open(BytesIO(pix.tobytes("png"))).convert("RGB"))
        return images
    return [Image.open(BytesIO(response.content)).convert("RGB")]


def run_ocr(url: str) -> str:
    images   = load_images_from_url(url)
    all_text = []
    for i, img in enumerate(images):
        text = pytesseract.image_to_string(img, config="--psm 6")
        all_text.append(text)
    return "\n".join(all_text)


def run_ocr_multiple(urls: list[str]) -> str:
    all_text = []
    for url in urls:
        images = load_images_from_url(url)
        for img in images:
            text = pytesseract.image_to_string(img, config="--psm 6")
            all_text.append(text)
    return "\n".join(all_text)


def image_url_to_base64(url: str) -> tuple[str, str]:
    """Download image and convert to base64. Returns (base64_data, media_type)."""
    response     = requests.get(url, timeout=15)
    content_type = response.headers.get("Content-Type", "image/jpeg").lower()
    if "png" in content_type:
        media_type = "image/png"
    elif "webp" in content_type:
        media_type = "image/webp"
    else:
        media_type = "image/jpeg"
    b64 = base64.b64encode(response.content).decode("utf-8")
    return b64, media_type

# ─────────────────────────────────────────────────────────────────────────────
#  RC FIELD EXTRACTION
#  Handles all known Indian RC formats
# ─────────────────────────────────────────────────────────────────────────────

def _clean_rc_value(raw: str, stop_at_next_field: bool = True) -> str:
    """
    Clean extracted value — remove noise, stop at next field label.
    Handles OCR artifacts like ~, |, #, etc.
    """
    if not raw:
        return ""

    # Stop at known field labels that appear inline (two-column layout)
    if stop_at_next_field:
        stop_patterns = [
            r'\bO\.?\s*SL\.?\s*NO\b',
            r'\bMFR\b', r'\bMAKER\b', r'\bMANUFACTURER\b',
            r'\bCLASS\b', r'\bVEHICLE\s*CLASS\b',
            r'\bCOLOU?R\b', r'\bCOLOR\b',
            r'\bCC\b', r'\bCYL\b', r'\bCYLINDER\b',
            r'\bBODY\b', r'\bSEAT\b', r'\bSEATING\b',
            r'\bUNLADEN\b', r'\bWHEEL\b', r'\bWHEELBASE\b',
            r'\bSTDG\b', r'\bTAX\b', r'\bFORM\b',
            r'\bSEE\s*RULE\b', r'\bS/W/D\b',
            r'\bADDRESS\b', r'\bSON/DAUGHTER\b',
            r'\bHORSE\s*POWER\b', r'\bBHP\b',
            r'\bREGISTRATION\s*AUTHORITY\b',
            r'\bCARD\s*ISSUE\b',
            r'\s{3,}',   # 3+ spaces = column separator
        ]
        earliest = len(raw)
        for pat in stop_patterns:
            m = re.search(pat, raw, re.IGNORECASE)
            if m and m.start() < earliest:
                earliest = m.start()
        raw = raw[:earliest]

    # Remove OCR noise characters
    raw = re.sub(r'[~\*\#\$\|\^\\]+', '', raw)
    # Remove leading/trailing punctuation and whitespace
    raw = raw.strip().strip('.,;:/-').strip()
    # Collapse internal whitespace
    raw = re.sub(r'\s+', ' ', raw)
    return raw


def _find_value(text: str, *label_patterns: str,
                multiline: bool = False) -> str:
    """
    Find a field value in OCR text using multiple label pattern variations.
    Handles:
    - LABEL : VALUE (standard)
    - LABEL\nVALUE (value on next line — smart card format)
    - LABEL VALUE (no separator)
    """
    for pattern in label_patterns:
        # Pattern 1: LABEL [optional whitespace] [:.-=] [whitespace] VALUE
        m = re.search(
            pattern + r'\s*[:\-\.=~]+\s*(.+)',
            text, re.IGNORECASE | (re.MULTILINE if multiline else 0)
        )
        if m:
            val = _clean_rc_value(m.group(1).strip())
            if val and len(val) > 0:
                return val

        # Pattern 2: LABEL on one line, VALUE on the next line (smart card)
        m = re.search(
            pattern + r'\s*\n\s*(.+)',
            text, re.IGNORECASE
        )
        if m:
            val = _clean_rc_value(m.group(1).strip(), stop_at_next_field=False)
            # Make sure it's not another label
            if val and len(val) > 1 and not re.match(
                    r'^(regn|chassis|engine|owner|maker|model|fuel|color|class|date|validity)',
                    val, re.IGNORECASE):
                return val

    return ""


def _extract_vehicle_number_all_formats(text: str) -> str:
    """
    Extract vehicle registration number from any RC format.
    Handles all known patterns across RC types.
    """
    # Indian vehicle number pattern — flexible
    VN_PATTERN = re.compile(
        r'\b([A-Z]{2}[\s\-]?\d{2}[\s\-]?[A-Z]{1,3}[\s\-]?\d{3,4})\b',
        re.IGNORECASE
    )

    # Priority patterns — most specific first
    priority_patterns = [
        # Format: "REG NO : KA04JN6024"
        r'REG\s*(?:NO|NUMBER|NUM|\.?\s*NO\.?)\s*[:\-\.]\s*([A-Z]{2}[\s\-]?\d{2}[\s\-]?[A-Z]{1,3}[\s\-]?\d{3,4})',
        # Format: "Regn No\nKA03KK7727" or "Regn. Number\nKA03KK7727"
        r'REGN?\.?\s*(?:NO\.?|NUMBER)?\s*\n\s*([A-Z]{2}[\s\-]?\d{2}[\s\-]?[A-Z]{1,3}[\s\-]?\d{3,4})',
        # Format: "Regn. Number KA03KK7727"
        r'REGN?\.?\s*(?:NO\.?|NUMBER)?\s*[:\-]?\s*([A-Z]{2}[\s\-]?\d{2}[\s\-]?[A-Z]{1,3}[\s\-]?\d{3,4})',
        # DigiLocker format: RC_REGN_NO
        r'RC_REGN_NO\s*[:\-=]\s*([A-Z]{2}[\s\-]?\d{2}[\s\-]?[A-Z]{1,3}[\s\-]?\d{3,4})',
    ]

    for pat in priority_patterns:
        m = re.search(pat, text, re.IGNORECASE)
        if m:
            vn = re.sub(r'[\s\-]', '', m.group(1)).upper()
            if 8 <= len(vn) <= 11:
                return vn

    # Fallback: scan every line for vehicle number pattern
    for line in text.split('\n'):
        m = VN_PATTERN.search(line)
        if m:
            vn = re.sub(r'[\s\-]', '', m.group(1)).upper()
            if 8 <= len(vn) <= 11:
                return vn

    return ""


def _extract_engine_number(text: str) -> str:
    """
    Extract engine number — handles all known label variations:
    - ENGINE.NO (Form 23A)
    - Engine/Motor No (Smart Card)
    - Engine No. (booklet)
    - RC_ENG_NO (DigiLocker)
    - ENG NO, MOTOR NO
    Engine numbers are alphanumeric, typically 8-17 characters.
    """
    patterns = [
        # "ENGINE/MOTOR NO" or "Engine/Motor No" — smart card format
        r'ENGINE\s*/\s*MOTOR\s*NO\.?\s*[:\-\n]\s*([A-Z0-9]{6,17})',
        # "ENGINE.NO" — Form 23A
        r'ENGINE\.?\s*NO\.?\s*[:\-\.~=]+\s*([A-Z0-9]{6,17})',
        # "Engine No." — booklet
        r'ENGINE\s*NO\.?\s*[:\-\.]\s*([A-Z0-9]{6,17})',
        # "ENG NO" abbreviation
        r'ENG\.?\s*NO\.?\s*[:\-\.]\s*([A-Z0-9]{6,17})',
        # "MOTOR NO"
        r'MOTOR\s*NO\.?\s*[:\-\.]\s*([A-Z0-9]{6,17})',
        # DigiLocker
        r'RC_ENG_NO\s*[:\-=]\s*([A-Z0-9]{6,17})',
        # Multiline — label then value on next line
        r'ENGINE\s*/?\s*MOTOR\s*NO\.?\s*\n\s*([A-Z0-9]{6,17})',
        r'ENGINE\.?\s*NO\.?\s*\n\s*([A-Z0-9]{6,17})',
    ]

    text_upper = text.upper()
    for pat in patterns:
        m = re.search(pat, text_upper)
        if m:
            val = m.group(1).strip()
            # Validate: must be alphanumeric, 6-17 chars
            if re.match(r'^[A-Z0-9]{6,17}$', val):
                return val

    return ""


def _extract_chassis_number(text: str) -> str:
    """
    Extract chassis number — handles all formats.
    Indian chassis numbers are typically 17-char VIN or shorter.
    Labels: CHASSIS.NO, Chassis No, Chasis No (one s), RC_CHASI_NO
    """
    patterns = [
        # "CHASSIS.NO" — Form 23A
        r'CHASSIS\.?\s*NO\.?\s*[:\-\.~=]+\s*([A-Z0-9]{8,17})',
        # "Chassis No" — Smart Card
        r'CHASSIS\s*NO\.?\s*[:\-\.]\s*([A-Z0-9]{8,17})',
        # "Chasis No" — common misspelling/variant
        r'CHASIS\s*NO\.?\s*[:\-\.]\s*([A-Z0-9]{8,17})',
        # DigiLocker
        r'RC_CHASI_NO\s*[:\-=]\s*([A-Z0-9]{8,17})',
        r'RC_CHASSIS_NO\s*[:\-=]\s*([A-Z0-9]{8,17})',
        # Multiline
        r'CHASSIS\.?\s*NO\.?\s*\n\s*([A-Z0-9]{8,17})',
        r'CHASIS\s*NO\.?\s*\n\s*([A-Z0-9]{8,17})',
    ]

    text_upper = text.upper()
    for pat in patterns:
        m = re.search(pat, text_upper)
        if m:
            val = m.group(1).strip()
            if re.match(r'^[A-Z0-9]{8,17}$', val):
                return val

    return ""


def _extract_owner_name(text: str) -> str:
    """
    Extract owner name — handles:
    - OWNERNAME (Form 23A — no space)
    - Owner Name (Smart Card)
    - Name of Owner (booklet)
    - RC_OWNER_NAME (DigiLocker)
    Removes S/W/D OF continuation.
    """
    patterns = [
        r'OWNER\s*NAME\s*[:\-\.~=]+\s*([^\n]+)',
        r'OWNERNAME\s*[:\-\.~=]+\s*([^\n]+)',
        r'NAME\s*OF\s*(?:OWNER|REGISTERED\s*OWNER)\s*[:\-\.]\s*([^\n]+)',
        r'RC_OWNER_NAME\s*[:\-=]\s*([^\n]+)',
        r'REGISTERED\s*OWNER\s*[:\-\.]\s*([^\n]+)',
        # Smart card — "Owner Name\nAMIT ANVERI"
        r'OWNER\s*NAME\s*\n\s*([A-Z][A-Z\s]{2,40})',
    ]

    text_upper = text.upper()
    for pat in patterns:
        m = re.search(pat, text_upper)
        if m:
            val = _clean_rc_value(m.group(1).strip())
            # Remove S/W/D continuation
            val = re.split(r'S/?W/?D|SON\b|WIFE\b|DAUGHTER\b|ADDRESS\b',
                           val, flags=re.IGNORECASE)[0].strip()
            # Clean and title-case
            val = val.strip('.,;:/-').strip()
            if val and 2 <= len(val) <= 60:
                return val.title()

    return ""


def _extract_maker(text: str) -> str:
    """
    Extract maker/manufacturer — handles:
    - MFR : HONDA (Form 23A)
    - Maker:\nROYAL-ENFIELD (UNIT OF EICHER LTD) (Smart Card)
    - MANUFACTURER (booklet)
    - RC_MAKER_DESC (DigiLocker)
    """
    text_upper = text.upper()

    # Smart Card: "Maker:" followed by value (possibly on next line)
    # Value may contain brackets: "ROYAL-ENFIELD (UNIT OF EICHER LTD)"
    m = re.search(r'MAKER\s*[:\-\.~]?\s*\n?\s*([A-Z][A-Z0-9\s\-\(\)\.]{1,60})',
                  text_upper)
    if m:
        val = _clean_rc_value(m.group(1))
        # Extract just the main brand name, remove parenthetical subsidiary
        val = re.sub(r'\s*\([^)]+\)\s*', '', val).strip()
        if val and 2 <= len(val) <= 40:
            return val.title()

    # MFR : HONDA
    m = re.search(r'\bMFR\s*[:\-\.]\s*([A-Z][A-Z\s\-]{1,30})', text_upper)
    if m:
        val = _clean_rc_value(m.group(1))
        if val:
            return val.title()

    # MANUFACTURER / MAKE
    for pat in [
        r'MANUFACTURER\s*[:\-\.]\s*([A-Z][A-Z\s\-]{1,30})',
        r'\bMAKE\s*[:\-\.]\s*([A-Z][A-Z\s\-]{1,30})',
        r'RC_MAKER_DESC\s*[:\-=]\s*([^\n]+)',
    ]:
        m = re.search(pat, text_upper)
        if m:
            val = _clean_rc_value(m.group(1))
            if val:
                return val.title()

    return ""


def _extract_model(text: str) -> str:
    """
    Extract model — handles:
    - MODEL : DIO (DX) (Form 23A)
    - Model:\nHIMALAYAN (Smart Card)
    - RC_VEH_DESC (DigiLocker)
    """
    text_upper = text.upper()

    # Smart card: "Model:" on one line, value on next
    m = re.search(r'\bMODEL\s*[:\-\.~]?\s*\n\s*([A-Z][A-Z0-9\s\-\(\)\.]{1,40})',
                  text_upper)
    if m:
        val = _clean_rc_value(m.group(1), stop_at_next_field=False)
        val = re.sub(r'[()]', '', val).strip()
        if val and 1 <= len(val) <= 40:
            return val.title()

    # Inline: "MODEL : DIO (DX)"
    m = re.search(r'\bMODEL\s*[:\-\.~=]+\s*([^\n]+)', text_upper)
    if m:
        val = _clean_rc_value(m.group(1))
        val = re.sub(r'[()]', '', val).strip()
        if val:
            return val.title()

    for pat in [
        r'VEH(?:ICLE)?\s*MODEL\s*[:\-\.]\s*([^\n]+)',
        r'RC_VEH_DESC\s*[:\-=]\s*([^\n]+)',
    ]:
        m = re.search(pat, text_upper)
        if m:
            val = _clean_rc_value(m.group(1))
            val = re.sub(r'[()]', '', val).strip()
            if val:
                return val.title()

    return ""


def _extract_color(text: str) -> str:
    """
    Extract colour — handles:
    - COLOUR: GREY (Form 23A inline)
    - Color:\nROCK RED (Smart Card next line)
    - RC_COLOR (DigiLocker)
    """
    text_upper = text.upper()

    # Smart card next-line format
    m = re.search(r'COLO(?:U?R)\s*[:\-\.~]?\s*\n\s*([A-Z][A-Z\s]{1,30})',
                  text_upper)
    if m:
        val = _clean_rc_value(m.group(1), stop_at_next_field=False).strip()
        if val and 1 <= len(val) <= 30:
            return val.title()

    # Inline format
    m = re.search(r'COLO(?:U?R)\s*[:\-\.~=]+\s*([A-Z][A-Z\s]{1,30})',
                  text_upper)
    if m:
        val = _clean_rc_value(m.group(1))
        if val:
            return val.title()

    for pat in [r'RC_COLOR\s*[:\-=]\s*([^\n]+)',
                r'RC_COLOUR\s*[:\-=]\s*([^\n]+)']:
        m = re.search(pat, text_upper)
        if m:
            val = _clean_rc_value(m.group(1))
            if val:
                return val.title()

    return ""


def _extract_vehicle_class(text: str) -> str:
    """
    Extract vehicle class — handles:
    - CLASS : MCYCLE (Form 23A inline)
    - Vehicle Class: M-CYCLE/SCOOTER (2WN) (Smart Card)
    - RC_VEH_CLASS_DESC (DigiLocker)
    """
    # Normalisation map
    CLASS_MAP = {
        "MCYCLE": "Motorcycle", "M-CYCLE": "Motorcycle",
        "M/CYCLE": "Motorcycle", "MOTORCYCLE": "Motorcycle",
        "SCOOTER": "Scooter", "M-CYCLE/SCOOTER": "M-Cycle/Scooter",
        "MCYCLE/SCOOTER": "M-Cycle/Scooter",
        "M-CYCLE/SCOOTER (2WN)": "M-Cycle/Scooter",
        "MOPED": "Moped", "E-CYCLE": "E-Cycle",
        "LMV": "Light Motor Vehicle", "HMV": "Heavy Motor Vehicle",
    }

    text_upper = text.upper()

    # Smart card: "Vehicle Class: M-CYCLE/SCOOTER (2WN)"
    m = re.search(
        r'VEHICLE\s*CLASS\s*[:\-\.~]?\s*\n?\s*([A-Z][A-Z0-9\s\-/\(\)]{1,40})',
        text_upper)
    if m:
        val = _clean_rc_value(m.group(1), stop_at_next_field=False).strip()
        # Remove parenthetical like (2WN)
        val_clean = re.sub(r'\s*\([^)]+\)', '', val).strip()
        return CLASS_MAP.get(val_clean, val_clean.title() if val_clean else "")

    # Inline: "CLASS : MCYCLE"
    m = re.search(r'\bCLASS\s*[:\-\.~=]+\s*([A-Z][A-Z0-9\s\-/]{1,30})',
                  text_upper)
    if m:
        val = _clean_rc_value(m.group(1)).strip()
        return CLASS_MAP.get(val.upper(), val.title())

    for pat in [r'RC_VEH_CLASS_DESC\s*[:\-=]\s*([^\n]+)',
                r'VEH(?:ICLE)?\s*CLASS\s*[:\-\.]\s*([^\n]+)']:
        m = re.search(pat, text_upper)
        if m:
            val = _clean_rc_value(m.group(1)).strip()
            val_clean = re.sub(r'\s*\([^)]+\)', '', val).strip()
            return CLASS_MAP.get(val_clean.upper(), val_clean.title())

    return ""


def _extract_date(text: str, *label_patterns: str) -> str:
    """
    Extract a date field — returns DD/MM/YYYY.
    Handles separators: / - . space
    Handles formats: DD/MM/YYYY, DD-MM-YYYY, DD MM YYYY, MM-YYYY (mfg date)
    """
    DATE_RE = re.compile(
        r'\b(\d{1,2})\s*[\-/\.]\s*(\d{1,2})\s*[\-/\.]\s*(\d{4})\b'
        r'|'
        r'\b(\d{4})\s*[\-/\.]\s*(\d{1,2})\s*[\-/\.]\s*(\d{1,2})\b'
        r'|'
        r'\b(\d{1,2})\s*[\-/\.]\s*(\d{4})\b',  # MM/YYYY for mfg date
    )

    for label_pat in label_patterns:
        m = re.search(label_pat + r'\s*[:\-\.~=]?\s*([^\n]{4,15})',
                      text, re.IGNORECASE)
        if m:
            candidate = m.group(1).strip()
            dm = DATE_RE.search(candidate)
            if dm:
                groups = dm.groups()
                if groups[0]:   # DD/MM/YYYY
                    d, mo, y = groups[0], groups[1], groups[2]
                    return f"{d.zfill(2)}/{mo.zfill(2)}/{y}"
                elif groups[3]: # YYYY/MM/DD
                    y, mo, d = groups[3], groups[4], groups[5]
                    return f"{d.zfill(2)}/{mo.zfill(2)}/{y}"
                elif groups[6]: # MM/YYYY
                    mo, y = groups[6], groups[7]
                    return f"01/{mo.zfill(2)}/{y}"

    return ""


def _extract_fuel(text: str) -> str:
    text_upper = text.upper()
    for pat in [
        r'FUEL\s*TYPE\s*[:\-\.~=]+\s*([A-Z]+)',
        r'\bFUEL\s*[:\-\.~=]+\s*([A-Z]+)',
        r'RC_FUEL_DESC\s*[:\-=]\s*([^\n]+)',
    ]:
        m = re.search(pat, text_upper)
        if m:
            val = m.group(1).split()[0].strip()
            fuel_map = {
                "PETROL": "Petrol", "DIESEL": "Diesel",
                "CNG": "CNG", "ELECTRIC": "Electric",
                "HYBRID": "Hybrid", "LPG": "LPG",
            }
            return fuel_map.get(val.upper(), val.title())
    return ""


def _extract_engine_cc(text: str) -> str:
    text_upper = text.upper()
    # "CC : 109" or "Cubic Cap. / ... 410.94"
    for pat in [
        r'\bCC\s*[:\-\.]\s*(\d+(?:\.\d+)?)',
        r'CUBIC\s*CAP(?:ACITY)?\s*[:\-\./]?\s*(\d+(?:\.\d+)?)',
        r'ENGINE\s*CAPACITY\s*[:\-\.]\s*(\d+(?:\.\d+)?)',
        r'DISPLACE?MENT\s*[:\-\.]\s*(\d+(?:\.\d+)?)',
    ]:
        m = re.search(pat, text_upper)
        if m:
            val = m.group(1).split('/')[0].strip()  # handle "410.94 / 23.96"
            try:
                cc = float(val)
                if 50 <= cc <= 5000:
                    return f"{int(cc)}cc"
            except ValueError:
                pass
    return ""


def _detect_rc_format(text: str) -> str:
    """
    Detect which RC format we're dealing with.
    Returns: 'smart_card', 'form_23a', 'digilocker', 'booklet', 'unknown'
    """
    text_upper = text.upper()
    if "INDIAN UNION VEHICLE REGISTRATION" in text_upper or \
       "ENGINE/MOTOR NO" in text_upper or \
       "DATE OF REGN" in text_upper:
        return "smart_card"
    if "REG NO :" in text_upper or "OWNERNAME" in text_upper or \
       "ENGINE.NO" in text_upper or "REG/FC UPTO" in text_upper:
        return "form_23a"
    if "RC_REGN_NO" in text_upper or "RC_OWNER_NAME" in text_upper or \
       "RC_ENG_NO" in text_upper:
        return "digilocker"
    if "REGN. NO." in text_upper or "CHASIS NO" in text_upper:
        return "booklet"
    return "unknown"


def extract_rc_fields(ocr_text: str) -> dict:
    """
    Master RC extraction function.
    Detects format and applies appropriate extraction strategy.
    Handles all known Indian RC formats flawlessly.
    """
    text        = ocr_text
    text_upper  = text.upper()
    rc_format   = _detect_rc_format(text)
    print(f"[RC Extract] Detected format: {rc_format}")

    # ── Vehicle Number ────────────────────────────────────────────────────────
    vehicle_number = _extract_vehicle_number_all_formats(text_upper)

    # ── Engine Number ─────────────────────────────────────────────────────────
    engine_number = _extract_engine_number(text)

    # ── Chassis Number ────────────────────────────────────────────────────────
    chassis_number = _extract_chassis_number(text)

    # ── Owner Name ────────────────────────────────────────────────────────────
    owner = _extract_owner_name(text)

    # ── Maker ─────────────────────────────────────────────────────────────────
    maker = _extract_maker(text)

    # ── Model ─────────────────────────────────────────────────────────────────
    model = _extract_model(text)

    # ── Colour ────────────────────────────────────────────────────────────────
    color = _extract_color(text)

    # ── Vehicle Class ─────────────────────────────────────────────────────────
    vehicle_class = _extract_vehicle_class(text)

    # ── Fuel Type ─────────────────────────────────────────────────────────────
    fuel_type = _extract_fuel(text)

    # ── Engine CC ─────────────────────────────────────────────────────────────
    engine_cc = _extract_engine_cc(text)

    # ── Registration Date ─────────────────────────────────────────────────────
    # Smart card: "Date of Regn." / Form 23A: "REG.DATE" / "REG. DATE"
    registration_date = _extract_date(
        text_upper,
        r'DATE\s*OF\s*REG(?:N|ISTRATION)?\.?',
        r'REG(?:N|ISTRATION)?\.?\s*DATE',
        r'DATE\s*OF\s*REGISTRATION',
        r'RC_REGN_DT',
    )

    # ── Fitness / Validity Upto ───────────────────────────────────────────────
    # Smart card: "Regn. Validity" / Form 23A: "REG/FC UPTO"
    fitness_upto = _extract_date(
        text_upper,
        r'REGN?\.?\s*VALIDITY',
        r'REG(?:N|ISTRATION)?/?FC\s*UPTO',
        r'FITNESS\s*UPTO',
        r'VALID(?:ITY)?\s*(?:UPTO|TILL|DATE)',
        r'RC_FIT_UPTO',
        r'VALID\s*UP\s*TO',
    )

    # ── Manufacturing Date ────────────────────────────────────────────────────
    mfg_date = _extract_date(
        text_upper,
        r'MFG\.?\s*DATE',
        r'MANUFACTURING\s*DATE',
        r'MONTH[\s\-]*YEAR\s*OF\s*MFG\.?',
        r'YEAR\s*OF\s*MFG\.?',
        r'MFG\.?\s*YEAR',
        r'RC_MFG_MONTH_YR',
    )
    # Smart card format: "Month-Year of Mfg.\n03-2022"
    if not mfg_date:
        m = re.search(
            r'MONTH[\s\-]*YEAR\s*OF\s*MFG\.?\s*\n\s*(\d{2}[\-/]\d{4})',
            text_upper
        )
        if m:
            parts = re.split(r'[\-/]', m.group(1))
            if len(parts) == 2:
                mfg_date = f"01/{parts[0].zfill(2)}/{parts[1]}"

    # ── Card Issue Date (Smart Card specific) ─────────────────────────────────
    card_issue_date = ""
    m = re.search(
        r'CARD\s*ISSUE\s*DATE\s*[:\(\-]?\s*(\d{2}[\-/\.]\d{2}[\-/\.]\d{4})',
        text_upper
    )
    if m:
        raw_date = m.group(1)
        parts    = re.split(r'[\-/\.]', raw_date)
        if len(parts) == 3:
            card_issue_date = f"{parts[0].zfill(2)}/{parts[1].zfill(2)}/{parts[2]}"

    # ── State (from vehicle number prefix) ───────────────────────────────────
    state = ""
    if vehicle_number and len(vehicle_number) >= 2:
        state = STATE_NAME_MAP.get(vehicle_number[:2].upper(), "")

    # ── Build result ──────────────────────────────────────────────────────────
    result = {
        "vehicle_number":    vehicle_number,
        "owner":             owner,
        "maker":             maker,
        "model":             model,
        "fuel_type":         fuel_type,
        "color":             color,
        "vehicle_class":     vehicle_class,
        "registration_date": registration_date,
        "fitness_upto":      fitness_upto,
        "engine_cc":         engine_cc,
        "chassis_number":    chassis_number,
        "engine_number":     engine_number,
        "mfg_date":          mfg_date,
        "card_issue_date":   card_issue_date,
        "rc_format":         rc_format,
        "insurance_upto":    "",
        "pucc_upto":         "",
        "state":             state,
    }

    print(f"[RC Extract] Format: {rc_format} | Vehicle: {vehicle_number}")
    for k, v in result.items():
        if v and k not in ("rc_format", "insurance_upto", "pucc_upto"):
            print(f"  {k}: {v}")

    return result

# ─────────────────────────────────────────────
#  Vehicle Number Helpers
# ─────────────────────────────────────────────
STATE_CODES = (
    r"AN|AP|AR|AS|BR|CG|CH|DD|DL|DN|GA|GJ|HP|HR|"
    r"JH|JK|KA|KL|LA|LD|MH|ML|MN|MP|MZ|NL|OD|PB|"
    r"PY|RJ|SK|TN|TR|TS|UK|UP|WB"
)
VEHICLE_REGEX = re.compile(
    rf"((?:{STATE_CODES}))[\s\-]?(\d{{1,2}})[\s\-]?([A-Z]{{1,3}})[\s\-]?(\d{{3,4}})",
    re.IGNORECASE,
)
OCR_DIGIT_FIX = str.maketrans("OIBSGZ", "015862")
RC_KW_PATTERN = re.compile(
    r"(registr|reg\.?\s*no|vehicle\s*no|veh\.?\s*no|regn\.|rc\s*no)",
    re.IGNORECASE,
)


def normalize_vehicle_number(text: str) -> str:
    return re.sub(r"[\s\-]", "", text).upper()


def fix_ocr_digits(raw: str) -> str:
    raw = normalize_vehicle_number(raw)
    m   = re.match(r"^([A-Z]{1,2})([0-9OI]{1,2})([A-Z]{1,3})([0-9OI]{3,4})$", raw, re.IGNORECASE)
    if m:
        return (m.group(1).upper() + m.group(2).upper().translate(OCR_DIGIT_FIX)
                + m.group(3).upper() + m.group(4).upper().translate(OCR_DIGIT_FIX))
    return raw


def extract_vehicle_number_from_text(text: str) -> Optional[str]:
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if RC_KW_PATTERN.search(line):
            block = " ".join(lines[i: i + 4])
            m = VEHICLE_REGEX.search(block)
            if m:
                c = fix_ocr_digits(m.group(0))
                if 8 <= len(c) <= 11:
                    return c
    for line in lines:
        m = VEHICLE_REGEX.search(line)
        if m:
            c = fix_ocr_digits(m.group(0))
            if 8 <= len(c) <= 11:
                return c
    clean = normalize_vehicle_number(text)
    anchored = re.compile(
        rf"((?:{STATE_CODES}))([0-9OI]{{2}})([A-Z]{{1,3}})([0-9OI]{{3,4}})", re.IGNORECASE)
    m = anchored.search(clean)
    if m:
        c = fix_ocr_digits(m.group(0))
        if 8 <= len(c) <= 11:
            return c
    return None


# ─────────────────────────────────────────────
#  Document Type Detection
# ─────────────────────────────────────────────
def detect_doc_type(text: str) -> str:
    t = text.lower()
    if "insurance" in t or "policy" in t or "premium" in t:
        return "Insurance"
    if "puc" in t or "pollution" in t or "emission" in t:
        return "PUC"
    if "regn" in t or "chassis" in t or "registration" in t or "reg no" in t:
        return "RC"
    return "Unknown"


# ─────────────────────────────────────────────
#  Expiry Date Extraction
# ─────────────────────────────────────────────
DATE_PATTERNS = [
    r"\b(\d{2})[\/\-\.](\d{2})[\/\-\.](\d{4})\b",
    r"\b(\d{2})[\/\-\.](\d{2})[\/\-\.](\d{2})\b",
    r"\b(\d{4})[\/\-\.](\d{2})[\/\-\.](\d{2})\b",
    r"\b(\d{1,2})\s+(January|February|March|April|May|June|July|August|"
    r"September|October|November|December)\s+(\d{4})\b",
    r"\b(\d{1,2})[\-\s](Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[\-\s](\d{4})\b",
]
EXPIRY_KEYWORDS = re.compile(
    r"(expir|valid\s*(?:till|upto|up\s*to)|validity|policy\s*end|cover\s*end|upto|puc\s*valid)",
    re.IGNORECASE,
)
MONTH_MAP = {
    "january":"01","february":"02","march":"03","april":"04","may":"05",
    "june":"06","july":"07","august":"08","september":"09","october":"10",
    "november":"11","december":"12","jan":"01","feb":"02","mar":"03",
    "apr":"04","jun":"06","jul":"07","aug":"08","sep":"09","oct":"10",
    "nov":"11","dec":"12",
}


def parse_date_match(m: re.Match, pattern: str) -> str:
    groups = m.groups()
    if any(mon in pattern for mon in ["January", "Jan"]):
        day   = groups[0].zfill(2)
        month = MONTH_MAP.get(groups[1].lower(), "00")
        year  = groups[2]
        return f"{day}/{month}/{year}" if month != "00" else ""
    if len(groups[0]) == 4:
        year, month, day = groups[0], groups[1], groups[2]
    else:
        day, month, year = groups[0], groups[1], groups[2]
        if len(year) == 2:
            year = "20" + year
    try:
        if not (2000 <= int(year) <= 2050): return ""
        if not (1 <= int(month) <= 12):     return ""
        if not (1 <= int(day) <= 31):       return ""
    except ValueError:
        return ""
    return f"{day}/{month}/{year}"


def extract_expiry_date(text: str) -> Optional[str]:
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if EXPIRY_KEYWORDS.search(line):
            block = " ".join(lines[i: i + 3])
            for pattern in DATE_PATTERNS:
                m = re.search(pattern, block, re.IGNORECASE)
                if m:
                    date_str = parse_date_match(m, pattern)
                    if date_str:
                        return date_str
    all_dates = []
    for pattern in DATE_PATTERNS:
        for m in re.finditer(pattern, text, re.IGNORECASE):
            date_str = parse_date_match(m, pattern)
            if date_str:
                try:
                    d, mo, y = date_str.split("/")
                    all_dates.append((int(y), int(mo), int(d), date_str))
                except Exception:
                    continue
    if all_dates:
        all_dates.sort(reverse=True)
        return all_dates[0][3]
    return None


# ─────────────────────────────────────────────
#  Expiry Status
# ─────────────────────────────────────────────
def compute_expiry_status(expiry_str: Optional[str]) -> dict:
    if not expiry_str:
        return {"days_remaining": None, "status": "unknown", "message": "No expiry date"}
    try:
        parts       = expiry_str.split("/")
        expiry_date = datetime(int(parts[2]), int(parts[1]), int(parts[0]))
        today       = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
        days        = (expiry_date - today).days
        if days < 0:
            return {"days_remaining": days, "status": "expired",
                    "message": f"Expired {abs(days)} days ago."}
        elif days <= 30:
            return {"days_remaining": days, "status": "expiring_soon",
                    "message": f"Expires in {days} day(s)."}
        else:
            return {"days_remaining": days, "status": "valid",
                    "message": f"Valid for {days} more days."}
    except Exception:
        return {"days_remaining": None, "status": "unknown", "message": "Invalid date format"}


# ─────────────────────────────────────────────
#  Vehicle Details API + Smart Mock
# ─────────────────────────────────────────────
STATE_NAME_MAP = {
    "KA": "Karnataka", "MH": "Maharashtra", "DL": "Delhi",
    "TN": "Tamil Nadu", "AP": "Andhra Pradesh", "TS": "Telangana",
    "GJ": "Gujarat", "RJ": "Rajasthan", "UP": "Uttar Pradesh",
    "WB": "West Bengal", "KL": "Kerala", "PB": "Punjab",
}

VEHICLE_DATABASE = [
    {"maker": "Honda",         "model": "Activa 6G",     "class": "M-Cycle/Scooter", "fuel": "Petrol", "engine": "109.51cc"},
    {"maker": "Honda",         "model": "CB Shine",      "class": "Motorcycle",       "fuel": "Petrol", "engine": "124cc"},
    {"maker": "Honda",         "model": "Unicorn 160",   "class": "Motorcycle",       "fuel": "Petrol", "engine": "162.71cc"},
    {"maker": "Honda",         "model": "Dio",           "class": "M-Cycle/Scooter", "fuel": "Petrol", "engine": "109.51cc"},
    {"maker": "Bajaj",         "model": "Pulsar 150",    "class": "Motorcycle",       "fuel": "Petrol", "engine": "149.5cc"},
    {"maker": "Bajaj",         "model": "Pulsar NS200",  "class": "Motorcycle",       "fuel": "Petrol", "engine": "199.5cc"},
    {"maker": "TVS",           "model": "Apache RTR 160","class": "Motorcycle",       "fuel": "Petrol", "engine": "159.7cc"},
    {"maker": "TVS",           "model": "Jupiter",       "class": "M-Cycle/Scooter", "fuel": "Petrol", "engine": "109.7cc"},
    {"maker": "Yamaha",        "model": "FZ-S V3",       "class": "Motorcycle",       "fuel": "Petrol", "engine": "149cc"},
    {"maker": "Yamaha",        "model": "R15 V4",        "class": "Motorcycle",       "fuel": "Petrol", "engine": "155cc"},
    {"maker": "Hero",          "model": "Splendor Plus", "class": "Motorcycle",       "fuel": "Petrol", "engine": "97.2cc"},
    {"maker": "Hero",          "model": "Glamour",       "class": "Motorcycle",       "fuel": "Petrol", "engine": "124.7cc"},
    {"maker": "Royal Enfield", "model": "Classic 350",   "class": "Motorcycle",       "fuel": "Petrol", "engine": "349cc"},
    {"maker": "Royal Enfield", "model": "Himalayan",     "class": "Motorcycle",       "fuel": "Petrol", "engine": "411cc"},
    {"maker": "KTM",           "model": "Duke 200",      "class": "Motorcycle",       "fuel": "Petrol", "engine": "199.5cc"},
    {"maker": "KTM",           "model": "Duke 390",      "class": "Motorcycle",       "fuel": "Petrol", "engine": "373.2cc"},
    {"maker": "Suzuki",        "model": "Gixxer SF 250", "class": "Motorcycle",       "fuel": "Petrol", "engine": "249cc"},
]

COLORS = ["Pearl Precious White","Matte Axis Grey","Rebel Red Metallic",
          "Athletic Blue Metallic","Midnight Black","Sports Red"]
OWNER_FIRST = ["Rahul","Priya","Amit","Sneha","Kiran","Pooja","Vijay","Meera"]
OWNER_LAST  = ["Kumar","Sharma","Singh","Patel","Reddy","Nair","Iyer","Joshi"]


def fetch_vehicle_details_from_api(vehicle_number: str) -> dict | None:
    if SUREPASS_TOKEN != "YOUR_SUREPASS_TOKEN_HERE":
        try:
            headers  = {"Authorization": f"Bearer {SUREPASS_TOKEN}", "Content-Type": "application/json"}
            response = requests.post("https://kyc-api.surepass.io/api/v1/rc/rc-full-details",
                                     json={"id_number": vehicle_number}, headers=headers, timeout=15)
            if response.status_code == 200:
                raw  = response.json()
                data = raw.get("data", raw)
                def get(*keys):
                    for k in keys:
                        val = data.get(k)
                        if val and str(val).strip() not in ("","null","None","NA","N/A","-"):
                            return str(val).strip()
                    return ""
                return {
                    "owner": get("owner_name"), "model": get("model","vehicle_model"),
                    "maker": get("vehicle_manufacturer_name","maker"),
                    "fuel_type": get("fuel_type"), "color": get("vehicle_colour","color"),
                    "registration_date": get("registration_date","reg_date"),
                    "vehicle_class": get("vehicle_class_desc","vehicle_class"),
                    "fitness_upto": get("fit_up_to","fitness_upto"),
                    "insurance_upto": get("insurance_upto"), "pucc_upto": get("pucc_upto"),
                    "chassis_number": get("chassis_number"), "engine_number": get("engine_number"),
                    "engine_cc": "", "mfg_date": "", "state": "",
                }
        except Exception as e:
            print(f"[Surepass] Failed: {e}")
    return _smart_mock(vehicle_number)


def _smart_mock(vehicle_number: str) -> dict:
    seed    = int(hashlib.md5(vehicle_number.encode()).hexdigest(), 16)
    vehicle = VEHICLE_DATABASE[seed % len(VEHICLE_DATABASE)]
    color   = COLORS[(seed // 7) % len(COLORS)]
    owner   = f"{OWNER_FIRST[(seed//3)%len(OWNER_FIRST)]} {OWNER_LAST[(seed//11)%len(OWNER_LAST)]}"
    sc      = re.match(r'^([A-Z]{2})', vehicle_number.upper())
    state   = STATE_NAME_MAP.get(sc.group(1) if sc else "KA", "Karnataka")
    reg_year = 2015 + (seed % 8)
    reg_mon  = 1 + (seed % 12)
    reg_day  = 1 + ((seed // 5) % 28)
    reg_date = f"{reg_day:02d}/{reg_mon:02d}/{reg_year}"
    today    = datetime.now()
    ins_date = (today + timedelta(days=180 + (seed % 180))).strftime("%d/%m/%Y")
    puc_date = (today + timedelta(days=90  + (seed % 180))).strftime("%d/%m/%Y")
    chars    = "ABCDEFGHJKLMNPRSTUVWXYZ0123456789"
    chassis  = "ME4" + "".join(chars[(seed >> i) % len(chars)] for i in range(14))
    engine   = "".join(chars[(seed * 3 >> i) % len(chars)] for i in range(10))
    return {
        "owner": owner, "model": f"{vehicle['maker']} {vehicle['model']}",
        "maker": vehicle["maker"], "fuel_type": vehicle["fuel"],
        "color": color, "registration_date": reg_date,
        "vehicle_class": vehicle["class"],
        "fitness_upto": f"{reg_day:02d}/{reg_mon:02d}/{reg_year + 15}",
        "insurance_upto": ins_date, "pucc_upto": puc_date,
        "chassis_number": chassis, "engine_number": engine,
        "state": state, "engine_cc": vehicle["engine"], "mfg_date": "",
    }


# ─────────────────────────────────────────────
#  Vehicle Image
# ─────────────────────────────────────────────
def fetch_vehicle_image(maker: str, model: str) -> Optional[str]:
    if not UNSPLASH_ACCESS_KEY:
        print("[Unsplash] No API key found")
        return None

    try:
        query = f"{maker} {model}"

        print(f"[Unsplash] Searching for: {query}")

        response = requests.get(
            "https://api.unsplash.com/search/photos",
            params={
                "query": query,
                "per_page": 1,
                "orientation": "landscape",
            },
            headers={
                "Authorization": f"Client-ID {UNSPLASH_ACCESS_KEY}"
            },
            timeout=15,
        )

        print(f"[Unsplash] Status = {response.status_code}")

        if response.status_code == 200:
            data = response.json()
            results = data.get("results", [])

            if results:
                image_url = results[0]["urls"]["regular"]
                print(f"[Unsplash] Image Found = {image_url}")
                return image_url

            print(f"[Unsplash] No results for {query}")

        else:
            print(f"[Unsplash] Error response: {response.text}")

    except Exception as e:
        print(f"[Unsplash Error] {e}")

    return None

# ─────────────────────────────────────────────
#  Manual Loading
# ─────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────
#  REAL VEHICLE MANUAL URLS
#  Add your Firebase Storage URLs here after uploading the PDFs.
#  Key = lowercase model name (must match what comes from the API/RC)
#  Value = Firebase Storage download URL
# ─────────────────────────────────────────────────────────────────────────────
REAL_MANUAL_URLS = {
    # Honda
    "honda dio":                 "https://firebasestorage.googleapis.com/v0/b/vehicle-doc-intelligence.firebasestorage.app/o/manuals%2Fhonda-dio.pdf?alt=media&token=9bdf2cb0-463f-4354-b2cd-c3e4aae41432",
    "honda activa 6g":           "YOUR_FIREBASE_URL_FOR_honda-activa-6g.pdf",
    "honda activa 5g":           "YOUR_FIREBASE_URL_FOR_honda-activa-5g.pdf",
    "honda cb shine":            "YOUR_FIREBASE_URL_FOR_honda-cb-shine.pdf",
    "honda unicorn 160":         "YOUR_FIREBASE_URL_FOR_honda-unicorn.pdf",
    "honda hornet 2.0":          "YOUR_FIREBASE_URL_FOR_honda-hornet.pdf",
    # Bajaj
    "bajaj pulsar 150":          "YOUR_FIREBASE_URL_FOR_bajaj-pulsar-150.pdf",
    "bajaj pulsar ns200":        "YOUR_FIREBASE_URL_FOR_bajaj-pulsar-ns200.pdf",
    "bajaj dominar 400":         "YOUR_FIREBASE_URL_FOR_bajaj-dominar-400.pdf",
    # Royal Enfield
    "royal enfield classic 350": "YOUR_FIREBASE_URL_FOR_re-classic-350.pdf",
    "royal enfield himalayan":   "YOUR_FIREBASE_URL_FOR_re-himalayan.pdf",
    "royal enfield meteor 350":  "YOUR_FIREBASE_URL_FOR_re-meteor-350.pdf",
    # TVS
    "tvs apache rtr 160":        "YOUR_FIREBASE_URL_FOR_tvs-apache-160.pdf",
    "tvs jupiter":               "YOUR_FIREBASE_URL_FOR_tvs-jupiter.pdf",
    "tvs ntorq 125":             "YOUR_FIREBASE_URL_FOR_tvs-ntorq.pdf",
    # Yamaha
    "yamaha r15 v4":             "YOUR_FIREBASE_URL_FOR_yamaha-r15.pdf",
    "yamaha fz-s v3":            "YOUR_FIREBASE_URL_FOR_yamaha-fz.pdf",
    # Hero
    "hero splendor plus":        "YOUR_FIREBASE_URL_FOR_hero-splendor.pdf",
    "hero glamour":              "YOUR_FIREBASE_URL_FOR_hero-glamour.pdf",
    # KTM
    "ktm duke 200":              "YOUR_FIREBASE_URL_FOR_ktm-duke-200.pdf",
    "ktm duke 390":              "YOUR_FIREBASE_URL_FOR_ktm-duke-390.pdf",
    # Suzuki
    "suzuki gixxer sf 250":      "YOUR_FIREBASE_URL_FOR_suzuki-gixxer.pdf",
    "suzuki access 125":         "YOUR_FIREBASE_URL_FOR_suzuki-access.pdf",
}


def _get_manual_url(model_name: str) -> Optional[str]:
    """
    Find the PDF manual URL for a given model name.
    Tries exact match first, then partial match.
    """
    if not model_name:
        return None

    model_lower = model_name.lower().strip()

    # Exact match
    if model_lower in REAL_MANUAL_URLS:
        url = REAL_MANUAL_URLS[model_lower]
        if "YOUR_FIREBASE_URL" not in url:
            print(f"[Manual] Exact URL match: '{model_lower}'")
            return url

    # Partial match — "Honda Dio DX" matches "honda dio"
    for key, url in REAL_MANUAL_URLS.items():
        if "YOUR_FIREBASE_URL" in url:
            continue
        if key in model_lower or model_lower in key:
            print(f"[Manual] Partial URL match: '{model_lower}' → '{key}'")
            return url

    print(f"[Manual] No PDF URL found for '{model_lower}'")
    return None


def _extract_text_from_pdf_url(url: str) -> str:
    """
    Download a PDF from URL and extract all text using PyMuPDF.
    Returns empty string if download or extraction fails.
    """
    try:
        print(f"[Manual] Downloading PDF from: {url[:60]}...")
        response = requests.get(url, timeout=30)

        if response.status_code != 200:
            print(f"[Manual] Download failed: HTTP {response.status_code}")
            return ""

        pdf  = fitz.open(stream=response.content, filetype="pdf")
        text = ""
        for page_num in range(len(pdf)):
            page_text = pdf.load_page(page_num).get_text()
            text += page_text

        print(f"[Manual] Extracted {len(text)} characters from "
              f"{pdf.page_count} pages")

        if len(text) < 500:
            print(f"[Manual] PDF appears to be image-based — "
                  f"insufficient text extracted")
            return ""

        return text

    except Exception as e:
        print(f"[Manual] PDF extraction error: {e}")
        return ""


def load_manual_for_vehicle(
    vehicle_number: str,
    model_name: str,
    user_id: str,
    rc_data: dict = None,
) -> bool:
    """
    Load manual for a vehicle. Priority order:
    1. Already loaded — return immediately
    2. Real PDF from Firebase Storage — best accuracy
    3. AI generated — guaranteed fallback

    The AI fallback means the chat ALWAYS works even without a PDF.
    """

    kb = get_user_knowledge(user_id)

    if vehicle_number not in kb:
        kb[vehicle_number] = {"manual": [], "bills": []}

    # Already loaded — skip
    if kb[vehicle_number]["manual"]:
        print(f"[Manual] Already loaded for {vehicle_number}")
        return True

    print(f"[Manual] Loading for: {model_name}")

    # ── PRIORITY 1: Try real PDF manual ─────────────────────
    pdf_url = _get_manual_url(model_name)

    if pdf_url:
        print(f"[Manual] Trying real PDF: {pdf_url[:60]}...")

        pdf_text = _extract_text_from_pdf_url(pdf_url)

        if pdf_text and len(pdf_text) > 500:
            chunks = chunk_text(
                pdf_text,
                source_label=f"Owner Manual — {model_name} (Official PDF)"
            )

            kb[vehicle_number]["manual"] = chunks

            print(f"[Manual] ✅ Loaded from real PDF: {len(chunks)} chunks")

            return True

        else:
            print(
                f"[Manual] ⚠️ PDF extraction failed — "
                f"falling back to AI generation"
            )

    # ── PRIORITY 2: AI Generated manual ─────────────────────
    print(f"[Manual] Generating AI manual for: {model_name}")

    return _generate_manual_with_ai(
        vehicle_number,
        model_name,
        user_id,
        rc_data,
    )

def _generate_manual_with_ai(
    vehicle_number: str,
    model_name: str,
    user_id: str,
    rc_data: dict = None,
) -> bool:
    """
    Generate manual content using Groq AI.
    Used as fallback when no real PDF is available.
    """
    kb = get_user_knowledge(user_id)

    if vehicle_number not in kb:
        kb[vehicle_number] = {
            "manual": [],
            "bills": []
        }
    rc_context = ""
    if rc_data:
        parts = []
        if rc_data.get("engine_cc"):
            parts.append(f"engine: {rc_data['engine_cc']}")
        if rc_data.get("fuel_type"):
            parts.append(f"fuel: {rc_data['fuel_type']}")
        if parts:
            rc_context = f" Known specs: {', '.join(parts)}."

    sections = [
        ("Engine & Technical Specifications",
         f"Complete technical specs for {model_name}.{rc_context} "
         f"Include: engine type, displacement, max power (bhp at rpm), "
         f"max torque (Nm at rpm), ignition, transmission."),

        ("Maintenance Schedule",
         f"Complete maintenance schedule for {model_name} with exact km "
         f"and month intervals: engine oil, oil filter, air filter, "
         f"spark plug, valve clearance, chain, brakes, tyres."),

        ("Engine Oil & Fluids",
         f"Exact fluid specs for {model_name}: engine oil grade, "
         f"oil capacity in litres, brake fluid type, fuel tank "
         f"capacity, recommended octane."),

        ("Tyre Specifications & Brakes",
         f"Tyre and brake specs for {model_name}: front/rear tyre sizes, "
         f"tyre pressures in PSI (solo and pillion), brake types."),

        ("Electrical System",
         f"Electrical specs for {model_name}: battery voltage and Ah, "
         f"headlight wattage, main fuse rating, charging voltage."),

        ("Common Problems & Troubleshooting",
         f"Top 6 common problems for {model_name} with diagnosis and "
         f"fixes: hard starting, rough idle, poor mileage, chain "
         f"noise, brake issues, electrical faults."),

        ("Safety & Riding Guidelines",
         f"Safety guidelines for {model_name}: break-in procedure, "
         f"max load, pre-ride checklist, storage guidelines."),
    ]

    all_chunks = []
    for section_title, prompt in sections:
        try:
            response = groq_client.chat.completions.create(
                model="llama-3.3-70b-versatile",
                messages=[
                    {"role": "system", "content":
                     "You are a certified motorcycle mechanic. "
                     "Provide accurate, specific technical information. "
                     "Use exact numbers. Never say you don't know."},
                    {"role": "user", "content": prompt},
                ],
                max_tokens=700,
                temperature=0.1,
            )
            content      = response.choices[0].message.content
            section_text = f"=== {section_title} ===\n{content}"
            chunks       = chunk_text(
                section_text,
                source_label=f"Owner Manual — {section_title} (AI Generated)"
            )
            all_chunks.extend(chunks)
            print(f"[Manual] ✓ AI: {section_title} ({len(chunks)} chunks)")
        except Exception as e:
            print(f"[Manual] ✗ AI: {section_title}: {e}")

    if all_chunks:
        kb[vehicle_number]["manual"] = all_chunks
        print(f"[Manual] Total: {len(all_chunks)} AI chunks for "
              f"{vehicle_number}")
        return True

    return False

# ─────────────────────────────────────────────
#  Text Chunking + Retrieval
# ─────────────────────────────────────────────
def chunk_text(text: str, source_label: str) -> list[dict]:
    chunks = []
    start  = 0
    text   = text.strip()
    while start < len(text):
        end   = min(start + CHUNK_SIZE, len(text))
        chunk = text[start:end].strip()
        if chunk:
            chunks.append({"text": chunk, "source": source_label})
        start += CHUNK_SIZE - CHUNK_OVERLAP
    return chunks


def _tokenize(text: str) -> set[str]:
    return set(re.findall(r'\b[a-z]{2,}\b', text.lower()))


def retrieve_chunks(query: str, chunks: list[dict], top_k: int = TOP_K_CHUNKS) -> list[dict]:
    if not chunks:
        return []
    query_tokens = _tokenize(query)
    if not query_tokens:
        return chunks[:top_k]
    scored = []
    for chunk in chunks:
        chunk_tokens = _tokenize(chunk["text"])
        overlap = len(query_tokens & chunk_tokens)
        union   = len(query_tokens | chunk_tokens)
        scored.append((overlap / union if union > 0 else 0, chunk))
    scored.sort(key=lambda x: x[0], reverse=True)
    return [c for _, c in scored[:top_k]]


# ─────────────────────────────────────────────
#  Service Bill Processing
# ─────────────────────────────────────────────
def extract_service_bill_text(ocr_text: str) -> str:
    lines    = [l.strip() for l in ocr_text.split('\n') if l.strip()]
    result   = []
    date_pat = re.compile(r'\b(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4})\b')
    odo_pat  = re.compile(r'(\d{4,6})\s*(km|kms|kilometers|odometer)', re.IGNORECASE)
    for line in lines:
        m = date_pat.search(line)
        if m:
            result.append(f"Service Date: {m.group(1)}")
            break
    for line in lines:
        m = odo_pat.search(line)
        if m:
            result.append(f"Odometer: {m.group(1)} km")
            break
    result.append("Full Service Record:")
    result.extend(lines)
    return "\n".join(result)


def generate_bill_explanation(ocr_text: str, vehicle_model: str) -> str:
    try:
        response = groq_client.chat.completions.create(
            model="llama-3.3-70b-versatile",
            messages=[
                {"role": "system", "content": "You are a vehicle service advisor explaining bills simply."},
                {"role": "user", "content":
                 f"Vehicle: {vehicle_model}\n\nBill:\n{ocr_text[:2000]}\n\n"
                 "Explain: 1) Work done 2) Parts replaced 3) Cost 4) Date and odometer 5) Recommendations."},
            ],
            max_tokens=500, temperature=0.3,
        )
        return response.choices[0].message.content
    except Exception as e:
        return "Service bill uploaded. Ask the AI for details."


# ─────────────────────────────────────────────
#  Chat Helpers
# ─────────────────────────────────────────────
def _get_vehicle_context(
    vehicle_number: str,
    user_id: str,
) -> Optional[dict]:

    vehicles = get_user_vehicles(user_id)

    vn = normalize_vehicle_number(vehicle_number)

    return next(
        (
            v for v in vehicles
            if normalize_vehicle_number(v["vehicle_number"]) == vn
        ),
        None,
    )


def _build_context_block(vehicle: dict, query: str, kb: dict) -> str:
    manual_chunks = kb.get("manual", [])
    bill_chunks   = kb.get("bills", [])
    top_manual    = retrieve_chunks(query, manual_chunks, top_k=5)
    top_bills     = retrieve_chunks(query, bill_chunks, top_k=3)
    if not manual_chunks:
        return "MANUAL STATUS: Owner manual not loaded."
    lines = []
    if top_manual:
        lines.append("=== FROM OWNER MANUAL ===")
        for chunk in top_manual:
            lines.append(f"[{chunk['source']}]\n{chunk['text']}\n---")
    if top_bills:
        lines.append("=== FROM SERVICE HISTORY ===")
        for chunk in top_bills:
            lines.append(f"[{chunk['source']}]\n{chunk['text']}\n---")
    return "\n".join(lines)


SYSTEM_PROMPT = """You are a vehicle assistant.
RULES:
1. Check manual context first. If found: start with "According to your owner's manual..."
2. If not in manual but vehicle-related: start with "Based on general automotive knowledge..."
3. If not vehicle-related: reply ONLY with "I can only answer questions about your vehicle."
4. Never make up specific numbers not in context.
5. For service history: use "Based on your service records..." or say no bills uploaded.

VEHICLE: {vehicle_info}
CONTEXT: {context}"""


def build_system_prompt(vehicle: dict, context_block: str) -> str:
    number = vehicle.get("vehicle_number", "Unknown")
    kb = {"manual": [], "bills": []}
    vehicle_info = (
        f"Vehicle: {number} | Model: {vehicle.get('maker','')} {vehicle.get('model','')}\n"
        f"Fuel: {vehicle.get('fuel_type','')} | Engine: {vehicle.get('engine_cc','')}\n"
        f"Manual Sections: {len(kb.get('manual',[]))} | Service Records: {len(kb.get('bills',[]))}"
    )
    return SYSTEM_PROMPT.format(vehicle_info=vehicle_info,
                                 context=context_block or "(No context available)")


# ─────────────────────────────────────────────
#  Vehicle Profile Builder
# ─────────────────────────────────────────────
def _build_vehicle_dict(vehicle_number: str, details: dict,
                         rc_url: Optional[str] = None) -> dict:
    image_url = fetch_vehicle_image(details.get("maker", ""), details.get("model", ""))
    docs = []
    if rc_url:
        docs.append({"type": "RC", "url": rc_url, "urls": [rc_url],
                     "expiry_date": None, "uploaded_at": datetime.now().strftime('%d/%m/%Y')})
    return {
        "vehicle_number":    vehicle_number,
        "owner":             details.get("owner", ""),
        "model":             details.get("model", ""),
        "maker":             details.get("maker", ""),
        "fuel_type":         details.get("fuel_type", ""),
        "color":             details.get("color", ""),
        "registration_date": details.get("registration_date", ""),
        "vehicle_class":     details.get("vehicle_class", ""),
        "fitness_upto":      details.get("fitness_upto", ""),
        "insurance_upto":    details.get("insurance_upto", ""),
        "pucc_upto":         details.get("pucc_upto", ""),
        "chassis_number":    details.get("chassis_number", ""),
        "engine_number":     details.get("engine_number", ""),
        "engine_cc":         details.get("engine_cc", ""),
        "mfg_date":          details.get("mfg_date", ""),
        "state":             details.get("state", ""),
        "image_url":         image_url,
        "documents":         docs,
        "service_bills":     [],
        "damage_reports":    [],
    }
 
def _generate_claim_pdf(data: dict) -> str:
    """
    Generates a professional insurance claim PDF report.
    Returns the path to the generated PDF file.
    """
    tmp_dir  = tempfile.mkdtemp()
    pdf_path = os.path.join(tmp_dir, f"claim_{data['claimReference']}.pdf")
 
    doc = SimpleDocTemplate(
        pdf_path,
        pagesize=A4,
        rightMargin=2*cm,
        leftMargin=2*cm,
        topMargin=2*cm,
        bottomMargin=2*cm,
    )
 
    # ── Styles ─────────────────────────────────────────────────────────────────
    styles = getSampleStyleSheet()
 
    style_title = ParagraphStyle(
        "ClaimTitle",
        parent=styles["Title"],
        fontSize=20,
        textColor=colors.HexColor("#1A1A2E"),
        spaceAfter=6,
        alignment=TA_CENTER,
        fontName="Helvetica-Bold",
    )
    style_subtitle = ParagraphStyle(
        "ClaimSubtitle",
        parent=styles["Normal"],
        fontSize=11,
        textColor=colors.HexColor("#555555"),
        spaceAfter=4,
        alignment=TA_CENTER,
    )
    style_section = ParagraphStyle(
        "SectionHeader",
        parent=styles["Heading2"],
        fontSize=13,
        textColor=colors.HexColor("#1A1A2E"),
        spaceBefore=16,
        spaceAfter=6,
        fontName="Helvetica-Bold",
        borderPad=4,
    )
    style_body = ParagraphStyle(
        "BodyText",
        parent=styles["Normal"],
        fontSize=10,
        textColor=colors.HexColor("#333333"),
        spaceAfter=4,
        leading=15,
    )
    style_label = ParagraphStyle(
        "Label",
        parent=styles["Normal"],
        fontSize=10,
        textColor=colors.HexColor("#666666"),
        fontName="Helvetica-Bold",
        spaceAfter=2,
    )
    style_ref = ParagraphStyle(
        "Reference",
        parent=styles["Normal"],
        fontSize=12,
        textColor=colors.HexColor("#E8B84B"),
        fontName="Helvetica-Bold",
        alignment=TA_CENTER,
        spaceAfter=4,
    )
    style_footer = ParagraphStyle(
        "Footer",
        parent=styles["Normal"],
        fontSize=8,
        textColor=colors.HexColor("#999999"),
        alignment=TA_CENTER,
    )
    style_disclaimer = ParagraphStyle(
        "Disclaimer",
        parent=styles["Normal"],
        fontSize=9,
        textColor=colors.HexColor("#888888"),
        spaceAfter=4,
        leading=13,
        alignment=TA_LEFT,
    )
 
    # ── Content ────────────────────────────────────────────────────────────────
    story = []
 
    # Header
    story.append(Paragraph("MOTOR VEHICLE INSURANCE CLAIM REPORT", style_title))
    story.append(Paragraph("Generated by AutoVault — Vehicle Management System", style_subtitle))
    story.append(Spacer(1, 0.1*inch))
 
    # Reference number box
    ref_table = Table(
        [[Paragraph(f"Claim Reference: {data['claimReference']}", style_ref)]],
        colWidths=[16*cm],
    )
    ref_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#1A1A2E")),
        ("ROWBACKGROUNDS", (0, 0), (-1, -1), [colors.HexColor("#1A1A2E")]),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 10),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 10),
        ("LEFTPADDING", (0, 0), (-1, -1), 10),
        ("RIGHTPADDING", (0, 0), (-1, -1), 10),
        ("ROUNDEDCORNERS", (0, 0), (-1, -1), 6),
    ]))
    story.append(ref_table)
    story.append(Spacer(1, 0.15*inch))
 
    # ── Section 1: Vehicle & Claim Details ────────────────────────────────────
    story.append(Paragraph("1. VEHICLE &amp; CLAIM DETAILS", style_section))
    story.append(HRFlowable(width="100%", thickness=1,
                             color=colors.HexColor("#E8B84B"), spaceAfter=8))
 
    vehicle_data = [
        ["Vehicle Registration No.", data.get("vehicleNumber", "—")],
        ["Owner Name",               data.get("ownerName", "—")],
        ["Insurance Status",         data.get("insuranceStatus", "—")],
        ["Date &amp; Time of Report", data.get("submittedAt", "—")],
        ["Photographs Submitted",    str(data.get("photosSubmitted", 0))],
    ]
    vehicle_table = Table(vehicle_data, colWidths=[6*cm, 10*cm])
    vehicle_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (0, -1), colors.HexColor("#F5F5F5")),
        ("TEXTCOLOR", (0, 0), (0, -1), colors.HexColor("#444444")),
        ("FONTNAME", (0, 0), (0, -1), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 10),
        ("ROWBACKGROUNDS", (0, 0), (-1, -1),
         [colors.HexColor("#FAFAFA"), colors.white]),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#DDDDDD")),
        ("TOPPADDING", (0, 0), (-1, -1), 7),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
        ("LEFTPADDING", (0, 0), (-1, -1), 8),
        ("RIGHTPADDING", (0, 0), (-1, -1), 8),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
    ]))
    story.append(vehicle_table)
 
    # ── Section 2: Accident Description ───────────────────────────────────────
    story.append(Paragraph("2. ACCIDENT DESCRIPTION", style_section))
    story.append(HRFlowable(width="100%", thickness=1,
                             color=colors.HexColor("#E8B84B"), spaceAfter=8))
    desc = data.get("accidentDescription", "No description provided.")
    story.append(Paragraph(desc, style_body))
 
    # ── Section 3: AI Damage Assessment ───────────────────────────────────────
    damage = data.get("damageSummary", "").strip()
    if damage:
        story.append(Paragraph("3. AI DAMAGE ASSESSMENT", style_section))
        story.append(HRFlowable(width="100%", thickness=1,
                                 color=colors.HexColor("#E8B84B"), spaceAfter=8))
        story.append(Paragraph(
            "<i>The following damage assessment was generated by AI vision analysis "
            "of the submitted accident photographs:</i>",
            style_disclaimer,
        ))
        story.append(Spacer(1, 0.05*inch))
 
        damage_box = Table(
            [[Paragraph(damage, style_body)]],
            colWidths=[16*cm],
        )
        damage_box.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#FFF8E7")),
            ("BOX", (0, 0), (-1, -1), 1, colors.HexColor("#E8B84B")),
            ("TOPPADDING", (0, 0), (-1, -1), 10),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 10),
            ("LEFTPADDING", (0, 0), (-1, -1), 10),
            ("RIGHTPADDING", (0, 0), (-1, -1), 10),
        ]))
        story.append(damage_box)
 
    # ── Section 4: Document Checklist ─────────────────────────────────────────
    checklist = data.get("checklist", [])
    if checklist:
        story.append(Paragraph(
            "4. DOCUMENT CHECKLIST" if damage else "3. DOCUMENT CHECKLIST",
            style_section,
        ))
        story.append(HRFlowable(width="100%", thickness=1,
                                 color=colors.HexColor("#E8B84B"), spaceAfter=8))
 
        table_data = [["Document", "Status", "Required", "Notes"]]
        for item in checklist:
            available = item.get("available", False)
            required  = item.get("required", False)
            status    = "✓ Available" if available else "✗ Missing"
            req_text  = "Yes" if required else "No"
            note      = item.get("note", "")
            table_data.append([
                item.get("item", ""),
                status,
                req_text,
                note,
            ])
 
        check_table = Table(
            table_data,
            colWidths=[4.5*cm, 3.5*cm, 2.5*cm, 5.5*cm],
        )
 
        # Row colors based on availability
        row_styles = [
            ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#1A1A2E")),
            ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
            ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
            ("FONTSIZE", (0, 0), (-1, -1), 9),
            ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#DDDDDD")),
            ("TOPPADDING", (0, 0), (-1, -1), 6),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
            ("LEFTPADDING", (0, 0), (-1, -1), 8),
            ("RIGHTPADDING", (0, 0), (-1, -1), 8),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ]
        for i, item in enumerate(checklist, start=1):
            available = item.get("available", False)
            required  = item.get("required", False)
            if available:
                bg = colors.HexColor("#F0FFF4")
                tc = colors.HexColor("#276749")
            elif required:
                bg = colors.HexColor("#FFF5F5")
                tc = colors.HexColor("#C53030")
            else:
                bg = colors.HexColor("#FFFFF0")
                tc = colors.HexColor("#744210")
            row_styles.append(("BACKGROUND", (0, i), (-1, i), bg))
            row_styles.append(("TEXTCOLOR", (1, i), (1, i), tc))
            row_styles.append(("FONTNAME", (1, i), (1, i), "Helvetica-Bold"))
 
        check_table.setStyle(TableStyle(row_styles))
        story.append(check_table)
 
    # ── Section 5: Next Steps ──────────────────────────────────────────────────
    next_sec_num = 5 if (damage and checklist) else (4 if (damage or checklist) else 3)
    story.append(Paragraph(f"{next_sec_num}. RECOMMENDED NEXT STEPS", style_section))
    story.append(HRFlowable(width="100%", thickness=1,
                             color=colors.HexColor("#E8B84B"), spaceAfter=8))
 
    steps = [
        ("URGENT", "File an FIR",
         "Visit nearest police station and file a First Information Report (FIR) within 24 hours of the accident. Obtain a copy of the FIR — it is mandatory for the insurance claim."),
        ("URGENT", "Notify Your Insurance Company",
         "Call your insurer helpline immediately. Most insurers require notification within 24-48 hours. Provide the claim reference number from this report."),
        ("ACTION", "Vehicle Inspection",
         "Take your vehicle to an authorised garage. The insurance company will send a surveyor to assess the damage. Do not carry out repairs before the surveyor's visit."),
        ("ACTION", "Submit Documents",
         "Submit to the insurer: RC, Insurance Policy, FIR copy, Driving Licence, Repair Estimate from garage, and this claim report."),
        ("INFO", "Claim Settlement",
         "After surveyor approval, the insurer will process your claim — either cashless at a network garage or reimbursement based on your policy type."),
    ]
 
    urgency_colors = {
        "URGENT": colors.HexColor("#C53030"),
        "ACTION": colors.HexColor("#744210"),
        "INFO":   colors.HexColor("#276749"),
    }
    urgency_bg = {
        "URGENT": colors.HexColor("#FFF5F5"),
        "ACTION": colors.HexColor("#FFFFF0"),
        "INFO":   colors.HexColor("#F0FFF4"),
    }
 
    steps_data = [["Priority", "Step", "Action Required"]]
    for urgency, title, desc in steps:
        steps_data.append([urgency, title, desc])
 
    steps_table = Table(steps_data, colWidths=[2*cm, 4*cm, 10*cm])
    steps_styles = [
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#1A1A2E")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 9),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#DDDDDD")),
        ("TOPPADDING", (0, 0), (-1, -1), 8),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
    ]
    for i, (urgency, _, _) in enumerate(steps, start=1):
        bg = urgency_bg.get(urgency, colors.white)
        tc = urgency_colors.get(urgency, colors.black)
        steps_styles.append(("BACKGROUND", (0, i), (-1, i), bg))
        steps_styles.append(("TEXTCOLOR", (0, i), (0, i), tc))
        steps_styles.append(("FONTNAME", (0, i), (1, i), "Helvetica-Bold"))
 
    steps_table.setStyle(TableStyle(steps_styles))
    story.append(steps_table)
 
    # ── Disclaimer ─────────────────────────────────────────────────────────────
    story.append(Spacer(1, 0.3*inch))
    story.append(HRFlowable(width="100%", thickness=0.5,
                             color=colors.HexColor("#CCCCCC"), spaceAfter=8))
    story.append(Paragraph(
        "<b>IMPORTANT DISCLAIMER:</b> This report was generated automatically by the AutoVault "
        "application. The AI damage assessment is based on computer vision analysis and is "
        "provided for reference purposes only. It does not replace a professional insurance "
        "surveyor's assessment. The final claim settlement is subject to your insurance policy "
        "terms and conditions and the decision of your insurance company.",
        style_disclaimer,
    ))
    story.append(Spacer(1, 0.1*inch))
    story.append(Paragraph(
        f"Report generated by AutoVault | {data.get('submittedAt', '')} | Ref: {data.get('claimReference', '')}",
        style_footer,
    ))
 
    # Build PDF
    doc.build(story)
    return pdf_path

# ─────────────────────────────────────────────
#  FEATURE 1: DAMAGE DETECTION
# ─────────────────────────────────────────────
@app.post("/detect-damage")
def detect_damage(data: DamageDetectionRequest):
    """
    Analyse a vehicle image for visible damage using Groq vision.
    Returns damage types, severity, affected areas, and repair recommendations.
    """
    try:
        vehicle_number = normalize_vehicle_number(data.vehicleNumber)
        target = _get_vehicle_context(vehicle_number)

        # Download image and convert to base64 for vision model
        print(f"[Damage] Analysing image for {vehicle_number}...")
        img_b64, media_type = image_url_to_base64(data.imageUrl)

        prompt = """Analyse this vehicle image for damage. Provide a structured assessment:

1. DAMAGE DETECTED: List each type of damage visible (scratches, dents, cracks, rust, broken parts, paint damage, etc.)
2. AFFECTED AREAS: Describe exactly where on the vehicle each damage is located
3. SEVERITY: Rate overall severity as LOW, MEDIUM, or HIGH with reasoning
4. SEVERITY DETAILS:
   - LOW: Minor cosmetic damage, no functional impact
   - MEDIUM: Noticeable damage, may affect resale value or minor function
   - HIGH: Significant structural or functional damage, immediate attention needed
5. REPAIR RECOMMENDATIONS: Specific repairs needed for each damage item
6. ESTIMATED PRIORITY: Which repairs are most urgent

If no damage is visible, clearly state "NO VISIBLE DAMAGE DETECTED" and describe the vehicle condition.
Be specific and professional. Format your response clearly with these exact section headers."""

        response = groq_client.chat.completions.create(
            model="meta-llama/llama-4-scout-17b-16e-instruct",
            messages=[
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {
                            "type":      "image_url",
                            "image_url": {
                                "url": f"data:{media_type};base64,{img_b64}"
                            },
                        },
                    ],
                }
            ],
            max_tokens=1000,
            temperature=0.2,
        )

        analysis_text = response.choices[0].message.content
        print(f"[Damage] Analysis complete: {analysis_text[:100]}...")

        # Parse severity from response
        severity = "MEDIUM"
        if "HIGH" in analysis_text.upper() and "SEVERITY" in analysis_text.upper():
            severity = "HIGH"
        elif "LOW" in analysis_text.upper() and "SEVERITY" in analysis_text.upper():
            severity = "LOW"
        if "NO VISIBLE DAMAGE" in analysis_text.upper():
            severity = "NONE"

        # Store damage report on vehicle
        report = {
            "image_url":   data.imageUrl,
            "analysed_at": datetime.now().strftime('%d/%m/%Y %H:%M'),
            "severity":    severity,
            "analysis":    analysis_text,
        }
        if target:
            if "damage_reports" not in target:
                target["damage_reports"] = []
            target["damage_reports"].append(report)

        return {
            "message":       "Damage analysis complete.",
            "vehicle_number": vehicle_number,
            "severity":      severity,
            "analysis":      analysis_text,
            "analysed_at":   report["analysed_at"],
        }

    except Exception as e:
        print(f"ERROR /detect-damage: {e}")
        import traceback; traceback.print_exc()
        return {"message": "Damage analysis failed", "error": str(e)}


# ─────────────────────────────────────────────
#  FEATURE 2: PREDICTIVE MAINTENANCE
# ─────────────────────────────────────────────

# Standard maintenance intervals (km)
MAINTENANCE_INTERVALS = {
    "Engine Oil Change":       {"interval_km": 3000,  "interval_months": 6,  "priority": "HIGH"},
    "Oil Filter":              {"interval_km": 6000,  "interval_months": 12, "priority": "HIGH"},
    "Air Filter Clean":        {"interval_km": 6000,  "interval_months": 12, "priority": "MEDIUM"},
    "Air Filter Replace":      {"interval_km": 12000, "interval_months": 24, "priority": "MEDIUM"},
    "Spark Plug Check":        {"interval_km": 6000,  "interval_months": 12, "priority": "MEDIUM"},
    "Spark Plug Replace":      {"interval_km": 12000, "interval_months": 24, "priority": "MEDIUM"},
    "Chain Lubrication":       {"interval_km": 500,   "interval_months": 1,  "priority": "HIGH"},
    "Chain Adjustment":        {"interval_km": 2000,  "interval_months": 3,  "priority": "HIGH"},
    "Chain Replace":           {"interval_km": 20000, "interval_months": 36, "priority": "MEDIUM"},
    "Brake Fluid":             {"interval_km": 12000, "interval_months": 24, "priority": "HIGH"},
    "Tyre Pressure Check":     {"interval_km": 500,   "interval_months": 1,  "priority": "HIGH"},
    "Valve Clearance":         {"interval_km": 12000, "interval_months": 24, "priority": "MEDIUM"},
    "Coolant Change":          {"interval_km": 20000, "interval_months": 24, "priority": "LOW"},
    "Battery Check":           {"interval_km": 6000,  "interval_months": 12, "priority": "MEDIUM"},
}


@app.post("/predictive-maintenance")
def predictive_maintenance(data: MaintenanceRequest):
    """
    Analyses vehicle data and service history to predict upcoming maintenance needs.
    Uses service bills, registration date, and mileage to calculate what's due.
    """
    try:
        vehicle_number = normalize_vehicle_number(data.vehicleNumber)
        user_id = data.userId or "default"

        target = _get_vehicle_context(vehicle_number,user_id,)
        if not target:
            return {"message": "Vehicle not found."}

        model_name    = target.get("model", "Unknown Vehicle")
        reg_date_str  = target.get("registration_date", "")
        current_km    = data.currentMileage or 0
        bills         = target.get("service_bills", [])
        bill_chunks = []

        # Calculate vehicle age in months
        vehicle_age_months = 0
        if reg_date_str:
            try:
                parts = reg_date_str.split("/")
                reg_dt = datetime(int(parts[2]), int(parts[1]), int(parts[0]))
                vehicle_age_months = (datetime.now() - reg_dt).days // 30
            except Exception:
                pass

        # Build maintenance predictions
        predictions = []
        for service_name, intervals in MAINTENANCE_INTERVALS.items():
            interval_km     = intervals["interval_km"]
            interval_months = intervals["interval_months"]
            priority        = intervals["priority"]

            # Calculate based on mileage
            km_status      = "unknown"
            km_next        = None
            months_next    = None
            overdue        = False

            if current_km > 0:
                last_service_km = 0  # assume 0 if no record
                km_since_last   = current_km - last_service_km
                km_until_next   = interval_km - (km_since_last % interval_km)
                km_next         = current_km + km_until_next

                if km_since_last >= interval_km:
                    km_status = "OVERDUE"
                    overdue   = True
                elif km_until_next <= interval_km * 0.1:
                    km_status = "DUE_SOON"
                else:
                    km_status = "OK"

            # Calculate based on months
            if vehicle_age_months > 0:
                months_since_last = vehicle_age_months % interval_months
                months_until_next = interval_months - months_since_last
                months_next       = months_until_next

                if months_since_last >= interval_months:
                    overdue = True

            predictions.append({
                "service":         service_name,
                "priority":        priority,
                "interval_km":     interval_km,
                "interval_months": interval_months,
                "status":          "OVERDUE" if overdue else km_status,
                "km_until_next":   km_next,
                "months_until_next": months_next,
                "overdue":         overdue,
            })

        # Sort: overdue first, then by priority
        priority_order = {"HIGH": 0, "MEDIUM": 1, "LOW": 2}
        predictions.sort(key=lambda x: (
            0 if x["overdue"] else 1,
            priority_order.get(x["priority"], 2)
        ))

        # Get AI-enhanced analysis using service history
        ai_analysis = ""
        if bill_chunks:
            try:
                bill_context = "\n".join([c["text"] for c in bill_chunks[:5]])
                response = groq_client.chat.completions.create(
                    model="llama-3.3-70b-versatile",
                    messages=[
                        {"role": "system", "content": "You are a vehicle maintenance expert."},
                        {"role": "user", "content":
                         f"Vehicle: {model_name}\nCurrent mileage: {current_km} km\n"
                         f"Vehicle age: {vehicle_age_months} months\n\n"
                         f"Service history:\n{bill_context}\n\n"
                         "Based on this service history, what maintenance is most urgently needed? "
                         "Give 3-5 specific recommendations with reasoning. Be concise."},
                    ],
                    max_tokens=400, temperature=0.2,
                )
                ai_analysis = response.choices[0].message.content
            except Exception as e:
                print(f"[Maintenance] AI analysis failed: {e}")

        overdue_count   = sum(1 for p in predictions if p["overdue"])
        due_soon_count  = sum(1 for p in predictions if p["status"] == "DUE_SOON")

        return {
            "message":         "Maintenance analysis complete.",
            "vehicle_number":  vehicle_number,
            "model":           model_name,
            "current_mileage": current_km,
            "vehicle_age_months": vehicle_age_months,
            "overdue_count":   overdue_count,
            "due_soon_count":  due_soon_count,
            "predictions":     predictions,
            "ai_analysis":     ai_analysis,
            "last_service":    bills[-1]["uploaded_at"] if bills else None,
        }

    except Exception as e:
        print(f"ERROR /predictive-maintenance: {e}")
        return {"message": "Maintenance analysis failed", "error": str(e)}


# ─────────────────────────────────────────────
#  FEATURE 3: SMART DASHBOARD
# ─────────────────────────────────────────────
@app.get("/dashboard")
def get_dashboard(userId: str = "default"):
    """
    Returns aggregated data across all vehicles for the smart dashboard.
    Includes expiry alerts, maintenance summaries, document status.
    """
    try:
        vehicles = get_user_vehicles(userId)
        total_vehicles    = len(vehicles)
        total_documents   = 0
        expiry_alerts     = []
        maintenance_alerts = []
        document_summary  = {"RC": 0, "Insurance": 0, "PUC": 0}
        monthly_reminders = []

        for vehicle in vehicles:
            vnum  = vehicle["vehicle_number"]
            model = vehicle.get("model", vnum)
            docs  = vehicle.get("documents", [])

            for doc in docs:
                doc_type = doc.get("type", "")
                total_documents += 1

                if doc_type in document_summary:
                    document_summary[doc_type] += 1

                # Check expiry
                expiry_str = doc.get("expiry_date")
                if expiry_str and doc_type in ("Insurance", "PUC"):
                    status = compute_expiry_status(expiry_str)
                    days   = status.get("days_remaining")

                    if days is not None and days <= 30:
                        expiry_alerts.append({
                            "vehicle_number": vnum,
                            "model":          model,
                            "doc_type":       doc_type,
                            "expiry_date":    expiry_str,
                            "days_remaining": days,
                            "status":         status["status"],
                            "message":        status["message"],
                            "urgency":        "HIGH" if days <= 7 else "MEDIUM",
                        })

                    # Add to monthly calendar
                    if expiry_str and days is not None and 0 <= days <= 90:
                        monthly_reminders.append({
                            "date":     expiry_str,
                            "vehicle":  vnum,
                            "type":     doc_type,
                            "days":     days,
                        })

            # Maintenance alerts based on service bill count and age
            bills = vehicle.get("service_bills", [])
            reg_date_str = vehicle.get("registration_date", "")
            if reg_date_str:
                try:
                    parts = reg_date_str.split("/")
                    reg_dt = datetime(int(parts[2]), int(parts[1]), int(parts[0]))
                    age_months = (datetime.now() - reg_dt).days // 30
                    if age_months >= 6 and len(bills) == 0:
                        maintenance_alerts.append({
                            "vehicle_number": vnum,
                            "model":          model,
                            "message":        f"No service records uploaded. Vehicle is {age_months} months old.",
                            "priority":       "MEDIUM",
                        })
                except Exception:
                    pass

        # Sort expiry alerts by urgency
        expiry_alerts.sort(key=lambda x: x["days_remaining"])
        monthly_reminders.sort(key=lambda x: x["days"])

        # Document completion percentage per vehicle
        vehicle_health = []
        for vehicle in vehicles:
            docs  = vehicle.get("documents", [])
            types = {d["type"] for d in docs}
            score = (len(types & {"RC", "Insurance", "PUC"}) / 3) * 100

            # Reduce score for expired docs
            for doc in docs:
                if doc.get("expiry_date"):
                    status = compute_expiry_status(doc["expiry_date"])
                    if status["status"] == "expired":
                        score -= 20
                    elif status["status"] == "expiring_soon":
                        score -= 10

            score = max(0, min(100, score))
            damage_reports = vehicle.get("damage_reports", [])

            vehicle_health.append({
                "vehicle_number":   vehicle["vehicle_number"],
                "model":            vehicle.get("model", ""),
                "health_score":     round(score),
                "documents_count":  len(docs),
                "bills_count":      len(vehicle.get("service_bills", [])),
                "damage_count":     len(damage_reports),
                "image_url":        vehicle.get("image_url"),
            })

        return {
            "summary": {
                "total_vehicles":   total_vehicles,
                "total_documents":  total_documents,
                "expiry_alerts":    len(expiry_alerts),
                "maintenance_alerts": len(maintenance_alerts),
            },
            "document_summary":    document_summary,
            "expiry_alerts":       expiry_alerts[:10],
            "maintenance_alerts":  maintenance_alerts,
            "monthly_reminders":   monthly_reminders,
            "vehicle_health":      vehicle_health,
        }

    except Exception as e:
        print(f"ERROR /dashboard: {e}")
        return {"message": "Dashboard failed", "error": str(e)}


# ─────────────────────────────────────────────
#  FEATURE 4: INSURANCE CLAIM ASSISTANT
# ─────────────────────────────────────────────
@app.post("/insurance-claim")
def insurance_claim(data: InsuranceClaimRequest):
    """
    Guides users through the insurance claim process.
    Analyses accident images, checks document completeness,
    and generates a structured claim report.
    """
    try:
        vehicle_number = normalize_vehicle_number(data.vehicleNumber)
        target = _get_vehicle_context(vehicle_number)
        if not target:
            return {"message": "Vehicle not found."}

        model       = target.get("model", "Unknown Vehicle")
        docs        = target.get("documents", [])
        doc_types   = {d["type"] for d in docs}

        # ── Check document checklist ───────────────────────────────────
        checklist = [
            {
                "item":      "Vehicle RC",
                "available": "RC" in doc_types,
                "required":  True,
                "note":      "Required to verify vehicle ownership",
            },
            {
                "item":      "Insurance Policy",
                "available": "Insurance" in doc_types,
                "required":  True,
                "note":      "Required to file the claim",
            },
            {
                "item":      "Accident Photos",
                "available": len(data.imageUrls) > 0,
                "required":  True,
                "note":      f"{len(data.imageUrls)} photo(s) uploaded",
            },
            {
                "item":      "PUC Certificate",
                "available": "PUC" in doc_types,
                "required":  False,
                "note":      "May be required by some insurers",
            },
            {
                "item":      "Accident Description",
                "available": len(data.accidentDescription) > 10,
                "required":  True,
                "note":      "Detailed description of the incident",
            },
        ]

        checklist_complete = all(
            item["available"] for item in checklist if item["required"]
        )
        completed_count = sum(1 for item in checklist if item["available"])

        # ── Analyse accident images if provided ────────────────────────
        damage_summary = ""
        if data.imageUrls:
            try:
                img_b64, media_type = image_url_to_base64(data.imageUrls[0])
                response = groq_client.chat.completions.create(
                    model="meta-llama/llama-4-scout-17b-16e-instruct",
                    messages=[{
                        "role": "user",
                        "content": [
                            {"type": "text", "text":
                             "This is an accident damage photo for an insurance claim. "
                             "Describe the visible damage briefly and professionally "
                             "as it would appear in an insurance claim report. "
                             "Include: affected parts, estimated severity, and whether "
                             "the damage appears consistent with a traffic accident."},
                            {"type": "image_url",
                             "image_url": {"url": f"data:{media_type};base64,{img_b64}"}},
                        ],
                    }],
                    max_tokens=400, temperature=0.2,
                )
                damage_summary = response.choices[0].message.content
            except Exception as e:
                print(f"[Claim] Image analysis failed: {e}")
                damage_summary = "Image analysis unavailable. Please describe the damage manually."

        # ── Generate claim report ──────────────────────────────────────
        insurance_doc = next((d for d in docs if d["type"] == "Insurance"), None)
        insurance_expiry = insurance_doc.get("expiry_date") if insurance_doc else None

        claim_report = {
            "vehicle_number":      vehicle_number,
            "vehicle_model":       model,
            "owner":               target.get("owner", ""),
            "insurance_status":    "Active" if insurance_expiry and
                                   compute_expiry_status(insurance_expiry)["status"] == "valid"
                                   else "Expired/Unknown",
            "accident_description": data.accidentDescription,
            "damage_assessment":   damage_summary,
            "photos_submitted":    len(data.imageUrls),
            "documents_submitted": len(data.documentUrls or []),
            "claim_reference":     f"CLM-{vehicle_number[-4:]}-{datetime.now().strftime('%Y%m%d%H%M')}",
            "submitted_at":        datetime.now().strftime('%d/%m/%Y %H:%M'),
        }

        # ── Next steps guidance ────────────────────────────────────────
        next_steps = [
            {
                "step":        1,
                "title":       "File an FIR",
                "description": "Visit your nearest police station and file an FIR (First Information Report) within 24 hours of the accident.",
                "done":        False,
                "urgent":      True,
            },
            {
                "step":        2,
                "title":       "Notify Your Insurer",
                "description": "Call your insurance company's helpline immediately. Most require notification within 24-48 hours.",
                "done":        False,
                "urgent":      True,
            },
            {
                "step":        3,
                "title":       "Get Vehicle Inspected",
                "description": "Take your vehicle to an authorised garage for a damage assessment. The insurer will send a surveyor.",
                "done":        False,
                "urgent":      False,
            },
            {
                "step":        4,
                "title":       "Submit Documents",
                "description": "Submit: RC, Insurance Policy, FIR copy, driving licence, and repair estimates.",
                "done":        checklist_complete,
                "urgent":      False,
            },
            {
                "step":        5,
                "title":       "Claim Settlement",
                "description": "After surveyor approval, the insurer will process your claim. Cashless or reimbursement based on your policy.",
                "done":        False,
                "urgent":      False,
            },
        ]

        # Store claim on vehicle
        if "insurance_claims" not in target:
            target["insurance_claims"] = []
        target["insurance_claims"].append({
            "reference":   claim_report["claim_reference"],
            "submitted_at": claim_report["submitted_at"],
            "status":      "Submitted",
        })

        return {
            "message":            "Insurance claim report generated.",
            "checklist":          checklist,
            "checklist_complete": checklist_complete,
            "completed_items":    completed_count,
            "total_items":        len(checklist),
            "claim_report":       claim_report,
            "next_steps":         next_steps,
            "damage_summary":     damage_summary,
        }

    except Exception as e:
        print(f"ERROR /insurance-claim: {e}")
        import traceback; traceback.print_exc()
        return {"message": "Claim processing failed", "error": str(e)}

def _generate_claim_pdf(data: dict) -> str:
    """
    Generates a professional A4 insurance claim PDF.
    Returns path to the temporary PDF file.
    """
    tmp_dir  = tempfile.mkdtemp()
    pdf_path = _os.path.join(
        tmp_dir, f"claim_{data['claimReference']}.pdf")

    doc = SimpleDocTemplate(
        pdf_path, pagesize=A4,
        rightMargin=2*cm, leftMargin=2*cm,
        topMargin=2*cm,  bottomMargin=2*cm,
    )

    styles = getSampleStyleSheet()

    style_title = ParagraphStyle("T", parent=styles["Title"],
        fontSize=18, textColor=colors.HexColor("#1A1A2E"),
        spaceAfter=4, alignment=TA_CENTER, fontName="Helvetica-Bold")

    style_subtitle = ParagraphStyle("S", parent=styles["Normal"],
        fontSize=10, textColor=colors.HexColor("#555555"),
        spaceAfter=4, alignment=TA_CENTER)

    style_section = ParagraphStyle("H", parent=styles["Heading2"],
        fontSize=12, textColor=colors.HexColor("#1A1A2E"),
        spaceBefore=14, spaceAfter=5, fontName="Helvetica-Bold")

    style_body = ParagraphStyle("B", parent=styles["Normal"],
        fontSize=10, textColor=colors.HexColor("#333333"),
        spaceAfter=4, leading=15)

    style_ref = ParagraphStyle("R", parent=styles["Normal"],
        fontSize=13, textColor=colors.HexColor("#E8B84B"),
        fontName="Helvetica-Bold", alignment=TA_CENTER, spaceAfter=4)

    style_footer = ParagraphStyle("F", parent=styles["Normal"],
        fontSize=8, textColor=colors.HexColor("#999999"),
        alignment=TA_CENTER)

    style_disclaimer = ParagraphStyle("D", parent=styles["Normal"],
        fontSize=9, textColor=colors.HexColor("#888888"),
        spaceAfter=4, leading=13)

    story = []

    # ── Header ────────────────────────────────────────────────────────────────
    story.append(Paragraph(
        "MOTOR VEHICLE INSURANCE CLAIM REPORT", style_title))
    story.append(Paragraph(
        "Generated by AutoVault — Vehicle Management System", style_subtitle))
    story.append(Spacer(1, 0.1*inch))

    # Reference number box
    ref_table = Table(
        [[Paragraph(
            f"Claim Reference: {data['claimReference']}", style_ref)]],
        colWidths=[16*cm])
    ref_table.setStyle(TableStyle([
        ("BACKGROUND",    (0,0), (-1,-1), colors.HexColor("#1A1A2E")),
        ("ALIGN",         (0,0), (-1,-1), "CENTER"),
        ("TOPPADDING",    (0,0), (-1,-1), 10),
        ("BOTTOMPADDING", (0,0), (-1,-1), 10),
    ]))
    story.append(ref_table)
    story.append(Spacer(1, 0.15*inch))

    # ── Section 1: Vehicle Details ─────────────────────────────────────────────
    story.append(Paragraph("1. VEHICLE &amp; CLAIM DETAILS", style_section))
    story.append(HRFlowable(width="100%", thickness=1,
        color=colors.HexColor("#E8B84B"), spaceAfter=8))

    v_data = [
        ["Registration Number", data.get("vehicleNumber", "—")],
        ["Owner Name",          data.get("ownerName",      "—")],
        ["Insurance Status",    data.get("insuranceStatus","—")],
        ["Report Date & Time",  data.get("submittedAt",    "—")],
        ["Photos Submitted",    str(data.get("photosSubmitted", 0))],
    ]
    v_table = Table(v_data, colWidths=[6*cm, 10*cm])
    v_table.setStyle(TableStyle([
        ("BACKGROUND",    (0,0), (0,-1), colors.HexColor("#F5F5F5")),
        ("FONTNAME",      (0,0), (0,-1), "Helvetica-Bold"),
        ("FONTSIZE",      (0,0), (-1,-1), 10),
        ("ROWBACKGROUNDS",(0,0), (-1,-1),
            [colors.HexColor("#FAFAFA"), colors.white]),
        ("GRID",          (0,0), (-1,-1), 0.5, colors.HexColor("#DDDDDD")),
        ("TOPPADDING",    (0,0), (-1,-1), 7),
        ("BOTTOMPADDING", (0,0), (-1,-1), 7),
        ("LEFTPADDING",   (0,0), (-1,-1), 8),
        ("RIGHTPADDING",  (0,0), (-1,-1), 8),
        ("VALIGN",        (0,0), (-1,-1), "MIDDLE"),
    ]))
    story.append(v_table)

    # ── Section 2: Accident Description ────────────────────────────────────────
    story.append(Paragraph("2. ACCIDENT DESCRIPTION", style_section))
    story.append(HRFlowable(width="100%", thickness=1,
        color=colors.HexColor("#E8B84B"), spaceAfter=8))
    story.append(Paragraph(
        data.get("accidentDescription", "No description provided."),
        style_body))

    # ── Section 3: AI Damage Assessment ────────────────────────────────────────
    damage = data.get("damageSummary", "").strip()
    if damage:
        story.append(Paragraph(
            "3. AI DAMAGE ASSESSMENT", style_section))
        story.append(HRFlowable(width="100%", thickness=1,
            color=colors.HexColor("#E8B84B"), spaceAfter=8))
        story.append(Paragraph(
            "<i>AI vision analysis of submitted accident photographs:</i>",
            style_disclaimer))
        story.append(Spacer(1, 0.05*inch))
        dmg_box = Table(
            [[Paragraph(damage, style_body)]], colWidths=[16*cm])
        dmg_box.setStyle(TableStyle([
            ("BACKGROUND",    (0,0), (-1,-1), colors.HexColor("#FFF8E7")),
            ("BOX",           (0,0), (-1,-1), 1, colors.HexColor("#E8B84B")),
            ("TOPPADDING",    (0,0), (-1,-1), 10),
            ("BOTTOMPADDING", (0,0), (-1,-1), 10),
            ("LEFTPADDING",   (0,0), (-1,-1), 10),
            ("RIGHTPADDING",  (0,0), (-1,-1), 10),
        ]))
        story.append(dmg_box)

    # ── Section 4: Document Checklist ──────────────────────────────────────────
    checklist = data.get("checklist", [])
    sec_num = 4 if damage else 3
    if checklist:
        story.append(Paragraph(
            f"{sec_num}. DOCUMENT CHECKLIST", style_section))
        story.append(HRFlowable(width="100%", thickness=1,
            color=colors.HexColor("#E8B84B"), spaceAfter=8))

        tdata = [["Document", "Status", "Required", "Notes"]]
        for item in checklist:
            av  = item.get("available", False)
            req = item.get("required",  False)
            tdata.append([
                item.get("item", ""),
                "✓ Available" if av else "✗ Missing",
                "Yes" if req else "No",
                item.get("note", ""),
            ])

        ctable = Table(tdata,
            colWidths=[4.5*cm, 3.5*cm, 2.5*cm, 5.5*cm])
        cstyles = [
            ("BACKGROUND",  (0,0), (-1,0), colors.HexColor("#1A1A2E")),
            ("TEXTCOLOR",   (0,0), (-1,0), colors.white),
            ("FONTNAME",    (0,0), (-1,0), "Helvetica-Bold"),
            ("FONTSIZE",    (0,0), (-1,-1), 9),
            ("GRID",        (0,0), (-1,-1), 0.5, colors.HexColor("#DDDDDD")),
            ("TOPPADDING",  (0,0), (-1,-1), 6),
            ("BOTTOMPADDING",(0,0),(-1,-1), 6),
            ("LEFTPADDING", (0,0), (-1,-1), 8),
            ("RIGHTPADDING",(0,0), (-1,-1), 8),
            ("VALIGN",      (0,0), (-1,-1), "MIDDLE"),
        ]
        for i, item in enumerate(checklist, start=1):
            av  = item.get("available", False)
            req = item.get("required",  False)
            if av:
                bg = colors.HexColor("#F0FFF4")
                tc = colors.HexColor("#276749")
            elif req:
                bg = colors.HexColor("#FFF5F5")
                tc = colors.HexColor("#C53030")
            else:
                bg = colors.HexColor("#FFFFF0")
                tc = colors.HexColor("#744210")
            cstyles += [
                ("BACKGROUND", (0,i), (-1,i), bg),
                ("TEXTCOLOR",  (1,i), (1,i),  tc),
                ("FONTNAME",   (1,i), (1,i),  "Helvetica-Bold"),
            ]
        ctable.setStyle(TableStyle(cstyles))
        story.append(ctable)

    # ── Section 5: Next Steps ───────────────────────────────────────────────────
    next_num = sec_num + 1 if checklist else sec_num
    story.append(Paragraph(
        f"{next_num}. RECOMMENDED NEXT STEPS", style_section))
    story.append(HRFlowable(width="100%", thickness=1,
        color=colors.HexColor("#E8B84B"), spaceAfter=8))

    steps = [
        ("URGENT", "File an FIR",
         "Visit the nearest police station within 24 hours. Obtain FIR copy — mandatory for claim."),
        ("URGENT", "Notify Insurer",
         "Call your insurance helpline immediately. Provide the claim reference from this report."),
        ("ACTION", "Vehicle Inspection",
         "Take vehicle to authorised garage. Do NOT repair before insurer surveyor visit."),
        ("ACTION", "Submit Documents",
         "Submit: RC, Insurance Policy, FIR copy, Driving Licence, Repair Estimate, this report."),
        ("INFO",   "Claim Settlement",
         "After surveyor approval — cashless at network garage or reimbursement per your policy."),
    ]
    urgency_colors_map = {
        "URGENT": colors.HexColor("#C53030"),
        "ACTION": colors.HexColor("#744210"),
        "INFO":   colors.HexColor("#276749"),
    }
    urgency_bg_map = {
        "URGENT": colors.HexColor("#FFF5F5"),
        "ACTION": colors.HexColor("#FFFFF0"),
        "INFO":   colors.HexColor("#F0FFF4"),
    }
    sdata = [["Priority", "Step", "What To Do"]]
    for u, t, d in steps:
        sdata.append([u, t, d])
    stable = Table(sdata, colWidths=[2*cm, 4*cm, 10*cm])
    sstyles = [
        ("BACKGROUND",  (0,0), (-1,0), colors.HexColor("#1A1A2E")),
        ("TEXTCOLOR",   (0,0), (-1,0), colors.white),
        ("FONTNAME",    (0,0), (-1,0), "Helvetica-Bold"),
        ("FONTSIZE",    (0,0), (-1,-1), 9),
        ("GRID",        (0,0), (-1,-1), 0.5, colors.HexColor("#DDDDDD")),
        ("TOPPADDING",  (0,0), (-1,-1), 8),
        ("BOTTOMPADDING",(0,0),(-1,-1), 8),
        ("LEFTPADDING", (0,0), (-1,-1), 6),
        ("RIGHTPADDING",(0,0), (-1,-1), 6),
        ("VALIGN",      (0,0), (-1,-1), "TOP"),
    ]
    for i, (u, _, _) in enumerate(steps, start=1):
        sstyles += [
            ("BACKGROUND", (0,i), (-1,i), urgency_bg_map[u]),
            ("TEXTCOLOR",  (0,i), (0,i),  urgency_colors_map[u]),
            ("FONTNAME",   (0,i), (1,i),  "Helvetica-Bold"),
        ]
    stable.setStyle(TableStyle(sstyles))
    story.append(stable)

    # ── Disclaimer & Footer ────────────────────────────────────────────────────
    story.append(Spacer(1, 0.3*inch))
    story.append(HRFlowable(width="100%", thickness=0.5,
        color=colors.HexColor("#CCCCCC"), spaceAfter=8))
    story.append(Paragraph(
        "<b>DISCLAIMER:</b> This report was generated by AutoVault. "
        "The AI damage assessment is for reference only and does not replace "
        "a professional insurance surveyor's assessment. Final claim settlement "
        "is subject to your policy terms and the insurer's decision.",
        style_disclaimer))
    story.append(Spacer(1, 0.1*inch))
    story.append(Paragraph(
        f"AutoVault  |  {data.get('submittedAt', '')}  |  {data.get('claimReference', '')}",
        style_footer))

    doc.build(story)
    return pdf_path

# ─────────────────────────────────────────────
#  Existing Routes
# ─────────────────────────────────────────────
@app.get("/")
def root():
    return {"message": "Backend running"}


@app.post("/process")
def process(data: RCUploadRequest):
    try:
        user_id = data.userId or "default"
        print("USER ID =", data.userId)

        user_id = data.userId or "default"

        vehicles = get_user_vehicles(user_id)
        vehicles = get_user_vehicles(user_id)
        kb = get_user_knowledge(user_id)

        text     = run_ocr(data.imageUrl)
        doc_type = detect_doc_type(text)
        if doc_type != "RC":
            return {"message": f"This looks like a {doc_type}. Please upload an RC.",
                    "document_type": doc_type, "vehicle_saved": False}
        rc_data        = extract_rc_fields(text)
        vehicle_number = rc_data.get("vehicle_number", "") or extract_vehicle_number_from_text(text)
        if not vehicle_number:
            return {"message": "Could not read vehicle number.", "vehicle_saved": False}
        vehicle_number = normalize_vehicle_number(vehicle_number)
        for v in vehicles:
            if normalize_vehicle_number(v["vehicle_number"]) == vehicle_number:
                return {"message": "Vehicle already exists.", "vehicle_number": vehicle_number,
                        "vehicle_saved": False}
        api_data = {}
        if not rc_data.get("owner") or not rc_data.get("model"):
            api_data = fetch_vehicle_details_from_api(vehicle_number) or {}
        merged = {k: rc_data.get(k) or api_data.get(k, "")
                  for k in ["owner","model","maker","fuel_type","color","registration_date",
                             "vehicle_class","fitness_upto","insurance_upto","pucc_upto",
                             "chassis_number","engine_number","engine_cc","mfg_date","state"]}
        vehicle = _build_vehicle_dict(vehicle_number, merged, rc_url=data.imageUrl)
        vehicles.append(vehicle)
        model_name = merged.get("model", "")

        if model_name:
            load_manual_for_vehicle(vehicle_number,model_name,user_id,rc_data=merged,)
        return {"message": "Vehicle created successfully.", "vehicle_number": vehicle_number,
                "document_type": "RC", "vehicle_saved": True, "details": merged}
    except Exception as e:
        print(f"ERROR /process: {e}")
        return {"message": "Processing failed", "error": str(e), "vehicle_saved": False}


@app.post("/add-vehicle-manual")
def add_vehicle_manual(data: ManualVehicleRequest):
    vehicle_number = normalize_vehicle_number(data.vehicle_number)
    user_id = data.userId or "default"

    vehicles = get_user_vehicles(user_id)
    kb = get_user_knowledge(user_id)
    for v in vehicles:
        if normalize_vehicle_number(v["vehicle_number"]) == vehicle_number:
            return {"message": "Vehicle already exists.", "vehicle_number": vehicle_number}
    details = fetch_vehicle_details_from_api(vehicle_number)
    if not details:
        return {"message": "Could not fetch vehicle details."}
    vehicle = _build_vehicle_dict(vehicle_number, details)
    vehicles.append(vehicle)
    if details.get("model"):
        load_manual_for_vehicle(vehicle_number, details["model"],user_id,)
    return {"message": "Vehicle created", "vehicle": vehicle}


@app.post("/add-document")
def add_document(data: DocumentUploadRequest):
    try:
        vehicle_number = normalize_vehicle_number(data.vehicleNumber)
        user_id = data.userId or "default"

        vehicles = get_user_vehicles(user_id)
        doc_type       = data.docType
        target = next((v for v in vehicles
                       if normalize_vehicle_number(v["vehicle_number"]) == vehicle_number), None)
        if not target:
            return {"message": f"Vehicle {vehicle_number} not found."}
        if any(d["type"] == doc_type for d in target["documents"]):
            return {"message": f"{doc_type} already uploaded."}
        combined_text = run_ocr_multiple(data.imageUrls)
        expiry_date   = extract_expiry_date(combined_text)
        target["documents"].append({
            "type": doc_type, "url": data.imageUrls[0],
            "urls": data.imageUrls, "page_count": len(data.imageUrls),
            "expiry_date": expiry_date,
            "uploaded_at": datetime.now().strftime('%d/%m/%Y'),
        })
        expiry_status = compute_expiry_status(expiry_date)
        return {
            "message": f"{doc_type} added ({len(data.imageUrls)} page(s)).",
            "vehicle_number": vehicle_number, "document_type": doc_type,
            "expiry_date": expiry_date, "days_remaining": expiry_status["days_remaining"],
            "expiry_status": expiry_status["status"],
        }
    except Exception as e:
        return {"message": "Error processing document", "error": str(e)}


@app.delete("/vehicle/{vehicle_number}")
def delete_vehicle(
    vehicle_number: str,
    userId: str = "default"
):
    vehicle_number = normalize_vehicle_number(vehicle_number)
    vehicles = get_user_vehicles(userId)
    kb = get_user_knowledge(userId)
    chat = get_user_chat(userId)
    idx = next((i for i, v in enumerate(vehicles)
                if normalize_vehicle_number(v["vehicle_number"]) == vehicle_number), None)
    if idx is None:
        return {"message": "Vehicle not found.", "deleted": False}
    deleted = vehicles.pop(idx)
    kb.pop(vehicle_number, None)
    chat.pop(vehicle_number, None)
    return {"message": f"Vehicle {vehicle_number} deleted.", "deleted": True,
            "docs_deleted": len(deleted.get("documents", [])),
            "bills_deleted": len(deleted.get("service_bills", []))}


@app.post("/upload-service-bill")
def upload_service_bill(data: ServiceBillRequest):
    try:
        vehicle_number = normalize_vehicle_number(data.vehicleNumber)
        user_id = data.userId or "default"

        vehicles = get_user_vehicles(user_id)
        kb = get_user_knowledge(user_id)
        target = next((v for v in vehicles
                       if normalize_vehicle_number(v["vehicle_number"]) == vehicle_number), None)
        if not target:
            return {"message": f"Vehicle {vehicle_number} not found."}
        ocr_text    = run_ocr(data.imageUrl)
        bill_text   = extract_service_bill_text(ocr_text)
        explanation = generate_bill_explanation(ocr_text, target.get("model", ""))
        bill_chunks = chunk_text(bill_text,
                                 source_label=f"Service Bill ({datetime.now().strftime('%d/%m/%Y')})")
        if vehicle_number not in kb:
            kb[vehicle_number] = {"manual": [], "bills": []}
        kb[vehicle_number]["bills"].extend(bill_chunks)
        if "service_bills" not in target:
            target["service_bills"] = []
        target["service_bills"].append({
            "url": data.imageUrl, "uploaded_at": datetime.now().strftime('%d/%m/%Y'),
            "preview": bill_text[:200], "explanation": explanation,
        })
        return {"message": "Service bill uploaded.", "vehicle_number": vehicle_number,
                "explanation": explanation}
    except Exception as e:
        return {"message": "Error processing service bill", "error": str(e)}

@app.delete("/service-bill")
def delete_service_bill(
    vehicleNumber: str,
    billIndex: int,
    userId: str = "default"
):
    try:
        print("========== DELETE SERVICE BILL ==========")
        print("Vehicle =", vehicleNumber)
        print("Bill Index =", billIndex)
        print("User =", userId)

        vehicle_number = normalize_vehicle_number(vehicleNumber)

        vehicles = get_user_vehicles(userId)

        target = next(
            (
                v for v in vehicles
                if normalize_vehicle_number(v["vehicle_number"]) == vehicle_number
            ),
            None,
        )

        if not target:
            return {
                "message": "Vehicle not found."
            }

        bills = target.get("service_bills", [])

        if billIndex < 0 or billIndex >= len(bills):
            return {
                "message": "Bill not found."
            }

        deleted_bill = bills.pop(billIndex)

        # Delete file from Firebase Storage
        file_url = deleted_bill.get("url")

        try:
            if file_url:
                bucket = storage.bucket()

                import urllib.parse

                path = file_url.split("/o/")[1].split("?")[0]
                path = urllib.parse.unquote(path)

                blob = bucket.blob(path)

                if blob.exists():
                    blob.delete()
                    print("Firebase file deleted:", path)

        except Exception as e:
            print("Firebase delete failed:", e)

        return {
            "message": "Service bill deleted successfully.",
            "deleted_bill": deleted_bill,
        }

    except Exception as e:
        return {
            "message": "Failed to delete service bill.",
            "error": str(e),
        }

@app.post("/upload-manual")
def upload_manual(data: ManualUploadRequest):
    try:
        vehicle_number = normalize_vehicle_number(data.vehicleNumber)
        user_id = data.userId or "default"

        vehicles = get_user_vehicles(user_id)
        kb = get_user_knowledge(user_id)
        target = next((v for v in vehicles
                       if normalize_vehicle_number(v["vehicle_number"]) == vehicle_number), None)
        if not target:
            return {"message": "Vehicle not found."}
        response = requests.get(data.imageUrl, timeout=30)
        pdf      = fitz.open(stream=response.content, filetype="pdf")
        text     = "".join(page.get_text() for page in pdf)
        if len(text) < 200:
            return {"message": "PDF appears image-based. Text could not be extracted."}
        model_name = target.get("model", vehicle_number)
        chunks     = chunk_text(text, source_label=f"Owner Manual — {model_name} (User Uploaded)")
        if vehicle_number not in kb:
            kb[vehicle_number] = {"manual": [], "bills": []}
        kb[vehicle_number]["manual"] = chunks
        return {"message": f"Manual uploaded. {len(chunks)} sections indexed.",
                "pages": pdf.page_count, "chunks": len(chunks)}
    except Exception as e:
        return {"message": "Error processing manual", "error": str(e)}


@app.post("/chat")
def chat(data: ChatRequest):
    try:
        user_id = data.userId or "default"

        kb_store = get_user_knowledge(user_id)
        chat_store = get_user_chat(user_id)
        lookup_number  = normalize_vehicle_number(data.targetVehicleNumber or data.vehicleNumber)
        primary_number = normalize_vehicle_number(data.vehicleNumber)
        vehicle = _get_vehicle_context(lookup_number) or _get_vehicle_context(primary_number)
        if not vehicle:
            return {"answer": "I could not find the vehicle."}
        vn         = normalize_vehicle_number(vehicle["vehicle_number"])
        model_name = vehicle.get("model", "")
        kb         = kb_store.get(vn, {"manual": [], "bills": []})
        if model_name and not kb.get("manual"):
            load_manual_for_vehicle(vn,model_name,user_id,)
            kb = kb_store.get(vn, {"manual": [], "bills": []})
        context_block = _build_context_block(vehicle, data.question, kb)
        system_prompt = build_system_prompt(vehicle, context_block)
        history       = chat_store.get(primary_number, [])[-10:]
        messages      = history + [{"role": "user", "content": data.question}]
        groq_messages = [{"role": "system", "content": system_prompt}]
        for msg in messages[:-1]:
            groq_messages.append({"role": msg["role"], "content": msg["content"]})
        groq_messages.append({"role": "user", "content": data.question})
        resp = groq_client.chat.completions.create(
            model="llama-3.3-70b-versatile", messages=groq_messages,
            max_tokens=1024, temperature=0.3)
        answer = resp.choices[0].message.content
        if primary_number not in chat_store:
            chat_store[primary_number] = []
        chat_store[primary_number].append({"role": "user",      "content": data.question})
        chat_store[primary_number].append({"role": "assistant", "content": answer})
        return {"answer": answer, "vehicle_number": vn,
                "manual_loaded": len(kb.get("manual", [])) > 0,
                "manual_chunks": len(kb.get("manual", []))}
    except Exception as e:
        print(f"[Chat] ERROR: {e}")
        return {"answer": "AI service is temporarily unavailable.", "error": str(e)}


@app.delete("/chat/history/{vehicle_number}")
def clear_chat_history(
    vehicle_number: str,
    userId: str = "default"
):
    vn = normalize_vehicle_number(vehicle_number)
    chat = get_user_chat(userId)
    chat.pop(vn, None)
    return {"message": f"Chat history cleared for {vn}"}


@app.get("/vehicles")
def get_vehicles(userId: str = "default"):
    return get_user_vehicles(userId)


@app.get("/vehicle/{vehicle_number}")
def get_vehicle(
    vehicle_number: str,
    userId: str = "default"
):
    vehicle_number = normalize_vehicle_number(vehicle_number)
    vehicles = get_user_vehicles(userId)
    for v in vehicles:
        if normalize_vehicle_number(v["vehicle_number"]) == vehicle_number:
            return v
    return {"message": "Vehicle not found."}


@app.get("/expiry-status")
def expiry_status_all(userId: str = "default"):
    result = []
    vehicles = get_user_vehicles(userId)
    for vehicle in vehicles:
        vnum = vehicle["vehicle_number"]
        for doc in vehicle.get("documents", []):
            if doc["type"] in ("Insurance", "PUC"):
                status = compute_expiry_status(doc.get("expiry_date"))
                result.append({
                    "vehicle_number": vnum, "doc_type": doc["type"],
                    "expiry_date": doc.get("expiry_date"),
                    "days_remaining": status["days_remaining"],
                    "status": status["status"], "message": status["message"],
                })
    return result


@app.get("/debug/manual/{vehicle_number}")
def debug_manual(
    vehicle_number: str,
    userId: str = "default"
):
    vn = normalize_vehicle_number(vehicle_number)
    kb_store = get_user_knowledge(userId)
    kb = kb_store.get(vn, {})
    return {
        "manual_chunks":   len(kb.get("manual", [])),
        "bill_chunks":     len(kb.get("bills", [])),
        "manual_loaded":   len(kb.get("manual", [])) > 0,
        "manual_sections": list({c["source"] for c in kb.get("manual", [])}),
    }

@app.post("/insurance-claim/download-report")
def download_claim_report(data: ClaimReportRequest):
    """
    Generates and returns a downloadable PDF insurance claim report.
    Call this AFTER /insurance-claim to get the PDF version.
    """
    try:
        user_id = data.userId or "default"
        target = _get_vehicle_context(
            normalize_vehicle_number(
                data.vehicleNumber
            ),
            user_id,
        )

        # Build data dict for PDF
        pdf_data = {
            "vehicleNumber":       data.vehicleNumber,
            "ownerName":           target.get("owner", "") if target else "",
            "insuranceStatus":     data.insuranceStatus or "Unknown",
            "accidentDescription": data.accidentDescription,
            "damageSummary":       data.damageSummary or "",
            "checklist":           data.checklist or [],
            "photosSubmitted":     data.photosSubmitted or 0,
            "claimReference":      data.claimReference,
            "submittedAt":         data.submittedAt or
                                   datetime.now().strftime('%d/%m/%Y %H:%M'),
        }

        print(f"[PDF] Generating claim report for {data.vehicleNumber}...")
        pdf_path = _generate_claim_pdf(pdf_data)
        print(f"[PDF] Generated at: {pdf_path}")

        filename = f"InsuranceClaim_{data.vehicleNumber}_{data.claimReference}.pdf"

        return FileResponse(
            path=pdf_path,
            filename=filename,
            media_type="application/pdf",
            headers={
                "Content-Disposition": f'attachment; filename="{filename}"'
            },
        )

    except Exception as e:
        print(f"ERROR /insurance-claim/download-report: {e}")
        import traceback; traceback.print_exc()
        return {"message": "PDF generation failed", "error": str(e)}