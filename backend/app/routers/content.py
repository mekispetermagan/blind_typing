import json
import re
from pathlib import Path
from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import FileResponse, Response
from ..config import ROOT

router = APIRouter(prefix='/api')


@router.get('/menu')
def menu():
    return json.loads((ROOT / 'data' / 'menu.json').read_text(encoding='utf-8'))


@router.get('/activities/{category}/{name}')
def activity(category: str, name: str):
    if category not in {'lessons', 'practice'} or not re.fullmatch(r'[a-zA-Z0-9_]+\.json', name):
        raise HTTPException(404)
    path = ROOT / 'data' / category / name
    if not path.is_file():
        raise HTTPException(404)
    return json.loads(path.read_text(encoding='utf-8'))


@router.get('/audio/{name}')
def audio(name: str, request: Request):
    if not re.fullmatch(r'[a-zA-Z0-9_]+\.(wav|mp3)', name):
        raise HTTPException(404)
    path = ROOT / 'assets' / 'audio' / name
    if not path.is_file():
        raise HTTPException(404)
    stat = path.stat()
    etag = f'"{stat.st_mtime_ns:x}-{stat.st_size:x}"'
    if request.headers.get('if-none-match') == etag:
        return Response(status_code=304, headers={'ETag': etag})
    return FileResponse(path, headers={'ETag': etag, 'Cache-Control': 'no-cache'})
