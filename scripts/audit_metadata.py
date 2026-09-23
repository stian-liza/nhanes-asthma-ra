"""Audit required metadata without downloading or modeling participant records.

This is a coverage check, not an automatic semantic/approval gate.
"""
import csv
import hashlib
import json
import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]


def includes_age(target, age=20):
    match = re.search(r'(\d+) YEARS - (\d+) YEARS', target)
    if not match:
        return None
    return int(match[1]) <= age <= int(match[2])


def ra_code(row):
    codes = [v['code'] for v in json.loads(row['values_json'])
             if 'rheumatoid' in v['label'].lower()]
    if len(codes) != 1:
        raise ValueError('RA value label not uniquely identified')
    return codes[0]


def audit(rows):
    result = []
    for year in range(1999, 2019, 2):
        cycle = f'{year}-{year+1}'
        lookup = {r['variable'].upper(): r for r in rows if r['cycle'] == cycle}
        required = ['SEQN', 'RIDAGEYR', 'RIAGENDR', 'RIDRETH1', 'DMDEDUC2',
                    'INDFMPIR', 'SDDSRVYR', 'SDMVSTRA', 'SDMVPSU', 'WTINT2YR',
                    'MCQ010', 'MCQ160A', 'SMQ020', 'SMQ040']
        missing = [v for v in required if v not in lookup]
        current = next((lookup[k] for k in ['MCQ035', 'MCQ030'] if k in lookup), None)
        arthritis = next((lookup[k] for k in ['MCQ195', 'MCQ191', 'MCQ190'] if k in lookup), None)
        if current is None:
            missing.append('current_asthma_question')
        if arthritis is None:
            missing.append('arthritis_type_question')
        adult = includes_age(current['target']) if current else None
        eligibility = [includes_age(lookup[k]['target']) for k in required
                       if k in lookup and k != 'SEQN']
        if arthritis:
            eligibility.append(includes_age(arthritis['target']))
        can_cover = not missing and adult is True and all(v is True for v in eligibility)
        result.append(dict(cycle=cycle,current_variable=current['variable'] if current else '',
                           current_target=current['target'] if current else '',
                           current_includes_age20=adult,
                           arthritis_variable=arthritis['variable'] if arthritis else '',
                           ra_positive_code=ra_code(arthritis) if arthritis else '',
                           missing_required=';'.join(missing),
                           required_fields_include_age20=all(v is True for v in eligibility),
                           adult_current_coverage_verdict='pass' if can_cover else 'revise'))
    return result


def main():
    source = REPO/'docs/data/variable_dictionary.csv'
    with source.open() as f:
        coverage = audit(list(csv.DictReader(f)))
    with (source.parent/'cycle_coverage.csv').open('w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=list(coverage[0]), lineterminator='\n')
        writer.writeheader(); writer.writerows(coverage)
    failed = [r['cycle'] for r in coverage if r['adult_current_coverage_verdict'] != 'pass']
    sha = hashlib.sha256(source.read_bytes()).hexdigest()
    existing_file=source.parent/'metadata_review.json'
    existing=json.loads(existing_file.read_text()) if existing_file.exists() else {}
    retain_approval=(existing.get('approved_plan')=='v0.3' and
                     existing.get('primary_download_verdict')=='pass' and
                     existing.get('dictionary_sha256')==sha and
                     failed==['1999-2000'])
    review = dict(
        primary_download_verdict='revise' if failed else 'needs evidence',
        approved_plan='v0.2',
        checked='30 official codebooks; required fields, age-20 coverage, arthritis value labels',
        failed_cycles=failed,
        weak_point='Coverage is not full semantic review, clinical validity, sample-size or novelty validation.',
        next_move='Resolve and approve documented scope amendment before participant-data acquisition.',
        dictionary_sha256=sha,
        automatic_gate_can_authorize_download=False)
    if retain_approval:
        review=existing
    (source.parent/'metadata_review.json').write_text(json.dumps(review,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(review, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
