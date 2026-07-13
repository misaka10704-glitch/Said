#!/usr/bin/env python3
"""Simulate one Good answer on smoke apkg and re-export — verifies progress fields change."""
from __future__ import annotations

import json
import shutil
import sqlite3
import tempfile
import time
import zipfile
from pathlib import Path

SRC = Path.home() / "Downloads" / "SpeakingAnki_smoke_Pronounce.apkg"
OUT = Path.home() / "Downloads" / "SpeakingAnki_smoke_Pronounce_answered.apkg"


def main() -> None:
    assert SRC.exists(), SRC
    td = Path(tempfile.mkdtemp())
    try:
        with zipfile.ZipFile(SRC) as zf:
            zf.extractall(td)
        db = td / "collection.anki2"
        con = sqlite3.connect(db)
        row = con.execute(
            "SELECT id,type,queue,due,ivl,factor,reps,lapses,left FROM cards LIMIT 1"
        ).fetchone()
        assert row, "no cards"
        cid, typ, queue, due, ivl, factor, reps, lapses, left = row
        assert queue == 0 and typ == 0
        # Graduate-like Good on new card with single learning step → review ivl=1
        now = int(time.time())
        crt = con.execute("SELECT crt FROM col").fetchone()[0]
        today = max(0, (now - crt) // 86400)
        new_ivl = 1
        new_due = today + new_ivl
        con.execute(
            """UPDATE cards SET mod=?, type=2, queue=2, due=?, ivl=?, factor=2500, reps=reps+1, left=0 WHERE id=?""",
            (now, new_due, new_ivl, cid),
        )
        con.execute(
            """INSERT INTO revlog (id,cid,usn,ease,ivl,lastIvl,factor,time,type)
               VALUES (?,?,?,?,?,?,?,?,?)""",
            (now * 1000, cid, -1, 3, new_ivl, 0, 2500, 3000, 0),
        )
        con.execute("UPDATE col SET mod=?, usn=-1", (now,))
        con.commit()
        after = con.execute("SELECT type,queue,due,ivl,reps FROM cards WHERE id=?", (cid,)).fetchone()
        con.close()
        if OUT.exists():
            OUT.unlink()
        with zipfile.ZipFile(OUT, "w", compression=zipfile.ZIP_STORED) as zf:
            for p in td.iterdir():
                if p.is_file():
                    zf.write(p, arcname=p.name)
        print("before new/queue0 → after", after)
        print("wrote", OUT)
        assert after[0] == 2 and after[1] == 2 and after[3] == 1 and after[4] == 1
        print("progress export verify OK")
    finally:
        shutil.rmtree(td)


if __name__ == "__main__":
    main()
