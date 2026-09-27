"""Run from LogicTests/: python3 make_fsrs_fixtures.py (needs pip package fsrs==6.3.2)."""
"""Generate FSRS test cases from py-fsrs 6.3.2 (reference) for the Swift port."""
import json, random
from datetime import datetime, timedelta, timezone
from fsrs import Scheduler, Card, Rating, State

random.seed(20260927)
BASE = datetime(2026, 9, 27, 8, 0, 0, tzinfo=timezone.utc)
cases = []
for n in range(60):
    retention = random.choice([0.8, 0.85, 0.9, 0.9, 0.95])
    sch = Scheduler(desired_retention=retention, enable_fuzzing=False)
    card = Card(card_id=n + 1, due=BASE)
    t = BASE + timedelta(seconds=random.randint(0, 3600))
    steps = []
    for k in range(random.randint(3, 14)):
        # mostly answer when due, sometimes early or late
        if k > 0:
            mode = random.random()
            if mode < 0.6:
                t = card.due + timedelta(seconds=random.randint(0, 3 * 3600))
            elif mode < 0.8:
                t = card.due + timedelta(days=random.randint(1, 20), seconds=random.randint(0, 80000))
            else:
                t = t + timedelta(seconds=random.randint(30, 20 * 3600))
        r = random.choices([1, 2, 3, 4], weights=[2, 2, 6, 1])[0]
        card, _ = sch.review_card(card, Rating(r), review_datetime=t)
        steps.append({
            'rating': r,
            'at': t.timestamp(),
            'state': int(card.state),
            'step': card.step,
            'stability': card.stability,
            'difficulty': card.difficulty,
            'due': card.due.timestamp(),
        })
    cases.append({'retention': retention, 'start': BASE.timestamp(), 'steps': steps})
# retrievability samples
sch = Scheduler(enable_fuzzing=False)
card = Card(card_id=999, due=BASE)
card, _ = sch.review_card(card, Rating.Good, review_datetime=BASE)
card, _ = sch.review_card(card, Rating.Good, review_datetime=BASE + timedelta(minutes=11))
retr = []
for d in [0, 1, 2, 3, 5, 8, 13, 30]:
    at = BASE + timedelta(minutes=11, days=d, hours=1)
    retr.append({'at': at.timestamp(), 'r': sch.get_card_retrievability(card, current_datetime=at)})
out = {'cases': cases,
       'retrievability': {'lastReview': card.last_review.timestamp(), 'stability': card.stability,
                          'difficulty': card.difficulty, 'samples': retr},
       'intervals': [{'retention': rr, 'stability': s, 'days': Scheduler(desired_retention=rr, enable_fuzzing=False)._next_interval(stability=s)}
                     for rr in (0.8, 0.9, 0.95) for s in (0.1, 0.5, 1.0, 2.3065, 3.7, 10.0, 25.5, 100.0, 1234.5)]}
json.dump(out, open('Tests/DDULogicTests/Fixtures/fsrs_cases.json', 'w'), indent=0)
print(len(cases), sum(len(c['steps']) for c in cases))
