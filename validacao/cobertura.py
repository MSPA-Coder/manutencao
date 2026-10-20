"""Measure the complete existing suite without changing application dependencies."""
import json
import os
import runpy
import sys
from pathlib import Path

import coverage

project = os.environ["VALIDATION_PROJECT"]
output = Path("/evidence") / project
output.mkdir(exist_ok=True)
sources = os.environ["VALIDATION_SOURCES"].split(",")
sys.path.insert(0, os.getcwd())
measurement = coverage.Coverage(
    data_file=str(output / ".coverage"),
    branch=True,
    source=sources,
    omit=["*/tests/*", "*/CodexTemp/*", "*/build/*"]
    + ([] if project == "SharedAuth" else ["*/.venv/*"]),
)
measurement.start()
exit_code = 0
try:
    if project == "BackupRestore":
        sys.argv = ["unittest", "discover", "-s", "tests", "-v"]
        runpy.run_module("unittest", run_name="__main__")
    else:
        sys.argv = ["pytest", "-ra", "-o", "cache_dir=/tmp/validation-pytest-cache", "--junitxml=" + str(output / "junit.xml")]
        runpy.run_module("pytest", run_name="__main__")
except SystemExit as exc:
    exit_code = exc.code if isinstance(exc.code, int) else int(bool(exc.code))
finally:
    measurement.stop()
    measurement.save()
    measurement.json_report(outfile=str(output / "coverage.json"))
    measurement.xml_report(outfile=str(output / "coverage.xml"))
    measurement.html_report(directory=str(output / "html"))
    data = json.loads((output / "coverage.json").read_text())
    (output / "result.json").write_text(json.dumps({
        "project": project, "suite_exit_code": exit_code,
        "sources": sources, "coverage_version": coverage.__version__,
        "totals": data["totals"],
    }, indent=2) + "\n")
    print("VALIDATION_RESULT", (output / "result.json").read_text())
sys.exit(exit_code)
