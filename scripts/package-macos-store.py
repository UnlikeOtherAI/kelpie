#!/usr/bin/env python3

import argparse
import hashlib
import os
import plistlib
import re
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from macos_autofill_signing import EXTENSION, prepare


TEAM = "23B7GTLBN7"
BUNDLE_ID = "com.unlikeotherai.kelpie"
RESOURCES_ID = "com.unlikeotherai.kelpie.browser.resources.macos"
RESOURCES = Path("Contents/Resources/KelpieBrowserResources.bundle")
INSTALLER = f"3rd Party Mac Developer Installer: UnlikeOtherAI s.r.o. ({TEAM})"
APP_IDENTIFIER = f"{TEAM}.{BUNDLE_ID}"


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def command(*args):
    return subprocess.run([str(arg) for arg in args], check=True, capture_output=True)


def read_plist(path):
    return plistlib.loads(path.read_bytes())


def write_plist(path, values):
    path.write_bytes(plistlib.dumps(values))


def distribution_certificate(profile):
    details = plistlib.loads(command("security", "cms", "-D", "-i", profile).stdout)
    entitlements = details["Entitlements"]
    require(details["TeamIdentifier"] == [TEAM], "Provisioning profile belongs to a different team")
    require("OSX" in details["Platform"], "Provisioning profile does not cover macOS")
    require(entitlements.get("com.apple.application-identifier") == APP_IDENTIFIER,
            "Provisioning profile does not cover the App Store bundle identifier")
    require(not details.get("ProvisionedDevices") and not details.get("ProvisionsAllDevices")
            and not entitlements.get("com.apple.security.get-task-allow")
            and not entitlements.get("get-task-allow"), "Expected a Mac App Store distribution profile")
    require(details["ExpirationDate"].replace(tzinfo=timezone.utc) > datetime.now(timezone.utc),
            "Provisioning profile has expired")
    certificates = details["DeveloperCertificates"]
    require(len(certificates) == 1, "Expected one distribution certificate in the provisioning profile")
    return certificates[0]


def verify_signature(path, identifier, certificate, scratch):
    details = command("codesign", "-dvv", path).stderr.decode().splitlines()
    require(f"Identifier={identifier}" in details, f"Incorrect code signature identifier in {path.name}")
    require(f"TeamIdentifier={TEAM}" in details, f"Incorrect Apple signing team in {path.name}")
    prefix = scratch / f"{path.name}-certificate-"
    command("codesign", "--display", f"--extract-certificates={prefix}", path)
    require(Path(f"{prefix}0").read_bytes() == certificate, f"Unexpected signing certificate in {path.name}")


def package(archive, profile, provider_profile, version, build, output):
    source = archive / "Products/Applications/Kelpie.app"
    info = read_plist(source / "Contents/Info.plist")
    require(info["CFBundleIdentifier"] == BUNDLE_ID, "Archive the WebKit-only Kelpie App Store target")
    require(info.get("LSApplicationCategoryType"), "The archive is missing its App Store category")
    require(re.fullmatch(r"\d+\.\d+(?:\.\d+)?", version) and re.fullmatch(r"[1-9]\d*", build),
            "Supply a numeric App Store version and positive integer build number")
    require(output.suffix == ".pkg" and not output.exists() and output.parent.is_dir(),
            "Supply a new .pkg path in an existing directory")

    certificate = distribution_certificate(profile)
    identity = hashlib.sha1(certificate).hexdigest().upper()
    available_identities = command("security", "find-identity", "-v", "-p", "codesigning").stdout.decode()
    require(any(identity in line and "Apple Distribution:" in line and TEAM in line
                for line in available_identities.splitlines()),
            "The Mac App Store profile's Apple Distribution private key is unavailable")

    with tempfile.TemporaryDirectory(prefix="kelpie-store-", dir=output.parent) as temporary:
        scratch = Path(temporary)
        app = scratch / source.name
        command("ditto", source, app)
        resources = app / RESOURCES
        require(read_plist(resources / "Contents/Info.plist")["CFBundleIdentifier"] == RESOURCES_ID,
                "Unexpected browser resources identifier")
        plugins = app / "Contents/PlugIns"
        require(set(plugins.iterdir()) == {app / EXTENSION}, "Expected only the Kelpie AutoFill extension")
        for container in ("Frameworks", "Helpers", "XPCServices"):
            location = app / "Contents" / container
            require(not location.exists() or not any(location.iterdir()),
                    f"Unexpected packaged code in Contents/{container} in the WebKit-only app")

        info.update(CFBundleShortVersionString=version, CFBundleVersion=build)
        write_plist(app / "Contents/Info.plist", info)
        embedded_profile = Path("Contents/embedded.provisionprofile")
        allowed = prepare(app, profile, provider_profile, scratch, "store")
        require(identity in allowed, "The AutoFill provider profile must permit the distribution identity")
        provider_info = app / EXTENSION / "Contents/Info.plist"
        extension_info = read_plist(provider_info)
        extension_info.update(CFBundleShortVersionString=version, CFBundleVersion=build)
        write_plist(provider_info, extension_info)
        entitlements = scratch / "host.plist"
        store_entitlements = read_plist(entitlements)
        command("codesign", "--force", "--sign", identity, "--entitlements", scratch / "provider.plist", app / EXTENSION)

        command("codesign", "--force", "--sign", identity, "--identifier", RESOURCES_ID, resources)
        command("codesign", "--force", "--sign", identity, "--identifier", BUNDLE_ID,
                "--entitlements", entitlements, app)
        command("codesign", "--verify", "--deep", "--strict", app)
        package_path = scratch / output.name
        command("productbuild", "--component", app, "/Applications", "--sign", INSTALLER, package_path)
        command("pkgutil", "--check-signature", package_path)

        expanded = scratch / "expanded"
        command("pkgutil", "--expand-full", package_path, expanded)
        apps = list(expanded.rglob("Kelpie.app"))
        require(len(apps) == 1, "Installer does not contain exactly one Kelpie app")
        payload = apps[0]
        command("codesign", "--verify", "--deep", "--strict", payload)
        require(read_plist(payload / "Contents/Info.plist") == info, "Packaged app metadata differs")
        require((payload / embedded_profile).read_bytes() == profile.read_bytes(),
                "Packaged app is missing the selected provisioning profile")
        require((payload / EXTENSION / embedded_profile).read_bytes() == provider_profile.read_bytes(),
                "Packaged AutoFill provider profile differs")
        verify_signature(payload / EXTENSION, BUNDLE_ID + ".autofill", certificate, scratch)
        provider_entitlements = command("codesign", "-d", "--entitlements", "-", "--xml", payload / EXTENSION).stdout
        require(plistlib.loads(provider_entitlements) == read_plist(scratch / "provider.plist"),
                "Packaged AutoFill provider entitlements differ")
        verify_signature(payload / RESOURCES, RESOURCES_ID, certificate, scratch)
        verify_signature(payload, BUNDLE_ID, certificate, scratch)
        signed_entitlements = command("codesign", "-d", "--entitlements", "-", "--xml", payload).stdout
        require(plistlib.loads(signed_entitlements) == store_entitlements, "Packaged app entitlements differ")
        os.link(package_path, output)
    print(f"Verified signed {BUNDLE_ID} {version} build {build} with an embedded Mac App Store profile.")
    print(output)


def main():
    parser = argparse.ArgumentParser(description="Package a Kelpie macOS archive for App Store Connect.")
    parser.add_argument("--archive", required=True, type=Path)
    profiles = Path.home() / ".config/unlikeotherai/signing/kelpie-autofill"
    parser.add_argument("--profile", type=Path, default=profiles / "MAC_APP_STORE-host.provisionprofile")
    parser.add_argument("--provider-profile", type=Path, default=profiles / "MAC_APP_STORE-provider.provisionprofile")
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        package(args.archive.resolve(), args.profile.resolve(), args.provider_profile.resolve(), args.version, args.build, args.output.resolve())
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr.decode(errors="replace").strip())
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
