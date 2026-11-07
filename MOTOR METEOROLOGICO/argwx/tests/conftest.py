import os
import tempfile

_tmp = tempfile.mkdtemp(prefix="argwx-test-")
os.environ.update({
    "ARGWX_DATABASE_URL": f"sqlite:///{_tmp}/test.db", "ARGWX_DATA_MODE": "demo",
    "ARGWX_SYNC_ON_STARTUP": "false", "ARGWX_SCHEDULER_ENABLED": "false", "ARGWX_ENV": "development",
})

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402


@pytest.fixture(scope="session")
def client():
    from app.main import app
    from app.services.sync import sync

    with TestClient(app) as c:
        sync()
        yield c
