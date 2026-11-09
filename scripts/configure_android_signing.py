#!/usr/bin/env python3
"""Injects release keystore signing configuration into Flutter's generated app build.gradle(.kts)."""

from pathlib import Path
import sys


KTS_PROPERTIES = """val keystoreProperties = java.util.Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    java.io.FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}
"""

KTS_SIGNING_BLOCK = """    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {"""

KTS_RELEASE_SIGNING = """signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }"""


def patch_kts(path: Path) -> None:
    content = path.read_text(encoding="utf-8")
    if "keystorePropertiesFile" in content:
        print(f"{path} already configured for release signing.")
        return

    plugins_end = content.find("}\n", content.find("plugins {"))
    if plugins_end == -1:
        raise RuntimeError(f"Could not locate plugins block in {path}")
    insert_pos = plugins_end + 2
    content = content[:insert_pos] + "\n" + KTS_PROPERTIES + content[insert_pos:]

    if "    buildTypes {" not in content:
        raise RuntimeError(f"Could not locate buildTypes block in {path}")
    content = content.replace("    buildTypes {", KTS_SIGNING_BLOCK, 1)

    old_debug = 'signingConfig = signingConfigs.getByName("debug")'
    if old_debug not in content:
        raise RuntimeError(f"Could not locate debug signingConfig line in {path}")
    content = content.replace(old_debug, KTS_RELEASE_SIGNING, 1)

    path.write_text(content, encoding="utf-8")
    print(f"Successfully configured release signing in {path}")


def patch_groovy(path: Path) -> None:
    content = path.read_text(encoding="utf-8")
    if "keystorePropertiesFile" in content:
        print(f"{path} already configured for release signing.")
        return

    header = """def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.withReader('UTF-8') { reader -> keystoreProperties.load(reader) }
}

"""
    signing = """    signingConfigs {
        release {
            if (keystorePropertiesFile.exists()) {
                keyAlias keystoreProperties['keyAlias']
                keyPassword keystoreProperties['keyPassword']
                storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
                storePassword keystoreProperties['storePassword']
            }
        }
    }

    buildTypes {"""

    content = header + content
    content = content.replace("    buildTypes {", signing, 1)
    content = content.replace(
        "signingConfig signingConfigs.debug",
        "signingConfig keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug",
        1,
    )
    content = content.replace(
        "signingConfig = signingConfigs.debug",
        "signingConfig = keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug",
        1,
    )
    path.write_text(content, encoding="utf-8")
    print(f"Successfully configured release signing in {path}")


def main() -> int:
    kts = Path("android/app/build.gradle.kts")
    groovy = Path("android/app/build.gradle")
    if kts.exists():
        patch_kts(kts)
        return 0
    if groovy.exists():
        patch_groovy(groovy)
        return 0
    print("ERROR: Neither android/app/build.gradle.kts nor android/app/build.gradle found!", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
