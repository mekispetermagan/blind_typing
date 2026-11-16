from contextlib import asynccontextmanager
from fastapi import Depends, FastAPI, Request
from .database import initialize_database
from .models.base import utc_now
from .auth import current_user
from .routers.auth import router as auth_router
from .routers.content import router
from .routers.attempts import router as attempts_router
from .routers.progress import router as progress_router
from .routers.trainer import router as trainer_router
from .routers.homework import router as homework_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    initialize_database()
    yield


app = FastAPI(lifespan=lifespan)


@app.middleware('http')
async def timestamp_homework_submission(request: Request, call_next):
    if (request.method == 'PUT' and request.url.path.startswith('/api/homeworks/')
            and '/attempts/' in request.url.path):
        await request.body()
        request.state.submission_received_at = utc_now()
    return await call_next(request)

app.include_router(auth_router)
app.include_router(router, dependencies=[Depends(current_user)])
app.include_router(attempts_router)
app.include_router(progress_router)
app.include_router(trainer_router)
app.include_router(homework_router)
