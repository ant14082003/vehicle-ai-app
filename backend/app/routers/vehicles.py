from fastapi import APIRouter
from app.dependencies.firebase import db

router = APIRouter(prefix="/vehicles")

@router.get("/")
def get_vehicles():

    vehicles = db.collection("vehicles").stream()

    result = []

    for v in vehicles:
        data = v.to_dict()
        data["id"] = v.id
        result.append(data)

    return result