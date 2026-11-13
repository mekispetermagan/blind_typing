import sqlite3
from .config import DATABASE_PATH


def initialize_database():
    DATABASE_PATH.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(DATABASE_PATH):
        pass
