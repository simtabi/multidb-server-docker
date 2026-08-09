#!/usr/bin/env bash
# verify: every vulnerability waiver is scoped, justified, and expires
# tags: fast security
# phase: 1

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cd "$MDB_ROOT" || exit 1

# SPEC section 18, criterion 11b: "trivy clean or waived with notes".
#
# The "with notes" half is the part that decays. A scanner is easy to make green
# by pasting IDs into an ignore file, and six months later nobody can tell which
# were reasoned about and which were pasted to unblock a build. This check makes
# that impossible.
#
# It deliberately does NOT run trivy. Scanning belongs in CI, where the images
# exist and the vulnerability database can be fetched; what belongs in the
# harness is the discipline around the waivers, which is checkable offline and
# in a second.

need_file "$MDB_ROOT/.trivyignore.yaml"

# One source of truth. Trivy reads whichever file --ignorefile names, so leaving
# the old flat file behind means two waiver lists, one of them unread and
# drifting -- and the unread one is the one that looks maintained.
if [[ -e "$MDB_ROOT/.trivyignore" ]]; then
    vfail "both .trivyignore and .trivyignore.yaml exist; only the YAML file is
       read, so the flat one is a second waiver list nobody enforces. Delete it."
fi

# CI must actually scan. A waiver file is meaningless if nothing enforces it,
# and this is exactly the pairing that rots -- the scan step gets removed to
# unblock something and the ignore file stays, looking like coverage.
ci="$MDB_ROOT/.github/workflows/ci.yml"
grep -q 'trivy image' "$ci" \
    || vfail "no 'trivy image' scan in .github/workflows/ci.yml; the waiver file implies a scan that does not run"
grep -q 'ignorefile .trivyignore\.yaml' "$ci" \
    || vfail "the CI scan does not pass --ignorefile .trivyignore.yaml; these waivers would be ignored"
vinfo "CI scans images and honours the waiver file"

# scripts/scan promises, in its own header, to be "the same scan CI runs". That
# promise is only true while both read the same waiver file, and it silently
# stopped being true the moment the flat file was replaced: the wrapper went on
# bind-mounting a path that no longer existed, which docker helpfully creates as
# an empty DIRECTORY -- so trivy would have found no waivers and every scan
# would have failed, locally, for a reason that pointed at the CVEs rather than
# at the mount.
grep -q 'ignorefile /\.trivyignore\.yaml' "$MDB_ROOT/scripts/scan" \
    || vfail "scripts/scan does not use --ignorefile /.trivyignore.yaml; it claims to
       be the same scan CI runs, and a different waiver file makes that false"
grep -q '\.trivyignore\.yaml:/\.trivyignore\.yaml' "$MDB_ROOT/scripts/scan" \
    || vfail "scripts/scan does not mount .trivyignore.yaml into the trivy container;
       docker would create an empty directory at that path and every waiver
       would be silently dropped"
vinfo "make scan reads the same waiver file as CI"

# The action was compromised in March 2026: 75 of its 76 version tags were
# force-pushed to steal CI secrets. Referencing it by tag is the exact
# supply-chain risk a scanner exists to reduce.
if grep -q 'aquasecurity/trivy-action@v' "$ci"; then
    vfail "ci.yml uses aquasecurity/trivy-action by tag; that action's tags were
       force-pushed in a 2026 supply-chain attack. Install the pinned binary
       and verify it against the release checksums instead."
fi
vinfo "scanner is a pinned, checksum-verified binary rather than a tagged action"

# -----------------------------------------------------------------------------
# The waiver file itself
# -----------------------------------------------------------------------------
# Parsed with python3 -- already a harness dependency via scripts/check-env --
# but WITHOUT PyYAML, which is absent from the system python on macOS and would
# make this check pass on CI and fail on a laptop.
#
# So it is a hand parser, and that is only safe because it is strict: it knows
# the handful of constructs this file is allowed to use and FAILS on anything
# else rather than skipping it. A parser that silently ignores what it does not
# understand would let a malformed waiver through as if it were absent -- which
# reads as "no waiver" while trivy is still applying one.
# The parser is written out before it is run rather than piped in through a
# heredoc inside $( ). bash 3.2 -- which is what macOS ships, and what half the
# people running this harness have -- mis-parses a heredoc nested in a command
# substitution when the body contains parentheses, and this body is python. It
# fails with a syntax error pointing at a line well past the real one.
py="$(mktemp)"
add_cleanup "rm -f '$py'"
cat >"$py" <<'PY'
import datetime, re, sys

path = sys.argv[1]
MIN_STATEMENT = 40      # a reason, not a label
MAX_HORIZON   = 180     # days; beyond this "expiry" is decoration
WARN_WITHIN   = 30      # days; say so before CI says it for us

entries, errors, section = [], [], None
cur = None
pending = None          # the key whose folded/list continuation we are reading

def flush():
    if cur is not None:
        entries.append(cur)

with open(path) as fh:
    for n, raw in enumerate(fh, 1):
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue

        # Section header, column 0.
        m = re.match(r'^(\w+):\s*$', line)
        if m:
            flush(); cur = None; pending = None
            section = m.group(1)
            if section != "vulnerabilities":
                errors.append(f"line {n}: unsupported section '{section}'; this "
                              f"check only knows how to validate 'vulnerabilities'")
            continue

        # New entry.
        m = re.match(r'^  - id:\s*(\S+)\s*$', line)
        if m:
            flush()
            cur = {"line": n, "id": m.group(1), "purls": [], "statement": "",
                   "expired_at": None}
            pending = None
            continue

        if cur is None:
            errors.append(f"line {n}: content before any '- id:' entry")
            continue

        # Scalar keys.
        m = re.match(r'^    (statement|expired_at|purls):\s*(.*)$', line)
        if m:
            key, val = m.group(1), m.group(2).strip()
            if key == "purls":
                if val:
                    errors.append(f"line {n}: purls must be a list on following lines")
                pending = "purls"
            elif key == "statement":
                if val in (">-", ">", "|-", "|"):
                    pending = "statement"
                else:
                    cur["statement"] = val.strip('"\''); pending = None
            else:
                cur["expired_at"] = val; pending = None
            continue

        # Continuations: a purl list item, or a folded statement line.
        m = re.match(r'^      - "?([^"]+)"?\s*$', line)
        if m and pending == "purls":
            cur["purls"].append(m.group(1)); continue
        m = re.match(r'^      (\S.*)$', line)
        if m and pending == "statement":
            cur["statement"] = (cur["statement"] + " " + m.group(1)).strip(); continue

        errors.append(f"line {n}: unrecognised construct: {line.strip()[:60]!r}")

flush()

if section is None:
    errors.append("no 'vulnerabilities:' section")

today = datetime.date.today()
seen = {}
warnings = []

for e in entries:
    tag = f"{e['id']} (line {e['line']})"

    if not re.match(r'^(CVE-\d{4}-\d+|GHSA-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4})$', e["id"]):
        errors.append(f"{tag}: not a recognisable CVE or GHSA identifier")

    # Same id twice with the same scope is a duplicate; with a different scope
    # it is a deliberate second decision and fine.
    key = (e["id"], tuple(sorted(e["purls"])))
    if key in seen:
        errors.append(f"{tag}: duplicates the entry at line {seen[key]}")
    seen[key] = e["line"]

    if len(e["statement"]) < MIN_STATEMENT:
        errors.append(f"{tag}: statement is {len(e['statement'])} chars; "
                      f"too short at under {MIN_STATEMENT} to be a reason")
    elif "revisit" not in e["statement"].lower():
        errors.append(f"{tag}: statement names no revisit condition; the expiry "
                      f"says WHEN to look again, the statement must say what to look for")

    if not e["expired_at"]:
        errors.append(f"{tag}: no expired_at; a waiver with no end is a decision "
                      f"nobody will re-make")
        continue

    try:
        exp = datetime.date.fromisoformat(str(e["expired_at"]))
    except ValueError:
        errors.append(f"{tag}: expired_at '{e['expired_at']}' is not yyyy-mm-dd")
        continue

    left = (exp - today).days
    if left < 0:
        errors.append(f"{tag}: expired {-left} day(s) ago on {exp}. Trivy has "
                      f"stopped applying it -- re-evaluate and either fix the "
                      f"finding or renew the waiver with current reasoning.")
    elif left > MAX_HORIZON:
        errors.append(f"{tag}: expires in {left} days, beyond the {MAX_HORIZON}-day "
                      f"limit. An expiry that far out is decoration.")
    elif left <= WARN_WITHIN:
        warnings.append(f"{tag}: expires in {left} day(s), on {exp}")

for w in warnings:
    print(f"      soon: {w}", file=sys.stderr)
for x in errors:
    print(f"      {x}", file=sys.stderr)

scoped = sum(1 for e in entries if e["purls"])
print(f"FAIL {len(errors)}" if errors
      else f"OK {len(entries)} {scoped} {len(warnings)}")
PY

# stdout carries a single machine-readable verdict; the detail goes to stderr,
# which the harness already shows, so a failure names every bad entry at once
# rather than one per run.
verdict="$(python3 "$py" "$MDB_ROOT/.trivyignore.yaml")"

case "$verdict" in
    "OK "*)
        read -r _ total scoped soon <<<"$verdict"
        vinfo "$total waiver(s), each with a reason, a revisit condition and an expiry"
        vinfo "$scoped of them scoped to specific packages by purl"
        # An `if`, not `(( soon > 0 )) && vinfo ...`. As the last command in this
        # branch that arithmetic test IS the check's exit status, so zero
        # expiring waivers -- the good case -- would fail the check. Exactly the
        # bug that made the whole harness abort after its first passing check.
        if (( soon > 0 )); then
            vinfo "$soon expire within 30 days; renew or fix before CI does it for you"
        fi
        ;;
    "FAIL "*)
        vfail "${verdict#FAIL } waiver(s) are unscoped, unjustified, expired, or malformed (detail above)"
        ;;
    *)
        vfail "the waiver parser produced no verdict; .trivyignore.yaml may be unreadable"
        ;;
esac
