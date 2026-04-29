from fastapi import APIRouter
from app.services.ai_service import get_answer

router = APIRouter(prefix="/ai")

@router.post("/query")
def query_ai(data: dict):

    question = data.get("question")

    result = get_answer(question)

    return result