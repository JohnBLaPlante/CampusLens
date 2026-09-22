# Academic policy conventions (demo institution)

> Policy excerpt for demonstration purposes; synthetic institution.

## Satisfactory Academic Progress (SAP)

A student is placed on **academic probation** when their term GPA falls
below 2.0 (`TERM_GPA < 2.0` in TERMGPA), flagged with `EVENT_TYPE =
'PROBATION'` in ACAE.

A student is **academically dismissed** after two consecutive terms of
probation, flagged with `EVENT_TYPE = 'DISMISSAL'` in ACAE. A dismissed
student's TERMGPA record ends at the term of dismissal.

## Attrition

**Attrition** means a student left before completing all 8 tracked terms
without graduating, via either:

- **voluntary withdrawal** (`EVENT_TYPE = 'WITHDRAWAL'` in ACAE,
  `FINAL_STATUS = 'WITHDRAWN'` in STUSL), or
- **academic dismissal** (`FINAL_STATUS = 'DISMISSED'` in STUSL).

## Term-numbering convention

Terms 1-8 span 4 academic years, two terms (fall, spring) per year: Year 1
= terms 1-2, Year 2 = terms 3-4, Year 3 = terms 5-6, Year 4 = terms 7-8.
"First-year attrition" means an attrition event with `TIME <= 2`.

## Leave of absence and advising flags

A leave of absence (`EVENT_TYPE = 'LOA'`) and an advising flag
(`EVENT_TYPE = 'ADVISING_FLAG'`) are recorded independently of GPA and do
not by themselves end enrollment.

## Denominators

Percentages by program use the number of students in STUSL for that
program as the denominator, unless a measure states otherwise.

## Exploratory analyses

Any analysis not covered by a validated measure in `measures/retention.R`
is exploratory. Exploratory results should be reviewed by institutional
research staff before being shared outside the team.
