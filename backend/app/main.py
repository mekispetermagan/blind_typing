from contextlib import asynccontextmanager
from fastapi import Depends, FastAPI
from .database import initialize_database
from .auth import current_user
from .routers.auth import router as auth_router
from .routers.content import router
from .routers.attempts import router as attempts_router
from .routers.progress import router as progress_router
from .routers.trainer import router as trainer_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    initialize_database()
    yield


app = FastAPI(lifespan=lifespan)
app.include_router(auth_router)
app.include_router(router, dependencies=[Depends(current_user)])
app.include_router(attempts_router)
app.include_router(progress_router)
app.include_router(trainer_router)
