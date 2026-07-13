#!/usr/bin/env python3
"""Create a tiny Anki-compatible .apkg for SpeakingAnki import smoke tests."""
from __future__ import annotations

import json
import sqlite3
import time
import zipfile
from pathlib import Path

OUT = Path.home() / "Downloads" / "SpeakingAnki_smoke_Pronounce.apkg"
OUT_COMPOSE = Path.home() / "Downloads" / "SpeakingAnki_smoke_Compose.apkg"


def build(path: Path, model_name: str, deck_name: str, fields: list[str], field_names: list[str]) -> None:
    staging = path.with_suffix(".staging")
    if staging.exists():
        import shutil
        shutil.rmtree(staging)
    staging.mkdir()
    db = staging / "collection.anki2"
    con = sqlite3.connect(db)
    cur = con.cursor()
    cur.executescript(
        """
        CREATE TABLE col (
          id integer primary key, crt integer, mod integer, scm integer, ver integer,
          dty integer, usn integer, ls integer, conf text, models text, decks text,
          dconf text, tags text
        );
        CREATE TABLE notes (
          id integer primary key, guid text, mid integer, mod integer, usn integer,
          tags text, flds text, sfld text, csum integer, flags integer, data text
        );
        CREATE TABLE cards (
          id integer primary key, nid integer, did integer, ord integer, mod integer,
          usn integer, type integer, queue integer, due integer, ivl integer,
          factor integer, reps integer, lapses integer, left integer, odue integer,
          odid integer, flags integer, data text
        );
        CREATE TABLE revlog (
          id integer primary key, cid integer, usn integer, ease integer, ivl integer,
          lastIvl integer, factor integer, time integer, type integer
        );
        CREATE TABLE graves (usn integer, oid integer, type integer);
        """
    )
    now = int(time.time())
    mid = 1600000000001
    did = 1600000000002
    nid = 1600000000003
    cid = 1600000000004
    models = {
        str(mid): {
            "id": mid,
            "name": model_name,
            "type": 0,
            "mod": now,
            "flds": [{"name": n, "ord": i, "sticky": False, "rtl": False, "font": "Arial", "size": 20, "media": []} for i, n in enumerate(field_names)],
            "tmpls": [{
                "name": "Card 1",
                "ord": 0,
                "qfmt": "{{" + field_names[0] + "}}",
                "afmt": "{{FrontSide}}<hr id=answer>{{" + (field_names[1] if len(field_names) > 1 else field_names[0]) + "}}",
                "bqfmt": "",
                "bafmt": "",
                "did": None,
            }],
            "css": ".card { font-family: arial; font-size: 22px; text-align: center; }",
            "req": [[0, "any", [0]]],
            "tags": [],
            "vers": [],
        }
    }
    decks = {
        "1": {"id": 1, "name": "Default", "mod": now, "usn": -1, "collapsed": False, "browserCollapsed": False, "desc": "", "dyn": 0, "conf": 1, "extendNew": 0, "extendRev": 0},
        str(did): {"id": did, "name": deck_name, "mod": now, "usn": -1, "collapsed": False, "browserCollapsed": False, "desc": "", "dyn": 0, "conf": 1, "extendNew": 10, "extendRev": 50},
    }
    dconf = {
        "1": {
            "id": 1,
            "name": "Default",
            "mod": now,
            "usn": -1,
            "maxTaken": 60,
            "autoplay": True,
            "timer": 0,
            "replayq": True,
            "new": {"delays": [1, 10], "ints": [1, 4, 0], "initialFactor": 2500, "order": 1, "perDay": 20},
            "rev": {"perDay": 200, "ease4": 1.3, "ivlFct": 1.0, "maxIvl": 36500, "hardFactor": 1.2},
            "lapse": {"delays": [10], "mult": 0, "minInt": 1, "leechFails": 8, "leechAction": 0},
        }
    }
    conf = {"activeDecks": [did], "curDeck": did, "newSpread": 0, "collapseTime": 1200, "timeLim": 0, "estTimes": True, "dueCounts": True, "sortType": "noteFld", "sortBackwards": False}
    cur.execute(
        "INSERT INTO col VALUES (1,?,?,?,11,0,0,0,?,?,?,?,?)",
        (now, now, now, json.dumps(conf), json.dumps(models), json.dumps(decks), json.dumps(dconf), json.dumps({})),
    )
    flds = "\x1f".join(fields)
    cur.execute(
        "INSERT INTO notes VALUES (?,?,?,?,?,?,?,?,?,?,?)",
        (nid, "smokeguid0001", mid, now, -1, "", flds, fields[0], 0, 0, ""),
    )
    cur.execute(
        "INSERT INTO cards VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        (cid, nid, did, 0, now, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, ""),
    )
    con.commit()
    con.close()
    (staging / "media").write_text("{}", encoding="utf-8")
    if path.exists():
        path.unlink()
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.write(db, arcname="collection.anki2")
        zf.write(staging / "media", arcname="media")
    import shutil
    shutil.rmtree(staging)
    print("wrote", path)


if __name__ == "__main__":
    build(
        OUT,
        model_name="Pronounce_Learning",
        deck_name="Pronounce_Learning::Basic",
        fields=["apple /ˈæpl/", "苹果"],
        field_names=["Front", "Back"],
    )
    build(
        OUT_COMPOSE,
        model_name="Speaking Compose",
        deck_name="English_Speaking::Compose::English_Keywords",
        fields=["join us · interested · encouraged", "en", "", "", "", ""],
        field_names=["Front", "Lang", "A", "B", "C", "Cues"],
    )
