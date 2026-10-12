"""Anthropic API key in the GNOME keyring (libsecret). The key never touches a file."""
import gi
gi.require_version("Secret", "1")
from gi.repository import Secret  # noqa: E402

SCHEMA = Secret.Schema.new(
    "os.bapirlo.Writer", Secret.SchemaFlags.NONE,
    {"service": Secret.SchemaAttributeType.STRING},
)
ATTRS = {"service": "anthropic-api-key"}


def get_key():
    try:
        return Secret.password_lookup_sync(SCHEMA, ATTRS, None)
    except Exception:  # keyring locked / no secret service
        return None


def set_key(key):
    Secret.password_store_sync(SCHEMA, ATTRS, Secret.COLLECTION_DEFAULT,
                               "Bapirlo Writer — Anthropic API key", key.strip(), None)


def clear_key():
    try:
        Secret.password_clear_sync(SCHEMA, ATTRS, None)
    except Exception:
        pass
