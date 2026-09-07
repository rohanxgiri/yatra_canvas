# Five-day planner example

Actual synthetic solver output; 15 selected places, 15-minute matrix legs, 5.012s solve.

Vehicle 0 = Day 1; vehicle 1 = Day 3; vehicle 2 = Day 4. Days 2 and 5 remain REST.

Visit durations use the existing category estimator. All scheduled stops in this fixture have UNKNOWN hours and remain unverified.

## Day 1: FULL_DAY

| Time | Stop | Category |
| --- | --- | --- |
| 09:15–10:00 | Place 6 | monument |
| 10:15–11:00 | Place 5 | cafe |
| 11:15–12:00 | Place 4 | religious |
| 12:15–13:00 | Place 13 | cafe |
| 13:00–14:00 | Lunch | — |
| 14:15–15:45 | Place 2 | museum |
| 16:00–18:00 | Place 1 | heritage |

## Day 2: REST

REST

## Day 3: FULL_DAY

| Time | Stop | Category |
| --- | --- | --- |
| 10:15–12:15 | Place 11 | heritage |
| 12:30–13:30 | Place 3 | park |
| 13:30–14:30 | Lunch | — |
| 14:45–15:45 | Place 8 | park |
| 16:00–17:30 | Place 7 | museum |

## Day 4: HALF_DAY

| Time | Stop | Category |
| --- | --- | --- |
| 09:15–10:30 | Place 9 | market |
| 10:45–11:45 | Place 12 | park |
| 12:00–12:45 | Place 10 | religious |
| 12:45–13:45 | Lunch | — |

## Day 5: REST

REST

## Unscheduled

| Place | Reason |
| --- | --- |
| Place 14 | CLOSED_ON_AVAILABLE_DAYS |
| Place 15 | LOCKED_DAY_INFEASIBLE |
