#!/usr/bin/env python3
"""Check four-language catalogs, placeholders, and production Swift text at CI time."""
from pathlib import Path
import argparse, collections
import re,json
cjk = re.compile(r'[\u3040-\u30ff\u3400-\u9fff]')
def string_at(s,start):
    i=start+1; literal=''; chunks=[]; expressions=[]
    while i<len(s):
        if s[i]=='"': return i+1,chunks+[literal],expressions
        if s[i]=='\\':
            if s[i+1]=='(':
                chunks.append(literal);literal='';j=i+2;depth=1
                while depth:
                    if s[j]=='"':j=string_at(s,j)[0];continue
                    if s[j]=='(':depth+=1
                    if s[j]==')':depth-=1
                    j+=1
                expressions.append(s[i+2:j-1]);i=j;continue
            escapes={'n':'\n','r':'\r','t':'\t','"':'"','\\':'\\','0':'\0'}
            literal+=escapes.get(s[i+1],s[i:i+2]);i+=2;continue
        literal+=s[i];i+=1
    raise ValueError(start)
def strings(s):
    i=0
    while i<len(s):
        if s.startswith('//',i):
            j=s.find('\n',i);i=len(s) if j<0 else j+1;continue
        if s.startswith('/*',i):
            depth=1;i+=2
            while depth:
                if s.startswith('/*',i):depth+=1;i+=2
                elif s.startswith('*/',i):depth-=1;i+=2
                else:i+=1
            continue
        if s[i]=='"':
            end,chunks,args=string_at(s,i)
            key=''.join(c+(f'{{{n}}}' if n<len(args) else '') for n,c in enumerate(chunks))
            yield i,end,key,args
            i=end
        else:i+=1

LANGUAGES = ("en", "zh-Hans", "zh-Hant", "ja")
ROOT = Path(__file__).resolve().parents[1]
ENTRY = re.compile(r'\s*("(?:\\.|[^"\\])*")\s*=\s*("(?:\\.|[^"\\])*")\s*;')
PLACEHOLDER = re.compile(r"\{[0-9]+\}")
PRINTF = re.compile(r"%(?:[0-9]+\$)?[-+0 #]*(?:[0-9]+|\*)?(?:\.[0-9]+)?(?:ll|l|z)?[@diufgse%]")
UI_CONTEXT = re.compile(r"(?:\b(?:label|title|withTitle|message|detail|hint|accessibilityDescription):|\b(?:ActionButton|FraloStyle\.text|FraloStyle\.paragraph|label|hint|field)\(|\.(?:title|stringValue|messageText|informativeText|toolTip)\s*=|\bsetAccessibility(?:Label|Help)\()\s*$")
# Names and file-format identifiers are language independent; new prose belongs in the catalog.
NEUTRAL = {"Fralo", "PNG", "JPEG", "Safari", "Chrome", "Duo", "iPad"}

def read_catalog(path):
    source = path.read_text()
    catalog, errors, cursor = {}, [], 0
    trivia = re.compile(r"(?:\s+|//[^\n]*(?:\n|$)|/\*.*?\*/)+", re.DOTALL)
    while cursor < len(source):
        skip = trivia.match(source, cursor)
        if skip: cursor = skip.end()
        if cursor == len(source): break
        match = ENTRY.match(source, cursor)
        if not match:
            errors.append(f"{path}: invalid catalog syntax")
            break
        key, value = map(json.loads, match.groups())
        if key in catalog: errors.append(f"{path}: duplicate key {key!r}")
        if not value.strip(): errors.append(f"{path}: empty translation for {key!r}")
        catalog[key] = value
        cursor = match.end()
    return catalog, errors

def compare_catalogs(catalogs):
    errors = []
    base = catalogs["zh-Hans"]
    for language, catalog in catalogs.items():
        for key in base.keys() - catalog.keys(): errors.append(f"{language}: missing key {key!r}")
        for key in catalog.keys() - base.keys(): errors.append(f"{language}: extra key {key!r}")
        for key, value in catalog.items():
            if collections.Counter(PLACEHOLDER.findall(key)) != collections.Counter(PLACEHOLDER.findall(value)):
                errors.append(f"{language}: interpolation mismatch for {key!r}")
            if PRINTF.search(key) and PRINTF.findall(key) != PRINTF.findall(value):
                errors.append(f"{language}: printf format mismatch for {key!r}")
    return errors

def check_source(path, source, catalog):
    errors = []
    for start, end, key, arguments in strings(source):
        localized = re.search(r"L10n\.tr\(\s*$", source[max(0,start-50):start])
        location = f"{path}:{source.count(chr(10),0,start)+1}"
        if localized:
            if key not in catalog: errors.append(f"{location}: missing catalog key {key!r}")
        elif cjk.search(key) or (not re.search(r"DispatchQueue\([^)]*$", source[max(0,start-100):start]) and not re.fullmatch(r"(?:\{[0-9]+\}|[0-9\s×%./:–—-]|px)*", key) and UI_CONTEXT.search(source[max(0,start-100):start]) and
                                  re.search(r"[A-Za-z]", key) and key not in NEUTRAL):
            # Developer diagnostics are outside user experience; comments are skipped by the lexer.
            errors.append(f"{location}: user-facing literal must use L10n.tr: {key!r}")
    return errors

def check(root):
    errors, catalogs = [], {}
    for language in LANGUAGES:
        path = root / f"Sources/FraloLocalization/Resources/{language}.lproj/Localizable.strings"
        if not path.is_file(): errors.append(f"Missing language catalog: {language}"); continue
        catalogs[language], issues = read_catalog(path); errors.extend(issues)
    if len(catalogs) != len(LANGUAGES): return errors
    errors.extend(compare_catalogs(catalogs))
    for target in ("FraloApp", "FraloCore", "FraloDesignSystem"):
        # Development-only galleries and fixtures are intentionally outside shipping UI.
        for path in (root / "Sources" / target).glob("*.swift"):
            errors.extend(check_source(path.relative_to(root), path.read_text(), catalogs["en"]))
    return errors

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    errors = check(args.root)
    if errors:
        print("\n".join(errors)); raise SystemExit(1)
    catalog, _ = read_catalog(args.root / "Sources/FraloLocalization/Resources/en.lproj/Localizable.strings")
    print(f"Localization checks passed: {len(catalog)} keys in all {len(LANGUAGES)} languages.")
