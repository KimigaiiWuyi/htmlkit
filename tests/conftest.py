from pathlib import Path

import pytest

ASSETS_DIR = Path(__file__).parent / "assets"


def pytest_addoption(parser):
    parser.addoption(
        "--regen-ref",
        action="store_true",
        default=False,
        help="Regenerate reference images instead of verifying against them",
    )
    parser.addoption(
        "--output-img-dir",
        type=str,
        default="",
        help="Directory to save output images",
    )


@pytest.fixture(scope="session")
def regen_ref(request):
    return request.config.getoption("--regen-ref")


@pytest.fixture(scope="session")
def output_img_dir(request):
    return request.config.getoption("--output-img-dir")
