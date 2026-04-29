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
import hashlib
import base64
import os
# ─────────────────────────────────────────────
#  CONFIG
# ─────────────────────────────────────────────
SUREPASS_TOKEN      = "YOUR_SUREPASS_TOKEN_HERE"
GROQ_KEY            = ""
UNSPLASH_ACCESS_KEY = "YOUR_UNSPLASH_KEY_HERE"
GOOGLE_API_KEY      = "YOUR_GOOGLE_API_KEY_HERE"
GOOGLE_CX           = "YOUR_GOOGLE_CX_HERE"

CHUNK_SIZE    = 800
CHUNK_OVERLAP = 100
TOP_K_CHUNKS  = 6

# ─────────────────────────────────────────────
#  In-memory DB
# ─────────────────────────────────────────────
vehicles_db    = []
knowledge_base: dict[str, dict] = {}
chat_history:   dict[str, list] = {}

app = FastAPI()
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

pytesseract.pytesseract.tesseract_cmd = r"C:\Program Files\Tesseract-OCR\tesseract.exe"
groq_client = Groq(api_key=GROQ_KEY)


# ─────────────────────────────────────────────
#  Request Models
# ─────────────────────────────────────────────
class RCUploadRequest(BaseModel):
    imageUrl: str

class DocumentUploadRequest(BaseModel):
    imageUrls: list[str]
    vehicleNumber: str
    docType: str

class ManualVehicleRequest(BaseModel):
    vehicle_number: str

class ServiceBillRequest(BaseModel):
    imageUrl: str
    vehicleNumber: str

class ManualUploadRequest(BaseModel):
    imageUrl: str
    vehicleNumber: str

class ChatRequest(BaseModel):
    vehicleNumber: str
    question: str
    targetVehicleNumber: Optional[str] = None

class DamageDetectionRequest(BaseModel):
    imageUrl: str
    vehicleNumber: str

class MaintenanceRequest(BaseModel):
    vehicleNumber: str
    currentMileage: Optional[int] = None

class InsuranceClaimRequest(BaseModel):
    vehicleNumber: str
    accidentDescription: str
    imageUrls: list[str]
    documentUrls: Optional[list[str]] = []


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


# ─────────────────────────────────────────────
#  RC Field Extraction
# ─────────────────────────────────────────────
def extract_rc_fields(ocr_text: str) -> dict:
    text  = ocr_text.upper()
    lines = text.split('\n')

    def clean_value(raw: str) -> str:
        if not raw:
            return ""
        stop_patterns = [
            r'\bO\.?\s*SL\.?\s*NO\b', r'\bMFR\b', r'\bMAKER\b',
            r'\bCLASS\b', r'\bCOLOU?R\b', r'\bCC\b', r'\bCYL\b',
            r'\bBODY\b', r'\bSEAT\b', r'\bUNLADEN\b', r'\bWHEEL\b',
            r'\bSTDG\b', r'\bTAX\b', r'\bFORM\b', r'\bS/W/D\b',
            r'\bADDRESS\b', r'\s{3,}',
        ]
        earliest = len(raw)
        for pat in stop_patterns:
            m = re.search(pat, raw)
            if m and m.start() < earliest:
                earliest = m.start()
        result = raw[:earliest].strip()
        result = re.sub(r'[~\*\#\$\|\^]+', '', result).strip()
        return result.strip('.,;:/-').strip()

    def find_field(*patterns) -> str:
        for pattern in patterns:
            m = re.search(pattern + r'\s*[:\-\.=~]+\s*([^\n]+)', text, re.IGNORECASE)
            if m:
                val = clean_value(m.group(1).strip())
                if val and len(val) > 1:
                    return val
        return ""

    vehicle_number = ""
    for pat in [
        r'REG\s*(?:NO|NUMBER|NUM|\.NO)\s*[:\-\.]\s*([A-Z]{2}[\s\-]?\d{2}[\s\-]?[A-Z]{1,3}[\s\-]?\d{3,4})',
    ]:
        m = re.search(pat, text, re.IGNORECASE)
        if m:
            vehicle_number = re.sub(r'[\s\-]', '', m.group(1)).upper()
            break
    if not vehicle_number:
        for line in lines:
            m = re.search(r'\b([A-Z]{2}\d{2}[A-Z]{1,3}\d{3,4})\b', line)
            if m:
                vehicle_number = m.group(1)
                break

    owner = ""

    for line in lines:
        l = line.strip().upper()

        if "OWNERNAME" in l or "OWNER NAME" in l:
            parts = re.split(r'[:\-]', l, maxsplit=1)

            if len(parts) > 1:
                owner = parts[1].strip()
                break

    # Clean unwanted parts
    if owner:
        owner = re.split(r'S/?W/?D|SON|WIFE|DAUGHTER', owner)[0].strip()
        owner = re.sub(r'[^A-Z\s]', '', owner).strip()

    model = find_field(r'MODEL', r'VEH\s*MODEL')
    model = re.sub(r'[()]', '', model).strip()

    maker = ""
    mfr_m = re.search(r'\bMFR\s*[:\-\.]\s*([A-Z]+)', text)
    if mfr_m:
        maker = mfr_m.group(1).strip()
    if not maker:
        maker = find_field(r'MAKER', r'MANUFACTURER')

    fuel = find_field(r'FUEL\s*TYPE', r'\bFUEL\b')
    if fuel:
        fuel = fuel.split()[0]

    color = ""
    col_m = re.search(r'COLOU?R\s*[:\-\.]\s*([A-Z]+(?:\s+[A-Z]+)?)', text)
    if col_m:
        color = clean_value(col_m.group(1))
    if not color:
        color = find_field(r'COLOU?R', r'COLOR')

    vehicle_class = ""
    cls_m = re.search(r'\bCLASS\s*[:\-\.]\s*([A-Z/\-]+(?:\s+[A-Z/\-]+)?)', text)
    if cls_m:
        vehicle_class = clean_value(cls_m.group(1))
    class_map = {"MCYCLE": "Motorcycle", "M-CYCLE": "Motorcycle",
                 "M/CYCLE": "Motorcycle", "SCOOTER": "Scooter"}
    vehicle_class = class_map.get(vehicle_class.upper().strip(), vehicle_class)

    reg_date = ""
    rd_m = re.search(r'REG\.?\s*DATE\s*[:\-\.]\s*(\d{2}/\d{2}/\d{4})', text)
    if rd_m:
        reg_date = rd_m.group(1)

    fitness_upto = ""
    fu_m = re.search(r'REG/?FC\s*UPTO\s*[:\-\.]\s*(\d{2}/\d{2}/\d{4})', text)
    if fu_m:
        fitness_upto = fu_m.group(1)

    engine_cc = ""
    cc_m = re.search(r'\bCC\s*[:\-\.]\s*(\d+)', text)
    if cc_m:
        engine_cc = f"{cc_m.group(1)}cc"

    chassis = ""
    ch_m = re.search(r'CHASSIS\.?\s*NO\s*[:\-\.]\s*([A-Z0-9]+)', text)
    if ch_m:
        chassis = ch_m.group(1).strip()

   # ── Engine Number Extraction (Final Fix) ──────────────────────
    engine_no = ""

    normalized_text = text.replace("O", "0").replace("I", "1")
    lines = normalized_text.split("\n")

    for line in lines:
        l = line.strip().upper()

        if "ENGINE" in l or "ENG" in l:
            print("ENGINE LINE FOUND:", l)

            candidates = re.findall(r'[A-Z0-9]{6,}', l)

            for c in candidates:
                # Skip obvious wrong matches
                if c in ["ENG1NE", "ENGINE", "MCYCLE", "CLASS"]:
                    continue

                # Must contain BOTH letters and numbers (real engine numbers do)
                if re.search(r'[A-Z]', c) and re.search(r'\d', c):
                    engine_no = c
                    break

            if engine_no:
                break

    print("ENGINE NUMBER:", engine_no)

    mfg_date = find_field(r'MFG\.?\s*DATE', r'MANUFACTURING\s*DATE')
    print("ENGINE LINE FOUND:", line)
    print("ENGINE NUMBER:", engine_no)
    # ── State from Vehicle Number (All India) ─────────────────────
    state_map = {
        "AN": "Andaman and Nicobar Islands",
        "AP": "Andhra Pradesh",
        "AR": "Arunachal Pradesh",
        "AS": "Assam",
        "BR": "Bihar",
        "CG": "Chhattisgarh",
        "CH": "Chandigarh",
        "DD": "Daman and Diu",
        "DL": "Delhi",
        "DN": "Dadra and Nagar Haveli",
        "GA": "Goa",
        "GJ": "Gujarat",
        "HP": "Himachal Pradesh",
        "HR": "Haryana",
        "JH": "Jharkhand",
        "JK": "Jammu and Kashmir",
        "KA": "Karnataka",
        "KL": "Kerala",
        "LA": "Ladakh",
        "LD": "Lakshadweep",
        "MH": "Maharashtra",
        "ML": "Meghalaya",
        "MN": "Manipur",
        "MP": "Madhya Pradesh",
        "MZ": "Mizoram",
        "NL": "Nagaland",
        "OD": "Odisha",
        "PB": "Punjab",
        "PY": "Puducherry",
        "RJ": "Rajasthan",
        "SK": "Sikkim",
        "TN": "Tamil Nadu",
        "TR": "Tripura",
        "TS": "Telangana",
        "UK": "Uttarakhand",
        "UP": "Uttar Pradesh",
        "WB": "West Bengal"
    }

    state = ""

    if vehicle_number and len(vehicle_number) >= 2:
        state_code = vehicle_number[:2]
        state = state_map.get(state_code, "")
    return {
        "vehicle_number":    vehicle_number,
        "owner":             owner.title() if owner else "",
        "model":             model.title() if model else "",
        "maker":             maker.title() if maker else "",
        "fuel_type":         fuel.title() if fuel else "",
        "color":             color.title() if color else "",
        "vehicle_class":     vehicle_class,
        "registration_date": reg_date,
        "fitness_upto":      fitness_upto,
        "engine_cc":         engine_cc,
        "chassis_number":    chassis,
        "engine_number":     engine_no,
        "mfg_date":          mfg_date,
        "insurance_upto":    "",
        "pucc_upto":         "",
        "state":             state,
    }


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
WIKIMEDIA_VEHICLE_IMAGES = {
    "activa 6g":      "https://upload.wikimedia.org/wikipedia/commons/thumb/4/4e/Honda_Activa_6G.jpg/800px-Honda_Activa_6G.jpg",
    "activa":         "https://upload.wikimedia.org/wikipedia/commons/thumb/4/4e/Honda_Activa_6G.jpg/800px-Honda_Activa_6G.jpg",
    "dio":            "https://upload.wikimedia.org/wikipedia/commons/thumb/c/c5/Honda_Dio_2021.jpg/800px-Honda_Dio_2021.jpg",
    "cb shine":       "https://upload.wikimedia.org/wikipedia/commons/thumb/b/b8/Honda_CB_Shine.jpg/800px-Honda_CB_Shine.jpg",
    "himalayan":      "https://upload.wikimedia.org/wikipedia/commons/thumb/f/f1/Royal_Enfield_Himalayan_%282021%29.jpg/800px-Royal_Enfield_Himalayan_%282021%29.jpg",
    "classic 350":    "https://upload.wikimedia.org/wikipedia/commons/thumb/9/9f/Royal_Enfield_Classic_350_%282021%29.jpg/800px-Royal_Enfield_Classic_350_%282021%29.jpg",
    "pulsar 150":     "https://upload.wikimedia.org/wikipedia/commons/thumb/6/6d/Bajaj_Pulsar_150.jpg/800px-Bajaj_Pulsar_150.jpg",
    "pulsar ns200":   "https://upload.wikimedia.org/wikipedia/commons/thumb/0/0b/Bajaj_Pulsar_NS200.jpg/800px-Bajaj_Pulsar_NS200.jpg",
    "duke 390":       "https://upload.wikimedia.org/wikipedia/commons/thumb/d/d6/KTM_390_Duke_2023.jpg/800px-KTM_390_Duke_2023.jpg",
    "duke 200":       "https://upload.wikimedia.org/wikipedia/commons/thumb/8/82/KTM_Duke_200.jpg/800px-KTM_Duke_200.jpg",
    "r15":            "https://upload.wikimedia.org/wikipedia/commons/thumb/3/3b/Yamaha_YZF-R15_V4.jpg/800px-Yamaha_YZF-R15_V4.jpg",
    "fz":             "https://upload.wikimedia.org/wikipedia/commons/thumb/8/8e/Yamaha_FZ-S_V3.jpg/800px-Yamaha_FZ-S_V3.jpg",
    "apache rtr 160": "https://upload.wikimedia.org/wikipedia/commons/thumb/2/2a/TVS_Apache_RTR_160_4V.jpg/800px-TVS_Apache_RTR_160_4V.jpg",
    "jupiter":        "https://upload.wikimedia.org/wikipedia/commons/thumb/5/5b/TVS_Jupiter.jpg/800px-TVS_Jupiter.jpg",
    "splendor":       "https://upload.wikimedia.org/wikipedia/commons/thumb/e/e3/Hero_Splendor_Plus_Black.jpg/800px-Hero_Splendor_Plus_Black.jpg",
    "glamour":        "https://upload.wikimedia.org/wikipedia/commons/thumb/1/1c/Hero_Glamour.jpg/800px-Hero_Glamour.jpg",
    "gixxer":         "https://upload.wikimedia.org/wikipedia/commons/thumb/1/1e/Suzuki_Gixxer_SF_250.jpg/800px-Suzuki_Gixxer_SF_250.jpg",
}


def fetch_vehicle_image(maker: str, model: str) -> Optional[str]:
    full    = f"{maker} {model}".lower()
    maker_l = maker.lower()
    if full.startswith(f"{maker_l} {maker_l}"):
        full = full[len(maker_l):].strip()
    for keyword, url in WIKIMEDIA_VEHICLE_IMAGES.items():
        if keyword in full:
            return url
    return None


# ─────────────────────────────────────────────
#  Manual Loading
# ─────────────────────────────────────────────
def load_manual_for_vehicle(vehicle_number: str, model_name: str,
                             rc_data: dict = None) -> bool:
    if vehicle_number not in knowledge_base:
        knowledge_base[vehicle_number] = {"manual": [], "bills": []}
    if knowledge_base[vehicle_number]["manual"]:
        return True

    rc_context = ""
    if rc_data:
        parts = []
        if rc_data.get("engine_cc"):  parts.append(f"engine: {rc_data['engine_cc']}")
        if rc_data.get("fuel_type"):  parts.append(f"fuel: {rc_data['fuel_type']}")
        if parts:
            rc_context = f"\nKnown specs: {', '.join(parts)}."

    sections = [
        ("Engine & Technical Specifications",
         f"Provide complete technical specifications for {model_name}.{rc_context} Include engine type, displacement, max power, max torque, starting system, ignition, carburetor/FI."),
        ("Maintenance Schedule",
         f"Complete maintenance schedule for {model_name} with exact km intervals: engine oil, oil filter, air filter, spark plug, valve clearance, chain, brakes, tyres."),
        ("Engine Oil & Fluids",
         f"For {model_name}: recommended oil grade, oil capacity, brake fluid type, fuel tank capacity, recommended octane."),
        ("Tyre & Brakes",
         f"For {model_name}: front/rear tyre sizes, tyre pressures in PSI (solo and pillion), brake types and sizes."),
        ("Electrical System",
         f"For {model_name}: battery spec, headlight wattage, main fuse rating, charging voltage."),
        ("Common Problems & Troubleshooting",
         f"Common issues for {model_name}: hard starting, rough idle, poor mileage, chain noise, brake issues, electrical faults with diagnosis and fix."),
        ("Safety & Riding Guidelines",
         f"Safety guidelines for {model_name}: break-in procedure, max load, pre-ride checklist, storage guidelines."),
    ]

    all_chunks = []
    for section_title, prompt in sections:
        try:
            response = groq_client.chat.completions.create(
                model="llama-3.3-70b-versatile",
                messages=[
                    {"role": "system", "content": "You are a certified motorcycle mechanic. Provide accurate, specific technical information."},
                    {"role": "user", "content": prompt},
                ],
                max_tokens=700, temperature=0.1,
            )
            content      = response.choices[0].message.content
            section_text = f"=== {section_title} ===\n{content}"
            chunks       = chunk_text(section_text, source_label=f"Owner Manual — {section_title}")
            all_chunks.extend(chunks)
        except Exception as e:
            print(f"[Manual] ✗ {section_title}: {e}")

    if all_chunks:
        knowledge_base[vehicle_number]["manual"] = all_chunks
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
def _get_vehicle_context(vehicle_number: str) -> Optional[dict]:
    vn = normalize_vehicle_number(vehicle_number)
    return next((v for v in vehicles_db if normalize_vehicle_number(v["vehicle_number"]) == vn), None)


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
    kb     = knowledge_base.get(normalize_vehicle_number(number), {})
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
        target = _get_vehicle_context(vehicle_number)
        if not target:
            return {"message": "Vehicle not found."}

        model_name    = target.get("model", "Unknown Vehicle")
        reg_date_str  = target.get("registration_date", "")
        current_km    = data.currentMileage or 0
        bills         = target.get("service_bills", [])
        kb            = knowledge_base.get(vehicle_number, {})
        bill_chunks   = kb.get("bills", [])

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
def get_dashboard():
    """
    Returns aggregated data across all vehicles for the smart dashboard.
    Includes expiry alerts, maintenance summaries, document status.
    """
    try:
        total_vehicles    = len(vehicles_db)
        total_documents   = 0
        expiry_alerts     = []
        maintenance_alerts = []
        document_summary  = {"RC": 0, "Insurance": 0, "PUC": 0}
        monthly_reminders = []

        for vehicle in vehicles_db:
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
        for vehicle in vehicles_db:
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


# ─────────────────────────────────────────────
#  Existing Routes
# ─────────────────────────────────────────────
@app.get("/")
def root():
    return {"message": "Backend running"}


@app.post("/process")
def process(data: RCUploadRequest):
    try:
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
        for v in vehicles_db:
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
        vehicles_db.append(vehicle)
        model_name = merged.get("model", "")
        if model_name:
            load_manual_for_vehicle(vehicle_number, model_name, rc_data=merged)
        return {"message": "Vehicle created successfully.", "vehicle_number": vehicle_number,
                "document_type": "RC", "vehicle_saved": True, "details": merged}
    except Exception as e:
        print(f"ERROR /process: {e}")
        return {"message": "Processing failed", "error": str(e), "vehicle_saved": False}


@app.post("/add-vehicle-manual")
def add_vehicle_manual(data: ManualVehicleRequest):
    vehicle_number = normalize_vehicle_number(data.vehicle_number)
    for v in vehicles_db:
        if normalize_vehicle_number(v["vehicle_number"]) == vehicle_number:
            return {"message": "Vehicle already exists.", "vehicle_number": vehicle_number}
    details = fetch_vehicle_details_from_api(vehicle_number)
    if not details:
        return {"message": "Could not fetch vehicle details."}
    vehicle = _build_vehicle_dict(vehicle_number, details)
    vehicles_db.append(vehicle)
    if details.get("model"):
        load_manual_for_vehicle(vehicle_number, details["model"])
    return {"message": "Vehicle created", "vehicle": vehicle}


@app.post("/add-document")
def add_document(data: DocumentUploadRequest):
    try:
        vehicle_number = normalize_vehicle_number(data.vehicleNumber)
        doc_type       = data.docType
        target = next((v for v in vehicles_db
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
def delete_vehicle(vehicle_number: str):
    vehicle_number = normalize_vehicle_number(vehicle_number)
    idx = next((i for i, v in enumerate(vehicles_db)
                if normalize_vehicle_number(v["vehicle_number"]) == vehicle_number), None)
    if idx is None:
        return {"message": "Vehicle not found.", "deleted": False}
    deleted = vehicles_db.pop(idx)
    knowledge_base.pop(vehicle_number, None)
    chat_history.pop(vehicle_number, None)
    return {"message": f"Vehicle {vehicle_number} deleted.", "deleted": True,
            "docs_deleted": len(deleted.get("documents", [])),
            "bills_deleted": len(deleted.get("service_bills", []))}


@app.post("/upload-service-bill")
def upload_service_bill(data: ServiceBillRequest):
    try:
        vehicle_number = normalize_vehicle_number(data.vehicleNumber)
        target = next((v for v in vehicles_db
                       if normalize_vehicle_number(v["vehicle_number"]) == vehicle_number), None)
        if not target:
            return {"message": f"Vehicle {vehicle_number} not found."}
        ocr_text    = run_ocr(data.imageUrl)
        bill_text   = extract_service_bill_text(ocr_text)
        explanation = generate_bill_explanation(ocr_text, target.get("model", ""))
        bill_chunks = chunk_text(bill_text,
                                 source_label=f"Service Bill ({datetime.now().strftime('%d/%m/%Y')})")
        if vehicle_number not in knowledge_base:
            knowledge_base[vehicle_number] = {"manual": [], "bills": []}
        knowledge_base[vehicle_number]["bills"].extend(bill_chunks)
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


@app.post("/upload-manual")
def upload_manual(data: ManualUploadRequest):
    try:
        vehicle_number = normalize_vehicle_number(data.vehicleNumber)
        target = next((v for v in vehicles_db
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
        if vehicle_number not in knowledge_base:
            knowledge_base[vehicle_number] = {"manual": [], "bills": []}
        knowledge_base[vehicle_number]["manual"] = chunks
        return {"message": f"Manual uploaded. {len(chunks)} sections indexed.",
                "pages": pdf.page_count, "chunks": len(chunks)}
    except Exception as e:
        return {"message": "Error processing manual", "error": str(e)}


@app.post("/chat")
def chat(data: ChatRequest):
    try:
        lookup_number  = normalize_vehicle_number(data.targetVehicleNumber or data.vehicleNumber)
        primary_number = normalize_vehicle_number(data.vehicleNumber)
        vehicle = _get_vehicle_context(lookup_number) or _get_vehicle_context(primary_number)
        if not vehicle:
            return {"answer": "I could not find the vehicle."}
        vn         = normalize_vehicle_number(vehicle["vehicle_number"])
        model_name = vehicle.get("model", "")
        kb         = knowledge_base.get(vn, {"manual": [], "bills": []})
        if model_name and not kb.get("manual"):
            load_manual_for_vehicle(vn, model_name)
            kb = knowledge_base.get(vn, {"manual": [], "bills": []})
        context_block = _build_context_block(vehicle, data.question, kb)
        system_prompt = build_system_prompt(vehicle, context_block)
        history       = chat_history.get(primary_number, [])[-10:]
        messages      = history + [{"role": "user", "content": data.question}]
        groq_messages = [{"role": "system", "content": system_prompt}]
        for msg in messages[:-1]:
            groq_messages.append({"role": msg["role"], "content": msg["content"]})
        groq_messages.append({"role": "user", "content": data.question})
        resp = groq_client.chat.completions.create(
            model="llama-3.3-70b-versatile", messages=groq_messages,
            max_tokens=1024, temperature=0.3)
        answer = resp.choices[0].message.content
        if primary_number not in chat_history:
            chat_history[primary_number] = []
        chat_history[primary_number].append({"role": "user",      "content": data.question})
        chat_history[primary_number].append({"role": "assistant", "content": answer})
        return {"answer": answer, "vehicle_number": vn,
                "manual_loaded": len(kb.get("manual", [])) > 0,
                "manual_chunks": len(kb.get("manual", []))}
    except Exception as e:
        print(f"[Chat] ERROR: {e}")
        return {"answer": "AI service is temporarily unavailable.", "error": str(e)}


@app.delete("/chat/history/{vehicle_number}")
def clear_chat_history(vehicle_number: str):
    vn = normalize_vehicle_number(vehicle_number)
    chat_history.pop(vn, None)
    return {"message": f"Chat history cleared for {vn}"}


@app.get("/vehicles")
def get_vehicles():
    return vehicles_db


@app.get("/vehicle/{vehicle_number}")
def get_vehicle(vehicle_number: str):
    vehicle_number = normalize_vehicle_number(vehicle_number)
    for v in vehicles_db:
        if normalize_vehicle_number(v["vehicle_number"]) == vehicle_number:
            return v
    return {"message": "Vehicle not found."}


@app.get("/expiry-status")
def expiry_status_all():
    result = []
    for vehicle in vehicles_db:
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
def debug_manual(vehicle_number: str):
    vn = normalize_vehicle_number(vehicle_number)
    kb = knowledge_base.get(vn, {})
    return {
        "manual_chunks":   len(kb.get("manual", [])),
        "bill_chunks":     len(kb.get("bills", [])),
        "manual_loaded":   len(kb.get("manual", [])) > 0,
        "manual_sections": list({c["source"] for c in kb.get("manual", [])}),
    }