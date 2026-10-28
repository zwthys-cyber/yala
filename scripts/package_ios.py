#!/usr/bin/env python3
"""Validate a device build and produce an unsigned IPA on a GitHub macOS runner."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import zipfile


def main():
    app = Path("build/ios/iphoneos/Runner.app")
    with (app / "Info.plist").open("rb") as source:
        info = plistlib.load(source)
    executable = app / info["CFBundleExecutable"]
    architectures = subprocess.check_output(
        ["lipo", "-archs", str(executable)], text=True
    ).strip().split()
    if "arm64" not in architectures:
        raise RuntimeError(f"Expected an arm64 device build, got {architectures}")
    if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
        raise RuntimeError("Refusing to package a simulator app as a device IPA")
    if not info.get("NSLocalNetworkUsageDescription"):
        raise RuntimeError("Missing iOS local network permission description")
    if not (app / "Frameworks/App.framework/flutter_assets").is_dir():
        raise RuntimeError("Flutter assets missing from compiled app")

    output = Path("output").resolve()
    output.mkdir(exist_ok=True)
    staging = Path("build/ios/ipa_staging")
    shutil.rmtree(staging, ignore_errors=True)
    payload = staging / "Payload"
    payload.mkdir(parents=True)
    shutil.copytree(app, payload / app.name, symlinks=True)
    ipa = output / "YALA-unsigned.ipa"
    ipa.unlink(missing_ok=True)
    subprocess.run(["zip", "-qry", str(ipa), "Payload"], cwd=staging, check=True)
    with zipfile.ZipFile(ipa) as archive:
        if archive.testzip() is not None:
            raise RuntimeError("IPA archive failed CRC verification")
        if "Payload/Runner.app/Info.plist" not in archive.namelist():
            raise RuntimeError("IPA Payload structure is invalid")
    checksum = hashlib.file_digest(ipa.open("rb"), "sha256").hexdigest()
    (output / "YALA-unsigned.ipa.sha256").write_text(f"{checksum}  {ipa.name}\n")
    report = {
        "repository": os.environ.get("GITHUB_REPOSITORY"),
        "commit": os.environ.get("GITHUB_SHA"),
        "run_url": (
            f"https://github.com/{os.environ.get('GITHUB_REPOSITORY')}/actions/runs/"
            f"{os.environ.get('GITHUB_RUN_ID')}"
        ),
        "bundle_identifier": info["CFBundleIdentifier"],
        "version": info["CFBundleShortVersionString"],
        "build_number": info["CFBundleVersion"],
        "minimum_ios": info["MinimumOSVersion"],
        "architectures": architectures,
        "sha256": checksum,
        "ipa_bytes": ipa.stat().st_size,
        "signing": "unsigned; user must sign before installation",
        "checks": ["arm64 device executable", "local network purpose string",
                   "Flutter assets", "IPA Payload layout", "ZIP CRC"],
        "real_router_test": "not performed by cloud CI",
    }
    (output / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    summary = (
        f"### YALA unsigned IPA\n\n"
        f"Version: {report['version']} ({report['build_number']}) · "
        f"iOS {report['minimum_ios']}+ · arm64\n\n"
        f"Commit: `{report['commit']}`\n\n"
        "Download the YALA-iOS-unsigned artifact below. Extract it and sign "
        "YALA-unsigned.ipa before installing on an iPhone.\n\n"
        f"SHA-256: `{checksum}`\n\n"
        "Cloud checks do not verify connectivity to your physical router.\n"
    )
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        Path(os.environ["GITHUB_STEP_SUMMARY"]).write_text(summary)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
