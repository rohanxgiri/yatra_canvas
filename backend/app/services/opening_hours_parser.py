"""Opening-hours parsing, normalization, and time-evaluation service.

Parses OSM and Geoapify opening_hours strings into normalized daily intervals,
distinguishing KNOWN, CLOSED, and UNKNOWN states.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta
from enum import Enum
from typing import Any

logger = logging.getLogger(__name__)


class OpeningHoursStatus(str, Enum):
    KNOWN = "KNOWN"
    CLOSED = "CLOSED"
    UNKNOWN = "UNKNOWN"


DAY_NAMES: dict[int, str] = {
    0: "monday",
    1: "tuesday",
    2: "wednesday",
    3: "thursday",
    4: "friday",
    5: "saturday",
    6: "sunday",
}

NAME_TO_DAY: dict[str, int] = {
    "mo": 0,
    "mon": 0,
    "monday": 0,
    "tu": 1,
    "tue": 1,
    "tues": 1,
    "tuesday": 1,
    "we": 2,
    "wed": 2,
    "wednesday": 2,
    "th": 3,
    "thu": 3,
    "thur": 3,
    "thurs": 3,
    "thursday": 3,
    "fr": 4,
    "fri": 4,
    "friday": 4,
    "sa": 5,
    "sat": 5,
    "saturday": 5,
    "su": 6,
    "sun": 6,
    "sunday": 6,
}


@dataclass(frozen=True, slots=True)
class TimeInterval:
    """A closed/half-open daily time interval in 24-hour HH:MM format."""

    open: str
    close: str

    def to_dict(self) -> dict[str, str]:
        return {"open": self.open, "close": self.close}

    def open_time(self) -> time:
        parts = self.open.split(":")
        h = 23 if parts[0] == "24" else int(parts[0])
        m = 59 if parts[0] == "24" else int(parts[1])
        return time(h, m)

    def close_time(self) -> time:
        parts = self.close.split(":")
        h = 23 if parts[0] == "24" else int(parts[0])
        m = 59 if parts[0] == "24" else int(parts[1])
        return time(h, m)

    def contains_time(self, t: time) -> bool:
        """Check if time t falls within [open, close]."""
        ot = self.open_time()
        ct = self.close_time()
        if self.close == "24:00":
            return t >= ot
        if ot <= ct:
            return ot <= t <= ct
        # Overnight window
        return t >= ot or t <= ct

    def contains_range(self, start_t: time, end_t: time) -> bool:
        """Check if [start_t, end_t] is completely contained within the interval."""
        if start_t > end_t:
            return False
        ot = self.open_time()
        ct = self.close_time()
        if self.close == "24:00":
            return start_t >= ot
        if ot <= ct:
            return ot <= start_t and end_t <= ct
        # Overnight window
        return (start_t >= ot and end_t >= ot and start_t <= end_t) or (
            start_t <= ct and end_t <= ct and start_t <= end_t
        )


@dataclass
class DaySchedule:
    day_of_week: int
    day_name: str
    status: OpeningHoursStatus = OpeningHoursStatus.UNKNOWN
    intervals: list[TimeInterval] = field(default_factory=list)

    def intervals_dicts(self) -> list[dict[str, str]]:
        return [i.to_dict() for i in self.intervals]


@dataclass
class NormalizedOpeningHours:
    status: OpeningHoursStatus
    raw_text: str | None
    days: dict[int, DaySchedule]

    def to_dict(self) -> dict[str, list[dict[str, str]]]:
        """Expose mapping of day_name -> list of interval dicts for PlaceRead response."""
        return {
            day.day_name: day.intervals_dicts()
            for day in self.days.values()
        }

    def is_open_at(self, dt: datetime) -> bool | None:
        """Check if open at given datetime. Returns None if UNKNOWN."""
        day = self.days[dt.weekday()]
        if day.status == OpeningHoursStatus.UNKNOWN:
            return None
        if day.status == OpeningHoursStatus.CLOSED:
            return False
        t = dt.time()
        return any(interval.contains_time(t) for interval in day.intervals)

    def can_visit_between(
        self, start_dt: datetime, end_dt: datetime
    ) -> bool | None:
        """Check if place can accommodate a visit between start_dt and end_dt. Returns None if UNKNOWN."""
        if start_dt > end_dt:
            return False
        if start_dt.date() != end_dt.date():
            # Spans midnight
            return None
        day = self.days[start_dt.weekday()]
        if day.status == OpeningHoursStatus.UNKNOWN:
            return None
        if day.status == OpeningHoursStatus.CLOSED:
            return False
        st = start_dt.time()
        et = end_dt.time()
        return any(interval.contains_range(st, et) for interval in day.intervals)

    def get_intervals_for_day(
        self, day: int | date | datetime
    ) -> list[TimeInterval]:
        idx = day if isinstance(day, int) else day.weekday()
        return list(self.days[idx].intervals)

    def get_next_opening(self, dt: datetime) -> datetime | None:
        """Find the next opening instant on or after dt up to 7 days ahead. Returns None if UNKNOWN."""
        if self.status == OpeningHoursStatus.UNKNOWN:
            return None
        for offset in range(8):
            curr_date = dt.date() + timedelta(days=offset)
            weekday_idx = curr_date.weekday()
            day = self.days[weekday_idx]
            if day.status == OpeningHoursStatus.CLOSED:
                continue
            for interval in day.intervals:
                parts = interval.open.split(":")
                h = 23 if parts[0] == "24" else int(parts[0])
                m = 59 if parts[0] == "24" else int(parts[1])
                opening_dt = datetime.combine(
                    curr_date, time(h, m), tzinfo=dt.tzinfo
                )
                if opening_dt > dt:
                    return opening_dt
        return None


class OpeningHoursParser:
    """Parser for OpenStreetMap and Geoapify opening_hours format."""

    _DAY_TOKENS = r"(?:Mo|Tu|We|Th|Fr|Sa|Su|Mon|Tue|Wed|Thu|Fri|Sat|Sun|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)"
    _DAY_PREFIX_RE = re.compile(
        rf"^(?P<days>(?:{_DAY_TOKENS}(?:\s*-\s*{_DAY_TOKENS})?(?:\s*,\s*)?)+)\s*(?::|\s)\s*(?P<hours>.+)$",
        re.IGNORECASE,
    )
    _INTERVAL_RE = re.compile(r"(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})")

    @classmethod
    def _add_interval(
        cls, day_schedule: DaySchedule, interval: TimeInterval
    ) -> None:
        day_schedule.status = OpeningHoursStatus.KNOWN
        existing_tuples = {(i.open, i.close) for i in day_schedule.intervals}
        if (interval.open, interval.close) not in existing_tuples:
            day_schedule.intervals.append(interval)
            day_schedule.intervals.sort(key=lambda i: i.open)

    @classmethod
    def parse(cls, raw: str | None) -> NormalizedOpeningHours:
        """Parse raw provider opening_hours string into a NormalizedOpeningHours structure."""
        if not raw or not isinstance(raw, str) or not raw.strip():
            return cls._empty_unknown(None)

        raw_str = raw.strip()
        lower = raw_str.casefold()

        # Quick exact matches
        if lower in {"24/7", "open 24/7", "all day"}:
            return cls._all_days(
                OpeningHoursStatus.KNOWN,
                [TimeInterval(open="00:00", close="24:00")],
                raw_str,
            )

        if lower in {"closed", "off"}:
            return cls._all_days(OpeningHoursStatus.CLOSED, [], raw_str)

        days: dict[int, DaySchedule] = {
            i: DaySchedule(day_of_week=i, day_name=DAY_NAMES[i])
            for i in range(7)
        }

        # Rule blocks separated by semicolons or newlines
        blocks = [b.strip() for b in re.split(r"[;\n]+", raw_str) if b.strip()]
        any_parsed = False

        for block in blocks:
            try:
                parsed_block = cls._parse_block(block)
                if not parsed_block:
                    continue

                target_days, status, intervals = parsed_block
                any_parsed = True
                for d in target_days:
                    if status == OpeningHoursStatus.CLOSED:
                        days[d].status = OpeningHoursStatus.CLOSED
                        days[d].intervals.clear()
                    elif status == OpeningHoursStatus.KNOWN:
                        for inter in intervals:
                            if cls._is_overnight(inter.open, inter.close):
                                # Day d gets inter.open to 24:00
                                cls._add_interval(
                                    days[d],
                                    TimeInterval(open=inter.open, close="24:00"),
                                )
                                # Day (d + 1) % 7 gets 00:00 to inter.close
                                next_d = (d + 1) % 7
                                cls._add_interval(
                                    days[next_d],
                                    TimeInterval(open="00:00", close=inter.close),
                                )
                            else:
                                cls._add_interval(days[d], inter)
            except Exception as exc:
                logger.debug(
                    "OpeningHoursParser encountered unparseable block '%s': %s",
                    block,
                    exc,
                )

        if not any_parsed:
            return cls._empty_unknown(raw_str)

        # For any day that wasn't mentioned in the schedule, mark as CLOSED with no intervals
        for d in days.values():
            if d.status == OpeningHoursStatus.UNKNOWN:
                d.status = OpeningHoursStatus.CLOSED
                d.intervals.clear()

        # Determine overall status
        statuses = {d.status for d in days.values()}
        if OpeningHoursStatus.KNOWN in statuses:
            overall_status = OpeningHoursStatus.KNOWN
        elif statuses == {OpeningHoursStatus.CLOSED}:
            overall_status = OpeningHoursStatus.CLOSED
        else:
            overall_status = OpeningHoursStatus.UNKNOWN

        return NormalizedOpeningHours(
            status=overall_status,
            raw_text=raw_str,
            days=days,
        )

    @classmethod
    def _parse_block(
        cls, block: str
    ) -> tuple[list[int], OpeningHoursStatus, list[TimeInterval]] | None:
        block = block.strip()
        if not block:
            return None

        # Check for explicit day prefix e.g. "Mo-Fr 09:00-18:00" or "Su off"
        match = cls._DAY_PREFIX_RE.match(block)
        if match:
            days_spec = match.group("days").strip()
            hours_spec = match.group("hours").strip()
            target_days = cls._expand_days(days_spec)
        else:
            # Check if entire block is hours e.g. "09:00-18:00"
            hours_spec = block
            target_days = list(range(7))

        if not target_days:
            return None

        lower_hours = hours_spec.casefold()
        if lower_hours in {"off", "closed"}:
            return target_days, OpeningHoursStatus.CLOSED, []

        intervals = cls._parse_intervals(hours_spec, target_days)
        if not intervals:
            return None

        return target_days, OpeningHoursStatus.KNOWN, intervals

    @classmethod
    def _expand_days(cls, days_spec: str) -> list[int]:
        """Expand day expressions like 'Mo-Fr', 'Sa,Su', 'Mo,We,Fr' into a list of day indices (0..6)."""
        result: list[int] = []
        parts = [p.strip() for p in days_spec.split(",") if p.strip()]
        for part in parts:
            if "-" in part:
                tokens = [t.strip().casefold() for t in part.split("-")]
                if len(tokens) == 2 and tokens[0] in NAME_TO_DAY and tokens[1] in NAME_TO_DAY:
                    start_idx = NAME_TO_DAY[tokens[0]]
                    end_idx = NAME_TO_DAY[tokens[1]]
                    if start_idx <= end_idx:
                        for d in range(start_idx, end_idx + 1):
                            if d not in result:
                                result.append(d)
                    else:
                        # Wrap-around e.g. Fr-Mo (4, 5, 6, 0)
                        curr = start_idx
                        while True:
                            if curr not in result:
                                result.append(curr)
                            if curr == end_idx:
                                break
                            curr = (curr + 1) % 7
            else:
                token = part.casefold()
                if token in NAME_TO_DAY and NAME_TO_DAY[token] not in result:
                    result.append(NAME_TO_DAY[token])
        return result

    @classmethod
    def _parse_intervals(
        cls, hours_spec: str, target_days: list[int]
    ) -> list[TimeInterval]:
        """Extract and normalize time intervals from string like '09:00-11:00, 14:00-22:00'."""
        intervals: list[TimeInterval] = []
        matches = list(cls._INTERVAL_RE.finditer(hours_spec))
        if not matches:
            return []

        for m in matches:
            open_str = cls._format_time(m.group(1))
            close_str = cls._format_time(m.group(2))
            if not open_str or not close_str:
                continue

            intervals.append(TimeInterval(open=open_str, close=close_str))

        return intervals

    @staticmethod
    def _format_time(t_str: str) -> str | None:
        try:
            parts = t_str.split(":")
            h = int(parts[0])
            m = int(parts[1])
            if (h == 24 and m == 0) or (0 <= h < 24 and 0 <= m < 60):
                return f"{h:02d}:{m:02d}"
        except (ValueError, IndexError):
            pass
        return None

    @staticmethod
    def _is_overnight(open_str: str, close_str: str) -> bool:
        try:
            oh, om = [int(p) for p in open_str.split(":")]
            ch, cm = [int(p) for p in close_str.split(":")]
            return (ch, cm) < (oh, om)
        except Exception:
            return False

    @classmethod
    def _all_days(
        cls, status: OpeningHoursStatus, intervals: list[TimeInterval], raw_text: str
    ) -> NormalizedOpeningHours:
        days: dict[int, DaySchedule] = {
            i: DaySchedule(
                day_of_week=i,
                day_name=DAY_NAMES[i],
                status=status,
                intervals=list(intervals),
            )
            for i in range(7)
        }
        return NormalizedOpeningHours(
            status=status,
            raw_text=raw_text,
            days=days,
        )

    @classmethod
    def _empty_unknown(cls, raw_text: str | None) -> NormalizedOpeningHours:
        days: dict[int, DaySchedule] = {
            i: DaySchedule(
                day_of_week=i,
                day_name=DAY_NAMES[i],
                status=OpeningHoursStatus.UNKNOWN,
                intervals=[],
            )
            for i in range(7)
        }
        return NormalizedOpeningHours(
            status=OpeningHoursStatus.UNKNOWN,
            raw_text=raw_text,
            days=days,
        )
