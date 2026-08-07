#!/usr/bin/env python3
"""
Vérificateur indépendant de verdicts signés (format Nostr NIP-01 + schnorr BIP-340).

Ne dépend d'aucune bibliothèque tierce et n'appelle AUCUN service de l'émetteur :
tout est recalculé localement. Deux contrôles, dans cet ordre :

  a. l'id NIP-01 : sha256 du tableau JSON compact [0,pubkey,created_at,kind,tags,content]
     encodé UTF-8, comparé à event.id ;
  b. la signature schnorr BIP-340 (64 octets) sur cet id de 32 octets pris comme message
     brut — pas de hachage supplémentaire — avec le tag "BIP0340/challenge", contre la
     clé publique x-only.

Usage :
    python3 verify_verdict.py <fichier.json | ->      # vérifie un événement
    python3 verify_verdict.py --self-test <vectors.csv>  # vecteurs officiels BIP-340

L'entrée peut être l'événement lui-même, ou un objet qui le contient sous `proof_event`
ou `event`.
"""
import hashlib
import json
import sys

# ── secp256k1 ────────────────────────────────────────────────────────────────
P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
G = (0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798,
     0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8)


def _add(p1, p2):
    if p1 is None:
        return p2
    if p2 is None:
        return p1
    x1, y1 = p1
    x2, y2 = p2
    if x1 == x2 and y1 != y2:
        return None
    if p1 == p2:
        lam = 3 * x1 * x1 * pow(2 * y1, P - 2, P) % P
    else:
        lam = (y2 - y1) * pow(x2 - x1, P - 2, P) % P
    x3 = (lam * lam - x1 - x2) % P
    return (x3, (lam * (x1 - x3) - y1) % P)


def _mul(point, k):
    r = None
    for i in range(256):
        if (k >> i) & 1:
            r = _add(r, point)
        point = _add(point, point)
    return r


def _lift_x(x):
    """Le point de la courbe d'abscisse x et d'ordonnée PAIRE, ou None."""
    if x >= P:
        return None
    y_sq = (pow(x, 3, P) + 7) % P
    y = pow(y_sq, (P + 1) // 4, P)
    if pow(y, 2, P) != y_sq:
        return None
    return (x, y if y % 2 == 0 else P - y)


def _tagged_hash(tag: str, msg: bytes) -> bytes:
    t = hashlib.sha256(tag.encode()).digest()
    return hashlib.sha256(t + t + msg).digest()


def schnorr_verify(msg: bytes, pubkey: bytes, sig: bytes) -> bool:
    """BIP-340. `msg` est le message BRUT (ici l'id de 32 octets), pas re-haché."""
    if len(pubkey) != 32 or len(sig) != 64:
        return False
    Pt = _lift_x(int.from_bytes(pubkey, "big"))
    if Pt is None:
        return False
    r = int.from_bytes(sig[:32], "big")
    s = int.from_bytes(sig[32:], "big")
    if r >= P or s >= N:
        return False
    e = int.from_bytes(_tagged_hash("BIP0340/challenge", sig[:32] + pubkey + msg), "big") % N
    R = _add(_mul(G, s), _mul(Pt, N - e))
    if R is None or R[1] % 2 != 0 or R[0] != r:
        return False
    return True


# ── NIP-01 ───────────────────────────────────────────────────────────────────
def nip01_serialize(ev: dict) -> bytes:
    """[0, pubkey, created_at, kind, tags, content] en JSON compact, UTF-8."""
    arr = [0, ev["pubkey"], int(ev["created_at"]), int(ev["kind"]), ev["tags"], ev["content"]]
    return json.dumps(arr, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def check_event(ev: dict) -> dict:
    ser = nip01_serialize(ev)
    computed = hashlib.sha256(ser).hexdigest()
    id_ok = computed == ev["id"].lower()
    sig_ok = False
    if id_ok:
        sig_ok = schnorr_verify(bytes.fromhex(ev["id"]), bytes.fromhex(ev["pubkey"]),
                                bytes.fromhex(ev["sig"]))
    return {"id_declare": ev["id"], "id_recalcule": computed, "id_ok": id_ok,
            "schnorr_ok": sig_ok, "pubkey": ev["pubkey"],
            "serialisation_octets": len(ser)}


def extract_event(obj):
    if isinstance(obj, dict):
        for key in ("proof_event", "event"):
            if key in obj and isinstance(obj[key], dict):
                return obj[key]
        if {"id", "pubkey", "sig", "content", "tags", "kind", "created_at"} <= set(obj):
            return obj
    raise SystemExit("aucun événement Nostr trouvé dans l'entrée")


# ── auto-test sur les vecteurs officiels ─────────────────────────────────────
def self_test(path):
    import csv
    rows = list(csv.DictReader(open(path)))
    ok = bad = 0
    for r in rows:
        pk, msg, sig = r["public key"].strip(), r["message"].strip(), r["signature"].strip()
        expected = r["verification result"].strip().upper() == "TRUE"
        try:
            got = schnorr_verify(bytes.fromhex(msg), bytes.fromhex(pk), bytes.fromhex(sig))
        except Exception:
            got = False
        if got == expected:
            ok += 1
        else:
            bad += 1
            print(f"  ÉCHEC vecteur {r['index']} : attendu {expected}, obtenu {got}  ({r['comment']})")
    print(f"  vecteurs BIP-340 officiels : {ok}/{len(rows)} conformes, {bad} divergence(s)")
    return bad == 0


if __name__ == "__main__":
    if sys.argv[1] == "--self-test":
        sys.exit(0 if self_test(sys.argv[2]) else 1)
    raw = sys.stdin.read() if sys.argv[1] == "-" else open(sys.argv[1]).read()
    ev = extract_event(json.loads(raw))
    res = check_event(ev)
    print(f"  pubkey du signataire : {res['pubkey']}")
    print(f"  id déclaré           : {res['id_declare']}")
    print(f"  id recalculé         : {res['id_recalcule']}")
    print(f"  (a) id NIP-01        : {'OK' if res['id_ok'] else 'KO'}")
    print(f"  (b) schnorr BIP-340  : {'OK' if res['schnorr_ok'] else 'KO'}")
    print(f"  préimage sérialisée  : {res['serialisation_octets']} octets")
    sys.exit(0 if res["id_ok"] and res["schnorr_ok"] else 1)
