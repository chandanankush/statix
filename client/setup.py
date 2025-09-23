from pathlib import Path

from setuptools import find_packages, setup

BASE_DIR = Path(__file__).parent
README = (BASE_DIR / "README.md").read_text(encoding="utf-8")

setup(
    name="system-stats-service",
    version="0.1.0",
    description="FastAPI service that exposes host system statistics.",
    long_description=README,
    long_description_content_type="text/markdown",
    author="Monitoring Stack",
    packages=find_packages(include=["system_stats", "system_stats.*"]),
    python_requires=">=3.9",
    include_package_data=True,
    install_requires=[
        "fastapi>=0.115.0",
        "uvicorn[standard]>=0.32.0",
        "psutil>=5.9.0",
        "requests>=2.32.0",
    ],
    entry_points={
        "console_scripts": [
            "system-stats-service=system_stats.main:main",
            "system-stats-forwarder=system_stats.forwarder:main",
        ]
    },
    classifiers=[
        "Programming Language :: Python :: 3",
        "Operating System :: OS Independent",
    ],
)
