import json
import re
from pathlib import Path
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import FileResponse, Response
from ..config import ROOT
from ..auth import current_user
from ..models import Role, User

router = APIRouter(prefix='/api')


@router.get('/menu')
def menu():
    return json.loads((ROOT / 'data' / 'menu.json').read_text(encoding='utf-8'))


@router.get('/areas/{area}/menu')
def area_menu(area: str, user: User = Depends(current_user)):
    allowed = {
        'student': {Role.STUDENT, Role.TRAINER, Role.ADMIN},
        'trainer': {Role.TRAINER, Role.ADMIN},
        'admin': {Role.ADMIN},
    }
    if area not in allowed:
        raise HTTPException(404, 'Unknown area')
    if user.role not in allowed[area]:
        raise HTTPException(403, 'Insufficient role')
    catalog = menu()
    return_item = {'id': 'area_selector', 'title': 'Vissza a területválasztóhoz', 'command': 'areaSelector'}
    if area == 'student':
        catalog['root']['children'].insert(-1, {'id': 'homeworks', 'title': 'Házi feladatok', 'command': 'homeworks'})
        if user.role in {Role.TRAINER, Role.ADMIN}:
            catalog['root']['children'].insert(-1, return_item)
    else:
        title = 'Adminisztrátor főmenü' if area == 'admin' else 'Oktatói főmenü'
        items = [return_item, {'id': 'logout', 'title': 'Kilépés', 'command': 'logout'}]
        if area == 'trainer':
            items.insert(0, {'id': 'student_progress', 'title': 'Tanulók haladása', 'command': 'students'})
            items.insert(0, {'id': 'view_homeworks', 'title': 'Házi feladatok megtekintése', 'command': 'viewHomeworks'})
            items.insert(0, {'id': 'add_homework', 'title': 'Házi feladat feladása', 'command': 'addHomework'})
        catalog['root'] = {
            'id': f'{area}_main', 'title': title, 'children': items,
        }
        catalog['progression'] = []
        catalog['challengeProgression'] = []
    return catalog


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
