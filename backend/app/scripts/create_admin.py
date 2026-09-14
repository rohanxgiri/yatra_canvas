"""Idempotent CLI command to bootstrap or update the initial YatraCanvas administrator."""

import argparse
import getpass
import os
import sys
from datetime import datetime, timezone

from sqlalchemy import func
from sqlmodel import Session, select

from app.core.security import hash_password
from app.database import create_db_and_tables, get_engine
from app.models import User, UserRole


def create_or_update_admin(
    email: str,
    password: str,
    name: str = "YatraCanvas Admin",
    update_password_if_exists: bool = False,
) -> bool:
    """Create the initial admin user or update their password if requested."""

    create_db_and_tables()
    normalized_email = email.strip().lower()

    with Session(get_engine()) as session:
        user = session.exec(
            select(User).where(func.lower(User.email) == normalized_email)
        ).first()

        now = datetime.now(timezone.utc)

        if user is not None:
            if update_password_if_exists:
                user.password_hash = hash_password(password)
                user.role = UserRole.ADMIN.value
                user.is_active = True
                user.name = name or user.name
                user.updated_at = now
                session.add(user)
                session.commit()
                print(f"Updated password and verified ADMIN role for: {user.email}")
                return True

            print(
                f"Admin user already exists: {user.email} (role: {user.role}, active: {user.is_active}). "
                "Use --update-password to reset the password."
            )
            return True

        new_admin = User(
            email=normalized_email,
            name=name,
            password_hash=hash_password(password),
            role=UserRole.ADMIN.value,
            is_active=True,
            created_at=now,
            updated_at=now,
        )
        session.add(new_admin)
        session.commit()
        session.refresh(new_admin)
        print(f"Admin account created successfully: {new_admin.email} (ID: {new_admin.id})")
        return True


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Bootstrap or update a YatraCanvas administrator account."
    )
    parser.add_argument(
        "--email",
        default=os.getenv("ADMIN_EMAIL", "admin@yatracanvas.com"),
        help="Administrator email address (default: ADMIN_EMAIL or admin@yatracanvas.com)",
    )
    parser.add_argument(
        "--password",
        default=os.getenv("ADMIN_PASSWORD"),
        help="Administrator password (default: ADMIN_PASSWORD env var; prompts if omitted)",
    )
    parser.add_argument(
        "--name",
        default="YatraCanvas Admin",
        help="Administrator display name (default: 'YatraCanvas Admin')",
    )
    parser.add_argument(
        "--update-password",
        action="store_true",
        help="Update the password if the administrator account already exists",
    )

    args = parser.parse_args()

    password = args.password
    if not password:
        if sys.stdin.isatty():
            password = getpass.getpass(f"Enter password for admin ({args.email}): ")
            confirm = getpass.getpass("Confirm password: ")
            if password != confirm:
                print("Error: Passwords do not match.", file=sys.stderr)
                sys.exit(1)
        else:
            print(
                "Error: Password must be supplied via --password or ADMIN_PASSWORD env var in non-interactive mode.",
                file=sys.stderr,
            )
            sys.exit(1)

    if len(password.strip()) < 8:
        print("Error: Admin password must be at least 8 characters long.", file=sys.stderr)
        sys.exit(1)

    create_or_update_admin(
        email=args.email,
        password=password,
        name=args.name,
        update_password_if_exists=args.update_password,
    )


if __name__ == "__main__":
    main()
