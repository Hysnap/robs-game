#!/usr/bin/env python3
"""Build a Markdown relationship tree from the RobsGame SQLite society database.

The report treats social_relationships as directed edges and renders both
directions. Work friends are derived from active livelihood contracts sharing
the same employer_entity_id; they are not assumed to be social_relationships
edges because the database stores those concepts separately.
"""

from __future__ import annotations

import argparse
import os
import sqlite3
from pathlib import Path
from typing import Iterable, Sequence


DEFAULT_DB = r"D:\Users\pgold\AppData\Roaming\Godot\app_userdata\RobsGame\game_society.db"
FAMILY_CODES = ("FAMILY", "SPOUSE", "EXTENDED_FAMILY")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", default=os.environ.get("ROBS_GAME_DB", DEFAULT_DB))
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--resident-id", type=int)
    target.add_argument("--name", help="Exact first-name/current-surname match.")
    parser.add_argument("--out", type=Path, help="Markdown output path.")
    parser.add_argument(
        "--max-relationships-per-person",
        type=int,
        default=0,
        help="Limit expanded relationships per person; 0 means no limit.",
    )
    return parser.parse_args()


def connect(db_path: str) -> sqlite3.Connection:
    path = Path(db_path)
    if not path.is_file():
        raise FileNotFoundError(f"SQLite database not found: {path}")
    connection = sqlite3.connect(path)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA query_only = ON")
    return connection


def resident_name(row: sqlite3.Row) -> str:
    return f"{row['first_name']} {row['current_surname']}"


def markdown(value: object) -> str:
    return str(value if value is not None else "—").replace("|", "\\|")


def get_root(connection: sqlite3.Connection, args: argparse.Namespace) -> sqlite3.Row:
    if args.resident_id is not None:
        row = connection.execute(
            """
            SELECT r.resident_id, r.first_name, r.current_surname,
                   r.birth_surname, r.dob, r.dod, r.household_id,
                   d.display_name AS district_name,
                   e.establishment_id AS home_establishment_id,
                   e.name AS home_name
            FROM residents r
            LEFT JOIN households h ON h.household_id = r.household_id
            LEFT JOIN establishments e ON e.establishment_id = h.establishment_id
            LEFT JOIN districts d ON d.district_id = e.district_id
            WHERE r.resident_id = ?
            """,
            (args.resident_id,),
        ).fetchone()
    else:
        parts = args.name.strip().split(maxsplit=1)
        if len(parts) != 2:
            raise ValueError("--name must contain first name and current surname")
        row = connection.execute(
            """
            SELECT r.resident_id, r.first_name, r.current_surname,
                   r.birth_surname, r.dob, r.dod, r.household_id,
                   d.display_name AS district_name,
                   e.establishment_id AS home_establishment_id,
                   e.name AS home_name
            FROM residents r
            LEFT JOIN households h ON h.household_id = r.household_id
            LEFT JOIN establishments e ON e.establishment_id = h.establishment_id
            LEFT JOIN districts d ON d.district_id = e.district_id
            WHERE r.first_name = ? AND r.current_surname = ?
            ORDER BY r.resident_id
            LIMIT 1
            """,
            tuple(parts),
        ).fetchone()
    if row is None:
        raise LookupError("No matching resident was found.")
    return row


def get_contracts(
    connection: sqlite3.Connection, resident_ids: Iterable[int]
) -> dict[int, list[sqlite3.Row]]:
    ids = sorted(set(resident_ids))
    if not ids:
        return {}
    placeholders = ",".join("?" for _ in ids)
    rows = connection.execute(
        f"""
        SELECT c.resident_id, c.contract_id, c.employer_entity_id,
               COALESCE(e.name, c.employer_entity_id) AS employer_name,
               l_class.code AS contract_class_code,
               l_class.title AS contract_class_title,
               l_role.code AS role_code, l_role.title AS role_title,
               l_type.title AS contract_type, c.schedule_window,
               c.weekly_hours, c.compensation_rate
        FROM livelihood_contracts c
        LEFT JOIN establishments e
          ON e.establishment_id = CAST(REPLACE(c.employer_entity_id, 'ESTAB_', '') AS INTEGER)
        LEFT JOIN system_labels l_class ON l_class.label_id = c.contract_class_id
        LEFT JOIN system_labels l_role ON l_role.label_id = c.role_title_id
        LEFT JOIN system_labels l_type ON l_type.label_id = c.contract_type_id
        WHERE c.valid_to IS NULL AND c.resident_id IN ({placeholders})
        ORDER BY c.resident_id, c.contract_id
        """,
        ids,
    ).fetchall()
    result: dict[int, list[sqlite3.Row]] = {resident_id: [] for resident_id in ids}
    for row in rows:
        result[row["resident_id"]].append(row)
    return result


def get_family(
    connection: sqlite3.Connection, root_id: int
) -> list[sqlite3.Row]:
    return connection.execute(
        """
        SELECT DISTINCT
               CASE WHEN s.from_resident_id = ? THEN s.to_resident_id
                    ELSE s.from_resident_id END AS resident_id,
               r.first_name, r.current_surname,
               l.code AS relationship_code, l.title AS relationship_title,
               s.affinity_score
        FROM social_relationships s
        JOIN residents r
          ON r.resident_id = CASE WHEN s.from_resident_id = ? THEN s.to_resident_id
                                  ELSE s.from_resident_id END
        JOIN system_labels l ON l.label_id = s.relationship_type_id
        WHERE (s.from_resident_id = ? OR s.to_resident_id = ?)
          AND s.valid_to IS NULL
          AND l.domain = 'RELATIONSHIP_TYPE'
          AND l.code IN ('FAMILY', 'SPOUSE', 'EXTENDED_FAMILY')
        ORDER BY l.code, r.current_surname, r.first_name, r.resident_id
        """,
        (root_id, root_id, root_id, root_id),
    ).fetchall()


def get_work_friends(
    connection: sqlite3.Connection, root_id: int, root_contracts: list[sqlite3.Row]
) -> list[sqlite3.Row]:
    employer_ids = sorted({row["employer_entity_id"] for row in root_contracts})
    if not employer_ids:
        return []
    placeholders = ",".join("?" for _ in employer_ids)
    return connection.execute(
        f"""
        SELECT DISTINCT r.resident_id, r.first_name, r.current_surname,
               c.employer_entity_id,
               COALESCE(e.name, c.employer_entity_id) AS employer_name,
               l_class.code AS contract_class_code,
               l_class.title AS contract_class_title,
               l_role.title AS role_title, l_type.title AS contract_type,
               c.schedule_window, c.weekly_hours, c.compensation_rate
        FROM livelihood_contracts c
        JOIN residents r ON r.resident_id = c.resident_id
        LEFT JOIN establishments e
          ON e.establishment_id = CAST(REPLACE(c.employer_entity_id, 'ESTAB_', '') AS INTEGER)
        LEFT JOIN system_labels l_class ON l_class.label_id = c.contract_class_id
        LEFT JOIN system_labels l_role ON l_role.label_id = c.role_title_id
        LEFT JOIN system_labels l_type ON l_type.label_id = c.contract_type_id
        WHERE c.valid_to IS NULL AND r.dod IS NULL
          AND c.employer_entity_id IN ({placeholders})
          AND c.resident_id != ?
        ORDER BY employer_name, r.current_surname, r.first_name, r.resident_id
        """,
        (*employer_ids, root_id),
    ).fetchall()


def get_relationships(
    connection: sqlite3.Connection,
    resident_ids: Sequence[int],
    max_per_person: int,
) -> dict[int, list[sqlite3.Row]]:
    ids = sorted(set(resident_ids))
    if not ids:
        return {}
    placeholders = ",".join("?" for _ in ids)
    rows = connection.execute(
        f"""
        SELECT s.from_resident_id, s.to_resident_id,
               s.subject_id,
               CASE WHEN s.from_resident_id = s.subject_id THEN 'outgoing'
                    ELSE 'incoming' END AS direction,
               other.first_name || ' ' || other.current_surname AS other_name,
               other.resident_id AS other_resident_id,
               l.code AS relationship_code, l.title AS relationship_title,
               ROUND(s.affinity_score, 2) AS affinity_score
        FROM (
            SELECT sr.*, sr.from_resident_id AS subject_id
            FROM social_relationships sr
            WHERE sr.from_resident_id IN ({placeholders}) AND sr.valid_to IS NULL
            UNION ALL
            SELECT sr.*, sr.to_resident_id AS subject_id
            FROM social_relationships sr
            WHERE sr.to_resident_id IN ({placeholders}) AND sr.valid_to IS NULL
        ) s
        JOIN residents other
          ON other.resident_id = CASE WHEN s.from_resident_id = s.subject_id
                                      THEN s.to_resident_id
                                      ELSE s.from_resident_id END
        JOIN system_labels l ON l.label_id = s.relationship_type_id
        ORDER BY s.subject_id, l.code, other.current_surname, other.first_name
        """,
        (*ids, *ids),
    ).fetchall()
    result: dict[int, list[sqlite3.Row]] = {resident_id: [] for resident_id in ids}
    for row in rows:
        if max_per_person and len(result[row["subject_id"]]) >= max_per_person:
            continue
        result[row["subject_id"]].append(row)
    return result


def render_contracts(rows: list[sqlite3.Row]) -> list[str]:
    if not rows:
        return ["- No active contract recorded."]
    return [
        "- `%s` — %s; %s; %s; %.1f hrs/week at %.2f"
        % (
            markdown(row["employer_name"]),
            markdown(row["role_title"]),
            markdown(row["contract_class_title"]),
            markdown(row["contract_type"]),
            row["weekly_hours"],
            row["compensation_rate"],
        )
        for row in rows
    ]


def render_direct_relationships(
    lines: list[str], title: str, ids: Iterable[int], people: dict[int, str],
    relationships: dict[int, list[sqlite3.Row]],
) -> None:
    lines.append(f"## Direct relationships of {title}")
    for resident_id in ids:
        lines.append(f"### {people[resident_id]} (resident #{resident_id})")
        rows = relationships.get(resident_id, [])
        if not rows:
            lines.append("- No active social relationships recorded.")
            continue
        for row in rows:
            lines.append(
                "- **%s** %s `%s` — affinity %s"
                % (
                    markdown(row["direction"]),
                    markdown(row["other_name"]),
                    markdown(row["relationship_code"]),
                    markdown(row["affinity_score"]),
                )
            )


def build_report(connection: sqlite3.Connection, args: argparse.Namespace) -> str:
    root = get_root(connection, args)
    root_id = root["resident_id"]
    root_contracts = get_contracts(connection, [root_id]).get(root_id, [])
    family = get_family(connection, root_id)
    work_friends = get_work_friends(connection, root_id, root_contracts)

    family_ids = [row["resident_id"] for row in family]
    work_ids = [row["resident_id"] for row in work_friends]
    expanded_ids = list(dict.fromkeys(family_ids + work_ids))
    people = {
        root_id: resident_name(root),
        **{
            row["resident_id"]: f"{row['first_name']} {row['current_surname']}"
            for row in family
        },
        **{
            row["resident_id"]: f"{row['first_name']} {row['current_surname']}"
            for row in work_friends
        },
    }
    contracts = get_contracts(connection, expanded_ids)
    relationships = get_relationships(
        connection, [root_id, *expanded_ids], args.max_relationships_per_person
    )

    lines = [
        f"# Relationship tree: {markdown(people[root_id])} (resident #{root_id})",
        "",
        "Generated from the active rows in `residents`, `social_relationships`, "
        "and `livelihood_contracts`.",
        "",
        "## Resident",
        f"- **Name:** {markdown(people[root_id])}",
        f"- **Resident ID:** `{root_id}`",
        f"- **Birth surname:** {markdown(root['birth_surname'])}",
        f"- **Status:** {'deceased' if root['dod'] is not None else 'living'}",
        f"- **Home:** {markdown(root['home_name'])} ({markdown(root['district_name'])})",
        "",
        "### Active contracts",
        *render_contracts(root_contracts),
        "",
        "## Resident's direct social relationships",
    ]
    for row in relationships.get(root_id, []):
        lines.append(
            "- **%s** %s `%s` — affinity %s"
            % (
                markdown(row["direction"]),
                markdown(row["other_name"]),
                markdown(row["relationship_code"]),
                markdown(row["affinity_score"]),
            )
        )
    if not relationships.get(root_id):
        lines.append("- No active social relationships recorded.")

    lines.extend(
        [
            "",
        "## Direct family",
        ]
    )
    if not family:
        lines.append("- No active family relationship recorded.")
    for row in family:
        lines.append(
            "- **%s** — %s; affinity %s (resident #%s)"
            % (
                markdown(f"{row['first_name']} {row['current_surname']}"),
                markdown(row["relationship_title"]),
                markdown(row["affinity_score"]),
                row["resident_id"],
            )
        )
        lines.extend(f"  {line}" for line in render_contracts(contracts[row["resident_id"]]))

    lines.extend(["", "## Work friends (shared active employer contracts)"])
    if not work_friends:
        lines.append("- No active coworkers found for the resident's contracts.")
    for row in work_friends:
        lines.append(
            "- **%s** — %s at `%s`; %s; resident #%s"
            % (
                markdown(f"{row['first_name']} {row['current_surname']}"),
                markdown(row["role_title"]),
                markdown(row["employer_name"]),
                markdown(row["contract_class_title"]),
                row["resident_id"],
            )
        )
        lines.extend(f"  {line}" for line in render_contracts(contracts[row["resident_id"]]))

    render_direct_relationships(
        lines, "family and work friends", expanded_ids, people, relationships
    )
    lines.extend(
        [
            "",
            "## Interpretation",
            "- Family is taken from active `FAMILY`, `SPOUSE`, and `EXTENDED_FAMILY` edges in either direction.",
            "- Work friends are all other living residents with an active contract at any employer shared by the resident.",
            "- Direct relationship lists include both outgoing and incoming social edges, because `social_relationships` is directed.",
            "- Contract rows are limited to `valid_to IS NULL`; historical contracts are excluded.",
        ]
    )
    if args.max_relationships_per_person:
        lines.insert(
            -1,
            "- Expanded relationship sections are limited to "
            f"{args.max_relationships_per_person} edges per person for this report.",
        )
    return "\n".join(lines) + "\n"


def main() -> int:
    args = parse_args()
    with connect(args.db) as connection:
        report = build_report(connection, args)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(report, encoding="utf-8")
        print(f"Wrote {args.out}")
    else:
        print(report, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
