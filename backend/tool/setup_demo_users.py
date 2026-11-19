#!/usr/bin/env python3
"""One-time local demo account setup. Run from backend with PYTHONPATH=."""
from getpass import getpass

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.auth import hasher
from app.database import engine, initialize_database
from app.models import AuthSession, Role, TrainerStudent, User


def main():
    initialize_database()
    pin = getpass('Demo admin PIN (six digits): ')
    if len(pin) != 6 or not pin.isascii() or not pin.isdigit():
        raise ValueError('The admin PIN must contain exactly six digits')
    with Session(engine) as session, session.begin():
        peter = session.scalar(select(User).where(User.name == 'Mekis Péter'))
        if peter is None:
            raise ValueError('Existing user Mekis Péter not found')
        peter.identifier = 'mekis.peter@gmail.com'
        peter.role = Role.ADMIN
        peter.credential_hash = hasher.hash(pin)
        peter.pin_temporary = True
        fruzsi = session.scalar(select(User).where(User.identifier == 'horvath.fruzsina@vakokintezete.hu'))
        if fruzsi is None:
            fruzsi = User(name='Horváth Fruzsina', identifier='horvath.fruzsina@vakokintezete.hu', role=Role.ADMIN)
            session.add(fruzsi)
        fruzsi.credential_hash = hasher.hash(pin)
        fruzsi.pin_temporary = True
        fruzsi.student_active = True
        session.flush()
        session.execute(delete(AuthSession).where(AuthSession.user_id.in_([peter.id, fruzsi.id])))
        if session.get(TrainerStudent, (fruzsi.id, peter.id)) is None:
            session.add(TrainerStudent(trainer_id=fruzsi.id, student_id=peter.id))


if __name__ == '__main__':
    main()
