"""Validate provisioning and prepare the two Kelpie AutoFill signatures."""
import argparse
import fnmatch
import hashlib
import plistlib
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path

TEAM = "23B7GTLBN7"
CAPABILITY = "com.apple.developer.authentication-services.autofill-credential-provider"
EXTENSION = Path("Contents/PlugIns/KelpieAutoFill.appex")
ROOT = Path(__file__).resolve().parents[1] / "apps/macos"


def read_profile(path):
    result = subprocess.run(["security", "cms", "-D", "-i", str(path)], check=True, capture_output=True)
    return plistlib.loads(result.stdout)


def validate_profile(profile, bundle_id, group, distribution):
    entitlement = profile["Entitlements"]
    if (profile["TeamIdentifier"] != [TEAM] or "OSX" not in profile["Platform"]
            or entitlement.get("com.apple.application-identifier") != TEAM + "." + bundle_id
            or entitlement.get(CAPABILITY) is not True):
        raise ValueError(f"Use an UnlikeOtherAI macOS AutoFill profile for {bundle_id}")
    if not any(fnmatch.fnmatchcase(group, item) for item in entitlement.get("keychain-access-groups", [])):
        raise ValueError(f"Profile for {bundle_id} does not permit the website-password Keychain group")
    if (bool(profile.get("ProvisionsAllDevices")) != (distribution == "direct")
            or profile.get("ProvisionedDevices") or entitlement.get("get-task-allow")
            or entitlement.get("com.apple.security.get-task-allow")):
        raise ValueError(f"Expected a {distribution} distribution profile for {bundle_id}")
    if profile["ExpirationDate"].replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc):
        raise ValueError(f"Expired profile for {bundle_id}")


def prepare(app, host_path, extension_path, scratch, distribution):
    host_id = plistlib.loads((app / "Contents/Info.plist").read_bytes())["CFBundleIdentifier"]
    extension = app / EXTENSION
    extension_id = plistlib.loads((extension / "Contents/Info.plist").read_bytes())["CFBundleIdentifier"]
    if host_id != "com.unlikeotherai.kelpie" or extension_id != host_id + ".autofill":
        raise ValueError("The embedded AutoFill extension does not belong to this Kelpie app")
    group = TEAM + "." + host_id + ".website-passwords"
    host_profile = read_profile(host_path)
    extension_profile = read_profile(extension_path)
    validate_profile(host_profile, host_id, group, distribution)
    validate_profile(extension_profile, extension_id, group, distribution)
    common = set(host_profile["DeveloperCertificates"]) & set(extension_profile["DeveloperCertificates"])
    if not common:
        raise ValueError("The two AutoFill profiles must allow the same signing certificate")
    host_template = "Kelpie/Kelpie.entitlements" if distribution == "direct" else "Kelpie/Store.entitlements"
    for bundle, identifier, profile, template, filename in [
        (app, host_id, host_path, host_template, "host.plist"),
        (extension, extension_id, extension_path, "PasswordAutoFill/AutoFill.entitlements", "provider.plist"),
    ]:
        values = plistlib.loads((ROOT / template).read_bytes())
        values["com.apple.application-identifier"] = TEAM + "." + identifier
        values["com.apple.developer.team-identifier"] = TEAM
        values["keychain-access-groups"] = [group]
        (scratch / filename).write_bytes(plistlib.dumps(values))
        shutil.copyfile(profile, bundle / "Contents/embedded.provisionprofile")
    return sorted(hashlib.sha1(cert).hexdigest().upper() for cert in common)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    for arg in ["app", "host-profile", "provider-profile", "scratch"]:
        parser.add_argument("--" + arg, required=True, type=Path)
    args = parser.parse_args()
    print("\n".join(prepare(args.app, args.host_profile, args.provider_profile, args.scratch, "direct")))
