from contextlib import asynccontextmanager
from fastapi import FastAPI
from .database import initialize_database
from .routers.content import router


@asynccontextmanager
async def lifespan(app: FastAPI):
    initialize_database()
    yield


app = FastAPI(lifespan=lifespan)
app.include_router(router)
