#!/usr/bin/env python3
"""Garde-fou de périmètre — v2, 17/08/2026.

Refuse d'écrire dans un chemin verrouillé, déclaré dans ~/.claude/PERIMETRE.txt.
La LECTURE reste toujours permise.

CE QUI CHANGE PAR RAPPORT À LA v1 — deux faux positifs corrigés :

  1. `2>/dev/null` était lu comme une écriture. Désormais seules les vraies
     cibles de redirection comptent : `> fichier` et `>> fichier`, en ignorant
     /dev/null et les redirections de descripteurs (2>&1).

  2. Une commande entière était jugée d'un bloc : un `rm` dans un segment et le
     nom d'un verrou dans un AUTRE segment se combinaient en un refus. Désormais
     la commande est découpée sur ; && || | et chaque segment est jugé seul.

Ces deux corrections resserrent la précision SANS ouvrir de brèche : un segment
qui contient à la fois un verbe modifiant et un chemin verrouillé est toujours
refusé.
"""
import json
import os
import re
import sys

PERIMETRE = os.path.expanduser("~/.claude/PERIMETRE.txt")

VERBES = re.compile(
    r"(?:^|\s)(?:"
    r"rm|rmdir|mv|cp|dd|truncate|shred|unlink"
    r"|install|chmod|chown|chgrp|ln"
    r"|sed\s+-i|perl\s+-i"
    r"|tee|touch|mkdir"
    r"|git\s+(?:checkout|restore|reset|clean|rm|mv|stash|apply|revert)"
    r"|npm\s+(?:install|ci)|yarn|pnpm"
    r"|zip|unzip|tar|rsync|ditto"
    r")\b"
)

# Cibles réelles d'écriture : > fichier / >> fichier.
# Exclut 2>&1 (descripteur) et /dev/null (puits).
CIBLES_REDIRECTION = re.compile(r"(?<!\d)>>?\s*(?!&)([^\s;|&]+)")


def verrous():
    try:
        with open(PERIMETRE, encoding="utf-8") as f:
            lignes = f.readlines()
    except OSError:
        return []
    out = []
    for l in lignes:
        l = l.split("#", 1)[0].strip()
        if l:
            out.append(os.path.realpath(os.path.expanduser(l)))
    return out


def sous_verrou(chemin, liste):
    if not chemin:
        return None
    c = os.path.realpath(os.path.expanduser(chemin))
    for v in liste:
        if c == v or c.startswith(v + os.sep):
            return v
    return None


def nomme_un_verrou(texte, liste):
    """Le segment nomme-t-il un verrou, par chemin complet ou par nom de dossier ?"""
    for v in liste:
        base = os.path.basename(v)
        if v in texte:
            return v
        if base and re.search(r"(?<![\w.-])" + re.escape(base) + r"(?![\w-])", texte):
            return v
    return None


def refuser(verrou, quoi):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": (
                f"PÉRIMÈTRE — écriture refusée.\n"
                f"  Cible   : {quoi}\n"
                f"  Verrou  : {verrou}\n"
                f"Ce chemin est déclaré hors périmètre dans ~/.claude/PERIMETRE.txt. "
                f"La lecture reste permise ; toute modification est bloquée.\n"
                f"Si une correction y est nécessaire : la SIGNALER à Helmy et attendre sa "
                f"demande explicite. Lui seul lève le verrou, en commentant la ligne."
            ),
        }
    }))
    sys.exit(0)


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return

    liste = verrous()
    if not liste:
        return

    outil = data.get("tool_name", "")
    entree = data.get("tool_input", {}) or {}

    if outil in ("Edit", "Write", "NotebookEdit"):
        cible = entree.get("file_path") or entree.get("notebook_path")
        v = sous_verrou(cible, liste)
        if v:
            refuser(v, cible)
        return

    if outil != "Bash":
        return

    cmd = entree.get("command", "") or ""

    # ── CORRECTION 2 : chaque segment est jugé pour lui-même ──
    for segment in re.split(r"\|\||&&|[;\n|]", cmd):
        seg = segment.strip()
        if not seg:
            continue

        # ── CORRECTION 1 : seules les vraies cibles de redirection comptent ──
        for cible in CIBLES_REDIRECTION.findall(seg):
            if cible in ("/dev/null", "/dev/stdout", "/dev/stderr"):
                continue
            v = sous_verrou(cible, liste)
            if v:
                refuser(v, f"redirection vers {cible}")

        # Un verbe modifiant ET un verrou nommé, dans LE MÊME segment.
        if VERBES.search(seg):
            v = nomme_un_verrou(seg, liste)
            if v:
                refuser(v, seg[:200])


if __name__ == "__main__":
    main()
