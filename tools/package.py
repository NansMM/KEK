#!/usr/bin/env python3
"""Fabrique les fichiers d'une release de KEK dans dist/ :

- KEK-<version>-forever.zip : le dossier KEK à la racine, prêt à copier dans Interface\\AddOns ;
- release.json : la carte d'identité lue par WowUp pour choisir le bon fichier (variante « forever ») ;
- notes.md : les notes de version, tirées de CHANGELOG.md.

Usage : python tools/package.py 1.7.2
"""
import io
import json
import os
import re
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "KEK")
DIST = os.path.join(ROOT, "dist")
REPO = "https://github.com/NansMM/KEK"


def fail(msg):
    print("ERREUR : " + msg)
    sys.exit(1)


def toc_field(name):
    with io.open(os.path.join(ADDON, "KEK.toc"), encoding="utf-8") as f:
        for line in f:
            m = re.match(r"^## %s:\s*(.+?)\s*$" % re.escape(name), line)
            if m:
                return m.group(1)
    return None


def changelog_section(version):
    path = os.path.join(ROOT, "CHANGELOG.md")
    if not os.path.exists(path):
        return None
    text = io.open(path, encoding="utf-8").read()
    m = re.search(r"^## %s\b[^\n]*\n(.*?)(?=^## |\Z)" % re.escape(version), text, re.S | re.M)
    return m.group(1).strip() if m else None


def main():
    if len(sys.argv) != 2 or not re.match(r"^\d+\.\d+\.\d+$", sys.argv[1]):
        fail("usage : python tools/package.py X.Y.Z")
    version = sys.argv[1]
    if toc_field("Version") != version:
        fail("KEK.toc annonce la version %s, pas %s" % (toc_field("Version"), version))
    interfaces = [int(n) for n in re.findall(r"\d+", toc_field("Interface") or "")]
    if 16001 not in interfaces:
        fail("KEK.toc doit déclarer l'interface 16001 (WoW Forever)")

    os.makedirs(DIST, exist_ok=True)
    zip_name = "KEK-%s-forever.zip" % version
    count = 0
    with zipfile.ZipFile(os.path.join(DIST, zip_name), "w", zipfile.ZIP_DEFLATED) as z:
        for dirpath, dirnames, files in os.walk(ADDON):
            dirnames.sort()
            for name in sorted(files):
                path = os.path.join(dirpath, name)
                z.write(path, os.path.relpath(path, ROOT).replace(os.sep, "/"))
                count += 1

    release = {"releases": [{
        "name": "KEK",
        "version": version,
        "filename": zip_name,
        "nolib": False,
        "metadata": [{"flavor": "forever", "interface": 16001}],
    }]}
    with io.open(os.path.join(DIST, "release.json"), "w", encoding="utf-8") as f:
        json.dump(release, f, ensure_ascii=False, indent=2)

    notes = changelog_section(version) or "Corrections et améliorations."
    notes += (
        "\n\n---\n"
        "**Installer avec WowUp** : client « World of Warcraft: Forever », Get Addons → Install from URL → `%s`.\n"
        "**À la main** : télécharge `%s` ci-dessous et décompresse-le dans `World of Warcraft\\_forever_\\Interface\\AddOns`."
        % (REPO, zip_name)
    )
    with io.open(os.path.join(DIST, "notes.md"), "w", encoding="utf-8") as f:
        f.write(notes + "\n")
    print("%s (%d fichiers), release.json, notes.md -> dist/" % (zip_name, count))


if __name__ == "__main__":
    main()
