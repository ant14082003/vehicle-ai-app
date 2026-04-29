import re

def extract_expiry_date(text):

    pattern = r"\d{2}/\d{2}/\d{4}"

    matches = re.findall(pattern, text)

    if matches:
        return matches[0]

    return None