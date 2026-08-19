#!/usr/bin/env python3
"""Banc d'essai du garde-fou v2 — compare son verdict à ce qui est attendu."""
import json
import os
import subprocess
import sys

S = os.path.dirname(os.path.abspath(__file__))
GARDE = os.path.join(S, "garde-perimetre-v2.py")
V = os.path.expanduser("~/.claude") + os.sep + "hooks"  # le verrou, assemblé

CAS = [
    # (outil, entrée, attendu, libellé)
    ("Bash", f"grep x {V}/f.py 2>/dev/null", "AUTORISÉ", "lecture avec 2>/dev/null — v1 refusait"),
    ("Bash", f"rm -rf /tmp/zzz && grep a {V}/f.py", "AUTORISÉ", "rm ailleurs + lecture du verrou — v1 refusait"),
    ("Bash", f"ls -l {V} | head -3", "AUTORISÉ", "listage du verrou"),
    ("Bash", f"cat {V}/f.py", "AUTORISÉ", "lecture simple du verrou"),
    ("Write", "/tmp/ok.txt", "AUTORISÉ", "écriture ailleurs"),
    ("Bash", f"rm -rf {V}", "REFUSÉ", "suppression DU verrou"),
    ("Bash", f"echo x > {V}/f.py", "REFUSÉ", "redirection VERS le verrou"),
    ("Bash", f"ls && cp a.py {V}/b.py", "REFUSÉ", "copie vers le verrou, 2e segment"),
    ("Bash", f"sed -i '' s/a/b/ {V}/f.py", "REFUSÉ", "édition en place du verrou"),
    ("Write", f"{V}/x.py", "REFUSÉ", "Write dans le verrou"),
    ("Bash", f"mv {V} /tmp/ailleurs", "REFUSÉ", "déplacement du verrou"),
]

ok = 0
for outil, arg, attendu, libelle in CAS:
    entree = {"command": arg} if outil == "Bash" else {"file_path": arg}
    payload = json.dumps({"tool_name": outil, "tool_input": entree})
    r = subprocess.run([sys.executable, GARDE], input=payload, capture_output=True, text=True)
    obtenu = "REFUSÉ" if r.stdout.strip() else "AUTORISÉ"
    marque = "✅" if obtenu == attendu else "❌"
    if obtenu == attendu:
        ok += 1
    print(f"  {marque} {libelle:<48} attendu {attendu:<9} obtenu {obtenu}")

print(f"\n  {ok}/{len(CAS)} conformes")
sys.exit(0 if ok == len(CAS) else 1)
