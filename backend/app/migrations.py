import logging
from sqlalchemy import inspect, text
from app.database import engine, Base
from app import models  # noqa: F401 — ensure all models are registered

logger = logging.getLogger("maveric_ai.migrations")


def _add_column_if_missing(conn, inspector, table_name: str, column_name: str, column_def: str):
    """Helper: add a column to a table only if it doesn't already exist."""
    if table_name not in inspector.get_table_names():
        return
    existing_columns = [col["name"] for col in inspector.get_columns(table_name)]
    if column_name not in existing_columns:
        logger.info("Migration: Adding column '%s' to table '%s'", column_name, table_name)
        conn.execute(text(f"ALTER TABLE {table_name} ADD COLUMN {column_name} {column_def};"))


def run_migrations():
    """
    Run non-destructive SQLite migrations using ALTER TABLE.
    FIXED: Extended to cover ALL tables, not just 'users'.
    Never drops tables. Never deletes data.
    """
    logger.info("Running database migrations...")

    # Create all tables defined in models (safe no-op if they already exist)
    Base.metadata.create_all(bind=engine)

    inspector = inspect(engine)

    with engine.connect() as conn:
        # ── users ─────────────────────────────────────────────────────────────
        _add_column_if_missing(conn, inspector, "users", "password_hash", "VARCHAR")
        _add_column_if_missing(conn, inspector, "users", "google_id", "VARCHAR")
        _add_column_if_missing(conn, inspector, "users", "profile_photo", "VARCHAR")
        _add_column_if_missing(conn, inspector, "users", "updated_at", "DATETIME")

        # ── conversations ─────────────────────────────────────────────────────
        _add_column_if_missing(conn, inspector, "conversations", "title", "VARCHAR DEFAULT 'New Chat'")
        _add_column_if_missing(conn, inspector, "conversations", "updated_at", "DATETIME")

        # ── chat_messages ─────────────────────────────────────────────────────
        _add_column_if_missing(conn, inspector, "chat_messages", "type", "VARCHAR DEFAULT 'text'")
        _add_column_if_missing(conn, inspector, "chat_messages", "file_path", "VARCHAR")
        _add_column_if_missing(conn, inspector, "chat_messages", "file_name", "VARCHAR")
        _add_column_if_missing(conn, inspector, "chat_messages", "voice_duration", "VARCHAR")
        _add_column_if_missing(conn, inspector, "chat_messages", "image_url", "VARCHAR")
        _add_column_if_missing(conn, inspector, "chat_messages", "model_used", "VARCHAR")
        _add_column_if_missing(conn, inspector, "chat_messages", "like_status", "INTEGER")

        # ── otp_tokens ────────────────────────────────────────────────────────
        _add_column_if_missing(conn, inspector, "otp_tokens", "is_used", "BOOLEAN DEFAULT 0")
        _add_column_if_missing(conn, inspector, "otp_tokens", "expires_at", "DATETIME")

        conn.commit()

    logger.info("Database migrations completed successfully.")


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    run_migrations()
