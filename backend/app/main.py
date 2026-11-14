from contextlib import asynccontextmanager
from fastapi import FastAPI
from .database import initialize_database
from .routers.content import router
from .routers.attempts import router as attempts_router
from .routers.progress import router as progress_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    initialize_database()
    yield


app = FastAPI(lifespan=lifespan)
app.include_router(router)
app.include_router(attempts_router)
app.include_router(progress_router)
