#!/usr/bin/env python3
"""Creates the iPhone simulator the StoreKit tests run on, and prints its id.

StoreKit's test sessions fail on the iOS 26.3 to 26.5 simulators: every
SKTestSession call logs SKInternalErrorDomain 3 ("Error saving
configuration file"), and there is then no storefront, no products and
nothing to buy, whether Xcode or xcodebuild runs the tests (Apple's
FB22237318, https://developer.apple.com/forums/thread/826971). They work
on 26.1 and 26.2; Apple lists a fix from Xcode 26.6, which the 26.5
runtime does not have.

So the tests run on the newest runtime of iOS 26.2 or earlier, else on
26.6 or later; with neither on the Mac, this downloads 26.2 first. The
iPhone it created before on that runtime is used again.

    udid=$(ios/scripts/storekit-test-simulator.py)
    xcodebuild test … -destination "id=$udid"
"""

import json
import subprocess
import sys

# SKTestSession fails from the first version up to, not including, the second.
BROKEN = ((26, 3), (26, 6))
# Downloaded when no runtime works: the newest known to.
FALLBACK = "26.2"
# The iPhone to create, the first the runtime has.
IPHONES = ["iPhone 17 Pro", "iPhone 16 Pro", "iPhone 15 Pro"]


def version(text):
    return tuple(int(part) for part in text.split("."))


def works(runtime):
    return not BROKEN[0] <= version(runtime["version"])[:2] < BROKEN[1]


def choose(runtimes):
    """The runtime and iPhone to test on, or None: 26.2 or earlier first,
    newest first, as those are known to work; then 26.6 or later."""
    usable = [
        runtime for runtime in runtimes
        if runtime.get("platform") == "iOS" and runtime.get("isAvailable") and works(runtime)
    ]
    usable.sort(key=lambda runtime: (version(runtime["version"]) < BROKEN[0], version(runtime["version"])), reverse=True)
    for runtime in usable:
        names = {device["name"]: device["identifier"] for device in runtime.get("supportedDeviceTypes", [])}
        iphone = next((name for name in IPHONES if name in names), None)
        if iphone is None:
            iphone = next((name for name in names if name.startswith("iPhone")), None)
        if iphone is not None:
            return runtime, iphone, names[iphone]
    return None


def installed():
    listing = subprocess.run(
        ["xcrun", "simctl", "list", "runtimes", "--json"], check=True, capture_output=True, text=True
    ).stdout
    return json.loads(listing)["runtimes"]


def existing(runtime, name):
    """The iPhone called `name` of `runtime`, if there is one."""
    listing = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "--json"], check=True, capture_output=True, text=True
    ).stdout
    devices = json.loads(listing)["devices"].get(runtime["identifier"], [])
    return next((device["udid"] for device in devices if device["name"] == name and device.get("isAvailable")), None)


def main():
    runtimes = installed()
    for runtime in runtimes:
        if runtime.get("platform") != "iOS":
            continue
        if not runtime.get("isAvailable"):
            state = "unavailable with this Xcode"
        else:
            state = "SKTestSession works" if works(runtime) else "SKTestSession broken"
        print(f"{runtime['name']} ({runtime['buildversion']}): {state}", file=sys.stderr)
    chosen = choose(runtimes)
    if chosen is None:
        print(f"No iOS runtime StoreKit's test sessions work on: downloading iOS {FALLBACK}.", file=sys.stderr)
        subprocess.run(["xcodebuild", "-downloadPlatform", "iOS", "-buildVersion", FALLBACK], check=True, stdout=sys.stderr)
        chosen = choose(installed())
    if chosen is None:
        sys.exit(f"iOS {FALLBACK} was downloaded, but simctl lists no iPhone of a runtime StoreKit's test sessions work on.")
    runtime, name, device_type = chosen
    print(f"StoreKit tests on {name}, {runtime['name']} ({runtime['buildversion']}).", file=sys.stderr)
    device = f"StoreKit tests ({name})"
    udid = existing(runtime, device) or subprocess.run(
        ["xcrun", "simctl", "create", device, device_type, runtime["identifier"]],
        check=True, capture_output=True, text=True,
    ).stdout.strip()
    print(udid)


if __name__ == "__main__":
    main()
